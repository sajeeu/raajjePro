# RaajjePro — Development Plan (v3)

Supersedes `01_Development_Plan_v2.md`. Folds in every decision resolved across three rounds of review on 2026-08-03: the original adversarial review (48 decisions), the round-2 review of v2 (8 decisions), and a final round on pricing, verification, and remaining gaps (4 decisions). See **§8 Decision Log** for full provenance — every non-obvious choice in this document is traceable to a specific answer you gave.

Stack unchanged: Flutter (mobile-first) · TypeScript/Fastify/Prisma/PostgreSQL · REST `/v1` · monorepo.

---

## What changed from v2 — read this first

1. **Booking now splits into two modes by category: slot-based and request-based.** Slots fit appointment-shaped services (Cleaning, Beauty, Fitness). They don't fit diagnostic/variable-duration ones (Plumbing, Electrical, AC Repair, Moving, Events, Photography, Gardening, Computer) — a plumber can't predict job length before seeing it. Request-based categories use the existing quote mechanism: the provider proposes a concrete time *and* price together, on accept.
2. **Tuition is removed entirely** — from categories, seed data, and every reference. Down to 11 categories.
3. **Emergency bookings bypass slots.** An urgent request goes straight to the provider as an ASAP accept prompt; contact unlocks immediately on acceptance given the urgency, rather than waiting for payment attestation.
4. **A pre-booking enquiry channel is restored**, strictly in-app, contact-masked, but explicitly allowing service details — appliance make/model/serial number, property details, photos. This was removed in v2's booking-scoped-only messaging; removing it left no way to ask a question before committing to a job and a price.
5. **Payment-attestation timeout now escalates instead of auto-confirming.** v2 auto-confirmed a payment claim after 7 days of provider silence, which recorded an attestation that may never have happened and unlocked contact info on it. It now moves to `payment_unresolved`, notifies both parties, and queues for admin review — nothing is unlocked on a timeout.
6. **Referrals are cut from v1.** The credit was farmable at zero cost (two accounts, four free actions, off-platform payment made it unverifiable) and reopened the stored-value question deferred with credits. Moved to post-v1 backlog with fraud controls as a prerequisite.
7. **The Verified badge now depends on identity verification only**, not an active subscription. A lapsed-but-verified provider stays verified — the badge is a safety signal, not a payment status.
8. **Push infrastructure moves to a new Phase 3c**, ahead of Phase 17 which depends on it, with an explicit fallback (SMS, then forced email) for providers who deny push at the OS level.
9. **The provider-accept step now has a 24-hour timeout.** An unresponsive provider no longer holds a slot or request hostage indefinitely.
10. **Subscription price is pinned: MVR 150/month, calendar billing, pause capped at 10 cumulative days and resumes remaining time (not restart) — and the same pause mechanic now applies symmetrically to the trial period**, keyed off the same provider-level `acceptingNewCustomers` toggle.
11. **Identity verification is specified**: ID/passport + trade proof (business registration, certificate, or completed-job photos), reviewed by the admin role already built in Phase 2.
12. **Downgrade now preserves any listing with a confirmed future booking** until that booking reaches a terminal state, rather than hiding it immediately regardless of a commitment already made to a customer.
13. **Recurring bookings added** (slot-based categories only) as a lightweight extension to Phase 17.
14. **Response-time metric shows "No data yet"** for a provider with zero booking history, instead of a blank or zero that reads worse than no metric at all.
15. **Deferred by your explicit choice, not by default:** admin hardening (MFA, IP allowlist, staffing plan) and counterparty-PII redaction on data export both stay out of v1 scope. Flagged in §7 so they aren't silently forgotten.

**Where I made a judgment call without a dedicated question**, because the round of decisions was already large — each is flagged inline with 🔧 and summarized in §6 so you can override any of them:
- Which categories are slot-based vs. request-based
- The mechanics of the emergency-bypass and completion-auto-timeout flows
- The Home launch-mode catalogue threshold (a tunable config value, not a structural decision)

---

## 1. Mockup Inventory & Coverage Map

| Screen | Status | Modules |
|---|---|---|
| Home (feed) | Exact match provided | Search & Discovery, Listings, Favorites, Provider Profiles |
| Explore (category grid) | Exact match provided — **now 11 categories, not 12** | Categories |
| Login | Provided, improvable | Identity & Auth |
| Register | Provided, improvable | Identity & Auth |
| Profile (customer) | Provided, improvable | Customer Profiles, Favorites, Bookings, Notifications |
| My Services Dashboard | Exact match provided | Provider Profiles, Listings, Reporting |
| Create/Edit Service Wizard (1–7) | Exact match provided | Listings, Categories, Media, Service Areas |
| Service Preview | Exact match provided | Listings, Reviews, Provider Profiles |

🔧 Removing Tuition breaks the "exact match" claim for the Explore grid's category count — the mockup shows a 3-column grid built around 12 items; 11 leaves an uneven last row. Grids handle this natively, but flagging since you asked for exact matches elsewhere.

### Pages with no mockup (Claude proposes, you approve, before that phase's code)

Carried over from v2:
- Bookings tab (list + detail + status timeline)
- Notifications centre
- Provider public profile
- Search results
- Category results
- Saved Services list
- Forgot Password flow
- Phone verification (OTP entry)
- Trust & Safety / Privacy & Security sub-screens
- Availability & Time Slot management (provider side)
- Provider Billing (subscription status, payment proof submission, invoice list)
- Admin panel (separate web app)

New in v3:
- **Booking flow, now two variants:** slot picker (slot-based categories) and request-with-time-window (request-based categories)
- **Pre-booking Enquiry thread** — contact-masked chat, listing-scoped, no booking required
- **Emergency / ASAP request flow** — bypasses the slot picker entirely
- **Provider-side payment & contact details entry** (bank details, phone/WhatsApp/Viber handle — captured in Phase 5, no screen existed for it in v1)

Removed in v3:
- ~~Referral screen~~ — cut with referrals; see §7 Post-v1 Backlog

---

## 1a. Provider Lifecycle Model

Unchanged from v2. Public visibility is **derived**, not stored: a provider is visible if and only if `count(published, active-visibility listings) > 0`, computed by one shared `findVisibleProviders` query every consumer calls. `verificationStatus` (unverified/pending/verified) is a separate axis, admin-transitioned — see §1e below for what evidence that now requires. `ProviderProfile` is created implicitly on first draft; `getOrCreateProviderProfile` is idempotent; `POST /v1/listings` requires a client idempotency key so a flaky connection can't create orphan drafts.

---

## 1b. Monetization Model — subscription only, pinned

Customer-facing rule unchanged: all customer features are free indefinitely, and nothing here may ever gate a customer action. Payment for jobs stays off-platform. Everything RaajjePro collects is a provider paying RaajjePro, via manual bank transfer + admin confirmation.

### v1 scope

| Layer | Mechanism |
|---|---|
| Free tier | 1 active listing, full search visibility (never paywalled), no badge dependency, no analytics |
| Trial | Full premium access. Starts on the provider's first booking reaching `confirmed`. Runs 60 calendar days. |
| Subscription (Premium) | **MVR 150/month, pinned.** Unlocks multiple active listings, analytics dashboard + weekly digest, priority placement. **Does not unlock the badge** — see §1e. |

~~Referral credit~~ — **cut.** See §7.

### Deferred to post-v1 (unchanged from v2)

Credit wallet & à la carte purchases; the advertising module. Rationale unchanged: every premium benefit derives its value from demand density that won't exist at launch.

### Trial and subscription lifecycle

- Warning 7 days before trial or subscription period end. 7-day grace period after expiry with no change, then downgrade to free.
- **Downgrade is non-destructive and reversible.** Listings beyond the free-tier cap are hidden (`visibility: 'hidden_over_cap'`), never deleted. Badge (now identity-only, see §1e) is unaffected by downgrade. Analytics disable. Any confirmed payment restores everything.
  - **Which listings get hidden — revised:** a listing with a booking in `accepted`, `payment_claimed`, or `confirmed` status and a future `scheduledFor` is **protected** and stays visible regardless of cap, until that booking reaches a terminal state (`completed`/`cancelled`/`declined`/`dispute_resolved`). Among unprotected listings, hide least-recently-updated first, keeping the most recently updated one visible.
  - **Why:** hiding a listing out from under a customer who already has a confirmed job booked against it breaks a commitment the platform already vouched for.
- **Pause — confirmed:** capped at 10 cumulative days. Resuming manually within the cap picks up where it left off (remaining paused time is preserved for later use). At the cap, pause auto-ends and the clock forcibly resumes.
  - **Now explicit: this applies symmetrically to the trial period, not just paid billing.** A trial provider who toggles `acceptingNewCustomers` off pauses their trial clock under the identical 10-day cumulative cap and resume-remaining-time rule. One pause mechanism, one implementation, shared by both states.
- Trial abuse prevention: one trial per user account, not tied to phone number — a provider who changes phone keeps their remaining trial.
- No expiry on money; subscription simply stops charging when cancelled.

### The manual payment mechanism

Unchanged from v2: one generic `PaymentSubmission` (purpose enum stays open for future re-additions of credits/ads), manual bank transfer + admin confirmation, nothing granted on `pending`, live-read entitlements never cached, admin reversal is an explicit audited endpoint, PDF invoice on confirmation, bank-statement CSV import with reference-code auto-matching in Phase 10a, 48-hour confirmation SLA as documented policy.

---

## 1c. Booking, Slots & Requests, Payment Attestation & Contact Visibility (rebuilt)

This replaces v2's §1c. v2 fixed the payment-ordering problem with a single slot-based model — which then didn't fit roughly two-thirds of the category list, and removed the ability to ask a question before committing to a job and a price. v3 splits booking into two modes and restores pre-booking communication without reopening the leakage problem it was built to close.

### Category booking mode

Every listing carries a `bookingMode`: `'slot'` or `'request'`, defaulted by category and editable per listing (a provider can override if their business genuinely fits the other mode better).

🔧 Default assignment, my first pass — adjust freely, it's a config table, not a structural decision:

| bookingMode | Categories | Why |
|---|---|---|
| `slot` | Cleaning, Beauty, Fitness | Fixed or provider-predictable duration; appointment-shaped |
| `request` | Plumbing, Electrical, AC Repair, Photography, Gardening, Computer, Moving, Events | Duration depends on diagnosis, property, or negotiation — cannot be pre-published as a fixed-length slot |

### Slot-based flow (unchanged from v2 in mechanics)

- Provider publishes bookable time slots (Phase 9a), generated from availability rules with individual override.
- Customers only ever see currently-open slots.
- Booking a slot reserves it atomically — `UNIQUE (providerId, listingId, startsAt)`, enforced at the database level, not just in application code.
- Cancellation or decline frees the slot back to `open`.

### Request-based flow (new)

- Customer submits a request: a **preferred date/time window** (not an exact slot — e.g. "Tuesday afternoon" or "this week"), job details, and location, through the listing's booking entry point.
- The provider reviews it via the same accept prompt used for slots, but **responds with a proposed concrete date/time and price** — this reuses the existing quote mechanism (`awaiting_quote` → `quote_offered`) rather than being a new state.
- The customer approves or rejects the proposed time/price. Approval transitions to `accepted` and **reserves that concrete date/time against the provider's calendar using the identical underlying reservation mechanism as a slot** — an accepted request-based booking blocks that time exactly as a slot booking would, so a provider can't be double-booked across their slot-based and request-based listings.
- Everything downstream (payment prompt, attestation, contact unlock, completion, review) is identical to the slot-based flow from `accepted` onward.

### Emergency bookings — new, bypasses both

- A listing may support an `isEmergency` request type (available regardless of `bookingMode`, most relevant to Plumbing/Electrical/AC Repair).
- The customer submits an emergency request with no slot or window — just "as soon as possible."
- The provider gets an **urgent accept prompt**, same no-contact/no-chat constraint as any accept step.
- 🔧 **On acceptance, contact info unlocks immediately** — this is a deliberate carve-out from the normal "unlocks at `confirmed`" rule, because coordinating access, exact location, and arrival with an urgent tradesperson cannot wait for a full payment-attestation cycle. Payment attestation (`I've Paid` / `Payment Received`) still happens afterward and still feeds `jobsCompletedCount`, trial progress, and review eligibility — it just doesn't gate contact for this booking type. If this trade-off feels wrong once you see it in use, it's a single conditional to remove.
- No slot reservation applies — an emergency booking doesn't block the provider's published calendar, since it's understood as an interruption to it.

### Pre-booking enquiry — restored, contact-masked

- A `Conversation` of type `enquiry`, scoped to a **listing** (not a booking), available to any phone-verified user before any booking exists.
- **Any message matching a phone-number-shaped sequence or a known contact-app phrase ("call me on Viber/WhatsApp") is rejected outright** — not silently redacted, not just nudged. The sender sees: *"For your safety, contact details can't be shared until a booking is confirmed. Job details and photos are fine."* This is intentionally stricter than Phase 18's general in-conversation nudge, because this channel exists specifically to solve the leakage problem while restoring the ability to talk.
- **Everything else is explicitly allowed** — appliance make/model/serial number, property details, photos of the issue, availability questions, price ranges. The point is to let a plumber ask "is it a split unit or ducted?" and a customer answer, not to make the thread useless.
- If a booking is later created between the same two users on the same listing, the **same conversation continues** rather than starting fresh, now also linked to the booking. Full chat (Phase 18) resumes once the booking reaches `accepted`.
- Restores the "Message" button on Service Preview (Phase 12), removed in v2.

### Access control — unchanged from v2

| Tier | Unlocks | Enforced by |
|---|---|---|
| Guest | Browse, search, view listings and public provider profiles | No gate |
| Registered | Save/favourite | `requireAuth` |
| Phone-verified | Book, enquire, message within a booking | `requirePhoneVerified` |
| Visible provider | Appears publicly, receives bookings | Derived published-listing count (§1a) |
| Entitled provider | Extra listings, analytics, priority | `getProviderEntitlements` (§1b) |

### Booking status machine

```
                    ┌──────────► declined (provider, from requested)
                    │
requested ──────────┴──► accepted ──► payment_claimed ──┬──► confirmed ──► completed
   │                        │              │             │        │
   │                        │              └──► disputed ┘        └──► (auto, 7d past
   │                        │                      │                    scheduled: see below)
   │                        │              (7d silence: escalates,      │
   │                        │               NOT auto-confirms — see     └──► dispute_resolved (admin)
   │                        │               below)
   └──► cancelled ◄─────────┘
        (customer, pre-payment)
```

Request-based/quote-priced listings insert `awaiting_quote → quote_offered → accepted` before the diagram above, as in v2. Emergency bookings skip straight from `requested` to `accepted` with no slot dependency, and contact unlocks at `accepted` rather than `confirmed`.

### The flow, step by step

1. Customer picks an open slot (slot-based) or submits a preferred window (request-based) or an ASAP request (emergency). Status `requested`.
2. **Provider accept prompt** — job details, no contact info, no chat. Accept/decline, or (request-based/quote-priced) propose a time + price.
3. On acceptance, the booking carries an **`agreedAmount`** (integer laari) — from listing price, or from the accepted quote. No booking leaves `requested`/`quote_offered` without one.
4. **24-hour timeout on this step.** If the provider doesn't respond within 24 hours, the booking auto-declines, the slot or calendar block releases, and the customer is notified to look elsewhere.
5. Customer is prompted to pay off-platform, directly to the provider, using the payment details the provider registered (Phase 5). Copy states plainly RaajjePro isn't handling this money.
6. Customer taps "I've Paid" — self-attestation, no proof upload. Status `payment_claimed`.
7. Provider confirms or disputes receipt. Confirm → `confirmed`. Dispute → `disputed`.
8. **Revised timeout:** if the provider neither confirms nor disputes within 7 days, the booking moves to **`payment_unresolved`** — not `confirmed`. Both parties are notified, it's queued in the Phase 22 moderation queue, and **nothing is unlocked**. An admin resolves it manually to `confirmed` or `cancelled` based on follow-up. v2's auto-confirm recorded an attestation that may never have happened and unlocked contact on it; this doesn't.
9. **`confirmed` is the contact-info unlock** (except emergency bookings, unlocked at `accepted` — see above).
10. **Completion.** 🔧 Revised: if the provider doesn't mark the job complete within 7 days of `scheduledFor`, the **customer is prompted** — "Did [Provider] complete this job?" (Yes / No / No response). "Yes" → `completed` normally. "No" → flagged to the moderation queue as a possible no-show, same path as a dispute. No response after a further 3-day grace → auto-completes, but tagged `completedVia: 'unconfirmed'` internally, distinguishing it from a genuine two-sided completion for analytics and trust purposes, while still opening review eligibility (a provider must not be able to block reviews forever by staying silent, which is why this doesn't simply stay open indefinitely). *This extends the same "don't silently manufacture a positive record from silence" principle you confirmed for payment escalation — flagging it as my own extension since it wasn't asked as a separate question. Tell me if you'd rather it stay a plain auto-complete.*
11. Review becomes postable once `completed`. One review per booking.

### Disputes — unchanged from v2

Either party may dispute. A late dispute (post-`completed`) is accepted; the booking stays completed, the dispute queues separately. `disputed` is not terminal — an admin resolves it to `dispute_resolved` with a recorded outcome. Decline ≠ dispute: separate endpoints, separate statuses, visually distinct in the UI.

### Recurring bookings — new

- Available on **slot-based listings only** (predictable duration is what makes "same time next week" meaningful).
- A `RecurringSeries` links a customer, provider, and listing to a weekly cadence.
- **Each occurrence still requires individual provider accept** — recurrence is a convenience, not a standing pre-authorization, deliberately preserving the same "provider always gets a real chance to decline" principle the whole redesign is built around. The UI streamlines it to a one-tap "Same time next week?" rather than a full re-request.
- Cancelling one occurrence doesn't cancel the series; cancelling the series stops future occurrences.

### Contact visibility — unchanged in principle, one exception noted

Neither party sees the other's phone, WhatsApp, or Viber handle before `confirmed`, **except emergency bookings, which unlock at `accepted`** (see above). Implemented as a live query, never a cached flag. The booking-scoped endpoint is the only place in the system that ever returns this data.

### Honest framing — unchanged

Never "Payment Verified," never a lock/checkmark implying platform certainty. "Provider confirmed receipt."

### What this does and does not prevent — unchanged

Slots/requests plus contact gating raise the bar against off-platform bypass; they don't stop a provider publishing their own number in a listing description, which Phase 22's free-text scanning mitigates but doesn't close. The pre-booking enquiry thread's hard block on contact patterns is the one place in the system where this is actually *enforced* rather than merely nudged — everywhere else remains a moderation problem, not an access-control one.

---

## 1d. Categories — 11, Tuition removed

Cleaning, Plumbing, Electrical, AC Repair, ~~Tuition~~, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events → **Cleaning, Plumbing, Electrical, AC Repair, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events.**

Phase 4's seed data, icon/color mapping, and every category-count reference elsewhere in this document reflect 11, not 12.

---

## 1e. Identity Verification — newly specified

The Verified badge depends solely on `verificationStatus: 'verified'` — it no longer requires an active subscription (§1b).

- **Evidence required:** a national ID or passport, plus proof the provider actually does the trade — a business registration, a trade certificate, or photos of completed jobs.
- **Review:** manual, by the admin role built in Phase 2 — no new vendor, no automated KYC integration, consistent with the manual-first posture of the rest of the platform.
- **Where this lives:** the review queue extends Phase 10a/22's existing admin panel and audit log rather than a separate tool.
- Full specification (evidence checklist, rejection reasons, resubmission path) belongs in Phase 23 alongside the legal/compliance work, but the *decision* — what's required and who reviews it — is locked now so Phase 5 and Phase 10 can build against it without guessing.

---

## 2. Architecture Decisions

Unchanged from v2: Fastify, Prisma, PostgreSQL, JWT, Zod, Riverpod, S3-compatible storage with proof uploads in a private bucket, UUID primary keys, integer-laari money, soft-delete everywhere, a real job runner, idempotency keys on money/creation POSTs, global + per-endpoint rate-limit tiers.

One addition:

| Decision | Choice | Note |
|---|---|---|
| **Push delivery** | **FCM + APNs, built in Phase 3c** | Split out of Phase 19 — see below. Required for Phase 17's accept prompt, with an explicit fallback for denied permission. |

---

## 3. Phased Roadmap

Phases 0, 1, 2, 3, 3b, 4, 6, 7, 11, 13, 14, 15, 20, 21, 22, 24 are **unchanged from v2** except where noted below (Phase 4's category count, Phase 15's badge/verification independence already matched v3). Only phases with substantive changes are repeated in full here.

### Phase 3c — Push Notification Infrastructure *(new)*

Sequenced after Phase 3 (device-token registration needs an authenticated user) and before Phase 9a/17, which depend on it.

- FCM (Android) + APNs (iOS) integration; device token registration, refresh, and multi-device support (a user may have several registered devices).
- A single `PushSender` abstraction — the send interface every later module (17, 19) calls, not one each.
- **Detect OS-level permission denial** and store that state on the user.
- **Fallback chain for the load-bearing prompt (Phase 17's provider-accept):** if push is denied or fails to deliver within the acceptance window, fall back to SMS (reusing Phase 3's SMS interface), then a forced transactional email.
- A persistent in-app reminder for a provider who has denied push: *"You may miss booking requests — enable notifications."*

**Done when:** a test push arrives on a real device within seconds; a provider with push denied receives an SMS fallback for a booking-accept prompt within the same window; multi-device registration and cleanup work correctly.

### Phase 5 — Provider Profiles *(backend only)*

Unchanged from v2's structure (`jobsCompletedCount` derived from the event log, contact details, payment details, provider-level `acceptingNewCustomers`, `getOrCreateProviderProfile`, `findVisibleProviders`) — one addition:

- **`bookingMode` default per category, overridable per listing** (§1c) — a lookup table seeded in Phase 4, referenced here and consumed by Phase 9/9a/17.

### Phase 8a — Subscription & Trial *(backend only)*

Unchanged from v2's structure, with the pinned/confirmed values from §1b:

- **`amount` on the subscription's `PaymentSubmission` defaults to MVR 150 (15000 laira), pinned, not a range.**
- **Pause logic is shared between `trialing` and `active` (paid) states** — one function, one 10-cumulative-day cap, resume-remaining-time semantics, forced auto-resume at the cap, applied identically regardless of which state the provider is in when they pause.
- ~~Referral code, referral credit~~ — removed. See §7.
- **Downgrade listing-protection logic** (§1b): before hiding any listing, the entitlement-downgrade job checks for a protected listing (one with a non-terminal booking and a future `scheduledFor`) and excludes it from the hide candidates.

**Done when:** trial starts on first confirmed booking; pause behaves identically whether triggered during trial or during an active paid period; a downgrade correctly skips hiding any listing with a confirmed future booking, and hides it the moment that booking completes or cancels.

### Phase 9a — Availability & Time Slots

Unchanged from v2 for the slot-based mechanics (`TimeSlot`, the `UNIQUE (providerId, listingId, startsAt)` constraint, transactional reservation, holiday/exception blocking, timezone convention). One addition:

- **The same reservation mechanism backs request-based `accepted` bookings** — when a request-based booking is accepted with a concrete date/time, it creates an equivalent reservation record against the provider so slot-based and request-based bookings can't overlap for the same provider.

### Phase 17 — Bookings Module

The largest phase, substantially revised from v2. No mockups — propose each frontend piece before implementing.

**Backend:**
1. `Booking`: listingId, customerId, providerId, `bookingMode` (slot/request/emergency), timeSlotId (nullable — null for request/emergency), status (per §1c, now including `payment_unresolved`), `agreedAmount` (integer laira), quotedAmount, `scheduledFor`, paymentClaimedAt, paymentAttestedAt, completedAt, `completedVia` (`'confirmed'` | `'unconfirmed'`), statusHistory.
2. `POST /v1/listings/:id/bookings` — slot-based reserves the slot in-transaction; request-based captures a preferred window; emergency captures no timing constraint. `requirePhoneVerified`; idempotency key required.
3. `PATCH /v1/bookings/:id/accept` — sets `agreedAmount`; no contact info, no chat exposed. **For `isEmergency` bookings, also triggers the immediate contact-info unlock** (§1c).
4. `PATCH /v1/bookings/:id/quote` / `/approve-quote` — request-based and quote-priced path; approving a request-based quote also creates the calendar reservation (Phase 9a).
5. `PATCH /v1/bookings/:id/decline` — provider; frees the slot/reservation; distinct from dispute.
6. **Scheduled job: auto-decline `requested`/`quote_offered` bookings 24 hours after creation with no provider response** — releases the slot/reservation, notifies the customer.
7. `PATCH /v1/bookings/:id/claim-payment` — customer self-attestation.
8. `PATCH /v1/bookings/:id/confirm-payment-received` — provider; → `confirmed`; the contact-info unlock (except emergency, already unlocked); fires the Phase 8a trial-start hook on the provider's first confirmed booking.
9. **Scheduled job: `payment_claimed` with no provider response after 7 days → `payment_unresolved`, not `confirmed`.** Notifies both parties, files a Report (Phase 22). No entitlement or contact info is granted by this transition.
10. `PATCH /v1/bookings/:id/dispute` — either party; → `disputed`; files a Report.
11. `PATCH /v1/bookings/:id/resolve-dispute` — admin; → `dispute_resolved`, and (new) also resolves `payment_unresolved` to `confirmed` or `cancelled`.
12. `PATCH /v1/bookings/:id/complete` — provider; → `completed`.
13. **Scheduled job: `confirmed` 7 days past `scheduledFor` with no completion → customer prompt** ("Did this happen?"), per §1c's revised auto-completion flow; a further 3-day non-response auto-completes with `completedVia: 'unconfirmed'`.
14. `PATCH /v1/bookings/:id/cancel` — customer, pre-payment; frees the slot/reservation.
15. `PATCH /v1/bookings/:id/reschedule` — moves to another open slot (slot-based) or a new proposed time (request-based); frees the old reservation atomically.
16. `POST /v1/recurring-series` / management endpoints — slot-based only; generates individual bookings on cadence, each requiring its own accept.
17. `GET /v1/users/me/bookings?role=&status=`
18. `GET /v1/bookings/:id/contact-info` — the only endpoint returning contact details, both directions, on a `confirmed` booking or an `accepted` emergency booking.

**Frontend:**
1. Booking entry, three variants: slot picker (open slots only), request-with-preferred-window, emergency/ASAP — routed by the listing's `bookingMode` and an "Emergency" toggle where applicable.
2. Provider accept prompt: job details, no contact/no chat, accept/decline/propose-quote, with a visible 24-hour countdown.
3. Payment prompt: provider's payment details, `agreedAmount` shown explicitly, honest copy, "I've Paid."
4. Provider receipt prompt: three visually distinct actions.
5. On `confirmed` (or `accepted` for emergency): contact details surfaced as an unlock moment.
6. **"Did this happen?" prompt** for the customer at the 7-day post-scheduled mark if the provider hasn't marked complete.
7. Bookings tab: status filter pills, detail view, status timeline, now with nine-plus distinct status badges including `payment_unresolved`.
8. Recurring-booking entry point and one-tap "Same time next week?" prompt.

**Done when:** the full lifecycle works for all three booking modes; concurrent bookings on one slot/reservation resolve to one winner; an unresponsive provider auto-declines at 24 hours and releases the hold; an unresolved payment claim escalates to admin review at day 7 without unlocking anything; a dispute from either side queues correctly; an emergency booking's contact unlock fires at `accepted`, not `confirmed`; the "did this happen" flow correctly distinguishes confirmed from unconfirmed completions; reschedule and recurring bookings both correctly manage the reservation lifecycle; the contact endpoint returns data only for a genuinely eligible pair.

### Phase 18 — Messaging Module

Revised: **no longer booking-scoped only.**

- `Conversation` type `enquiry` (listing-scoped, pre-booking, contact-pattern messages hard-rejected — §1c) or `booking` (full chat, available from `accepted` onward).
- `requirePhoneVerified` on both types.
- Block user; report from within a conversation (unchanged from v2).
- Contact-pattern detection in `booking`-type conversations remains a **soft nudge**, never a block — the hard block is specific to the pre-booking `enquiry` type, where the whole point of the channel is to prevent leakage while a job isn't yet committed.
- Frontend: conversation list (both types), thread view, the enquiry-thread rejection message specified in §1c.

**Done when:** an enquiry thread rejects a phone-number-shaped message with the specified copy while allowing a model-number-shaped one through; a booking-scoped thread nudges rather than blocks; two verified accounts can exchange messages in both conversation types; blocking and reporting both work.

### Phase 19 — Notifications Module

Reduced in scope now that Phase 3c owns push infrastructure — this phase is notification **content**, not delivery.

- `Notification`: userId, type, payload, readAt, createdAt — calls Phase 3c's `PushSender`, doesn't reimplement delivery.
- ~~Referral credited~~ removed from the type list; ~~push delivery build-out~~ removed (now Phase 3c).
- Types: booking_requested, booking_accepted, booking_declined, booking_auto_declined, payment_claimed, payment_confirmed, payment_unresolved, payment_disputed, dispute_resolved, booking_completed, booking_auto_completed, payment_submission_confirmed, payment_submission_rejected, trial_ending_7d, subscription_ending_7d, downgraded_to_free, new_message, new_enquiry, new_review.
- Weekly provider digest email (opt-in): views, bookings, reviews, top-performing listings.
- Provider analytics dashboard: per-listing views, booking counts, conversion rate, rating trend, response time.
- **Response-time metric: shows "No data yet" for a provider with zero booking-acceptance history**, rather than a blank or zero.
- Notification centre screen (propose first); live badge counts.

**Done when:** each event type fires correctly through Phase 3c's sender; the digest sends on schedule to opt-in providers only; the analytics dashboard renders real data; a brand-new provider's response-time metric reads "No data yet," not "0 minutes."

### Phase 23 — Legal, Compliance & App Store Readiness

Unchanged from v2 except:

- **Identity verification evidence and reviewer are no longer an open research question** — §1e specifies it. This phase implements the screens and the formal evidence checklist, it doesn't decide the model.
- **Remove the referral/stored-value research question** — no longer applicable with referrals cut from v1.
- Three research questions remain (App Store subscription-compliance, Maldivian data-protection status, GST/invoicing) — unchanged, still resolve before Phase 8a goes deep.

---

## 4. Sequencing Notes

- Phases 0–2 strictly linear.
- **Phase 3c (Push) now sits ahead of Phase 9a and Phase 17**, resolving the circular dependency v2 left open — Phase 17's accept prompt no longer waits on a phase built after it.
- Phase 9a is a hard prerequisite for Phase 17, as in v2.
- Phase 8a's trial hook fires from Phase 17's `confirm-payment-received`, unchanged.
- Phase 17 and Phase 22 retain the soft circular reference (disputes and unresolved-payment escalations file Reports); build 17 first with a minimal Report insert, 22 makes the queue real.
- **Pin before Phase 3c:** confirm the SMS provider's fallback cost is acceptable at scale — every denied-push provider now costs an SMS on every booking-accept prompt, not just OTP sends.
- **Pin before Phase 9a:** the per-category `bookingMode` table in §1c is a first pass — confirm or adjust before it's seeded, since it drives which listings get a slot picker vs. a request form.
- Phases 21, 22, 24 remain independent of one another.

---

## 5. Post-v1 Backlog (deliberate, not forgotten)

Unchanged from v2, plus two additions:

- Credit wallet & à la carte purchases; the advertising module; Dhivehi/Thaana localisation with RTL (needs a second font stack — Plus Jakarta Sans and Inter don't cover Thaana); admin role granularity, MFA, and network segregation; full analytics platform; automated image moderation; saved searches and alerts; real social auth.
- **Referrals — cut from v1, revisit only with fraud controls**: same-device/IP detection, a cap per account, credit issued on the *referred provider's first confirmed subscription payment* rather than a free/off-platform-verifiable booking, and a re-examination of the stored-value question under Maldives Monetary Authority rules before reintroducing it.
- **Data export counterparty-PII redaction** — currently out of v1 scope by your explicit choice (§7). If a provider's export containing a customer's name/time/amount ever becomes a real complaint or a compliance question, this is a small, contained fix.

---

## 6. Judgment Calls Made Without a Dedicated Question

Everything below was resolved by extending a principle you'd already confirmed, or by picking a reasonable default for a genuinely low-stakes/tunable value, rather than by a specific yes/no from you. Flagged here so nothing is silently locked in.

1. **Per-category `bookingMode` assignment** (§1c) — my first-pass split of the 11 categories into slot vs. request. Easiest of these to get wrong in a way that matters; review it specifically.
2. **Emergency-booking mechanics** — contact unlocking at `accepted` rather than `confirmed`, and no calendar reservation for emergency bookings. Follows directly from "emergency bypasses slots," but the specific unlock-timing trade-off wasn't spelled out when you chose that option.
3. **Completion auto-timeout redesign** ("did this happen?" prompt, `completedVia: 'unconfirmed'` tagging) — extends the same "don't manufacture a false positive from silence" principle you confirmed for the payment-attestation timeout. Not asked as its own question.
4. **Home launch-mode catalogue threshold** — defaulted to 50+ published active listings, tunable at any time without a code change. Genuinely low-stakes; didn't spend a question on it.
5. **Trial-start trigger stays as "first confirmed booking" only** — the v2 review flagged that this might never fire for a provider who publishes but never gets booked, and recommended also allowing an explicit "Try Premium" provider-initiated trial start. **I did not apply this fix** — it was in my findings but never made it into a question round. Worth a decision before Phase 8a: leave as-is, or add the explicit-request path?

---

## 7. What Was Explicitly Deferred by Your Choice

Distinct from the backlog above — these were offered as in-scope options and you chose not to include them. Recorded so they read as a decision, not an oversight, if they come up later:

- **Admin hardening** (MFA, IP allowlist, a staffing plan behind the 48-hour confirmation SLA) stays out of v1. The residual risk: a single admin role with a single reviewer is your only check on money-adjacent actions (entitlement grants, content hiding, dispute resolution) — worth a look before the provider count makes a mistake here expensive.
- **Data export counterparty-PII redaction** stays out of v1 — a provider's export currently includes their customers' names, booking times, and amounts.

---

## 8. Decision Log

For traceability. Every substantive choice in this document, in the order it was made.

**Round 1 — core logic (11 decisions):** booking reorder to provider-commits-before-payment via time-slot publishing (yours, refined into §1c's slot/request/emergency split) · `agreedAmount` added · dispute given an exit + admin resolution · completion decoupled from sole provider control · completion-count trial trigger dropped · trial starts at first booking (later refined to first *confirmed* booking) · `lifecycleStatus` made derived, not stored · billing pause fixed to provider level · `boosted_placement`/`search_boost` naming collision noted for resolution when ads return post-v1 · idempotency added to money/creation paths.

**Round 2 — product design (4 decisions):** role switcher for the provider dashboard · launch-mode Home for a thin catalogue · accessibility criteria moved into Phase 1 · wizard reframed around required-fields-remaining.

**Round 3 — v2 review, booking model (4 decisions):** category-bifurcated booking mode, Tuition removed · emergency bypasses slots · pre-booking enquiry restored, in-app, service-details-allowed · payment timeout escalates instead of auto-confirming.

**Round 4 — v2 review, monetization & infra (4 decisions):** referrals cut · badge decoupled from subscription · push moved to an early phase with a fallback · 24-hour accept timeout.

**Round 5 — pricing, verification, remaining gaps (4 decisions):** MVR 150/month pinned · pause resumes remaining time, and the same rule extends to the trial period · identity verification = ID + trade proof, admin manual review · downgrade preserves confirmed future bookings + recurring bookings + response-time fallback added to v1 scope; admin hardening and data-export redaction explicitly left out.

**Not yet decided:** the five items in §6, most notably the trial-start-trigger question and the per-category `bookingMode` table.
