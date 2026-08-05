# RaajjePro — Adversarial Design Review (Round 2)

Reviewed: `01_Development_Plan_v2.md`
Date: 2026-08-03
Posture: skeptical, including toward the changes made in v2.

**Not available:** the Foundational Project Blueprint, the mockups, `02_Cursor_Prompts.md` (not yet updated to v2), and the rules/skills files (deliberately not updated).

**Framing:** v2 resolved most of round 1's findings. This round focuses on (a) what survived, and (b) **problems v2 created**, which is where the interesting material is. Several of the fixes traded one class of problem for another.

---

## 1. Core Logic Review

### 1.1 🔴 The time-slot model doesn't fit most of the service categories

This is the most serious finding in this review, and it comes directly from the v2 change.

Your 12 categories: Cleaning, Plumbing, Electrical, AC Repair, Tuition, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events.

Pre-published fixed-duration slots work well for **Tuition, Beauty, Fitness** — appointment-shaped services with predictable duration.

They fit badly or not at all for:

| Category | Why slots break |
|---|---|
| **Plumbing / Electrical / AC Repair** | Duration is unknown until diagnosis. A callout is 30 minutes or 4 hours. |
| **Moving** | Half-day to full-day, size-dependent. |
| **Events / Photography** | A wedding is 8–12 hours, booked months ahead, negotiated. |
| **Cleaning** | Duration scales with property size. |
| **Gardening / Computer** | Variable, often multi-visit. |

**The mechanical consequence:** Phase 9a fixes slot duration per listing. A plumber publishing 1-hour slots gets booked at 10:00 and 11:00 for a job that takes three hours. The `UNIQUE (providerId, listingId, startsAt)` constraint guarantees no two bookings share a *slot* — it does not guarantee no two bookings share the provider's *actual time*. **The double-booking guarantee is real at the database level and illusory in practice** for roughly two-thirds of your catalogue.

**Two further contradictions this creates:**

- **`emergencyService` becomes incoherent.** The Listing entity has an emergency-service toggle. An emergency by definition does not fit a slot published last Tuesday. There is now no booking path for the single most valuable, highest-urgency job type in plumbing and AC repair — the exact jobs where a customer will reach for whatever channel works fastest, which is Viber.
- **The constraint is scoped to `(providerId, listingId, startsAt)`** — per listing. A provider with three listings can be booked at 10:00 on all three simultaneously.

**Why it matters:** slot-blocking is now load-bearing for three separate things — double-booking prevention, the pre-payment provider-accept step, and platform-leakage control. If the model doesn't fit the service, all three degrade together.

### 1.2 🔴 Auto-confirm on provider silence grants payment attestation to a non-response

Phase 17 auto-advances `payment_claimed → confirmed` after 7 days of provider silence, and `confirmed` sets `paymentAttestedAt` and unlocks contact info both ways.

Consider: a customer books, taps "I've Paid" without paying, and the provider is travelling, ill, or simply doesn't see the prompt. Seven days later the system has recorded a payment attestation that never happened, unlocked the provider's phone number, and made the booking eligible to proceed to completion and review.

**Silence is being read as consent on the one action in the system that involves money.** That is strictly worse than the indefinite limbo it was designed to fix. The same objection applies to auto-completion opening review eligibility for a job that may never have occurred.

**Recommendation:** on timeout, escalate rather than confirm — move to `unresolved`, notify both parties, surface in the moderation queue, and unlock nothing.

### 1.3 🟠 `requested` has no timeout, and it holds the slot hostage

The slot is reserved the moment a booking enters `requested`. There is **no deadline on the provider's accept step** — I specified a timeout from `payment_claimed` onward and left this earlier transition open.

A provider who never responds locks that slot indefinitely. No other customer can book it, and the original customer waits with no signal. For a provider who has abandoned the app entirely, every slot they ever published becomes permanently unbookable one request at a time.

**Recommendation:** auto-decline and release the slot after 24–48 hours of no provider response.

### 1.4 🔴 Referral credit is farmable at zero cost

MVR 50 credit per referred user who *completes a booking*. Completing a booking requires: a booking request, a provider accept, a customer "I've Paid", and a provider "Payment Received."

**All four actions are free, and the payment is off-platform — so nothing has to actually happen.** One person with two accounts (or a friend) can manufacture completed bookings against their own listing indefinitely. Each cycle costs nothing and yields MVR 50 against their subscription.

This is not a theoretical exploit. It is the cheapest possible attack on the only credit-issuing mechanism in v1, and off-platform payment is precisely what makes it unverifiable.

Secondary issue: referral credit is **stored value on your balance sheet**, which reopens the Maldives Monetary Authority question that deferring the credit wallet was meant to close.

### 1.5 🟠 The badge now means "verified and currently paying"

v2 gates the Verified badge on identity verification **and** an active premium subscription. A provider who passed a background check and then let their subscription lapse loses the badge while remaining exactly as verified as before.

Customers will read that badge as a safety signal — that is what "Verified Provider" means in every marketplace they've used, and your own Home mockup lists it under a Trust grid alongside Real Reviews and Secure Messaging.

**You are selling a trust signal.** A less-safe-looking provider is not less safe; they are less current on a bill. That is a trust-integrity problem, plausibly a consumer-protection one, and it undermines the badge's value for the providers who *do* pay, since the signal no longer means what it says.

**Recommendation:** badge tracks identity verification only. Sell placement, listings, and analytics — not safety.

### 1.6 🟠 The trial may never fire for most providers

Trial now starts on the provider's **first confirmed booking** — a genuine improvement over first publish. But it has an unintended consequence: a provider who publishes and receives no bookings never starts a trial, never experiences premium, and therefore never has a reason to buy it.

At launch, when the catalogue is thin and demand is thin, that describes most providers. The trial is now so well-targeted it may not trigger.

It also creates a second problem: a provider cannot start their own trial, and you cannot demo premium to a prospect, because trial start is gated on a *customer* action.

**Recommendation:** trial starts on first confirmed booking **or** on explicit provider request (a "Try Premium" button), whichever comes first.

### 1.7 🟠 A completed booking that never happened inflates the provider's stats

Auto-completion at 7 days past the scheduled date marks a no-show booking `completed`. That feeds `jobsCompletedCount`, the provider's public stats, and any trending heuristic derived from completions.

**A provider who never turns up gets credit for the job.** The customer can leave a bad review, which partly offsets it, but the completion count — displayed publicly as a competence signal — is simply wrong.

### 1.8 🟡 Downgrade hides a listing that may have confirmed future bookings

On downgrade, listings beyond the free cap are hidden. Nothing says what happens to **confirmed bookings against a hidden listing**, or to its reserved future slots. The customer has paid, attested, and holds contact details for a job against a listing that no longer publicly exists.

### 1.9 🟡 Slots that pass unbooked have no lifecycle

No rule covers a slot whose time has passed without a booking. They accumulate. `open` slots in the past must be excluded from every query, and ideally reaped by the Phase 0 job runner.

### 1.10 🟡 Per-listing pricing vs. provider-level availability is an odd split

v2 made pricing granular (per listing) and availability coarse (one provider-level `acceptingNewCustomers`). Both choices are individually defensible, but a provider who wants to pause only their weekend photography work while continuing tuition cannot.

---

## 2. Product Design Review

### 2.1 🔴 There is now no way to ask a question before committing

This is the sharpest regression in v2, created by two decisions interacting:

- Messaging is **booking-scoped only** (12.1)
- **No chat before `accepted`** (part of the contact-free accept prompt)
- The pre-booking **Message button was removed** from Service Preview as a consequence

So the customer journey is: find a listing → **book a specific time slot** → wait → provider accepts or declines. There is no point at which either party can ask a question.

Concretely: a customer needs AC repair. The provider needs to know the brand, whether it's a split unit, which floor, whether there's parking, whether parts are likely needed. The customer needs to know whether the provider covers their island, works on that brand, and what it roughly costs.

**Neither can ask.** The provider must accept blind — and on acceptance they commit to an `agreedAmount`. For quote-priced listings this is worse still: the provider must produce a binding quote with zero ability to clarify.

The predictable outcomes: providers decline a lot, customers cancel a lot, slots churn, and both parties conclude the app is friction and reach for Viber — which is exactly the leakage the design exists to prevent.

**Recommendation:** allow a pre-booking enquiry thread that is contact-masked (in-app only, no numbers, no attachments) and does not require a slot. It preserves the leakage control while restoring the conversation the transaction actually needs. Alternatively, add a structured pre-booking Q&A on the listing so the provider can answer common questions once.

### 2.2 🟠 "Push cannot be disabled" is not enforceable

v2 makes push required and non-optional because provider accept is load-bearing on it. Both iOS and Android let the user deny or revoke notification permission at OS level regardless of app preference. A meaningful share of users will deny on the permission prompt.

So the flow's critical path depends on a signal the platform does not let you guarantee. There is no fallback specified, and an app that requires notifications to function may draw App Store review attention.

**Recommendation:** detect denied permission, warn providers explicitly that they will miss booking requests, and add a fallback (SMS on accept-prompt timeout, or a forced email) for providers with push off.

### 2.3 🟠 Booking a time slot is a heavier first action than the market will bear

The customer's first commitment is now picking a specific date and time — before any contact, any question, any price confirmation. On Facebook, the first action is typing "do you fix Daikin ACs in Hulhumalé?"

Slot-first is right for tuition and salons. It's wrong for the diagnostic trades, and it compounds §2.1.

### 2.4 🟡 Response time is displayed publicly but is barely measurable

v2 surfaces a response-time metric on listings and profiles. But with messaging booking-scoped and no pre-booking contact, the only measurable signal is how fast a provider responds to accept prompts. A new provider has no bookings and therefore no metric — and a blank or "no data" reads worse to a customer than a slow number.

### 2.5 🟢 What v2 genuinely fixed

Worth recording, because these were real: accessibility is now a Phase 1 requirement with specific criteria rather than absent; cold-start Home exists; offline write-queuing protects the wizard; the role switcher surfaces the paying user's workspace; the wizard leads with required-fields-remaining; account deletion, data export, session management, and in-app credential changes all exist. That's a substantial product-quality improvement over v1.

---

## 3. Feature Gap Analysis

Most of round 1's gaps are closed. What remains:

| Gap | Severity | Note |
|---|---|---|
| **Pre-booking enquiry** | 🔴 | See §2.1. The single largest remaining feature hole. |
| **Emergency / same-day booking path** | 🔴 | `emergencyService` exists as a listing flag with no booking flow that can serve it. |
| **Variable-duration / multi-slot booking** | 🟠 | No way to book "a half day" or "three consecutive hours". |
| **Recurring bookings** | 🟠 | Weekly cleaning and weekly tuition are the two highest-retention use cases in this catalogue, and each requires re-booking from scratch every week. |
| **Provider absence / holiday mode** | 🟡 | Slot blocking by range exists in 9a; there's no single "away until X" that also communicates to customers. |
| **Saved payment instructions per provider** | 🟡 | Captured in Phase 5, but no customer-side "how do I pay this provider" history. |
| **Admin: manual booking intervention** | 🟡 | Admins can resolve disputes but cannot correct a wrong state (e.g. release a hostage slot from §1.3). |
| **Support ticketing** | 🟡 | Phase 24 adds a contact link. With disputes, payment rejections, and appeals all routing to humans, a link to WhatsApp is thin. |
| **Feedback mechanism** | 🟢 | Still none. |

---

## 4. Technical Architecture Review

### 4.1 🟠 Phase 19 is a prerequisite for Phase 17 and still numbered after it

v2 notes this in the sequencing section and does not fix it. The provider accept prompt — the load-bearing moment of the entire booking flow — depends on push delivery built two phases later. "Accept that Phase 17 is untestable end-to-end until 19 lands" is not an acceptable resolution for the core loop.

**Recommendation:** split a Phase 2b — Push Infrastructure (FCM/APNs, device token registration, a send abstraction) — and leave notification types, the centre screen, digests, and analytics in Phase 19.

### 4.2 🟠 Slot generation is unspecified in the dimension that matters

Phase 9a says slots are "generated from the listing's availability rules (days, business hours, service duration) with individual override." It never defines:

- how far ahead slots are generated (a rolling window? how long?)
- who regenerates them and when (job? on-write? on-read?)
- what happens to existing bookings when a provider edits their availability
- whether the generation job is idempotent

This is a table that grows monotonically per provider per listing and is queried on the hot path of every listing view. It deserves an explicit design.

### 4.3 🟡 Data export returns other people's data

`GET /v1/users/me/data-export` returns "the user's own data as JSON." For a provider, that includes bookings — which contain customer names, scheduled times, and amounts. A provider's export is a customer list.

**Recommendation:** define the export schema explicitly and redact counterparty PII.

### 4.4 🟡 Account deletion leaves bookings half-anonymous

Anonymising authored content is right. But a booking has two parties. When a customer deletes, the provider's history shows a counterparty-less booking, and `GET /v1/bookings/:id/contact-info` on a confirmed booking with a deleted user is undefined.

### 4.5 🟡 The `(providerId, listingId, startsAt)` constraint is scoped too narrowly

Per §1.1 — it should be `(providerId, startsAt)` to prevent a provider being booked simultaneously across their own listings.

### 4.6 🟢 Genuinely improved

UUIDs, integer laari, soft-delete convention, idempotency middleware, real job runner, rate-limit tiers, event-log rollup replacing hot-path counters, real admin identity with an audit log, private proof storage with EXIF stripping, CSP and output encoding on the admin app. This is a materially stronger technical foundation than v1.

---

## 5. Security Review

### 5.1 🟠 Single admin role, single reviewer, no coverage plan

v2 chose a single `admin` role and single-reviewer confirmation, both reasonable for v1 simplicity. Combined, they mean: **one compromised or careless admin account can grant entitlements, hide any content, resolve any dispute, and reverse any payment**, with the audit log as the only control — and audit logs are detective, not preventive.

There is also no staffing plan behind the 48-hour SLA. The entire revenue path has a bus factor of one, with no weekend or illness coverage defined.

### 5.2 🟠 Referral farming — see §1.4

The only credit-issuing mechanism in v1 is exploitable at zero cost by a single person with two accounts.

### 5.3 🟡 MFA deferred on the account that approves money

Documented as post-v1. Worth reconsidering: TOTP on a handful of admin accounts is a few hours of work and removes the highest-value credential-theft target in the system.

### 5.4 🟡 Admin panel shares an origin and network path with the public API

Network segregation is deferred. At minimum, an IP allowlist on `/v1/admin/*` costs nothing.

### 5.5 🟢 Substantially improved

Real admin auth, audit trail, UUIDs closing the enumeration surface, OTP send limits with a pinned SMS provider, global and per-endpoint rate limits, private proof bucket, EXIF stripping, server-side upload validation, CSP and output encoding. Round 1's security score was driven by stubbed admin auth across every money endpoint; that is now resolved.

---

## 6. Business Review

### 6.1 🔴 The competitive question is still unanswered — and v2 made the comparison harder

Round 1 raised this and v2's §7 acknowledges it honestly without resolving it. But v2's changes actively increase customer-side friction:

**Facebook:** type a question → get a number → call.
**RaajjePro v2:** register → verify phone via OTP → find listing → **pick a specific time slot with no ability to ask anything first** → wait for provider acceptance → pay off-platform → tap "I've Paid" → wait for provider confirmation → *then* get a phone number.

Seven steps and two waits, versus one message. Every step was individually justified. Collectively they describe a product that is harder to use than the free alternative, for a customer who receives no benefit from the monetisation the friction protects.

**This remains the single largest risk to the product, larger than anything technical in this document.**

### 6.2 🟠 Deferring credits and ads was right; the remaining product may be too thin to sell

With 8b and 8c cut, premium is: multiple listings, analytics + weekly digest, priority placement, badge eligibility.

- Multiple listings — irrelevant to a solo tradesperson, who is your modal provider
- Priority placement — worth little in a thin catalogue
- Analytics — now genuinely defined (Phase 19), which is a real improvement
- Badge — the clearest value, and §1.5 argues it shouldn't be sold

Strip the badge on trust grounds and premium is analytics plus placement. **That may not sustain MVR 150–200/month.** The honest question is whether v1 should monetise at all, or run free to build density and introduce pricing once the marketplace demonstrably delivers work.

### 6.3 🟡 Trial-on-first-booking may never trigger — see §1.6

---

## 7. AI-Specific Review

Not applicable. No AI component.

---

## 8. Edge Cases

**Slots and booking**
- Provider edits availability while bookings exist against generated slots.
- Provider changes a listing's slot duration; existing slots are now inconsistent.
- Customer books the last slot; provider declines; slot returns — to whom, and is anyone told?
- Two listings, same provider, same time (§4.5).
- DST — not applicable (UTC+5, no DST), a genuine simplification. Ramadan hours still need the range-blocking in 9a.
- A slot exists but the provider's `acceptingNewCustomers` is off — is it bookable?

**Payment and trial**
- Customer taps "I've Paid" and immediately deletes their account.
- Provider's first confirmed booking is later disputed and resolved against them — does the trial, started by that booking, roll back?
- Downgrade hides the listing holding a confirmed future booking (§1.8).
- Referral credit exceeds the subscription price — is the balance carried, refunded, or lost?

**Identity and access**
- Provider passes verification, subscription lapses, badge disappears, customer who booked partly on that badge now sees an unbadged provider mid-booking.
- Push permission denied at OS level (§2.2).
- Provider blocks a customer with whom they have a confirmed booking — does contact info stay visible?

**Data**
- Provider exports data containing customer PII (§4.3).
- Both parties to a booking delete their accounts.

---

## 9. Missing Requirements

**Functional:** pre-booking enquiry; emergency/same-day path; variable-duration and multi-slot booking; recurring bookings; `requested` timeout; admin booking-state intervention; slot generation window and regeneration policy; referral abuse controls; export schema with counterparty redaction.

**Non-functional:** still no stated p95 latency, cold-start target, availability target, or supported-device matrix. Backup RPO/RTO now referenced in Phase 24 but not given values.

**Security:** admin MFA; admin IP allowlist; admin staffing and coverage; referral fraud detection.

**Compliance:** the four Phase 23 research questions remain open and are correctly flagged; referral credit adds a fifth (stored value).

**Operational:** no runbook; no on-call; no defined admin coverage behind the 48-hour SLA.

---

## 10. Development Risks

**Highest risk is now Phase 9a + 17 together.** Slots are new, load-bearing for three separate concerns, unfit for most of the catalogue as designed (§1.1), and feed the largest phase in the plan. Getting the slot model wrong invalidates the booking flow, the leakage control, and the double-booking guarantee simultaneously.

**Second: the payments + admin stack.** Improved substantially, but still a second codebase, single-role and single-reviewer, with a bus factor of one and a farmable credit mechanism.

**Timeline:** the plan is roughly flat despite cutting two phases — 9a was added and several phases grew. Still 3–6 months solo.

**Reduced risk vs. v1:** SMS provider now pinned before Phase 3; the six open questions are explicitly registered rather than scattered; agent-delegated decisions are fewer.

---

## 11. Prioritized Recommendations

### 🔴 Critical — resolve before Phase 9a or 17

1. **Redesign the slot model** to accommodate variable-duration and emergency services, or explicitly scope v1 to appointment-shaped categories only (§1.1).
2. **Restore a pre-booking enquiry channel**, contact-masked (§2.1).
3. **Replace auto-confirm-on-silence with escalation** (§1.2).
4. **Add an emergency / same-day booking path**, or remove `emergencyService` from the listing model (§1.1, §3).
5. **Fix referral farming**, or cut referrals from v1 (§1.4).
6. **Decouple the badge from subscription** (§1.5).

### 🟠 High Priority

7. Add a `requested` timeout that releases the slot (§1.3).
8. Split Phase 2b — Push Infrastructure, ahead of Phase 17 (§4.1).
9. Add a push-denied fallback and warn providers explicitly (§2.2).
10. Broaden the uniqueness constraint to `(providerId, startsAt)` (§4.5).
11. Trial also startable on explicit provider request (§1.6).
12. Don't count auto-completed no-shows toward `jobsCompletedCount` (§1.7).
13. Specify slot generation window, regeneration policy, and edit-with-existing-bookings behaviour (§4.2).
14. Define what happens to bookings against a hidden-over-cap listing (§1.8).
15. Add admin MFA and an IP allowlist (§5.3, §5.4).
16. Define admin staffing behind the 48-hour SLA (§5.1).
17. Redact counterparty PII from data export (§4.3).

### 🟡 Medium Priority

18. Multi-slot / variable-duration booking. 19. Recurring bookings. 20. Slot reaping for past unbooked slots. 21. Account-deletion handling for the counterparty side of a booking. 22. Response-time metric fallback for providers with no history. 23. Per-listing availability pause. 24. Admin manual booking intervention. 25. Referral credit overflow handling. 26. Stated non-functional targets.

### 🟢 Nice to Have

27. Feedback mechanism. 28. Support ticketing beyond a contact link. 29. Provider holiday mode with customer-facing messaging.

---

## 12. Overall Assessment

| Dimension | v1 | v2 | Driver |
|---|---|---|---|
| **Architecture** | 7 | **8** | UUIDs, money type, soft-delete, idempotency, real job runner, event-log rollup, real admin identity. Docked for the slot model and Phase 19 ordering. |
| **Product design** | 5 | **6** | Real gains: a11y, cold start, offline, IA, wizard framing. Offset by the pre-booking communication dead zone and a slot model that fits perhaps a third of the catalogue. |
| **Scalability** | 8 | **8** | Event-log rollup helps; slots add trivial volume at this market size. Unchanged in substance. |
| **Security** | 4 | **7** | The largest single improvement. Real admin auth, audit log, UUIDs, rate limits, private proof storage, CSP. Docked for no MFA, single role, bus factor of one, and referral farming. |
| **Business viability** | 4 | **5** | Deferring credits and ads was correct and trial timing is better. But the competitive question is unanswered, v2 increased customer friction, referrals are farmable, and premium may now be too thin to sustain its price. |
| **Maintainability** | 7 | **7** | Cleaner conventions and an explicit open-questions register, offset by a larger plan and a new load-bearing subsystem. |

### Assessment

v2 is a **substantially better engineering plan** — security in particular went from the weakest dimension to a reasonable one, and the foundational conventions (UUIDs, money type, soft-delete, idempotency, job runner) are the kind of thing that is nearly free now and very expensive later.

It is **not yet a better product plan**. The slot system solved double-booking and the payment-ordering problem, and in doing so introduced a booking model that doesn't fit most of the catalogue and removed the ability for two people to talk before committing. Those two findings (§1.1, §2.1) are the ones I'd want resolved before any Phase 9a or 17 code exists.

**Recommendation: one more revision pass on the booking and communication model specifically.** Phases 0–8 are ready to build now and nothing in this review blocks them — start there while the booking model is settled.
