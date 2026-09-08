import type { UserSession } from '../../generated/prisma/client.js';
import type { UserWithProfile } from './repository.js';

export interface UserDto {
  id: string;
  fullName: string;
  email: string;
  emailVerified: boolean;
  /** Own-read only. Split back into the parts the client collected. */
  phone: { dialCode: string; number: string } | null;
  status: 'active' | 'frozen' | 'anonymised';
  deletionDeadlineAt: string | null;
  isProvider: boolean;
  createdAt: string;
}

/**
 * The one mapping every route uses for a user. Structural exclusion
 * (backend/CLAUDE.md): the hash, tokens and session ids are simply not
 * fields here. The phone is present because the only consumer of this DTO is
 * the account holder — there is no other-user read in Phase 3.
 */
export function userDto(user: UserWithProfile): UserDto {
  const phone =
    user.phoneE164 === null || user.phoneDialCode === null
      ? null
      : { dialCode: user.phoneDialCode, number: user.phoneE164.slice(user.phoneDialCode.length) };
  return {
    id: user.id,
    fullName: user.fullName,
    email: user.email,
    emailVerified: user.emailVerifiedAt !== null,
    phone,
    status: user.status,
    deletionDeadlineAt: user.deletionDeadlineAt?.toISOString() ?? null,
    isProvider: user.providerProfile !== null,
    createdAt: user.createdAt.toISOString(),
  };
}

/** Never the IP, never the user agent, never a token hash. */
export function sessionDto(session: UserSession, currentSessionId: string) {
  return {
    id: session.id,
    deviceName: session.deviceName,
    createdAt: session.createdAt.toISOString(),
    lastSeenAt: session.lastSeenAt.toISOString(),
    current: session.id === currentSessionId,
  };
}
