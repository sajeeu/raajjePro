# Phase 11 — Reviews, ratings & §1f's conduct metrics

Built 2026-10-09 against `01_Development_Plan_v5.md` revision 5.37: §Phase 11
(its three-clause **Done when**), §1f Provider Conduct & Reputation, §1h's
locked agreement and callback guarantee where they feed conduct, and the four
ledger rows earlier phases pointed here (P1, P5-2, P8-2, P17-11).

This file records the four questions the plan left open, the definitions the
build had to pin down, and what is deliberately not built.

---

## 1. The owner's four decisions (2026-10-09)

The owner asked for the recommended option on each and for the phase to be
built through without further prompts.

**On-time rate stays null.** §1f defines it as "arrivals within 15 min of the
promised time ÷ completed **with an arrival mark**". Nothing in the booking
machine records an arrival, and the plan never says who marks one — the
customer, the provider, or both. Inventing it would put a product decision in
the schema. So `onTimeRate` is computed as what it truly is today: no
denominator, `null`, never `0`. Ledger **P11-1** says what closes it.

**Every category carries §1f's eight tags.** The plan says "six to eight fixed
tags per category" and names one set; the design brief calls it Cleaning's.
Nothing defines the other eleven. `ReviewTag` is seeded per category from that
one set (`modules/reviews/seed.ts`), create-if-absent on `(categoryId, key)`, so
a category can diverge later through data without a schema change and without
disturbing a count already made. "Quality materials" reads poorly on
Photography or Fitness; that is the known cost.

**A tag shows at three different customers, not three applications.** §1f
and §Phase 11 say "applied three times"; `Rate This Job.dc.html` and the
design brief say "three different customers". They differ when one customer
reviews the same provider three times. The stricter reading is §1f's own stated
intent — "no single review can brand anyone" — so the tag-count rows carry both
`applicationCount` (what is printed: "Arrived late (5)") and `customerCount`
(what the threshold reads). 🔧 **The plan's wording now trails this decision**
and should be amended to say "three different customers" at §1f and §Phase 11.

**Threshold alerts are deferred.** §Phase 11 asks for "an alert on crossing a
threshold naming what would clear it", and the plan sets no threshold. The
metrics, the provider's own view and the underlying-bookings list are built;
the alert is not. Ledger **P11-2**.

## 2. Reviews

- **`Review`**: one per booking (unique `booking_id`), rating 1–5 (CHECK
  constraint plus Zod), optional tags from the booking's category, optional
  written body (the prototype's "Written review — optional"). `POST
  /v1/bookings/:id/review` — the booking's customer only, idempotency key
  required, `{ "rating": n }` is a complete review (§1f's two taps).
- **"Completed" means `completedAt` is set**, not the current status. §1c
  accepts a late dispute on a completed booking and "the booking stays
  completed"; a customer who disputed afterwards can still review. Every path
  that never completes — cancelled, declined, a completion-prompt "No" — has no
  `completedAt` and is refused `REVIEW_BOOKING_NOT_COMPLETED`.
- **Aggregates are recomputed, never incremented**, in the transaction that
  posts, hides or unhides — per provider and per listing, star breakdown and tag
  counts. The provider's aggregate row is locked first (`INSERT … ON CONFLICT DO
  UPDATE`), then the listing's, so concurrent posts for one provider serialise
  and none is lost. Asserted with four simultaneous posts.
- **Hide/unhide** — `POST /v1/admin/reviews/:id/hide|unhide`, `requireAdmin`, a
  reason required, audit-logged, a flag and never a delete (invariant 1d).
  §Phase 22 builds the queue that calls them; there is no panel (§0.0 item 20).
- **Public reads**: `GET /v1/listings/:id/reviews` and `/review-summary`, `GET
  /v1/providers/:id/reviews` and `/review-summary`, `GET
  /v1/categories/:id/review-tags`. A listing or provider that §1a or
  `PUBLICLY_VISIBLE_LISTING` does not show is not found. A deleted listing's
  reviews keep counting for the provider (§Phase 8).
- **Authorship**: `authorId` is kept and never returned — no DTO has the field.
  The public card prints "Aishath N." (the prototype's form). The anonymisation
  hook stamps `authorAnonymisedAt`; the review, its body and its weight stay,
  and the display name becomes null.

## 3. Conduct — the definitions the plan left implicit

`modules/conduct/compute.ts` is the one place each is written. Window: rolling
90 days. A booking an admin excluded on appeal counts towards nothing.

| Metric | What the build counts |
|---|---|
| Completion | completed ÷ (completed + provider-cancelled + no-show), each when it happened in the window |
| Cancellation | of bookings that reached `accepted` in the window, those the **provider** cancelled. Customer cancellations and the system's verification-revocation cancel do not count |
| No-show | same cohort: an emergency offer marked `no_show`, and a completion-prompt "No" **once an admin resolves it `resolved_for_customer`** — §1f says "confirmed" no-shows, and "possible" becomes confirmed when someone looks |
| On-time | `null` (§1 above, P11-1) |
| Price adherence | of completed bookings with an agreed amount (callbacks excluded — zero by definition): `(final ?? agreed) ≤ agreed` **and** the provider never proposed raising the price. §1h: every attempt "feeds price adherence", so a rejected upward proposal still counts |
| Acceptance | explicit answers on targeted bookings: slot `accept`/`decline`, request `offer-quote`/`decline`. Timeouts excluded. Emergency broadcasts excluded on both sides — §0.0 rules a pass "does not touch the acceptance rate", and counting offers without passes would only inflate it |
| Median response | the same answers, seconds from creation (or the customer's pre-accept reschedule, which restarts the clock) |

Payment-claim outcomes feed nothing (§1f, Round 24). A declined callback lands
in acceptance through the ordinary `decline` edge, a callback cancelled after
acceptance in cancellation — no special case (P17-11).

### Recomputed on transition, not on read

`BookingRepository.recordStatusEvent` writes every status event in the
machine. On a terminal one it calls `ConductService.markStale` **inside that
transaction**, upserting the provider's `ProviderConductSnapshot` with
`staleSince`. The `conduct-recompute` job (every minute) recomputes stale
snapshots under the same row lock, so a booking transaction still in flight
makes it wait, and one starting later re-marks the row. It is not inline
because some transitions write their evidence after the event — `markNotArrived`
closes the offer as `no_show` after it. The job also recomputes every snapshot
daily, because a 90-day window moves when nothing happens.

Rates are stored as integer basis points (no float in the database) and
returned as fractions through §Phase 5's `ProviderConductSource`, which
`ConductService` now implements. Phase 5's display rules — numbers only, the
ten-booking floor, the provider first — are unchanged.

### The provider's own evidence, and appeals

- `GET /v1/providers/me/conduct/bookings` — the bookings behind the numbers,
  each with flags saying which metric it moved, computed against the
  snapshot's own `computedAt` so the list and the numbers cannot disagree.
- `POST /v1/admin/bookings/:id/exclude-from-conduct` and `/include-in-conduct`
  — §1f's appeal outcome. Reason required, audit-logged, reversible, and the
  snapshot is recomputed in the same transaction. §Phase 22 owns the appeal
  queue that leads here.

## 4. Not built, deliberately

- **Threshold alerts** (P11-2) and the **ranking and emergency-eligibility
  consequences** of §1f — the latter are §Phase 15's ranking and a later
  eligibility rule; §Phase 11 lists neither.
- **Review editing, provider replies, a review window** — the plan specifies
  none of them.
- **Showing ratings on the public provider and listing shapes** — §Phase 12 and
  §Phase 13 compose the summary endpoints into their own pages.
- **Frontend** — §Phase 11 is marked *(backend)*. `Rate This Job.dc.html` exists
  for whichever phase builds the screen.

## 5. Flagged for correction

- **§1f / §Phase 11 wording**: "applied three times" → "three different
  customers" (§1 above). Not edited here; the owner amends the plan.
- **`.claude/skills/provider-conduct-and-reviews/SKILL.md`** said "On-time
  applies to slot and request modes only. Emergency has no `scheduledFor`" —
  the pre-Round-22 rule. Corrected to match §1f.
