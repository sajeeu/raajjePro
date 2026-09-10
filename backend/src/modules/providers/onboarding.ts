import type { ProviderProfile } from '../../generated/prisma/client.js';

/**
 * "Has this account completed §Phase 6a's onboarding?" — derived, never
 * stored.
 *
 * §Phase 6a's Done-when ends on it: *"a provider who already completed
 * onboarding never sees it again, going straight to the dashboard or a
 * resumed draft instead"*, and its resume rule is the same question read the
 * other way — *"a provider who abandons onboarding after step 1 or 2 (backs
 * out, closes the app) and returns later resumes from wherever they left
 * off"*. Both need one answer, and it has to be the server's (invariant 4):
 * §Phase 6's role switcher routes on it and so does the onboarding screen
 * itself, and two clients deriving it separately is two rules.
 *
 * **Nothing stores it**, for the same reason §1a stores no visibility flag:
 * a stored "onboarded" boolean is a copy of these fields that drifts the
 * first time one of them is cleared. This function is the only definition,
 * and `information_schema` is asserted to hold no column that looks like one.
 *
 * ### What it counts, and why each one
 *
 * Exactly what §Phase 6a's three steps collect — step 1 is explanatory and
 * persists nothing, so there is nothing here for it:
 *
 *   - **`businessName` and `providerType`** — step 2's two required "About
 *     you" fields. `providerType` in particular cannot be guessed: §1e reads
 *     it to decide whether Gold review asks for personal ID or a business
 *     registration, so null means *not yet asked*, never a default.
 *   - **The three bank fields** — step 2's "Getting paid", all required
 *     there. §1b never moves money for a booking, so a customer paying this
 *     provider needs the destination account to exist; a listing published
 *     without one is a service nobody can pay for.
 *   - **At least one default service area** — step 3. Its CTA is disabled
 *     with none chosen, so a provider who stopped here has not finished, and
 *     this is the field that tells that state apart from a finished one.
 *   - **A verified email** — §Phase 5: *"required to complete Phase 6a's
 *     provider onboarding"*, and §Phase 6a: *"Unverified blocks Continue with
 *     its own message, since booking notifications go there."*
 *
 * ### Why the email gate lives here rather than on the endpoints
 *
 * The obvious alternative was `requireEmailVerified` on
 * `PATCH /v1/providers/me`. It was rejected: that endpoint is also Phase 10a's
 * billing surface and every later provider-profile edit, and §1a says
 * dashboard access is never gated — a provider editing their own bio is not
 * booking, enquiring or messaging, which is what §1c's stricter guard exists
 * for. So the rule is enforced where the rule actually is: an unverified
 * account can write its own profile fields, and is **not onboarded** until
 * the address those booking notifications go to has been confirmed. An API
 * client that skips §Phase 6a's UI reaches the same answer the UI gives.
 *
 * Once true this cannot silently go false: `POST /v1/users/me/change-email/confirm`
 * writes the new address and `emailVerifiedAt` together, so a verified
 * account never passes back through an unverified state and no provider is
 * dragged back into onboarding by changing their email.
 *
 * `bio`, `yearsOfExperience` and the photo are deliberately absent — §Phase 6a
 * marks the introduction optional and there is no photo column to check
 * (media upload is §Phase 8's).
 */
export interface OnboardingInputs {
  /** Null where the account has no provider profile at all — not a provider yet. */
  profile: ProviderProfile | null;
  /** Current (not soft-deleted) `ProviderServiceArea` rows for that profile. */
  serviceAreaCount: number;
  /** `User.emailVerifiedAt !== null`. */
  emailVerified: boolean;
}

export function isOnboardingComplete({
  profile,
  serviceAreaCount,
  emailVerified,
}: OnboardingInputs): boolean {
  if (profile === null) return false;
  if (!emailVerified) return false;
  if (serviceAreaCount < 1) return false;
  return ONBOARDING_PROFILE_FIELDS.every((field) => isFilled(profile[field]));
}

/**
 * The profile columns §Phase 6a's step 2 marks required. Kept as a list so a
 * test can assert each one individually — a completeness check that passed
 * with the destination account missing would be the expensive kind of wrong.
 */
export const ONBOARDING_PROFILE_FIELDS = [
  'businessName',
  'providerType',
  'bankName',
  'bankAccountName',
  'bankAccountNumber',
] as const satisfies readonly (keyof ProviderProfile)[];

/** A whitespace-only business name is not a business name. */
function isFilled(value: unknown): boolean {
  return typeof value === 'string'
    ? value.trim().length > 0
    : value !== null && value !== undefined;
}
