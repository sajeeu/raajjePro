import { z } from 'zod';

import { emailField, otpCodeBody, passwordField, phoneField } from '../auth/schema.js';
import { MAX_USER_PASSWORD_LENGTH } from '../auth/service.js';

export const changePasswordBody = z.object({
  currentPassword: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
  newPassword: passwordField,
});
export const changeEmailRequestBody = z.object({
  newEmail: emailField,
  currentPassword: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
});
export const changeEmailConfirmBody = otpCodeBody;
export const changePhoneBody = phoneField;

/**
 * `PATCH /v1/users/me` (plan §Phase 6).
 *
 * §Phase 6 names the endpoint and no fields. `fullName` is the one
 * user-owned field on this entity that does not already have its own Phase 3
 * endpoint — password, email and phone each carry a credential check or a
 * re-verification step and keep theirs. The bounds match
 * `registerBody.fullName` exactly, because it is the same field: a rule that
 * holds at registration and not afterwards is not a rule.
 *
 * Unknown keys are **stripped, not rejected**, matching
 * `updateOwnProviderBody` (`docs/decisions/17-phase-5-provider-profiles.md`,
 * decision 8). Everything else on `User` is either admin-transitioned
 * (`status`), Phase-3-owned (`email`, `phoneE164`, `passwordHash`) or set by
 * the system (`termsAcceptedAt`, the deletion timestamps, the
 * push-permission pair), so what matters is that naming one of those cannot
 * change it — which the test asserts against the row, not against a status
 * code.
 */
export const updateOwnUserBody = z.object({ fullName: z.string().trim().min(1).max(120) });
