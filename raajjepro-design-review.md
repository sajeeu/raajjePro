# RaajjePro — Adversarial Design Review

Reviewed: `01_Development_Plan.md`, `02_Cursor_Prompts.md`, `03_Cursor_Rules_Skills_Subagents.md`, `03b_..._v2.md`
Date: 2026-08-03
Posture: skeptical. Assumptions are challenged, not confirmed.

**Not available to this review:** the Foundational Project Blueprint, `04_Cursor_Best_Practices.md`, and the mockup images. Findings that would depend on those are flagged rather than guessed.

---

## 1. Core Logic Review

### 1.1 🔴 The booking flow inverts how these services are actually bought and paid for

Phase 17's sequence is: customer submits request → customer pays → provider confirms receipt → booking is confirmed → contact info unlocks.

Real-world local services in the Maldives — plumbing, AC repair, electrical, moving — work the opposite way. The provider comes, assesses, does the work, and is paid afterward, usually in cash. The plan asks the customer to pay in full **before the provider has agreed to the job, before a price is knowable, and before any work exists**.

This isn't a theoretical objection. The plan's own pricing model proves it:

- `pricingModel` includes `quote` ([02:224](../Downloads/02_Cursor_Prompts.md:224)) — a listing whose entire premise is that the price is unknown until the provider assesses the job. There is no possible way for a customer to "pay and confirm" a quote-priced booking.
- `range` has the same problem: the customer pays… which end of the range?
- `hourly` and `daily`: paid for how many hours, decided by whom, before the work happens?

Only `fixed` pricing is compatible with the flow as designed, and it is one of five models.

**Why it matters:** this is the product's core loop. If it doesn't match how the transaction actually happens, users route around it — which is precisely the leakage the contact-gating was built to prevent. The gate and the flow are working against each other.

**Recommendation:** restructure to `requested → accepted (provider commits, price agreed) → in_progress → completed → payment_claimed → payment_confirmed`. Unlock contact info at `accepted`, not after payment. That matches reality, gives the provider a real commitment point, and still ties the unlock to a platform-mediated event.

### 1.2 🔴 A booking has no amount

The Booking entity ([02:533](../Downloads/02_Cursor_Prompts.md:533)) has no price, amount, or agreed-sum field. So:

- "I've Paid" attests to paying an unspecified amount.
- "Payment Received" confirms receipt of an unspecified amount.
- A `disputed` booking gives the Phase 22 admin queue nothing to reason about — no figure, no agreement, nothing but two conflicting assertions.
- Nothing can ever be reported on: no GMV, no average job value, no pricing insight for the analytics you plan to sell.

**Recommendation:** add `agreedAmount` set at provider acceptance, and make both attestation actions reference it explicitly in the UI ("Confirm you received MVR 850 from Ahmed").

### 1.3 🔴 The `disputed` state has no exit

`dispute-payment` transitions `payment_claimed → disputed` ([02:537](../Downloads/02_Cursor_Prompts.md:537)). No transition out of `disputed` exists anywhere in the plan. A customer who genuinely paid and hit a mistaken or malicious dispute is permanently stuck: no contact info, no completion, no review right, no resolution path, money gone.

Compounding it, only the provider can dispute. The customer has no equivalent action — not for "provider never showed up," not for "provider claims I didn't pay when I did." Message 34 of the source conversation proposed both directions; only one was built.

**Recommendation:** add `resolve-dispute` (admin-actionable, restoring to `confirmed` or `cancelled`) and a customer-initiated dispute path. A terminal state on a money-adjacent flow is a support nightmare.

### 1.4 🔴 The provider controls whether they can ever be reviewed

Chain the dependencies: a review requires a `completed` booking (Phase 11) → completion requires `confirmed` ([02:539](../Downloads/02_Cursor_Prompts.md:539)) → `confirmed` requires the provider to attest payment received → completion itself is a provider-only action.

**A provider who never confirms receipt, or never marks complete, can never receive a negative review.** The entire trust layer is gated on the consent of the party being evaluated. Any provider who has a bad job simply doesn't press the button.

**Recommendation:** allow the customer to mark a booking complete, or auto-complete N days after the scheduled date, and open review eligibility on either path.

### 1.5 🟠 The system pays providers not to complete bookings

Phase 17a ends the free trial on the provider's **3rd completed booking** ([02:561](../Downloads/02_Cursor_Prompts.md:561)). Completion is provider-initiated and confers no benefit on them.

So marking work complete costs a provider their remaining free trial and exposes them to review. The rational provider never presses it. That silently breaks trial expiry, review volume, booking stats, `jobsCompletedCount`, and every "trending" heuristic derived from completions.

**Recommendation:** drop the completion-count trial trigger entirely, or tie it to bookings *received* rather than completed.

### 1.6 🟠 The trial demonstrates value its recipients cannot use

Premium unlocks multiple listings, priority placement, analytics, and the badge. The trial starts at first publish ([02:264](../Downloads/02_Cursor_Prompts.md:264)) and runs 60 days.

A brand-new solo provider — a plumber, an AC technician — has exactly one service. The free tier already gives them one listing with full discoverability, explicitly never paywalled ([01:80](../Downloads/01_Development_Plan.md:80)). During their entire trial, the *only* premium benefits they can actually experience are priority placement and the badge — and priority placement is worthless in a marketplace that has no customers yet at launch.

Sixty days later they are asked for MVR 150–200/month having experienced nothing they'd miss.

**Recommendation:** start the trial clock at the provider's **first received booking**, not first publish. That way the trial is spent in a period when the platform is demonstrably working for them.

### 1.7 🟠 `lifecycleStatus` is a one-way door

`activateProvider` flips `pending → active` and is "a no-op if already active" ([02:167](../Downloads/02_Cursor_Prompts.md:167)). There is no reverse transition.

A provider who publishes one listing, then pauses or deletes it, stays `active` forever with zero public listings. They remain eligible for Featured Providers and their public profile page stays reachable — rendering exactly the empty dead-end that §1a's gating was designed to prevent ([01:66](../Downloads/01_Development_Plan.md:66)).

**Recommendation:** derive public visibility from `count(published listings) > 0` rather than from a stored status field. The stored field will always drift from the thing it's proxying.

### 1.8 🟠 The contact gate is one-directional and trivially bypassed by the party motivated to bypass it

The gate hides the *provider's* number from the customer. But:

- The provider receives a booking request with the customer's name and details and can message them in-app from the moment the request lands.
- The provider is the party paying for the platform, so the provider is the party motivated to take the relationship offline.
- Any provider can hand out their own number in chat, in a listing description, in an FAQ answer, or in a gallery image, in step 1 of the wizard, before any customer interaction exists.

The plan acknowledges in-chat leakage as a moderation problem ([01:148](../Downloads/01_Development_Plan.md:148)) but doesn't address the simpler vector: the provider's own listing content is free-text and never scanned.

**Why it matters:** the gate imposes real cost on customers (register → verify → book → pay → wait) to protect a revenue model customers get nothing from — while the provider can defeat it in a text field. That's the worst possible split of friction and benefit.

### 1.9 🟡 Billing pause is anchored to a per-listing flag

Phase 8a permits pausing "while the provider's Availability `acceptingNewCustomers` flag (from the Listings module) is false" ([02:270](../Downloads/02_Cursor_Prompts.md:270)). But `acceptingNewCustomers` is a **Listing** field ([02:226](../Downloads/02_Cursor_Prompts.md:226)), not a provider field. With three listings, which one governs? Also unspecified: can a *trial* be paused? If so, 60 days stretches indefinitely.

### 1.10 🟡 Two different things are both called "boost"

Phase 8b sells a credit-funded `boosted_placement` entitlement that affects search ranking. Phase 8c sells an ad placement type literally named `search_boost` ([02:305](../Downloads/02_Cursor_Prompts.md:305)). Phase 15 consumes both. Their interaction — does a provider with both get double lift? does one outrank the other? — is never defined, and the shared name guarantees confusion in code review.

### 1.11 🟡 Draft creation is not idempotent, but the API contract claims it should be

`011-api-contract.mdc` requires idempotent operations to behave idempotently. `POST /v1/listings` with an empty body creates a new draft on every call. Phase 16's "Become a Provider" is specified to *resume* an existing draft ([02:516](../Downloads/02_Cursor_Prompts.md:516)); Phase 9's "New Service" creates a fresh one. Same endpoint, opposite expectations, no idempotency key. A double-tap on a slow connection produces orphan drafts — which matters when the free cap is one active listing.

---

## 2. Product Design Review

### 2.1 🟠 The information architecture is customer-shaped; the paying user is buried

The bottom nav is Home / Explore / Bookings / Messages / Profile — a pure consumer IA. The provider's entire workspace, the My Services Dashboard, is a sub-route under Profile. Phase 10's own prompt flags uncertainty about this ([02:364](../Downloads/02_Cursor_Prompts.md:364)).

There is also no role switcher anywhere. One human is both a customer and a provider on one account (`role` defaults to customer; ProviderProfile is a separate entity), and the app never gives them a way to change context. The Bookings tab must serve both "jobs I've requested" and "jobs requested of me" with no design for that.

**Why it matters:** providers are the only people who will ever pay you, and their primary surface is two taps deep behind a tab named after something else.

### 2.2 🟠 Home is designed for a mature marketplace and will look broken on day one

Home renders five content rows: Popular Near You, Featured Providers, Popular This Week, Nearby, Recently Viewed ([02:497](../Downloads/02_Cursor_Prompts.md:497)). At launch, with perhaps 20 listings, every row will show the same handful of services — or empty/skeleton states stacked down the page.

No cold-start strategy exists anywhere in 29 phases. The plan's Definition of Done for Phase 16 asks that each section show "a real, correctly-empty, or correctly-loading state," which is exactly right *mechanically* and misses the product problem: a home screen that is technically correct and visibly empty reads as abandonment.

**Recommendation:** design a launch-mode Home that collapses to two sections and a strong category grid, with the full layout gated behind a catalogue-size threshold.

### 2.3 🟠 No offline or poor-network behavior anywhere

Nothing in 29 phases addresses connectivity. Inter-atoll mobile data in the Maldives is uneven — this is not a generic concern here.

The sharpest instance: the wizard PATCHes on every step transition as its autosave mechanism ([02:328](../Downloads/02_Cursor_Prompts.md:328)). With no offline queue and no write-through cache, a provider filling in seven steps on a weak connection either loses work or hits repeated errors — during the single most important conversion flow in the app.

Phase 14 specifies optimistic UI for favourites and nothing else.

### 2.4 🟠 Accessibility is entirely absent

Across four documents, 29 phases, and seven rule files, there is no mention of: minimum touch targets, contrast ratios, `Semantics` labels, dynamic type / `textScaler`, screen reader support, or reduced-motion. Phase 1 builds the entire design system with no a11y requirement, which means every one of ~25 screens inherits the gap.

The motion vocabulary is heavy (tap-scale on everything, animated pills, spring sheets) with no reduced-motion path.

**Recommendation:** add a11y acceptance criteria to `030-design-system.mdc` now, while Phase 1 is unbuilt. Retrofitting across 25 screens costs 10x.

### 2.5 🟡 Provider onboarding is a 7-step wizard as a first impression

The wizard doubles as onboarding, which is elegant. But the first experience of becoming a provider is a seven-step form with roughly 40 fields, presented to a small trades business owner on a phone. Only five fields are actually required to publish ([02:238](../Downloads/02_Cursor_Prompts.md:238)).

The design correctly allows jumping to Review at any point — but the *perceived* commitment is "Step 1 of 7," not "3 fields left."

**Recommendation:** surface a live "N required fields remaining to publish" indicator instead of leading with step count, and consider collapsing steps 5–6 into an "optional details" section reachable after publish.

### 2.6 🟡 Retention is unaddressed

Notifications are purely transactional. There is no digest, no "your listing got 14 views this week," no saved-search alert, no re-engagement of any kind. For customers the natural usage frequency is perhaps twice a year — retention is the hardest problem in this category and the plan has no mechanism for it beyond Saved Services and Recently Viewed, both passive.

### 2.7 🟡 Error UX for the flows most likely to fail is unspecified

- Payment submission **rejected**: how does the provider learn? Phase 19's notification types don't include it; the billing screen is pull-only ([02:394](../Downloads/02_Cursor_Prompts.md:394)).
- OTP never arrives: resend with cooldown exists, no fallback, no support path. This blocks booking *and* messaging.
- Publish blocked by entitlement cap mid-wizard.

### 2.8 🟢 What's genuinely good here

Worth stating plainly, because it's above average: the loading/empty/error/populated discipline is enforced at the rule level, in a skill, and in Definitions of Done. The design-token discipline (no inline colors, extend shared widgets rather than fork) is real and will hold up. The "propose a design and stop" gate for un-mocked screens is a well-designed constraint on agent drift.

---

## 3. Feature Gap Analysis

Missing features a user of this app would reasonably expect:

| Gap | Severity | Note |
|---|---|---|
| **Account deletion** | 🔴 | Apple requires in-app deletion for any app offering account creation. Absent from all 29 phases. Blocks App Store release. |
| **Double-booking prevention** | 🔴 | `scheduledFor` exists; nothing prevents two customers booking the same slot. Availability is day-of-week + open hours only — no capacity, no conflict check. |
| **Block a user** | 🔴 | Messaging has no block. In a country of ~550k where social circles overlap heavily, no block function is a serious safety gap. |
| **Report from inside a chat** | 🟠 | Reports are reachable from listings, reviews, and provider profiles — not from a conversation, which is where harassment actually occurs. |
| **Provider analytics** | 🟠 | Sold as a premium benefit in §1b and defined nowhere. You are charging MVR 150–200/month for an undefined feature. |
| **Booking reschedule** | 🟠 | Only cancel and decline exist. Rescheduling is the single most common change to a service appointment. |
| **Change password / email / phone in-app** | 🟠 | Reset-by-email exists (Phase 3b). In-session change appears only as a parenthetical in a proposed sub-screen ([02:187](../Downloads/02_Cursor_Prompts.md:187)). |
| **Session / device management** | 🟠 | Same parenthetical. Never scoped. |
| **Web presence / deep links** | 🟠 | §1c justifies open guest browsing partly on **SEO** ([01:115](../Downloads/01_Development_Plan.md:115)) — but there is no web surface in the entire plan, so there is nothing to index. The Share button on Service Preview has no link target infrastructure, no universal links, no fallback page. |
| **Receipts / invoices** | 🟠 | Providers and advertisers pay a business expense and receive no document. GST treatment is never mentioned. |
| **Entitlement reversal / refund** | 🟠 | An admin can confirm a payment. Nothing can un-confirm one. No refund, no reversal, no correction path for a mistaken confirmation. |
| **Admin user provisioning** | 🟠 | Every admin endpoint is role-gated against a stub. No phase creates admin accounts, defines admin roles, or manages them. |
| **Search sort & price filter** | 🟡 | Four fixed filter chips, no sort control, no price range, no distance sort. |
| **ToS re-acceptance on change** | 🟡 | Accepted once at registration; no versioning or re-prompt. |
| **Help / FAQ / in-app support** | 🟡 | Phase 24 adds a contact link. No self-service content, no dispute guidance for the flow most likely to confuse people. |
| **Feedback mechanism** | 🟢 | None. |
| **Data export** | 🟢 | Relevant to data-protection compliance; not needed at v1. |

---

## 4. Technical Architecture Review

### 4.1 🔴 Wallet spending has a check-then-act race and no idempotency

Phase 8b: "Each spend endpoint must check sufficient balance first and reject with a clear error if insufficient — never allow a negative balance" ([02:291](../Downloads/02_Cursor_Prompts.md:291)).

That is a textbook TOCTOU race. Two concurrent spends both read a balance of 100, both pass the check, both debit. There is no mention of a transaction, row lock, or a DB-level `CHECK (balance >= 0)` constraint anywhere.

No money-adjacent POST in the plan accepts an idempotency key: top-up requests, spends, upgrade requests, ad payment submissions. A double-tap on "Top up MVR 250" creates two submissions; two admins confirming the same submission concurrently credits twice.

### 4.2 🔴 Payment proof images have no stated access control

Proof-of-payment uploads are bank transfer screenshots — they contain account numbers, names, and balances. They go through the same presigned-upload path as listing photos ([02:243](../Downloads/02_Cursor_Prompts.md:243)) into the same object storage.

Nothing specifies: whether these objects are private, whether reads are signed and short-lived, whether they're segregated from public listing media, or a retention period. If the presigned pattern yields publicly-readable URLs — the default in many S3 setups — every provider's financial documents are world-readable to anyone with the URL.

Also unaddressed for all uploads: server-side content-type and size validation, EXIF stripping (listing photos will carry GPS coordinates of providers' homes), and any malware scanning.

### 4.3 🟠 There is no background job runner in the architecture

Trial expiry is check-on-read ([02:265](../Downloads/02_Cursor_Prompts.md:265)). Ad campaign expiry is check-on-read ([02:312](../Downloads/02_Cursor_Prompts.md:312)).

Consequences:
- A trial that expired three days ago still grants premium entitlements until something happens to read that record — and `getProviderEntitlements` is never specified to invoke `checkTrialExpiry`, so entitlements can be served from stale state indefinitely.
- No renewal reminders are possible, which matters enormously when renewal is a manual bank transfer the provider must remember to initiate.
- No OTP cleanup, no digest email, no expiry sweeps, no reconciliation jobs.

Adding a scheduler after 20 phases of assuming none exists is a structural retrofit, not a small addition.

### 4.4 🟠 Money has no specified numeric type

`amount`, `price`, `priceMax`, `balance`, `priceQuoted`, package prices — none of these specify Decimal, integer minor units, or anything else. If any lands as a float, you get rounding errors in a financial ledger. This is the cheapest fix in this document and the most annoying to discover late.

**Recommendation:** integer laari (MVR × 100) throughout, stated in `010-backend-conventions.mdc`.

### 4.5 🟠 Counter design is inconsistent and write-heavy

`jobsCompletedCount` is specified as derived, "don't hand-maintain as a raw counter if it can drift" ([02:161](../Downloads/02_Cursor_Prompts.md:161)) — good instinct. But `viewCount` and `bookingCount` on Listing are hand-maintained counters updated on every event ([02:228](../Downloads/02_Cursor_Prompts.md:228), [02:543](../Downloads/02_Cursor_Prompts.md:543)).

Every Service Preview open becomes a row write with lock contention on popular listings, plus a second write for the Recently Viewed log. Two different strategies for the same class of problem, in the same entity.

**Recommendation:** one event log, periodic rollup. Also gives Phase 21's ProductEvent requirement most of its data for free.

### 4.6 🟠 No deletion or cascade semantics

`DELETE /v1/listings/:id` is owner-only and otherwise unspecified. What happens to:
- bookings referencing that listing?
- reviews referencing it (and the provider's aggregate rating derived from them)?
- an active ad campaign whose `listingId` points at it?
- a `confirmed` booking whose contact-info unlock is a live query against it?

Same questions for provider profiles and user accounts. No soft-delete convention exists in any rule file.

### 4.7 🟡 Client-side entitlement checks will drift

Phase 9 adds `GET /v1/providers/me/entitlements` ad hoc ("add this thin read-only endpoint if it doesn't already exist" — [02:329](../Downloads/02_Cursor_Prompts.md:329)) so the client can decide whether to show an upgrade prompt. Meanwhile the rules correctly insist entitlements are always live-checked server-side.

The gap: nothing enforces the cap at **publish** time. Phase 8's publish endpoint runs required-field validation only. A provider can create drafts while on trial and publish them all after downgrading.

### 4.8 🟡 No caching strategy at all

Home fires six endpoints on open. Categories and Islands are near-static reference data fetched fresh every time. No ETag, no Cache-Control, no client-side cache policy. Not a scale problem at this market size — it's a battery and mobile-data problem for users on metered atoll connections.

### 4.9 🟢 What's architecturally sound

Domain-module boundaries with cross-module access via exported service functions; the response envelope; `/v1` versioning with a no-in-place-breaking-change rule; Zod validation with generated OpenAPI; dependency inversion for SMS, email, storage, and social auth; explicit authorization checks required per mutating endpoint. This is a better foundation than most projects at this stage.

---

## 5. Security Review

### 5.1 🔴 Admin authentication is stubbed in every phase that introduces it, and de-stubbed in none

Phase 4 ([02:141](../Downloads/02_Cursor_Prompts.md:141)), Phase 8a ([02:271](../Downloads/02_Cursor_Prompts.md:271)), Phase 8c, Phase 10a, Phase 22 all defer admin auth to a stub or to "basic auth appropriate for internal-only use." Phase 20's security pass never lists replacing them.

These endpoints grant money-equivalent entitlements, hide content, and suspend providers. There is no admin identity model, no MFA, no role granularity, no network segregation from the public API, no audit trail on entitlement grants, and no way to create an admin user.

### 5.2 🔴 Stored XSS reaches an admin web app

All user-authored text (bio, descriptions, FAQs, tags, review comments, chat messages, business names) is rendered by Flutter, which is not XSS-susceptible. So the plan's lack of output-sanitization guidance looks harmless.

It isn't: the admin panel is explicitly **a separate web app** ([01:47](../Downloads/01_Development_Plan.md:47)), and it renders exactly this content — reported listings, reported reviews, disputed bookings, advertiser business names. A malicious provider can put a script payload in a listing description, report their own listing to guarantee an admin views it, and execute in the context of the tool that approves payments.

Nothing in any rule file or phase mentions output encoding, CSP, or sanitization.

### 5.3 🔴 No rate limiting on OTP sends

Phase 3 specifies "attempt limiting" on OTP *verification* ([02:102](../Downloads/02_Cursor_Prompts.md:102)) but nothing on *sending*. Every send costs real money to an SMS provider. An unauthenticated or lightly-authenticated send endpoint with no limit is a direct financial denial-of-service — an attacker can drain your SMS budget from a script.

Beyond OTP, the only rate limit in the entire plan is on review creation (Phase 22). No global API limits, no login brute-force protection, no lockout policy.

### 5.4 🟠 SMS is a single point of failure with no provider chosen

Phone verification gates *both* booking and messaging — the app's two transactional actions. The SMS sender is stubbed behind an interface with no provider selected, no cost model, no delivery-failure fallback, and no alternative verification path.

If SMS delivery degrades, the marketplace stops functioning entirely. Also unaddressed: many carriers require sender-ID registration before A2P SMS will deliver reliably, which has lead time.

### 5.5 🟠 ID scheme is unspecified, and enumeration surface is wide

Nothing states whether IDs are UUIDs or sequential integers. Prisma's common default patterns include autoincrement. With sequential IDs, `GET /v1/listings/:id`, `/v1/bookings/:id`, `/v1/conversations/:id`, and `/v1/admin/payment-submissions/:id` are all trivially enumerable.

Authorization checks are mandated on mutating endpoints by rule. Read endpoints are less consistently covered — `GET /v1/conversations/:id/messages` never states a participant check.

### 5.6 🟠 PII handling has no policy until Phase 23, which is after everything is built

Collected: names, emails, phone numbers, precise device location, chat contents, and bank transfer proofs. No encryption-at-rest statement, no retention periods, no minimization, no deletion path (see §3).

Phase 23 produces a findings document at the *end* of the build. The findings will arrive after every schema decision is already made.

**Two compliance questions I can't answer from here and you should not assume the answer to:**
- The current status of Maldivian personal-data-protection legislation and what it requires of a platform storing this data. Verify; don't assume nothing applies.
- Whether a stored credit balance denominated 1:1 in MVR constitutes stored value / e-money under Maldives Monetary Authority rules. If it does, the credits system carries a licensing question that would not apply to a plain subscription.

### 5.7 🟡 The contact gate creates false assurance

The app tells users their contact details are protected until a booking is confirmed. In practice any provider can publish their number in a listing description. Users who trust the stated guarantee may behave less carefully than they would on Facebook, where they know exactly what's public.

---

## 6. Business Review

### 6.1 🔴 Monetization is built before demand exists — and before the product does

Phases 8a, 8b, 8c, 10a, and 17a — five phases, roughly a fifth of the effort — construct subscriptions, trials, a credit wallet, à la carte purchases, an advertising system, a billing UI, and a separate admin tool.

All of it is built **before** Search (15), Home (16), Bookings (17), and Messaging (18) exist. That is: the payment infrastructure is complete before the marketplace can perform a single transaction.

Every premium benefit — priority placement, boosts, ad slots, extra listings — derives its value from demand density that will not exist at launch. You cannot sell placement in an empty marketplace.

**Recommendation:** move 8a to a minimal subscription-only implementation, defer 8b (credits) and 8c (ads) entirely past v1, and delay 10a's billing UI until there are providers asking to pay. That recovers roughly 15–20% of the build for a product that can't monetize yet regardless.

### 6.2 🔴 No articulated advantage over the incumbent, which is free

The incumbent for Maldivian local services is Facebook groups, Viber, and word of mouth. All free, everyone is already on them, zero friction, instant phone numbers.

Nothing in these four documents states why a provider or a customer switches. The candidate answer is trust — but the plan's trust mechanism is explicitly *not* verification (it's mutual self-attestation, and the docs are commendably honest about that), and its discovery advantage requires catalogue density it won't have for a long time.

Meanwhile the contact gate makes the comparison actively worse for customers: Facebook gives a number in one tap; RaajjePro requires register → OTP → book → pay → wait for provider confirmation. **You are adding friction to the free side of a two-sided market in order to protect monetization on the paid side.** That is the single largest adoption risk in the plan, larger than any technical finding in this document.

### 6.3 🟠 The free tier may be well-targeted enough to prevent conversion

Free tier: one active listing, full search visibility, never paywalled. That is exactly what a solo tradesperson needs — permanently.

Premium adds: multiple listings (irrelevant to a solo provider), priority placement (worthless while the catalogue is small), analytics (undefined), and the badge (the only clearly desirable item).

The plausible conclusion is that the badge is the actual product and the subscription is a wrapper around it. If so, sell the badge as a one-time or annual verification fee and skip the recurring-billing machinery entirely — which also eliminates the monthly manual-transfer operational load below.

### 6.4 🟠 Manual payment confirmation is an unbounded, permanent operational cost

At 200 paying providers renewing monthly, that's roughly 10 proof reviews per working day, forever, done by a human, with no automation and no tooling beyond a pending list. It also imposes a 0–72 hour activation delay that will read as "the app is broken" to whoever just paid.

The reference-code design is a good foundation for automating this. **Recommendation:** add bank-statement CSV import with auto-matching on reference code before launch, not after. Alternatively, revisit a local gateway (BML Connect / M-Faisaa) sooner than "later" — the plan rules this out permanently rather than as a v1 simplification.

### 6.5 🟡 Ads are premature by roughly two years

Nobody buys a banner in an app with a few hundred users, and the plan has no impression tracking, no reporting to advertisers, no fill-rate logic, and no rotation when multiple campaigns target the same slot.

---

## 7. AI-Specific Review

Not applicable — no AI/LLM component in the current plan.

One adjacent note: §1 of the plan floats automated NSFW/inappropriate-image scanning as a future upgrade. If added, that introduces a model dependency with per-image cost, latency in the upload path, a false-positive appeals workflow, and a human-review queue. Worth scoping as a real feature if it's ever picked up, not as a checkbox.

---

## 8. Edge Cases Likely to Be Overlooked

**Booking / payment**
- Customer pays cash on completion (the normal case) and taps "I've Paid" three days later — booking sat in `requested` with no timeout, no reminder, no expiry.
- Provider marks "Payment Not Received" as a soft decline because it's easier than explaining. Nothing distinguishes them behaviorally, and the dispute becomes permanent (§1.3).
- Provider books their own listing. No self-booking prevention.
- Booking `confirmed`, then the provider is suspended by moderation — does the contact-info live query still resolve for the customer who already relied on it?
- Listing deleted while a booking against it is `confirmed`.
- Customer deletes their account after leaving a review — attribution, and the provider's aggregate rating.

**Money**
- Two admins confirm the same PaymentSubmission simultaneously.
- Provider submits proof, admin confirms, provider disputes the charge with their bank. No reversal path exists.
- Rate card changes between campaign draft and payment confirmation — **correctly handled** by the price snapshot. Good.
- Trial expires mid-wizard while the provider is editing their fourth listing.
- Credits purchased and never spent — no expiry, no refund policy, no liability accounting.

**Identity**
- Provider changes phone number after consuming a trial. Trial eligibility is tied to verified phone; is a new trial granted?
- Two family members share one phone number.
- Social login (stubbed) yields a user with no phone at all — they can never book or message, and no flow collects it post-hoc.
- Refresh-token rotation across two devices. Naive rotation schemes log out device A when device B refreshes; multi-device is never specified.

**Time**
- Maldives is a single timezone (UTC+5), which is a genuine simplification — but `trialEndsAt`, `scheduledFor`, business hours, and `[startDate, endDate]` campaign windows all need a stated convention. "Today's date within the range" is ambiguous about boundary days.
- Ramadan and public holidays change business hours seasonally. Availability has no exception/holiday concept.

**Network / data**
- Duplicate submissions on flaky connections — no idempotency keys anywhere.
- Gallery upload of eight images on 3G with no resumable upload.
- Notification deep-links to a booking the recipient can no longer access.

---

## 9. Missing Requirements

**Functional:** account deletion; password/email/phone change; block user; report from chat; reschedule; double-booking prevention; provider analytics definition; receipts; admin provisioning; entitlement reversal; deletion cascade rules; ToS re-acceptance.

**Non-functional:** no performance targets (p95 API latency, app cold-start, time-to-first-render on Home's six calls); no availability target; no supported OS/device matrix; no minimum-bandwidth assumption despite the market; no data retention periods; no RPO/RTO — Phase 24 runs a restore drill but names no objective it's testing against.

**Security:** no threat model; no pen-test or security-review gate before launch; no secret rotation cadence (Phase 24 documents the process, not the frequency); no admin MFA requirement; no defined incident response.

**Compliance:** Maldivian data-protection status (verify, don't assume); stored-value/e-money question for credits; GST registration and invoicing for subscription and ad revenue; App Store account-deletion requirement; App Store/Play subscription policy (already flagged in Phase 23 — keep it); SMS sender-ID registration lead time.

**Operational:** no runbook; no on-call or alert-response expectation to match Phase 21's alerting; **no SLA for payment confirmation**, despite the entire monetization model depending on a human acting quickly; no defined admin staffing or coverage for weekends.

---

## 10. Development Risks

**Highest-risk component — the manual payments stack + admin panel.** It handles money, spans a second codebase, ships with stubbed authentication, has no reversal path, races on wallet balance, and carries permanent unbounded operational load. Every category of risk in this document concentrates here.

**Second — Phase 17.** The largest single phase (11 backend endpoints plus four separately-proposed frontend surfaces), the product's core loop, and built on a sequence I believe is wrong (§1.1). Getting it wrong is expensive because Reviews, Notifications, trial expiry, and provider stats all hang off it.

**Technical debt already committed:**
- Roughly ten explicit stubs with no reconciliation phase (Phase 6's booking counts, Phase 11's nullable `bookingId`, Phase 16's notification badge, Phase 12/18 route stubs, five admin role checks). Phase 20 doesn't sweep them.
- At least eight decisions delegated to the coding agent with "your call, document it" — statusHistory shape, credits ratio, badge gating logic, real-time strategy, photo-report mechanism, pause auto-resume, trending heuristic, admin panel stack. Each is a coin flip that becomes permanent.
- Two versions of file 03 in circulation, with `02` still pointing at the superseded one.

**Cost:** SMS per OTP, uncapped (§5.3); object storage growing with every gallery and every proof image, with no retention policy; a second web app to maintain; error tracking; and human hours on payment confirmation forever.

**Timeline:** 29 phases. At 2–5 days each including review, that's roughly 3–6 months of solo Cursor-driven work before launch. The monetization tier is 15–20% of that for revenue that structurally cannot exist pre-launch.

**Third-party:** the SMS provider is unchosen and load-bearing on the core loop; social auth is stubbed with real OAuth deferred; object storage, error tracking, and hosting are all undecided at Phase 24.

---

## 11. Prioritized Recommendations

### 🔴 Critical — resolve before writing Phase 8a or Phase 17 code

1. **Reorder the booking flow** so the provider accepts before payment is requested, and reconcile it with `quote`/`range`/`hourly` pricing (§1.1).
2. **Add an agreed amount to Booking** and reference it in both attestation actions (§1.2).
3. **Give `disputed` an exit, and give customers a dispute path** (§1.3).
4. **Decouple review eligibility from provider-controlled completion** (§1.4).
5. **Build real admin authentication** — identity model, MFA, audit trail, network separation — before any admin endpoint ships (§5.1).
6. **Lock down payment-proof storage**: private objects, short-lived signed reads, segregated bucket/prefix, retention policy, EXIF stripping on all uploads (§4.2).
7. **Fix wallet concurrency** (transaction + DB-level non-negative constraint) and **add idempotency keys** to every money-adjacent POST (§4.1).
8. **Add a phase that captures provider payment and contact details** — the booking flow currently displays data no phase creates.
9. **Rate-limit OTP sends** and choose an SMS provider with a cost model and a delivery-failure fallback (§5.3, §5.4).
10. **Decide double-booking**: prevent it, or explicitly document that capacity management is out of scope and design the UI to set that expectation (§3).

### 🟠 High Priority

11. Defer credits (8b) and advertising (8c) entirely past v1; reduce 8a to subscription-only (§6.1).
12. Add a background job runner to the architecture now (§4.3).
13. Add in-app account deletion — App Store blocker (§3).
14. Add block-user and report-from-chat (§3).
15. Design a cold-start Home for a near-empty catalogue (§2.2).
16. Add offline/poor-network handling, starting with the wizard's autosave (§2.3).
17. Set accessibility criteria in `030-design-system.mdc` before Phase 1 is built (§2.4).
18. Fix money's numeric type — integer laari — in the backend conventions rule (§4.4).
19. Start the trial clock at first *received booking*, not first publish (§1.6).
20. Drop the completion-count trial trigger (§1.5).
21. Move crash reporting and error tracking from Phase 21 into Phase 2/3 (§4).
22. Define what "analytics" means before selling it (§3).
23. Specify deletion and cascade semantics for listings, providers, and users (§4.6).
24. Enforce the entitlement cap at publish time, not just at draft creation (§4.7).
25. Add output encoding/CSP requirements for the admin web app (§5.2).
26. Design a provider/customer role switch and reconsider the dashboard's place in the IA (§2.1).
27. Add bank-statement CSV import with reference-code auto-matching (§6.4).
28. Derive public provider visibility from published-listing count rather than a one-way status flag (§1.7).

### 🟡 Medium Priority

29. Deep links, universal links, and a minimal web fallback page — or drop the SEO justification from §1c (§3).
30. Add payment-event notification types to Phase 19; add rejection notifications for payment submissions.
31. Search sort control and price filter.
32. Booking reschedule.
33. In-app password/email/phone change; session and device list.
34. Receipts and GST treatment.
35. Document the timezone convention and add holiday/exception handling to availability.
36. Resolve the `boosted_placement` vs `search_boost` naming collision and define their interaction (§1.10).
37. Fix billing pause to key off a provider-level flag (§1.9).
38. Add idempotency to draft creation and reconcile Phase 9 vs Phase 16 entry-point behavior (§1.11).
39. Replace hand-maintained view/booking counters with an event log and rollup (§4.5).
40. Add a stub-reconciliation checklist to Phase 20.
41. Add ToS versioning and re-acceptance.

### 🟢 Nice to Have

42. Saved searches and alerts; weekly provider performance digest; referral mechanics; provider data export; onboarding/splash; ad impression reporting for advertisers.

---

## 12. Overall Assessment

| Dimension | Score | Driving factor |
|---|---|---|
| **Architecture** | **7/10** | Genuinely strong module boundaries, response envelope, versioning, and dependency inversion. Loses points for no job runner, unaddressed concurrency on money paths, inconsistent counter strategy, and admin as an afterthought. |
| **Product design** | **5/10** | Excellent state-completeness and design-token discipline. Undercut by a core loop whose ordering doesn't match the real transaction, a customer-shaped IA that buries the paying user, and zero coverage of cold start, offline, accessibility, or retention. |
| **Scalability** | **8/10** | Over-provisioned for a ~550k-person market, which is the right direction to be wrong. Real weak points are check-on-read expiry and per-view counter writes, not throughput. |
| **Security** | **4/10** | Good conventions on paper — per-endpoint authorization, no PII in logs, Zod everywhere — comprehensively undermined by stubbed admin auth across every money endpoint, unspecified access control on financial documents, no rate limiting, and no threat model. |
| **Business viability** | **4/10** | Monetization is built before demand can exist; the trial demonstrates value its recipients can't use; there is no articulated reason to leave Facebook; and the contact gate taxes the free side to protect the paid side. |
| **Maintainability** | **7/10** | The rules/skills/subagents scaffolding is genuinely above average and will pay off. Docked for two codebases, a superseded rule file still being referenced, ten unreconciled stubs, and eight decisions delegated to the agent. |

### Top 10 issues to address first

1. Booking flow requires payment before provider commitment, and is incompatible with quote/range/hourly pricing.
2. Booking carries no amount — attestation and dispute resolution have no subject.
3. `disputed` is a terminal state; customers have no dispute path at all.
4. Providers unilaterally control whether they can ever be reviewed.
5. Admin authentication is stubbed everywhere and built nowhere, on money-granting endpoints.
6. Payment-proof images have no specified access control.
7. Wallet spending races; no idempotency on any money-adjacent write.
8. Provider payment and contact details are displayed by the booking flow and created by no phase.
9. No OTP send rate limiting, and SMS is an unchosen single point of failure for the entire transactional core.
10. Monetization (five phases) is built before the marketplace can transact.

### Top 10 improvements that would most strengthen the product

1. Restructure the booking lifecycle around provider acceptance, with contact unlock at acceptance and payment attestation after the work.
2. Cut v1 monetization to a single subscription — defer credits and ads — and redirect that effort to Search, Home, Bookings, and Messaging.
3. Start the trial when the platform delivers the provider's first booking.
4. Build a cold-start Home that looks intentional with twenty listings.
5. Make the provider experience first-class in the IA with a real role switch.
6. Add offline tolerance to the wizard and the booking flow.
7. Set accessibility standards in the design system before any screen is built.
8. Automate payment matching from bank statements via the reference code you already designed.
9. Add a real trust signal to complement self-attestation — identity verification with visible criteria — and consider making that the paid product instead of a feature bundle.
10. Add a minimal web surface so shared listings resolve and the SEO argument in §1c becomes true.

### Recommendation

**Revise before developing — do not redesign, and do not proceed as-is.**

The foundations are sound and worth building now: Phases 0 through 8, the design system, the module boundaries, and the rules/skills discipline are better than most projects have at this stage, and none of my findings undermine them.

What must change before code is written is narrower and specific: **Phase 17's lifecycle ordering, the monetization sequencing, and admin authentication.** Those three are load-bearing, and each is far cheaper to fix in a document today than in a codebase in three months.

The business findings in §6 are not blockers for building, but they are blockers for *launching well*, and they deserve an answer before Phase 8a: what makes someone leave Facebook for this, and is the paid product a subscription or a verification badge?
