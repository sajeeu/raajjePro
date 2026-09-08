import { createHash, randomInt, randomUUID } from 'node:crypto';

import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import { AppError, BusinessRuleError } from '../../core/errors.js';
import type { OtpPurpose, PrismaClient } from '../../generated/prisma/client.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { Db } from '../audit/types.js';
import type { EmailSender } from '../email/types.js';

export const OTP_ADDRESS_LIMIT = 3;
export const OTP_ADDRESS_WINDOW_MS = 15 * 60_000;
export const OTP_ACCOUNT_LIMIT = 5;
export const OTP_ACCOUNT_WINDOW_MS = 60 * 60_000;
export const OTP_ATTEMPT_LIMIT = 5;
/** What the client shows as its resend countdown. Advisory — the two limits above are the rule. */
export const OTP_RESEND_COOLDOWN_MS = 60_000;

export interface OtpSendResult {
  status: 'sent' | 'suppressed' | 'failed';
  expiresAt: Date;
  resendAvailableAt: Date;
}

/** 429 with the seconds remaining, so the UI shows a real countdown (plan §Phase 3). */
export class OtpRateLimitedError extends AppError {
  constructor(
    public readonly retryAfterSeconds: number,
    limit: 'address' | 'account',
  ) {
    super(429, 'OTP_RATE_LIMITED', 'Too many codes requested — wait before asking for another', {
      retryAfterSeconds,
      limit,
    });
  }
}

function codeHashFor(id: string, code: string): string {
  return createHash('sha256').update(`${id}|${code}`).digest('hex');
}

/**
 * The email itself. A reset code is not a verification code — it opens the
 * account rather than confirming an address — so it says so, and it tells a
 * recipient who did not ask for it what to do (plan §Phase 3b).
 */
function copyFor(
  purpose: OtpPurpose,
  code: string,
  expiryMinutes: number,
): { subject: string; text: string } {
  if (purpose === 'password_reset') {
    return {
      subject: 'Your RaajjePro password reset code',
      text: [
        `Your RaajjePro password reset code is ${code}.`,
        '',
        `It expires in ${String(expiryMinutes)} minutes, and it can only be used once.`,
        'Entering it lets you set a new password, which signs you out on every device.',
        '',
        "If you didn't ask to reset your password, you can ignore this email — your",
        'password stays as it is and nothing changes without this code.',
      ].join('\n'),
    };
  }
  return {
    subject: 'Your RaajjePro verification code',
    text: [
      `Your RaajjePro verification code is ${code}.`,
      '',
      `It expires in ${String(expiryMinutes)} minutes.`,
      "If you didn't ask for this code, you can ignore this email — nothing changes without it.",
    ].join('\n'),
  };
}

/**
 * Emailed six-digit codes (plan §Phase 3). Both send limits are enforced here,
 * not by the route tier — they key on the address and the account, not the
 * IP — inside a transaction that locks the user row, so concurrent sends
 * cannot slip a fourth one through. Every live code for a purpose stays valid
 * until it expires; five wrong attempts invalidate all of them.
 */
export class OtpService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      email: EmailSender;
      clock: Clock;
      config: Config;
    },
  ) {}

  /** Who may call: the auth and account services, for the signed-in user they are acting for. */
  async send(input: {
    userId: string;
    purpose: OtpPurpose;
    targetEmail: string;
    meta: RequestMeta;
  }): Promise<OtpSendResult> {
    const now = this.deps.clock();
    const targetEmail = input.targetEmail.trim().toLowerCase();
    const id = randomUUID();
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const expiryMinutes = this.expiryMinutesFor(input.purpose);
    const expiresAt = new Date(now.getTime() + expiryMinutes * 60_000);

    await this.deps.prisma.$transaction(async (tx) => {
      // Serialise per user: the already-verified check and the two counts
      // below and the insert must not interleave with another send for the
      // same account. Raw SQL because Prisma has no row lock; "app_user" is
      // the mapped table name.
      const [locked] = await tx.$queryRaw<
        { email_verified_at: Date | null }[]
      >`SELECT email_verified_at FROM app_user WHERE id = ${input.userId}::uuid FOR UPDATE`;
      // Plan §4: for verify_email specifically, an already-verified account
      // is refused before either rate-limit count runs — checked inside the
      // same locked section so it cannot race a concurrent confirm.
      if (input.purpose === 'verify_email' && locked?.email_verified_at != null) {
        throw new BusinessRuleError(
          'EMAIL_ALREADY_VERIFIED',
          'This email address is already verified',
        );
      }
      await this.assertUnderLimits(tx, input.userId, targetEmail, now);
      await tx.emailOtp.create({
        data: {
          id,
          userId: input.userId,
          purpose: input.purpose,
          targetEmail,
          codeHash: codeHashFor(id, code),
          expiresAt,
          createdAt: now,
        },
      });
    });

    const outcome = await this.deps.email.send({
      channel: 'otp',
      to: targetEmail,
      recipientUserId: input.userId,
      ...copyFor(input.purpose, code, expiryMinutes),
    });
    await this.deps.prisma.emailOtp.update({
      where: { id },
      data: { emailMessageId: outcome.messageId },
    });
    return {
      status: outcome.status,
      expiresAt,
      resendAvailableAt: new Date(now.getTime() + OTP_RESEND_COOLDOWN_MS),
    };
  }

  /**
   * Who may call: the auth and account services, for the signed-in user.
   * Returns the address the matched code was sent to — the caller decides
   * what verifying it means (mark verified, or switch the account's email).
   */
  async confirm(input: {
    userId: string;
    purpose: OtpPurpose;
    code: string;
    meta: RequestMeta;
  }): Promise<{ targetEmail: string }> {
    const now = this.deps.clock();
    const match = await this.match(input.userId, input.purpose, input.code, now);
    const consumed = await this.deps.prisma.emailOtp.updateMany({
      where: { id: match.id, consumedAt: null },
      data: { consumedAt: now },
    });
    if (consumed.count === 0) {
      throw new BusinessRuleError(
        'OTP_EXPIRED',
        'That code was already used — request a fresh one',
      );
    }
    return { targetEmail: match.targetEmail };
  }

  /**
   * Who may call: Phase 3b's reset flow, before it opens the set-a-new-password
   * step. Identical to `confirm` except that a hit is **not** consumed — the
   * code is spent by the confirm that follows, so a user who reaches the
   * password screen and abandons it can come back with the same code. A miss
   * costs an attempt exactly as `confirm` does, so five wrong guesses still
   * invalidate every live code whichever call made them.
   */
  async check(input: { userId: string; purpose: OtpPurpose; code: string }): Promise<void> {
    await this.match(input.userId, input.purpose, input.code, this.deps.clock());
  }

  /** The shared matcher. Throws the OTP_* business errors; never returns a miss. */
  private async match(
    userId: string,
    purpose: OtpPurpose,
    codeInput: string,
    now: Date,
  ): Promise<{ id: string; targetEmail: string }> {
    const code = codeInput.trim();
    const live = await this.deps.prisma.emailOtp.findMany({
      where: {
        userId,
        purpose,
        consumedAt: null,
        invalidatedAt: null,
        expiresAt: { gt: now },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (live.length === 0) {
      throw new BusinessRuleError('OTP_EXPIRED', 'That code has expired — request a fresh one');
    }
    const match = live.find((row) => row.codeHash === codeHashFor(row.id, code));
    if (match !== undefined) return { id: match.id, targetEmail: match.targetEmail };
    // Wrong: one attempt against every live code, since we cannot know which
    // one was meant. The fifth failure invalidates them all.
    const ids = live.map((row) => row.id);
    await this.deps.prisma.emailOtp.updateMany({
      where: { id: { in: ids } },
      data: { attempts: { increment: 1 } },
    });
    const attempts = Math.max(...live.map((row) => row.attempts)) + 1;
    if (attempts >= OTP_ATTEMPT_LIMIT) {
      await this.invalidateAll(this.deps.prisma, userId, purpose, now);
      throw new BusinessRuleError(
        'OTP_INVALIDATED',
        'That code has been invalidated after 5 incorrect attempts — request a fresh one',
      );
    }
    throw new BusinessRuleError('OTP_INCORRECT', "That code isn't right", {
      attemptsRemaining: OTP_ATTEMPT_LIMIT - attempts,
    });
  }

  /** The reset code runs on its own, longer clock (plan §Phase 3b; `Forgot Password.dc.html` says 30 minutes). */
  expiryMinutesFor(purpose: OtpPurpose): number {
    return purpose === 'password_reset'
      ? this.deps.config.auth.passwordResetExpiryMinutes
      : this.deps.config.auth.otpExpiryMinutes;
  }

  invalidateAll(
    db: Db,
    userId: string,
    purpose: OtpPurpose,
    now: Date,
  ): Promise<{ count: number }> {
    return db.emailOtp.updateMany({
      where: { userId, purpose, consumedAt: null, invalidatedAt: null },
      data: { invalidatedAt: now },
    });
  }

  private async assertUnderLimits(
    db: Db,
    userId: string,
    targetEmail: string,
    now: Date,
  ): Promise<void> {
    const [byAddress, byAccount] = await Promise.all([
      db.emailOtp.findMany({
        where: { targetEmail, createdAt: { gt: new Date(now.getTime() - OTP_ADDRESS_WINDOW_MS) } },
        orderBy: { createdAt: 'asc' },
        select: { createdAt: true },
      }),
      db.emailOtp.findMany({
        where: { userId, createdAt: { gt: new Date(now.getTime() - OTP_ACCOUNT_WINDOW_MS) } },
        orderBy: { createdAt: 'asc' },
        select: { createdAt: true },
      }),
    ]);
    const waits: { seconds: number; limit: 'address' | 'account' }[] = [];
    const oldestAddress = byAddress[0];
    if (byAddress.length >= OTP_ADDRESS_LIMIT && oldestAddress !== undefined) {
      waits.push({
        seconds: Math.ceil(
          (oldestAddress.createdAt.getTime() + OTP_ADDRESS_WINDOW_MS - now.getTime()) / 1000,
        ),
        limit: 'address',
      });
    }
    const oldestAccount = byAccount[0];
    if (byAccount.length >= OTP_ACCOUNT_LIMIT && oldestAccount !== undefined) {
      waits.push({
        seconds: Math.ceil(
          (oldestAccount.createdAt.getTime() + OTP_ACCOUNT_WINDOW_MS - now.getTime()) / 1000,
        ),
        limit: 'account',
      });
    }
    const worst = waits.sort((a, b) => b.seconds - a.seconds)[0];
    if (worst !== undefined) throw new OtpRateLimitedError(Math.max(worst.seconds, 1), worst.limit);
  }
}
