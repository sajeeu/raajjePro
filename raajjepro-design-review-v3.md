# RaajjePro — Adversarial Design Review (Round 3, final)

Reviewed: `01_Development_Plan_v3.md`, cross-checked against `02_Cursor_Prompts.md`, `03_Cursor_Rules_Skills_Subagents.md`, `03b_..._v2.md`
Date: 2026-08-03

**Framing:** v3 resolved nearly everything from rounds 1 and 2. This review is therefore almost entirely about **problems v3 created**, plus one document-set problem that is now the most urgent practical issue in the project.

**Not available:** the Foundational Project Blueprint, the mockups, `04_Cursor_Best_Practices.md`.

---

## 0. The most urgent finding: the document set is now incoherent

This is not a design flaw in v3. It is a delivery flaw that will actively produce wrong code, and it outranks everything else here.

**`02_Cursor_Prompts.md` still describes v1's product.** It contains Phase 8b (credit wallet), Phase 8c (advertising), 12 categories including Tuition, the `requested → payment_claimed → confirmed` flow with no provider-accept step, no time slots, no `agreedAmount`, no enquiry threads, and no emergency path. **If you paste Phase 17's prompt from that file, Cursor builds v1's booking flow** — the exact design three rounds of review dismantled.

**The rules files are worse, because they auto-apply.** `03_..._md`'s `000-project-context.mdc` is `alwaysApply: true` and states as non-negotiable invariants:

- **1a:** `lifecycleStatus` is a stored field flipped one-way on first publish — v3 deleted this field entirely in favour of derived visibility (§1a)
- **1b:** credits and ad campaigns exist as monetization — both cut from v1
- **1d:** contact info is hidden until `confirmed`, with no exceptions — v3 added the emergency carve-out

Cursor will enforce these against every generation, in every session, silently. A rule file that contradicts the plan is worse than a stale one: it will actively fight correct code.

**Also:** v3 is a diff, not a spec. Line 262 defers sixteen phases to "unchanged from v2," and v2 in turn defers several to v1. To build Phase 4 correctly you now need three documents open simultaneously and must reconcile them yourself.

**Recommendation, before any other work:** collapse v1/v2/v3 into a single standalone plan, regenerate `02_Cursor_Prompts.md` against it, and rewrite `000-project-context.mdc`'s invariants. Until that's done the planning work is not usable by the tool it was written for.

---

## 1. Core Logic Review

### 1.1 🔴 The emergency path is a one-tap bypass of the entire contact-gating architecture

Emergency bookings (§1c): no slot, no calendar reservation, and **contact info unlocks at `accepted`** — before any payment, any attestation, any money changing hands.

`isEmergency` is available "regardless of `bookingMode`" (line 148). Nothing restricts which listings may offer it.

So the fastest route to a provider's phone number is: find any listing with emergency enabled → submit an emergency request → provider taps Accept → both parties now have each other's numbers → cancel. Cost: zero. Time: minutes.

**And both parties are motivated to do exactly this.** The provider wants the customer off-platform (they're the one being asked to pay MVR 150/month). The customer wants a phone number. The emergency flow hands both of them what they want, with no payment step in between, and there is no penalty for cancelling afterward.

Every provider on the platform can enable emergency on their listing and turn it into a contact-exchange button.

This is the single most consequential finding in this review. §1c's contact gate is the mechanism the business model rests on — it is why a provider would pay rather than just take the work offline. v3 put a documented, sanctioned bypass next to it.

**Recommendations, in order of preference:**
1. **Emergency unlocks contact at `payment_claimed`, not `accepted`.** The customer still attests payment before getting the number, preserving the ordering that matters. For a genuine emergency the customer will happily tap "I've Paid" — they want the plumber.
2. Restrict `isEmergency` to a whitelist of categories (Plumbing, Electrical, AC Repair) and require `verificationStatus: verified` to enable it — raising the cost of using it as a bypass.
3. Rate-limit emergency requests per customer per period, and track accept-then-cancel patterns as a moderation signal.
4. If you keep unlock-at-accept, at minimum make emergency bookings **non-cancellable without a reason that files a Report**.

### 1.2 🔴 The enquiry thread's hard block cannot do what it's specified to do

§1c requires that the pre-booking enquiry thread **hard-reject** phone-number-shaped messages while **explicitly allowing** appliance make, model, and serial numbers.

Maldivian mobile numbers are 7 digits beginning 7 or 9. An air-conditioner serial number is a 7-to-15 digit string. A model number is alphanumeric with digit runs. **These are not reliably distinguishable.** The filter will either be loose enough to pass phone numbers or tight enough to reject the exact content the channel exists to carry — and because the block is *hard*, every false positive is a user-facing failure on the primary pre-sales channel.

Worse: **photos are explicitly allowed** in the same paragraph. A photo of a business card, or a screenshot of a contacts entry, passes trivially. So does "nine seven one two…", or "my number's on my Facebook page."

**The block is therefore both unreliable and circumventable, while creating false confidence** — you'll believe leakage is prevented here when it isn't.

**Recommendation:** make the enquiry thread a **soft nudge with logging**, consistent with Phase 18's booking-scoped conversations, rather than a hard block. Log detections as a moderation signal and act on patterns. A provider who trips the detector on 40 enquiries is visible; the individual message doesn't need to be blocked. This also removes the false-positive failure mode entirely.

### 1.3 🔴 Emergency bookings contradict the `agreedAmount` invariant

Line 194: "No booking leaves `requested`/`quote_offered` without [an `agreedAmount`]."
Line 188: emergency bookings "skip straight from `requested` to `accepted`."

An emergency plumber cannot state a price before seeing the job — that is what makes it an emergency. So emergency bookings either violate the invariant, or require a number the provider cannot produce.

Nothing in §1c or Phase 17 resolves this. Since `agreedAmount` is what the entire downstream attestation references ("Confirm you received MVR X"), an emergency booking with a null or guessed amount breaks the attestation, the dispute record, and the analytics.

**Recommendation:** emergency bookings carry `agreedAmount: null` at `accepted`, and the provider sets it at the point of claiming payment — the customer attests against the amount the provider entered. Requires an explicit extra state or an amount-setting step, but keeps the invariant honest.

### 1.4 🟠 Emergency bookings have no `scheduledFor`, so they never auto-complete

The completion timeout (line 316) fires "7 days past `scheduledFor`." Emergency bookings have no slot and no window — `scheduledFor` is null by construction.

Therefore an emergency booking that the provider never marks complete **sits in `confirmed` indefinitely**. Review eligibility never opens. The provider can permanently block reviews of emergency work simply by not pressing the button — which is precisely the loophole §1c's completion redesign was built to close, still open for one booking type.

**Recommendation:** set `scheduledFor` to the acceptance timestamp for emergency bookings, so the same 7-day clock applies.

### 1.5 🟠 The 24-hour accept timeout is wrong for emergencies and mis-specified for quotes

**For emergencies:** a 24-hour auto-decline is meaningless when a pipe has burst. Emergencies need a response window measured in minutes, with fast escalation to another provider or an explicit "no one is available" outcome. v3 applies one flat 24-hour rule to all three booking modes.

**For quotes, the job is specified incorrectly.** Line 309: *"auto-decline `requested`/`quote_offered` bookings 24 hours after creation with no provider response."*

But `quote_offered` means the provider **has** responded — the state is waiting on the *customer*. As written, the job would auto-decline quotes the customer hasn't had time to review, 24 hours after booking creation, including a quote the provider submitted at hour 23. The condition conflates "no provider response" with a state that exists only because the provider responded.

**Recommendation:** three separate timeouts — emergency accept (minutes), standard accept (24h), and customer quote-approval (its own clock, starting when the quote is offered).

### 1.6 🟠 Request-based quote approval can reserve a time that's already gone

For request-based bookings, the calendar reservation is created **on customer approval** (line 143), not when the quote is offered. Between offer and approval, nothing holds the time.

So: provider quotes Tuesday 2pm to customer A, then accepts a slot booking for Tuesday 2pm from customer B. Customer A approves. The `UNIQUE (providerId, listingId, startsAt)` constraint rejects the insert, and customer A gets a database error after agreeing to a price.

**Recommendation:** hold a provisional reservation when the quote is offered, expiring with the quote's approval window.

### 1.7 🟠 Pause and calendar billing are incompatible

§1b pins "calendar billing" (line 20) and simultaneously specifies that pausing "picks up where it left off," preserving remaining paused time.

If a provider pauses four days, their period end shifts four days. Their next billing date is now the 5th, not the 1st. After several pauses, every provider is on a different anchor date and "calendar month" no longer describes anything.

Separately: **the pause mechanism is disproportionate to its value.** Ten cumulative days out of a 60-day trial, or out of a monthly subscription, is a rounding error — but it requires shared state across two lifecycle states, a cumulative counter, a forced-resume job, and interaction with `acceptingNewCustomers`. That is a lot of surface for ~3% of a billing period.

**Recommendation:** either drop pause from v1 entirely, or switch to anchor-date billing (bill on day N of each period, where N shifts with pauses) and stop calling it calendar billing.

### 1.8 🟠 Two paths reach `confirmed`, and only one fires the trial hook

Line 311: the trial-start hook fires from `confirm-payment-received`.
Line 314: an admin resolving `payment_unresolved` can also move a booking to `confirmed`.

The admin path does not fire the hook. A provider whose first-ever confirmed booking arrived via admin resolution never starts their trial.

**Recommendation:** move the hook to the state transition into `confirmed`, not to one endpoint.

### 1.9 🟡 Recurring series die silently on a missed accept

Each occurrence requires individual provider acceptance (line 212), and unaccepted bookings auto-decline at 24 hours (line 195). A provider who misses one week — travel, illness, a busy day — has that occurrence auto-declined. Nothing specifies whether the series continues, pauses, or terminates, or what the customer is told.

A weekly cleaning customer will reasonably read one auto-declined week as "this is cancelled."

### 1.10 🟡 Recurring bookings lost most of their use case with Tuition

Recurring is restricted to slot-based listings — Cleaning, Beauty, Fitness. Weekly tuition was the strongest recurring use case in the original catalogue and it was removed in the same revision that added recurring bookings. What remains is essentially weekly cleaning.

Worth confirming this feature still earns its place in v1.

### 1.11 🟡 `bookingMode` seeding is a dangling reference

Line 280 says the `bookingMode` lookup table is "seeded in Phase 4." Line 262 says Phase 4 is unchanged from v2 apart from the category count. Phase 4's actual specification therefore does not include this seed.

### 1.12 🟡 "15000 laira" (line 286)

The unit is *laari*. The value is right; the spelling is wrong in the one place a constant gets copied from.

---

## 2. Product Design Review

### 2.1 🟠 Customers can't tell which booking experience a listing will give them

Some listings open a slot picker; others open a request-a-window form; some also offer an emergency toggle. Nothing in search results, category grids, or Home cards indicates which. A customer expecting to pick a time gets a form, or vice versa.

**Recommendation:** surface it as a card-level affordance — "Book instantly" vs. "Request a time" — which is also a genuine differentiator worth showing.

### 2.2 🟠 The enquiry thread's rejection message will read as the app being broken

Given §1.2's false-positive problem, a customer who types their AC's serial number and is told *"For your safety, contact details can't be shared"* will conclude the app is malfunctioning — because it is. This is on the primary pre-sales path, at the moment of highest intent.

### 2.3 🟡 The multi-listing benefit arrives at the worst moment

Free tier is one listing. Trial (full premium, including multiple listings) starts at the first *confirmed booking*. So a provider is capped at one listing throughout their entire pre-demand period, and gains the ability to publish more at precisely the moment they're occupied with an actual job.

### 2.4 🟡 No win-back path for a downgraded provider

Downgrade hides listings and disables analytics. Nothing re-engages that provider afterward — no "your hidden listings are still here" email, no reactivation offer. The notification list has `downgraded_to_free` and nothing beyond it.

### 2.5 🟢 What v3 genuinely fixed

The slot/request bifurcation resolves round 2's biggest finding properly rather than papering over it. The enquiry thread restores the pre-booking conversation. Escalating instead of auto-confirming on payment silence is the right call and correctly reasoned. The "did this happen?" completion prompt with `completedVia` tagging is a better design than either auto-completing or leaving it open. Cutting referrals was correct. Decoupling the badge from subscription was correct on trust grounds.

---

## 3. Feature Gap Analysis

| Gap | Severity | Note |
|---|---|---|
| **Emergency dispatch / fallback** | 🟠 | If the one emergency provider doesn't answer in 20 minutes, there is no path to the next one. An emergency feature without escalation is a promise the platform can't keep. |
| **Booking-mode indicator in discovery** | 🟠 | §2.1. |
| **Recurring series lifecycle handling** | 🟡 | §1.9. |
| **Provider win-back** | 🟡 | §2.4. |
| **Enquiry thread lifecycle** | 🟡 | What happens to an enquiry thread when its listing is hidden by downgrade or soft-deleted? Unspecified. |
| **Feedback mechanism** | 🟢 | Still absent across all three revisions. |

Everything else flagged in rounds 1 and 2 is now either scoped, deferred with a written reason, or explicitly declined in §7. That list is in good shape.

---

## 4. Technical Architecture Review

### 4.1 🟠 The uniqueness constraint is still listing-scoped

`UNIQUE (providerId, listingId, startsAt)` (line 136, carried from v2). Round 2 flagged that this should be `(providerId, startsAt)` — a provider with three listings can still be booked three times at 10:00.

v3 partially addresses this in prose (line 143: request-based reservations use "the identical underlying reservation mechanism… so a provider can't be double-booked across their slot-based and request-based listings") but the stated constraint doesn't enforce it. Prose intent, database permissiveness.

**Recommendation:** the reservation table needs a provider-scoped exclusion constraint on the time range, not a listing-scoped uniqueness on a start timestamp. PostgreSQL's `EXCLUDE USING gist` with a `tstzrange` handles overlapping durations correctly, which a `startsAt` equality check does not — two 10:00 and 10:30 bookings of one-hour jobs don't collide under the current constraint at all.

### 4.2 🟠 SMS fallback timing is unspecified and probably useless as implied

Phase 3c: fall back to SMS "if push is denied or fails to deliver within the acceptance window." The acceptance window is 24 hours. An SMS sent at hour 23 arrives just before auto-decline.

**Recommendation:** send the SMS fallback immediately on push-denied state (known in advance, not discovered), and at a fixed short interval (say 30 minutes) on delivery failure. Also specify SMS content — booking details only, no links, to avoid training providers to tap links in texts.

### 4.3 🟡 The emergency unlock is irreversible in practice

Contact-info visibility is a live query, so cancelling an emergency booking revokes API access to the number. Both parties already have it. Worth stating plainly in the design so nobody treats revocation as meaningful.

### 4.4 🟢 Unchanged and still sound

UUIDs, integer laari, soft-delete, job runner, idempotency keys, rate-limit tiers, event-log rollups, private proof storage with EXIF stripping, real admin identity with audit log, CSP and output encoding on the admin app. This foundation has held up across three reviews.

---

## 5. Security Review

### 5.1 🔴 The emergency path is an authorization bypass by design

§1.1. The system's most sensitive data — the contact details every other endpoint is forbidden from returning — is released on an unpaid, unverified, self-declared "emergency" that any user can initiate against any listing that has the flag enabled.

Framed as a security finding rather than a product one: you have one gated resource, one endpoint that releases it, and a second path to that endpoint with materially weaker preconditions and no rate limit.

### 5.2 🟠 The rules files now contradict the plan and auto-apply

§0. `alwaysApply: true` invariants asserting a deleted field, cut features, and a superseded contact rule will be enforced on every Cursor generation.

### 5.3 🟡 Admin hardening remains deferred by choice

Recorded in §7 of the plan and correctly framed there. Restating the residual risk once: single role, single reviewer, no MFA, no IP allowlist, no staffing plan behind a 48-hour SLA, on the account that grants entitlements, hides content, resolves disputes, and now also approves identity verification (§1e) — which makes that account the arbiter of the platform's only real trust signal.

### 5.4 🟡 Identity verification adds a sensitive-document store with no stated handling

§1e now collects national IDs and passports. The plan specifies who reviews them but not: which bucket they live in, retention period after a verification decision, whether they're purged on account deletion, or who besides the reviewing admin can retrieve them. Payment proofs got explicit private-bucket treatment; ID documents are strictly more sensitive and got none.

---

## 6. Business Review

### 6.1 🟠 Two round-5 decisions interacted badly: premium may now have nothing compelling in it

Round 2 identified the badge as the clearest value in the premium bundle. Round 5 correctly decoupled the badge from subscription on trust grounds — and pinned the price at MVR 150 in the same round.

What premium now contains: multiple listings (irrelevant to a solo tradesperson, who is the modal provider), priority placement (worth little in a thin catalogue), and analytics (genuinely defined now, but a weekly digest is a thin anchor for a recurring charge).

Each decision was individually right. Together they removed the one item most likely to sell the bundle without adjusting anything else. **The conversion case for premium is weaker in v3 than it was in v2.**

**Options:** price lower for v1 and raise later; make identity verification itself a paid one-time service (separating "we checked this person" — a real cost you incur — from the recurring bundle); or accept that v1 monetization is nominal and the goal is density, not revenue.

### 6.2 🟠 The competitive question is unanswered across all three reviews

Unchanged and worth stating once more, because it hasn't moved: nothing in the plan says why a provider or customer leaves Facebook groups and Viber. v3 improved the customer journey (enquiry restored, booking modes fit the services) but the fundamental comparison — one message versus register/verify/enquire/book/wait/pay/attest — is still unfavourable, and the emergency bypass (§1.1) means the platform's answer to leakage now has a hole in it that both parties benefit from using.

### 6.3 🟡 Emergency is a brand promise the platform can't yet keep

Offering emergency booking with a single-provider request and no dispatch fallback (§3) means a customer with a flooding bathroom may get silence. Emergency failures are the ones people tell others about.

---

## 7. AI-Specific Review

Not applicable — no AI component in v1. The post-v1 backlog's automated image moderation would introduce one; scope it properly if it's picked up.

---

## 8. Edge Cases

**Emergency**
- Emergency accepted, contact exchanged, customer cancels immediately — no penalty, no record beyond the cancellation.
- Emergency booking never completes (§1.4) — no `scheduledFor`, no auto-complete, no review.
- Multiple emergency requests to several providers simultaneously; all accept; customer takes one. Three providers now hold the customer's number.
- Emergency on a Beauty or Fitness listing — permitted today, semantically meaningless.

**Quotes and requests**
- Quote offered at hour 23; auto-decline job fires at hour 24 (§1.5).
- Quote approved after the slot was sold to someone else (§1.6).
- Customer's preferred window has already passed by the time the provider quotes.

**Recurring**
- One occurrence auto-declines; series state undefined (§1.9).
- Provider's `acceptingNewCustomers` turns off mid-series.
- Series outlives the provider's subscription; listing gets hidden on downgrade — but is protected only if a booking is already `accepted` (§1b), and future series occurrences aren't yet bookings.

**Billing**
- Pause taken twice in one period; billing anchor drifts (§1.7).
- Trial paused, then the provider's only listing is hidden by an unrelated downgrade.

**Enquiry**
- Serial number rejected as a phone number (§1.2).
- Photo of a business card accepted (§1.2).
- Enquiry thread on a listing that's since been hidden or deleted.

---

## 9. Missing Requirements

**Functional:** emergency response window and dispatch fallback; emergency `agreedAmount` handling; emergency `scheduledFor`; separate quote-approval timeout; provisional reservation on quote offer; recurring-series failure semantics; booking-mode indicator in discovery; ID-document retention and access policy; enquiry-thread lifecycle on listing removal.

**Non-functional:** still no stated p95 latency, cold-start target, availability target, or supported-device matrix across any revision. RPO/RTO referenced in Phase 24, values still unstated.

**Security:** emergency-request rate limiting; ID-document storage handling; the deferred admin hardening.

**Compliance:** the three Phase 23 research questions remain open and correctly flagged. §1e's ID collection may add a fourth — identity-document retention almost certainly falls under whatever Maldivian data-protection framework applies.

**Operational:** no runbook; no on-call; no admin coverage plan behind the 48-hour SLA; no defined process for the identity-verification review queue's turnaround.

---

## 10. Development Risks

**Highest risk: the document set (§0).** Not a design risk — a delivery risk, and the one most likely to cause real waste. Building from stale prompts under contradicting rules produces code matching a superseded design, discovered late.

**Second: Phase 17.** Now carrying three booking modes, five timeout jobs, quote flows, recurring series, reschedule, and dispute/escalation paths. It was already the largest phase in v2; v3 grew it substantially. Strong candidate for splitting — slot-based core first, then request/quote, then emergency, then recurring.

**Third: emergency as a feature.** New surface, weakest preconditions, hardest real-world expectations, and the security hole in §1.1.

**Timeline:** v3 added Phase 3c and grew Phases 17 and 18 while removing 8b/8c's replacements from v2 (already gone). Net roughly flat at 3–6 months solo, with more of it concentrated in the riskiest phase.

---

## 11. Prioritized Recommendations

### 🔴 Critical — before any Phase 9a/17 code

1. **Regenerate `02_Cursor_Prompts.md` and rewrite the `000-project-context.mdc` invariants** against v3, and collapse v1/v2/v3 into one standalone plan (§0).
2. **Close the emergency contact-unlock bypass** — move the unlock to `payment_claimed`, restrict `isEmergency` by category and verification status, and rate-limit it (§1.1).
3. **Make the enquiry filter a soft nudge with logging, not a hard block** (§1.2).
4. **Resolve `agreedAmount` for emergency bookings** (§1.3).

### 🟠 High Priority

5. Set `scheduledFor` on emergency acceptance so completion timeouts fire (§1.4).
6. Split the accept timeout into three: emergency (minutes), standard (24h), quote-approval (own clock) — and fix the job condition that auto-declines `quote_offered` (§1.5).
7. Provisional reservation when a quote is offered (§1.6).
8. Resolve pause vs. calendar billing; consider dropping pause from v1 (§1.7).
9. Move the trial-start hook to the `confirmed` transition, not one endpoint (§1.8).
10. Provider-scoped range-exclusion constraint instead of listing-scoped `startsAt` uniqueness (§4.1).
11. Specify SMS fallback timing and content (§4.2).
12. Define ID-document storage, retention, and access (§5.4).
13. Emergency dispatch fallback, or drop the emergency promise to "urgent request" framing (§3, §6.3).
14. Revisit premium's contents or price given the badge decoupling (§6.1).

### 🟡 Medium Priority

15. Recurring-series failure semantics (§1.9) · 16. Booking-mode indicator in discovery (§2.1) · 17. Confirm recurring still earns v1 scope (§1.10) · 18. Fix the Phase 4 `bookingMode` seed reference (§1.11) · 19. "laira" → "laari" (§1.12) · 20. Provider win-back path (§2.4) · 21. Enquiry-thread lifecycle (§3) · 22. Stated non-functional targets (§9).

### 🟢 Nice to Have

23. Feedback mechanism · 24. Emergency accept-then-cancel pattern detection as a moderation signal.

---

## 12. Overall Assessment

| Dimension | v1 | v2 | v3 | Driver |
|---|---|---|---|---|
| **Architecture** | 7 | 8 | **8** | Foundations unchanged and still strong. Held flat rather than raised: the reservation constraint doesn't enforce what the prose claims, and several new flows contradict stated invariants. |
| **Product design** | 5 | 6 | **7** | The slot/request split, restored enquiry channel, and escalate-don't-auto-confirm are all genuinely right. Held back by an enquiry filter that can't work as specified and no booking-mode signalling. |
| **Scalability** | 8 | 8 | **8** | Unchanged. Never the constraint at this market size. |
| **Security** | 4 | 7 | **6** | Down from v2. The core posture is unchanged and good, but the emergency path is a sanctioned bypass of the one gated resource in the system, ID documents arrived with no handling policy, and the auto-applied rules now contradict the design. |
| **Business viability** | 4 | 5 | **5** | Better product-market fit in the booking model; offset by premium losing its most compelling item in the same round the price was pinned, and by the emergency bypass undermining the leakage control the model depends on. |
| **Maintainability** | 7 | 7 | **5** | The sharpest drop. v3 is well-organised internally — decision log, flagged judgment calls — but the artifact *set* is now three chained documents plus a prompts file describing a different product plus rule files asserting deleted invariants. |

### Assessment

**The product design is now right.** Three rounds got the booking model to fit the actual services, restored the conversation the transaction requires, and removed every mechanism that manufactured a false record from silence. §1c is a considerably better design than what this started with, and the reasoning behind it is sound.

**Two things stand between this and buildable.**

The first is §0 — the plan is correct and the artifacts Cursor actually reads are not. That is a mechanical fix and should happen before anything else, because every hour of building against stale prompts is wasted.

The second is the emergency path. It was added to solve a real gap, and it does, but as specified it hands both parties a free, sanctioned route around the contact gate — and the contact gate is the reason a provider would pay you instead of taking the work to Viber. Moving the unlock to `payment_claimed` costs almost nothing in customer experience and closes it.

**Recommendation: fix §0 and §1.1–1.3, then build.** Phases 0 through 8 remain ready and nothing here blocks them — start there while the emergency and enquiry details settle. This plan does not need a fourth structural revision; it needs its supporting artifacts regenerated and four specific holes closed.
