# RaajjePro — Development Plan (v4)

**This document is standalone.** It supersedes `01_Development_Plan.md` (v1), `_v2.md`, and `_v3.md` entirely. Nothing here defers to an earlier revision — every phase is specified in full. Delete or archive the older plans; they now conflict with this one in ways that will produce wrong code.

Folds in all 31 decisions resolved across four rounds of adversarial review on 2026-08-03. Full provenance in **§9 Decision Log**.

**Stack:** Flutter (mobile-first) · TypeScript / Fastify / Prisma / PostgreSQL · REST `/v1` · monorepo.

---

## 0. Read this first

### 0.1 Why v4 exists

v3 was a diff against v2, which was a diff against v1. Three chained documents meant that building any given phase required reconciling three specs by hand. Worse, `02_Cursor_Prompts.md` and `.cursor/rules/000-project-context.mdc` still described v1's product — and the rules file is `alwaysApply: true`, so it was asserting deleted fields and cut features into every generation. v4 collapses the chain. `02` and `03`/`03b` have been regenerated against this document.

### 0.2 What changed from v3

Four decisions from the final review round, plus the specification fixes they required:

1. **Emergency bookings no longer unlock contact at `accepted`.** They unlock at `payment_claimed`, same ordering as every other booking type. `isEmergency` is now restricted to Plumbing, Electrical, and AC Repair, requires `verificationStatus: verified`, and is rate-limited per customer. v3's carve-out was a one-tap bypass of the contact gate that both parties were motivated to use — and the contact gate is the reason a provider pays rather than moving to Viber.
2. **The pre-booking enquiry filter is a soft nudge with logging, not a hard block.** v3 required hard-rejecting phone-shaped text while explicitly allowing appliance serial numbers. Maldivian mobiles are 7 digits; AC serials are digit strings; these are not reliably distinguishable, and photos were allowed anyway, so a photo of a business card passed regardless. Detections are now logged as a moderation signal — a provider tripping it across 40 enquiries is visible and actionable; the individual message is not blocked.
3. **Emergency bookings carry a callout fee as `agreedAmount`**, set by the provider after accepting and before the customer is prompted to pay. v3 required an `agreedAmount` before leaving `requested` while also routing emergencies straight to `accepted` — a plumber cannot price a job they haven't seen. The callout fee is what they *can* price, it is labelled as such in the UI, and the plan states plainly that the full job cost is settled off-platform.
4. **All four artifacts regenerated** — this plan standalone, `02_Cursor_Prompts.md` rebuilt phase by phase, `03`/`03b` rule invariants rewritten.

### 0.3 One decision applied on your behalf — override if you disagree

**Trial-start trigger.** This was flagged in the v2 review and again in v3's §6 and never made it into a question round. v3 left it as "first confirmed booking only," which means a provider who publishes but never gets booked never experiences premium and never converts. That is the single largest lever on subscription revenue.

**Applied:** trial starts on the provider's first `confirmed` booking **or** on an explicit provider-initiated "Try Premium" request, whichever comes first. Still 60 calendar days, still one per account.

This is the fix recommended in two prior reviews. It is a small change (one extra endpoint, one extra call site into the same function) and it is reversible. If you want booking-only, say so before Phase 8a.

### 0.4 Specification fixes applied without a question

These were defects rather than choices — the spec contradicted itself or left a gap an implementer would have to guess at. Each is flagged inline with 🔧 where it appears.

| Fix | Was |
|---|---|
| `scheduledFor` set to acceptance time on emergency bookings | Emergency had no `scheduledFor`, so the completion timeout never fired and reviews never opened |
| Three separate timeouts: emergency accept (30 min), standard accept (24 h), customer quote-approval (72 h, own clock) | One 24-hour rule applied to all modes; the scheduled job also auto-declined `quote_offered`, a state that exists only because the provider *did* respond |
| Provisional reservation created when a quote is offered | Reservation was created only on customer approval, so the time could be sold to someone else in between and approval would hit a constraint violation |
| Billing anchor date, explicitly not "calendar month" | "Calendar billing" and "pause resumes remaining time" are incompatible — a pause shifts the anchor |
| Trial hook fires on the transition *into* `confirmed` | Hook was on one endpoint; an admin resolving `payment_unresolved` also reaches `confirmed` and would not have fired it |
| `EXCLUDE USING gist` on a provider-scoped time range | `UNIQUE (providerId, listingId, startsAt)` let one provider be booked three times at 10:00 across three listings, and did not detect overlapping durations at all |
| SMS fallback fires immediately on known push-denial, at 30 min on delivery failure | "Within the acceptance window" meant an SMS could arrive at hour 23 of a 24-hour window |
| ID/passport documents: private bucket, 90-day retention post-decision, access logged | §1e introduced ID collection with no storage, retention, or access policy |
| Recurring series survives a missed occurrence | A single auto-declined week silently killed the series |
| Dispute outcomes enumerated | "An outcome recorded" with no enumeration meant an unstructured audit log |
| Slot generation window: 60 days rolling | Unspecified — affects payload size, schema, and Phase 17's transaction scope |
| `bookingMode` seeded in Phase 4 | v3 referenced a Phase 4 seed that Phase 4's spec did not include |
| "laari", not "laira" | Typo in the one place a currency constant gets copied from |

---

## 1. Mockup Inventory & Coverage Map

| Screen | Status | Modules |
|---|---|---|
| Home (feed) | Exact match provided | Search & Discovery, Listings, Favorites, Provider Profiles |
| Explore (category grid) | Exact match provided — **11 categories, not 12** | Categories |
| Login | Provided, improvable | Identity & Auth |
| Register | Provided, improvable | Identity & Auth |
| Profile (customer) | Provided, improvable | Customer Profiles, Favorites, Bookings, Notifications |
| My Services Dashboard | Exact match provided | Provider Profiles, Listings, Reporting |
| Create/Edit Service Wizard (1–7) | Exact match provided | Listings, Categories, Media, Service Areas |
| Service Preview | Exact match provided | Listings, Reviews, Provider Profiles |

🔧 Removing Tuition breaks the "exact match" claim for the Explore grid — the mockup shows a 3-column grid built around 12 items; 11 leaves an uneven last row. Grids handle this natively, but flagging since exact matches are expected elsewhere.

### Screens with no mockup — Claude proposes, you approve, before that phase's code

Bookings tab (list + detail + status timeline) · Notifications centre · Provider public profile · Search results · Category results · Saved Services list · Forgot Password flow · Phone verification (OTP entry) · Trust & Safety and Privacy & Security sub-screens · Availability & Time Slot management (provider side) · Provider Billing (subscription status, payment proof submission, invoice list) · Account settings (change password/email/phone, active sessions, data export, account deletion) · Role switcher (customer ⇄ provider) · Launch-mode Home variant · Admin panel (separate web app) · **Booking flow, three variants** (slot picker, request-with-window, emergency/ASAP) · **Pre-booking Enquiry thread** · **Provider contact & payment details entry** (Phase 5).

**The admin panel is a separate internal web app**, not a Flutter screen. Backend endpoints are identical either way.

**Provider onboarding has no separate page.** The Create/Edit Service Wizard *is* onboarding — starting a draft is what makes someone a provider (§1a).

---

## 1a. Provider Lifecycle Model

**Public visibility is derived, not stored.** A provider is publicly visible if and only if `count(listings WHERE status='published' AND visibility='active') > 0`, computed by one shared query helper — `findVisibleProviders` — that Featured Providers, search, and the public profile endpoint all call. There is no stored `lifecycleStatus` field. v1 had one, flipped one-way on first publish, and it drifted: a provider who unpublished their only listing stayed `active` forever with an empty public profile.

- **`ProviderProfile` is created implicitly** on the first `POST /v1/listings` by a user who has none. `getOrCreateProviderProfile(userId)` is idempotent.
- **`verificationStatus`** (`unverified` / `pending` / `verified`) is a separate axis — identity evidence, admin-transitioned (§1e). Never conflated with visibility. A provider can be visible and unverified simultaneously.
- **Idempotency:** `POST /v1/listings` requires a client-supplied key so a retry on a flaky connection cannot create orphan drafts. "Become a Provider" for a user with an existing draft resumes it.
- **Dashboard access is never gated.** A provider with only drafts reaches My Services Dashboard normally, stats at zero.

---

## 1b. Monetization Model — subscription only

**Customer-facing rule:** all customer features are free indefinitely. Nothing in this section may ever gate a customer action.

**Payment for jobs is off-platform.** RaajjePro never moves money between customer and provider. Everything RaajjePro collects is a provider paying RaajjePro, via manual bank transfer + admin confirmation. No payment gateway in v1.

### v1 scope

| Layer | Mechanism |
|---|---|
| Free tier | 1 active listing, full search visibility (**never** paywalled), no analytics. Badge is unaffected — see §1e. |
| Trial | Full premium access, 60 calendar days. **Starts on the first booking reaching `confirmed`, or on an explicit "Try Premium" request, whichever comes first** (§0.3). |
| Subscription (Premium) | **MVR 150/month, pinned.** Unlocks multiple active listings, analytics dashboard + weekly digest, priority placement. **Does not unlock the badge.** |

### Deferred to post-v1

Credit wallet & à la carte purchases; the advertising module; referrals. Rationale: every premium benefit derives its value from demand density that will not exist at launch. Building three monetization systems before the marketplace could transact was v1's largest sequencing error. Keep `PaymentSubmission`'s `purpose` enum open so all three slot back in additively.

### Trial and subscription lifecycle

- **Warning** 7 days before trial or subscription period end.
- **Grace:** 7 days after expiry with nothing changing, then downgrade to free.
- **Billing anchor — 🔧 explicitly not "calendar month".** A subscription bills every 30 days from an anchor date set at first confirmed payment. **Pausing shifts the anchor by the paused duration.** Calling this "calendar month" was incoherent with pause: a provider who pauses four days is no longer billed on the 1st, and after several pauses no two providers share an anchor. Bill on the anchor, display the next billing date, and never imply month boundaries.
- **Pause:** capped at **10 cumulative days**. Resuming manually within the cap preserves the remaining paused allowance for later use. At the cap, pause auto-ends and the clock forcibly resumes. **The identical mechanism applies to the trial period** — one function, one cap, one resume rule, shared by `trialing` and `active`. Pause keys off the provider-level `acceptingNewCustomers` toggle (§Phase 5).
- **Downgrade is non-destructive and reversible.** Listings beyond the free-tier cap are hidden (`visibility: 'hidden_over_cap'`), never deleted. Analytics disable. Badge is unaffected. Any confirmed payment restores everything. Basic discoverability of the remaining listing is never affected.
  - **Protected listings:** a listing with a booking in `accepted`, `awaiting_payment`, `payment_claimed`, `payment_unresolved`, or `confirmed` status and a future `scheduledFor` **stays visible regardless of cap**, until that booking reaches a terminal state (`completed` / `cancelled` / `declined` / `dispute_resolved`). Hiding a listing out from under a customer who already has a confirmed job booked against it breaks a commitment the platform vouched for.
  - Among unprotected listings, hide least-recently-updated first, keeping the most recently updated one visible. The provider can choose a different one from the dashboard.
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

## 1c. Booking, Slots & Requests, Payment Attestation, Contact Visibility

### Category booking mode

Every listing carries a `bookingMode`: `'slot'` or `'request'`, defaulted by category (seeded in Phase 4) and editable per listing.

| bookingMode | Categories | Why |
|---|---|---|
| `slot` | Cleaning, Beauty, Fitness | Fixed or provider-predictable duration; appointment-shaped |
| `request` | Plumbing, Electrical, AC Repair, Photography, Gardening, Computer, Moving, Events | Duration depends on diagnosis, property, or negotiation — cannot be pre-published as a fixed-length slot |

🔧 This assignment is a config table, not a structural decision. Confirm before Phase 4 seeds it.

**Emergency capability is separate and restricted.** A listing may set `isEmergency: true` only if **all** of the following hold:
- its category is **Plumbing, Electrical, or AC Repair**
- the provider's `verificationStatus` is `verified`

Enforced server-side on the listing publish and update paths, and re-checked at booking creation (a provider whose verification is later revoked stops receiving emergency requests immediately).

### 🔧 Discovery must signal booking mode

Search results, category results, and Home cards show a mode affordance — **"Book instantly"** for slot-based, **"Request a time"** for request-based, plus an **"Emergency available"** marker where applicable. v3 had no signal at all: a customer expecting to pick a time got a form, or vice versa. This is also a genuine differentiator worth surfacing.

### Slot-based flow

- Provider publishes bookable time slots (Phase 9a), generated from availability rules with individual override.
- **Customers only ever see currently-open slots.** No picker ever shows an unavailable time.
- Booking a slot reserves it atomically inside the booking-creation transaction. A race resolves to exactly one winner.
- Cancellation or decline frees the slot back to `open`.

### Request-based flow

- Customer submits a **preferred date/time window** (not an exact slot — "Tuesday afternoon", "this week"), job details, and location.
- Provider reviews via the same accept prompt and **responds with a proposed concrete date/time and price**. This reuses the quote mechanism (`awaiting_quote` → `quote_offered`).
- 🔧 **Offering a quote creates a provisional reservation** on the proposed time, expiring with the quote's 72-hour approval window. Without this, the provider could sell that time to someone else in the interim and the customer's approval would fail on a constraint violation after they had already agreed a price.
- Customer approves or rejects. Approval converts the provisional reservation to a firm one and transitions to `accepted`.
- Everything downstream is identical to the slot-based flow from `accepted` onward.

### Emergency bookings

- Customer submits an ASAP request — no slot, no window — with job details and location.
- Provider gets an **urgent accept prompt** with a **30-minute** response window (🔧 not 24 hours; a 24-hour auto-decline is meaningless when a pipe has burst).
- **On acceptance** the provider sets a **callout fee** as `agreedAmount` — the amount they charge to attend. 🔧 They cannot price the full job before seeing it; the callout fee is what they *can* price. The UI labels it "Callout fee" and states plainly that parts and labour are settled directly with the provider afterward, consistent with every other booking on the platform.
- **Contact unlocks at `payment_claimed`**, same as every other booking type. The customer attests payment of the callout fee, then gets the number. A customer with a flooding bathroom will tap "I've Paid" without hesitation; a customer farming phone numbers will not.
- 🔧 **`scheduledFor` is set to the acceptance timestamp**, so the 7-day completion timeout fires normally. In v3 it was null and emergency bookings could never auto-complete, letting a provider block reviews of emergency work forever by staying silent.
- **No calendar reservation** — an emergency is understood as an interruption to the published calendar, not a block on it.
- **Rate limit:** 3 emergency requests per customer per 24 hours, 10 per 7 days. Accept-then-cancel patterns are logged as a moderation signal (Phase 22).
- **If no one accepts within 30 minutes:** the booking auto-declines, the customer is notified, and is offered one tap to send the same request to a different emergency-capable provider, or to convert it to a normal request-based booking. 🔧 Simultaneous fan-out to multiple providers is deliberately out of v1 scope — see §6.

### Pre-booking enquiry — contact-masked, soft-nudged

- A `Conversation` of type `enquiry`, scoped to a **listing** (not a booking), available to any phone-verified user before any booking exists.
- **Everything is allowed** — appliance make/model/serial number, property details, photos of the issue, availability questions, price ranges. The point is to let a plumber ask "is it a split unit or ducted?" and a customer answer.
- **Contact-pattern detection is a soft nudge, never a block.** The sender sees an inline, non-blocking reminder: *"Contact details are shared automatically once a booking is confirmed — you don't need to swap numbers here."* The message sends regardless.
- 🔧 **Every detection is logged** with conversation, sender, and matched pattern, and surfaces in Phase 22's moderation queue as an aggregate signal. A provider who trips the detector across 40 enquiries is visible and actionable; an individual false positive costs nothing.
- **Why not a hard block:** v3 required hard-rejecting phone-shaped text while explicitly allowing appliance serial numbers. Maldivian mobiles are 7 digits beginning 7 or 9; AC serials are 7–15 digit strings; model numbers are alphanumeric with digit runs. These are not reliably distinguishable, and the block would fire on exactly the content the channel exists to carry — on the primary pre-sales path, at the moment of highest intent. Photos were allowed in the same paragraph, so a photo of a business card passed anyway, as did "nine seven one two…". The block was unreliable, circumventable, and created false confidence that leakage was prevented here.
- If a booking is later created between the same two users on the same listing, the **same conversation continues**, now also linked to the booking. Full chat resumes once the booking reaches `accepted`.
- 🔧 **Lifecycle:** if the listing is hidden by downgrade the thread stays readable to both parties but accepts no new messages, with an explanatory state. If the listing is soft-deleted the thread becomes read-only and is excluded from the conversation list after 30 days.
- Restores the "Message" button on Service Preview (Phase 12).

### Access control — graduated

| Tier | Unlocks | Enforced by |
|---|---|---|
| Guest | Browse, search, view listings and public provider profiles | No gate |
| Registered | Save/favourite | `requireAuth` |
| Phone-verified | Book, enquire, message within a booking | `requirePhoneVerified` |
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
- **Emergency** bookings sit in `accepted` until the provider sets the callout fee, then move to `awaiting_payment`.
- **`payment_unresolved` is not terminal.** An admin resolves it to `confirmed` or `cancelled`.
- **`disputed` is not terminal.** An admin resolves it to `dispute_resolved` with an enumerated outcome.

### The flow, step by step

1. Customer picks an open slot (slot-based), submits a preferred window (request-based), or submits an ASAP request (emergency). Status `requested`.
2. **Provider accept prompt** — job details, **no contact info, no chat**. Accept / decline, or (request-based) propose a time + price.
3. **On acceptance the booking carries an `agreedAmount`** (integer laari): from the listing price for fixed pricing, from the accepted quote for request-based, or from the provider-set callout fee for emergency. No booking reaches `awaiting_payment` without one.
4. **🔧 Three accept timeouts, not one:**
   - **Emergency:** 30 minutes → auto-decline, notify customer, offer another provider or conversion to a normal request.
   - **Slot and request-based:** 24 hours → auto-decline, release the slot or reservation, notify the customer to look elsewhere.
   - **Customer quote-approval:** 72 hours from the quote being *offered* (its own clock) → quote expires, provisional reservation releases, booking closes. v3's job auto-declined `quote_offered` 24 hours after *booking creation*, which would have killed quotes the provider submitted at hour 23 before the customer ever saw them.
5. Customer is prompted to pay off-platform, directly to the provider, using the payment details the provider registered (Phase 5). Copy states plainly that RaajjePro is not handling this money.
6. Customer taps **"I've Paid"** — self-attestation, no proof upload. Status `payment_claimed`. **This is the contact-info unlock**, for every booking type including emergency.
7. Provider confirms or disputes receipt. Confirm → `confirmed`. Dispute → `disputed`.
8. **If the provider neither confirms nor disputes within 7 days** → **`payment_unresolved`**, not `confirmed`. Both parties notified, queued in Phase 22's moderation queue. **Nothing further is unlocked by this transition.** An admin resolves it manually. v2 auto-confirmed here, recording an attestation that may never have happened.
9. **Completion.** If the provider doesn't mark the job complete within 7 days of `scheduledFor`, the **customer is prompted**: *"Did [Provider] complete this job?"* (Yes / No / no response).
   - **Yes** → `completed` normally, `completedVia: 'confirmed'`.
   - **No** → flagged to the moderation queue as a possible no-show, same path as a dispute.
   - **No response after a further 3-day grace** → auto-completes, tagged `completedVia: 'unconfirmed'`, distinguishing it from a genuine two-sided completion for analytics and trust purposes while still opening review eligibility. A provider must not be able to block reviews forever by staying silent.
10. Review becomes postable once `completed`. One review per booking.

### Contact visibility

Neither party sees the other's phone, WhatsApp, or Viber handle before **`payment_claimed`**. Uniform across all three booking modes — v3's emergency carve-out at `accepted` is removed.

- Before `accepted`: nothing. The accept prompt is deliberately contact-free and chat-free.
- Between `accepted` and `payment_claimed`: the provider sees the customer's **name and job location only**, via booking context. (Location is necessary to quote and to attend; it is not contact information.)
- At `payment_claimed`: both parties see each other's contact details, via the single booking-scoped endpoint.

Implemented as a **live query** — "does a booking at or past `payment_claimed` exist between these two users" — never a cached flag. `GET /v1/bookings/:id/contact-info` is the only endpoint in the system that returns this data. No listing, provider-profile, or search response may ever include it.

🔧 Note honestly: revocation is meaningless after the fact. If a booking is later cancelled the endpoint stops returning the number, but both parties already have it. The gate controls *when* contact is exchanged, not whether it can be retained.

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

Slots, requests, and contact gating raise the bar meaningfully against off-platform bypass. They do **not** stop a provider publishing their own number in a listing description, an FAQ answer, or a gallery image — and the provider is the party with the incentive. Phase 22's free-text scanning mitigates this; obfuscation defeats it. **Treat the gate as friction, not enforcement.** Nothing in v4 is an access-control guarantee against a determined provider; the enquiry-thread logging (§1c) makes patterns visible, which is the realistic ceiling.

---

## 1d. Categories — 11

**Cleaning, Plumbing, Electrical, AC Repair, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events.**

Tuition is removed entirely — from categories, seed data, and every reference. Phase 4's seed, icon/color mapping, and every category-count reference in this document reflect 11.

---

## 1e. Identity Verification

The Verified badge depends solely on `verificationStatus: 'verified'`. It does **not** require an active subscription — a lapsed-but-verified provider stays verified. The badge is a safety signal, not a payment status.

- **Evidence required:** a national ID or passport, **plus** proof the provider does the trade — a business registration, a trade certificate, or photos of completed jobs.
- **Review:** manual, by the admin role built in Phase 2. No new vendor, no automated KYC, consistent with the manual-first posture of the rest of the platform.
- **Where it lives:** the review queue extends Phase 10a/22's existing admin panel and audit log.
- 🔧 **Document handling — newly specified.** ID and passport images are strictly more sensitive than payment proofs and v3 introduced them with no policy:
  - Stored in a **separate private bucket**, never the media bucket, never publicly addressable, accessed only via short-lived signed URLs.
  - **Retained 90 days after a verification decision, then purged.** The decision, the evidence *type*, and the reviewing admin persist; the images do not.
  - **Every access is logged** — which admin viewed which document, when. The audit log records the decision, the evidence types submitted, and the rejection reason where applicable, so a rejected provider gets a real reason and a disputed decision has a record.
  - Purged immediately on account deletion.
- Emergency capability depends on this status (§1c), which makes verification load-bearing for more than the badge.
- Full evidence checklist, rejection-reason taxonomy, and resubmission path are built in Phase 23. The *decision* — what's required, who reviews, how documents are handled — is locked here so Phases 5 and 10 can build against it.

---

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
| Rate limiting | **Global + per-endpoint tiers** | stricter on auth, OTP, payment, and emergency-booking endpoints |
| **Time conflicts** | **`EXCLUDE USING gist` on `(providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`** | 🔧 replaces `UNIQUE (providerId, listingId, startsAt)`, which let one provider be booked three times at 10:00 across three listings and did not detect overlapping durations at all |
| Push delivery | **FCM + APNs, built in Phase 3c** | ahead of Phase 17, which depends on it, with an explicit fallback chain |

---

## 3. Phased Roadmap

### Phase 0 — Repository & Environment Foundation

- Monorepo `/backend` (domain modules) + `/frontend` (Flutter, feature-based)
- TypeScript strict, ESLint, Prettier, commit hooks; Flutter lint config
- Env config strategy; `.env.example`; no secrets committed
- CI skeleton: lint + build
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

**Done when:** the gallery renders every widget; a11y criteria verified with a screen reader and at 200% text scale; `flutter analyze` clean.

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
- **Admin identity model:** admin users, a single `admin` role for v1, login, session. Not a stub. MFA and network segregation documented as post-v1 (§7).
- **Audit log:** every admin action records admin ID, timestamp, action, target, and reason. Queryable by date / admin / action type.

**Done when:** `/v1/health` returns 200; a malformed request returns the standard envelope; a repeated idempotent POST returns the original result; rate limits trigger correctly; an admin action appears in the queryable audit log.

### Phase 3 — Identity & Authentication

- Register, login, JWT access + refresh rotation, logout, `me`, password reset
- Social auth: provider-agnostic interface with stubs (Facebook/Google/Viber)
- **Phone verification:** OTP send + verify, `phoneVerified` flag, `requirePhoneVerified` guard (stricter than `requireAuth`, distinct `PHONE_NOT_VERIFIED` error code)
  - SMS provider chosen and pinned before this phase starts, with a cost model and delivery-failure fallback. Sender-ID registration lead time confirmed.
  - 🔧 **Rate limits, explicit:** **3 OTP sends per phone number per 15 minutes** *and* **5 per user account per hour** (both, not either). **5 verification attempts per issued OTP**, after which it is invalidated and a new send is required. Hitting either send limit returns `OTP_RATE_LIMITED` with the seconds remaining, so the UI can show a real countdown rather than a generic error.
- **Account settings (backend + screens):**
  - change password, change email, change phone (each re-verified)
  - active session list + revoke — per-device refresh tokens so revoking one device doesn't log out the others
  - data export — `GET /v1/users/me/data-export` returns the user's own data as JSON
  - account deletion — App Store requirement. Anonymises all authored content: name/email/phone replaced with a placeholder, listings and reviews preserved so provider rating aggregates stay intact. Soft-delete, not purge. **ID documents (§1e) are purged, not anonymised.**
- Frontend: Login, Register (pixel-match), OTP verification screen (propose first), account settings sub-screens (propose first)

**Done when:** full register → verify → logout → login cycle works; an unverified user browses freely but is rejected by `requirePhoneVerified`; both OTP rate limits verified independently; a deleted account's reviews remain with anonymised attribution; export returns complete data.

### Phase 3b — Forgot Password Flow *(propose design first)*

Reset-token issuance, expiry, consumption; invalidates all refresh tokens on success. Three screens: request email → check-your-inbox confirmation → set new password.

**Done when:** a user can request a reset, receive a token, and set a new password that works on Login; the old refresh tokens are all invalid.

### Phase 3c — Push Notification Infrastructure

Sequenced after Phase 3 (device-token registration needs an authenticated user) and before Phase 9a/17, which depend on it.

- FCM (Android) + APNs (iOS) integration; device token registration, refresh, and multi-device support
- A single **`PushSender`** abstraction — the send interface every later module (17, 19) calls, not one each
- **Detect OS-level permission denial** and store that state on the user
- 🔧 **Fallback chain with explicit timing** for the load-bearing prompt (Phase 17's provider-accept):
  - If push permission is **already known denied**: send SMS **immediately**, in parallel with the (futile) push attempt. Do not wait.
  - If push is permitted but **delivery is unconfirmed after 30 minutes**: send SMS.
  - If SMS **fails or the provider has no verified phone**: send a forced transactional email immediately.
  - v3 said "fails to deliver within the acceptance window" — the window is 24 hours, so an SMS could arrive at hour 23, after the booking had effectively died.
  - **For emergency bookings (30-minute window), SMS fires immediately in all cases**, in parallel with push. There is no time for a fallback ladder.
- 🔧 **SMS content:** booking type, customer first name, job location island, and an instruction to open the app. **No links** — do not train providers to tap links in text messages. No amounts, no phone numbers.
- **Observability:** log every fallback invocation with reason. Alert if SMS fallback exceeds 5% of accept prompts in a rolling day — that indicates a push-integration regression, not user preference.
- A persistent in-app reminder for a provider who has denied push: *"You may miss booking requests — enable notifications."*

**Done when:** a test push arrives on a real device within seconds; a provider with push denied receives an SMS fallback for a booking-accept prompt immediately, not at the end of the window; an emergency prompt fires push and SMS in parallel; multi-device registration and cleanup work; fallback invocations appear in logs.

### Phase 4 — Categories Module

- `Category`: id, name, icon identifier, color token, sortOrder, isActive. Unlimited categories — no hardcoded enum in schema or validation.
- **Seed exactly 11:** Cleaning, Plumbing, Electrical, AC Repair, Beauty, Photography, Gardening, Computer, Moving, Fitness, Events.
- 🔧 **Also seed the `bookingMode` default per category** (§1c) and the `emergencyCapable` flag (true for Plumbing, Electrical, AC Repair only). v3 referenced a Phase 4 seed that Phase 4's spec did not contain. Phase 5 reads it, Phases 9/9a/17 consume it.
- `GET /v1/categories` — public, active categories sorted by sortOrder, including `bookingMode` and `emergencyCapable`.
- Admin-only POST/PATCH/DELETE against **real** admin auth from Phase 2.
- Frontend: Explore screen pixel-matched, grid driven entirely by the live endpoint.

**Done when:** a 12th category added via API appears in Explore with no rebuild; the seeded `bookingMode` and `emergencyCapable` values are readable by a downstream module.

### Phase 5 — Provider Profiles *(backend only)*

- `ProviderProfile`: userId, businessName, bio, yearsOfExperience, `verificationStatus`, createdAt
- **`jobsCompletedCount` derived from the booking event log**, never a hand-maintained counter
- **Contact details — load-bearing:** `phone`, `whatsappHandle`, `viberHandle`. v1 returned these from Phase 17's endpoint without any phase ever creating them.
- **Payment details — load-bearing:** bank name, account name, account number, and/or other transfer instructions. v1's booking flow displayed "the provider's payment details" that no phase collected.
  - Sensitive: excluded from every response except the booking-scoped contact endpoint, and from all logs.
- **`acceptingNewCustomers` at provider level** — one toggle gates all of a provider's listings, and billing pause keys off it coherently.
- **`bookingMode` default lookup** read from Phase 4's seed, overridable per listing (§1c)
- `getOrCreateProviderProfile(userId)` — idempotent
- `findVisibleProviders(...)` — the single shared gate, filtering on derived published-listing count (§1a)

**Done when:** `getOrCreateProviderProfile` called twice returns one row; `findVisibleProviders` excludes a provider whose only listing is a draft and includes them the moment one is published, with no stored status field involved; contact and payment details are absent from every response except the Phase 17 contact endpoint.

### Phase 6 — Customer Profile Module

- `GET /v1/users/me/profile-summary` — one call for the Profile screen
- `PATCH /v1/users/me`
- Frontend: Profile screen (pixel-match), five rows navigating to sub-screens
- **Role switcher:** an explicit customer ⇄ provider mode control. Providers are the only paying users; their workspace must not be buried. Propose the switcher's placement and the resulting provider-mode IA before implementing — this is the one navigation change that departs from the original mockups.

**Done when:** Profile reflects live data; every row navigates; switching to provider mode reaches My Services Dashboard in one action.

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
- Publish endpoint: full required-field validation returning a structured missing-field list
  - **Also enforces the entitlement cap.** v1 checked the cap only at draft creation, so drafts made during a trial could all be published after downgrade.
- Media upload via presigned URL — **server-side content-type and size validation, EXIF stripping on every image**
- Soft-delete only; document cascade rules for a listing with bookings, reviews, or reserved slots
- **View and booking counts come from an event log with periodic rollup**, not per-request counter writes

**Done when:** a listing saves empty, patches per step, publishes only when complete and within cap; `isEmergency` is rejected on a non-emergency category or an unverified provider; a soft-deleted listing disappears from public queries while its bookings and reviews remain intact.

### Phase 8a — Subscription & Trial *(backend only)*

- Generic `PaymentSubmission`: payerId, `purpose` (v1: `subscription`; enum stays open), amount (laari), proofUrl, referenceCode, status, submittedAt, reviewedBy, reviewedAt, rejectionReason
- `ProviderSubscription`: providerId, tier, status (`trialing`/`active`/`free`/`paused`/`expired`), trialStartedAt, trialEndsAt, **billingAnchorAt**, currentPeriodEnd, pausedAt, cumulativePausedDays, remainingPauseAllowanceDays
- **`amount` defaults to MVR 150 = 15000 laari, pinned, not a range**
- 🔧 **Trial starts on either trigger, whichever fires first** (§0.3):
  - the transition of any booking into `confirmed` where this is the provider's first — **hooked on the state transition, not on one endpoint**, so an admin resolving `payment_unresolved` to `confirmed` also fires it
  - `POST /v1/providers/me/subscription/start-trial` — an explicit provider-initiated "Try Premium"
  - Both call the same `startTrial(providerId)` function, which is a no-op if a trial has ever run for that account.
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
- **Progress framing shows "N required fields left to publish"** alongside or instead of "Step 1 of 7" — five fields are actually required, and leading with the step count overstates the commitment
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
- 🔧 **Slot generation window: 60 days rolling**, regenerated by a nightly job. An availability-rule change regenerates **future unreserved slots only** — reserved slots are never touched by a rule change. v3 left the window, the regeneration trigger, and the rule-change behaviour all unspecified.
- Endpoints: generate/regenerate, block/unblock, list open slots for a listing

**Frontend:** provider slot management in the dashboard; customer slot picker showing **only `open` slots**, never an unavailable time.

**Timezone:** all times stored UTC, presented in Maldives time (UTC+5). Document the convention; a single-timezone market makes this simple, but boundary days still need a stated rule.

**Done when:** two concurrent booking attempts on the same slot resolve to exactly one success and one clear "no longer available" error under real concurrency; a slot-based and a request-based booking that overlap in time on the same provider cannot both succeed, even on different listings; a cancelled booking's slot reappears; a blocked range removes those slots; an expired quote's provisional reservation is released.

### Phase 10 — My Services Dashboard

- Stats row, filter pills, list/grid toggle, service cards with context menu, live toggle
- Reachable in one action from the Phase 6 role switcher
- **Slot management entry point** (Phase 9a)
- Renders correctly for a provider with only drafts
- **Badge indicator reflects `verificationStatus` alone** — not subscription state (§1e)

**Done when:** every context-menu action performs a real mutation with no manual refresh; a drafts-only provider sees a correct zero state; the badge persists through a subscription lapse.

### Phase 10a — Provider Billing UI & Admin Panel

**Part 1 — Provider Billing (Flutter).** No mockups; propose first.
- Subscription status: trial countdown / next billing date / free-tier state, upgrade CTA, **"Try Premium" CTA for a provider who has never started a trial** (§0.3)
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
- Audit log viewer (Phase 2)
- 🔧 **Security, mandatory and now specified rather than deferred to implementer judgment.** This app renders user-authored text (listing descriptions, review bodies, enquiry messages) and is the tool that approves money. A malicious provider can plant a script payload in a description and report their own listing to guarantee an admin views it.
  - **Build it in React** (or another framework with default-on JSX escaping). Do not server-render raw HTML string concatenation.
  - **No `dangerouslySetInnerHTML` anywhere**, enforced by an ESLint rule that fails the build.
  - **CSP header:** `default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`. No `unsafe-inline`, no CDN origins.
  - **User-authored fields are rendered as text nodes only** — never as HTML, never as a URL in an `href` without scheme validation.
  - Test with a stored `<script>`, an `<img onerror>`, and a `javascript:` URL in a listing description, a review body, and an enquiry message.
- Real admin auth from Phase 2; never publicly reachable without credentials

**Done when:** a provider submits with proof and sees pending; an admin confirms and the entitlement activates; a rejection surfaces its reason with working resubmit and appeal; CSV import proposes correct matches; the three XSS payloads above render inert in every admin view; an aged `payment_unresolved` item triggers its alert.

### Phase 11 — Reviews & Ratings *(backend)*

- `Review` tied to a **`completed`** booking. One review per booking, enforced.
- Rating aggregation per listing and per provider; star breakdown, computed transactionally on write
- **Auto-completion (Phase 17) is what makes this safe.** Gating reviews on completion is correct *only* because a provider can no longer block completion indefinitely.
- Soft-delete; a hidden review is excluded from aggregates

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

### Phase 14 — Favorites (Saved Services)

Save/unsave endpoints, saved list, heart toggle wired everywhere with optimistic update and rollback, Saved Services screen (propose first).

**Done when:** tapping the heart anywhere persists via API; the Saved Services screen reflects it immediately; Profile's count updates.

### Phase 15 — Search & Discovery

- Search endpoint with filters, sort, pagination, appropriate indexes
- **Sort control and price-range filter** — v1 had four fixed chips and no sort, thin for the primary discovery mechanism
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

The largest phase and the highest-risk one. No mockups — propose each frontend piece before implementing.

🔧 **Build in four sequential slices**, each independently testable, rather than as one unit. Phase 17 carries three booking modes, five scheduled jobs, quote flows, recurring series, reschedule, and dispute/escalation paths. Attempting it in one pass is the single largest delivery risk in this plan.
- **17.1 — slot-based core:** create, accept, decline, claim-payment, confirm-receipt, complete, cancel, contact endpoint, the 24-hour and 7-day jobs
- **17.2 — request-based and quotes:** quote offer/approve, provisional reservations, the 72-hour quote-approval job
- **17.3 — emergency:** the restricted path, callout fee, 30-minute window, rate limits, the no-acceptance fallback offer
- **17.4 — recurring series and reschedule**

**Backend:**
1. `Booking`: listingId, customerId, providerId, `bookingMode` (`slot`/`request`/`emergency`), timeSlotId (nullable), reservationId (nullable), status (§1c, including `awaiting_payment` and `payment_unresolved`), `agreedAmount` (integer laari, nullable until set), `amountKind` (`listing_price`/`quote`/`callout_fee`), quotedAmount, `scheduledFor`, amountSetAt, paymentClaimedAt, paymentAttestedAt, completedAt, `completedVia` (`confirmed`/`unconfirmed`), statusHistory
2. `POST /v1/listings/:id/bookings` — slot-based reserves in-transaction; request-based captures a preferred window; emergency captures no timing constraint but **validates category eligibility, provider verification, and the customer's emergency rate limit**. `requirePhoneVerified`; idempotency key required.
3. `PATCH /v1/bookings/:id/accept` — sets `agreedAmount` for slot and request bookings; **for emergency, accepts without an amount and moves to `accepted` pending the callout fee**. No contact info, no chat exposed.
4. `PATCH /v1/bookings/:id/set-amount` — 🔧 emergency only; provider sets the callout fee; transitions `accepted` → `awaiting_payment` and fires the customer's payment prompt.
5. `PATCH /v1/bookings/:id/quote` / `/approve-quote` — request-based path. Offering a quote creates a **provisional reservation** (Phase 9a); approving converts it to firm.
6. `PATCH /v1/bookings/:id/decline` — provider; frees the slot/reservation; distinct from dispute.
7. **Scheduled job — accept timeouts, three distinct conditions:** emergency `requested` older than **30 minutes**; slot/request `requested` older than **24 hours**; `quote_offered` older than **72 hours from the quote timestamp** (not from booking creation). Each releases its reservation and notifies the correct party.
8. `PATCH /v1/bookings/:id/claim-payment` — customer self-attestation. **This is the contact-info unlock** for all three modes.
9. `PATCH /v1/bookings/:id/confirm-payment-received` — provider; → `confirmed`.
10. **Scheduled job:** `payment_claimed` with no provider response after 7 days → `payment_unresolved`. Notifies both parties, files a Report (Phase 22). **No entitlement or additional access is granted by this transition.**
11. `PATCH /v1/bookings/:id/dispute` — either party; → `disputed`; files a Report.
12. `PATCH /v1/bookings/:id/resolve-dispute` — admin; → `dispute_resolved` with an **enumerated outcome** (§1c); also resolves `payment_unresolved` to `confirmed` or `cancelled`.
13. `PATCH /v1/bookings/:id/complete` — provider; → `completed`, `completedVia: 'confirmed'`.
14. **Scheduled job:** `confirmed` 7 days past `scheduledFor` with no completion → customer "Did this happen?" prompt; a further 3-day non-response auto-completes with `completedVia: 'unconfirmed'`.
15. `PATCH /v1/bookings/:id/cancel` — customer, pre-payment; frees the reservation.
16. `PATCH /v1/bookings/:id/reschedule` — another open slot (slot-based) or a new proposed time (request-based); frees the old reservation atomically.
17. `POST /v1/recurring-series` + management — slot-based only; generates occurrences on cadence, each requiring its own accept; **a missed occurrence skips that week and notifies both parties; three consecutive misses pause the series** (§1c).
18. `GET /v1/users/me/bookings?role=&status=`
19. `GET /v1/bookings/:id/contact-info` — the only endpoint returning contact details, both directions, on a booking at or past `payment_claimed`.
20. **🔧 Trial-start hook fires on the state transition into `confirmed`**, not from one endpoint — so both `confirm-payment-received` and an admin `resolve-dispute` resolution reach it.

**Frontend:**
1. Booking entry, three variants: slot picker (open slots only), request-with-preferred-window, emergency/ASAP — routed by `bookingMode` and the emergency toggle where available.
2. Provider accept prompt: job details, no contact/no chat, accept/decline/propose-quote, **with a countdown matching the mode's actual window** (30 min / 24 h).
3. Emergency callout-fee entry for the provider, with copy stating that parts and labour are settled directly afterward.
4. Payment prompt: provider's payment details, `agreedAmount` shown explicitly and labelled by `amountKind`, honest copy, "I've Paid."
5. Provider receipt prompt: three visually distinct actions — "Payment Received", "Payment Not Received", "Decline Booking".
6. On `payment_claimed`: contact details surfaced as an unlock moment for both parties.
7. **"Did this happen?" prompt** for the customer at the 7-day post-scheduled mark.
8. Bookings tab: status filter pills, detail view, **status timeline showing when each transition happened and who caused it**, distinct badges for every status including `awaiting_payment` and `payment_unresolved`.
9. Recurring-booking entry point and one-tap "Same time next week?".
10. Emergency no-acceptance state: "No one accepted in time" with one tap to try another provider or convert to a scheduled request.

**Done when:** the full lifecycle works for all three modes; concurrent bookings on one reservation window resolve to one winner **even across different listings of the same provider**; an unresponsive provider auto-declines at the correct window per mode; a quote expires on its own 72-hour clock and releases its provisional reservation; an unresolved payment claim escalates to admin review at day 7 without unlocking anything; contact unlocks at `payment_claimed` and never earlier, including for emergency; an emergency booking on an ineligible category or by an unverified provider is rejected; the emergency rate limit triggers; the "did this happen" flow distinguishes confirmed from unconfirmed completions and fires for emergency bookings too; a missed recurring occurrence skips rather than kills the series; reschedule manages reservations atomically; the contact endpoint returns data only for a genuinely eligible pair.

### Phase 18 — Messaging Module

- `Conversation` type **`enquiry`** (listing-scoped, pre-booking) or **`booking`** (full chat, from `accepted` onward)
- `requirePhoneVerified` on both types
- 🔧 **Contact-pattern detection is a soft nudge in both types — never a block, never a redaction** (§1c). Every detection is **logged** (conversationId, senderId, matched pattern, timestamp) and aggregated into Phase 22's moderation signals.
- Block user; report from within a conversation
- Enquiry-thread lifecycle on listing hide/delete (§1c)
- Frontend: conversation list (both types), thread view, the inline non-blocking nudge banner near the composer

**Done when:** an enquiry thread delivers a message containing an appliance serial number without obstruction and logs a detection where one fires; a nudge appears inline and never blocks a send; two verified accounts exchange messages in both conversation types; blocking and reporting both work; detection aggregates are queryable by provider.

### Phase 19 — Notifications Module

Notification **content**, not delivery — Phase 3c owns delivery.

- `Notification`: userId, type, payload, readAt, createdAt — calls Phase 3c's `PushSender`, never reimplements delivery
- Types: booking_requested, booking_accepted, booking_declined, booking_auto_declined, emergency_no_acceptance, amount_set, payment_claimed, payment_confirmed, payment_unresolved, payment_disputed, dispute_resolved, booking_completed, booking_auto_completed, completion_check_prompt, recurring_occurrence_missed, recurring_series_paused, payment_submission_confirmed, payment_submission_rejected, verification_approved, verification_rejected, trial_ending_7d, subscription_ending_7d, downgraded_to_free, winback_7d, winback_30d, new_message, new_enquiry, new_review
- **Weekly provider digest email** (opt-in): views, bookings, reviews, top-performing listings
- **Provider analytics dashboard:** per-listing views, booking counts, conversion rate, rating trend, response time
- **Response-time metric shows "No data yet"** for a provider with zero booking-acceptance history, never a blank or a zero that reads worse than no metric at all
- Notification centre screen (propose first); live badge counts

**Done when:** each event type fires through Phase 3c's sender; the digest sends on schedule to opt-in providers only; the analytics dashboard renders real data; a brand-new provider's response-time metric reads "No data yet," not "0 minutes."

### Phase 20 — Hardening, QA & Launch Readiness

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
- State audit against every screen: loading / empty / error / populated
- **Accessibility audit** against Phase 1's criteria across all screens
- Known-limitations document

**Done when:** suite passes; every concurrency test holds; §5's targets are measured and met or consciously accepted; the stub and decision registers are complete; the a11y audit passes.

### Phase 21 — Observability & Crash Reporting

- Backend APM/error tracking wired into Phase 2 logging
- Flutter crash reporting — 🔧 **pull this integration forward to Phase 3** and leave only the ProductEvent log and uptime monitoring here. Crash reporting genuinely wants to exist from the first real screen, not after twenty phases of building blind.
- Uptime monitoring on `/v1/health` and on the payment-submission endpoints specifically
- **Notification-delivery observability** (§Phase 3c): fallback-invocation rate, alert above 5%
- `ProductEvent` log: draft_created, listing_published, slot_published, booking_requested, booking_accepted, emergency_requested, emergency_unaccepted, amount_set, payment_claimed, booking_confirmed, booking_completed, enquiry_started, contact_pattern_detected, trial_started, trial_converted, trial_expired, search_performed

**Done when:** deliberate backend and Flutter exceptions both surface within minutes; a broken payment endpoint triggers an alert; every event type is confirmed logging; the SMS-fallback alert fires when forced above threshold.

### Phase 22 — Content Moderation & Reporting

- `Report`: reporterId, targetType (`listing`/`review`/`user`/`booking`/`message`/`photo`), targetId, reason enum, status, reviewedBy, reviewedAt, **resolution reason**
- Booking disputes and `payment_unresolved` escalations (Phase 17) file here automatically, with both parties' history shown together
- Admin queue extends Phase 10a's panel and reuses its auth and audit log
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
- **Phase 3c (Push) sits ahead of Phase 9a and Phase 17** — Phase 17's accept prompt is load-bearing on real-time delivery and must not wait on a phase built after it.
- **Phase 9a is a hard prerequisite for Phase 17.** Do not let it get absorbed; Phase 17 is already the largest phase in the plan.
- **Phase 17 builds in four slices** (17.1–17.4, §Phase 17). Do not attempt it in one pass.
- **Phase 8a's trial hook fires from Phase 17's transition into `confirmed`**, plus its own `start-trial` endpoint.
- **Phase 17 and Phase 22** retain a soft circular reference (disputes and escalations file Reports); build 17 first with a minimal Report insert, 22 makes the queue real.
- **Phase 4 must seed `bookingMode` and `emergencyCapable`** before Phase 5, 8, 9a, or 17 read them.
- **Pin before Phase 3:** SMS provider, cost model, sender-ID lead time. Phone verification gates booking, enquiry, and messaging — SMS is a single point of failure for the entire transactional core.
- **Pin before Phase 3c:** confirm SMS fallback cost at scale. Every push-denied provider now costs an SMS on every accept prompt, and emergency prompts send SMS unconditionally.
- **Pin before Phase 4:** confirm the per-category `bookingMode` table (§1c) — it drives which listings get a slot picker vs. a request form.
- **Pin before Phase 8a:** the trial-start trigger applied in §0.3, if you want to override it.
- **Resolve before Phase 8a goes deep:** Phase 23's App Store subscription question. A negative answer forces a data-model change.
- **Phases 21, 22, 24** have no dependency on one another. Pull Phase 21's crash-reporting integration forward to Phase 3.

---

## 5. Non-Functional Targets

🔧 New in v4. No revision of this plan has ever stated one, which meant Phase 20's performance and reliability audits had nothing to audit against.

| Dimension | Target |
|---|---|
| API latency | p95 < 400 ms, p99 < 1000 ms, measured at the edge, excluding media upload |
| Slot picker | Payload capped at 14 days of slots per request with pagination; renders in < 1.5 s on a 3G connection |
| App cold start | < 3 s to interactive Home on a mid-range Android device |
| Push delivery | 90% of accept prompts delivered within 30 s; SMS fallback within 2 min of trigger |
| Availability | 99.5% monthly on the API, measured against `/v1/health` |
| Backups | RPO 24 h, RTO 4 h — drilled in Phase 24, not assumed |
| Admin SLA | Payment submissions confirmed/rejected within 48 h; `payment_unresolved` items resolved within 5 business days; verification decisions within 5 business days |
| Supported devices | Android 8.0+, iOS 14+ |

These are starting targets, not contractual. Measure in Phase 20 and revise deliberately rather than discovering them in production.

---

## 6. Post-v1 Backlog — deliberate, not forgotten

- **Credit wallet & à la carte purchases**; the **advertising module**. Both require demand density that will not exist at launch. `PaymentSubmission`'s `purpose` enum stays open so they slot back in additively. Note the `boosted_placement` / `search_boost` naming collision to resolve when ads return.
- **Referrals — cut from v1, revisit only with fraud controls:** same-device/IP detection, a per-account cap, credit issued on the *referred provider's first confirmed subscription payment* rather than a free off-platform-verifiable booking, and a re-examination of the stored-value question under Maldives Monetary Authority rules. The MVR 50-per-completed-booking design was farmable at zero cost by two accounts and four free actions.
- **Emergency dispatch fan-out** — sending one emergency request to several eligible providers simultaneously, first accept wins, others auto-decline. Reuses the existing reservation race machinery. Deliberately out of v1 because Phase 17 is already the largest delivery risk; the v1 fallback (§1c) is a one-tap retry with another provider.
- **Recurring bookings on request-based services** — currently slot-based only. Weekly plumbing checkups can't commit to a fixed duration upfront. Revisit if recurring proves valuable on the slot-based categories.
- **Dhivehi / Thaana localisation with RTL.** Needs a second font stack — Plus Jakarta Sans and Inter carry no Thaana coverage. A Phase 1 typography consequence worth knowing now even though the work is deferred.
- Admin role granularity, MFA, and network segregation · full analytics platform on Phase 21's ProductEvent log · automated image moderation · saved searches and alerts · real social auth.
- **Data export counterparty-PII redaction** — out of v1 by explicit choice (§7). If a provider's export containing a customer's name, booking time, and amount becomes a real complaint or compliance question, this is a small contained fix.
- **In-app feedback mechanism** — absent across all four revisions. Worth adding once there are enough users to generate signal.

---

## 7. Explicitly Deferred by Your Choice

Distinct from the backlog — these were offered as in-scope and you chose not to include them. Recorded so they read as decisions, not oversights.

- **Admin hardening** (MFA, IP allowlist, a staffing plan behind the 48-hour SLA) stays out of v1.
  **Residual risk:** a single admin role with a single reviewer is your only check on money-adjacent actions — entitlement grants, content hiding, dispute resolution, and now identity verification (§1e), which makes that account the arbiter of the platform's only real trust signal *and* the gate on emergency capability. Worth a look before the provider count makes a mistake expensive.
- **Data export counterparty-PII redaction** stays out of v1 — a provider's export currently includes their customers' names, booking times, and amounts.

---

## 8. What This Plan Still Doesn't Solve

Two things worth keeping in view, because no amount of planning detail addresses them.

**Provider-side leakage remains open, and v4 is honest about the ceiling.** Slots, requests, and contact gating raise the bar considerably against customers bypassing the platform. They do not stop a provider putting their number in a listing description, an FAQ answer, or a gallery image. v3 attempted enforcement in the enquiry thread via a hard block; v4 removed it because it could not distinguish a phone number from an AC serial in a 7-digit-number country, and photos passed regardless. What replaces it — logged detections surfacing as provider-level moderation signals (§Phase 22) — is the realistic ceiling: it makes patterns visible and actionable without breaking the pre-sales channel. **Treat the gate as friction, not enforcement.**

**The competitive question is still unanswered.** Nothing in this plan establishes why a Maldivian provider or customer leaves Facebook groups and Viber — free, universal, zero-friction — for this. v4 improved the customer journey substantially: the booking model now fits the services, the enquiry channel restores the pre-sales conversation, and no mechanism manufactures a false record from silence. But the fundamental comparison — one Viber message versus register / verify / enquire / book / wait / pay / attest — remains unfavourable, and the contact gate necessarily adds friction to the free side of the market to protect monetisation on the paid side.

This is a positioning and go-to-market problem, not a development one. It deserves an answer before Phase 8a, not after launch.

---

## 9. Decision Log

Every substantive choice in this document, in the order made. All rounds dated 2026-08-03.

**Round 1 — core logic (11 decisions):** booking reordered to provider-commits-before-payment via time-slot publishing (yours, refined into §1c's slot/request/emergency split) · `agreedAmount` added · dispute given an exit and admin resolution · completion decoupled from sole provider control · completion-count trial trigger dropped · trial starts at first booking (later refined to first *confirmed* booking) · `lifecycleStatus` made derived, not stored · billing pause moved to provider level · `boosted_placement`/`search_boost` naming collision noted for post-v1 · idempotency added to money and creation paths · credits and ads cut to post-v1.

**Round 2 — product design (4 decisions):** role switcher for the provider dashboard · launch-mode Home for a thin catalogue · accessibility criteria moved into Phase 1 · wizard reframed around required-fields-remaining.

**Round 3 — v2 review, booking model (4 decisions):** category-bifurcated booking mode, Tuition removed · emergency bypasses slots · pre-booking enquiry restored, in-app, service-details-allowed · payment timeout escalates instead of auto-confirming.

**Round 4 — v2 review, monetization & infra (4 decisions):** referrals cut · badge decoupled from subscription · push moved to an early phase with a fallback · 24-hour accept timeout.

**Round 5 — pricing, verification, remaining gaps (4 decisions):** MVR 150/month pinned · pause resumes remaining time, extended to the trial period · identity verification = ID + trade proof, admin manual review · downgrade preserves confirmed future bookings, plus recurring bookings and the response-time fallback label; admin hardening and data-export redaction explicitly left out.

**Round 6 — v3 review, final (4 decisions):** emergency contact unlock moved to `payment_claimed`, `isEmergency` restricted to Plumbing/Electrical/AC Repair with a verification requirement and a per-customer rate limit · enquiry contact filter changed from hard block to soft nudge with logged moderation signals · emergency `agreedAmount` becomes a provider-set callout fee at the payment-request step · all four project artifacts regenerated against a standalone plan.

**Applied without a dedicated question, flagged for override:**
- **Trial-start trigger** now fires on first confirmed booking *or* an explicit "Try Premium" request (§0.3). Recommended in two prior reviews, never asked. This is the single largest lever on subscription conversion.
- The thirteen specification fixes in §0.4 — each resolved a self-contradiction or an unspecified gap rather than a genuine choice.
- Home launch-mode threshold defaulted to 50 published active listings, tunable via config.

**Open, requiring your input:**
- The per-category `bookingMode` table (§1c) — confirm before Phase 4 seeds it.
- Whether premium's contents justify MVR 150 now that the badge is decoupled (§1b) — flagged as a business risk, no change made.
- Phase 23's three research questions — App Store subscription compliance, Maldivian data-protection status, GST obligations.
