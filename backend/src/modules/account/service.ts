import type { Clock } from '../../core/clock.js';
import { AuthenticationError, BusinessRuleError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';
import { Prisma, type PrismaClient } from '../../generated/prisma/client.js';
import { hashPassword, verifyPassword } from '../admin-auth/crypto.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import { userDto } from '../auth/dto.js';
import { profileSummaryDto, type ProfileSummaryDto } from './dto.js';
import { providerOwnExport } from '../providers/types.js';
import type { OtpSendResult, OtpService } from '../auth/otp.js';
import { normalisePhone } from '../auth/phone.js';
import type { UserRepository, UserWithProfile } from '../auth/repository.js';
import { emailInUse, phoneInUse } from '../auth/service.js';
import type { ExportContributors } from './export.js';

/** Queued-deletion backstop (plan §Phase 3, Round 9): anonymisation runs at this many days regardless of open bookings. */
export const DELETION_BACKSTOP_DAYS = 30;

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
      exportContributors: ExportContributors;
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

  /**
   * Who may call: the signed-in user, about themselves. The Profile screen's
   * one read (plan §Phase 6).
   *
   * No email-verification guard: §1c's stricter `requireEmailVerified` gates
   * booking, enquiry and messaging, and reading your own profile is none of
   * those. A frozen account reads normally too — it can still see who it is
   * while its deletion is queued.
   */
  async profileSummary(userId: string): Promise<ProfileSummaryDto> {
    return profileSummaryDto(await this.loadOrThrow(userId));
  }

  /**
   * Who may call: the signed-in user, for their own account (plan §Phase 6,
   * `PATCH /v1/users/me`).
   *
   * The route also carries `requireActiveAccount`, on the same reasoning
   * §Phase 5's `PATCH /v1/providers/me` does: a frozen account is queued for
   * anonymisation, which replaces the name with a placeholder, so rewriting
   * the name it is about to erase is exactly the thing "starts nothing new"
   * means.
   *
   * Audited as `user.name.changed`, with no value in the entry — a name is a
   * PII value and the audit log takes IDs, enums and counts only.
   */
  async updateOwnUser(
    principal: UserPrincipal,
    body: { fullName: string },
    meta: RequestMeta,
  ): Promise<UserWithProfile> {
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: principal.id }, data: { fullName: body.fullName } });
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.name.changed',
        targetType: 'user',
        targetId: principal.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
    return this.loadOrThrow(principal.id);
  }

  /** Who may call: the signed-in user, for their own data. Own data — so the phone is present; nothing about anyone else ever is. */
  async exportData(userId: string): Promise<Record<string, unknown>> {
    const user = await this.loadOrThrow(userId);
    const sessions = await this.deps.repo.listLiveSessions(userId);
    const dto = userDto(user);
    return {
      exportedAt: this.deps.clock().toISOString(),
      account: {
        id: user.id,
        fullName: user.fullName,
        email: user.email,
        emailVerifiedAt: user.emailVerifiedAt?.toISOString() ?? null,
        phone: dto.phone,
        status: user.status,
        createdAt: user.createdAt.toISOString(),
        termsAcceptedAt: user.termsAcceptedAt.toISOString(),
      },
      // Phase 5 extended this section from two fields to the whole profile.
      // Mapped by the providers module so the export and `GET
      // /v1/providers/me` cannot drift apart, and own-data like the phone
      // above — a provider's own bank details are theirs to take with them.
      providerProfile:
        user.providerProfile === null ? null : providerOwnExport(user.providerProfile),
      sessions: sessions.map((s) => ({
        deviceName: s.deviceName,
        createdAt: s.createdAt.toISOString(),
        lastSeenAt: s.lastSeenAt.toISOString(),
      })),
      ...(await this.deps.exportContributors.collectAll(userId)),
    };
  }

  /**
   * Who may call: the signed-in user. Queued, never refused (plan §Phase 3,
   * Round 9): accepted immediately, frozen at once, anonymised by the job when
   * open bookings terminate or at the 30-day backstop. A repeat returns the
   * original dates. Sessions stay live — open bookings still need chat.
   */
  async requestDeletion(
    principal: UserPrincipal,
    meta: RequestMeta,
  ): Promise<{ status: 'frozen'; deletionRequestedAt: Date; deletionDeadlineAt: Date }> {
    const now = this.deps.clock();
    const deadline = new Date(now.getTime() + DELETION_BACKSTOP_DAYS * 86_400_000);
    const result = await this.deps.prisma.$transaction(async (tx) => {
      const frozen = await tx.user.updateMany({
        where: { id: principal.id, status: 'active' },
        data: { status: 'frozen', deletionRequestedAt: now, deletionDeadlineAt: deadline },
      });
      if (frozen.count === 1) {
        await this.deps.audit.record(tx, {
          actorType: 'user',
          actorId: principal.id,
          action: 'user.deletion.requested',
          targetType: 'user',
          targetId: principal.id,
          reason: 'user_initiated',
          requestId: meta.requestId,
          ipAddress: meta.ip,
        });
      }
      return tx.user.findUniqueOrThrow({ where: { id: principal.id } });
    });
    if (result.deletionRequestedAt === null || result.deletionDeadlineAt === null) {
      throw new Error('frozen user without deletion dates');
    }
    return {
      status: 'frozen',
      deletionRequestedAt: result.deletionRequestedAt,
      deletionDeadlineAt: result.deletionDeadlineAt,
    };
  }
}
