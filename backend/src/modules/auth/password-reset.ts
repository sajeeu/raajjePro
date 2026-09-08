import type { Clock } from '../../core/clock.js';
import { BusinessRuleError } from '../../core/errors.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import { assertRecoverableByEmail } from '../account/service.js';
import { hashPassword } from '../admin-auth/crypto.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import { OTP_RESEND_COOLDOWN_MS, OtpRateLimitedError, type OtpService } from './otp.js';
import type { UserRepository, UserWithProfile } from './repository.js';

/** What the request step tells the client, whether or not anything was sent. */
export interface ResetRequestResult {
  expiresAt: Date;
  resendAvailableAt: Date;
}

/**
 * Forgot password (plan §Phase 3b). The code is Phase 3's emailed six digits
 * under a third `OtpPurpose`, so the send limits, the five-attempt
 * invalidation and the delivery log are the ones already built and tested —
 * only the clock is longer (§Phase 3b's 30 minutes against an OTP's 10).
 *
 * **Nothing here reveals whether an address has an account.** An unknown
 * address, an unverified one, a frozen or anonymised account and a live
 * account under its send limit all return the same body from `request`; all
 * of them fail `verify` and `confirm` with the same `OTP_EXPIRED` a real
 * account with no live code gets. That rule comes from the design brief
 * (`docs/design/sessions/09-identity.md`: "Forgot-password confirmation is
 * identical whether or not the address is registered") and it is the reason
 * several branches below deliberately throw away information.
 */
export class PasswordResetService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      repo: UserRepository;
      otp: OtpService;
      audit: AuditService;
      clock: Clock;
    },
  ) {}

  /**
   * Who may call: anyone, unauthenticated — someone who cannot sign in is by
   * definition not signed in. Rate limited per IP at the route, and per
   * address and per account by the OTP service.
   */
  async request(emailInput: string, meta: RequestMeta): Promise<ResetRequestResult> {
    const now = this.deps.clock();
    const email = emailInput.trim().toLowerCase();
    const silent: ResetRequestResult = {
      expiresAt: new Date(
        now.getTime() + this.deps.otp.expiryMinutesFor('password_reset') * 60_000,
      ),
      resendAvailableAt: new Date(now.getTime() + OTP_RESEND_COOLDOWN_MS),
    };

    const user = await this.deps.repo.findByEmail(email);
    if (user === null || !this.isRecoverable(user)) return silent;

    try {
      const sent = await this.deps.otp.send({
        userId: user.id,
        purpose: 'password_reset',
        targetEmail: user.email,
        meta,
      });
      return { expiresAt: sent.expiresAt, resendAvailableAt: sent.resendAvailableAt };
    } catch (error) {
      // A 429 here would be an existence oracle: only a real account
      // accumulates the rows the limits count, so an unregistered address
      // could never produce one. Swallowing it costs the client nothing real
      // — being over the limit means three codes went to that inbox in the
      // last quarter hour and the newest is still live, so "check your inbox"
      // remains true and the code waiting there still works.
      if (error instanceof OtpRateLimitedError) return silent;
      throw error;
    }
  }

  /**
   * Who may call: anyone holding a code. Checks it **without spending it**, so
   * the set-a-new-password step can open on a code that is known good and the
   * confirm below can still use it. A wrong code costs an attempt.
   */
  async verify(emailInput: string, code: string): Promise<void> {
    const user = await this.lookupOrDeny(emailInput);
    await this.deps.otp.check({ userId: user.id, purpose: 'password_reset', code });
  }

  /**
   * Who may call: anyone holding a code. Sets the password and **revokes every
   * session** — plan §Phase 3b: "the old refresh tokens are all invalid". No
   * tokens come back: the flow returns to Sign In, which is what the artboard
   * does and what a reset triggered by a stolen account should do.
   */
  async confirm(
    emailInput: string,
    code: string,
    newPassword: string,
    meta: RequestMeta,
  ): Promise<void> {
    const user = await this.lookupOrDeny(emailInput);
    // Spend the code first, outside the transaction below. If the write then
    // fails the code is gone and a fresh one is needed — the safe direction
    // for a credential change to fail in.
    await this.deps.otp.confirm({
      userId: user.id,
      purpose: 'password_reset',
      code,
      meta,
    });
    const passwordHash = await hashPassword(newPassword);
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: user.id },
        data: { passwordHash, passwordChangedAt: now },
      });
      await this.deps.repo.revokeAllSessions(tx, user.id, now, 'password_reset');
      // Any other code still in flight — a second request made while the
      // first email was in transit — dies with the one that was used.
      await this.deps.otp.invalidateAll(tx, user.id, 'password_reset', now);
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: user.id,
        action: 'user.password.reset',
        targetType: 'user',
        targetId: user.id,
        reason: 'forgot_password',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  /**
   * Email is the recovery channel and only a verified address can serve as one
   * (`assertRecoverableByEmail`, built in Phase 3). A frozen or anonymised
   * account is not recoverable either — deletion was asked for, and a reset
   * must not walk it back.
   */
  private isRecoverable(user: UserWithProfile): boolean {
    if (user.status !== 'active') return false;
    try {
      assertRecoverableByEmail(user);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * The same error a real account with no live code gets, so a caller cannot
   * tell an unregistered address from a stale one by the response.
   */
  private async lookupOrDeny(emailInput: string): Promise<UserWithProfile> {
    const user = await this.deps.repo.findByEmail(emailInput.trim().toLowerCase());
    if (user === null || !this.isRecoverable(user)) {
      throw new BusinessRuleError('OTP_EXPIRED', 'That code has expired — request a fresh one');
    }
    return user;
  }
}
