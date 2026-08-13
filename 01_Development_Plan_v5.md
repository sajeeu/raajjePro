# RaajjePro — Development Plan (v5.5)

**This document is standalone.** It supersedes `01_Development_Plan.md` (v1) through `_v4.md` entirely. Nothing here defers to an earlier revision — every phase is specified in full. Delete or archive the older plans; they now conflict with this one in ways that will produce wrong code.

Folds in all decisions resolved across thirteen rounds of review, 2026-08-03 to 2026-08-08. Full provenance in **§9 Decision Log**.

**Stack:** Flutter (mobile-first) · TypeScript / Fastify / Prisma / PostgreSQL · REST `/v1` · monorepo.

---

## 0. Read this first

### 0.0 Revision 5.5 — read this before §0.1–0.3

🔧 **Rounds 8 and 9 (2026-08-05) changed decisions that §0.1–0.3 below still describe in their original form.** Those sections are kept as a historical record of how v5 arrived where it did; **where they conflict with anything below, the later section wins.** Four changes are load-bearing enough to state up front:

1. **Verification is three tiers, not a binary flag** (§1e). Bronze / Silver / Gold, replacing `verified`. Emergency capability requires Silver or above. Any statement below that a provider is simply "verified" means Silver+ where emergency is concerned.
2. **There is exactly one contact-info exception, for emergencies** (§1c). §0.2 states the rule as "never, full stop, not even for emergencies." That is no longer true: `POST /v1/bookings/:id/reveal-contact` exists, under seven request-time conditions plus a runtime kill switch, for emergency bookings only. **No other endpoint may return a phone number** — that part of the original rule stands unchanged and is still a testable invariant in Phase 17.
3. **The admin panel is three phases** — 10a (money and identity queues), 10b (accounts, config, search, shell), 10c (ops dashboard).
4. **Subscription price is per-provider** (`subscriptionPriceLaari`, §1b), not the pinned platform-wide MVR 150 that §0 and earlier rounds describe.
5. **Emergency requests broadcast to every eligible provider at once** (Round 12) — the provider states their callout fee when accepting, and the customer accepts or rejects that offer, with a rejection re-broadcasting. Fan-out was previously deferred to post-v1. **Moving** is now emergency-capable with a 120-minute window, the trial is **30 days** not 60, and **admin MFA and session controls are in v1**.
6. **SMS is gone from the entire system, and email replaces it** (Round 11). OTP is sent to email; `requireEmailVerified` replaces `requirePhoneVerified` everywhere the plan previously used it; the Phase 3c fallback ladder is push → email. A phone number is still collected and still unique, but is **no longer verified** — nothing below Bronze proves it belongs to its holder.
7. **Round 10 folded in thirteen further decisions** that had been made but never written down — most consequentially: the emergency `finalAmount` is now **required**, not optional; the `booking` chat opens at **quote offered**, not at `accepted`; and downgrade keeps the **highest-performing** listing, not the most recently updated. Any older statement of those three is superseded.
8a. **Round 15 is the largest revision since v5 itself, and it changes decisions §1b and §1c state in their original form.** Six are load-bearing: **emergency acceptances no longer race** — offers collect for 90 seconds and the customer picks from up to three (§1c); **emergency eligibility is per-category**, `gold` for Electrical and Plumbing and `silver` for AC Repair and Moving, never a flat `silver` (§1c); a **MVR 200 emergency dispatch fee** is the first and only charge to a customer, amending §1b's free-forever rule (§1c); **provider conduct is scored and displayed as objective metrics** with editorial labels explicitly rejected (§1f); **"payment hold" means a locked agreement, not escrow** — RaajjePro still never moves money (§1h); and **phone uniqueness begins at Bronze, not at registration** (§Phase 3).
8. **The email provider is Amazon SES, and bounce handling moves off Phase 3's critical path** (Round 13). SES is the sole transactional email vendor. Because SES will not leave its sandbox until bounce and complaint handling already exists, that work is a **Phase 0–2 prerequisite**, not the Phase 3c task §Phase 3c previously called it. Anywhere below that describes bounce handling as part of Phase 3c, read it as *already built by then*.

### 0.1 Why v5 exists

v4 was reviewed line-by-line against an 82-item interactive checklist covering provider registration and every customer/provider workflow — 77 confirmed, 5 rejected, several more amended in the comments on items marked "Yes." One of those rejections is a genuine architectural change, not a tweak: **no contact information is ever exchanged between customer and provider, at any point, for any booking type.** v4's entire "contact unlocks at `payment_claimed`" mechanism — the thing three prior review rounds spent the most effort getting right — is removed outright and replaced with something simpler. v5 folds that in, along with five smaller product decisions from the same review. `02_Cursor_Prompts.md` and `03_Cursor_Rules_Skills_Subagents.md` have not yet been regenerated against this revision — that's the next step, done separately.

### 0.2 What changed from v4

Six decisions from the checklist review on 2026-08-04:

1. **Contact information is never shared, full stop.** Not "later," not "after payment," not "except for emergencies" — never. v4's `GET /v1/bookings/:id/contact-info` endpoint, its unlock-at-`payment_claimed` rule, and the whole concept of a contact "unlock moment" are deleted. See §1c below for what replaces it — the existing in-app booking chat, which was already speced to open at `accepted`, becomes the sole coordination channel for the entire life of a booking. This is a simplification, not new work: it removes a mechanism rather than adding one, because the replacement already existed in Phase 18.
2. **Provider Profile drops WhatsApp and Viber entirely.** Phone number only, and that phone number is used for OTP and account purposes — it is never returned in any response to another user, exactly as before, just with two fewer fields to protect.
3. **A real "Become a Provider" onboarding flow is added**, ahead of the wizard. v4 had no dedicated screen — starting a draft listing was the only onboarding moment, and the account-level fields (phone, bank details, `acceptingNewCustomers`) were collected later, awkwardly, from inside the dashboard. v5 gives onboarding its own flow: an explanatory intro, then those account-level fields collected once, then a handoff into the listing wizard.
4. **Cover image becomes a required field to publish**, not optional. It's the first thing a customer sees on every card and in every search result; v4's publish gate didn't require it, which meant a listing could go live with a blank thumbnail.
5. **A twelfth category is added: Boat Charter** (picnics, fishing, sandbank trips), request-based like most of the catalogue — trip type, duration, and price vary too much for a fixed-slot picker to fit.
6. **Three smaller UX fixes**, each a direct response to a review comment: a slot whose time has already passed is never shown as bookable regardless of its stored status; the request-based preferred-window picker surfaces quick-pick chips ("Tomorrow morning," "This week") instead of demanding free text; and emergency bookings get an optional final-settled-amount field at completion, separate from the initial callout fee, for real job economics.

### 0.3 What changed from v3

Four decisions from the final review round, plus the specification fixes they required:

1. **Emergency bookings no longer unlock contact at `accepted`.** They unlock at `payment_claimed`, same ordering as every other booking type. `isEmergency` is now restricted to Plumbing, Electrical, and AC Repair, requires `verificationStatus: verified`, and is rate-limited per customer. v3's carve-out was a one-tap bypass of the contact gate that both parties were motivated to use — and the contact gate is the reason a provider pays rather than moving to Viber.
2. **The pre-booking enquiry filter is a soft nudge with logging, not a hard block.** v3 required hard-rejecting phone-shaped text while explicitly allowing appliance serial numbers. Maldivian mobiles are 7 digits; AC serials are digit strings; these are not reliably distinguishable, and photos were allowed anyway, so a photo of a business card passed regardless. Detections are now logged as a moderation signal — a provider tripping it across 40 enquiries is visible and actionable; the individual message is not blocked.
3. **Emergency bookings carry a callout fee as `agreedAmount`**, set by the provider after accepting and before the customer is prompted to pay. v3 required an `agreedAmount` before leaving `requested` while also routing emergencies straight to `accepted` — a plumber cannot price a job they haven't seen. The callout fee is what they *can* price, it is labelled as such in the UI, and the plan states plainly that the full job cost is settled off-platform.
4. **All four artifacts regenerated** — this plan standalone, `02_Cursor_Prompts.md` rebuilt phase by phase, `03`/`03b` rule invariants rewritten.

### 0.4 One decision applied on your behalf — override if you disagree

**Trial-start trigger.** This was flagged in the v2 review and again in v3's §6 and never made it into a question round. v3 left it as "first confirmed booking only," which means a provider who publishes but never gets booked never experiences premium and never converts. That is the single largest lever on subscription revenue.

**Applied:** trial starts on the provider's first `confirmed` booking **or** on an explicit provider-initiated "Try Premium" request, whichever comes first. Still 60 calendar days, still one per account.

This is the fix recommended in two prior reviews. It is a small change (one extra endpoint, one extra call site into the same function) and it is reversible. If you want booking-only, say so before Phase 8a.

### 0.5 Specification fixes applied without a question

These were defects rather than choices — the spec contradicted itself or left a gap an implementer would have to guess at. Each is flagged inline with 🔧 where it appears.

| Fix | Was |
|---|---|
| `scheduledFor` set to acceptance time on emergency bookings | Emergency had no `scheduledFor`, so the completion timeout never fired and reviews never opened |
| Three separate timeouts: emergency accept (30 min), standard accept (24 h), customer quote-approval (72 h, own clock) | One 24-hour rule applied to all modes; the scheduled job also auto-declined `quote_offered`, a state that exists only because the provider *did* respond |
| Provisional reservation created when a quote is offered | Reservation was created only on customer approval, so the time could be sold to someone else in between and approval would hit a constraint violation |
| Billing anchor date, explicitly not "calendar month" | "Calendar billing" and "pause resumes remaining time" are incompatible — a pause shifts the anchor |
| Trial hook fires on the transition *into* `confirmed` | Hook was on one endpoint; an admin resolving `payment_unresolved` also reaches `confirmed` and would not have fired it |
| `EXCLUDE USING gist` on a provider-scoped time range | `UNIQUE (providerId, listingId, startsAt)` let one provider be booked three times at 10:00 across three listings, and did not detect overlapping durations at all |
| Fallback fires immediately on known push-denial, at 30 min on delivery failure (SMS in the original decision; email since Round 11) | "Within the acceptance window" meant an SMS could arrive at hour 23 of a 24-hour window |
| ID/passport documents: private bucket, 90-day retention post-decision, access logged | §1e introduced ID collection with no storage, retention, or access policy |
| Recurring series survives a missed occurrence | A single auto-declined week silently killed the series |
| Dispute outcomes enumerated | "An outcome recorded" with no enumeration meant an unstructured audit log |
| Slot generation window: 60 days rolling | Unspecified — affects payload size, schema, and Phase 17's transaction scope |
| `bookingMode` seeded in Phase 4 | v3 referenced a Phase 4 seed that Phase 4's spec did not include |
| "laari", not "laira" | Typo in the one place a currency constant gets copied from |

---

## 1. Mockup Inventory & Coverage Map

🔧 **Rewritten in Round 10.** The previous version listed modules rather than owning phases, and closed with a line asserting that provider onboarding has no separate page — which Phase 6a contradicted from the moment v5 introduced it.

### Screens with a mockup — 8

| Screen | Status | Owning phase |
|---|---|---|
| Home (feed) | Exact match provided | 16 |
| Explore (category grid) | Exact match provided — **12 categories, matches the original grid** | 4 |
| Login | Provided, improvable | 3 |
| Register | Provided, improvable | 3 |
| Profile (customer) | Provided, improvable | 6 |
| My Services Dashboard | Exact match provided | 10 |
| Create/Edit Service Wizard (1–7) | Exact match provided | 9 |
| Service Preview | Exact match provided | 12 |

🔧 An earlier revision removed Tuition, dropping the count to 11 and leaving an uneven last row in the mockup's 3-column, 12-item grid. Adding Boat Charter in v5 brings the count back to 12 — the original grid's exact-match claim holds again, coincidentally.

**Where a mockup and this plan disagree, the plan wins and the divergence gets flagged, not silently implemented.** Three are known: the wizard's Availability step shows a per-listing "Accepting New Customers" toggle that is now provider-level and lives on the dashboard; any mockup implying contact details pass between customer and provider is obsolete outside the emergency reveal (§1c); and any single "Verified" badge is obsolete now that verification has three tiers (§1e).

### Screens with no mockup — 20

Claude proposes a design, you approve it, and only then does that phase's code get written. These are **not** lesser screens — they include the entire booking flow and every admin surface. Having no fixed design is an advantage here: interaction behaviour can be specified from scratch rather than retrofitted around a layout.

| Screen / flow | Owning phase | Platform |
|---|---|---|
| Phone verification (OTP entry) | 3 | Flutter |
| Account settings sub-screens (password/email/phone, sessions, data export, deletion) | 3 | Flutter |
| Forgot Password flow | 3b | Flutter |
| Role switcher (customer ⇄ provider) | 6 | Flutter |
| **Become a Provider onboarding flow** | **6a** | Flutter |
| Availability & Time Slot management (provider side) | 9a | Flutter |
| Provider Billing (subscription status, payment proof submission, invoice list) | 10a | Flutter |
| Admin panel — money & identity queues | 10a | **React web** |
| Admin panel — accounts, config, search, shell | 10b | **React web** |
| Admin panel — ops dashboard | 10c | **React web** |
| Provider public profile | 13 | Flutter |
| Saved Services list | 14 | Flutter |
| Search results | 15 | Flutter |
| Category results | 15 | Flutter |
| Launch-mode Home variant | 16 | Flutter |
| **Booking flow, three variants** (slot picker, request-with-window, emergency/ASAP) | 17.1–17.3 | Flutter |
| Bookings tab (list + detail + status timeline) | 17.1 | Flutter |
| **Pre-booking Enquiry thread** and booking chat | 18 | Flutter |
| Notifications centre | 19 | Flutter |
| Trust & Safety and Privacy & Security sub-screens | 23 | Flutter |

**The admin panel is a separate internal React web app**, not a Flutter screen, built across Phases 10a, 10b and 10c. Backend endpoints are identical either way. Keyboard, hover and focus states apply there; mobile assumptions do not.

🔧 **Provider onboarding has its own flow (Phase 6a), new in v5.** Every revision before v5 stated the opposite — that the Create/Edit Service Wizard *was* onboarding, and that starting a draft was what made someone a provider. That is no longer true, and the old claim survived into v5's own §1 by oversight. What remains true from it is the §1a mechanism underneath: `ProviderProfile` is still created implicitly and idempotently by `getOrCreateProviderProfile`, and Phase 8's draft-creation path still calls it as a fallback for anyone who reaches the wizard without one. Phase 6a is the front door; the implicit path is the safety net behind it.

---

## 1a. Provider Lifecycle Model

**Public visibility is derived, not stored.** A provider is publicly visible if and only if `count(listings WHERE status='published' AND visibility='active') > 0`, computed by one shared query helper — `findVisibleProviders` — that Featured Providers, search, and the public profile endpoint all call. There is no stored `lifecycleStatus` field. v1 had one, flipped one-way on first publish, and it drifted: a provider who unpublished their only listing stayed `active` forever with an empty public profile.

- **`ProviderProfile` is created implicitly** on the first `POST /v1/listings` by a user who has none. `getOrCreateProviderProfile(userId)` is idempotent.
- **`verificationTier`** (`none` / `bronze` / `silver` / `gold`) is a separate axis — identity and trade evidence, admin-transitioned except the auto-granted Silver route (§1e). Never conflated with visibility. A provider can be visible at tier `none` simultaneously. `verificationStatus` (`unverified` / `pending` / `verified`) persists alongside it as the *review* state of a pending submission, not as the badge.
- 🔧 **Suspension is an input to visibility.** An admin-suspended provider (§Phase 10b) is excluded by `findVisibleProviders`, so one change covers search, Home, and the public profile. Their listing pages return a neutral unavailable state rather than a booking form. Without this the derived-visibility model would leave a suspended provider fully listed and apparently bookable, with rejection happening only server-side after the customer had committed.
- **Idempotency:** `POST /v1/listings` requires a client-supplied key so a retry on a flaky connection cannot create orphan drafts. "Become a Provider" for a user with an existing draft resumes it.
- **Dashboard access is never gated.** A provider with only drafts reaches My Services Dashboard normally, stats at zero.

---

## 1b. Monetization Model — subscription only

**Customer-facing rule:** all customer features are free indefinitely, with 🔧 **exactly one exception, added in Round 15** — the **MVR 200 emergency dispatch fee** (§1c), incurred only when a customer selects an emergency offer. Nothing else in this section may ever gate a customer action, and no further customer charge may be introduced without amending this rule explicitly.

**Payment for jobs is off-platform.** RaajjePro never moves money between customer and provider. Everything RaajjePro collects is a provider paying RaajjePro, via manual bank transfer + admin confirmation. No payment gateway in v1.

### v1 scope

| Layer | Mechanism |
|---|---|
| Free tier | 1 active listing, full search visibility (**never** paywalled), no analytics. Badge is unaffected — see §1e. |
| Trial | Full premium access, 🔧 **30 calendar days** (Round 12 — was 60). **Starts on the first booking reaching `confirmed`, or on an explicit "Try Premium" request, whichever comes first** (§0.4). |
| Subscription (Premium) | **MVR 150/month standard.** Unlocks multiple active listings, analytics dashboard + weekly digest, priority placement. **Does not unlock the badge.** |

🔧 **Introductory pricing — Round 9.** §1b previously pinned MVR 150 platform-wide while simultaneously recording (below) that the premium bundle was known-weak against free alternatives. Shipping a price already diagnosed as weak, with no mechanism to test a different one, left the plan unable to act on its own finding.

- A **`subscriptionPriceLaari`** field lives on the provider record, set at their first confirmed payment and honoured on every renewal thereafter. The subscription entity reads this, never a global constant.
- The **first 100 providers** are set to the introductory rate of 🔧 **MVR 75 = 7500 laari** (Round 14 — half the standard MVR 150); everyone after them takes the standard rate. The cohort boundary is the field's value, not a rule evaluated later — a provider's price never changes because of someone else's signup.
- The introductory rate is **honoured for 12 months from the billing anchor**, then converts to standard with **30 days' notice** delivered through Phase 19. Time-boxing keeps the acquisition benefit without a permanent revenue drag, and produces a clean conversion measurement.
- This makes trial-to-paid conversion measurable against two real price points — which is what Phase 10c's dashboard trend line exists to show.

### Deferred to post-v1

Credit wallet & à la carte purchases; the advertising module; referrals. Rationale: every premium benefit derives its value from demand density that will not exist at launch. Building three monetization systems before the marketplace could transact was v1's largest sequencing error. Keep `PaymentSubmission`'s `purpose` enum open so all three slot back in additively.

### Trial and subscription lifecycle

- **Warning** 7 days before trial or subscription period end.
- **Grace:** 7 days after expiry with nothing changing, then downgrade to free.
- **Billing anchor — 🔧 explicitly not "calendar month".** A subscription bills every 30 days from an anchor date set at first confirmed payment. **Pausing shifts the anchor by the paused duration.** Calling this "calendar month" was incoherent with pause: a provider who pauses four days is no longer billed on the 1st, and after several pauses no two providers share an anchor. Bill on the anchor, display the next billing date, and never imply month boundaries.
- **Pause:** capped at **10 cumulative days**. Resuming manually within the cap preserves the remaining paused allowance for later use. At the cap, pause auto-ends and the clock forcibly resumes. **The identical mechanism applies to the trial period** — one function, one cap, one resume rule, shared by `trialing` and `active`. Pause keys off the provider-level `acceptingNewCustomers` toggle (§Phase 5).
- **Downgrade is non-destructive and reversible.** Listings beyond the free-tier cap are hidden (`visibility: 'hidden_over_cap'`), never deleted. Analytics disable. Badge is unaffected. Any confirmed payment restores everything. Basic discoverability of the remaining listing is never affected.
  - **Protected listings:** a listing with a booking in `accepted`, `awaiting_payment`, `payment_claimed`, `payment_unresolved`, or `confirmed` status and a future `scheduledFor` **stays visible regardless of cap**, until that booking reaches a terminal state (`completed` / `cancelled` / `declined` / `dispute_resolved`). Hiding a listing out from under a customer who already has a confirmed job booked against it breaks a commitment the platform vouched for.
  - 🔧 **Among unprotected listings, keep the highest-performing one visible** — ranked by confirmed bookings over the trailing 90 days, falling back to listing views where booking counts tie, and only to recency where a provider has neither. The provider can override the choice from the dashboard. An earlier rule kept the *most recently updated* listing, which a provider who knew the rule could game by touching their preferred listing more often than the others, regardless of which actually performed.
- **Trial abuse prevention:** one trial per user account, not tied to phone number — a provider who changes phone keeps their remaining trial.
- **Win-back:** 🔧 a downgraded provider receives a notification at 7 and 30 days reminding them their hidden listings are intact and one confirmed payment restores them. v3 had a `downgraded_to_free` notification and no follow-up.
- No expiry on money; subscription simply stops charging when cancelled.

### The manual payment mechanism

One generic `PaymentSubmission` entity serves every purpose (v1: `subscription` only; the enum stays open):

1. Provider initiates a payment intent in-app.
2. App shows RaajjePro's bank details + a generated reference code.
3. Provider uploads proof and submits. Status `pending`.
4. Admin reviews in the panel and **confirms** (grants the entitlement) or **rejects** (reason required).
5. On rejection the provider sees the reason and may **resubmit immediately** — no cooldown — or **appeal** for re-review.
6. On confirmation, a downloadable **PDF invoice** is generated.

**Nothing is granted on submission.** A `pending` submission produces entitlements identical to no payment at all. `getProviderEntitlements` reads live database state on every call and never caches.

**Reversal:** an admin can reverse a confirmed payment (mistake, bank reversal). Explicit endpoint with an audit-log entry, never a database edit.

**Automation:** Phase 10a includes bank-statement CSV import with reference-code auto-matching. Manual review at 200 providers is ~10 confirmations per working day forever.

**Operational SLA:** confirm or reject within 48 hours. Policy, not code — but documented, because the model depends on humans acting fast.

### 🔧 Flagged business risk, not a defect

Round 5 pinned MVR 150 and decoupled the badge from subscription in the same round. Each was individually right — the badge is a safety signal and must not lapse with payment — but together they removed the most compelling item from the premium bundle without adjusting anything else. Premium now contains multiple listings (irrelevant to a solo tradesperson, the modal provider), priority placement (worth little in a thin catalogue), and analytics.

Options if trial-to-paid conversion disappoints: price lower for v1 and raise later; make identity verification a paid one-time service, separating "we checked this person" (a real cost you incur) from the recurring bundle; or accept that v1 monetization is nominal and the goal is density. **No change made — the price is your pinned decision. Recorded so the interaction is visible.**

---

## 1c. Booking, Slots & Requests, Payment Attestation, In-App Communication

### Category booking mode

Every listing carries a `bookingMode`: `'slot'` or `'request'`, defaulted by category (seeded in Phase 4) and editable per listing.

| bookingMode | Categories | Why |
|---|---|---|
| `slot` | Cleaning, Beauty, Fitness | Fixed or provider-predictable duration; appointment-shaped |
| `request` | Plumbing, Electrical, AC Repair, Photography, Gardening, Computer, Moving, Events, **Boat Charter** | Duration depends on diagnosis, property, negotiation, or trip type — cannot be pre-published as a fixed-length slot |

🔧 This assignment is a config table, not a structural decision. Confirm before Phase 4 seeds it. **Boat Charter is new in v5** (§1d) — request-based, standard fields, no special schema beyond the rest of the catalogue: trip type and duration vary too much (a two-hour sandbank run and a full-day fishing charter are both "Boat Charter") for either a fixed slot or a bespoke field set to fit cleanly.

**Emergency capability is separate and restricted.** A listing may set `isEmergency: true` only if **all** of the following hold:
- its category is 🔧 **Plumbing, Electrical, AC Repair, or Moving** (Moving added in Round 12, with a 120-minute accept window)
- the provider's `verificationTier` meets the category's 🔧 **`emergencyMinimumTier` — Round 15**. **`gold` for Electrical and Plumbing**, **`silver` for AC Repair and Moving**. Electrical and plumbing failures at 2am are life-safety work in a stranger's home; five completed bookings evidences nothing about trade competence, and Gold is the only tier carrying a trade certificate. Never hardcode `silver`.

Enforced server-side on the listing publish and update paths, and re-checked at booking creation (a provider whose verification is later revoked stops receiving emergency requests immediately).

### 🔧 Discovery must signal booking mode

Search results, category results, and Home cards show a mode affordance — **"Book instantly"** for slot-based, **"Request a time"** for request-based, plus an **"Emergency available"** marker where applicable. v3 had no signal at all: a customer expecting to pick a time got a form, or vice versa. This is also a genuine differentiator worth surfacing.

### Slot-based flow

- Provider publishes bookable time slots (Phase 9a), generated from availability rules with individual override.
- **Customers only ever see currently-open slots.** No picker ever shows an unavailable time.
- 🔧 **A slot whose `startsAt` has already passed is never shown as bookable, regardless of its stored status.** The picker filters on `startsAt > now()` in addition to `status = 'open'` — a slot that was open five minutes ago and simply wasn't cleaned up by the regeneration job must not appear as a live option. This is a query-time guarantee, not dependent on the nightly regeneration job having already run.
- Booking a slot reserves it atomically inside the booking-creation transaction. A race resolves to exactly one winner.
- Cancellation or decline frees the slot back to `open`.

### Request-based flow

- Customer submits a **preferred date/time window** (not an exact slot — "Tuesday afternoon", "this week"), job details, and location.
- 🔧 **The window picker leads with quick-pick chips** — "Tomorrow morning," "Tomorrow afternoon," "This week," "This weekend" — covering the common cases in one tap, with free text available underneath for anything more specific. A blank text field as the primary interaction asks more of the customer than most bookings need.
- Provider reviews via the same accept prompt and **responds with a proposed concrete date/time and price**. This reuses the quote mechanism (`awaiting_quote` → `quote_offered`).
- 🔧 **Quote and approval windows are per-category — Round 15.** They were a flat 24h to quote and 72h to approve, which meant booking a plumber could legitimately take four days. Nobody waits four days for a blocked drain; they call someone and the booking never happens. **Plumbing, Electrical, AC Repair and Computer: 2 hours to quote, 4 hours to approve.** **Photography, Gardening, Moving, Events and Boat Charter: 24 hours to quote, 72 hours to approve**, where planning genuinely happens. Seeded as `quoteExpiryMinutes` and `quoteApprovalMinutes` (§1d); never hardcode 24/72.
- 🔧 **Offering a quote creates a provisional reservation** on the proposed time, expiring with the quote's approval window. Without this, the provider could sell that time to someone else in the interim and the customer's approval would fail on a constraint violation after they had already agreed a price.
- 🔧 **The `booking`-type chat opens the moment a quote is offered**, not at `accepted`. This is the one window where negotiation is most likely to be needed — the provider proposes Tuesday 2pm at a price and the customer wants Tuesday 3pm — and an earlier revision left it with no channel at all, so the customer's only levers were approve or reject as offered, forcing the provider to guess again from scratch while the 72-hour clock and the provisional reservation churned each time.
- Customer approves or rejects. Approval converts the provisional reservation to a firm one and transitions to `accepted`.
- Everything downstream is identical to the slot-based flow from `accepted` onward.

### Emergency bookings

- Customer submits an ASAP request — no slot, no window — with job details and location.
- 🔧 **The request is broadcast to every eligible provider at once — Round 12.** All providers whose listing is emergency-capable in that category, who serve that island, whose `verificationTier` is `silver` or above, and who have `acceptingNewCustomers` on. Earlier revisions sent an emergency to **one** provider at a time and explicitly deferred fan-out to post-v1; that is reversed. Sequential dispatch is the wrong shape for the one booking type where minutes matter, and it made the customer's choice of provider — made under stress, from a list — the thing that determined whether anyone came at all.
- 🔧 **A provider accepts *with* their callout fee, in one action.** The fee is no longer set in a second step after accepting. Under broadcast, deferring it would commit the customer to an unknown provider at an unknown price before they saw either.
- 🔧 **Offers are collected for a window, then the customer chooses — Round 15 replaced first-past-the-post.** Acceptances no longer race: the first acceptance opens a **90-second collection window** during which every other eligible provider may also accept with their own fee. At the end of it the customer is shown **up to three offers side by side** — provider, tier, rating, distance and callout fee — and picks one. Under the old rule the winner was whoever tapped fastest rather than whoever was nearest or cheapest, the customer decided blind one offer at a time, and the dominant provider strategy was to accept instantly and quote high. The collection window costs 90 seconds of a 30-minute budget and converts a race into a genuine competitive bid.
  - **Fewer than three offers** at the end of the window: show what arrived. **None:** keep broadcasting and open a new window on the next acceptance.
  - Each offer is an `EmergencyOffer` row (bookingId, providerId, calloutFeeLaari, createdAt, state). `emergency_offered` now means *offers are collected and awaiting the customer*, not *one provider has claimed this*.
  - The atomic-claim machinery still applies, but only to the offer the customer selects — it resolves the case where two customers somehow reach the same provider, not the case of two providers reaching one customer.

🔧 **The selected offer does not bind the customer until they select it.** It is presented as an **offer** — provider, tier, rating, and callout fee — and the customer **accepts or rejects** it.
  - **Accept** → the offer's fee becomes `agreedAmount` (`amountKind: 'callout_fee'`) and the booking moves straight to `awaiting_payment`.
  - **Reject** → the booking returns to `requested` and **re-broadcasts immediately**, excluding every provider already rejected on this booking. The rejected provider is told the customer went elsewhere, without a reason.
  - **Customer silence** → 🔧 the offer expires after **5 minutes**, releases the provider, and re-broadcasts. Applied without a dedicated question: an emergency customer is holding their phone, and a longer window wastes the overall clock.
  - Concurrent acceptances resolve to exactly one winner; the losers are told immediately that it was claimed, not left on a spinner.
- **On acceptance** the callout fee is carried as `agreedAmount` — the amount they charge to attend. 🔧 They cannot price the full job before seeing it; the callout fee is what they *can* price. The UI labels it "Callout fee" and states plainly that parts and labour are settled directly with the provider afterward, consistent with every other booking on the platform.
- 🔧 **At completion the provider must record the final settled amount** — a separate field from `agreedAmount`, capturing what the job actually came to once parts and labour were added on top of the callout fee. **Required to mark an emergency booking complete**, exactly as `agreedAmount` already gates entry to `awaiting_payment`. It was optional in an earlier revision, which meant it would be reliably present on clean cheap jobs and reliably absent on the padded bill a customer was disputing — precisely inverting the evidentiary value it exists to provide. Scoped to emergency bookings only in v1; request-based quotes already carry a real negotiated price.
- **In-app chat opens at `accepted`**, same as every other booking mode (§Pre-booking enquiry and full chat, below) — this is when the provider gets the exact address, access instructions, and any detail that doesn't fit the initial job description.
- 🔧 **`scheduledFor` is set to the acceptance timestamp**, so the 7-day completion timeout fires normally. Without this, emergency bookings would have no natural scheduled time, the completion timeout could never fire, and a provider could block reviews of emergency work forever by staying silent.
- **No calendar reservation** — an emergency is understood as an interruption to the published calendar, not a block on it.
- 🔧 **Arrival confirmation and re-dispatch — Round 15.** A confirmed emergency provider who never arrives is currently unhandled: the customer waits with no recourse. The customer may mark **"provider has not arrived"** from the booking screen at any point after the category's accept window elapses. This releases the provider, records a **no-show** against their conduct record (§1f), and **re-broadcasts immediately** excluding them. No admin is involved — an emergency cannot wait for a queue.
- **Rate limit:** 3 emergency requests per customer per 24 hours, 10 per 7 days. Accept-then-cancel patterns are logged as a moderation signal (Phase 22).
- 🔧 **The overall response window is per-category, not a single 30 minutes — Round 12.** Plumbing, Electrical and AC Repair keep **30 minutes**. **Moving**, newly emergency-capable, gets **120 minutes**: the 30-minute figure was set for a tradesperson arriving with hand tools, and a mover needs a vehicle and usually a crew. Stored as `emergencyAcceptWindowMinutes` on the category (§Phase 4), alongside `minimumLeadTimeMinutes`.
- **If the window expires with no accepted offer:** the booking auto-declines, the customer is notified, and is offered one tap to re-broadcast or to convert it to a normal request-based booking. Individual offer expiries and rejections do **not** stop the clock — the window governs the whole request, so a customer who rejects three offers has spent that time.
- **Rejections do not consume the customer's rate limit.** The limit applies to *requests*, not to offers within one.
- 🔧 **Emergency dispatch fee — MVR 200, new in Round 15.** RaajjePro charges the **customer** MVR 200 (20000 laari) per emergency dispatch. It exists to stop the feature being used casually, and it is the first money the platform takes from a customer — §1b's "all customer features are free indefinitely" is amended accordingly, and only for this.
  - **Incurred when the customer selects an offer**, never on submitting a request. A dispatch nobody accepts costs the customer nothing, and a customer whose emergency goes unanswered must not also receive a bill.
  - 🔧 **It never blocks dispatch.** There is no payment gateway — every payment to RaajjePro is a manual bank transfer — so the fee is recorded as **owed** and the job proceeds immediately. Requiring a transfer mid-emergency would be both unworkable and indefensible.
  - **Settled afterwards** through the existing `PaymentSubmission` flow against a generated reference code, with admin confirmation. This is what `PaymentSubmission`'s open `purpose` enum was left open for: a new value `emergency_dispatch_fee`, alongside the subscription purpose.
  - 🔧 **An unsettled fee blocks all new bookings**, not only emergency ones. The account is not suspended and existing bookings are unaffected — the customer simply cannot start anything new while owing.
  - 🔧 **The block lifts the moment the customer submits proof of transfer, not when an admin confirms it.** Online banking is done from a phone here, so settling takes minutes — but admin confirmation runs on a 48-hour SLA, and holding a customer hostage to a queue for MVR 200 would punish them for the platform's own latency. Submission clears the block; the admin verifies afterwards and acts on anything false. This is the same trust posture the plan already takes with booking payment attestation, and a fabricated receipt is a moderation matter (§Phase 22), not a reason to make everyone wait.
  - The fee is **not refundable on a provider no-show** — but a re-dispatch under the no-show rule above does **not** incur a second fee. One emergency, one fee.

### Pre-booking enquiry and in-app chat — the only channel, always

🔧 **v5 change, and the largest single change in this revision.** Phone, WhatsApp, and Viber numbers are never exchanged between a customer and a provider — with **exactly one deliberate, narrowly-scoped exception for emergency bookings**, specified below and nowhere else. Outside that exception there is no "unlock moment" anywhere in this system: not before a booking exists, not during a slot or request booking, not after any booking completes. Every prior revision of this plan built increasingly careful machinery around *when* contact info should become visible; v5 removes the question by removing the thing being gated. Everything two parties need to coordinate — appliance details, exact address, gate codes, arrival updates, a photo of the leak — happens as a message, before and after a booking is made.

This isn't new infrastructure. Phase 18's booking-scoped chat was already speced to open at `accepted` in every prior revision; v5 simply deletes the *separate*, later contact-info unlock that used to sit on top of it, and keeps the chat running for the entire life of the booking instead of treating it as a waiting room before "real" contact.

- **Two conversation types, both entirely in-app:**
  - `enquiry` — scoped to a **listing** (not a booking), available to any phone-verified user before any booking exists. **Everything is allowed** — appliance make/model/serial number, property details, photos of the issue, availability questions, price ranges. The point is to let a plumber ask "is it a split unit or ducted?" and a customer answer.
  - `booking` — opens automatically at `accepted` and stays open for the entire life of the booking, including after completion. This is now the *only* way arrival logistics, access instructions, and anything not covered in the initial job description gets communicated. It never expires or gets replaced by a "real" contact channel, because there isn't one.
- 🔧 **Contact-pattern detection is silent — Round 12 removed the user-visible nudge entirely.** Nothing is shown to the sender, nothing is blocked, nothing is redacted. In-app messaging carries no interference of any kind. Earlier revisions showed an inline reminder that phone numbers are never shared; it was friction on exactly the content the enquiry channel exists to carry, and it did nothing the moderation aggregate below does not already do better.
- **Detection itself continues, invisibly.** Every match is still recorded and still feeds the provider-level signal in Phase 22 — the enforcement mechanism is the aggregate, not the individual message, and it works whether or not the sender is told.
- **Every detection is logged** with conversation, sender, and matched pattern, and surfaces in Phase 22's moderation queue as an aggregate signal. A provider who trips the detector across 40 enquiries is visible and actionable; an individual false positive costs nothing.
- **Why detection never blocks:** Maldivian mobiles are 7 digits beginning 7 or 9; AC serials are 7–15 digit strings; model numbers are alphanumeric with digit runs. These are not reliably distinguishable, and a hard block would fire on exactly the content the enquiry channel exists to carry. Photos are also allowed, so a photo of a business card would pass a text filter regardless. A soft nudge with logged aggregates catches the pattern without breaking the legitimate case.
- If a booking is later created between the same two users on the same listing, the **enquiry conversation continues**, now also linked to the booking, and the `booking`-type chat opens alongside it once the booking reaches `accepted`.
- 🔧 **Lifecycle:** if the listing is hidden by downgrade, both threads stay readable to their participants but accept no new messages on the `enquiry` side, with an explanatory state — a `booking`-type thread tied to a still-active booking is never affected by its listing's visibility. If the listing is soft-deleted, the `enquiry` thread becomes read-only and is excluded from the conversation list after 30 days.
- Restores the "Message" button on Service Preview (Phase 12).
- **Payment details are not contact information.** The provider's bank transfer details (§Provider Profile, Phase 5) are still shown to the customer at the payment step of every booking — a bank account number isn't a way to reach a person, and the off-platform payment cannot physically happen without it.

### 🔧 The emergency contact exception — the only one

**Round 9, and a deliberate narrowing of v5's original absolute rule.** Emergency coordination relies entirely on in-app text chat, in a market this plan itself calls connectivity-unreliable. One dropped message on a weak atoll connection means an accepted, paying provider standing on the wrong street while a pipe floods a house. Every other booking mode can absorb a delayed message; an emergency cannot. Rather than staff a human relay, v5.1 opens a single audited path — and confines it tightly enough that the invariant still holds everywhere else.

**Conditions — all seven must hold, and are validated on every request:**
- The booking's `bookingMode` is **`emergency`**. No slot or request booking can reach this path, ever.
- The booking is at **`accepted` or later**. Never at `requested` — a provider who hasn't committed gets nothing.
- The **customer initiates** the request explicitly, from the booking detail screen. There is no automatic reveal and no provider-initiated reveal.
- **The reveal is mutual and simultaneous.** Both parties see each other's number, or neither does. A one-way reveal would hand the customer a lever the provider never agreed to.
- **The counterparty is notified** at the moment of reveal, in-app and by push.
- The reveal **expires 24 hours after the booking reaches a terminal state**, after which the endpoint returns nothing for that booking.
- **Every reveal is logged** — bookingId, requesting user, timestamp — and surfaces in Phase 22's moderation signals. A customer who requests reveals on every emergency booking is a visible pattern.

**Separately, and not one of the seven:** the reveal is **killable at runtime** via the Phase 10b kill switch, without a deploy. This is a runtime feature flag checked before the seven, not a per-request validation — which is why the count is seven and the list below it is eight lines long. Phase 20's audit asserts the seven; the kill switch is exercised by Phase 10b's own tests.

🔧 **The revealed number is not a verified number — Round 11.** Removing SMS removed the only proof that a number belongs to its account holder (§Phase 3). Below Bronze the number is self-declared text, and a customer in an emergency can reach a wrong or dead line at the worst possible moment. Two mitigations, both already in the plan: emergency capability already requires **Silver or above** (§1e), and Bronze review already has the admin confirm the number — so every provider who can receive an emergency request has had their number checked by a human. The reveal UI states that the number was confirmed at verification, never that it is "verified" as a live property.

**Implementation:** one endpoint, `POST /v1/bookings/:id/reveal-contact`, which validates every condition above and is the **only** route in the system through which a phone number reaches another user. Phase 17's "no response shape carries a phone number" audit still applies to every other endpoint in the module, unchanged — this one is the single, named, deliberately-excepted exception, and any *other* endpoint returning a phone number is still a defect.

**What this does not change:** WhatsApp and Viber handles are still not collected at all (§Phase 5) and cannot be revealed by anything. Nothing about a provider's identity beyond the phone number crosses this boundary. Slot, request, and recurring bookings remain absolutely chat-only.

### Access control — graduated

| Tier | Unlocks | Enforced by |
|---|---|---|
| Guest | Browse, search, view listings and public provider profiles | No gate |
| Registered | Save/favourite | `requireAuth` |
| Email-verified | Book, enquire, message within a booking | 🔧 `requireEmailVerified` (Round 11 — replaces `requirePhoneVerified`; there is no SMS in this system) |
| Visible provider | Appears publicly, receives bookings | Derived published-listing count (§1a) |
| Entitled provider | Extra listings, analytics, priority | `getProviderEntitlements` (§1b) |

Enforcement is server-side on every relevant endpoint. A guest may see a "Book Now" button — tapping it routes to login/verification. The backend rejects regardless of what the client sends.

### Booking status machine

```
                    ┌──────────► declined (provider, or timeout)
                    │
requested ──────────┴──► accepted ──► awaiting_payment ──► payment_claimed ──┐
   │                        │              (amount set)          │            │
   │                        │                                    │            ▼
   │                        │                          ┌─────────┴───► confirmed ──► completed
   │                        │                          │                    │
   │                        ▼                          ▼                    ▼
   └──► cancelled     payment_unresolved ◄──── disputed ──► dispute_resolved (admin)
        (customer,    (7d provider silence;
         pre-payment)  admin resolves)
```

- **Request-based / quote-priced** listings insert `awaiting_quote → quote_offered → accepted` before the diagram above.
- **Slot-based and request-based** bookings pass through `awaiting_payment` instantly — `agreedAmount` is set at `accepted`, so the customer's payment prompt appears immediately.
- 🔧 **Emergency** bookings insert `emergency_offered` between `requested` and `awaiting_payment` (Round 12): the request broadcasts, a provider claims it by accepting *with* a callout fee, the customer accepts or rejects that offer, and only an accepted offer reaches `awaiting_payment`. A rejected or expired offer returns the booking to `requested` and re-broadcasts. `emergency_offered` is **not** terminal and cannot be reached by any other booking mode.
- **`payment_unresolved` is not terminal.** An admin resolves it to `confirmed` or `cancelled`.
- **`disputed` is not terminal.** An admin resolves it to `dispute_resolved` with an enumerated outcome.

### The flow, step by step

1. Customer picks an open slot (slot-based), submits a preferred window (request-based), or submits an ASAP request (emergency). Status `requested`.
2. **Provider accept prompt** — job details and the customer's name only, **no contact details of any kind, and no chat yet**. Accept / decline, or (request-based) propose a time + price — 🔧 offering a quote is itself what opens the chat (§Request-based flow).
3. **On acceptance the booking carries an `agreedAmount`** (integer laari): from the listing price for fixed pricing, from the accepted quote for request-based, or from the provider-set callout fee for emergency. No booking reaches `awaiting_payment` without one.
4. **🔧 Three accept timeouts, not one:**
   - **Emergency:** 30 minutes → auto-decline, notify customer, offer another provider or conversion to a normal request.
   - **Slot and request-based:** 24 hours → auto-decline, release the slot or reservation, notify the customer to look elsewhere.
   - **Customer quote-approval:** 72 hours from the quote being *offered* (its own clock) → quote expires, provisional reservation releases, booking closes. An earlier revision's job auto-declined `quote_offered` 24 hours after *booking creation*, which would have killed quotes the provider submitted at hour 23 before the customer ever saw them.
5. **The `booking`-type in-app chat opens the instant the booking is accepted.** This is the sole channel from this point forward — arrival details, exact address, access instructions, anything the initial job description didn't cover.
6. Customer is prompted to pay off-platform, directly to the provider, using the payment details the provider registered (Phase 5). Copy states plainly that RaajjePro is not handling this money.
7. Customer taps **"I've Paid"** — self-attestation, no proof upload. Status `payment_claimed`.
8. Provider confirms or disputes receipt. Confirm → `confirmed`. Dispute → `disputed`.
9. **If the provider neither confirms nor disputes within 7 days** → **`payment_unresolved`**, not `confirmed`. Both parties notified, queued in Phase 22's moderation queue. **Nothing further is unlocked by this transition.** An admin resolves it manually. An earlier revision auto-confirmed here, recording an attestation that may never have happened.
10. **Completion.** If the provider doesn't mark the job complete within 7 days of `scheduledFor`, the **customer is prompted**: *"Did [Provider] complete this job?"* (Yes / No / no response).
    - **Yes** → `completed` normally, `completedVia: 'confirmed'`.
    - **No** → flagged to the moderation queue as a possible no-show, same path as a dispute.
    - **No response after a further 3-day grace** → auto-completes, tagged `completedVia: 'unconfirmed'`, distinguishing it from a genuine two-sided completion for analytics and trust purposes while still opening review eligibility. A provider must not be able to block reviews forever by staying silent.
11. Review becomes postable once `completed`. One review per booking. **The `booking`-type chat stays open after completion** — a customer who needs to reach the provider again about the same job (a follow-up question, a warranty claim) still has the thread; it is never torn down.

### In-app communication is the channel — one audited exception, nothing else to gate

🔧 **v5 removed the general concept this section used to describe; Round 9 restores exactly one instance of it.** Every revision before v5 specified a general unlock schedule — a phone number appearing at `confirmed`, then at `payment_claimed`, with a contested carve-out for emergencies. v5 removed all of it. Round 9 reintroduces **only** the emergency carve-out, as the audited, customer-initiated, mutual, expiring, kill-switchable path specified above — and nothing else. For every other booking type the v5 answer stands unchanged: never, for anyone, at any point.

- Provider Profile (Phase 5) stores exactly one phone number, used for OTP verification and account-level notification. It is returned to another user through **one endpoint only** — `POST /v1/bookings/:id/reveal-contact`, under the emergency conditions above. It appears in no other response: not in a public listing, not in a provider profile, not in any booking payload, not in search. There is no `GET /v1/bookings/:id/contact-info` endpoint in this system; if you encounter one in older project documentation, remove it rather than reimplement it — it is not the same thing as the emergency reveal and grants far broader access.
- What a customer and provider actually exchange — job details, arrival logistics, photos, follow-up questions — travels through the `enquiry` and `booking` conversation types described above (§Pre-booking enquiry and in-app chat), for the entire relationship between them, not a bounded window inside it.
- **Bank transfer details** (§Provider Profile, Phase 5) are shown at the payment step of every booking. This is payment information, not contact information — it doesn't let either party reach the other, and the off-platform payment cannot happen without it.

### Disputes

- **Either party may dispute.** A late dispute (post-`completed`) is accepted; the booking stays completed and the dispute queues separately.
- **`disputed` is not terminal.** An admin resolves it to `dispute_resolved` with an outcome from a 🔧 **fixed enumeration**: `resolved_for_customer`, `resolved_for_provider`, `inconclusive`, `fraud_confirmed`, `withdrawn`. v3 recorded "an outcome" with no enumeration, which would have produced an unstructured audit log you could not measure fairness against.
- Disputes feed Phase 22's queue with both parties' history shown together. RaajjePro can see patterns and act proportionately, but cannot adjudicate an off-platform payment and must never present itself as doing so.
- **Decline ≠ dispute.** Separate endpoints, separate statuses, visually distinct in the UI.

### Recurring bookings

- **Slot-based listings only** — predictable duration is what makes "same time next week" meaningful.
- A `RecurringSeries` links a customer, provider, and listing to a weekly cadence.
- **Each occurrence still requires individual provider accept.** Recurrence is a convenience, not a standing pre-authorization — preserving the "provider always gets a real chance to decline" principle the whole redesign is built around. The UI streamlines it to a one-tap "Same time next week?".
- 🔧 **A missed occurrence does not kill the series.** If an occurrence auto-declines at the 24-hour timeout, that week is skipped, both parties are notified explicitly ("this week was not confirmed; your series continues next week"), and the series continues. **Three consecutive missed occurrences** pause the series and notify the customer to reconfirm. v3 left this undefined, so one busy week would have silently ended a recurring relationship.
- Cancelling one occurrence doesn't cancel the series; cancelling the series stops future occurrences.

### Honest framing — mandatory

Never "Payment Verified." Never a lock or verified-checkmark on this flow. Use **"Provider confirmed receipt."** RaajjePro has no visibility into the actual transaction and the UI must not imply otherwise.

### What this does and does not prevent

Never collecting or exposing contact info closes the specific leak every earlier revision was defending against — a booking flow that unlocks a phone number can't accidentally leak it through a bug, an over-broad DTO, or a timing edge case, because there's nothing to leak. It does **not** stop a provider publishing their own number in a listing description, an FAQ answer, or a gallery image — and the provider is the party with the incentive, since that's still the fastest way off the platform for both sides. Phase 22's free-text scanning of listing content mitigates this; obfuscation defeats it. **Treat this as friction on the provider's side, not a sealed boundary.** The enquiry- and booking-thread detection logging (§1c) makes patterns visible, which is the realistic ceiling for what a moderation system can do about a determined provider.

---

## 1d. Categories — 12

**Cleaning, Plumbing, Electrical, AC Repair, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events, Boat Charter.**

Tuition was removed entirely in an earlier revision — from categories, seed data, and every reference. 🔧 **Boat Charter is added in v5** — picnics, fishing trips, sandbank excursions. Request-based (§1c), not emergency-capable, no schema fields beyond the standard set. Phase 4's seed, icon/color mapping, and every category-count reference in this document reflect 12.

---

## 1e. Identity Verification — three tiers

🔧 **Rewritten in Round 9.** Verification was a binary `verified` flag whose evidence bar had just been tightened to require a business registration or trade certificate. Against §1e's own premise — that many Maldivian tradespeople are informal and unregistered — that made the badge unobtainable for the modal provider, and since emergency capability gates on verification, it would have shrunk the emergency pool to near zero at launch. Tiering keeps the stricter evidence rule while giving an unregistered tradesperson a real ladder.

`verificationTier` replaces the binary flag: `none` / `bronze` / `silver` / `gold`. `verificationStatus` (`unverified` / `pending` / `verified`) remains as the *review* state of a pending submission; the tier is what the badge renders and what other systems gate on.

| Tier | Requirements | Public copy |
|---|---|---|
| **Bronze** | A national ID or passport matching the account name. 🔧 The admin also confirms the account's phone number — by calling it, or by matching it against the document. No trade evidence. | "ID checked by RaajjePro" |
| **Silver** | Bronze, **plus** photos of completed work, **plus** a second factor that is *not* paperwork — either a customer reference RaajjePro contacts directly, or **5 completed on-platform bookings with no unresolved dispute** | "ID checked, work verified" |
| **Gold** | Silver, **plus** a business registration **or** a recognised trade certificate | "ID checked, registered trade" |

- **Photos of completed work are never sufficient on their own at any tier.** This preserves the forgeability fix — photos are trivially reusable — while Silver's second factor can be *earned on-platform* rather than issued by a ministry. An informal plumber reaches Silver within their first handful of jobs; only Gold requires formal registration.
- 🔧 **The 5-clean-bookings route to Silver is granted automatically, with no admin review at all.** Only ID checks (Bronze), customer references, and Gold paperwork ever reach a human. This is what keeps three tiers affordable against a single admin on a 5-business-day SLA (§7).
- **Tiers do not expire.** There is no annual recheck. A confirmed-fraud dispute outcome, or an accumulated dispute pattern surfaced by Phase 22, triggers an admin review that may demote or revoke a tier. Time-based expiry would generate recurring review load for the case that rarely matters; dispute-triggered review catches the case that does.
- The badge depends solely on `verificationTier`. It does **not** require an active subscription — a lapsed-but-verified provider keeps their tier. The badge is a safety signal, not a payment status.
- **Review:** manual, by the admin role built in Phase 2 (except the auto-granted Silver route above). No new vendor, no automated KYC, consistent with the manual-first posture of the rest of the platform.
- **Where it lives:** the review queue extends Phase 10a/22's existing admin panel and audit log.
- 🔧 **Document handling — newly specified.** ID and passport images are strictly more sensitive than payment proofs and v3 introduced them with no policy:
  - Stored in a **separate private bucket**, never the media bucket, never publicly addressable, accessed only via short-lived signed URLs.
  - 🔧 **Excluded from the application backup, with its own retention — Round 15.** A 90-day purge that leaves the document sitting in a database or bucket backup is not a 90-day purge, and it is the first thing a data-protection review finds. The identity bucket carries an independent lifecycle policy and is **not** included in the application backup set. State the real retention in Phase 23's policy — purged from production at 90 days and from backups within the bucket's own retention — rather than the one that sounds better.
  - **Retained 90 days after a verification decision, then purged.** The decision, the evidence *type*, and the reviewing admin persist; the images do not.
  - **Every access is logged** — which admin viewed which document, when. The audit log records the decision, the evidence types submitted, and the rejection reason where applicable, so a rejected provider gets a real reason and a disputed decision has a record.
  - Purged immediately on account deletion.
- 🔧 **Emergency capability requires `silver` or above** (§1c) — demonstrated work history, but no paperwork. Setting the emergency gate at Gold would recreate the exact exclusion this tiering exists to fix; setting it at Bronze would mean a bare ID check is enough to enter a stranger's home in an emergency.
- Full evidence checklist, rejection-reason taxonomy, and resubmission path are built in Phase 23. The *decision* — what's required, who reviews, how documents are handled — is locked here so Phases 5 and 10 can build against it.

---

## 1f. Provider Conduct & Reputation — 🔧 new in Round 15

Star ratings measure whether a customer *liked* the job. They say nothing about whether a provider turns up, honours the price they quoted, or answers at all — which are the three failures customers actually complain about, and the three that drove people to distrust the Facebook market in the first place. Conduct is a second axis, computed from booking outcomes rather than opinions, and it is the mechanism that makes "commitment" a real claim rather than a marketing line.

### The metrics — computed, never self-reported

| Metric | Definition | Notes |
|---|---|---|
| **Completion rate** | completed ÷ (completed + provider-cancelled + no-show) | The headline reliability number |
| **Cancellation rate** | provider-initiated cancellations after `accepted` ÷ accepted | Customer cancellations never count against a provider |
| **No-show rate** | confirmed no-shows ÷ accepted | Emergency no-shows (§1c) and completion-timeout abandonments |
| **On-time rate** | arrivals within 15 min of `scheduledFor` ÷ completed with an arrival mark | Slot and request modes only; emergency has no scheduled time |
| **Price adherence** | completions where `finalAmount` ≤ `agreedAmount` ÷ completions with both | The anti-hiking signal, and the reason `finalAmount` is mandatory |
| **Acceptance rate** | accepted ÷ (accepted + declined) — explicit responses only | Unchanged from Round 10; timeouts feed response rate, not this |
| **Median response time** | median seconds from prompt to explicit response | Timeouts excluded from the median, counted in response rate |

### Display — 🔧 objective metrics only, never editorial labels

**The public profile shows numbers and counts, and nothing else.** "94% on time · 3% cancelled · usually responds in 12 minutes · 47 jobs completed" — the customer draws their own conclusion.

🔧 **There are no system-generated warning labels.** "Prone to cancel" and "Price hiking" were considered in Round 15 and **rejected**: they are automated public accusations, computed from a handful of data points, in a market small enough that everyone knows everyone. A wrong label is somebody's livelihood and a plausible defamation claim, and the numbers carry the same decision value without asserting a character judgement. **Do not reintroduce editorial labels in any form**, including euphemistic ones.

- **Nothing displays below a 10-completed-booking floor.** Under that, show "New provider" and the job count. One cancellation out of two bookings is 50% and means nothing.
- **A rolling 90-day window**, so a provider who improves is not defined by last year.
- **Every metric is visible to the provider on their own dashboard before it is visible to anyone else**, with the underlying bookings listed. Nobody should learn their on-time rate from a customer.

### Consequences — graduated, and never silent

- **Alerts first.** Crossing a threshold notifies the provider with the specific bookings that caused it and what would clear it. A provider who does not know they have a problem cannot fix it.
- **Then ranking.** Sustained poor conduct lowers search position. This is the main lever, and it is proportionate — the provider is not removed, just less prominent.
- **Then emergency suspension.** Falling below thresholds removes `emergencyCapable` eligibility while the tier is retained. Emergency is the highest-trust surface and the first thing to lose.
- **Admin review, never automatic account action.** Suspension stays a human decision through Phase 10b, with the conduct record as evidence.
- **Appeal.** Any provider may contest a metric through the Phase 22 queue; a booking excluded on appeal is excluded from the aggregate and audit-logged.

### 🔧 Structured review tags — alongside the star rating

The 1–5 star rating stays. Each category additionally carries **six to eight fixed tags, positive and negative**, selectable in one tap: *On time · Fair price · Quality materials · Good communication · Left a mess · Arrived late · Poor communication · Price changed on site.*

- **Fixed per category, never free text.** Free tags cannot be aggregated, arrive in a mix of Dhivehi and English, and become a moderation surface.
- **Negative tags are the point.** A positive-only set makes every profile look identical and pushes criticism into free text where it cannot be counted.
- Tags aggregate on the profile as counts — "On time (31) · Fair price (28) · Arrived late (3)" — and a tag is only shown once it has been applied **three times**, so no single review can brand anyone.
- Rating a booking must be **two taps minimum**: stars, then optional tags. Review completion rate is what makes the whole system work, and every extra field costs completions.

## 1g. Local preference — 🔧 new in Round 15

Customers may filter to **Maldivian-owned businesses**. This is an attribute of the *business*, evidenced by the registration document Gold verification already collects, and it is verified rather than self-declared.

🔧 **It is deliberately not a nationality field on the individual.** Storing the nationality of every provider and letting customers exclude people by it is discrimination in most legal frameworks, would read very badly if it surfaced, and is not what the customer preference is actually about. Business ownership delivers the local-economy goal and the trust signal without profiling workers.

- Available only at **Gold**, because that is the tier carrying the registration document. Below Gold the attribute is absent rather than false.
- Surfaces as a filter and a profile attribute, never as a ranking boost — customers who care can filter; customers who do not are unaffected.

## 1h. Repeat use — 🔧 new in Round 15

**The problem this section exists to solve.** Payment happens off-platform and coordination cannot be enforced, so after one completed booking the customer has met a provider they liked and the provider has met a paying customer — and neither needs RaajjePro for the second job. Platforms that hold payment retain a reason to exist on transaction two; this one holds nothing. Everything below is a deliberate answer to that, and it is the difference between a subscription and a one-off lead fee.

### 🔧 The locked agreement — what "payment hold" means here

Round 15 considered holding customer funds until completion and **rejected it**: escrow means a payment gateway and almost certainly MMA licensing, which is a different company, not a feature. The behaviour wanted — no price hiking, no no-shows — is obtained instead by making the agreement itself immovable.

- At `accepted`, the **agreed price, date, time and scope are locked**. Neither party can alter them unilaterally.
- Any change requires an **explicit in-app amendment the other party accepts**. The original terms and the amendment are both retained.
- **Every amendment attempt is recorded**, accepted or not, and feeds price adherence (§1f). A provider who routinely revises upward on site has a number that says so.
- At completion, `finalAmount` above `agreedAmount` **without an accepted amendment** is a price-adherence failure and is visible on the profile as one.
- The customer's evidence in a dispute is therefore complete without RaajjePro ever touching money: agreed terms, amendment history, timestamps, chat, and both completion attestations.

### 🔧 Callback guarantee

A provider commits to **return free within 7 days** if the same issue recurs — honoured **only for on-platform bookings**, and enforceable because RaajjePro holds the record of what was agreed.

- Opt-in per listing, displayed as a badge, and a real differentiator against an unrecorded phone arrangement.
- A callback is a **new booking linked to the original**, at zero cost, so it flows through the normal machinery and appears in both parties' history.
- Declining an honoured callback claim routes to the Phase 22 dispute queue and counts against conduct.
- This is the clearest answer to "why book here instead of calling them directly": going direct forfeits it.

### 🔧 Saved preferences and one-tap rebooking

- **Saved addresses** with labels, **preferred time windows**, and **standing service instructions** ("gate code", "ask for the manager"), reused across bookings.
- Favourites already exist (Phase 14, saved *listings*); Round 15 extends them to **saved providers**, since customers remember a person, not a listing.
- "Book Again" (Round 10) carries the saved preferences forward, so a repeat booking is genuinely one screen.

### 🔧 Provider replacement on cancellation

A confirmed provider cancelling is the moment a customer decides the platform is unreliable. It must never dead-end.

- **Emergency bookings re-broadcast** through the normal §1c dispatch, excluding the cancelling provider. No new dispatch fee is incurred.
- 🔧 **Normal bookings do not broadcast.** The customer is dropped back into the booking flow with **service, date, time and preferences pre-filled**, so rebooking is a confirmation rather than a re-entry. Broadcasting a non-urgent job to every provider would be noise for them and pressure for the customer.
- The cancelling provider takes the conduct hit (§1f) in both cases.

## 2. Architecture Decisions

| Decision | Choice | Note |
|---|---|---|
| Backend framework | Fastify (TypeScript) | |
| ORM | Prisma | |
| Database | PostgreSQL | |
| Auth | JWT access + refresh rotation | per-device refresh tokens |
| Validation | Zod | |
| State management | Riverpod | |
| File storage | S3-compatible | payment proofs in a private bucket; **ID documents in a separate private bucket** (§1e) |
| Primary keys | **UUID for every entity** | removes the enumeration surface |
| Money | **Integer laari (MVR × 100)** | never float, never decimal-as-string; one type across every price, amount, and balance. MVR 150 = **15000 laari** |
| Deletion | **Soft-delete everywhere** | `visibility`/`status` field; nothing is ever hard-deleted |
| Job runner | **pg_cron or equivalent** | v1 had none yet relied on time-based expiry |
| Idempotency | **Client key on every money-adjacent and creation POST** | server dedupes on `(userId, operation, key)` |
| Rate limiting | **Global + per-endpoint tiers** | stricter on auth, OTP, payment, and emergency-booking endpoints. 🔧 **Messaging carries its own tier** — per-conversation and per-user message caps. The enquiry channel's content policy is deliberately permissive (§1c), so an uncapped-volume channel with only after-the-fact block and report is a real spam and harassment surface. |
| **Time conflicts** | **`EXCLUDE USING gist` on `(providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`** | 🔧 replaces `UNIQUE (providerId, listingId, startsAt)`, which let one provider be booked three times at 10:00 across three listings and did not detect overlapping durations at all |
| Push delivery | **FCM + APNs, built in Phase 3c** | ahead of Phase 17, which depends on it, with an explicit fallback chain |
| **Read caching** | 🔧 **Short-TTL cache (30–60 s) in front of Home, Search, and category browse** | §5's p95 < 400 ms target is achievable on indexes alone only at low volume. **No explicit invalidation** — the TTL is deliberately short enough that suspension, category edits, and the launch-mode flip self-correct within a minute, avoiding a bust-key matrix across every mutable input. Revisit read replicas once Phase 21 shows real read volume. |
| **API versioning** | 🔧 **Additive-only within `/v1`** | never remove or repurpose a field; mobile clients cannot be force-updated, so a breaking change would strand installed app versions. Deprecation policy written down in Phase 2, before the first breaking change is needed. |

---

## 3. Phased Roadmap

🔧 **A convention that applies to every frontend phase below.** Each phase's own "Done when" is not met until its screens specify their **loading, empty, error, and populated** states — the empty state naming what the user should do next, not merely reporting that nothing is there. Phase 20 keeps its audit as a backstop, but a single late QA sweep is the wrong place to *design* these: it produces copy and error handling bolted on after the fact, by someone no longer holding the context the screen was built in.


### Phase 0 — Repository & Environment Foundation

- Monorepo `/backend` (domain modules) + `/frontend` (Flutter, feature-based)
- TypeScript strict, ESLint, Prettier, commit hooks; Flutter lint config
- Env config strategy; `.env.example`; no secrets committed
- CI skeleton: lint + build, 🔧 **plus automated dependency scanning — Round 15**. It costs nothing at this stage and covers the highest-frequency real-world compromise path; Phase 20 is an internal audit against your own requirements and cannot find a class of problem nobody thought of.
- 🔧 **Point-in-time recovery configured from the first migration — Round 15.** WAL archiving with an RPO of 5 minutes or better (§5). Turning it on later does not recover what was lost before it was on.
- **Job runner wired up** (pg_cron or equivalent) with one no-op scheduled job proving it runs
- README documenting: UUID primary keys, integer-laari money, soft-delete convention, idempotency-key convention

**Done when:** both apps boot; lint clean; the scheduled no-op job is observably firing.

### Phase 1 — Design System & Shared UI Foundation

- Theme tokens: colours, typography (Plus Jakarta Sans / Inter), spacing, radius
- Shared widgets: buttons, `AppCard`, `StatusBadge`, chips, `StatMiniCard`, `RatingStars`, `AnimatedBottomNav`, `AppHeader`, `SaveHeartToggle`, `EmptyState`, `SkeletonLoader`, bottom-sheet shell
- Motion primitives: tap-scale, spring sheet, animated nav pill
- **Accessibility baseline, non-negotiable and built in here:**
  - minimum 48dp touch targets on every interactive element
  - WCAG AA contrast verified for all text and status colours (amber-on-white in particular)
  - `Semantics` labels on every control and icon-only button
  - `MediaQuery.textScaler` respected — no fixed-height text containers
  - every motion primitive has a reduced-motion path honouring the OS setting
- Component gallery route rendering everything with sample data

- 🔧 **Built RTL-ready, without shipping Dhivehi — Round 15.** Thaana is right-to-left, and §6 defers localisation while noting only the font consequence. The *layout* consequence is the expensive one: in Flutter, RTL is `Directionality`, `EdgeInsetsDirectional`, `start`/`end` and mirrored motion, not a translation file. A design system built with absolute directions is inherited by every later phase, making the retrofit a rewrite of the presentation layer. Use directional insets and alignment **exclusively** — no `EdgeInsets.only(left:)`, no `TextAlign.left`, no hardcoded row order. This costs nothing now and is the difference between adding a locale later and rebuilding the frontend.

**Done when:** the gallery renders every widget; a11y criteria verified with a screen reader and at 200% text scale; 🔧 the gallery also renders correctly under a forced RTL `Directionality` with no overlap or clipping; `flutter analyze` clean.

### Phase 2 — Backend Core Infrastructure

- Fastify bootstrap, `/v1` prefix
- Global error handling (validation / auth / authz / business-rule / conflict / not-found / infra / unexpected); never leak internals
- Structured logging with correlation IDs; no PII in logs
- Typed config module, fail-fast on missing vars
- Standard response envelope (success + error shapes)
- Prisma setup, migration workflow, UUID + soft-delete + integer-money conventions encoded in base schema patterns
- `GET /v1/health`
- **Rate limiting:** global tiers (unauthenticated per IP, authenticated per user) plus a per-endpoint override mechanism
- **Idempotency middleware:** reusable, keyed on `(userId, operation, clientKey)`
- **Admin identity model:** admin users, a single `admin` role for v1, login, session. Not a stub.
- 🔧 **TOTP MFA, mandatory on every admin account — Round 12.** Authenticator app, not SMS (there is none, §Phase 3). Enrolment required before the account can take any action, with recovery codes issued once. Reverses the earlier decision to defer admin hardening.
- 🔧 **Session controls — Round 12.** Active-session list with force-logout, a short idle timeout, and re-authentication before viewing an identity document. IP allowlisting stays out of scope (§7) — it locks the admin out when travelling.
- **Audit log:** every admin action records admin ID, timestamp, action, target, and reason. Queryable by date / admin / action type.

**Done when:** `/v1/health` returns 200; a malformed request returns the standard envelope; a repeated idempotent POST returns the original result; rate limits trigger correctly; an admin action appears in the queryable audit log.

### Phase 3 — Identity & Authentication

- Register, login, JWT access + refresh rotation, logout, `me`, password reset
- Social auth: provider-agnostic interface with stubs (Facebook/Google/Viber)
- 🔧 **Email verification replaces phone verification — Round 11. There is no SMS anywhere in this system.** OTP is sent to **email**, with an `emailVerified` flag and a `requireEmailVerified` guard (stricter than `requireAuth`, distinct `EMAIL_NOT_VERIFIED` error code). This guard is what gates booking, enquiry and messaging — every place the plan previously said `requirePhoneVerified`.
  - 🔧 **The provider is Amazon SES — Round 13.** $0.10 per 1,000 emails, against a new-account credit of $200 over six months that covers realistic launch volume many times over. Transactional email carries OTP, the Phase 3c fallback, and Phase 10b's admin alerting — it is the single delivery channel and therefore a single point of failure.
  - 🔧 **SES must be out of its sandbox before this phase starts, and that is not a formality.** A sandboxed account sends **200 messages per day, to verified addresses only** — which means the real registration flow, an OTP to an arbitrary new mailbox, cannot even be exercised until production access is granted. Leaving the sandbox requires attesting that **bounce and complaint handling is already in place**, so that work is a **Phase 0–2 prerequisite** (§4 Sequencing), not a Phase 3c task. AWS responds within 24 hours but may come back for more information; this must not sit on Phase 3's critical path, because Phase 3 gates booking, enquiry and messaging.
  - Deliverability setup is still required regardless of vendor: SPF, DKIM, DMARC, and a warmed sending domain.
  - 🔧 **Rate limits, explicit:** **3 OTP sends per email address per 15 minutes** *and* **5 per user account per hour** (both, not either). **5 verification attempts per issued OTP**, after which it is invalidated and a new send is required. Hitting either send limit returns `OTP_RATE_LIMITED` with the seconds remaining, so the UI can show a real countdown rather than a generic error.
- 🔧 **Phone number: collected, unique, and NOT verified.** Both `email` and `phone` carry a database-level unique constraint, so each can back exactly one account. A registration attempt against either an in-use email or an in-use phone is **blocked at the field**, naming which one is taken, with a route to login or password reset — never a generic failure and never a silent overwrite.
  - 🔧 **Foreign numbers are accepted — Round 15.** The 7-digit 7-or-9 prefix logic is a Maldivian assumption embedded across validation and contact-pattern detection. Resort guests and expatriate residents are plausible high-value customers, and rejecting their number at registration is a silently lost signup. Store numbers in E.164 with a country code, default to +960, and treat the 7/9 heuristic as Maldives-only rather than universal.
  - **Uniqueness is not ownership, and the UI must not imply otherwise.** Nothing proves the number belongs to the person who typed it, because the mechanism that proved it (SMS OTP) is gone. A phone number is displayed as user-supplied information, never with a check mark, never described as verified.
  - 🔧 **Uniqueness is enforced from Bronze, not from registration — Round 15.** An unverified phone number is **claimable**: several accounts may hold it, and none of them displays it as anything. Exclusivity begins only when an admin confirms the number during Bronze review, which already happens. This closes squatting as an attack rather than as an inconvenience — under the old rule one motivated person could register the numbers of every established tradesperson in Malé in an afternoon, and each victim's recovery was a manual review against a 5-business-day SLA, jamming the supply pipeline at exactly the moment it needs to fill. **If a number is already held at Bronze or above, registration is blocked at the field** as before.
  - 🔧 **Two consequences this creates, both handled by the admin, not by new infrastructure.** First, **squatting**: registering with someone else's number permanently blocks the real holder, who has no self-serve way to prove ownership. Second, **number recycling**: Maldivian numbers are reassigned on carrier churn, so a recycled number stays locked to a dormant account forever. Both resolve through the existing Phase 10b recovery queue — a claimant submits identity evidence and an admin releases the number.
  - 🔧 **The admin confirms the phone number during Bronze review** (§1e) — by calling it, or by matching it against the submitted identity document. This costs nothing new (Bronze is already a manual review) and it makes a verification tier mean the number is real as well as the person. Below Bronze, treat every number as unproven.
- **Account settings (backend + screens):**
  - change password, change email, change phone (each re-verified)
  - active session list + revoke — per-device refresh tokens so revoking one device doesn't log out the others
  - 🔧 **Saved preferences — Round 15 (§1h):** labelled addresses, preferred time windows, and standing service instructions, reused by every booking flow and carried forward by "Book Again".
  - data export — `GET /v1/users/me/data-export` returns the user's own data as JSON
  - 🔧 **Account recovery — Round 11.** Email is now the primary credential, so recovery runs the other way: a user who loses access to their email address recovers through **manual admin review** against the account record and their identity evidence, via Phase 10b's queue. There is no automated second channel, because SMS was it. Standard password reset (Phase 3b) still runs over email for anyone who retains mailbox access.
  - account deletion — App Store requirement. Anonymises all authored content: name/email/phone replaced with a placeholder, listings and reviews preserved so provider rating aggregates stay intact. Soft-delete, not purge. **ID documents (§1e) are purged, not anonymised.**
  - 🔧 **Deletion is queued, never refused — Round 9.** A deletion request is **accepted immediately** and the account is frozen (no new bookings, no new listings, hidden from search). Anonymisation executes automatically once every non-terminal booking reaches a terminal state, with a **hard 30-day backstop** after which it proceeds regardless. Refusing deletion outright while bookings are open — the earlier design — could block a user indefinitely on admin inaction, since `payment_unresolved` only clears when a human acts, and both Apple and Google require in-app deletion to actually work.
  - 🔧 **Admin internal notes (§Phase 10b) about the user are deleted with the account**, matching the anonymisation rule. Only the audit log's structured reason fields persist.
- Frontend: Login, Register (pixel-match), OTP verification screen (propose first), account settings sub-screens (propose first)

**Done when:** full register → verify → logout → login cycle works; an unverified user browses freely but is rejected by `requireEmailVerified`; 🔧 registering with an already-used email is blocked naming the email, and with an already-used phone is blocked naming the phone, each offering login or reset; both OTP rate limits verified independently; a deleted account's reviews remain with anonymised attribution; export returns complete data; 🔧 a deletion request with an open booking is accepted and freezes the account rather than erroring, completes automatically when that booking terminates, and completes anyway at the 30-day backstop; an email confirmation link verifies and a recovery attempt without one is refused.

### Phase 3b — Forgot Password Flow *(propose design first)*

Reset-token issuance, expiry, consumption; invalidates all refresh tokens on success. Three screens: request email → check-your-inbox confirmation → set new password.

**Done when:** a user can request a reset, receive a token, and set a new password that works on Login; the old refresh tokens are all invalid.

### Phase 3c — Push Notification Infrastructure

Sequenced after Phase 3 (device-token registration needs an authenticated user) and before Phase 9a/17, which depend on it.

- FCM (Android) + APNs (iOS) integration; device token registration, refresh, and multi-device support
- A single **`PushSender`** abstraction — the send interface every later module (17, 19) calls, not one each
- **Detect OS-level permission denial** and store that state on the user
- 🔧 **Two-rung fallback chain — Round 11 removed the SMS rung.** For the load-bearing prompt (Phase 17's provider-accept):
  - If push permission is **already known denied**: send **email immediately**, in parallel with the (futile) push attempt. Do not wait.
  - If push is permitted but **delivery is unconfirmed after 30 minutes**: send email.
  - **For emergency bookings (30-minute window), email fires immediately in all cases**, in parallel with push. There is no time for a ladder.
  - An earlier revision said "fails to deliver within the acceptance window" — the window is 24 hours, so a fallback could arrive at hour 23, after the booking had effectively died. The timings above are what fix that.
- 🔧 **No in-app notification toggle — Round 11.** The app offers no setting to disable booking notifications; they are transactional and always sent. **This cannot be enforced beyond the app:** iOS and Android both let a user revoke notification permission at the OS level and no app can override that. "Always enabled" therefore means *we do not offer a switch*, and the OS-denied case is exactly what the email fallback exists for. Marketing and digest sends remain opt-in and are unaffected.
- 🔧 **Fallback email content:** booking type, customer first name, job location island, and an instruction to open the app. **No links** — do not train providers to tap links in messages that claim a job is waiting. No amounts, no phone numbers.
- **Observability:** log every fallback invocation with reason. Alert if the email fallback exceeds 5% of accept prompts in a rolling day — that indicates a push-integration regression, not user preference.
- A persistent in-app reminder for a provider who has denied push at the OS level: *"You may miss booking requests — enable notifications."*
- 🔧 **Email is now the only delivery channel that works when push fails**, so its deliverability is load-bearing in a way it was not before.
- 🔧 **Bounce and complaint handling already exists by the time this phase starts — Round 13.** It is a Phase 0–2 prerequisite, because SES will not grant production access without it (§Phase 3). What this phase adds is the *consumption* side: the SNS event destination feeding a stored delivery/bounce/complaint record per message, the suppression list being honoured before send, and the reputation metrics being watched rather than merely collected.
- 🔧 **SES has no searchable activity UI, so the message log is ours to build.** Phase 10b needs to answer "did this provider actually receive the emergency alert?" in one lookup; on a hosted vendor that is a built-in console, on SES it is an event destination plus a queryable store plus a screen. Budget it here and surface it in Phase 10b — it is real scope that a hosted provider would have absorbed.

**Done when:** a test push arrives on a real device within seconds; a provider with push denied at the OS level receives an **email** fallback for a booking-accept prompt immediately, not at the end of the window; an emergency prompt fires push and email in parallel; the app exposes no toggle for booking notifications; multi-device registration and cleanup work; fallback invocations and bounces appear in logs.

### Phase 4 — Categories Module

- `Category`: id, name, icon identifier, color token, sortOrder, isActive, `bookingMode`, `emergencyCapable`, `minimumLeadTimeMinutes`, `emergencyAcceptWindowMinutes` (Round 12), and 🔧 **`emergencyMinimumTier`, `quoteExpiryMinutes`, `quoteApprovalMinutes` (Round 15)**. Unlimited categories — no hardcoded enum in schema or validation.
- **Seed exactly 12:** Cleaning, Plumbing, Electrical, AC Repair, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events, **Boat Charter**. 🔧 Boat Charter is new in v5 — picnics, fishing trips, sandbank excursions. Request-based, not emergency-capable; no schema fields beyond the standard set (§1c).
- 🔧 **Also seed, per category:** the `bookingMode` default (§1c); `emergencyCapable` — 🔧 **true for Plumbing, Electrical, AC Repair and Moving** (Moving added in Round 12); 🔧 **`minimumLeadTimeMinutes` — Round 14 set these, do not invent them:** Cleaning 180 · Beauty 120 · Fitness 120 · Plumbing 60 · Electrical 60 · AC Repair 60 · Computer 120 · Gardening 720 · Photography 1440 · Moving 1440 · Boat Charter 1440 · Events 2880. Only the three slot categories bite immediately, since they are the ones with a picker in Phase 9a; all twelve remain admin-editable from Phase 10b. and `emergencyAcceptWindowMinutes` — **30 for Plumbing, Electrical and AC Repair, 120 for Moving**, null elsewhere. A mover needs a vehicle and usually a crew, so the 30-minute figure set for a tradesperson with hand tools does not transfer. 🔧 **`emergencyMinimumTier` (Round 15)** — `gold` for Electrical and Plumbing, `silver` for AC Repair and Moving, null elsewhere. 🔧 **`quoteExpiryMinutes` / `quoteApprovalMinutes` (Round 15)** — 120 / 240 for Plumbing, Electrical, AC Repair and Computer; 1440 / 4320 for Photography, Gardening, Moving, Events and Boat Charter; null for the three slot categories, which do not quote. Phase 5 reads these, Phases 9/9a/17 consume them.
- `GET /v1/categories` — public, active categories sorted by sortOrder, including `bookingMode` and `emergencyCapable`.
- Admin-only POST/PATCH/DELETE against **real** admin auth from Phase 2.
- Frontend: Explore screen pixel-matched, grid driven entirely by the live endpoint.

**Done when:** a 13th category added via API appears in Explore with no rebuild; the seeded `bookingMode` and `emergencyCapable` values are readable by a downstream module; Boat Charter appears correctly as request-based, not emergency-capable.

### Phase 5 — Provider Profiles *(backend only)*

🔧 **Round 15 adds two attributes here.** `maldivianOwned` — a verified attribute of the *business*, evidenced by the registration document Gold already collects (§1g), exposed as a filter and a profile flag, **never as a ranking boost** and **never as a nationality field on an individual**. And the read surface for §1f's conduct metrics, which Phase 11 computes and Phases 5 and 12 display.

- `ProviderProfile`: userId, businessName, bio, yearsOfExperience, `verificationTier`, `verificationStatus`, `subscriptionPriceLaari`, createdAt
- **`jobsCompletedCount` derived from the booking event log**, never a hand-maintained counter
- 🔧 **Contact detail — phone number only.** v5 removes WhatsApp and Viber handles from this entity entirely; earlier revisions collected all three for eventual display to a customer. Neither is ever collected or shown now. The phone number that remains is the same one verified in Phase 3, used for OTP, account-level notification, and — 🔧 **as the single Round 9 exception** — the emergency contact reveal (§1c). Exactly one endpoint in this system, `POST /v1/bookings/:id/reveal-contact`, returns it to another user, under the conditions §1c specifies. No other endpoint does, and any that appears to is a defect.
- 🔧 **Verified email — new in Round 9, built in Phase 3.** The phone-compromise recovery path (§7) depends on a second verified channel that no revision of this plan ever built. Email is captured with a confirmation link alongside phone verification — optional at signup, promptable later, required to complete Phase 6a's provider onboarding. It serves three purposes at once: account recovery, the opt-in weekly digest (Phase 19), and Phase 10b's outbound admin alerting.
- **Payment details — load-bearing:** bank name, account name, account number, and/or other transfer instructions. This is the one piece of provider information that *is* shown to a customer — at the payment step of a booking — because the off-platform transfer can't happen without it. It is not contact information and the distinction matters: excluded from every response except the booking-scoped payment step, and from all logs.
- **`acceptingNewCustomers` at provider level** — one toggle gates all of a provider's listings, and billing pause keys off it coherently.
- **`bookingMode` default lookup** read from Phase 4's seed, overridable per listing (§1c)
- `getOrCreateProviderProfile(userId)` — idempotent, called by Phase 6a's onboarding flow and (as a fallback for anyone who reaches the wizard without it) Phase 8's draft-creation endpoint
- `findVisibleProviders(...)` — the single shared gate, filtering on derived published-listing count (§1a)

**Done when:** `getOrCreateProviderProfile` called twice returns one row; `findVisibleProviders` excludes a provider whose only listing is a draft and includes them the moment one is published, with no stored status field involved; 🔧 `findVisibleProviders` also excludes a suspended provider, verified from search, Home, and the public profile in one test; a provider's phone number is absent from every response except their own profile read **and the emergency reveal endpoint under its §1c conditions**; payment details are absent from every response except the booking payment step.

### Phase 6 — Customer Profile Module

- `GET /v1/users/me/profile-summary` — one call for the Profile screen
- `PATCH /v1/users/me`
- Frontend: Profile screen (pixel-match), five rows navigating to sub-screens
- **Role switcher:** an explicit customer ⇄ provider mode control. Providers are the only paying users; their workspace must not be buried. Propose the switcher's placement and the resulting provider-mode IA before implementing — this is the one navigation change that departs from the original mockups.
- Switching to provider mode for the first time routes into Phase 6a's onboarding flow rather than straight to the dashboard; a returning provider goes straight to My Services Dashboard.

**Done when:** Profile reflects live data; every row navigates; switching to provider mode for the first time reaches the onboarding flow, and reaches My Services Dashboard directly on every subsequent switch.

### Phase 6a — Become a Provider: Onboarding Flow

🔧 **New in v5.** Earlier revisions had no dedicated onboarding screen — starting a draft listing was the only moment that created a Provider Profile, and the account-level fields (phone, payment details, `acceptingNewCustomers`) were collected later, awkwardly, from inside the dashboard after the provider already had a live listing. v5 gives onboarding a real flow, sequenced before the wizard rather than folded into it.

No mockup exists. Propose a design before implementing — 2–3 screens reusing the established system, not a new visual language.

1. **Intro screen:** what being a provider on RaajjePro means in plain terms — subscription-only monetization stays invisible here (that's Phase 8a/10a's job, later), this screen is about the mechanics: publish a service, get bookings, get paid directly by the customer, communicate entirely through the app. A single CTA into the next step.
2. **Account details step:** collects the fields Phase 5 needs before a listing can meaningfully exist — phone number (pre-filled from Phase 3's verified number, confirmable rather than re-typed), payment/bank transfer details, and the `acceptingNewCustomers` toggle (defaulted on). This calls `getOrCreateProviderProfile` and then a new `PATCH /v1/providers/me` covering these fields specifically — reuse Phase 5's existing update endpoint, do not create a parallel one.
3. **Hand off directly into the Phase 9 wizard's Step 1**, pre-populated with nothing (a fresh draft), so the very next thing the provider does is describe their first service.
- A provider who abandons onboarding after step 1 or 2 (backs out, closes the app) and returns later resumes from wherever they left off — this reuses Phase 9's existing resume-a-draft logic pattern, applied one level earlier in the funnel.
- 🔧 **A "Not right now" action on the intro screen** returns the user to customer mode cleanly, leaving no orphaned draft and no resume prompt nagging them from the role switcher. Resuming where you left off is right for someone who *intends* to finish; it is the wrong behaviour for someone who started the flow, looked at what it involved, and decided against becoming a provider. Choosing it again later starts the flow fresh.

**Done when:** a brand-new user going through Home's "Become a Provider" CTA or Phase 6's role switcher lands on the intro screen, not the wizard directly; completing account details persists phone and payment details onto the Provider Profile via the existing Phase 5 update endpoint; the flow hands off into a fresh wizard draft; a provider who already completed onboarding never sees it again, going straight to the dashboard or a resumed draft instead.

### Phase 7 — Service Areas & Location Module

- Island reference data (real seed list, not five entries), `ProviderServiceArea` join table
- `POST`/`DELETE /v1/providers/me/service-areas`, `GET /v1/islands?search=`
- Frontend: searchable island multi-select as a **reusable widget** (embedded in the wizard's Location step in Phase 9 — build standalone, not screen-specific), header location bottom sheet

**Done when:** the multi-select works standalone against real API data; the header bottom sheet lets a customer pick a browsing island that persists for the session.

### Phase 8 — Service Listings: Backend Domain

- Fields matching all 7 wizard steps: Details, Location, Pricing, Media, Availability, Extra Info, Meta
- **Pricing is per-listing** (each listing carries its own model and rates), not per-provider
- **`bookingMode` per listing**, defaulted from the category seed, provider-overridable
- **`isEmergency` per listing**, settable only when the category is `emergencyCapable` **and** the provider is `verified` (§1c) — enforced on publish and update
- `acceptingNewCustomers` is **not** on the Listing entity — it is provider-level (Phase 5)
- Draft-save accepting partial/empty payloads; implicitly creates the Provider Profile; **requires an idempotency key**
- Publish endpoint: full required-field validation returning a structured missing-field list. 🔧 **Six required fields, not five:** name, category, short description, at least one island, a pricing model with its price, **and now a cover image.** v4 left the cover image optional at publish, which meant a listing could go live with a blank thumbnail — the first thing a customer sees on every card and in search results. Everything else (gallery beyond the cover, availability detail, extra info) stays optional.
  - **Also enforces the entitlement cap.** v1 checked the cap only at draft creation, so drafts made during a trial could all be published after downgrade.
- Media upload via presigned URL — **server-side content-type and size validation, EXIF stripping on every image**
- Soft-delete only; document cascade rules for a listing with bookings, reviews, or reserved slots
- **View and booking counts come from an event log with periodic rollup**, not per-request counter writes

**Done when:** a listing saves empty, patches per step, publishes only when complete and within cap; `isEmergency` is rejected on a non-emergency category or an unverified provider; a soft-deleted listing disappears from public queries while its bookings and reviews remain intact.

### Phase 8a — Subscription & Trial *(backend only)*

- Generic `PaymentSubmission`: payerId, `purpose` (v1: `subscription`; enum stays open), amount (laari), proofUrl, referenceCode, status, submittedAt, reviewedBy, reviewedAt, rejectionReason
- `ProviderSubscription`: providerId, tier, status (`trialing`/`active`/`free`/`paused`/`expired`), trialStartedAt, trialEndsAt, **billingAnchorAt**, currentPeriodEnd, pausedAt, cumulativePausedDays, remainingPauseAllowanceDays
- 🔧 **`amount` reads the provider's `subscriptionPriceLaari`** (§1b), defaulting to MVR 150 = 15000 laari for anyone outside the introductory cohort. Never a global constant and never a range.
- 🔧 **Trial starts on either trigger, whichever fires first** (§0.4):
  - the transition of any booking into `confirmed` where this is the provider's first — **hooked on the state transition, not on one endpoint**, so an admin resolving `payment_unresolved` to `confirmed` also fires it
  - `POST /v1/providers/me/subscription/start-trial` — an explicit provider-initiated "Try Premium"
  - 🔧 **A third, proactive trigger: prompt "Try Premium" automatically 7 days after a provider's first published listing** if no booking has landed and no trial has started. Without it the confirmed-booking trigger is close to decorative for the provider it most needs to reach — a new provider is capped at one listing, and reaching `confirmed` requires publish → accept → payment → attestation → provider confirmation, realistically days to weeks after signup. The explicit button would otherwise be the only trigger that ever fires in a useful timeframe, and it only fires for a provider who already went looking for it.
  - All three call the same `startTrial(providerId)` function, which is a no-op if a trial has ever run for that account.
- 🔧 **Billing anchor, not calendar month** (§1b): 30-day periods from `billingAnchorAt`; pausing shifts the anchor by the paused duration.
- **Pause logic shared between `trialing` and `active`** — one function, one 10-cumulative-day cap, resume-remaining-time semantics, forced auto-resume at the cap, applied identically regardless of state.
- **Scheduled jobs** (Phase 0's runner, not check-on-read): 7-day-out warning, expiry → grace, grace → downgrade, **win-back notifications at 7 and 30 days post-downgrade**
- **Downgrade listing-protection:** before hiding any listing, exclude any with a non-terminal booking and a future `scheduledFor` (§1b)
- `getProviderEntitlements(providerId)` — the single source of tier truth, **live DB read every call**, no caching, nothing granted on a `pending` submission
- Endpoints: upgrade-request, subscription status, pause/resume, start-trial
- Admin: confirm / reject / **reverse** a submission, plus the pending list. All audit-logged.
- **Idempotency key required** on every submission-creating call
- **PDF invoice** generated on confirmation

**Done when:** a trial starts on first confirmed booking *and* independently on an explicit request, and never twice; an admin resolving `payment_unresolved` to `confirmed` fires the trial hook; pause behaves identically during trial and paid period and correctly shifts the billing anchor; a downgrade skips hiding any listing with a confirmed future booking and hides it the moment that booking completes; a `pending` submission grants exactly nothing; a reversal restores prior state and is audit-logged.

### Phase 9 — Create/Edit Service Wizard: Frontend

- Steps 1–7 pixel-matched, wired to Phase 8
- Step navigation never blocked; Review always reachable
- **Progress framing shows "N required fields left to publish"** alongside or instead of "Step 1 of 7" — 🔧 **six fields are required as of v5** (name, category, short description, one island, pricing, and now a cover image — §Phase 8), and leading with the step count overstates the commitment
- 🔧 **Step 1's tags are selectable chips, not free-text entry — Round 12.** A category-scoped set of suggested tags renders as tappable pills, with free text underneath for anything not covered. Typing a tag from memory asks a provider to guess what customers search for; showing the options turns it into recognition. The helper line stays — *"Relevant tags help customers find you in search"* — so a provider understands why the field is worth filling in, not just that it exists
- Step 5 (Availability) surfaces `bookingMode` and, where the category allows it, the `isEmergency` toggle with a clear explanation of the 30-minute response expectation and the verification requirement
- **Offline resilience:** every step's autosave PATCH is queued locally on failure and replayed on reconnect. **Step navigation is blocked until the current step's data has persisted** — the wizard is the highest-value conversion flow in the app and must not silently lose work on a weak atoll connection.
- Over-cap new-draft attempt shows an upgrade prompt, not a generic error

**Done when:** a service can be created end-to-end; the app can be killed mid-wizard and resumed; airplane-mode transitions queue and replay correctly; publish is blocked with the exact missing-field list; the emergency toggle is unavailable and explained on an ineligible category or unverified provider.

### Phase 9a — Availability, Time Slots & Reservations

No mockup exists. Propose the provider-side slot management UI and the customer-side slot picker before implementing.

**Backend:**
- `TimeSlot` (providerId, listingId, startsAt, endsAt, status `open`/`reserved`/`blocked`), generated from the listing's availability rules with individual override
- 🔧 **`Reservation`** — a provider-scoped table backing *both* slot bookings and accepted request-based bookings, with **`EXCLUDE USING gist (providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`**. This is the hard guarantee against double-booking. It replaces v2/v3's `UNIQUE (providerId, listingId, startsAt)`, which allowed one provider to be booked three times at 10:00 across three listings and never detected overlapping durations at all.
- Reservations are created inside the booking transaction; a race resolves to exactly one winner
- **Provisional reservations** (§1c) for offered quotes, with a 72-hour expiry swept by a scheduled job
- Cancellation, decline, or timeout releases the reservation
- Holiday and exception handling: providers block ranges (Ramadan hours, travel, public holidays)
- 🔧 **Slot generation window: 60 days rolling**, regenerated 🔧 **incrementally and per-provider — Round 15**, not as a global nightly sweep. Only rules that changed regenerate, and the job carries a stated wall-clock budget with a Phase 21 alert on overrun. A global regeneration is trivial at fifty providers and is the first job that becomes a problem at a thousand, colliding with the day's first bookings. An availability-rule change regenerates **future unreserved slots only** — reserved slots are never touched by a rule change. v3 left the window, the regeneration trigger, and the rule-change behaviour all unspecified.
- Endpoints: generate/regenerate, block/unblock, list open slots for a listing
- 🔧 **The list-open-slots query filters on `startsAt > now()` in addition to `status = 'open'`.** A slot that was open a moment ago and hasn't yet been cleaned up by the nightly regeneration job must never be returned as bookable just because its status hasn't caught up — this is a query-time guarantee, not something that depends on job timing.

**Frontend:** provider slot management in the dashboard; customer slot picker showing **only currently open, not-yet-passed slots**, never an unavailable or already-elapsed time.

**Timezone:** all times stored UTC, presented in Maldives time (UTC+5). Document the convention; a single-timezone market makes this simple, but boundary days still need a stated rule.

**Done when:** two concurrent booking attempts on the same slot resolve to exactly one success and one clear "no longer available" error under real concurrency; a slot-based and a request-based booking that overlap in time on the same provider cannot both succeed, even on different listings; a cancelled booking's slot reappears; a blocked range removes those slots; an expired quote's provisional reservation is released; a slot whose `startsAt` has just passed disappears from the picker immediately, without waiting on the regeneration job.

### Phase 10 — My Services Dashboard

- Stats row, filter pills, list/grid toggle, service cards with context menu, live toggle
- Reachable in one action from the Phase 6 role switcher
- **Slot management entry point** (Phase 9a)
- Renders correctly for a provider with only drafts
- **Badge indicator reflects `verificationTier` alone** — not subscription state (§1e); Bronze, Silver and Gold render distinctly, each with the honest copy §1e specifies

**Done when:** every context-menu action performs a real mutation with no manual refresh; a drafts-only provider sees a correct zero state; the badge persists through a subscription lapse.

### Phase 10a — Provider Billing UI & Admin Panel

**Part 1 — Provider Billing (Flutter).** No mockups; propose first.
- Subscription status: trial countdown / next billing date / free-tier state, upgrade CTA, **"Try Premium" CTA for a provider who has never started a trial** (§0.4)
- Payment Proof Submission: bank details, reference code, upload, submit — built once, parameterised by purpose
- Submitted state shows "pending admin confirmation" with no implication of instant activation
- Rejection shows the reason, with **immediate resubmit** and **appeal** actions
- **Invoice list** with PDF download per confirmed payment

**Part 2 — Admin Panel (separate internal web app).** Propose the stack before building; optimise for low effort.
- Pending `PaymentSubmission` list with proof image, submitter, amount, reference code
- Confirm / reject (reason required) / **reverse**, all audit-logged
- **Bank-statement CSV import with reference-code auto-matching** — proposes matches for one-click confirmation
- **Identity verification queue** (§1e): submitted evidence, decision, rejection reason, all logged; documents served via short-lived signed URLs and access-logged
- **`payment_unresolved` queue** with a 🔧 **5-business-day resolution target** and an alert when any item ages past it or the queue exceeds 25 open items
- 🔧 **Unmatched-transaction queue** for CSV rows the reference-code matcher could not resolve — a garbled reference, an amount that does not match the submission, or a payment split across two transfers. Each is resolvable manually against a searchable list of open submissions. The importer's auto-matching assumes reasonably clean data; real manual bank transfers routinely are not, and without this the admin has no path for a row that does not match cleanly.
- Audit log viewer (Phase 2)
- 🔧 **Security, mandatory and now specified rather than deferred to implementer judgment.** This app renders user-authored text (listing descriptions, review bodies, enquiry messages) and is the tool that approves money. A malicious provider can plant a script payload in a description and report their own listing to guarantee an admin views it.
  - **Build it in React** (or another framework with default-on JSX escaping). Do not server-render raw HTML string concatenation.
  - **No `dangerouslySetInnerHTML` anywhere**, enforced by an ESLint rule that fails the build.
  - **CSP header:** `default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`. No `unsafe-inline`, no CDN origins.
  - **User-authored fields are rendered as text nodes only** — never as HTML, never as a URL in an `href` without scheme validation.
  - Test with a stored `<script>`, an `<img onerror>`, and a `javascript:` URL in a listing description, a review body, and an enquiry message.
- Real admin auth from Phase 2; never publicly reachable without credentials

**Done when:** a provider submits with proof and sees pending; an admin confirms and the entitlement activates; a rejection surfaces its reason with working resubmit and appeal; CSV import proposes correct matches; the three XSS payloads above render inert in every admin view; an aged `payment_unresolved` item triggers its alert.

### Phase 10b — Admin Panel: Accounts, Config, Search & Shell

**Scoped in response to the v5 adversarial review (§9, Round 8): Phase 10a gives the admin a way to approve money and identity, but no way to look at a user, see whether the business is healthy, or find anything without knowing which queue it's in. This phase closes that gap.** Extends Phase 10a's app, auth, and audit log — not a new stack.

**Account management**
- User directory: search by phone number or name, filterable by role (customer/provider) and status
- Detail view: profile, listings, booking history, reports filed against/by, verification history, all in one place
- **Suspend / unsuspend**, reason required, audit-logged. Suspension blocks new bookings and listing publication; existing non-terminal bookings are unaffected (consistent with §8's block-on-delete rule) until they resolve on their own.
- **Ban and hard-delete remain manual database operations**, not panel actions — deliberately excluded from v1 to avoid a single-admin credential having one-click destructive reach over an account (§7 residual risk)
- **Read-only "view as user"**: renders the user's own view of their listings, bookings, and subscription state exactly as they see it, for diagnosing "I can't see my booking"-class support requests. No ability to act as the user. Every use is access-logged with the viewing admin, target user, and timestamp — same signed-URL-and-log pattern as identity documents in Phase 10a.
  - 🔧 **Message content is excluded, Round 9.** Since §1c makes chat the sole channel, those threads carry home addresses, gate codes, and photos of people's houses. View-as-user renders listings, bookings, and subscription state and **never message bodies**. An admin reaches a thread only through a specific report or dispute that names it, scoped to that thread alone and logged separately — which is also the only form of access Phase 23's privacy policy has to describe.
- **Suspension feeds `findVisibleProviders` (§1a)** — a suspended provider disappears from search, Home, and the public profile through the one shared query, rather than staying listed and failing at booking time.
- **Booking intervention stays as specified in Phase 17/10a — dispute and `payment_unresolved` resolution only.** No general force-cancel or state override was added; a booking stuck in any other state has no in-panel escape hatch. Flagged as a known gap, not an oversight — revisit if it proves to bite.

**Config management**
- **Categories are admin-editable**: name, icon, active/inactive, and 🔧 `minimumLeadTimeMinutes` (the per-category slot lead time) — CRUD, audit-logged
- 🔧 **`bookingMode` is editable only while no live data depends on it, Round 9.** The change is blocked outright when any published listing in that category has open time slots or non-terminal bookings, with the blocking listings named. Flipping Cleaning from `slot` to `request` would otherwise orphan every published TimeSlot and leave confirmed future bookings pointing at a mode their listing no longer has — a migration the plan never defined. Name, icon, lead time and active/inactive stay freely editable.
- **Emergency-eligible categories remain code-defined** (§1c: Plumbing, Electrical, AC Repair). This list is a safety decision, not configuration.
- **Launch-mode threshold (§Phase 16, the 50-listing gate) is admin-editable**, with the current listing count shown alongside it so the admin can see how close the platform is before flipping it
- These surfaces are read *and* write — reversing the plan's original "categories are code+migration" posture, so a spec change like v5's own Boat Charter addition doesn't need a deploy

**Internal notes**
- Free-text notes attachable to a user, a booking, or a verification/dispute case
- Timestamped, attributed to the authoring admin, never visible to the subject user
- Shown inline on the relevant record (user detail, booking detail, verification/dispute case) — not a separate notes screen
- 🔧 **Deleted with their subject's account** (§Phase 3). Notes are free text about a real person and would otherwise survive both §1e's 90-day document purge and Phase 3's anonymisation, leaving undisclosed personal data the plan never scoped. Structured reasons in the audit log persist; the free text does not.

**Alerting (pushed, not just displayed)**
- The existing in-panel alerts (aged `payment_unresolved`, queue over 25 items, email-fallback rate above 5% from Phase 21) additionally fire **outbound** — email or Slack/Telegram — so a single admin who hasn't opened the panel still gets the SLA-breach warning
- New disputes and verification submissions also push on arrival, not only on aging
- 🔧 **De-duplicated per threshold crossing.** A queue-depth or SLA breach notifies once when the threshold is crossed and again only after it clears and re-crosses — not on every scheduled run. An alert that fires every fifteen minutes while a queue is deep gets muted within a day, which is the failure mode this whole mechanism exists to prevent.

**Kill switches**
- Admin-flippable, audit-logged flags for: emergency bookings, new registrations, new listing publication, and the emergency contact reveal (§1c)
- 🔧 **Email is three separate switches, not one — Round 9's reasoning, applied to email after Round 11 removed SMS.** `OTP email`, `notification/fallback email`, and `marketing email`. 🔧 **Round 13:** these map onto three SES **configuration sets**, which is also what keeps their reputation metrics separate — a complaint spike on the opt-in digest must not be able to degrade the sending reputation that OTP depends on. A single outbound-email switch would also kill OTP — now the *only* verification channel — locking every user out of registration and any new-device login, and simultaneously disabling Phase 3c's push→email fallback. That is a platform outage, not an incident control. The risk is higher than it was under SMS, because email is now the sole channel rather than one of two.
- A persistent banner in the panel (and, where relevant, in the Flutter app) while any flag is off, so a flipped switch doesn't get forgotten
- These are incident controls, not a general feature-flag framework — no admin-defined flags in v1

**Global search**
- Single command-palette search (⌘K) across users (phone/name), bookings (ID), and payments (reference code); typed input routes to the matching record type
- Each list screen also keeps its own scoped filter — the command palette is for "I have an ID or a phone number," not for browsing

**Shared list/table conventions** (apply to every queue and list added by Phase 10a and this phase)
- Filter by status/date/type, sortable columns, server-side pagination with a visible total count
- Shared date-range control with presets (today, 7 days, 30 days, custom)
- CSV export of the current filtered view — 🔧 **carrying IDs, statuses, dates, amounts and counts only, never phone numbers, names, email addresses or bank details.** Round 9: §1e protects identity documents carefully, but an unrestricted export of the user directory would let every phone number on the platform leave in one click, from a single credential with no MFA, no IP allowlist and no session controls (all deliberately declined, §7). Exports stay useful for reporting without becoming an exfiltration path.

**Shell**
- Persistent sidebar navigation; each queue item shows its live open-count badge
- Consistent severity colour coding across every screen — anything past its SLA is visibly flagged the same way everywhere

**Explicitly not in this phase** (raised and declined during scoping): proactive risk-signal dashboard — Phase 22's contact-pattern and cancel-pattern signals stay report-driven, surfacing only alongside a filed report; bulk queue actions and keyboard triage — every queue item is still reviewed and actioned individually; provider broadcast messaging — no in-panel way to reach providers as a segment; IP allowlisting, forced session controls, and MFA — admin auth stays exactly as specified in Phase 2, consistent with §7's accepted single-admin risk.

**Done when:** an admin can find any user, booking, or payment by phone/name/ID/reference code in under two actions; suspending a user removes them from search and Home via `findVisibleProviders` and blocks new bookings without touching an in-progress one; view-as-user renders listings and bookings, is access-logged, and exposes no message content; a booking-mode change is refused while the category has open slots or live bookings and names them; flipping the OTP-email kill switch does not affect notification email or marketing email, and vice versa; a kill switch shows its banner everywhere relevant within one page load; a pushed alert arrives outside the panel and does not repeat while the threshold stays breached; a CSV export of the user directory contains no phone number, name, email, or bank detail.

### Phase 10c — Admin Ops Dashboard

🔧 **Split from Phase 10b in Round 9.** The dashboard's trend lines read Phase 21's `ProductEvent` log, so sequencing the whole panel behind Phase 21 would have pushed account search, suspension, config, and global search — all needed operationally from first launch — behind twenty phases of work. Only this part waits.

- KPI cards: open items across every queue, bookings today/this week by status, active/trial/paid provider counts, listings vs. the launch-mode threshold
- Two trend lines: bookings over time, and trial-to-paid conversion **split by `subscriptionPriceLaari` cohort** — this is what makes §1b's introductory-pricing decision measurable rather than a guess
- Recent-activity feed: latest audit-log entries (what was approved/rejected/resolved, by whom)

**Done when:** the trial-to-paid line matches a manual query of the same data, and separates the introductory-rate cohort from the standard-rate one.

### Phase 11 — Reviews & Ratings *(backend)*

- `Review` tied to a **`completed`** booking. One review per booking, enforced.
- Rating aggregation per listing and per provider; star breakdown, computed transactionally on write
- **Auto-completion (Phase 17) is what makes this safe.** Gating reviews on completion is correct *only* because a provider can no longer block completion indefinitely.
- 🔧 **Structured review tags — Round 15 (§1f).** Six to eight fixed tags per category, positive and negative, selectable in one tap alongside the star rating. `ReviewTag` seeded per category; never free text. A tag is only displayed once applied **three times**, so no single review brands anyone. Rating must stay **two taps minimum** — review completion rate is what makes the whole system work, and every extra field costs completions.
- 🔧 **Provider conduct metrics — Round 15 (§1f), computed here, displayed in Phases 5 and 12.** Completion, cancellation, no-show, on-time, price adherence, acceptance and median response time, all derived from booking outcomes rather than opinions, over a **rolling 90 days**, recomputed on booking terminal transitions rather than on read.
  - **Nothing displays below 10 completed bookings** — show "New provider" and the job count. One cancellation out of two is 50% and means nothing.
  - 🔧 **Never generate editorial labels.** "Prone to cancel", "Price hiking" and every euphemism were considered and rejected (§1f): automated public accusations from thin data, in a market where everyone knows everyone. Emit numbers only.
  - **The provider sees their own metrics before anyone else**, with the underlying bookings listed, plus an alert on crossing a threshold naming what would clear it.
  - Appeals route through Phase 22; an excluded booking leaves the aggregate and is audit-logged.
- Soft-delete; a hidden review is excluded from aggregates
- 🔧 **Authorship is retained internally after the author's account is anonymised** — never shown publicly, never returned in any response, but preserved so a disputed review can still be traced and adjudicated. Phase 3's anonymisation otherwise lets a customer post a fabricated review, delete their account, and leave the provider with no way to identify or contest the source, since the accountability trail is severed by design.

**Done when:** posting a review updates the aggregate; a second review on the same booking is rejected; hiding a review recomputes the aggregate.

### Phase 12 — Service Preview (Public Listing Page)

- `GET /v1/listings/:id/public` and `GET /v1/providers/:id/public-summary`
- **Neither response ever contains contact or payment details.** Not "for now", not behind a flag.
- Frontend: hero with overlay controls, provider identity badge, About / Reviews / Provider tabs, sticky footer
- **Book Now** routes by `bookingMode` — slot picker, request form, or (where offered) an emergency toggle presented alongside the normal path with its callout-fee expectation stated up front. Unverified users route to phone verification first.
- **"Message" button restored** (§1c) — opens the pre-booking enquiry thread
- **Report affordance** in the overlay controls (Phase 22)
- **Provider response-time metric displayed** (Phase 19 computes it)

**Done when:** live data renders end-to-end; the Edit control appears only for the owner; the raw API response contains no contact or payment data under any circumstance; each booking mode routes to the correct entry point.

### Phase 13 — Provider Public Profile *(propose design first)*

- Backend reuses `findVisibleProviders` (§1a). Returns not-found for a provider with no published listings, even by direct id.
- Same contact/payment exclusion as Phase 12
- Frontend: header, stats grid, listings grid, response-time metric, not-found state

**Done when:** renders for a visible provider; returns a proper not-found state for a drafts-only provider's id; no contact data in the response regardless of viewer.

### Phase 14 — Favorites (Saved Services and 🔧 Providers)

🔧 **Round 15 extends favourites to providers, not only listings.** Customers remember a person, not a listing — and taking a provider's phone number to remember them is exactly the behaviour §1c's contact rule exists to prevent. Saving a provider is the on-platform substitute for that.

Save/unsave endpoints, saved list, heart toggle wired everywhere with optimistic update and rollback, Saved Services screen (propose first).

**Done when:** tapping the heart anywhere persists via API; the Saved Services screen reflects it immediately; Profile's count updates.

### Phase 15 — Search & Discovery

- Search endpoint with filters, sort, pagination, appropriate indexes
- 🔧 **Sort options, in this order — Round 12: distance, then rating, then price.** Distance leads because a provider who cannot reach your island is not a result at all. Price-range filter alongside. v1 had four fixed chips and no sort, thin for the primary discovery mechanism
- 🔧 **Booking-mode affordance on every result card** (§1c): "Book instantly" / "Request a time", plus an "Emergency available" marker
- **Priority placement** for premium subscribers affects ordering *within* the genuinely relevant result set, never membership in it
- **Any paid influence on ordering carries a visible "Sponsored" label.** No unlabelled paid placement.
- **No visibility difference between verified and unverified providers** in baseline search. Verification affects the badge, not findability.
- Frontend: results page (propose first), filter/sort wiring

**Done when:** results are correct, paginated, and filtered; priority placement never surfaces an irrelevant listing; every boosted result is labelled; every card states its booking mode.

### Phase 16 — Home Feed

- Section endpoints: popular-near-you, featured-providers (via `findVisibleProviders`), popular-this-week, nearby, recently-viewed
- **Launch mode, mandatory:** below a catalogue-size threshold (🔧 default **50 published active listings**, tunable via config without a code change), Home collapses to **two sections plus the category grid**. The full layout unlocks above the threshold. Nine rows over twenty listings shows the same services repeatedly and reads as an abandoned product. Propose the launch-mode layout before implementing.
- **Deep links / web fallback:** listings and provider profiles resolve via real URLs with universal links / app links and a minimal web fallback page. v1 justified open guest browsing partly on SEO while having no web surface to index, and shipped a Share button with nothing to share.
- **Trust grid** — 🔧 "Verified" copy must state what it means. In the Maldives a customer may read "Verified Provider" as "has a good track record" rather than "passed an ID and trade check." Use explicit copy: *"ID and trade checked by RaajjePro."*
- "Become a Provider" routes into the wizard, resuming an existing draft if one exists

**Done when:** every section shows live, correctly-empty, or correctly-loading state; launch mode renders convincingly against a twenty-listing seed; a shared listing URL opens the app when installed and the fallback page when not.

### Phase 17 — Bookings Module

🔧 **Round 15 adds four things to this phase, all specified in §1c and §1h.** Build them in the slice named:
- **17.1 — the locked agreement.** At `accepted`, `agreedAmount`, `scheduledFor` and scope lock. Changing any of them requires an explicit amendment the counterparty accepts; the original and the amendment are both retained; **every attempt is recorded whether accepted or not** and feeds price adherence. `finalAmount` above `agreedAmount` with no accepted amendment is a price-adherence failure. This is what "payment hold" means here — **do not build escrow, funds holding, or a payment gateway.**
- **17.1 — provider replacement.** A provider cancelling after `accepted` must never dead-end the customer. Emergency re-broadcasts (17.3). Everything else drops the customer into the booking flow with **service, date, time and saved preferences pre-filled** — non-urgent jobs are not broadcast. The cancelling provider takes the conduct hit either way.
- **17.3 — `EmergencyOffer`.** bookingId, providerId, calloutFeeLaari, createdAt, state. Offers now coexist: `emergency_offered` means *collecting and awaiting the customer*, not *claimed*. Plus the 90-second collection window, the MVR 200 dispatch fee, and the no-show re-dispatch path.
- **17.4 — the callback guarantee.** Opt-in per listing, displayed as a badge. A claim within 7 days creates a **new booking linked to the original at zero cost**, so it flows through the normal machinery and appears in both histories. Declining an honoured claim routes to Phase 22 and counts against conduct. This is the clearest answer to "why book here rather than calling them directly" — going direct forfeits it.

The largest phase and the highest-risk one. No mockups — propose each frontend piece before implementing.

🔧 **Build in four sequential slices**, each independently testable, rather than as one unit. Phase 17 carries three booking modes, five scheduled jobs, quote flows, recurring series, reschedule, and dispute/escalation paths. Attempting it in one pass is the single largest delivery risk in this plan.
- **17.1 — slot-based core:** create, accept, decline, claim-payment, confirm-receipt, complete, cancel, the 24-hour and 7-day jobs
- **17.2 — request-based and quotes:** quote offer/approve, provisional reservations, the 72-hour quote-approval job
- **17.3 — emergency:** the restricted path, callout fee, final-amount field, 30-minute window, rate limits, the no-acceptance fallback offer
- **17.4 — recurring series and reschedule**

**Backend:**
1. `Booking`: listingId, customerId, providerId, `bookingMode` (`slot`/`request`/`emergency`), timeSlotId (nullable), reservationId (nullable), status (§1c, including `awaiting_payment` and `payment_unresolved`), `agreedAmount` (integer laari, nullable until set), `amountKind` (`listing_price`/`quote`/`callout_fee`), quotedAmount, **`finalAmount` (integer laari, nullable — emergency only, §1c)**, `scheduledFor`, amountSetAt, paymentClaimedAt, paymentAttestedAt, completedAt, `completedVia` (`confirmed`/`unconfirmed`), statusHistory
2. `POST /v1/listings/:id/bookings` — slot-based reserves in-transaction; request-based captures a preferred window; emergency captures no timing constraint but **validates category eligibility, provider verification, and the customer's emergency rate limit**. 🔧 `requireEmailVerified` (Round 11); idempotency key required.
3. `PATCH /v1/bookings/:id/accept` — sets `agreedAmount` for slot and request bookings; **for emergency, accepts without an amount and moves to `accepted` pending the callout fee**. No contact info is ever exposed by this or any later step (§1c) — the `booking`-type chat opens here instead (Phase 18).
4. 🔧 **Emergency dispatch, rebuilt in Round 12 and again in Round 15.** `set-amount` disappears as a separate step; the fee arrives with the acceptance. **Acceptances no longer race** — they create offers that coexist, and the customer chooses.
   - On creation, an emergency booking **broadcasts** to every eligible provider — emergency-capable category, island match, `verificationTier` meeting the category's `emergencyMinimumTier` (gold for Electrical and Plumbing, silver for AC Repair and Moving — never hardcode), `acceptingNewCustomers` on.
   - `PATCH /v1/bookings/:id/emergency-accept` — provider **creates an `EmergencyOffer`** and supplies `calloutFee` in the same call. 🔧 **This no longer claims the booking — Round 15.** The first offer opens a **90-second collection window** during which every other eligible provider may also offer. Status → `emergency_offered`, which now means *offers are collecting and awaiting the customer*, not *one provider has claimed this*. There is no `ALREADY_CLAIMED` race between providers any more; atomicity applies only to the offer the customer selects.
   - `PATCH /v1/bookings/:id/emergency-offer-response` — customer selects one `offerId` from **up to three offers shown side by side** (provider, tier, rating, distance, fee), or rejects all. Selecting sets `agreedAmount` from that offer's `calloutFee` with `amountKind: 'callout_fee'` → `awaiting_payment`, releases the unselected providers immediately rather than leaving them on a spinner, and 🔧 **incurs the MVR 200 dispatch fee (§1c)** — recorded as owed, never blocking dispatch. Reject-all → back to `requested`, re-broadcast, and **every** provider who offered is added to `rejectedProviderIds`.
   - **Scheduled job — offer expiry:** a collection window whose customer has not responded **5 minutes** after it closes → release all offers, return to `requested`, re-broadcast.
   - 🔧 **Provider no-show — Round 15:** the customer may mark *"provider has not arrived"* once the category's accept window has elapsed → release the provider, record a no-show against conduct (§1f), re-broadcast excluding them, and **no second dispatch fee**. No admin in the loop; an emergency cannot wait for a queue.
   - **Scheduled job — request expiry:** a `requested` emergency booking older than its category's `emergencyAcceptWindowMinutes` (30 for the three trades, 120 for Moving) → auto-decline, notify, offer re-broadcast or conversion to a request-based booking. Offer rejections and expiries do **not** reset this clock.
5. `PATCH /v1/bookings/:id/quote` / `/approve-quote` — request-based path. Offering a quote creates a **provisional reservation** (Phase 9a); approving converts it to firm.
6. `PATCH /v1/bookings/:id/decline` — provider; frees the slot/reservation; distinct from dispute.
7. **Scheduled job — accept timeouts, three distinct conditions:** emergency `requested` older than **30 minutes**; slot/request `requested` older than **24 hours**; `quote_offered` older than **72 hours from the quote timestamp** (not from booking creation). Each releases its reservation and notifies the correct party.
8. `PATCH /v1/bookings/:id/claim-payment` — customer self-attestation.
9. `PATCH /v1/bookings/:id/confirm-payment-received` — provider; → `confirmed`.
10. **Scheduled job:** `payment_claimed` with no provider response after 7 days → `payment_unresolved`. Notifies both parties, files a Report (Phase 22). **No entitlement or additional access is granted by this transition.**
11. `PATCH /v1/bookings/:id/dispute` — either party; → `disputed`; files a Report.
12. `PATCH /v1/bookings/:id/resolve-dispute` — admin; → `dispute_resolved` with an **enumerated outcome** (§1c); also resolves `payment_unresolved` to `confirmed` or `cancelled`.
13. `PATCH /v1/bookings/:id/complete` — provider; → `completed`, `completedVia: 'confirmed'`. 🔧 For emergency bookings this endpoint **requires `finalAmount`** — the real settled total once parts and labour were added to the callout fee. The request is rejected without it, the same way `awaiting_payment` cannot be reached without `agreedAmount`. It is the number a price dispute needs, and a provider has no incentive to volunteer it when it reflects badly on them.
14. **Scheduled job:** `confirmed` 7 days past `scheduledFor` with no completion → customer "Did this happen?" prompt; a further 3-day non-response auto-completes with `completedVia: 'unconfirmed'`.
15. `PATCH /v1/bookings/:id/cancel` — customer, pre-payment; frees the reservation.
16. `PATCH /v1/bookings/:id/reschedule` — another open slot (slot-based) or a new proposed time (request-based); frees the old reservation atomically.
17. `POST /v1/recurring-series` + management — slot-based only; generates occurrences on cadence, each requiring its own accept; **a missed occurrence skips that week and notifies both parties; three consecutive misses pause the series** (§1c).
18. `GET /v1/users/me/bookings?role=&status=`
19. 🔧 **`POST /v1/bookings/:id/reveal-contact` — the single contact exception, Round 9.** Emergency bookings only, at `accepted` or later, customer-initiated, mutual and simultaneous, counterparty notified, expiring 24 hours after the booking reaches a terminal state, logged to Phase 22's signals, and gated by the Phase 10b kill switch. Every condition is validated server-side (§1c). The old `GET /v1/bookings/:id/contact-info` is **not** this endpoint and must not be reintroduced — it exposed a phone number on every booking type with no conditions at all.
21. 🔧 **Verification revocation cascade — Round 9.** When a provider's `verificationTier` drops below `silver`, their in-flight emergency bookings are handled by payment state, not uniformly: at `accepted` or `awaiting_payment` the booking **auto-cancels** with both parties notified; at `payment_claimed`, `confirmed`, or later it is **routed to the admin queue as a dispute** and left otherwise untouched. Auto-cancelling a booking the customer has already paid for off-platform would strand real money with no platform recourse.
20. **🔧 Trial-start hook fires on the state transition into `confirmed`**, not from one endpoint — so both `confirm-payment-received` and an admin `resolve-dispute` resolution reach it.

**Frontend:**
1. Booking entry, three variants: slot picker (open slots only), request-with-preferred-window (🔧 leading with quick-pick time chips, §1c), emergency/ASAP — routed by `bookingMode` and the emergency toggle where available.
2. Provider accept prompt: job details and customer name only, no contact details, no chat yet, accept/decline/propose-quote, **with a countdown matching the mode's actual window** (30 min / 24 h). 🔧 Offering a quote opens the `booking` chat immediately (§1c), so the provider lands in a thread rather than back on a list.
3. 🔧 **Emergency accept-with-fee** for the provider — one screen, the callout fee entered as part of accepting, copy stating parts and labour settle directly afterward, and a clear "already claimed" state for a lost race.
3b. 🔧 **Emergency offer card** for the customer — provider name, verification tier, rating and callout fee, with Accept and Reject, a countdown on the 5-minute offer window, and a second countdown on the overall request window so they can see what rejecting costs.
4. Payment prompt: provider's payment details, `agreedAmount` shown explicitly and labelled by `amountKind`, honest copy, "I've Paid."
5. Provider receipt prompt: three visually distinct actions — "Payment Received", "Payment Not Received", "Decline Booking".
6. 🔧 On `accepted`: the `booking`-type chat opens and is surfaced prominently — this is the coordination moment, not a contact-info reveal (§1c).
7. **"Did this happen?" prompt** for the customer at the 7-day post-scheduled mark.
8. 🔧 Emergency completion: an optional "Final amount charged" field in the provider's complete-job flow, clearly marked optional, distinct from the callout fee shown earlier in the timeline.
9. Bookings tab: status filter pills, detail view, **status timeline showing when each transition happened and who caused it**, distinct badges for every status including `awaiting_payment` and `payment_unresolved`.
12. 🔧 **The accept prompt queues and replays offline**, reusing Phase 9's local-queue-and-replay pattern. A provider tapping Accept on a weak atoll connection must not lose the action or be left unsure whether it registered — the tap is recorded locally, replayed on reconnect, and the UI shows a pending state until the server confirms. Phase 9 built this treatment for the wizard alone while the plan named connectivity as a platform-wide risk; the accept prompt is the higher-stakes surface, since a lost tap costs the provider the job.
13. 🔧 **"Book again"** on a completed booking's detail view — pre-fills a new booking request against the same provider and listing, routed by that listing's current `bookingMode`. Recurring series (§1c) cover slot-based repeat work only, which leaves the majority of the catalogue — every request-based category — with no accelerated path back to a provider the customer already trusts.
14. 🔧 **Calendar export** on a confirmed booking — an ICS download or subscribe link, so a provider running several jobs a week can see them alongside everything else in their life rather than only inside the app.
10. Recurring-booking entry point and one-tap "Same time next week?".
11. Emergency no-acceptance state: "No one accepted in time" with one tap to try another provider or convert to a scheduled request.

**Done when:** the full lifecycle works for all three modes; concurrent bookings on one reservation window resolve to one winner **even across different listings of the same provider**; an unresponsive provider auto-declines at the correct window per mode; a quote expires on its own 72-hour clock and releases its provisional reservation; an unresolved payment claim escalates to admin review at day 7 without unlocking anything; 🔧 **no endpoint in the module returns a phone number, WhatsApp handle, or Viber handle — with the single exception of `reveal-contact`, and no WhatsApp or Viber handle even there** — verify this by inspecting every response shape in the module, not just the ones expected to carry it; the reveal endpoint rejects a non-emergency booking, a `requested`-state booking, and a provider-initiated call, reveals both numbers or neither, and returns nothing 24 hours after the booking goes terminal; revoking a provider's verification auto-cancels their `accepted` emergency bookings but routes their `payment_claimed` ones to admin instead; the `booking`-type chat opens at `accepted` and stays open through and after completion; an emergency booking on an ineligible category or by an unverified provider is rejected; the emergency rate limit triggers; 🔧 a broadcast reaches every eligible provider and nobody outside the eligibility rule; 🔧 two simultaneous accepts both produce offers rather than one winner, and the customer is shown both; a collection window closes at 90 seconds and presents at most three offers; selecting one releases the others immediately; reject-all re-broadcasts and never returns to any provider who offered; an unanswered set of offers expires 5 minutes after the window closes and re-broadcasts without resetting the overall window; 🔧 selecting an offer incurs the MVR 200 dispatch fee, the job proceeds without waiting for payment, an unsettled fee blocks a new booking, and submitting proof lifts that block before any admin confirms it; 🔧 a provider marked as not arrived is released, takes a no-show against conduct, and the booking re-broadcasts without a second fee; 🔧 an emergency on Electrical is refused to a silver provider and accepted from a gold one, while AC Repair accepts silver; the request window expires at 30 minutes for Plumbing and 120 for Moving; an emergency job cannot be completed without a final amount, and the endpoint rejects the attempt; the "did this happen" flow distinguishes confirmed from unconfirmed completions and fires for emergency bookings too; a missed recurring occurrence skips rather than kills the series; reschedule manages reservations atomically; an accept tapped in airplane mode replays on reconnect rather than being lost; "Book again" opens a correctly-routed new request against the same listing; a confirmed booking exports a valid ICS entry.

### Phase 18 — Messaging Module

- `Conversation` type **`enquiry`** (listing-scoped, available before any booking) or **`booking`** (opens at `accepted`, 🔧 **stays open for the entire life of the booking including after completion** — it is the only coordination channel that ever exists between these two parties, not a temporary waiting room before a "real" contact exchange, because there is no contact exchange, §1c)
- 🔧 `requireEmailVerified` on both types (Round 11)
- 🔧 **Contact-pattern detection is silent — Round 12.** No banner, no reminder, no redaction, no interference of any kind; the sender sees nothing. Detection still runs and every match is still **logged** (conversationId, senderId, matched pattern, timestamp) and aggregated into Phase 22's provider-level signal. The aggregate is the enforcement mechanism and it never required telling the sender.
- 🔧 **Block user — scope is the user's choice, Round 9.** Two distinct actions, presented together: **Mute this conversation** (silences one thread, nothing else) and **Block this person** (account-level — neither party can message the other or create a new booking against them, enforced server-side at both conversation-creation and booking-creation). "Block user" was previously unspecified as to scope, which for a feature framed as safety-relevant left its actual guarantee undefined.
- 🔧 **A block never severs a live booking's chat.** Since §1c makes the `booking` thread the sole coordination channel, killing it mid-job would leave a scheduled visit uncoordinated. Blocking takes effect immediately for all *future* bookings and messages, but the existing booking's thread stays open until that booking reaches a terminal state, with a visible notice to both parties explaining why. A user who wants out of the job itself cancels or disputes it — those are separate actions with their own consequences.
- Report from within a conversation
- Enquiry-thread lifecycle on listing hide/delete (§1c) — a `booking`-type thread is unaffected by its listing's visibility as long as the booking itself is non-terminal
- 🔧 **Provider-side "Decline future bookings from this customer"** — a self-service action, enforced at booking creation, independent of the Report → admin-review path. A provider who has had a bad experience otherwise has no way to protect themselves during a moderation SLA measured in days. It is one-directional and does not silence the existing conversation; blocking (above) is the stronger action where the provider wants that too.
- 🔧 **Messages queue and replay offline**, same pattern as Phase 9's wizard and Phase 17's accept prompt. Since chat is the sole coordination channel for a live job, a message that silently fails to send is a coordination failure, not a cosmetic one — queued messages show a pending state and send on reconnect.
- 🔧 **Retention and size policy.** Message content and attachments are retained for the life of the account and purged with it under Phase 3's anonymisation rule; attachments are capped at the same per-file size as listing media (Phase 8). §1e sets a precise 90-day window for identity documents, while chat — which routinely carries photos of a customer's home, property, and access points — had no stated policy at all.
- Frontend: conversation list (both types), thread view. 🔧 **No nudge banner** — the composer carries nothing beyond the normal send affordance.

**Done when:** an enquiry thread delivers a message containing an appliance serial number without obstruction and logs a detection where one fires; a message sent in airplane mode queues, shows pending, and delivers on reconnect; the message rate limit triggers; a provider who declines future bookings from a customer stops receiving them while their existing conversation stays intact; 🔧 a message containing a phone-shaped string sends with **no visible interference whatsoever** while still producing a logged detection; two verified accounts exchange messages in both conversation types; a `booking`-type thread remains open and usable after the booking reaches `completed`; blocking and reporting both work; detection aggregates are queryable by provider.

### Phase 19 — Notifications Module

Notification **content**, not delivery — Phase 3c owns delivery.

- `Notification`: userId, type, payload, readAt, createdAt — calls Phase 3c's `PushSender`, never reimplements delivery
- Types: booking_requested, booking_accepted, booking_declined, booking_auto_declined, emergency_no_acceptance, amount_set, payment_claimed, payment_confirmed, payment_unresolved, payment_disputed, dispute_resolved, booking_completed, booking_auto_completed, completion_check_prompt, recurring_occurrence_missed, recurring_series_paused, payment_submission_confirmed, payment_submission_rejected, verification_approved, verification_rejected, trial_ending_7d, subscription_ending_7d, downgraded_to_free, winback_7d, winback_30d, new_message, new_enquiry, new_review
- **Weekly provider digest email** (opt-in): views, bookings, reviews, top-performing listings
- **Provider analytics dashboard:** per-listing views, booking counts, conversion rate, rating trend, response time
- **Response-time metric shows "No data yet"** for a provider with zero booking-acceptance history, never a blank or a zero that reads worse than no metric at all
- 🔧 **Accept rate — new in Round 9, and deliberately two metrics rather than one.** Response time alone flatters a provider who ignores most requests and answers only the ones they want. **Accept rate** counts *explicit responses only* — `accepted ÷ (accepted + declined)` — and a request-based **quote offered counts as an acceptance**, since the provider did commit. Auto-declines at the 24-hour or 30-minute timeout are excluded from it entirely and feed a separate, more forgiving **response rate** (`responded ÷ received`). Folding timeouts into one number would score a provider asleep during a window identically to one who actively refused, which is not the same behaviour and should not carry the same penalty.
- Notification centre screen (propose first); live badge counts

**Done when:** each event type fires through Phase 3c's sender; the digest sends on schedule to opt-in providers only; the analytics dashboard renders real data; a brand-new provider's response-time metric reads "No data yet," not "0 minutes."

### Phase 19b — Help, Support & Feedback 🔧 *new in Round 15*

Several failure paths currently dead-end with no route to a human: a rejected payment, a stalled verification, a blocked registration, a disputed conduct metric. In a market this small, one stranded provider telling the story is material.

- **In-app help** — a short searchable FAQ plus a contact form that files into Phase 10b's queue as a typed case, so support is not a separate inbox.
- **Support case type** on the admin side, with the same SLA treatment and internal notes as other queues.
- 🔧 **Product feedback channel**, distinct from provider reviews — reviews rate providers, and nothing currently rates RaajjePro. At launch this is the fastest way to learn why people stop using it.
- Reachable from Profile and from every terminal error state, not buried in settings.

**Done when:** a contact-form submission appears as an admin case with its SLA running; help is reachable in one tap from a failed payment and a rejected verification; feedback is stored separately from reviews and is never shown on a provider profile.

### Phase 20 — Hardening, QA & Launch Readiness

🔧 **One external security review before launch — Round 15.** Not tied to this phase number: the trigger is **the moment real identity documents exist in production**, whichever phase that falls in. Everything else here verifies the system against requirements this project wrote, which cannot surface a category of problem the project never considered.

- Contract tests across every module; E2E on the critical path (register → verify → publish → slot published → customer books → provider accepts → payment attested → confirmed → completed → review)
- **Concurrency tests specifically:**
  - simultaneous slot booking
  - 🔧 **a slot-based and a request-based booking overlapping in time on the same provider across two different listings** — this is what the old constraint missed
  - 🔧 **a load test firing 1,000 concurrent booking attempts asserting zero double-books** — the regression canary for the whole transaction model
  - simultaneous admin confirmation of one submission
  - repeated idempotent POSTs
- Performance: payload sizes, pagination, N+1 audit, **verified against §5's targets**
- Security: authorization on **every** endpoint including reads, rate-limit verification, admin auth, no sensitive data in logs, the three XSS payloads against the admin panel
- **Stub reconciliation sweep** — enumerate every deferred stub from earlier phases and confirm each is now real or consciously deferred with a written reason
- **Decision reconciliation sweep** — every "your call, document it" left to the agent, confirmed and recorded
- 🔧 State audit against every screen: loading / empty / error / populated — a **backstop verifying** what each phase already specified, not the first time these states are considered
- **Accessibility audit** against Phase 1's criteria across all screens
- Known-limitations document

**Done when:** suite passes; every concurrency test holds; §5's targets are measured and met or consciously accepted; the stub and decision registers are complete; the a11y audit passes.

### Phase 21 — Observability & Crash Reporting

- Backend APM/error tracking wired into Phase 2 logging
- Flutter crash reporting — 🔧 **pull this integration forward to Phase 3** and leave only the ProductEvent log and uptime monitoring here. Crash reporting genuinely wants to exist from the first real screen, not after twenty phases of building blind.
- Uptime monitoring on `/v1/health` and on the payment-submission endpoints specifically
- **Notification-delivery observability** (§Phase 3c): fallback-invocation rate, alert above 5%
- `ProductEvent` log: draft_created, listing_published, slot_published, booking_requested, booking_accepted, emergency_requested, emergency_unaccepted, amount_set, payment_claimed, booking_confirmed, booking_completed, enquiry_started, contact_pattern_detected, trial_started, trial_converted, trial_expired, search_performed

**Done when:** deliberate backend and Flutter exceptions both surface within minutes; a broken payment endpoint triggers an alert; every event type is confirmed logging; the email-fallback alert fires when forced above threshold.

### Phase 22 — Content Moderation & Reporting

- `Report`: reporterId, targetType (`listing`/`review`/`user`/`booking`/`message`/`photo`), targetId, reason enum, status, reviewedBy, reviewedAt, **resolution reason**
- Booking disputes and `payment_unresolved` escalations (Phase 17) file here automatically, with both parties' history shown together
- Admin queue extends Phase 10a/10b's panel and reuses its auth and audit log; a flagged user's report/dispute history is visible from Phase 10b's account detail view
- **Actioning hides, never deletes** — reversible via the soft-delete visibility flag
- **Hidden content stays visible to its owner**, who sees the category and reason and can appeal. Everyone else cannot find it.
- **Moderation transparency:** the user is told the category and reason with an appeal path
- Review anti-spam: rate limit, and flag implausibly-fast reviews for a human look rather than auto-rejecting
- **Listing free-text scanning for contact patterns** — the provider-side leakage vector the contact gate does not close
- 🔧 **Contact-pattern detection aggregates from Phase 18** surface here as a provider-level signal, not per-message noise: "this provider tripped contact detection in 40 of 52 enquiries." This is the enforcement mechanism that replaces v3's hard block.
- 🔧 **Emergency accept-then-cancel pattern detection** as a provider-level and customer-level signal
- Report affordances: Service Preview overlay, review cards, provider profile, conversation threads, listing photos

**Done when:** each report type reaches the queue with enough context to act; actioning hides content from everyone but its owner; the owner sees the reason and can appeal; a Phase 17 dispute appears with both parties' history; a provider with repeated contact-pattern detections is visible as an aggregate.

### Phase 23 — Legal, Compliance & App Store Readiness

- **Not primarily a coding task.** Cursor builds screens and section structure with clearly-marked placeholders; it does **not** write binding legal language.
- **Unified Terms of Service** (customers and providers) + **separate Provider Agreement** covering subscription, trial, cancellation, the manual bank-transfer process, and dispute handling
- Privacy Policy
- Provider Agreement linked from the Payment Proof Submission flow, where it is most relevant
- **Identity verification screens and formal evidence checklist**, implementing §1e's locked decision — including the rejection-reason taxonomy and resubmission path
- **App Store account deletion:** already built in Phase 3. Verify it meets the current requirement.
- **Research, don't code — resolve before Phase 8a goes deep:**
  - App Store and Play policy on a manual-bank-transfer subscription. Apple's IAP rules have an exception path for physical goods and services; whether this qualifies needs a real determination from someone who has been through review, because a negative answer changes Phase 8a's data model.
  - **Current status of Maldivian personal-data-protection legislation.** Do not assume nothing applies. 🔧 §1e's ID-document collection makes this materially more important than it was in v2 — identity-document retention is exactly the kind of processing such a framework governs.
  - **GST registration and invoicing obligations** on subscription revenue.
- Data-protection findings written to `docs/data-protection-review.md` in the repo, not left in a chat

**Done when:** the legal screens exist with placeholder clearly distinguished from final; the three research questions have written answers; nothing invented binding language on its own authority.

### Phase 24 — Staging Environment & Deployment Hardening

- Staging fully separate from production, with date/data manipulation for testing trial expiry, grace periods, pause caps, quote expiry, and slot boundaries
- Secrets into a real secrets manager; rotation process **and cadence** documented
- CI extended to real deploy automation with a tested rollback path
- Automated backups **plus a performed restore drill**, timed against §5's stated RPO/RTO
- Support contact path in-app (WhatsApp/Viber link or email)

**Done when:** a trial expiry, a quote expiry, and a slot-boundary case can each be simulated in staging; a secret rotates without a deploy; the restore drill is done and timed against a stated target.

---

## 4. Sequencing Notes

- **Phases 0–2 strictly linear.**
- 🔧 **Phase 6a depends on Phase 5 and Phase 6.** It calls Phase 5's provider-profile creation and update functions and is reached from Phase 6's role switcher — sequence it directly after both, before Phase 9's wizard needs anywhere to hand off from.
- **Phase 3c (Push) sits ahead of Phase 9a and Phase 17** — Phase 17's accept prompt is load-bearing on real-time delivery and must not wait on a phase built after it.
- **Phase 9a is a hard prerequisite for Phase 17.** Do not let it get absorbed; Phase 17 is already the largest phase in the plan.
- **Phase 17 builds in four slices** (17.1–17.4, §Phase 17). Do not attempt it in one pass.
- **Phase 8a's trial hook fires from Phase 17's transition into `confirmed`**, plus its own `start-trial` endpoint.
- **Phase 17 and Phase 22** retain a soft circular reference (disputes and escalations file Reports); build 17 first with a minimal Report insert, 22 makes the queue real.
- **Phase 4 must seed `bookingMode` and `emergencyCapable`** before Phase 5, 8, 9a, or 17 read them.
- 🔧 **Do before Phase 0 — Round 15:** cost the admin load against launch revenue. Put hours against every manual step — identity review, the confirmation call, CSV reconciliation, disputes, the recovery queue — at 50, 200 and 500 providers, against subscription income at those counts. Fifty providers at the MVR 75 introductory rate is roughly USD 240 a month, and admin load grows faster than revenue because disputes track bookings rather than signups. 🔧 **Round 15 fixed the lever in advance:** verification quality is not adjustable — the document check and the confirmation call stay. The load must come out of everything else, through auto-matching more transfers, batching queues, and cutting admin touchpoints in payments and disputes.
- 🔧 **Pin before Phase 3 — Rounds 11 and 13:** the provider is **Amazon SES** (§Phase 3), with SPF, DKIM, DMARC and a warmed sending domain. Email verification gates booking, enquiry and messaging, *and* carries the Phase 3c fallback *and* Phase 10b's admin alerting — it is the single point of failure for the entire transactional core, more so than SMS was, because there is no second channel behind it.
- 🔧 **Do in the Phase 0–2 window, not at Phase 3 — Round 13:** build bounce and complaint handling (SNS event destination, stored per-message result, suppression list honoured before send), then request SES production access. **The attestation required to leave the sandbox is that this handling already exists**, so the order is fixed: build it, then apply, then start Phase 3. Sandboxed SES sends 200/day to verified addresses only, so Phase 3's registration flow is not even testable before this clears. AWS answers within 24 hours but can request more information — which is precisely why it belongs ahead of the critical path rather than on it. **There is no SMS provider to procure and no sender-ID registration lead time**, which removes the longest-lead external dependency in the plan; this replaces it with a shorter but harder-edged one.
- **Pin before Phase 4:** confirm the per-category `bookingMode` table (§1c) — it drives which listings get a slot picker vs. a request form.
- **Pin before Phase 8a:** the trial-start trigger applied in §0.4, if you want to override it.
- **Resolve before Phase 8a goes deep:** Phase 23's App Store subscription question. A negative answer forces a data-model change.
- **Phases 21, 22, 24** have no dependency on one another. Pull Phase 21's crash-reporting integration forward to Phase 3.
- **Phase 10b depends on Phase 10a only** (shares its app shell, auth, and audit log) and ships right after it — it carries the operational surface needed from first launch.
- 🔧 **Phase 10c depends on Phase 21's `ProductEvent` log** and is the only part of the admin panel sequenced late.
- 🔧 **Phase 23's data-protection and identity-document research runs in parallel with Phases 5 and 1e, gating their launch directly** — not only Phase 8a. Those are the phases that actually collect and store ID documents and bank details; discovering a different required retention model after they ship is a rebuild, not a course correction.
- 🔧 **Phase 3's verified-email capture is a prerequisite for Phase 6a** (provider onboarding requires it) and for Phase 10b's outbound alerting.

---

## 5. Non-Functional Targets

🔧 New in v4. No revision of this plan has ever stated one, which meant Phase 20's performance and reliability audits had nothing to audit against.

| Dimension | Target |
|---|---|
| API latency | p95 < 400 ms, p99 < 1000 ms, measured at the edge, excluding media upload |
| Slot picker | Payload capped at 14 days of slots per request with pagination; renders in < 1.5 s on a 3G connection |
| App cold start | < 3 s to interactive Home on a mid-range Android device |
| Push delivery | 90% of accept prompts delivered within 30 s; 🔧 email fallback within 2 min of trigger |
| Email deliverability | 🔧 99% of transactional email accepted by the receiving server; bounce rate under 2%, monitored from Phase 3c. 🔧 **Round 13:** this target is no longer only ours — AWS places an SES account under review above **5%** bounce and can pause sending above **10%**, so breaching it costs the channel itself, not just the metric |
| Availability | 99.5% monthly on the API, measured against `/v1/health` |
| Backups | 🔧 **RPO ≤ 5 min via WAL archiving and point-in-time recovery** (Round 15 — was 24 h), RTO 4 h, both drilled in Phase 24. Booking payment is a two-sided self-attestation RaajjePro never independently observes, so the database is the *only* record that a customer paid and a provider confirmed. A 24-hour RPO does not lose a day of data, it creates a day of unadjudicable disputes with no external ledger to reconcile against. PITR is a checkbox on every managed Postgres. |
| Admin SLA | Payment submissions confirmed/rejected within 48 h; `payment_unresolved` items resolved within 5 business days; verification decisions within 5 business days |
| Supported devices | Android 8.0+, iOS 14+ |

These are starting targets, not contractual. Measure in Phase 20 and revise deliberately rather than discovering them in production.

---

## 6. Post-v1 Backlog — deliberate, not forgotten

- **Credit wallet & à la carte purchases**; the **advertising module** — 🔧 **Round 15 set a trigger rather than leaving it open-ended: revisit at 200+ active providers.** Sponsored placement in search and category results, sold per category per island as a subscription add-on, is the format that works in a marketplace. Selling it to fifty providers competing over near-zero searches produces refund requests and teaches providers the platform does not work, which is why it stays deferred rather than being pulled forward. Both require demand density that will not exist at launch. `PaymentSubmission`'s `purpose` enum stays open so they slot back in additively. Note the `boosted_placement` / `search_boost` naming collision to resolve when ads return.
- **Referrals — cut from v1, revisit only with fraud controls:** same-device/IP detection, a per-account cap, credit issued on the *referred provider's first confirmed subscription payment* rather than a free off-platform-verifiable booking, and a re-examination of the stored-value question under Maldives Monetary Authority rules. The MVR 50-per-completed-booking design was farmable at zero cost by two accounts and four free actions.
- ~~**Emergency dispatch fan-out**~~ — 🔧 **built in v1 as of Round 12** (§1c), no longer deferred. Sending one emergency request to several eligible providers simultaneously, first accept wins, others auto-decline. Reuses the existing reservation race machinery. Deliberately out of v1 because Phase 17 is already the largest delivery risk; the v1 fallback (§1c) is a one-tap retry with another provider.
- **Recurring bookings on request-based services** — currently slot-based only. Weekly plumbing checkups can't commit to a fixed duration upfront. Revisit if recurring proves valuable on the slot-based categories.
- **Dhivehi / Thaana localisation with RTL.** Needs a second font stack — Plus Jakarta Sans and Inter carry no Thaana coverage. A Phase 1 typography consequence worth knowing now even though the work is deferred.
- Admin role granularity, MFA, and network segregation · full analytics platform on Phase 21's ProductEvent log · automated image moderation · saved searches and alerts · real social auth.
- **Data export counterparty-PII redaction** — out of v1 by explicit choice (§7). If a provider's export containing a customer's name, booking time, and amount becomes a real complaint or compliance question, this is a small contained fix.
- **In-app feedback mechanism** — absent across all four revisions. Worth adding once there are enough users to generate signal.

---

## 7. Explicitly Deferred by Your Choice

Distinct from the backlog — these were offered as in-scope and you chose not to include them. Recorded so they read as decisions, not oversights.

- 🔧 **Partially reversed in Round 12.** **TOTP MFA and session controls are now in v1** (§Phase 2) — the two highest-value controls, and neither needs a second person or a fixed IP. **IP allowlisting** stays out: it locks the admin out when travelling or on a changing home connection. **A staffing plan behind the 48-hour SLA** stays out.
  **Residual risk, reduced but not removed:** MFA and session controls (Round 12) mean a stolen password alone is no longer enough, but a single admin role with a single reviewer is still your only check on money-adjacent actions — entitlement grants, content hiding, dispute resolution, identity verification (§1e), and now account suspension, category configuration, kill switches, and view-as-user. That account is the arbiter of the platform's only real trust signal, the gate on emergency capability, *and* the operator of its incident controls. Round 9's PII-column and message-content exclusions were added specifically to cap the blast radius, since the credential itself is deliberately unhardened. Worth a look before the provider count makes a mistake expensive.
- **Second-admin sign-off** on verification and high-value dispute decisions was offered as a compensating control and declined again in Round 12 — it requires a second person to actually exist, which at launch they do not.
- **Data export counterparty-PII redaction** stays out of v1 — a provider's export currently includes their customers' names, booking times, and amounts.
- **Proactive risk-signal dashboard** — Phase 22's contact-pattern, accept-then-cancel, and fast-review signals stay report-driven, surfacing only alongside a filed report. Nobody sees a provider going bad until someone complains.
- **Bulk queue actions and keyboard triage** — every queue item is reviewed and actioned individually, including 30 clean CSV auto-matches.
- **Provider broadcast messaging** — no in-panel way to reach providers as a segment, including the introductory-pricing cohort the platform now creates.
- **A first-50-provider acquisition plan.** The launch-mode threshold (Phase 16) is a real product gate with no stated route to clearing it; organic signup is the working assumption. For a cold-start two-sided marketplace this is the largest unowned business risk in the plan.
- **Chat delivery latency target** — §5 sets targets for API, push, slot payloads and cold start, but chat, now the sole coordination channel, has none.
- 🔧 **Secondary email provider** — after Round 11 removed SMS, OTP, the push fallback and admin alerting all rest on one email vendor with no failover. An outage there means nobody can register, verify, or reliably receive a job offer. Larger than the SMS single-vendor risk it replaced. 🔧 **Round 13 chose SES alone and left this open**, which adds a second failure mode beyond outage: SES can **suspend sending on the account's own bounce or complaint rate**, so a bad list or a bug in the fallback path can take the channel down without any vendor incident at all. The mitigation remains a second provider behind Phase 3's `EmailSender` interface, still deferred.
- **Bank-detail de-anonymisation** — an account holder's name plus island plus trade may be identifying in a population this size, which would let the one deliberate exception to the contact rule partly defeat it. Reviewed and left unchanged.

---

## 8. What This Plan Still Doesn't Solve

Two things worth keeping in view, because no amount of planning detail addresses them.

**Provider-side leakage remains open, and v5 is honest about the ceiling.** v5's core change is that contact info is never collected for cross-party exposure in the first place — a stronger position than any gate, since there's nothing to unlock incorrectly. But it does not stop a provider putting their real number in a listing description, an FAQ answer, or a gallery image, and the provider is still the party with the incentive to do so. An earlier revision attempted enforcement in the enquiry thread via a hard block; that was removed because it could not distinguish a phone number from an AC serial in a 7-digit-number country, and photos passed regardless. What's in place instead — logged detections surfacing as provider-level moderation signals (§Phase 22) — is the realistic ceiling: it makes patterns visible and actionable without breaking the pre-sales channel.

**The competitive question is still unanswered, and v5 sharpens rather than resolves it.** Nothing in this plan establishes why a Maldivian provider or customer leaves Facebook groups and Viber — free, universal, zero-friction — for this. v5's no-contact-info rule is the most protective posture yet for keeping transactions on-platform, but it's also the most friction a customer has faced across every revision: even after booking and paying, there is still no phone number, only in-app chat. That may be exactly the right trade for the trust problem this platform exists to solve, or it may be one friction point too many against a free alternative that offers a real phone call. This is a positioning and go-to-market question, not a development one, and it's now more load-bearing than it was in v4.

This is a positioning and go-to-market problem, not a development one. It deserves an answer before Phase 8a, not after launch.

---

## 9. Decision Log

Every substantive choice in this document, in the order made. Rounds 1–6 dated 2026-08-03; Round 7 dated 2026-08-04.

**Round 1 — core logic (11 decisions):** booking reordered to provider-commits-before-payment via time-slot publishing (yours, refined into §1c's slot/request/emergency split) · `agreedAmount` added · dispute given an exit and admin resolution · completion decoupled from sole provider control · completion-count trial trigger dropped · trial starts at first booking (later refined to first *confirmed* booking) · `lifecycleStatus` made derived, not stored · billing pause moved to provider level · `boosted_placement`/`search_boost` naming collision noted for post-v1 · idempotency added to money and creation paths · credits and ads cut to post-v1.

**Round 2 — product design (4 decisions):** role switcher for the provider dashboard · launch-mode Home for a thin catalogue · accessibility criteria moved into Phase 1 · wizard reframed around required-fields-remaining.

**Round 3 — v2 review, booking model (4 decisions):** category-bifurcated booking mode, Tuition removed · emergency bypasses slots · pre-booking enquiry restored, in-app, service-details-allowed · payment timeout escalates instead of auto-confirming.

**Round 4 — v2 review, monetization & infra (4 decisions):** referrals cut · badge decoupled from subscription · push moved to an early phase with a fallback · 24-hour accept timeout.

**Round 5 — pricing, verification, remaining gaps (4 decisions):** MVR 150/month pinned · pause resumes remaining time, extended to the trial period · identity verification = ID + trade proof, admin manual review · downgrade preserves confirmed future bookings, plus recurring bookings and the response-time fallback label; admin hardening and data-export redaction explicitly left out.

**Round 6 — v3 review, final (4 decisions):** emergency contact unlock moved to `payment_claimed`, `isEmergency` restricted to Plumbing/Electrical/AC Repair with a verification requirement and a per-customer rate limit · enquiry contact filter changed from hard block to soft nudge with logged moderation signals · emergency `agreedAmount` becomes a provider-set callout fee at the payment-request step · all four project artifacts regenerated against a standalone plan.

**Round 7 — checklist review of v4, 82 items, 6 decisions:** contact information removed entirely — no phone/WhatsApp/Viber ever exposed between customer and provider, for any booking type, at any point; the in-app `booking`-type chat (already speced to open at `accepted`) becomes the sole coordination channel for a booking's entire lifetime · Provider Profile drops WhatsApp and Viber, phone-only · a real "Become a Provider" onboarding flow added (Phase 6a), collecting phone and payment details before the wizard rather than later from the dashboard · cover image made a required field to publish, not optional · Boat Charter added as a twelfth category, request-based · three smaller UX fixes: past-dated slots never shown as bookable regardless of stored status, the request-based window picker leads with quick-pick time chips, emergency completion gets an optional final-settled-amount field separate from the callout fee.

**Applied without a dedicated question, flagged for override:**
- **Trial-start trigger** now fires on first confirmed booking *or* an explicit "Try Premium" request (§0.4). Recommended in two prior reviews, never asked. This is the single largest lever on subscription conversion.
- The thirteen specification fixes in §0.5 — each resolved a self-contradiction or an unspecified gap rather than a genuine choice.
- Home launch-mode threshold defaulted to 50 published active listings, tunable via config.
- Bank transfer payment details continue to be shown to the customer at the payment step (§1c) — confirmed as the one deliberate exception to the no-contact-info rule, since the off-platform payment can't happen without them and they aren't a way to reach a person.

**Round 8 — admin panel scoping, dated 2026-08-05:** Phase 10b added — account search/view/suspend (ban and hard-delete stay manual DB operations, deliberately excluded from panel reach) · read-only "view as user" for support diagnosis, access-logged · categories and the launch-mode threshold made admin-editable (reversing the original code+migration posture) · internal notes on users/bookings/cases · in-panel alerts additionally push out (email/Slack/Telegram) · targeted incident kill switches (emergency bookings, registrations, listing publication, the emergency contact-number reveal, outbound SMS) · minimal ops dashboard (KPI cards, bookings and trial-conversion trend lines, activity feed) · command-palette global search · shared filter/sort/pagination/date-range/CSV-export conventions across every list · sidebar with live queue badges. Declined in the same pass: general booking-state override (dispute/`payment_unresolved` resolution stays the only intervention — flagged gap, not an oversight) · proactive risk-signal dashboard (Phase 22's signals stay report-driven) · bulk queue actions (every item still reviewed individually) · provider broadcast messaging · IP allowlisting, session hardening, and MFA (admin auth unchanged, consistent with the accepted single-admin risk in §7).

**Round 9 — second adversarial review, 16 findings, dated 2026-08-05.** Reviewed the plan *as amended* by Rounds 7–8, which had introduced contradictions of their own.

*Verification rewritten as three tiers (§1e).* The prior round tightened trade evidence so photos were no longer sufficient alone — correct against forgery, but against §1e's own premise that many Maldivian tradespeople are unregistered, it made the badge unobtainable for the modal provider *and*, since emergency gates on verification, would have emptied the emergency pool at launch. Bronze (ID only) / Silver (ID + work photos + a customer reference **or** 5 clean on-platform bookings) / Gold (Silver + registration or trade certificate). Photos never suffice alone at any tier; Silver's second factor is earnable on-platform rather than issued by a ministry. The 5-bookings route grants automatically with no admin review, which is what keeps three tiers affordable against one reviewer. Emergency requires Silver+. No time-based expiry; dispute patterns trigger review that can demote.

*The contact-info absolute became a single named exception (§1c).* Round 8's emergency-contact decision contradicted the plan in eight places, including two testable acceptance criteria — and was the third rebuild of §1c, the pattern the declined f35 guard existed to catch. Rather than leave it implicit, it is now specified as one endpoint under seven request-time conditions plus a runtime kill switch (emergency mode only, `accepted`+, customer-initiated, mutual, counterparty notified, expiring 24 h after terminal state, logged, kill-switchable). Every other endpoint returning a phone number remains a defect.

*Corrections to Round 8's own additions:* suspension now feeds `findVisibleProviders` (it previously left suspended providers listed and apparently bookable) · view-as-user excludes message content (chat is the sole channel and carries addresses and home photos) · CSV export drops all PII columns (an unrestricted directory export defeated §1e's document protections from a credential with no MFA) · `bookingMode` edits blocked while live slots or bookings exist (the migration was never defined) · the single outbound-SMS kill switch split into three (it would have killed OTP, and with it all authentication) · internal notes deleted with their subject's account · alerts de-duplicated per threshold crossing · the ops dashboard split into Phase 10c so the operational panel isn't gated behind Phase 21.

*Consequences of Round 7–8 decisions that had no home in the model:* per-provider `subscriptionPriceLaari`, honoured 12 months then converting with 30 days' notice, giving the introductory-pricing decision somewhere to live and something to measure · verified email built in Phase 3, since the phone-recovery decision depended on a channel no revision had built · account deletion **queued and auto-executing with a 30-day backstop** rather than refused, since refusing on open bookings could block indefinitely on admin inaction and both app stores require deletion to work · verification revocation auto-cancels emergency bookings **only pre-payment**, routing paid ones to admin instead of stranding a customer's money · block scope split into mute-conversation and account-level block, with a live booking's chat surviving until terminal state · accept rate defined as explicit responses only, with timeouts feeding a separate response rate.

*Applied without a dedicated question, flagged for override:* `minimumLeadTimeMinutes` added to the category seed, since the category-specific slot lead time needed a field · the short-TTL cache takes no explicit invalidation, relying on a 30–60 s window instead of a bust-key matrix.

*§1 rewritten in the same pass.* The inventory listed modules rather than owning phases, and closed by asserting that provider onboarding has no separate page — a pre-v5 claim that survived into v5 by oversight and directly contradicted Phase 6a. It now tags every screen with its owning phase and platform, separates the 8 mockup'd screens from the 20 without, states that the plan wins wherever a mockup disagrees (naming the three known divergences), and records what remains true of the old implicit-creation mechanism underneath Phase 6a.

*Downstream artifacts regenerated against revision 5.1 after this round:* `02_Cursor_Prompts.md` (was targeting v4, two revisions stale) and `03_Cursor_Rules_Skills_Subagents.md`. The latter mattered most — rules apply silently on every generation, and v4's always-apply rule asserted the deleted contact-info endpoint while instructing the agent to treat an emergency contact reveal as a closed security hole not to be reintroduced, which would have actively blocked Phase 17.3.

**Round 10 — folding in the previously-unrecorded decisions, dated 2026-08-05.** An audit before regenerating the downstream Cursor artifacts found thirteen decisions that had been made in review but never written into this document, two of which the plan still contradicted in its own text. No new choices were made in this round; every item below had already been decided.

*Corrections to text that contradicted a made decision:* emergency `finalAmount` is **required** to complete, not optional — it was reliably present on clean cheap jobs and reliably absent on the padded bill a customer was disputing, inverting its evidentiary value · downgrade keeps the **highest-performing** unprotected listing (confirmed bookings over 90 days, then views, then recency) rather than the most recently updated, which a provider who knew the rule could game by touching their preferred listing.

*Behaviours that had no home in any phase:* the `booking` chat opens when a **quote is offered**, closing the one window where negotiation is most needed and previously had no channel · offline queue-and-replay extended from the wizard to the **provider accept prompt and chat sends**, the two higher-stakes surfaces under the connectivity risk the plan names platform-wide · a **"Not right now"** exit from provider onboarding, since resume-where-you-left-off is wrong for someone who decided against it · **"Book again"** on completed bookings, since recurring series cover slot-based work only and leave every request-based category with no repeat path · **ICS calendar export** on confirmed bookings · **provider-side decline-future-bookings**, self-service and enforced at booking creation, since Report → admin review is measured in days · **unmatched-transaction queue** in Phase 10a for CSV rows the reference matcher cannot resolve · **messaging rate-limit tier** in §2, since the enquiry channel's content policy is deliberately permissive · **review authorship retained internally** after anonymisation, so a fabricated review survived by account deletion can still be adjudicated · **chat retention and attachment-size policy**, previously the only content class with none · a **proactive 7-day "Try Premium" prompt**, since the confirmed-booking trigger cannot realistically fire in a useful timeframe for a new provider · **per-phase loading/empty/error state design** promoted from Phase 20's late sweep into every frontend phase's own Done-when, with Phase 20 retained as a backstop.

**Round 11 — SMS removed, dated 2026-08-05.** Your decision, taken while pinning the SMS provider before Phase 3. Three changes and one consequence you accepted knowingly.

*SMS is removed from the system entirely.* OTP is sent to email, `emailVerified`/`requireEmailVerified` replace the phone equivalents at every gate, and Phase 3c's fallback ladder loses its middle rung to become push → email. This removes the longest-lead external dependency in the plan — sender-ID registration with the operators — and it removes a per-booking marginal cost that scaled with volume rather than signups.

*Push has no in-app toggle.* Booking notifications are transactional and always send. Recorded explicitly: **this cannot be enforced past the app.** iOS and Android both let a user revoke notification permission at the OS level and no app can override it, so "always enabled" means only that we ship no switch — the OS-denied path is precisely what the email fallback covers. Weak atoll connectivity is acknowledged and accepted as a launch-stage risk rather than designed around.

*Phone number: unique, collected, and not verified.* Both email and phone carry a unique constraint, and a registration against either in-use value is blocked at the field naming which one is taken. **Uniqueness is not ownership** — with SMS gone nothing proves the number belongs to the person who typed it, and the UI must never show it as verified. Two problems this creates were surfaced and are handled by the admin rather than new infrastructure: **squatting** (registering with someone else's number permanently blocks the real holder, who has no self-serve proof) and **number recycling** (a reassigned Maldivian number stays locked to a dormant account). Both resolve through Phase 10b's existing recovery queue. Additionally, **the admin now confirms the phone number during Bronze review** — a call, or a match against the submitted document — which costs nothing new and means every provider eligible for emergency work (Silver+) has had their number checked by a human. That is what keeps the emergency reveal from handing a customer a dead line.

*The residual risk, stated plainly:* email is now a single channel with nothing behind it, carrying OTP, the push fallback, and admin alerting at once. That is a narrower base than the two-channel design it replaced, and §7 records a secondary email provider as the deferred mitigation.

**Round 12 — 151-item end-to-end review, dated 2026-08-08.** A full walkthrough of every provider and customer step, answered item by item. Three items rejected outright and four accepted with changes attached.

*Emergency dispatch rebuilt from targeted to open broadcast.* An ASAP request now goes to every eligible provider simultaneously rather than one at a time, reversing a deferral that had sent fan-out to post-v1. This forced a second change: because the first acceptance would otherwise bind the customer to an unknown provider at an unknown price, **the callout fee is now supplied as part of accepting**, and the claim is presented to the customer as an **offer they accept or reject** — a rejection re-broadcasts and excludes that provider from later rounds. A new non-terminal status, `emergency_offered`, carries this. Offers expire after 5 minutes (applied without a question — an emergency customer is holding their phone, and a longer window burns the overall clock).

*Moving became emergency-capable, with a per-category window.* The 30-minute figure was set for a tradesperson arriving with hand tools; a mover needs a vehicle and usually a crew, so `emergencyAcceptWindowMinutes` joins the category seed at 30 for Plumbing, Electrical and AC Repair and 120 for Moving.

*Admin hardening partially reversed.* **TOTP MFA and session controls are now in v1** — the two controls that need neither a second person nor a fixed address. **IP allowlisting stays out** (it locks the admin out when travelling) and **second-admin sign-off stays out** (it requires a second admin to exist). The residual risk in §7 is reduced, not removed: a stolen password is no longer sufficient, but one reviewer is still the only check on money-adjacent actions.

*The trial is 30 calendar days, halved from 60.*

*In-app messaging carries no interference at all.* The contact-pattern nudge is removed outright — no banner, no reminder, nothing shown to the sender. **Detection and logging continue silently**, because the same review kept the provider-level moderation aggregate, and that aggregate never depended on telling the sender. Resolving those two answers together is the only reading consistent with both.

*Two interface decisions.* Listing tags become selectable chips scoped to the category rather than free-text entry — typing a tag from memory asks a provider to guess what customers search for. Search sort order is fixed as **distance, then rating, then price**; distance leads because a provider who cannot reach your island is not a result at all.

**Round 13 — email provider pinned, dated 2026-08-08.** Taken while clearing the pre-development checklist, after comparing SES, Postmark and Brevo against what this plan actually requires of the email layer.

*The provider is Amazon SES, sole vendor.* At $0.10 per 1,000 against a $200 new-account credit over six months, realistic launch volume is effectively free, and the cost curve matters more here than in most plans because Round 12's open emergency broadcast emails **every eligible provider on every emergency request** — a volume that scales with bookings rather than signups. Postmark was the alternative on deliverability grounds and a split (Postmark for OTP, SES for the Phase 19 digest) was recommended; a single vendor was chosen instead. Brevo was ruled out on a specific detail: its free and entry plans append a "Sent with Brevo" footer, and a third-party footer with a link in it on an OTP mail directly undercuts the reasoning in §Phase 3c that keeps links out of fallback email.

*The consequence that changes sequencing.* SES will not leave its sandbox — 200 messages/day, verified recipients only — until the account attests that bounce and complaint handling exists. That inverts the order this plan assumed: bounce handling was written as a Phase 3c task, and it is now a **Phase 0–2 prerequisite**, because Phase 3's registration flow cannot be tested, let alone launched, from inside the sandbox. §4 Sequencing carries the corrected order.

*Two costs accepted knowingly.* SES has no searchable activity console, so the per-message delivery log Phase 10b needs in order to answer "did this provider get the alert?" is scope this plan now owns rather than scope a hosted vendor absorbs. And the §7 single-vendor risk is not only an outage risk with SES: the account's own bounce rate can pause sending, so a defect in the fallback path can remove the channel with no vendor incident involved.

**Round 14 — build-readiness audit, dated 2026-08-11.** An audit of every artifact derived from this plan, run before Phase 0 and deliberately scoped to two defect classes: cross-document contradictions, and gaps that stop a coding agent. Business-model and security concerns were excluded from the pass. Six findings, all resolved; ten candidates were checked and dismissed as false positives.

*One contradiction of the now-familiar kind.* `skills/contact-rule-and-moderation/SKILL.md` still described contact-pattern detection as a **soft nudge**, which Round 12 removed outright. That skill auto-invokes on messaging and moderation work, so it contradicted the always-apply rule sitting beside it in the same context window. This is the third instance of the same pattern — SMS in Round 11, admin MFA in Round 12, the nudge here — and in all three the plan and `02` were correct while a skill or subagent file was not. **The derived artifacts, not the plan, are where a reversed decision survives.**

*Two values a phase needed and no document supplied.* The trial length was stated in §1b but never in Phase 8a's prompt, which defines `trialEndsAt` and all three start triggers — and the decision log's "halved from 60" sat nearby as the plausible wrong answer. And `minimumLeadTimeMinutes` was a required seed field whose prompt read "set a sensible value per category", which authorises an agent to invent twelve product decisions that become the launch seed. Both are now stated explicitly.

*Two business values set.* The **introductory rate is MVR 75**, half the standard MVR 150, held for the first 100 providers for 12 months — the spread chosen to be wide enough that Phase 10c's cohort comparison actually reads. **Minimum lead times** are seeded per category from 60 minutes for the three trades to 2880 for Events; only the three slot categories bite at launch, since they are the ones with a picker.

*One ambiguity that was quietly resolved wrong.* The contact reveal was called "seven conditions" in ten places while §1c listed eight bullets under "all of which must hold". `02` had already resolved it by treating the kill switch as separate, which is right — it is a runtime flag, not a per-request validation — but the resolution was never written down, so an agent counting the list would have had to guess which item to drop. §1c now states seven request-time conditions with the kill switch called out separately, and Phase 20's audit asserts the seven.

**Round 15 — the adversarial review, dated 2026-08-12.** *All twenty-nine resulting changes were reviewed item by item and confirmed without amendment on 2026-08-13.* A full external-style review across core logic, product design, feature gaps, architecture, security, business and edge cases, run deliberately at the areas Round 14 excluded. Fifteen findings decided, plus eight further product decisions taken alongside them. This is the largest revision since v5 was written, and unlike Rounds 10–14 it is mostly *new scope* rather than reconciliation.

*Emergency dispatch was rebuilt a second time.* Round 12 replaced targeted dispatch with an open broadcast where the first acceptance won. Round 15 found that this makes the winner whoever taps fastest rather than whoever is nearest or cheapest, forces the customer to decide blind one offer at a time under a countdown, and rewards providers for accepting instantly and quoting high. **Offers now collect for 90 seconds and the customer picks from up to three.** Eligibility also became per-category: **Gold for Electrical and Plumbing**, since electrical work at 2am in a stranger's home is life-safety work and five completed bookings evidences nothing about trade competence.

*The first customer-facing charge.* A **MVR 200 emergency dispatch fee**, incurred when the customer selects an offer and never on submitting a request, so a dispatch nobody answers costs nothing. With no payment gateway, it is recorded as owed and settled afterwards by bank transfer through the existing `PaymentSubmission` flow — which is what its open `purpose` enum was reserved for. It never blocks dispatch; an unsettled fee blocks all new bookings instead, because at MVR 200 a manual receivable is not worth chasing.

*Conduct became a second axis, and deliberately stayed unopinionated.* §1f scores completion, cancellation, no-show, on-time, price adherence, acceptance and response time from booking outcomes. System-generated labels — "Prone to cancel", "Price hiking" — were **considered and rejected**: automated public accusations computed from a handful of data points, in a market where everyone knows everyone, are a defamation exposure and a livelihood risk, and the raw numbers carry the same decision value without asserting a character judgement.

*"Payment holds" resolved without becoming a payment company.* Holding customer funds means a gateway and almost certainly MMA licensing. §1h instead locks the agreed price, date, time and scope at `accepted`, requires an accepted amendment to change any of them, and records every attempt against price adherence. Same anti-hiking and anti-no-show behaviour; RaajjePro still never touches money.

*Answers to the defection problem.* A **callback guarantee** honoured only for on-platform bookings, **saved preferences and providers**, and **provider replacement on cancellation** — re-broadcast for emergencies, a pre-filled booking flow for everything else. Together these are what makes job #2 happen here rather than by direct phone call, which §8 had identified as unanswered.

*Smaller corrections with outsized cost if missed.* **RPO moved from 24 hours to 5 minutes** — the database is the only record that payment happened, so 24 hours of loss is 24 hours of unadjudicable disputes. **Phase 1 must be RTL-ready** without shipping Dhivehi, because Thaana's layout consequence is architectural and a retrofit is a presentation-layer rewrite. **Identity documents leave the application backup set**, so the 90-day purge is true. **Phone uniqueness begins at Bronze**, closing squatting as a supply-side denial of service. Quote windows became per-category, because four days to book a plumber is a booking that never happens.

*Recorded without change:* chat-only coordination ships as designed and leakage is measured rather than pre-tested; verification quality stays exactly as-is, which fixes the admin-load lever to automation elsewhere; advertising stays deferred with a **200-provider trigger** rather than an open end; and **local preference is a verified "Maldivian-owned business" attribute at Gold**, not a nationality field on individuals.

**Open, requiring your input:**
- The per-category `bookingMode` table (§1c) — confirm before Phase 4 seeds it.
- Whether premium's contents justify MVR 150 now that the badge is decoupled (§1b) — flagged as a business risk, no change made.
- Whether the no-contact-info rule (§1c, §8) is the right trade against a free, phone-call-capable alternative like Viber — flagged as sharpened, not resolved, by this revision.
- Phase 23's three research questions — App Store subscription compliance, Maldivian data-protection status, GST obligations.
