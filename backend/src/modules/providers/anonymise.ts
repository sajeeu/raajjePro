import type { AnonymisationHooks } from '../account/anonymise.js';

/**
 * What account deletion has to erase from a provider profile (invariant 1d,
 * §Phase 3's queued anonymisation).
 *
 * `businessName` is already cleared inside the anonymiser's own transaction,
 * from before this module existed. Phase 5 adds two things that must go with
 * it and would otherwise survive a deletion:
 *
 *   - **the bank details**, which are the most sensitive thing this module
 *     stores, and
 *   - **the bio**, which is free text the provider wrote about themselves and
 *     routinely names them.
 *
 * Deliberately left in place: `verificationTier`, `verificationStatus` and
 * `maldivianOwned`. §1e requires the *decision* and the evidence type to
 * persist after the images are purged — a verification history that vanished
 * with the account would leave a re-registration indistinguishable from a
 * first-time signup. `subscriptionPriceLaari` stays for the same reason
 * Phase 8a needs a billing record to survive: it is money history, not
 * identity. None of the three names a person.
 *
 * Registered as a hook rather than written into the anonymiser, so it runs
 * inside the same transaction: a failure here leaves the user frozen with
 * their profile intact, to be retried, never half-erased.
 */
export function registerProviderAnonymisation(hooks: AnonymisationHooks): void {
  hooks.register('provider-profile', async (tx, userId) => {
    await tx.providerProfile.updateMany({
      where: { userId },
      data: {
        bio: null,
        bankName: null,
        bankAccountName: null,
        bankAccountNumber: null,
        transferInstructions: null,
      },
    });
  });
}
