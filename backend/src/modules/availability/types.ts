import type { MaldivesDate, WallClock } from '../../core/maldives-time.js';
import type { TimeSlotStatus } from '../../generated/prisma/client.js';

/**
 * **No shape in this file has a field for a phone number**, and nothing in
 * this module reads a `User` row — §1c allows exactly one endpoint in the
 * system to return one and it is `POST /v1/bookings/:id/reveal-contact`.
 * The customer-facing picker below carries a listing id and a set of times;
 * it does not carry the provider at all.
 */

export interface AvailabilityRuleDto {
  id: string;
  /** ISO weekday numbers, 1 = Monday. */
  weekdays: number[];
  startTime: WallClock;
  endTime: WallClock;
  slotDurationMinutes: number;
}

export interface AvailabilityExceptionDto {
  id: string;
  name: string;
  startDate: MaldivesDate;
  endDate: MaldivesDate;
  startTime: WallClock;
  endTime: WallClock;
  slotDurationMinutes: number | null;
}

export interface TimeOffDto {
  id: string;
  name: string;
  startDate: MaldivesDate;
  endDate: MaldivesDate;
}

/**
 * One time on the **provider's** own grid.
 *
 * `status` is the *effective* one, not the column: a slot whose own row says
 * `open` reads `reserved` here when the provider's time is held by a booking
 * on another listing. That is the honest answer, and it is the state
 * `Availability.dc.html`'s reserved sheet already has copy for — "A booking on
 * any of your listings holds your time, so you can never be double-booked."
 */
export interface ProviderSlotDto {
  id: string;
  startsAt: string;
  endsAt: string;
  status: TimeSlotStatus;
  /** True when the status came from a reservation elsewhere rather than this row. */
  heldByAnotherListing: boolean;
}

/** One time on the **customer's** picker. Everything here is open, future and past the lead time. */
export interface OpenSlotDto {
  id: string;
  startsAt: string;
  endsAt: string;
}

export interface ListingAvailabilityDto {
  listingId: string;
  rules: AvailabilityRuleDto[];
  exceptions: AvailabilityExceptionDto[];
  /** The last Maldives day slots currently reach — `Availability.dc.html`'s `horizonDate`. */
  horizonDate: MaldivesDate | null;
  lastGeneratedAt: string | null;
}

export interface OpenSlotsDto {
  listingId: string;
  /**
   * §Phase 4's seeded `Category.minimumLeadTimeMinutes`, read per category and
   * never hardcoded — Cleaning 180, Beauty 120, Fitness 120 today, and
   * admin-editable from §Phase 10b. Returned so the picker can say *why* an
   * early time is missing rather than just omitting it.
   */
  minimumLeadTimeMinutes: number;
  /** The earliest instant anything could be booked: now plus the lead time. */
  bookableFrom: string;
  slots: OpenSlotDto[];
}
