---
name: provider-conduct-and-reviews
description: Use when working on reviews, ratings, review tags, provider reputation, conduct metrics, search ranking by provider quality, or any provider-facing performance display. Triggers on mentions of rating, review, tags, cancel rate, no-show, on-time, price adherence, response time, reliability, or provider badges.
---
# Provider Conduct & Reviews

Two separate axes. Star ratings measure whether a customer LIKED the job. Conduct measures whether the provider turned up, honoured the price they quoted, and answered at all — computed from booking outcomes, never from opinions. Do not merge them into one score.

## Conduct metrics (§1f) — computed in Phase 11, displayed in Phases 5 and 12

Completion rate, cancellation rate, no-show rate, on-time rate, price adherence, acceptance rate, median response time. All derived from booking terminal transitions over a ROLLING 90-DAY window, recomputed on transition rather than on read.

- CUSTOMER cancellations never count against a provider. Only provider-initiated ones after `accepted`.
- Price adherence compares `finalAmount` to `agreedAmount`. An increase WITHOUT an accepted amendment is a failure — see the booking-payment-attestation skill for the locked agreement.
- Acceptance rate counts EXPLICIT responses only; timeouts feed response rate, not acceptance.
- On-time applies to slot and request modes only. Emergency has no `scheduledFor` to be late against.

## Display rules — these are invariants, not preferences

- **NEVER generate editorial labels.** "Prone to cancel", "Price hiking", "Unreliable" and every euphemism for them were considered in Round 15 and REJECTED. They are automated public accusations computed from thin data, in a market small enough that everyone knows everyone — a wrong one is somebody's livelihood and a plausible defamation claim. Emit NUMBERS ONLY and let the customer conclude: "94% on time · 3% cancelled · usually responds in 12 minutes · 47 jobs".
- **Nothing displays below 10 completed bookings.** Show "New provider" and the job count. One cancellation out of two bookings is 50% and means nothing.
- **The provider sees their own metrics before anyone else**, with the underlying bookings listed. Nobody should learn their on-time rate from a customer.

## Consequences — graduated, never silent, never automatic

Alert the provider first, naming the specific bookings and what would clear the threshold → then reduce search ranking → then remove emergency eligibility → then admin review. NEVER automatic account suspension; that stays a human decision in Phase 10b with the conduct record as evidence. Any provider may appeal through Phase 22, and a booking excluded on appeal leaves the aggregate and is audit-logged.

## Review tags

Six to eight FIXED tags per category, positive and negative, selected in one tap alongside the 1–5 star rating: *On time · Fair price · Quality materials · Good communication · Left a mess · Arrived late · Price changed on site.*

- FIXED PER CATEGORY, never free text. Free tags cannot be aggregated, arrive in a mix of Dhivehi and English, and become a moderation surface.
- Negative tags are the POINT. A positive-only set makes every profile look identical and pushes criticism into free text where it cannot be counted.
- A tag displays only once applied THREE times, so no single review brands anyone. Aggregate as counts: "On time (31) · Fair price (28) · Arrived late (3)".
- Rating must stay TWO TAPS MINIMUM — stars, then optional tags. Review completion rate is what makes the whole system work, and every extra required field costs completions.
