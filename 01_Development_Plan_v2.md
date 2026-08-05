# RaajjePro — Development Plan (v2)

Supersedes `01_Development_Plan.md`. This revision folds in the adversarial design review and the 48 decisions resolved on 2026-08-03.

Stack unchanged:
- **Frontend:** Flutter (mobile-first)
- **Backend:** TypeScript (Node), REST, API-first, versioned (`/v1`)
- **Database:** PostgreSQL
- **Repo shape:** Monorepo, strict `frontend/`/`backend/` separation, backend organized by domain module

### What changed from v1 — read this first

1. **Booking lifecycle rebuilt around provider-published time slots.** Booking a slot removes it from availability atomically. The provider accepts the job in-app *before* the customer is asked to pay. This fixes the ordering problem and eliminates double-booking as a separate concern.
2. **Credits (old Phase 8b) and Advertising (old Phase 8c) are cut from v1.** Subscription-only monetization. Roughly 20% of the build recovered.
3. **Trial starts at the provider's first *received booking*, not first publish.**
4. **Old Phase 17a (trial ends on 3rd completed booking) is deleted entirely** — it paid providers not to mark work complete.
5. **Accessibility is a Phase 1 requirement**, not a retrofit.
6. **Soft-delete everywhere. UUIDs everywhere. Integer laari for money. Idempotency keys on money paths. A real job runner.**
7. **Admin identity is real from Phase 2**, not stubbed until never.
8. **Messaging is booking-scoped only** — this removes the pre-booking "Message" affordance from Service Preview.

---

## 1. Mockup Inventory & Coverage Map

| Screen | Status | Modules |
|---|---|---|
| Home (feed) | Exact match provided | Search & Discovery, Listings, Favorites, Provider Profiles |
| Explore (category grid) | Exact match provided | Categories |
| Login | Provided, improvable | Identity & Auth |
| Register | Provided, improvable | Identity & Auth |
| Profile (customer) | Provided, improvable | Customer Profiles, Favorites, Bookings, Notifications |
| My Services Dashboard | Exact match provided | Provider Profiles, Listings, Reporting |
| Create/Edit Service Wizard (1–7) | Exact match provided | Listings, Categories, Media, Service Areas |
| Service Preview | Exact match provided | Listings, Reviews, Provider Profiles |

### Pages with no mockup (Claude proposes, you approve, before that phase's code)

Carried over from v1:
- Bookings tab (list + detail + status timeline)
- Messages tab (conversation list + thread)
- Notifications centre
- Provider public profile
- Search results
- Category results
- Saved Services list
- Forgot Password flow
- Phone verification (OTP entry)
- Trust & Safety / Privacy & Security sub-screens

New in v2, arising from the decisions:
- **Availability & Time Slot management** (provider publishes bookable slots — Phase 9a)
- **Booking flow** (slot picker → provider-accept wait → payment prompt → confirmation)
- **Quote request flow** (request → provider quotes → customer approves → payment)
- **Role switcher** (customer ⇄ provider mode)
- **Account settings**: change password / email / phone, active sessions, data export, **account deletion**
- **Provider Billing** (subscription status, payment proof submission, invoice list)
- **Admin panel** (separate web app — payments, moderation, audit log)
- **Referral screen** (share link, credit earned)
- **Launch-mode Home** (reduced-section variant — see §2.2)

Removed from the v1 list (deferred post-v1 with credits/ads): Credit Wallet & Top-Up, Advertise-with-Us / Ad Campaign creation.

**Admin panel remains a separate internal web app**, not a Flutter screen — confirmed. Backend endpoints are identical either way.

**Provider onboarding still has no separate page** — the Create/Edit Service Wizard *is* onboarding. See §1a.

---

## 1a. Provider Lifecycle Model (revised)

The v1 design stored `lifecycleStatus` as a field flipped one-way on first publish. That field drifts: a provider who unpublishes their only listing stays `active` forever with an empty public profile — the exact dead end the gate existed to prevent.

**Revised:**

- **Public visibility is derived, not stored.** A provider is publicly visible if and only if `count(listings WHERE status = 'published' AND visibility = 'active') > 0`. Compute it in one shared query helper (`findVisibleProviders`) that Featured Providers, search, and the public profile endpoint all call. There is no stored `lifecycleStatus` to keep in sync.
- **`ProviderProfile` is still created implicitly** on the first `POST /v1/listings` by a user who has none (`getOrCreateProviderProfile`, idempotent).
- **`verificationStatus`** (`unverified` / `pending` / `verified`) remains a separate axis — identity/background check, admin-transitioned. Never conflated with visibility.
- **Idempotency:** "Become a Provider" for a user with an existing draft resumes it. `POST /v1/listings` requires a client-supplied idempotency key so a retry on a flaky connection cannot create orphan drafts.
- **Dashboard access is never gated.** A provider with only drafts reaches My Services Dashboard normally, stats at zero.

---

## 1b. Monetization Model (revised — subscription only for v1)

**Customer-facing rule unchanged:** all customer features are free indefinitely. Nothing in this section may ever gate a customer action.

**Payment for jobs is off-platform.** RaajjePro never moves money between customer and provider. Everything RaajjePro collects is a provider paying RaajjePro, via **manual bank transfer + admin confirmation**. No payment gateway in v1.

### v1 scope

| Layer | Mechanism |
|---|---|
| Free tier | 1 active listing, full search visibility (**never** paywalled), no badge, no analytics |
| Trial | Full premium access. **Starts on the provider's first booking reaching `confirmed`** — not on publish. Runs 60 calendar days. |
| Subscription (Premium) | One tier, MVR 150–200/month (**pin the exact figure before Phase 8a**). Unlocks multiple active listings, analytics dashboard + weekly digest, priority placement, and badge eligibility. |
| Referral credit | MVR 50 credit per referred user who completes a booking. Applied against subscription dues. |

### Deferred to post-v1 (explicitly, not forgotten)

- **Credit wallet & à la carte purchases** (old Phase 8b)
- **Advertising: `Advertiser`, `AdRateCard`, `AdCampaign`, sponsored slots** (old Phase 8c)

Rationale: every premium benefit derives its value from demand density that will not exist at launch. Building three monetization systems before the marketplace can transact was the largest sequencing error in v1. Keep the `PaymentSubmission` mechanism generic enough (a `purpose` enum with room to grow) that both slot back in additively later.

### Trial and subscription lifecycle

- **Warning:** notification 7 days before trial or subscription period end.
- **Expiry:** grace period of 7 days after the end date. During grace, nothing changes. After grace with no confirmed payment → downgrade to free tier.
- **Downgrade is non-destructive and reversible:** listings beyond the free-tier cap are **hidden** (`visibility: 'hidden_over_cap'`), never deleted. Badge and analytics are disabled. Any confirmed payment restores everything. **Basic discoverability of the remaining listing is never affected.**
  - *Which listings get hidden:* keep the most recently updated active listing visible; hide the rest. Provider can choose a different one from the dashboard.
- **Pause:** a provider may pause billing at any point, capped at **10 cumulative days**. When the cap is reached the pause ends automatically and the clock resumes.
  - ⚠️ **Needs your confirmation before Phase 8a:** you said "after that, trial should start again." I've written this as *the trial clock resumes where it left off*. If you meant the trial genuinely **restarts from day 0**, say so — it's a one-line difference in the plan and a meaningfully different product behaviour.
- **Trial abuse prevention:** one trial per user account. Trial eligibility is **not** tied to phone number — a provider who changes their phone keeps their remaining trial.
- **No expiry on money:** subscription simply stops charging when cancelled. Referral credits never expire.

### The manual payment mechanism

One generic `PaymentSubmission` entity serves every purpose (v1: `subscription` only; the enum stays open):

1. Provider initiates a payment intent in-app.
2. App shows RaajjePro's bank details + a generated reference code.
3. Provider uploads proof of payment and submits. Status: `pending`.
4. Admin reviews in the panel and **confirms** (grants the entitlement) or **rejects** (with a reason).
5. On rejection, the provider sees the reason and may **resubmit immediately** — no cooldown — or **appeal** for admin re-review.
6. On confirmation, a **downloadable PDF invoice** is generated.

**Nothing is granted on submission.** A `pending` submission produces entitlements identical to no payment at all. `getProviderEntitlements` reads live database state on every call and never caches.

**Reversal:** an admin can reverse a confirmed payment (mistake, bank reversal). This is an explicit endpoint with an audit-log entry, not a database edit.

**Automation:** Phase 10a includes bank-statement CSV import with auto-matching on reference code. Manual review at 200 providers is ~10 confirmations per working day forever; the reference-code design already supports matching, so use it.

**Operational SLA:** admins confirm or reject within 48 hours. Policy, not code — but document it, because the whole model depends on humans acting fast.

---

## 1c. Booking, Slots, Payment Attestation & Contact Visibility (rebuilt)

This section replaces v1's §1c entirely. The v1 flow asked customers to pay before the provider had agreed to anything, and was incompatible with `quote`, `range`, and `hourly` pricing.

### Time slots are the foundation

- Providers publish **bookable time slots** against a listing (Phase 9a). Slots derive from the listing's availability (days, business hours, duration) and can be individually added, removed, or blocked.
- **Customers only ever see slots that are currently open.** No slot picker shows an unavailable time.
- Booking a slot **reserves it atomically**. It disappears from availability for everyone else at that instant.
- **Enforced by a database constraint** — `UNIQUE (providerId, listingId, scheduledFor)` — not merely by an application check. The application cannot override it.
- **Cancellation frees the slot.** When a booking is cancelled or declined, the slot returns to the pool. The provider may re-block it from the dashboard if they no longer want it offered.

Because the provider published the slot, they have already asserted general availability for that time. The accept step below is about accepting *this specific job*, not re-confirming availability.

### Access control — graduated

| Tier | Unlocks | Enforced by |
|---|---|---|
| Guest | Browse, search, view listings and public provider profiles | No gate |
| Registered | Save/favourite | `requireAuth` |
| **Phone-verified** | **Book, and message within a booking** | `requirePhoneVerified` |
| Visible provider | Appears publicly, receives bookings | Derived published-listing count (§1a) |
| Entitled provider | Extra listings, badge, analytics, priority | `getProviderEntitlements` (§1b) |

Enforcement is **server-side on every relevant endpoint**. A guest may see a "Book Now" button — tapping it routes to login/verification. The backend rejects regardless of what the client sends.

### Booking status machine

```
                    ┌──────────► declined (provider, from requested)
                    │
requested ──────────┴──► accepted ──► payment_claimed ──► confirmed ──► completed
   │                        │              │                  │
   │                        │              └──► disputed ◄─────┘ (either party)
   │                        │                      │
   └──► cancelled ◄─────────┘                      └──► dispute_resolved (admin)
        (customer, pre-payment)
```

**Quote-priced listings** insert two extra states before `accepted`:

```
requested ──► awaiting_quote ──► quote_offered ──► accepted (customer approves the quote)
```

### The flow, step by step

1. **Customer picks an open slot** and submits booking details. Status `requested`. The slot is reserved immediately.
2. **Provider is prompted in-app to accept.** This prompt shows the job details and **no contact information for either party**, and **no chat is available at this stage**. Accept or decline only.
   - For quote-priced listings, the provider instead submits a quote (`quote_offered`), which the customer approves or rejects.
3. **On acceptance** the booking carries an **`agreedAmount`** — from the listing price for fixed pricing, or from the accepted quote. Status `accepted`.
   - No booking may leave `requested`/`quote_offered` without an `agreedAmount`. Every downstream attestation references a real number.
4. **Customer is prompted to pay**, off-platform, directly to the provider, using the payment details the provider registered (Phase 5). Copy states plainly that RaajjePro is not handling this money.
5. **Customer taps "I've Paid"** — a self-attestation, no proof upload. Status `payment_claimed`.
6. **Provider confirms or disputes receipt.** Confirm → `confirmed`. Dispute → `disputed`.
   - **7-day grace:** if the provider neither confirms nor disputes within 7 days, the booking **auto-advances to `confirmed`**. This prevents indefinite limbo and removes the provider's ability to stall.
7. **`confirmed` is the contact-info unlock.** See below.
8. **Completion.** The provider marks the job complete. If they don't, the booking **auto-completes 7 days after the scheduled date**. This matters: review eligibility is gated on `completed`, and without auto-completion a provider could permanently block reviews of their own work by never pressing the button.
9. **Review becomes postable** once `completed`. One review per booking.

### Disputes

- **Either party may dispute** — provider ("payment not received") or customer ("provider didn't show", "I paid and they say I didn't"). v1's provider-only design was asymmetric.
- **A late dispute is accepted** even after `completed`. The booking stays completed; the dispute is queued.
- **`disputed` is not terminal.** An admin resolves it to `dispute_resolved` with an outcome recorded. v1 had no exit from this state, which stranded any customer hit by a mistaken dispute.
- Disputes feed the Phase 22 moderation queue with both parties' history together — RaajjePro can see patterns and act proportionately, but cannot adjudicate an off-platform payment and must never present itself as doing so.
- **Decline ≠ dispute.** Separate endpoints, separate statuses, visually distinct in the UI.

### Contact visibility — symmetric

Neither party sees the other's phone, WhatsApp, or Viber handle until the booking reaches **`confirmed`**.

- Before `accepted`: nothing. The accept prompt is deliberately contact-free and chat-free.
- Between `accepted` and `confirmed`: the provider sees the customer's **name only**, via booking context.
- At `confirmed`: both parties see each other's contact details, via the single booking-scoped endpoint.

Implement the check as a **live query** — "does a `confirmed` booking exist between these two users" — never a cached flag. This is the only endpoint in the system that returns contact details; no listing, provider-profile, or search response may ever include them.

### Honest framing is mandatory

Never "Payment Verified". Never a lock or verified-checkmark on this flow. Use "Provider confirmed receipt". RaajjePro has no visibility into the actual transaction, and the UI must not imply otherwise.

### What this does and does not prevent

The slot system plus contact gating meaningfully raises the bar against customers bypassing the platform. It does **not** prevent a provider from publishing their phone number in a listing description, an FAQ answer, or a gallery image — and the provider is the party motivated to do so. Treat that as a moderation problem (Phase 22), scan listing free-text for contact patterns, and do not assume the gate is airtight.

---

## 2. Architecture Decisions

| Decision | Choice | Note |
|---|---|---|
| Backend framework | Fastify (TypeScript) | unchanged |
| ORM | Prisma | unchanged |
| Database | PostgreSQL | unchanged |
| Auth | JWT access + refresh rotation | unchanged |
| Validation | Zod | unchanged |
| State management | Riverpod | unchanged |
| File storage | S3-compatible | **payment proofs in a separate private bucket/prefix** |
| **Primary keys** | **UUID for every entity** | removes the enumeration surface entirely |
| **Money** | **Integer laari (MVR × 100)** | never float, never decimal-as-string; one type across every price, amount, and balance |
| **Deletion** | **Soft-delete everywhere** | `visibility`/`status` field; nothing is ever hard-deleted |
| **Job runner** | **pg_cron (or equivalent)** | v1 had none, yet relied on time-based expiry |
| **Idempotency** | **Client-supplied key on every money-adjacent and creation POST** | server dedupes on `(userId, operation, key)` |
| **Rate limiting** | **Global + per-endpoint tiers** | stricter on auth, OTP, and payment endpoints |
| **Push delivery** | **FCM + APNs** | required infrastructure, not optional |

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
  - `Semantics` labels on every control and every icon-only button
  - `MediaQuery.textScaler` respected — no fixed-height text containers
  - **every motion primitive has a reduced-motion path** honouring the OS setting
- Component gallery route rendering everything with sample data
**Done when:** the gallery renders every widget; a11y criteria verified with a screen reader and at 200% text scale; `flutter analyze` clean.

### Phase 2 — Backend Core Infrastructure
- Fastify bootstrap, `/v1` prefix
- Global error handling (validation / auth / authz / business-rule / conflict / not-found / infra / unexpected); never leak internals
- Structured logging with correlation IDs; no PII in logs
- Typed config module, fail-fast on missing vars
- Standard response envelope (success + error shapes)
- Prisma setup, migration workflow, **UUID + soft-delete + integer-money conventions encoded in the base schema patterns**
- `GET /v1/health`
- **Rate limiting:** global tiers (unauthenticated per IP, authenticated per user) plus a per-endpoint override mechanism
- **Idempotency middleware:** reusable, keyed on `(userId, operation, clientKey)`
- **Admin identity model:** admin users, a single `admin` role for v1, login, session. Not a stub. MFA and network segregation are documented as post-v1.
- **Audit log:** every admin action records admin ID, timestamp, action, target, and reason. Queryable by date / admin / action type.
**Done when:** `/v1/health` returns 200; a malformed request returns the standard envelope; a repeated idempotent POST returns the original result; rate limits trigger correctly; an admin action appears in the queryable audit log.

### Phase 3 — Identity & Authentication
- Register, login, JWT access + refresh rotation, logout, `me`, password reset
- Social auth: provider-agnostic interface with stubs (Facebook/Google/Viber)
- **Phone verification:** OTP send + verify, `phoneVerified` flag, `requirePhoneVerified` guard (stricter than `requireAuth`, distinct `PHONE_NOT_VERIFIED` error code)
  - **SMS provider chosen and pinned before this phase starts**, with a cost model and a delivery-failure fallback. Sender-ID registration lead time confirmed.
  - **OTP send rate limit: 3 per phone number per 15 minutes.** Verification attempts limited separately.
- **Account settings (backend + screens):**
  - change password, change email, change phone (each re-verified)
  - **active session list + revoke** — per-device refresh tokens so revoking one device doesn't log out the others
  - **data export** — `GET /v1/users/me/data-export` returns the user's own data as JSON
  - **account deletion** — App Store requirement. Anonymises all authored content: name/email/phone replaced with a placeholder, listings and reviews preserved so provider rating aggregates stay intact. Soft-delete, not purge.
- Frontend: Login, Register (pixel-match), OTP verification screen (propose design first), account settings sub-screens (propose first)
**Done when:** full register → verify → logout → login cycle works; an unverified user browses freely but is rejected by `requirePhoneVerified`; OTP rate limit verified; a deleted account's reviews remain with anonymised attribution; export returns complete data.

### Phase 3b — Forgot Password Flow *(propose design first)*
Unchanged from v1. Reset-token issuance, expiry, consumption; invalidates all refresh tokens on success.

### Phase 4 — Categories Module
Unchanged from v1. Category CRUD (admin-only writes, now against **real** admin auth from Phase 2), seed 12 categories, Explore screen driven entirely by the live endpoint.
**Done when:** a 13th category added via API appears in Explore with no rebuild.

### Phase 5 — Provider Profiles *(backend only)*
- `ProviderProfile`: userId, businessName, bio, yearsOfExperience, `verificationStatus`, createdAt
- **`jobsCompletedCount` derived from the booking event log**, never a hand-maintained counter
- **Contact details — new, and load-bearing:** `phone`, `whatsappHandle`, `viberHandle`. v1 returned these from Phase 17's endpoint without any phase ever creating them.
- **Payment details — new, and load-bearing:** bank name, account name, account number, and/or other transfer instructions. v1's booking flow displayed "the provider's payment details" that no phase collected.
  - Treat these as sensitive: excluded from every response except the booking-scoped contact endpoint, and from all logs.
- **`acceptingNewCustomers` lives here, at provider level** — moved off the Listing entity. One toggle gates all of a provider's listings, and billing pause keys off it coherently.
- `getOrCreateProviderProfile(userId)` — idempotent
- `findVisibleProviders(...)` — the single shared gate, filtering on derived published-listing count (§1a)
**Done when:** `getOrCreateProviderProfile` called twice returns one row; `findVisibleProviders` excludes a provider whose only listing is a draft, and *includes* them the moment one is published, with no stored status field involved.

### Phase 6 — Customer Profile Module
- `GET /v1/users/me/profile-summary` — one call for the Profile screen
- `PATCH /v1/users/me`
- Frontend: Profile screen (pixel-match), five rows navigating to sub-screens
- **Role switcher:** an explicit customer ⇄ provider mode control. Providers are the only paying users; their workspace must not be buried. Propose the switcher's placement and the resulting provider-mode IA before implementing — this is the one navigation change that departs from the original mockups.
**Done when:** Profile reflects live data; every row navigates; switching to provider mode reaches My Services Dashboard in one action.

### Phase 7 — Service Areas & Location Module
Unchanged from v1. Island reference data, `ProviderServiceArea`, searchable island picker as a reusable widget, header location bottom sheet.

### Phase 8 — Service Listings: Backend Domain
- Fields matching all 7 wizard steps
- **Pricing is per-listing** (each listing carries its own model and rates) — confirmed, not per-provider
- **`acceptingNewCustomers` removed from the Listing entity** — now provider-level (Phase 5)
- Draft-save accepting partial/empty payloads; implicitly creates the Provider Profile; **requires an idempotency key**
- Publish endpoint: full required-field validation returning a structured missing-field list
  - **Also enforces the entitlement cap.** v1 checked the cap only at draft creation, so drafts made during a trial could all be published after downgrade.
- Media upload via presigned URL — **server-side content-type and size validation, EXIF stripping on every image**
- Soft-delete only; document the cascade rules for a listing with bookings, reviews, or reserved slots against it
- **View and booking counts come from an event log with periodic rollup**, not per-request counter writes
**Done when:** a listing saves empty, patches per step, publishes only when complete and within cap; a soft-deleted listing disappears from public queries while its bookings and reviews remain intact.

### Phase 8a — Subscription & Trial *(backend only)*
Reduced from v1's three-phase monetization tier to subscription only.
- Generic `PaymentSubmission`: payerId, `purpose` (v1: `subscription`; enum stays open), amount (laari), proofUrl, referenceCode, status, submittedAt, reviewedBy, reviewedAt, rejectionReason
- `ProviderSubscription`: providerId, tier, status (`trialing`/`active`/`free`/`paused`/`expired`), trialStartedAt, trialEndsAt, currentPeriodEnd, pausedAt, cumulativePausedDays
- **Trial starts on the provider's first booking reaching `confirmed`** (Phase 17 hook) — not on publish
- **Pause:** capped at 10 cumulative days, enforced server-side, auto-ends at the cap *(see the flag in §1b — confirm resume-vs-restart before building)*
- **Scheduled jobs** (Phase 0's runner, not check-on-read): 7-day-out warning, expiry → grace, grace → downgrade
- **Downgrade:** hides over-cap listings (`hidden_over_cap`), disables badge and analytics, never deletes, fully reversible
- `getProviderEntitlements(providerId)` — the single source of tier truth, **live DB read every call**, no caching, nothing granted on a `pending` submission
- **Referral:** referral code per user; MVR 50 credit when a referred user completes a booking; credit offsets subscription dues
- Endpoints: upgrade-request, subscription status, pause/resume
- Admin: confirm / reject / **reverse** a submission, plus the pending list. All audit-logged.
- **Idempotency key required** on every submission-creating call
- **PDF invoice** generated on confirmation
**Done when:** a trial starts on first confirmed booking and not before; the warning, expiry, and downgrade jobs fire on schedule; a `pending` submission grants exactly nothing; a confirmed payment produces a downloadable invoice; a reversal restores prior state and is audit-logged.

### Phase 9 — Create/Edit Service Wizard: Frontend
- Steps 1–7 pixel-matched, wired to Phase 8
- Step navigation never blocked; Review always reachable
- **Progress framing shows "N required fields left to publish"** alongside (or instead of) "Step 1 of 7" — five fields are actually required, and leading with the step count overstates the commitment
- **Offline resilience:** every step's autosave PATCH is queued locally on failure and replayed on reconnect. **Step navigation is blocked until the current step's data has persisted** — the wizard is the highest-value conversion flow in the app and must not silently lose work on a weak atoll connection.
- Over-cap new-draft attempt shows an upgrade prompt, not a generic error
**Done when:** a service can be created end-to-end; the app can be killed mid-wizard and resumed; airplane-mode transitions queue and replay correctly; publish is blocked with the exact missing-field list.

### Phase 9a — Availability & Time Slots *(new — the foundation of booking)*
No mockup exists. Propose the provider-side slot management UI and the customer-side slot picker before implementing.

- **Backend:** `TimeSlot` (providerId, listingId, startsAt, endsAt, status `open`/`reserved`/`blocked`), generated from the listing's availability rules (days, business hours, service duration) with individual override
  - **`UNIQUE (providerId, listingId, startsAt)` constraint** — the hard guarantee against double-booking
  - Slot reservation happens inside the booking-creation transaction; a race resolves to exactly one winner
  - Cancellation or decline returns the slot to `open`
  - Holiday and exception handling: providers can block ranges (Ramadan hours, travel, public holidays)
  - Endpoints: generate/regenerate slots, block/unblock, list open slots for a listing
- **Frontend (provider):** slot management in the dashboard — see generated slots, block individual ones, block a date range
- **Frontend (customer):** slot picker showing **only `open` slots**. Never display an unavailable time.
- **Timezone:** all times stored UTC, presented in Maldives time (UTC+5). Document the convention; a single-timezone market makes this simple, but boundary days still need a stated rule.
**Done when:** two concurrent booking attempts on the same slot resolve to exactly one success and one clear "no longer available" error, verified under real concurrency; a cancelled booking's slot reappears; a blocked range removes those slots from the picker.

### Phase 10 — My Services Dashboard
- Stats row, filter pills, list/grid toggle, service cards with context menu, live toggle
- Reachable in one action from the Phase 6 role switcher
- **Slot management entry point** (Phase 9a)
- Renders correctly for a provider with only drafts
- Badge indicator reflects real entitlement state — **badge requires both `verificationStatus: verified` AND an active premium subscription**; if the subscription lapses the badge hides while the verification remains
**Done when:** every context-menu action performs a real mutation with no manual refresh; a drafts-only provider sees a correct zero state; the badge appears and disappears with subscription state.

### Phase 10a — Provider Billing UI & Admin Panel

**Part 1 — Provider Billing (Flutter).** No mockups; propose first.
- Subscription status: trial countdown / renewal date / free-tier state, upgrade CTA
- Payment Proof Submission: bank details, reference code, upload, submit — built once, parameterised by purpose
- Submitted state shows "pending admin confirmation" with no implication of instant activation
- Rejection shows the reason, with **immediate resubmit** and **appeal** actions
- **Invoice list** with PDF download per confirmed payment
- Referral screen: share link, referred-user count, credit earned

**Part 2 — Admin Panel (separate internal web app).** Propose the stack before building; optimise for low effort.
- Pending `PaymentSubmission` list with proof image, submitter, amount, reference code
- Confirm / reject (reason required) / **reverse**, all audit-logged
- **Bank-statement CSV import with reference-code auto-matching** — proposes matches for one-click confirmation. Manual review does not scale to monthly renewals across hundreds of providers.
- Audit log viewer (Phase 2)
- **Security, mandatory:** this app renders user-authored text (listing descriptions, review bodies) and is the tool that approves money. A malicious provider can plant a script payload in a description and report their own listing to guarantee an admin views it. Requires **output encoding on all user content and a Content-Security-Policy header.** Not optional.
- Real admin auth from Phase 2; never publicly reachable without credentials
**Done when:** a provider submits with proof and sees pending; an admin confirms from the panel and the entitlement activates; a rejection surfaces its reason with working resubmit and appeal; CSV import correctly proposes matches; a stored `<script>` payload in a listing description renders inert in the admin view.

### Phase 11 — Reviews & Ratings *(backend)*
- `Review` tied to a **`completed`** booking. One review per booking, enforced.
- Rating aggregation per listing and per provider; star breakdown
- **Auto-completion (Phase 17) is what makes this safe.** Gating reviews on completion is correct *only* because a provider can no longer block completion indefinitely.
- Soft-delete; a hidden review is excluded from aggregates
**Done when:** posting a review updates the aggregate; a second review on the same booking is rejected; hiding a review recomputes the aggregate.

### Phase 12 — Service Preview (Public Listing Page)
- `GET /v1/listings/:id/public` and `GET /v1/providers/:id/public-summary`
- **Neither response ever contains contact or payment details.** Not "for now", not behind a flag.
- Frontend: hero with overlay controls, provider identity badge, About / Reviews / Provider tabs, sticky footer
- **Book Now** routes into the Phase 9a slot picker; unverified users route to phone verification first
- **The pre-booking "Message" button is removed.** Messaging is booking-scoped only (§Phase 18) — there is no conversation to open before a booking exists. Replace it with a "Report" affordance in the overlay controls (Phase 22) and let the About tab carry any pre-sales information the provider wants to publish.
- **Provider response-time metric displayed** (Phase 19 computes it) — a real trust signal
**Done when:** live data renders end-to-end; the Edit control appears only for the owner; the raw API response contains no contact or payment data under any circumstance.

### Phase 13 — Provider Public Profile *(propose design first)*
- Backend reuses `findVisibleProviders` (§1a). Returns not-found for a provider with no published listings, even by direct id.
- Same contact/payment exclusion as Phase 12
- Frontend: header, stats grid, listings grid, response-time metric, not-found state
**Done when:** renders for a visible provider; returns a proper not-found state for a drafts-only provider's id; no contact data in the response regardless of viewer.

### Phase 14 — Favorites (Saved Services)
Unchanged from v1. Save/unsave endpoints, saved list, heart toggle wired everywhere with optimistic update and rollback, Saved Services screen (propose first).

### Phase 15 — Search & Discovery
- Search endpoint with filters, sort, pagination, appropriate indexes
- **Sort control and price-range filter added** — v1 had four fixed chips and no sort, which is thin for the primary discovery mechanism
- **Priority placement** for premium subscribers affects ordering *within* the genuinely relevant result set, never membership in it
- **Any paid influence on ordering carries a visible "Sponsored" label.** No unlabelled paid placement.
- **No visibility difference between verified and unverified providers** in baseline search. Verification affects the badge, not findability.
- Frontend: results page (propose first), filter/sort wiring
**Done when:** results are correct, paginated, and filtered; priority placement never surfaces an irrelevant listing; every boosted result is labelled.

### Phase 16 — Home Feed
- Section endpoints: popular-near-you, featured-providers (via `findVisibleProviders`), popular-this-week, nearby, recently-viewed
- **Launch mode, mandatory:** below a catalogue-size threshold, Home collapses to **two sections plus the category grid**. The full nine-section layout unlocks above the threshold. Nine rows over twenty listings shows the same services repeatedly and reads as an abandoned product. Propose the launch-mode layout and the threshold before implementing.
- **Deep links / web fallback:** listings, provider profiles, and the referral link resolve via real URLs with universal links / app links and a minimal web fallback page. v1 justified open guest browsing partly on SEO while having no web surface to index, and shipped a Share button with nothing to share.
- Referral entry point
- "Become a Provider" routes into the wizard, resuming an existing draft if one exists
**Done when:** every section shows live, correctly-empty, or correctly-loading state; launch mode renders convincingly against a twenty-listing seed; a shared listing URL opens the app when installed and the fallback page when not.

### Phase 17 — Bookings Module
The largest phase, and the one v1 got wrong. No mockups — propose each frontend piece before implementing.

**Backend:**
1. `Booking`: listingId, customerId, providerId, timeSlotId, status (per §1c), **`agreedAmount` (integer laari)**, quotedAmount, paymentClaimedAt, paymentAttestedAt, completedAt, statusHistory
2. `POST /v1/listings/:id/bookings` — reserves the slot inside the same transaction; `requirePhoneVerified`; idempotency key required
3. `PATCH /v1/bookings/:id/accept` — provider accepts; sets `agreedAmount`; **no contact info and no chat exposed at this point**
4. `PATCH /v1/bookings/:id/quote` / `/approve-quote` — the quote-pricing path
5. `PATCH /v1/bookings/:id/decline` — provider; frees the slot; distinct from dispute
6. `PATCH /v1/bookings/:id/claim-payment` — customer self-attestation
7. `PATCH /v1/bookings/:id/confirm-payment-received` — provider; → `confirmed`; **the contact-info unlock**; **fires the Phase 8a trial-start hook on the provider's first confirmed booking**
8. `PATCH /v1/bookings/:id/dispute` — **either party**; → `disputed`; files a Report (Phase 22)
9. `PATCH /v1/bookings/:id/resolve-dispute` — **admin**; → `dispute_resolved` with a recorded outcome
10. `PATCH /v1/bookings/:id/complete` — provider; → `completed`; opens review eligibility
11. `PATCH /v1/bookings/:id/cancel` — customer, pre-payment; frees the slot
12. `PATCH /v1/bookings/:id/reschedule` — move to another open slot; frees the old one atomically
13. `GET /v1/users/me/bookings?role=&status=`
14. `GET /v1/bookings/:id/contact-info` — **the only endpoint returning contact details**, both directions, only on a `confirmed` booking between those two parties
15. **Scheduled jobs:** auto-confirm 7 days after `payment_claimed`; auto-complete 7 days after the scheduled date
16. Booking events feed the listing/provider aggregate rollups

**Frontend:**
1. Booking flow: slot picker (open slots only) → details → submit → "waiting for provider to accept"
2. Provider accept prompt: job details, **no contact info, no chat**, accept / decline (or submit quote)
3. Payment prompt: provider's payment details, `agreedAmount` shown explicitly, honest copy, "I've Paid"
4. Provider receipt prompt: three visually distinct actions — "Payment Received", "Payment Not Received", "Decline Booking"
5. On `confirmed`: contact details surfaced to both parties as an unlock moment
6. Bookings tab: status filter pills, detail view, and a **customer- and provider-visible status timeline** showing when each transition happened and who caused it — this reduces support load and makes the attestation flow legible
7. Nine visually distinct status badges
**Done when:** the full lifecycle works both ways; concurrent bookings on one slot resolve to one winner; a dispute from either side queues correctly and does not unlock contact info; an unresolved `payment_claimed` auto-confirms at day 7; an unmarked job auto-completes at day 7 and its review becomes postable; reschedule frees the old slot atomically; the contact endpoint returns data only for a genuinely confirmed pair.

### Phase 18 — Messaging Module
- **Booking-scoped only.** A conversation exists only in the context of an existing booking. There is no pre-booking messaging — this reduces spam and simplifies moderation, and it is why Phase 12's pre-booking Message button was removed.
- **No chat before `accepted`.** The accept prompt stays contact-free and chat-free.
- `requirePhoneVerified` on conversation creation and every message
- **Block user** — blocking prevents further messages and hides the blocker's contact details
- **Report from within a conversation** (Phase 22) — harassment happens in chat, and v1's report affordances were all outside it
- Contact-pattern detection on outgoing messages: **a soft inline nudge, never a block or redaction.** False positives cost more than the leakage they prevent.
- Frontend: conversation list, thread view (propose both first)
**Done when:** two verified accounts exchange messages within a booking; an unverified account is routed to verification rather than shown a raw error; blocking stops delivery both ways; a report from a thread reaches the moderation queue.

### Phase 19 — Notifications Module
- `Notification`: userId, type, payload, readAt, createdAt
- **Push (FCM/APNs) is required infrastructure and is enabled by default — users cannot disable it.** Provider booking-acceptance is load-bearing on real-time delivery; the whole flow stalls without it.
- **Email and in-app inbox are opt-in**, layered on top.
- **Types must include the payment and booking events v1 omitted:** booking_requested, booking_accepted, booking_declined, payment_claimed, payment_confirmed, payment_disputed, dispute_resolved, booking_completed, booking_auto_completed, **payment_submission_confirmed**, **payment_submission_rejected**, trial_ending_7d, subscription_ending_7d, downgraded_to_free, new_message, new_review, referral_credited
- **Weekly provider digest email** (opt-in): views, bookings, reviews, top-performing listings — this is the concrete deliverable behind the "analytics" you're selling with the subscription
- **Provider analytics dashboard** — defined here rather than left as an undefined premium benefit: per-listing views, booking counts, conversion rate, rating trend, response time
- **Response-time metric** computed from booking-acceptance and message history; surfaced publicly on listings and provider profiles
- Notification centre screen (propose first); live badge counts
**Done when:** each event type fires a correctly-typed, correctly-deep-linked notification; push arrives on a real device within seconds; the digest sends on schedule to opt-in providers only; the analytics dashboard renders real data.

### Phase 20 — Hardening, QA & Launch Readiness
- Contract tests across every module; E2E on the critical path (register → verify → publish → slot published → customer books → provider accepts → payment attested → confirmed → completed → review)
- **Concurrency tests specifically:** simultaneous slot booking, simultaneous admin confirmation of one submission, repeated idempotent POSTs
- Performance: payload sizes, pagination, N+1 audit
- Security: authorization on **every** endpoint including reads, rate-limit verification, admin auth, no sensitive data in logs
- **Stub reconciliation sweep** — enumerate every deferred stub from earlier phases and confirm each is now real or consciously deferred with a written reason. v1 accumulated roughly ten with no sweep.
- **Decision reconciliation sweep** — every "your call, document it" left to the agent, confirmed and recorded
- State audit against every screen: loading / empty / error / populated
- **Accessibility audit** against Phase 1's criteria across all screens
- Known-limitations document
**Done when:** suite passes; concurrency tests hold; the stub and decision registers are complete; the a11y audit passes.

### Phase 21 — Observability & Crash Reporting
- Backend APM/error tracking wired into Phase 2 logging
- Flutter crash reporting
- Uptime monitoring on `/v1/health` and on the payment-submission endpoints specifically
- `ProductEvent` log: draft_created, listing_published, slot_published, booking_requested, booking_accepted, payment_claimed, booking_confirmed, booking_completed, trial_started, trial_converted, trial_expired, search_performed, referral_completed
- **Note on sequencing:** crash reporting genuinely wants to exist from Phase 3 onward, not Phase 21. Consider pulling the Sentry/Crashlytics integration forward and leaving only the ProductEvent log and uptime monitoring here.
**Done when:** deliberate backend and Flutter exceptions both surface within minutes; a broken payment endpoint triggers an alert; every event type is confirmed logging.

### Phase 22 — Content Moderation & Reporting
- `Report`: reporterId, targetType (`listing`/`review`/`user`/`booking`/`message`/`photo`), targetId, reason enum, status, reviewedBy, reviewedAt, **resolution reason**
- Booking disputes (Phase 17) file here automatically, with both parties' history shown together
- Admin queue extends Phase 10a's panel and reuses its auth and audit log
- **Actioning hides, never deletes** — reversible via the soft-delete visibility flag
- **Hidden content stays visible to its owner**, who sees the category and reason and can appeal. Everyone else cannot find it.
- **Moderation transparency:** the user is told the category and reason ("misleading pricing", "spam", "inappropriate content") with an appeal path
- Review anti-spam: rate limit, and flag implausibly-fast reviews for a human look rather than auto-rejecting
- **Listing free-text scanning for contact patterns** — the provider-side leakage vector the contact gate does not close
- Report affordances: Service Preview overlay, review cards, provider profile, **conversation threads**, and listing photos
**Done when:** each report type reaches the queue with enough context to act; actioning hides content from everyone but its owner; the owner sees the reason and can appeal; a Phase 17 dispute appears with both parties' history.

### Phase 23 — Legal, Compliance & App Store Readiness
- **Not primarily a coding task.** Cursor builds screens and section structure with clearly-marked placeholders; it does **not** write binding legal language.
- **Unified Terms of Service** (customers and providers) + **separate Provider Agreement** covering subscription, trial, cancellation, the manual bank-transfer process, and dispute handling
- Privacy Policy
- Provider Agreement linked from the Payment Proof Submission flow, where it is most relevant
- **Identity verification flow** — the admin-side process behind `verificationStatus`, which the badge now depends on. Define what evidence is required and who reviews it.
- **App Store account deletion: already built in Phase 3.** Verify it meets the current requirement.
- **Research, don't code — resolve before Phase 8a goes deep:**
  - App Store and Play policy on a manual-bank-transfer subscription. Apple's IAP rules have an exception path for physical goods and services; whether this qualifies needs a real determination from someone who has been through review, because a negative answer changes Phase 8a's data model.
  - **Current status of Maldivian personal-data-protection legislation.** Do not assume nothing applies. Document what does.
  - **Whether referral credit constitutes stored value under Maldives Monetary Authority rules.** This is why credits were deferred, but referral credit reopens a smaller version of the same question.
  - **GST registration and invoicing obligations** on subscription revenue.
- Data-protection findings written to `docs/data-protection-review.md` in the repo, not left in a chat
**Done when:** the legal screens exist with placeholder clearly distinguished from final; the four research questions have written answers; nothing invented binding language on its own authority.

### Phase 24 — Staging Environment & Deployment Hardening
- Staging fully separate from production, with date/data manipulation for testing trial expiry, grace periods, pause caps, and slot boundaries
- Secrets into a real secrets manager; rotation process **and cadence** documented
- CI extended to real deploy automation with a tested rollback path
- Automated backups **plus a performed restore drill**, with RPO/RTO targets stated — v1 ran a drill against no objective
- Support contact path in-app (WhatsApp/Viber link or email)
**Done when:** a trial expiry and a slot-boundary case can be simulated in staging; a secret rotates without a deploy; the restore drill is done and timed against a stated target.

---

## 4. Post-v1 Backlog (deliberate, not forgotten)

- **Credit wallet & à la carte purchases** (boosts, extra slots, extra gallery) — old Phase 8b
- **Advertising module** — advertisers, rate cards, campaigns, sponsored placements — old Phase 8c. Requires audience first, plus impression tracking and advertiser reporting, neither of which v1 scoped.
- **Dhivehi / Thaana localisation with RTL.** Note: Plus Jakarta Sans and Inter carry no Thaana coverage, so this needs a second font stack — a Phase 1 typography consequence worth knowing now even though the work is deferred.
- Admin role granularity and MFA; admin network segregation
- Full analytics platform on top of Phase 21's ProductEvent log
- Automated image moderation
- Saved searches and alerts
- Real social auth (Facebook / Google / Viber)

---

## 5. Sequencing Notes

- Phases 0–2 are strictly linear.
- **Phase 9a (Time Slots) is a hard prerequisite for Phase 17** and is new — do not let it get absorbed into Phase 17, which is already the largest phase in the plan.
- **Phase 19 (Notifications) is effectively a prerequisite for Phase 17's provider-accept prompt.** v1 placed notifications two phases after the flow that depends on them. Either build push delivery early or accept that Phase 17 is untestable end-to-end until 19 lands — the accept prompt is the flow's load-bearing moment.
- **Phase 8a's trial hook fires from Phase 17**, not Phase 8. The trial now starts on first confirmed booking, so Phase 8a ships with the hook point defined and Phase 17 wires it.
- Phase 17 and Phase 22 retain a soft circular reference (disputes file Reports). Build 17 first with the Report insert minimal, then 22 makes the queue real.
- **Pin before Phase 8a:** the exact subscription price, the billing period length, and the pause resume-vs-restart question flagged in §1b.
- **Pin before Phase 3:** the SMS provider, its cost model, and sender-ID lead time. Phone verification gates both booking and messaging, so SMS is a single point of failure for the entire transactional core.
- **Resolve before Phase 8a goes deep:** Phase 23's App Store subscription question. A negative answer forces a data-model change.
- Phases 21, 22, and 24 have no dependency on one another.

---

## 6. Open Questions Requiring Your Decision

1. **Pause semantics** — after the 10-day cap, does the trial clock *resume* (my reading) or *restart from zero*? §1b.
2. **Exact subscription price** within MVR 150–200.
3. **Billing period length** — calendar month assumed; confirm.
4. **Catalogue threshold** at which Home switches from launch mode to the full layout.
5. **Slot duration model** — fixed per listing, or provider-configurable per slot? Phase 9a assumes per-listing.
6. **Identity verification evidence** — what does a provider submit to reach `verified`, and who reviews it? The badge now depends on this, so it is no longer a background concern.

---

## 7. Honest Assessment of What This Plan Still Doesn't Solve

Two things worth keeping in view, because no amount of planning detail addresses them:

**Provider-side leakage remains open.** The slot system and symmetric contact gating raise the bar considerably against customers bypassing the platform. They do not stop a provider from putting their number in a listing description. Phase 22's free-text scanning helps, obfuscation defeats it, and the provider is the party with the incentive. Treat the gate as friction, not enforcement.

**The competitive question is unanswered.** Nothing in this plan establishes why a Maldivian provider or customer leaves Facebook groups and Viber — free, universal, and zero-friction — for this. The plan's trust mechanism is honestly labelled as self-attestation rather than verification, and its discovery advantage needs catalogue density that will take time to build. The contact gate, necessarily, adds friction to the free side of the market to protect monetisation on the paid side. That is a real strategic risk, and it is a positioning and go-to-market problem rather than a development one. It deserves an answer before Phase 8a, not after launch.
