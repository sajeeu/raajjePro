# RaajjePro

Mobile-first, API-first local services marketplace for the Maldives. Flutter app (customer + provider) · TypeScript/Fastify/Prisma/PostgreSQL backend · separate React admin web app.

**Nothing is built yet.** This repository currently holds the specification the build will follow.

## The one document that matters

`01_Development_Plan_v5.md`, at **revision 5.7**. It is the single source of truth for every product decision, and it is standalone. **Read §0.0 first — it is a precedence rule**: where §0.1–0.3 conflict with a later section, the later section wins.

Do not restate the plan's content elsewhere. Cite it. Seventeen review rounds have shown that every copy of a decision eventually drifts from it — that failure has occurred five times, and each time the plan was right and a derived copy was wrong.

## Building a phase

Phases are slash commands: `/phase-0`, `/phase-3`, `/phase-17-1`. Each one names the plan sections it builds from and its Definition of Done. Work top to bottom; do not start phase N+1 until phase N's Done-when is met.

Where a command says a screen has no mockup, propose the design and get approval before writing implementation code.

## archive/ — never read as current

`archive/` holds superseded specifications and the Cursor-era build artifacts, kept for provenance only. **Never treat anything in `archive/` as current, and never cite it.** `01_Development_Plan_v4.md` in particular asserts a contact-info endpoint that was deleted, SMS OTP, a binary verified badge and a pinned global subscription price — none of which exist. If a question seems answerable only from an archived file, the answer is that the plan does not specify it: say so rather than filling the gap.

---

RaajjePro is a mobile-first, API-first Local Service Marketplace for the Maldives.
Frontend: Flutter. Backend: TypeScript (Fastify + Prisma + PostgreSQL). REST, versioned under /v1.
Full specification: `01_Development_Plan_v5.md` at revision 5.4. If any instruction here appears to conflict with that document, the document wins — flag the conflict rather than picking silently. Within that document, §0.0 is a precedence rule: where §0.1–0.3 conflict with a later section, the later section wins.

Non-negotiable architectural invariants — never violate these even if a prompt doesn't restate them:

1. Provider Profile and Service Listing are distinct domain entities. Never merge provider identity fields into a Listing, and never merge listing fields into a User or Provider Profile.

1a. PROVIDER ONBOARDING IS A REAL FLOW (Phase 6a). Older documentation stated there was no standalone "Become a Provider" screen and that the Create/Edit Service Wizard *was* onboarding. That is obsolete — Phase 6a is a 2–3 screen flow collecting phone, verified email and payment details, sequenced BEFORE the wizard, and it hands off into a fresh draft.
   PUBLIC VISIBILITY IS DERIVED, NEVER STORED: a provider is visible if and only if `count(listings WHERE status='published' AND visibility='active') > 0` AND the provider is not suspended, computed by ONE shared query helper (`findVisibleProviders`) that every consumer — search, Featured Providers, public profile — calls. There is no `lifecycleStatus` field anywhere in this schema; if you see one referenced in older documentation or existing code, it is obsolete and should be flagged for removal, not extended. Suspension is an INPUT to that helper, not a separate filter reimplemented per query.
   VERIFICATION IS THREE TIERS, NOT A BOOLEAN. `verificationTier` is `none` / `bronze` / `silver` / `gold` and is what the badge renders and what other systems gate on. `verificationStatus` (`unverified`/`pending`/`verified`) still exists but means only the REVIEW STATE of a pending submission — the two are different axes and must never be conflated with each other or with visibility. A provider can be publicly visible at tier `none`.

1b. Payment between customer and provider is entirely off-platform — RaajjePro never moves money for a booking. Everything RaajjePro itself collects (provider subscriptions only in v1) is collected via manual bank transfer + admin confirmation — never assume or scaffold a payment gateway integration unless explicitly instructed otherwise.
   V1 IS SUBSCRIPTION-ONLY. There is no credit wallet and no advertising module in this codebase. If you encounter references to `CreditWallet`, `AdCampaign`, `AdRateCard`, or an `Advertiser` entity in older documentation, they describe cut post-v1 features — do not build toward them. Keep `PaymentSubmission`'s `purpose` enum open (`'subscription'` today) so they can slot back in additively.
   SUBSCRIPTION PRICE IS PER-PROVIDER, NOT GLOBAL. Read `providerProfile.subscriptionPriceLaari`, set at first confirmed payment and defaulting to MVR 150 = 15000 laari. The first 100 providers take a reduced introductory rate honoured 12 months from the billing anchor, then converting with 30 days' notice. Never hardcode a single global price — older documentation pinned one, and the conversion measurement depends on two price points coexisting.
   All customer-facing features remain free — nothing may ever gate a customer action. Basic listing discoverability is never paywalled; only quantity (listings beyond the free cap) and extras (analytics, priority placement) are gated.
   THE BADGE IS GATED BY `verificationTier` ALONE, never by subscription state. A lapsed-but-verified provider keeps their tier — it is a safety signal, not a payment status. A lapsed subscription degrades a provider to the free tier; it never deletes data and never hard-blocks an account.

1c. Booking has THREE modes: `slot` (fixed-duration, provider-published time slots — Cleaning, Beauty, Fitness), `request` (customer proposes a window, provider proposes a concrete time and price — Plumbing, Electrical, AC Repair, Photography, Gardening, Computer, Moving, Events, Boat Charter), and `emergency`, layered on Plumbing/Electrical/AC Repair/**Moving** listings only and ONLY for a provider meeting the category's `emergencyMinimumTier` — GOLD for Electrical and Plumbing, SILVER for AC Repair and Moving (Round 15). NEVER hardcode `silver` as the bar; older documentation saying "silver or above" for all four, or `verificationStatus === 'verified'`, is obsolete. There are TWELVE categories, including Boat Charter.
   EMERGENCY REQUESTS BROADCAST TO EVERY ELIGIBLE PROVIDER AT ONCE, and ACCEPTANCES DO NOT RACE (Round 15). The provider supplies their callout fee as part of accepting. The first acceptance opens a 90-SECOND COLLECTION WINDOW during which other eligible providers may also accept; at the end the customer is shown UP TO THREE OFFERS SIDE BY SIDE and picks one. Each offer is an `EmergencyOffer` row. `emergency_offered` means "offers are collected and awaiting the customer", NOT "one provider has claimed this" — older documentation describing first-acceptance-wins is obsolete, as is one-provider-at-a-time dispatch, a separate `set-amount` step, or fan-out as post-v1.
   ELIGIBILITY IS PER-CATEGORY, read from `emergencyMinimumTier` — GOLD for Electrical and Plumbing, SILVER for AC Repair and Moving. Never hardcode `silver`. THE RESPONSE WINDOW IS 30 MINUTES FOR ALL FOUR EMERGENCY CATEGORIES, MOVING INCLUDED (Round 22). Read it from `emergencyAcceptWindowMinutes` and never hardcode it — the field stays per-category so it can diverge again — but do not reintroduce 120 for Moving. That 120 described how long a mover takes to ARRIVE, and this field governs how long they may take to ANSWER; the two were conflated, and it left an emergency-move customer waiting two hours to learn nobody was coming. ARRIVAL IS NOW PER-OFFER: the provider supplies `etaMinutes` on `EmergencyOffer` alongside the callout fee, in the same accept call. It is self-declared and unverified — render it as the provider's estimate, never as a platform guarantee. ON-TIME RATE COVERS EMERGENCY (Round 22), measured against the accepted offer's `etaMinutes` rather than `scheduledFor`; §1f's older "emergency has no scheduled time" exclusion is obsolete.
   EMERGENCY CARRIES A MVR 200 DISPATCH FEE charged to the CUSTOMER, incurred when they select an offer and never on submitting a request. It NEVER blocks dispatch: it is recorded as owed and settled later by bank transfer through `PaymentSubmission` (purpose `emergency_dispatch_fee`). An unsettled fee blocks new bookings, and THE BLOCK LIFTS ON PROOF SUBMISSION, not on admin confirmation.
   Time-conflict prevention is a PostgreSQL exclusion constraint scoped to the PROVIDER, not the listing — `EXCLUDE USING gist (providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`. A `UNIQUE` constraint on `(providerId, listingId, startsAt)` is insufficient: it does not prevent one provider being booked twice at the same time across two different listings, and it does not detect overlapping durations. If you see that older constraint referenced, replace it.
   THERE IS NO SMS ANYWHERE IN THIS SYSTEM. OTP is sent to EMAIL. Messaging and booking require email verification (`requireEmailVerified`, stricter than `requireAuth`), enforced server-side on every relevant endpoint — never rely on hiding a UI button. If you see `requirePhoneVerified`, `phoneVerified`, an `SmsSender`, or a push→SMS→email ladder in older documentation or existing code, all of it is obsolete — flag it for removal rather than extending it.
   PHONE IS UNIQUE BUT NOT VERIFIED. `email` carries a database-level unique constraint. `phone` is unique ONLY FROM BRONZE UPWARD (Round 15) — an unverified number is claimable by several accounts, and exclusivity begins when an admin confirms it during Bronze review. This closes phone squatting as a supply-side attack. A registration against an in-use email, or against a number already held at Bronze or above, is blocked at the field naming which one is taken. UNIQUENESS IS NOT OWNERSHIP: nothing proves a number belongs to whoever typed it, so never render a phone number with a check mark and never describe one as verified. The admin confirms the number during Bronze review, which is the only point at which it becomes a checked fact.
   Push notifications have no in-app toggle for transactional sends, and the fallback is EMAIL. Be honest about the limit: the OS can still revoke notification permission and no app overrides that, so the email fallback is what covers it.
   THERE IS EXACTLY ONE ENDPOINT IN THIS ENTIRE SYSTEM THAT RETURNS A PHONE NUMBER TO ANOTHER USER: `POST /v1/bookings/:id/reveal-contact`. It is emergency-bookings-only, at `accepted` or later, customer-initiated, mutual and simultaneous, notifies the counterparty, expires 24 hours after the booking reaches a terminal state, is logged, and is disableable by a runtime kill switch. Every one of those seven request-time conditions is validated server-side, with the Phase 10b kill switch checked separately at runtime.
   `GET /v1/bookings/:id/contact-info` DOES NOT EXIST AND MUST NOT BE CREATED. It is a different, far broader mechanism — it exposed a phone number on every booking type with no conditions — and it was deleted outright. WhatsApp and Viber handles are not collected anywhere in this system and cannot be revealed by anything. Any response shape outside the reveal endpoint that carries a phone number is a defect.
   Booking payment confirmation ("I've Paid" / "Payment Received") is a two-sided self-attestation between customer and provider, NEVER the `PaymentSubmission`/admin-confirmation mechanism (that is exclusively for RaajjePro's own subscription fees) — do not conflate the two systems. UI copy must never imply platform-level verification ("Payment Verified," a certainty checkmark) — use language that honestly reflects what happened, e.g. "Provider confirmed receipt."
   Contact-pattern detection is SILENT and LOGGED — never a block, never a redaction, and never shown to the sender. In-app messaging carries no interference of any kind. Older documentation describing an inline nudge banner is obsolete. A hard block on phone-shaped text cannot reliably distinguish a Maldivian mobile number from an appliance serial number, and blocking that content defeats the channel's purpose. Detections surface only as a provider-level moderation aggregate, never inline.
   IN-APP CHAT IS THE SOLE COORDINATION CHANNEL for a booking's entire life, including after completion. It opens at `quote_offered` for request-based bookings and at `accepted` for slot and emergency. It is never torn down and never replaced.

1d. Never write binding legal text (Terms of Service, Privacy Policy, Provider Agreement, or any policy language) as if it were final — legal content is always inserted as clearly-marked, structurally-correct placeholder pending real legal review, never fabricated. Moderation actions must always be reversible (status/visibility flag), never a hard delete. Product/analytics event logs follow the same no-PII rule as structured logging — event metadata may reference IDs, never raw email/phone/payment-proof/ID-document content.
   Identity-verification documents live in a SEPARATE private storage location from payment proofs and general media, are served only via short-lived signed URLs, every access is logged, and they are purged automatically 90 days after a verification decision and immediately on account deletion — the decision, the evidence type and the reviewing admin persist, the images do not.
   ACCOUNT DELETION IS QUEUED, NEVER REFUSED. A request is accepted immediately, the account frozen, and anonymisation executes automatically once non-terminal bookings terminate, with a hard 30-day backstop. Do not implement it as an error when bookings are open.

2. Publishing a basic service listing must remain simple; advanced details are always optional. A draft must be saveable with zero required fields filled. Only publish enforces required fields — of which a COVER IMAGE is one.

3. This is an open marketplace — no mandatory pre-publication approval workflow for listings.

4. The backend is the single source of truth for all business rules. Client-side validation exists only for UX; it must never be the only place a rule is enforced.

5. New functionality is added through additive, modular changes. Do not refactor unrelated modules as a side effect — flag suggested refactors instead of doing them silently.

6. Every phase/feature must be independently testable. If you can't state how to verify what you just built, stop and ask.

7. Money is always integer laari (MVR × 100), never float or decimal-as-string. MVR 150 = 15000 laari.

8. Every entity uses a UUID primary key. Nothing is ever hard-deleted — soft-delete via a visibility/status field, everywhere, no exceptions.

9. THE ADMIN PANEL IS A SEPARATE REACT WEB APP, not a Flutter screen, built across Phases 10a (money and identity queues), 10b (accounts, config, search, shell) and 10c (ops dashboard). Backend endpoints are identical either way.

10. THE TRANSACTIONAL EMAIL PROVIDER IS AMAZON SES, and it is the ONLY one — there is no SMS and no second email vendor. Email carries OTP, the Phase 3c push fallback, and Phase 10b's admin alerting, so it is a single point of failure by design. Send through the `EmailSender` interface, never by calling SES directly from a domain module. Three SES configuration sets back the three independently killable channels (OTP / notification / marketing) and keep their reputation metrics separate. Bounce/complaint handling and the suppression list are built in PHASE 0, not Phase 3c — SES will not leave its sandbox without them. SES has no searchable activity console, so the per-message delivery log is ours to build and Phase 10b must be able to answer "did this user actually receive it?" in one lookup.

11. PROVIDER CONDUCT IS SCORED AND DISPLAYED AS OBJECTIVE METRICS ONLY (§1f, Round 15). Completion, cancellation, no-show, on-time, price-adherence, acceptance and median response time, computed from booking outcomes over a rolling 90 days, hidden below 10 completed bookings. NEVER generate editorial labels — "Prone to cancel", "Price hiking" and every euphemism for them were considered and REJECTED as automated public accusations with defamation exposure. Show the numbers; let the customer conclude. Providers see their own metrics before anyone else does.

12. "PAYMENT HOLD" MEANS A LOCKED AGREEMENT, NOT ESCROW (§1h, Round 15). RaajjePro still never moves money for a booking. At `accepted` the agreed price, date, time and scope lock; changing any of them needs an explicit amendment the other party accepts; every attempt is recorded and feeds price adherence. DO NOT build escrow, funds holding, or a payment gateway for bookings.

13. QUOTE WINDOWS ARE PER-CATEGORY (Round 15), read from `quoteExpiryMinutes` / `quoteApprovalMinutes` — 120/240 for Plumbing, Electrical, AC Repair and Computer; 1440/4320 for Photography, Gardening, Moving, Events and Boat Charter. Never hardcode 24h/72h.

14. LOCAL PREFERENCE IS "MALDIVIAN-OWNED BUSINESS", VERIFIED AT GOLD (§1g, Round 15) — an attribute of the business evidenced by its registration document. NEVER store nationality on an individual provider and never let customers filter people by it.

Development priorities, in order: readability > cleverness, explicit > implicit, predictable > convenient, small focused changes > large sweeping ones.

Never expose internal error details (stack traces, raw DB errors) in API responses. Never log passwords, tokens, or full PII values.

---

# Working across machines

`HANDOVER.md` is the entry point for a fresh checkout. Keep it true — if a workflow changes, that file changes with it.

**Everything of value lives in git.** Never leave a decision, a design or a piece of reasoning only in a chat session. If it matters tomorrow, it is a file.

**End of day:** `scripts/eod-push.sh` verifies the design prototypes, checks the remote, commits and pushes. A scheduled task runs it at 16:30 Maldives time as a backstop.

# Working with Claude Design

The app is being rebuilt as working `.dc.html` prototypes in the Claude Design project `065ca2ad-ff8f-4eac-a8f8-e860a77561ff`. `docs/design/redesign-plan.md` carries the thirteen-session sequence; `docs/design/sessions/` carries the prompts.

- **Read a project file with the DesignSync connector** — `list_files`, then `get_file`. That project is `PROJECT_TYPE_PROJECT`, so it never appears in `list_projects`, which filters to design-system projects. Address it by id.
- **Audit every imported artboard against the plan before it is committed.** This is the step that catches what a design review cannot: invented endpoints, claims the product cannot keep, numbers that contradict a category's configuration. It has caught something material in every prototype so far.
- **Write corrections as a follow-up prompt** naming what to change and what to leave alone. Never rework a design directly — the project is the source and the repo is the copy.
- **`python3 docs/design/verify-dc.py <files>` gates the commit.** Structure plus the locked rules.
- **Components are files.** `<dc-import>` mounts a sibling `.dc.html`; seven exist and must be imported, never copied. The tier copy lives in `VerificationBadge` and the status labels in `StatusPill` — duplicating either into a screen is a defect.
- **Prototypes beat images.** Where `mockups/design-composer/` and `mockups/*.jpg` cover the same screen, the prototype is current and the JPEG is provenance.

# Scope Discipline

- Build exactly what the current phase's prompt describes. Do not build ahead into a later phase because it seems convenient.
- Do not add features not asked for. Do not add configuration options "for flexibility."
- If a prompt appears to require something the plan does not specify, STOP and ask rather than inventing it. A plausible guess written confidently is worse than a question.
- If a prompt conflicts with the plan, flag it. Do not resolve it silently in either direction.
- Deliberately out of v1 scope — do not build these, and do not leave TODOs implying they are coming: admin IP allowlisting; second-admin sign-off; bulk admin queue actions and keyboard triage; a proactive risk-signal dashboard; provider broadcast messaging; a secondary email provider; credit wallet; advertising; referrals; Dhivehi/Thaana localisation.
- IN scope as of Round 12, despite older documentation deferring them: admin TOTP MFA and session controls, and simultaneous emergency fan-out to multiple providers.
- IN scope as of Round 13, and EARLIER than older documentation places it: email bounce/complaint handling and the SES suppression list are a PHASE 0 deliverable, not Phase 3c. SES will not leave its sandbox without them, and a sandboxed account cannot send to unverified addresses — so Phase 3 is untestable until this exists. If a Phase 3c prompt implies you are building it for the first time, it already exists; wire to it.
- Flag suggested refactors; do not perform them as a side effect of an unrelated task.
