import { BusinessRuleError } from '../../core/errors.js';
import type { Category, VerificationTier } from '../../generated/prisma/client.js';
import { tiersAtOrAbove } from '../providers/visibility.js';

/**
 * §1c's composed emergency rule, written once (Round 17).
 *
 * > Four fields across three entities gate emergency work and no single place
 * > had put them together: `emergencyCapable` and `emergencyMinimumTier` on
 * > the **category**, `isEmergency` on the **listing**, `verificationTier` on
 * > the **provider**.
 *
 * This file is that single place. Three callers reach it — publish, update,
 * and the re-evaluation a tier drop triggers — and none of them may restate
 * the rule, for the same reason §1a keeps visibility in one helper.
 *
 * ## The two things this must never become
 *
 * **Never a boolean `verified` check.** `verificationStatus` is the review
 * state of a pending submission and says nothing about what evidence was
 * accepted; `verificationTier` is what the badge renders and what this gates
 * on. Conflating them was pre-Round-8 language that survived in this very
 * bullet until Round 17 — in the phase that builds the gate.
 *
 * **Never a hardcoded tier.** The bar is `gold` for Electrical and Plumbing
 * and `silver` for AC Repair and Moving, read from the category row. A test
 * that passes against a hardcoded `silver` is not a test of this rule, which
 * is why §Phase 8's Done-when names the silver-electrician case specifically.
 */

/** Everything the rule reads, so a caller cannot accidentally supply half of it. */
export interface EmergencyEligibilityInput {
  category: Pick<Category, 'name' | 'emergencyCapable' | 'emergencyMinimumTier'>;
  providerTier: VerificationTier;
}

export type EmergencyEligibility =
  | { eligible: true }
  | { eligible: false; code: 'EMERGENCY_CATEGORY_NOT_CAPABLE'; message: string }
  | {
      eligible: false;
      code: 'EMERGENCY_TIER_NOT_MET';
      message: string;
      requiredTier: VerificationTier;
      currentTier: VerificationTier;
    };

/**
 * May this provider advertise emergency work on a listing in this category?
 *
 * Returns the reason rather than a boolean because every caller needs it:
 * publish and update turn it into a structured error, and §Phase 9's step 5
 * renders the toggle "disabled with the reason shown" rather than silently
 * absent.
 */
export function emergencyEligibility(input: EmergencyEligibilityInput): EmergencyEligibility {
  const { category, providerTier } = input;

  if (!category.emergencyCapable) {
    return {
      eligible: false,
      code: 'EMERGENCY_CATEGORY_NOT_CAPABLE',
      message: `${category.name} does not offer emergency callouts`,
    };
  }

  // A capable category with no bar set is a misconfigured row, not an open
  // door. Refusing is the safe direction: the alternative admits anyone to
  // 2am work in a stranger's home because a column was left null.
  const required = category.emergencyMinimumTier;
  if (required === null) {
    return {
      eligible: false,
      code: 'EMERGENCY_CATEGORY_NOT_CAPABLE',
      message: `${category.name} does not offer emergency callouts`,
    };
  }

  if (!tiersAtOrAbove(required).includes(providerTier)) {
    return {
      eligible: false,
      code: 'EMERGENCY_TIER_NOT_MET',
      // Names the bar and the current tier, because the provider's next
      // action depends on the gap — and because §Phase 9 renders this text.
      message: `Emergency ${category.name} work needs ${required} verification; this account is ${providerTier}`,
      requiredTier: required,
      currentTier: providerTier,
    };
  }

  return { eligible: true };
}

/** The same rule as a throw, for the write paths. */
export function assertEmergencyAllowed(input: EmergencyEligibilityInput): void {
  const result = emergencyEligibility(input);
  if (result.eligible) return;
  throw new BusinessRuleError(result.code, result.message, [
    { path: 'isEmergency', message: result.message },
  ]);
}

/**
 * §1h / Round 28, and the same shape for the same reason: the callback
 * guarantee is offered **only** on a category whose `callbackEligible` is
 * set, and it is a promise RaajjePro enforces rather than a claim the
 * provider makes — so a listing may not carry it where nothing was fixed and
 * therefore nothing can un-fix.
 *
 * Read from the column, never from a list of six names in this file.
 */
export function assertCallbackAllowed(category: Pick<Category, 'name' | 'callbackEligible'>): void {
  if (category.callbackEligible) return;
  const message = `The callback guarantee is not offered on ${category.name}`;
  throw new BusinessRuleError('CALLBACK_NOT_AVAILABLE_FOR_CATEGORY', message, [
    { path: 'callbackGuaranteeOffered', message },
  ]);
}
