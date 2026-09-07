import { randomBytes } from 'node:crypto';

import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';
import { hashPassword } from '../admin-auth/crypto.js';
import type { AuditService } from '../audit/service.js';
import type { UserRepository } from '../auth/repository.js';

/** Phase 17 supplies the real one; until then nothing blocks. */
export interface DeletionBlocker {
  hasOpenBookings(userId: string): Promise<boolean>;
}
export const neverBlocks: DeletionBlocker = { hasOpenBookings: () => Promise.resolve(false) };

export type AnonymisationHook = (
  tx: Prisma.TransactionClient,
  userId: string,
  now: Date,
) => Promise<void>;

/**
 * Later phases register what anonymisation must also do — Phase 10a/23 purge
 * identity documents, 10b deletes internal notes, 11 strips review
 * attribution, 18 purges messages. Every hook runs inside the same
 * transaction as the user row change: a failing hook leaves the user frozen
 * and untouched, to be retried on the next run.
 */
export class AnonymisationHooks {
  private readonly hooks = new Map<string, AnonymisationHook>();
  register(name: string, hook: AnonymisationHook): void {
    if (this.hooks.has(name)) throw new Error(`anonymisation hook already registered: ${name}`);
    this.hooks.set(name, hook);
  }
  list(): [string, AnonymisationHook][] {
    return [...this.hooks.entries()];
  }
}

export type AnonymisationReason = 'bookings_terminal' | 'deletion_backstop';

export class AccountAnonymiser {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      repo: UserRepository;
      audit: AuditService;
      hooks: AnonymisationHooks;
    },
  ) {}

  /** Frozen users whose deadline has passed, or who have no open bookings. */
  async findDue(
    now: Date,
    blocker: DeletionBlocker,
  ): Promise<{ userId: string; reason: AnonymisationReason }[]> {
    const frozen = await this.deps.prisma.user.findMany({
      where: { status: 'frozen' },
      select: { id: true, deletionDeadlineAt: true },
      orderBy: { deletionRequestedAt: 'asc' },
    });
    const due: { userId: string; reason: AnonymisationReason }[] = [];
    for (const user of frozen) {
      if (user.deletionDeadlineAt !== null && user.deletionDeadlineAt.getTime() <= now.getTime()) {
        due.push({ userId: user.id, reason: 'deletion_backstop' });
      } else if (!(await blocker.hasOpenBookings(user.id))) {
        due.push({ userId: user.id, reason: 'bookings_terminal' });
      }
    }
    return due;
  }

  async runDue(
    now: Date,
    blocker: DeletionBlocker,
  ): Promise<{ processed: number; failed: number }> {
    let processed = 0;
    let failed = 0;
    for (const { userId, reason } of await this.findDue(now, blocker)) {
      try {
        await this.anonymise(userId, now, reason);
        processed += 1;
      } catch {
        failed += 1;
      }
    }
    return { processed, failed };
  }

  /** One user, one transaction: identity replaced, sessions revoked, codes invalidated, hooks run, audited. */
  async anonymise(userId: string, now: Date, reason: AnonymisationReason): Promise<void> {
    const passwordHash = await hashPassword(randomBytes(32).toString('hex'));
    await this.deps.prisma.$transaction(async (tx) => {
      const changed = await tx.user.updateMany({
        where: { id: userId, status: 'frozen' },
        data: {
          fullName: 'Deleted user',
          email: `deleted-${userId}@anonymised.raajjepro.invalid`,
          phoneE164: null,
          phoneDialCode: null,
          passwordHash,
          emailVerifiedAt: null,
          status: 'anonymised',
          anonymisedAt: now,
        },
      });
      if (changed.count === 0) return; // raced with another run, or no longer frozen
      await tx.providerProfile.updateMany({ where: { userId }, data: { businessName: null } });
      await this.deps.repo.revokeAllSessions(tx, userId, now, 'anonymised');
      await tx.emailOtp.updateMany({
        where: { userId, consumedAt: null, invalidatedAt: null },
        data: { invalidatedAt: now },
      });
      for (const [, hook] of this.deps.hooks.list()) await hook(tx, userId, now);
      await this.deps.audit.record(tx, {
        actorType: 'system',
        action: 'user.anonymised',
        targetType: 'user',
        targetId: userId,
        reason,
        metadata: { hooksRun: this.deps.hooks.list().length },
      });
    });
  }
}
