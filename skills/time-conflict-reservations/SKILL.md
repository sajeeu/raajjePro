---
name: time-conflict-reservations
description: Use when working on time slots, reservations, availability rules, booking creation, quotes, or reschedule. Triggers on mentions of slot, reservation, availability, double-booking, or scheduling.
---
# Time-Conflict Prevention

THE CONSTRAINT — provider-scoped and range-based:
`EXCLUDE USING gist (providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`

A `UNIQUE` index on `(providerId, listingId, startsAt)` is WRONG twice over: it permits one provider being booked three times at 10:00 across three different listings, and it detects nothing about overlapping DURATIONS. If you see it referenced anywhere, replace it. Application code must not be able to override the constraint.

- Slot reservation happens INSIDE the booking-creation transaction. A race resolves to exactly one winner.
- Reservations are FIRM (a booked slot) or PROVISIONAL (a quote offered, expiring with its approval window). QUOTE AND APPROVAL WINDOWS ARE PER-CATEGORY (Round 15) from `quoteExpiryMinutes` / `quoteApprovalMinutes` — 120/240 minutes for Plumbing, Electrical, AC Repair and Computer; 1440/4320 for Photography, Gardening, Moving, Events and Boat Charter. Never hardcode 24h/72h. Offering a quote MUST create a provisional reservation — otherwise the provider can sell that time in the interim and the customer's approval fails on a constraint violation after they already agreed a price.
- Releasing a reservation (cancel, decline, timeout, expiry) returns the slot to `open` atomically.
- Reschedule frees the old reservation in the SAME transaction that takes the new one — never leave the provider double-blocked or double-free.
- The customer-facing picker filters on `startsAt > now()` PLUS the category's `minimumLeadTimeMinutes`, IN ADDITION to `status = 'open'`. This is a QUERY-TIME guarantee, not a dependency on the nightly regeneration job having run.
- Slot generation is idempotent across a 60-day rolling window. Re-running changes nothing.
- Emergency bookings take NO calendar reservation — an emergency interrupts the published calendar rather than blocking it.
