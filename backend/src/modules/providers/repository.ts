import { Prisma } from '../../generated/prisma/client.js';
import type { PrismaClient, ProviderProfile } from '../../generated/prisma/client.js';

/** A Prisma client or an open transaction — Phase 3's registration creates a profile inside one. */
type Db = PrismaClient | Prisma.TransactionClient;

/**
 * Idempotent profile creation (§1a, §Phase 5). Called by Phase 6a's
 * onboarding flow and — as a fallback for anyone who reaches the wizard
 * without it — by Phase 8's draft-creation endpoint. Phase 3's
 * provider-variant registration calls it too, inside its transaction.
 *
 * A module-level function rather than a method so all four call sites share
 * one implementation: the `@unique` on `userId` means a second row is
 * impossible, and "called twice returns one row" is the §Phase 5 Done-when.
 *
 * `businessName` is only applied when the row is created. A second call must
 * not quietly overwrite a name the provider has since edited — that is what
 * `PATCH /v1/providers/me` is for.
 *
 * **Concurrency-safe, and it has to be.** Find-then-create loses a race: two
 * parallel calls both see no row and both insert, and the loser's `P2002`
 * against the `@unique` on `user_id` would surface as a 500 — from a double
 * tap on §Phase 6a's Continue, on the flaky connections this plan is built
 * for. So the unique index is treated as the arbiter it is: the loser catches
 * its own violation and re-reads the winner's row. Both callers get the same
 * profile and neither sees an error, which is what "idempotent" has to mean
 * here.
 */
export async function getOrCreateProviderProfile(
  db: Db,
  userId: string,
  businessName?: string,
): Promise<ProviderProfile> {
  const existing = await db.providerProfile.findUnique({ where: { userId } });
  if (existing !== null) return existing;
  try {
    return await db.providerProfile.create({
      data: { userId, ...(businessName === undefined ? {} : { businessName }) },
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      const winner = await db.providerProfile.findUnique({ where: { userId } });
      if (winner !== null) return winner;
    }
    throw error;
  }
}

/**
 * Provider profile reads and writes.
 *
 * Nothing here filters on a visibility flag, because there is none — §1a's
 * derived rule lives in `ProviderVisibility.findVisibleProviders` and every
 * public consumer goes through that. These methods are the owner's-own and
 * by-id reads, whose authorization is the caller's job and is stated at each
 * route.
 */
export class ProviderRepository {
  constructor(private readonly prisma: PrismaClient) {}

  getOrCreate(userId: string, businessName?: string): Promise<ProviderProfile> {
    return getOrCreateProviderProfile(this.prisma, userId, businessName);
  }

  findByUserId(userId: string): Promise<ProviderProfile | null> {
    return this.prisma.providerProfile.findUnique({ where: { userId } });
  }

  findById(id: string): Promise<ProviderProfile | null> {
    return this.prisma.providerProfile.findUnique({ where: { id } });
  }

  /** Takes the caller's transaction where there is one, so an audit entry commits with the change it describes. */
  update(
    userId: string,
    data: Prisma.ProviderProfileUpdateInput,
    db: Db = this.prisma,
  ): Promise<ProviderProfile> {
    return db.providerProfile.update({ where: { userId }, data });
  }

  /** Runs `fn` inside a transaction so the row change and its audit entry land together. */
  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }
}
