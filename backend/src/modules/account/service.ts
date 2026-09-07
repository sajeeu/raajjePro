import type { Clock } from '../../core/clock.js';
import { AuthenticationError, BusinessRuleError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';
import { Prisma, type PrismaClient } from '../../generated/prisma/client.js';
import { hashPassword, verifyPassword } from '../admin-auth/crypto.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import type { OtpSendResult, OtpService } from '../auth/otp.js';
import { normalisePhone } from '../auth/phone.js';
import type { UserRepository, UserWithProfile } from '../auth/repository.js';
import { emailInUse, phoneInUse } from '../auth/service.js';

/**
 * Email is the recovery channel (plan §Phase 3, Round 11), and only a verified
 * address can serve as one. Phase 3b's reset flow calls this before sending
 * anything; because its confirmation must not reveal whether an account
 * exists, the throw there becomes a silent non-send. The rule is the same.
 */
export function assertRecoverableByEmail(user: { emailVerifiedAt: Date | null }): void {
  if (user.emailVerifiedAt === null) {
    throw new BusinessRuleError(
      'EMAIL_NOT_VERIFIED',
      'Verify your email address before it can be used to recover your account',
    );
  }
}

/** Account settings (plan §Phase 3): each change re-checks the credential, re-verifies where the plan says, and is audited. */
export class AccountService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      repo: UserRepository;
      otp: OtpService;
      audit: AuditService;
      clock: Clock;
    },
  ) {}

  private async loadOrThrow(userId: string): Promise<UserWithProfile> {
    const user = await this.deps.repo.findById(userId);
    if (user === null) throw new AuthenticationError('UNAUTHENTICATED', 'Sign in to continue');
    return user;
  }

  private async verifyCurrentPassword(user: UserWithProfile, password: string): Promise<void> {
    if (!(await verifyPassword(user.passwordHash, password))) {
      throw new AuthenticationError('INVALID_CREDENTIALS', 'Your current password is not right');
    }
  }

  /** Who may call: the signed-in user, for their own account. Revokes every other device. */
  async changePassword(
    principal: UserPrincipal,
    currentPassword: string,
    newPassword: string,
    meta: RequestMeta,
  ): Promise<void> {
    const user = await this.loadOrThrow(principal.id);
    await this.verifyCurrentPassword(user, currentPassword);
    const passwordHash = await hashPassword(newPassword);
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: user.id },
        data: { passwordHash, passwordChangedAt: now },
      });
      await this.deps.repo.revokeOtherSessions(
        tx,
        user.id,
        principal.sessionId,
        now,
        'password_change',
      );
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: user.id,
        action: 'user.password.changed',
        targetType: 'user',
        targetId: user.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  /** Who may call: the signed-in user. Sends the code to the NEW address; nothing changes until it is confirmed. */
  async requestEmailChange(
    principal: UserPrincipal,
    newEmailInput: string,
    currentPassword: string,
    meta: RequestMeta,
  ): Promise<OtpSendResult & { newEmail: string }> {
    const user = await this.loadOrThrow(principal.id);
    await this.verifyCurrentPassword(user, currentPassword);
    const newEmail = newEmailInput.trim().toLowerCase();
    if (newEmail === user.email)
      throw new BusinessRuleError('EMAIL_UNCHANGED', 'That is already your email address');
    if ((await this.deps.repo.findByEmail(newEmail)) !== null) throw emailInUse();
    const result = await this.deps.otp.send({
      userId: user.id,
      purpose: 'change_email',
      targetEmail: newEmail,
      meta,
    });
    return { ...result, newEmail };
  }

  /** Who may call: the signed-in user, with the code from the new inbox. Uniqueness is re-checked here — the index is the last word. */
  async confirmEmailChange(
    principal: UserPrincipal,
    code: string,
    meta: RequestMeta,
  ): Promise<UserWithProfile> {
    const { targetEmail } = await this.deps.otp.confirm({
      userId: principal.id,
      purpose: 'change_email',
      code,
      meta,
    });
    if ((await this.deps.repo.findByEmail(targetEmail)) !== null) throw emailInUse();
    const now = this.deps.clock();
    try {
      await this.deps.prisma.$transaction(async (tx) => {
        await tx.user.update({
          where: { id: principal.id },
          data: { email: targetEmail, emailVerifiedAt: now },
        });
        await this.deps.repo.revokeOtherSessions(
          tx,
          principal.id,
          principal.sessionId,
          now,
          'email_change',
        );
        await this.deps.otp.invalidateAll(tx, principal.id, 'verify_email', now);
        await this.deps.audit.record(tx, {
          actorType: 'user',
          actorId: principal.id,
          action: 'user.email.changed',
          targetType: 'user',
          targetId: principal.id,
          reason: 'otp_confirmed',
          requestId: meta.requestId,
          ipAddress: meta.ip,
        });
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')
        throw emailInUse();
      throw error;
    }
    return this.loadOrThrow(principal.id);
  }

  /** Who may call: the signed-in user. Format and Bronze-uniqueness re-checked; the number is never verified. */
  async changePhone(
    principal: UserPrincipal,
    phone: { dialCode: string; number: string },
    meta: RequestMeta,
  ): Promise<UserWithProfile> {
    const normalised = normalisePhone(phone);
    if (await this.deps.repo.phoneHeldAtBronzeOrAbove(normalised.e164, principal.id))
      throw phoneInUse();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: principal.id },
        data: { phoneE164: normalised.e164, phoneDialCode: normalised.dialCode },
      });
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.phone.changed',
        targetType: 'user',
        targetId: principal.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
    return this.loadOrThrow(principal.id);
  }
}
