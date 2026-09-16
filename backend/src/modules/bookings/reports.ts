import { BusinessRuleError } from '../../core/errors.js';
import type { ReportReason, ReportTargetType } from '../../generated/prisma/enums.js';

/**
 * §Phase 22's `reason` enumeration, **scoped by `targetType`** (Round 17).
 *
 * The Prisma enum is flat because a database enum cannot express the scoping;
 * this map is the scoping, and it is the only thing that decides whether a
 * reason is allowed on a target. §Phase 22 extends the map when it takes over
 * the other five target types — it does not rewrite it.
 *
 * §Phase 17.1 files against `booking` alone.
 */
export const REASONS_BY_TARGET: Record<ReportTargetType, readonly ReportReason[]> = {
  listing: [
    'misleading_description',
    'wrong_category',
    'contact_details_in_listing',
    'prohibited_service',
    'not_the_real_provider',
  ],
  review: ['fake_review', 'abusive_language', 'not_about_this_service'],
  user: ['harassment', 'impersonation', 'fraud', 'repeated_no_show'],
  booking: ['work_not_done', 'price_changed_on_site', 'unsafe_work', 'payment_dispute'],
  message: ['harassment', 'contact_solicitation', 'spam', 'abusive_content'],
  photo: ['not_own_work', 'inappropriate_content', 'contains_contact_details'],
};

/** The four a booking dispute may be filed under. Exported so the Zod schema reads one list. */
export const BOOKING_REPORT_REASONS = REASONS_BY_TARGET.booking;

export class ReportReasonNotAllowedError extends BusinessRuleError {
  constructor(targetType: ReportTargetType, reason: ReportReason) {
    super('REPORT_REASON_NOT_ALLOWED', `That reason does not apply to a ${targetType}`, {
      targetType,
      reason,
    });
  }
}

export function assertReasonAllowed(targetType: ReportTargetType, reason: ReportReason): void {
  if (!REASONS_BY_TARGET[targetType].includes(reason)) {
    throw new ReportReasonNotAllowedError(targetType, reason);
  }
}
