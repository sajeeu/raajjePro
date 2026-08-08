# RaajjePro — Cursor Rules, Skills & Subagents (v5.2)

**Regenerated against `01_Development_Plan_v5.md`** (Rounds 8 through 11 folded in).

**Round 11 removed SMS from the system entirely.** If you have the v5.1 copy of these rules installed, replace it: it asserts SMS OTP, a `phoneVerified` flag, a `requirePhoneVerified` guard, and a push→SMS→email fallback ladder, none of which exist any more.

**Delete the v4 version of this file immediately.** It is the most dangerous stale artifact in the project, because rules auto-apply on *every* generation without being restated. Specifically, v4's always-apply rule asserted a `GET /v1/bookings/:id/contact-info` endpoint that no longer exists, and instructed the agent that an emergency contact reveal "was a deliberately closed security hole; do not reintroduce it." That instruction would actively fight Phase 17.3, which builds exactly such a reveal under seven deliberate conditions. It also asserted a binary `verificationStatus`, a pinned global subscription price, and that no provider-onboarding screen exists — all three now false.

## 1. Rules — `.cursor/rules/*.mdc`

Rules are always in context for matching files. Keep them short and invariant — anything phase-specific belongs in `02_Cursor_Prompts.md`, not here.

```
.cursor/rules/
  000-project-context.mdc
  010-backend-conventions.mdc
  011-api-contract.mdc
  020-frontend-conventions.mdc
  030-design-system.mdc
  040-testing.mdc
  050-scope-discipline.mdc
```

### `.cursor/rules/000-project-context.mdc`

**Always apply**

```markdown
---
alwaysApply: true
---
# RaajjePro — Project Context

RaajjePro is a mobile-first, API-first Local Service Marketplace for the Maldives.
Frontend: Flutter. Backend: TypeScript (Fastify + Prisma + PostgreSQL). REST, versioned under /v1.
Full specification: `01_Development_Plan_v5.md` at revision 5.1. If any instruction here appears to conflict with that document, the document wins — flag the conflict rather than picking silently. Within that document, §0.0 is a precedence rule: where §0.1–0.3 conflict with a later section, the later section wins.

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

1c. Booking has THREE modes: `slot` (fixed-duration, provider-published time slots — Cleaning, Beauty, Fitness), `request` (customer proposes a window, provider proposes a concrete time and price — Plumbing, Electrical, AC Repair, Photography, Gardening, Computer, Moving, Events, Boat Charter), and `emergency`, layered on Plumbing/Electrical/AC Repair listings only and ONLY for a provider at tier `silver` or `gold`. The bar is SILVER OR ABOVE — older documentation said `verificationStatus === 'verified'` and is obsolete. There are TWELVE categories, including Boat Charter.
   Time-conflict prevention is a PostgreSQL exclusion constraint scoped to the PROVIDER, not the listing — `EXCLUDE USING gist (providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`. A `UNIQUE` constraint on `(providerId, listingId, startsAt)` is insufficient: it does not prevent one provider being booked twice at the same time across two different listings, and it does not detect overlapping durations. If you see that older constraint referenced, replace it.
   THERE IS NO SMS ANYWHERE IN THIS SYSTEM. OTP is sent to EMAIL. Messaging and booking require email verification (`requireEmailVerified`, stricter than `requireAuth`), enforced server-side on every relevant endpoint — never rely on hiding a UI button. If you see `requirePhoneVerified`, `phoneVerified`, an `SmsSender`, or a push→SMS→email ladder in older documentation or existing code, all of it is obsolete — flag it for removal rather than extending it.
   PHONE IS UNIQUE BUT NOT VERIFIED. Both `email` and `phone` carry database-level unique constraints, and a registration against either in-use value is blocked at the field naming which one is taken. UNIQUENESS IS NOT OWNERSHIP: nothing proves a number belongs to whoever typed it, so never render a phone number with a check mark and never describe one as verified. The admin confirms the number during Bronze review, which is the only point at which it becomes a checked fact.
   Push notifications have no in-app toggle for transactional sends, and the fallback is EMAIL. Be honest about the limit: the OS can still revoke notification permission and no app overrides that, so the email fallback is what covers it.
   THERE IS EXACTLY ONE ENDPOINT IN THIS ENTIRE SYSTEM THAT RETURNS A PHONE NUMBER TO ANOTHER USER: `POST /v1/bookings/:id/reveal-contact`. It is emergency-bookings-only, at `accepted` or later, customer-initiated, mutual and simultaneous, notifies the counterparty, expires 24 hours after the booking reaches a terminal state, is logged, and is disableable by a runtime kill switch. Every one of those seven conditions is validated server-side.
   `GET /v1/bookings/:id/contact-info` DOES NOT EXIST AND MUST NOT BE CREATED. It is a different, far broader mechanism — it exposed a phone number on every booking type with no conditions — and it was deleted outright. WhatsApp and Viber handles are not collected anywhere in this system and cannot be revealed by anything. Any response shape outside the reveal endpoint that carries a phone number is a defect.
   Booking payment confirmation ("I've Paid" / "Payment Received") is a two-sided self-attestation between customer and provider, NEVER the `PaymentSubmission`/admin-confirmation mechanism (that is exclusively for RaajjePro's own subscription fees) — do not conflate the two systems. UI copy must never imply platform-level verification ("Payment Verified," a certainty checkmark) — use language that honestly reflects what happened, e.g. "Provider confirmed receipt."
   The enquiry channel's contact-pattern detection is a SOFT NUDGE, LOGGED, NEVER A BLOCK — the message always sends. A hard block on phone-shaped text cannot reliably distinguish a Maldivian mobile number from an appliance serial number, and blocking that content defeats the channel's purpose. Detections surface as a provider-level moderation signal, not enforced inline.
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

Development priorities, in order: readability > cleverness, explicit > implicit, predictable > convenient, small focused changes > large sweeping ones.

Never expose internal error details (stack traces, raw DB errors) in API responses. Never log passwords, tokens, or full PII values.
```

### `.cursor/rules/010-backend-conventions.mdc`

**Applies to:** `backend/**/*.ts`

```markdown
---
globs: backend/**/*.ts
---
# Backend Conventions

- Domain-module structure: `backend/src/modules/<domain>/` containing routes, service, repository, schema (Zod), and types. Business logic lives in the service layer, never in a route handler.
- Prisma is the only database access path. No raw SQL except where a feature genuinely requires it — the gist exclusion constraint and its supporting migration are the expected exception.
- Every mutating endpoint has an explicit authorization check as its first act, stated in a comment naming who is allowed. Authorization on READS too — an unauthorized read of a booking or a payment detail is a real leak.
- Zod schemas validate every request body, query and param. Never trust a client-supplied ID without checking ownership.
- Money is integer laari end to end — in the database, in the DTO, in the JSON. Never convert to float anywhere in the path.
- Idempotency middleware on every money-adjacent and creation POST, keyed on `(userId, operation, clientKey)`, returning the ORIGINAL result on repeat.
- Scheduled work runs on the job runner from Phase 0, never as check-on-read. If a transition should happen at a time, a job makes it happen at that time.
- Sensitive fields (payment details, identity documents, phone numbers) are excluded structurally in the DTO mapping layer, not by remembering to omit them per handler.
- Soft-delete only. Every query that returns user-visible data filters on the visibility/status field.
```

### `.cursor/rules/011-api-contract.mdc`

**Applies to:** `backend/**/*.ts`

```markdown
---
globs: backend/**/*.ts
---
# API Contract Rules

- Every response — success and failure — uses the standard envelope. Errors carry a stable machine-readable `code`, a human-readable `message`, and optional `details`. Never return a bare string; the frontend routes on codes.
- Error codes are stable identifiers, not prose. Renaming one is a breaking change.
- ADDITIVE-ONLY EVOLUTION WITHIN /v1. Never remove a field, never repurpose a field's meaning, never tighten a type. Mobile clients cannot be force-updated, so a breaking change strands every installed app version. If a change cannot be made additively, stop and flag it.
- Pagination is server-side and mandatory on any endpoint that can return an unbounded set.
- Rate-limit tiers are declared per endpoint, not applied globally by default. Auth, OTP, payment, emergency-booking and MESSAGING endpoints carry stricter tiers.
- No endpoint outside `POST /v1/bookings/:id/reveal-contact` may include a phone number in any response shape, at any nesting depth, under any status. When adding a field to a shared DTO, check what else consumes it.
```

### `.cursor/rules/020-frontend-conventions.mdc`

**Applies to:** `frontend/**/*.dart`

```markdown
---
globs: frontend/**/*.dart
---
# Flutter Conventions

- Feature-based structure: `lib/features/<feature>/` with presentation, controller (Riverpod), and data layers. Shared widgets live in `lib/shared/`, cross-cutting concerns in `lib/core/`.
- Riverpod for all state. No `setState` for anything that outlives a single widget's local interaction.
- EVERY screen implements loading, empty, error and populated states. This is part of the screen's own definition of done, not a later QA pass. An empty state names what the user should do next; it never merely reports that nothing is there.
- Network failures degrade gracefully. Where a flow is marked offline-resilient — the service wizard, the provider accept prompt, chat sends — queue locally on failure, show a pending indicator, and replay on reconnect. Never silently discard user input.
- Optimistic updates roll back visibly on failure.
- Errors surface INLINE where the user can act on them, not as generic toasts. A field error belongs under its field.
- Accessibility is built in, not retrofitted: 48x48 minimum touch targets, visible focus states, semantic labels, and reduced-motion handling that degrades shimmer and transitions when the OS flag is set.
- Never hardcode a color, font, spacing value or radius. Use design tokens; add to them explicitly if genuinely missing.
```

### `.cursor/rules/030-design-system.mdc`

**Applies to:** `frontend/**/*.dart`

```markdown
---
globs: frontend/**/*.dart
---
# RaajjePro Design System (source of truth)

- Tokens are derived from the mockups and live in a Theme extension. Scattered constants are a defect.
- Component states are explicit and complete: buttons carry pressed, disabled and loading; inputs carry normal, focused, error and disabled.
- A button that triggers a network call shows ITS OWN loading state. Do not cover the screen with a page-level spinner for a local action.
- Skeleton loaders for content that is fetching; not spinners, and not a blank screen.
- Verification tier badges are three distinct treatments (Bronze/Silver/Gold), each carrying the exact public copy from the plan's §1e: "ID checked by RaajjePro" / "ID checked, work verified" / "ID checked, registered trade". NEVER render a bare "Verified" — a customer may read that as "has a good track record" rather than "passed an ID and trade check".
- Booking-mode affordances appear on every card and listing surface: "Book instantly" (slot), "Request a time" (request), plus an "Emergency available" marker where applicable. A customer must never be uncertain which kind of wait they are in.
- Where a mockup predates the current plan, THE PLAN WINS and you flag the mismatch — do not silently implement the mockup.
```

### `.cursor/rules/040-testing.mdc`

**Applies to:** `backend/**/*.test.ts`, `frontend/**/*_test.dart`

```markdown
---
globs: backend/**/*.test.ts, frontend/**/*_test.dart
---
# Testing Conventions

- Every business rule gets a test asserting the rule, not the implementation. A test that would pass against a wrong implementation is not a test.
- Concurrency is tested explicitly wherever the plan names it: simultaneous slot booking, cross-listing overlap on one provider, 1,000 concurrent attempts asserting zero double-books, simultaneous admin confirmation, repeated idempotent POSTs.
- State machines are tested at their boundaries — the transition that should be rejected matters more than the one that should succeed.
- Scheduled jobs are tested by advancing time, not by waiting.
- Authorization tests cover reads as well as writes, and cover the wrong-user case, not just the unauthenticated one.
- Any endpoint touching a phone number is tested for its ABSENCE in the response, not only for the presence of what it should return.
- Registration is tested against both a duplicate email and a duplicate phone, asserting each is blocked with a message naming the specific field.
```

### `.cursor/rules/050-scope-discipline.mdc`

**Always apply**

```markdown
---
alwaysApply: true
---
# Scope Discipline

- Build exactly what the current phase's prompt describes. Do not build ahead into a later phase because it seems convenient.
- Do not add features not asked for. Do not add configuration options "for flexibility."
- If a prompt appears to require something the plan does not specify, STOP and ask rather than inventing it. A plausible guess written confidently is worse than a question.
- If a prompt conflicts with the plan, flag it. Do not resolve it silently in either direction.
- Deliberately out of v1 scope — do not build these, and do not leave TODOs implying they are coming: admin MFA, IP allowlisting and session hardening; second-admin sign-off; bulk admin queue actions and keyboard triage; a proactive risk-signal dashboard; provider broadcast messaging; a secondary SMS provider; simultaneous emergency fan-out to multiple providers; credit wallet; advertising; referrals; Dhivehi/Thaana localisation.
- Flag suggested refactors; do not perform them as a side effect of an unrelated task.
```

---

## 2. Skills — `skills/*/SKILL.md`

Auto-discovered and invoked when the task matches the skill's `description` — no `@mention` needed, though you can force one via the slash-command menu. Each skill lives in its own directory.

```
skills/
  wizard-step-pattern/SKILL.md
  backend-domain-module/SKILL.md
  screen-state-completeness/SKILL.md
  mockup-fidelity-check/SKILL.md
  no-mockup-design-proposal/SKILL.md
  manual-payment-monetization/SKILL.md
  booking-payment-attestation/SKILL.md
  offline-queue-and-replay/SKILL.md
  time-conflict-reservations/SKILL.md
  verification-tiers/SKILL.md
  contact-rule-and-moderation/SKILL.md
  admin-panel-conventions/SKILL.md
```

**Changed from v4:** `contact-gating-and-moderation` is renamed `contact-rule-and-moderation` — "gating" described a mechanism that no longer exists. Three skills are new: `offline-queue-and-replay` (the pattern is now shared by three phases), `verification-tiers`, and `admin-panel-conventions` (the admin app is React, and mobile assumptions were leaking into it).

### `skills/wizard-step-pattern/SKILL.md`

```markdown
---
name: wizard-step-pattern
description: Use when building, editing, or reviewing any step of the Create/Edit Service Wizard, or any other multi-step flow (provider onboarding, booking request, forgot-password). Triggers on mentions of "wizard," "step," "multi-step flow," or work inside frontend/lib/features/service_wizard/.
---
# Multi-Step Wizard Pattern

- Each step is a standalone widget accepting the current draft state + an onChange callback — never reads global state directly, so it can be tested in isolation.
- Step navigation state (which step is active, which are "complete") lives in a single Riverpod controller for the wizard, not per-step.
- "Complete" for progress-bar purposes means "has the minimum data for this step to be meaningful," NOT "passes publish validation" — different checks. A step can be visited and left blank; it just won't show a green check.
- Every step's onChange triggers a debounced PATCH to the draft entity — don't wait for "Continue" to persist.
- Offline resilience uses the shared queue-and-replay helper (see the offline-queue-and-replay skill), not a wizard-local implementation.
- The final review step is the only place full validation runs, and it must produce a FIELD-LEVEL list — not a generic "form invalid" — mapping to "Fix" deep links back to the offending step.
- Step navigation is never blocked by incomplete validation. A user can always jump straight to review with nothing filled in.
- Progress framing leads with required-fields-remaining, not step count, wherever the plan specifies it.
```

### `skills/backend-domain-module/SKILL.md`

```markdown
---
name: backend-domain-module
description: Use when creating a new backend domain module or adding endpoints to an existing one. Triggers on work under backend/src/modules/, or mentions of adding an entity, route, service, or repository.
---
# New Backend Domain Module Checklist

Every module ships with: routes, service, repository, Zod schema, types, and tests. Business logic in the service layer only.

Before considering the module done, confirm each:
- Authorization on EVERY endpoint including reads, with a comment naming who is permitted.
- Ownership checked on every client-supplied ID.
- Zod validation on body, query and params.
- Idempotency middleware on money-adjacent and creation POSTs.
- Sensitive fields excluded structurally in DTO mapping — payment details, identity documents, phone numbers. Not by per-handler memory.
- Soft-delete respected in every read query.
- Money as integer laari throughout.
- Standard response envelope, with stable error codes.
- Any state transition that should happen at a time is driven by a scheduled job, not check-on-read.
- A test asserting each business rule at its boundary.
```

### `skills/screen-state-completeness/SKILL.md`

```markdown
---
name: screen-state-completeness
description: Use when building or reviewing any Flutter screen. Triggers on any work under frontend/lib/features/ that renders data, or mentions of a screen, page, tab, or view.
---
# Screen State Completeness

Every screen implements four states. This is part of the screen's own definition of done, not Phase 20's audit — Phase 20 only VERIFIES what each phase already specified.

1. LOADING — skeleton loader matching the populated layout's shape, not a centred spinner and not a blank screen.
2. EMPTY — names what the user should do next, with an action where one exists. "No saved services yet" plus a route into Explore, never a bare "Nothing here."
3. ERROR — states what failed in human terms and offers retry. Never a raw error code or a stack trace.
4. POPULATED — the real thing.

Also handle, where applicable:
- Offline: a visible banner, and pending indicators on anything queued.
- Partial failure: one section failing must not blank the whole screen.
- A first-time state distinct from a genuinely-empty one where the difference matters to the user.

A "no data yet" metric reads as "No data yet" — never a blank, and never a zero that reads worse than no metric at all.
```

### `skills/mockup-fidelity-check/SKILL.md`

```markdown
---
name: mockup-fidelity-check
description: Use when implementing a screen against an attached mockup image. Triggers whenever a mockup file is referenced or attached.
---
# Mockup Fidelity Self-Check

Match the mockup pixel-for-pixel including motion — tap-scale, animated toggles, skeleton loaders, spring bottom sheets.

But WHERE A MOCKUP PREDATES THE CURRENT PLAN, THE PLAN WINS AND YOU FLAG THE MISMATCH. Do not silently implement the mockup. Known divergences to expect:
- The Explore grid shows 12 categories and the plan has 12 — including Boat Charter. If a mockup shows 11, the plan wins.
- The wizard's Availability step shows a per-listing "Accepting New Customers" toggle. That is now PROVIDER-LEVEL and lives on the dashboard. Remove it from the step.
- Any mockup implying contact details are exchanged between customer and provider is obsolete except for the emergency reveal path.
- Any mockup showing a single "Verified" badge is obsolete — verification is three tiers with tier-specific copy.

Before declaring a screen done: compare against the mockup at 1:1, check every state (not just populated), and list any deliberate divergence with its reason.
```

### `skills/no-mockup-design-proposal/SKILL.md`

```markdown
---
name: no-mockup-design-proposal
description: Use when asked to build a screen for which no mockup exists. Triggers on "propose a design," "no mockup," or any screen from the plan's no-mockup list.
---
# Proposing a Design With No Mockup

STOP before writing implementation code. Propose first, get approval, then build.

The proposal states: layout structure, which existing components it reuses, what each state looks like, and the primary user action. It reuses the established design system — it does not introduce a new visual language.

Screens in this category include: Bookings tab and detail, Notifications centre, provider public profile, search and category results, Saved Services, forgot-password, OTP entry, Trust & Safety and Privacy sub-screens, availability and slot management, provider billing, account settings, role switcher, launch-mode Home variant, all three booking-flow variants, the enquiry thread, and Phase 6a's onboarding flow.

Keep the proposal short — structure and states, not prose. A developer should be able to picture it in one read.
```

### `skills/manual-payment-monetization/SKILL.md`

```markdown
---
name: manual-payment-monetization
description: Use when working on subscriptions, trials, entitlements, payment submissions, or billing UI. Triggers on mentions of subscription, trial, entitlement, PaymentSubmission, billing, or invoice.
---
# Manual Payment & Monetization Pattern

- RaajjePro collects ONLY provider subscription fees, via manual bank transfer + admin confirmation. No payment gateway. Never scaffold one.
- `PaymentSubmission` is one generic entity with an open `purpose` enum — `'subscription'` today.
- NOTHING IS GRANTED ON SUBMISSION. A `pending` submission produces entitlements identical to no payment at all. `getProviderEntitlements` reads LIVE database state on every call and never caches.
- PRICE IS PER-PROVIDER: read `providerProfile.subscriptionPriceLaari`. Never a global constant.
- Billing is on a 30-day ANCHOR, never a calendar month. Pausing SHIFTS the anchor by the paused duration. Never imply month boundaries in data or copy.
- Pause is capped at 10 cumulative days, keyed off the provider-level `acceptingNewCustomers` toggle, with ONE shared implementation for `trialing` and `active`.
- Trial fires on whichever of three triggers comes first: transition INTO `confirmed` (hooked on the state transition, not one endpoint), an explicit "Try Premium", or a proactive prompt 7 days after first publish. All call one no-op-if-already-run function.
- DOWNGRADE IS NON-DESTRUCTIVE. Listings over cap are hidden, never deleted. The badge is unaffected. A listing with a confirmed future booking is PROTECTED and stays visible regardless of cap. Among unprotected listings, the HIGHEST-PERFORMING survives (bookings over 90 days, then views, then recency) — not the most recently updated, which was gameable.
- Admin confirmation and reversal are explicit audit-logged endpoints, never database edits.
```

### `skills/booking-payment-attestation/SKILL.md`

```markdown
---
name: booking-payment-attestation
description: Use when working on the booking payment flow, the "I've Paid" or "Payment Received" actions, disputes, or payment_unresolved. Triggers on mentions of attestation, claim-payment, confirm-receipt, dispute, or booking payment.
---
# Booking Payment Attestation

This is a TWO-SIDED SELF-ATTESTATION between customer and provider about an OFF-PLATFORM bank transfer. It is NEVER the `PaymentSubmission`/admin mechanism — that is exclusively RaajjePro's own subscription fees. Do not conflate the two systems.

- The customer taps "I've Paid" — self-attestation, NO proof upload. Status `payment_claimed`.
- The provider confirms or disputes. Confirm → `confirmed`. Dispute → `disputed`.
- SEVEN DAYS of provider silence → `payment_unresolved`, NOT `confirmed`. Both parties notified, a Report filed, and NOTHING further unlocked by the transition. An earlier revision auto-confirmed here, recording an attestation that may never have happened.
- Neither `disputed` nor `payment_unresolved` is terminal. An admin resolves both — disputes with a FIXED ENUMERATION (`resolved_for_customer`, `resolved_for_provider`, `inconclusive`, `fraud_confirmed`, `withdrawn`), never free text.
- Decline ≠ dispute. Separate endpoints, separate statuses, visually distinct in the UI.

HONEST FRAMING IS MANDATORY. RaajjePro has no visibility into the actual bank transfer and the UI must never imply otherwise:
- NEVER "Payment Verified". NEVER a lock or verified-checkmark on this flow.
- USE "Provider confirmed receipt."
- The whole experience here is waiting for a human decision, so status legibility and honest expectation-setting are the product. State what happens next and roughly when.

Emergency bookings additionally REQUIRE `finalAmount` to complete — the real settled total after parts and labour. It gates completion exactly as `agreedAmount` gates `awaiting_payment`. It is the number a dispute needs, and the provider has no incentive to volunteer it.
```

### `skills/offline-queue-and-replay/SKILL.md`

```markdown
---
name: offline-queue-and-replay
description: Use when implementing any action that must survive a dropped connection — the service wizard, the provider accept prompt, or chat sends. Triggers on mentions of offline, queue, replay, retry, or connectivity.
---
# Offline Queue and Replay

The plan names weak atoll connectivity as a platform-wide risk. Three surfaces are offline-resilient and MUST share one implementation, not three:

1. The Create/Edit Service Wizard's per-step autosave (Phase 9) — the highest-value conversion flow.
2. The provider accept prompt (Phase 17.1) — a lost tap costs the provider the job, and leaves them unsure whether it registered.
3. Chat message sends (Phase 18) — chat is the sole coordination channel, so a silently-failed message is a coordination failure, not a cosmetic one.

The pattern:
- Record the action locally BEFORE the network call.
- Show a visible pending state on the affected item — not a global spinner.
- Replay on reconnect, in order, idempotently. Server-side idempotency keys make a double-replay safe.
- On permanent failure, surface it where the user can act, and never discard their input.
- Never block the UI waiting for a network round trip on these three surfaces.

Build it once in `lib/core/`. If you find yourself writing a second implementation, stop.
```

### `skills/time-conflict-reservations/SKILL.md`

```markdown
---
name: time-conflict-reservations
description: Use when working on time slots, reservations, availability rules, booking creation, quotes, or reschedule. Triggers on mentions of slot, reservation, availability, double-booking, or scheduling.
---
# Time-Conflict Prevention

THE CONSTRAINT — provider-scoped and range-based:
`EXCLUDE USING gist (providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)`

A `UNIQUE` index on `(providerId, listingId, startsAt)` is WRONG twice over: it permits one provider being booked three times at 10:00 across three different listings, and it detects nothing about overlapping DURATIONS. If you see it referenced anywhere, replace it. Application code must not be able to override the constraint.

- Slot reservation happens INSIDE the booking-creation transaction. A race resolves to exactly one winner.
- Reservations are FIRM (a booked slot) or PROVISIONAL (a quote offered, expiring with its 72-hour window). Offering a quote MUST create a provisional reservation — otherwise the provider can sell that time in the interim and the customer's approval fails on a constraint violation after they already agreed a price.
- Releasing a reservation (cancel, decline, timeout, expiry) returns the slot to `open` atomically.
- Reschedule frees the old reservation in the SAME transaction that takes the new one — never leave the provider double-blocked or double-free.
- The customer-facing picker filters on `startsAt > now()` PLUS the category's `minimumLeadTimeMinutes`, IN ADDITION to `status = 'open'`. This is a QUERY-TIME guarantee, not a dependency on the nightly regeneration job having run.
- Slot generation is idempotent across a 60-day rolling window. Re-running changes nothing.
- Emergency bookings take NO calendar reservation — an emergency interrupts the published calendar rather than blocking it.
```

### `skills/verification-tiers/SKILL.md`

```markdown
---
name: verification-tiers
description: Use when working on identity verification, the verified badge, emergency eligibility, or the admin verification queue. Triggers on mentions of verification, verified, badge, bronze, silver, gold, or KYC.
---
# Verification Tiers

`verificationTier` is `none` / `bronze` / `silver` / `gold`. It is what the badge renders and what other systems gate on. It is NOT a boolean, and older documentation asserting `verificationStatus === 'verified'` is obsolete. `verificationStatus` still exists but means only the review state of a pending submission.

| Tier | Requirements | Public copy |
|---|---|---|
| Bronze | Government ID matching the account name. No trade evidence. | "ID checked by RaajjePro" |
| Silver | Bronze + photos of completed work + EITHER a customer reference RaajjePro contacts OR 5 completed on-platform bookings with no unresolved dispute | "ID checked, work verified" |
| Gold | Silver + business registration OR a recognised trade certificate | "ID checked, registered trade" |

- PHOTOS ARE NEVER SUFFICIENT ALONE AT ANY TIER — they are trivially reusable.
- THE 5-CLEAN-BOOKINGS ROUTE TO SILVER GRANTS AUTOMATICALLY, with no admin review. Implement as a triggered check, not a queue item. Only ID checks, customer references and Gold paperwork reach a human — that is what makes three tiers affordable against a single reviewer.
- EMERGENCY CAPABILITY REQUIRES SILVER OR ABOVE. Enforced on listing publish, on update, AND re-checked at booking creation.
- The badge NEVER depends on subscription state. A lapsed-but-verified provider keeps their tier.
- Tiers do NOT expire and there is no periodic recheck. A `fraud_confirmed` outcome or an accumulated dispute pattern triggers a review that may demote or revoke.
- Never render a bare "Verified" — always the tier-specific copy above.
- Documents: separate private bucket, short-lived signed URLs, every access logged, purged 90 days after decision and immediately on account deletion.
```

### `skills/contact-rule-and-moderation/SKILL.md`

```markdown
---
name: contact-rule-and-moderation
description: Use when working on messaging, the enquiry channel, contact-pattern detection, the emergency contact reveal, blocking, reports, or the moderation queue. Triggers on mentions of chat, message, enquiry, contact, block, report, or moderation.
---
# The Contact Rule & Moderation

Renamed from "contact-gating" in v4 — gating described a mechanism that no longer exists. There is no unlock schedule, no per-status visibility ladder.

THE RULE: phone numbers are never exchanged between customer and provider, with EXACTLY ONE exception — `POST /v1/bookings/:id/reveal-contact`, emergency bookings only, validating all seven conditions server-side: emergency mode; `accepted` or later; customer-initiated; mutual and simultaneous; counterparty notified; expiring 24 hours after terminal state; logged. Also kill-switchable at runtime.

`GET /v1/bookings/:id/contact-info` DOES NOT EXIST. Do not create it. It was a far broader mechanism exposing a number on every booking type with no conditions, and it was deleted. WhatsApp and Viber handles are not collected anywhere and cannot be revealed by anything.

CHAT IS THE SOLE COORDINATION CHANNEL for a booking's whole life, including after completion. It opens at `quote_offered` for request-based and at `accepted` for slot and emergency. Never torn down.

CONTACT-PATTERN DETECTION IS A SOFT NUDGE, LOGGED, NEVER A BLOCK. The message always sends. Maldivian mobiles are 7 digits beginning 7 or 9; AC serials are 7–15 digit strings — not reliably distinguishable, and blocking that content defeats the enquiry channel's purpose. Photos are allowed anyway, so a business-card photo passes a text filter regardless. Detections aggregate to a PROVIDER-LEVEL signal ("tripped detection in 40 of 52 enquiries"), never per-message noise.

BLOCK IS TWO ACTIONS: "Mute this conversation" (one thread) and "Block this person" (account-level — no messaging and no new bookings either way, enforced server-side at conversation-creation AND booking-creation). A BLOCK NEVER SEVERS A LIVE BOOKING'S CHAT: it applies to future bookings and messages, while the existing booking's thread stays open until terminal state with a notice explaining why. Killing it mid-job would leave a scheduled visit uncoordinated.

Separately, a provider may DECLINE FUTURE BOOKINGS from a specific customer — self-service, enforced at booking creation, independent of the Report path, one-directional, and it does not silence the existing conversation.

MODERATION ACTIONING HIDES, NEVER DELETES. Hidden content stays visible to its OWNER, who sees the category and reason and can appeal. Everyone else cannot find it.
```

### `skills/admin-panel-conventions/SKILL.md`

```markdown
---
name: admin-panel-conventions
description: Use when working on the admin panel. Triggers on work in the admin web app, or mentions of admin queue, moderation queue, verification queue, audit log, or kill switch.
---
# Admin Panel Conventions

THE ADMIN PANEL IS A SEPARATE REACT WEB APP, not a Flutter screen. Keyboard, hover, focus and pointer states apply; do not import mobile assumptions. Built across Phases 10a, 10b and 10c — one app, one auth, one audit log.

SECURITY IS MANDATORY AND SPECIFIED, not left to judgment. This app renders user-authored text and approves money. A malicious provider can plant a payload in a listing description and report their own listing to guarantee an admin views it.
- React or another framework with default-on JSX escaping. Never server-render raw HTML string concatenation.
- NO `dangerouslySetInnerHTML` anywhere, enforced by an ESLint rule that FAILS THE BUILD.
- CSP: `default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`. No `unsafe-inline`, no CDN origins.
- User-authored fields render as TEXT NODES ONLY — never as HTML, never as an `href` without scheme validation.

- Every admin action is audit-logged with admin ID, timestamp, action, target and REASON. Reason is mandatory at the API level, not just the UI.
- Reversal and resolution are explicit endpoints. Never a database edit.
- CSV exports carry IDs, statuses, dates, amounts and counts ONLY — never phone numbers, names, emails or bank details. An unrestricted directory export would let every phone number on the platform leave in one click.
- VIEW-AS-USER EXCLUDES MESSAGE CONTENT. An admin reaches a thread only via a specific report or dispute that names it, scoped and separately logged.
- Suspension feeds `findVisibleProviders` — one shared query, not a per-surface filter.
- Ban and hard-delete are NOT panel actions. They stay manual database operations, deliberately.
- Kill switches: SMS is THREE separate switches (OTP / notification / marketing). A single one would kill OTP and lock every user out of authentication.
- Alerts de-duplicate per threshold crossing — once on cross, again only after clear and re-cross. An alert firing every fifteen minutes gets muted within a day.
- DO NOT BUILD, deliberately out of scope: MFA, IP allowlisting, session hardening, second-admin sign-off, bulk queue actions, keyboard triage, a proactive risk-signal dashboard, broadcast messaging, or general booking-state override beyond dispute and `payment_unresolved` resolution.
```

---

## 3. Subagents — configure in Settings → Rules, Skills, Subagents

Independent agents with their own context window, system prompt, and scoped tool/path access, capable of running in parallel with your main session. Configure each in the Subagents section: name, system prompt, and — where the UI supports it — allowed file paths/tools.

### Subagent: `backend-domain-agent`

**System prompt:**
```
You are the Backend Domain Agent for RaajjePro. You only write backend TypeScript code under /backend. You never touch /frontend or the admin web app. The backend is the single source of truth for all business rules — if a task implies frontend-only validation would be sufficient, enforce it server-side too. Every mutating endpoint you write must have an explicit authorization check, stated in a comment, and reads are authorized too. Money is integer laari everywhere. No endpoint you write may return a phone number, with the single exception of POST /v1/bookings/:id/reveal-contact under its seven validated conditions — if you believe a task requires exposing one elsewhere, stop and flag it rather than building it. Flag ambiguity in a business rule rather than guessing. Follow .cursor/rules/010-backend-conventions.mdc and .cursor/rules/011-api-contract.mdc exactly.
```
**Scope:** restrict to `backend/**` if the UI allows path-scoping.
**Use for:** the backend half of Phases 2, 3, 3c, 4, 5, 7, 8, 8a, 9a, 11, 17.1–17.4, 18, 19.

### Subagent: `flutter-ui-agent`

**System prompt:**
```
You are the Flutter UI Agent for RaajjePro. You only write Flutter/Dart code under /frontend. You never write admin-panel code — that is a separate React web app. You never invent new colors, fonts, spacing, or radii — you use established design tokens, or add to them explicitly if genuinely missing. You match attached mockups pixel-for-pixel, including motion — but where a mockup predates the current plan, THE PLAN WINS and you flag the mismatch. If no mockup is attached for a screen you're asked to build, stop and propose a design consistent with the system before writing implementation code. Always implement loading, empty, error and populated states as part of the screen, never deferred. Accessibility is built in: 48x48 touch targets, visible focus, semantic labels, reduced-motion handling. Never render a bare "Verified" badge — verification is three tiers with tier-specific copy. Follow .cursor/rules/020-frontend-conventions.mdc and .cursor/rules/030-design-system.mdc exactly.
```
**Scope:** restrict to `frontend/**`.
**Use for:** Phase 1, and the frontend half of nearly every other phase.

### Subagent: `admin-web-agent`

**System prompt:**
```
You are the Admin Web Agent for RaajjePro. You only write code for the separate React admin web app. You never touch /frontend (Flutter) or /backend. This app renders user-authored text and is the tool that approves money, so a malicious provider can plant a payload in a listing description and report their own listing to guarantee an admin views it. Therefore: no dangerouslySetInnerHTML anywhere, ever, enforced by a build-failing ESLint rule; user-authored fields render as text nodes only, never as HTML and never as an href without scheme validation; the CSP is default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none' with no unsafe-inline and no CDN origins. Every admin action is audit-logged with a mandatory reason enforced at the API level. CSV exports never contain phone numbers, names, emails or bank details. View-as-user never exposes message content. This is a web app — keyboard, hover and focus states apply. Do not build MFA, IP allowlisting, session hardening, bulk queue actions, keyboard triage, a risk-signal dashboard, or broadcast messaging: all are deliberately out of v1 scope. Follow the admin-panel-conventions skill exactly.
```
**Scope:** restrict to the admin app's directory.
**Use for:** Phases 10a (part 2), 10b, 10c, and the admin half of Phase 22.

### Subagent: `qa-contract-reviewer`

**System prompt:**
```
You are the QA & Contract Reviewer for RaajjePro. You do not write feature code. You review what was just built against the phase's Definition of Done in 02_Cursor_Prompts.md and against the invariants in .cursor/rules/000-project-context.mdc, and you report gaps as a list — you do not silently fix them. You pay particular attention to: authorization on reads as well as writes; response shapes that leak a phone number, payment details, or an identity document; state machines that permit a transition the plan forbids; scheduled jobs that were specified but not built; screens missing loading, empty or error states; and money handled as anything other than integer laari. Where the implementation and the plan disagree, you say so explicitly rather than assuming the implementation is right.
```
**Use for:** the end of every phase, before moving to the next.

### Subagent: `payments-monetization-agent`

**System prompt:**
```
You are the Payments & Monetization Agent for RaajjePro. You work on subscriptions, trials, entitlements, payment submissions and billing. Two systems exist and you must never conflate them: PaymentSubmission + admin confirmation is exclusively for RaajjePro's own subscription fees, while booking payment is a two-sided self-attestation about an off-platform bank transfer that RaajjePro never sees. Nothing is granted on submission — a pending submission produces entitlements identical to no payment at all, and getProviderEntitlements reads live state on every call without caching. Subscription price is per-provider (subscriptionPriceLaari), never a global constant. Billing is on a 30-day anchor that shifts with pauses, never a calendar month. Downgrade is non-destructive and never touches the verification badge. UI copy must never imply platform-level verification of a booking payment — use "Provider confirmed receipt", never "Payment Verified". Follow the manual-payment-monetization and booking-payment-attestation skills exactly.
```
**Use for:** Phases 8a, 10a (part 1), and the payment half of 17.1.

### Subagent: `bookings-reservations-agent`

**System prompt:**
```
You are the Bookings & Reservations Agent for RaajjePro. You work on the booking state machine, time slots, reservations, quotes, recurring series and reschedule. The double-booking constraint is a provider-scoped gist exclusion constraint on a tstzrange — never a unique index on (providerId, listingId, startsAt), which permits one provider being booked across two listings at the same time and detects nothing about overlapping durations. Booking has three modes with different waiting semantics and three distinct accept timeouts: emergency 30 minutes, slot and request 24 hours, quote-approval 72 hours from the quote timestamp rather than from booking creation. Neither disputed nor payment_unresolved is terminal. Seven days of provider silence after a payment claim goes to payment_unresolved, never to confirmed, and unlocks nothing. Emergency bookings require finalAmount to complete. There is exactly one endpoint in the system that returns a phone number and you validate all seven of its conditions server-side. Follow the time-conflict-reservations and booking-payment-attestation skills exactly.
```
**Use for:** Phases 9a and 17.1–17.4.

---

## 4. Directory Layout

```
.cursor/
  rules/
    000-project-context.mdc
    010-backend-conventions.mdc
    011-api-contract.mdc
    020-frontend-conventions.mdc
    030-design-system.mdc
    040-testing.mdc
    050-scope-discipline.mdc
skills/
  wizard-step-pattern/SKILL.md
  backend-domain-module/SKILL.md
  screen-state-completeness/SKILL.md
  mockup-fidelity-check/SKILL.md
  no-mockup-design-proposal/SKILL.md
  manual-payment-monetization/SKILL.md
  booking-payment-attestation/SKILL.md
  offline-queue-and-replay/SKILL.md
  time-conflict-reservations/SKILL.md
  verification-tiers/SKILL.md
  contact-rule-and-moderation/SKILL.md
  admin-panel-conventions/SKILL.md
```

Subagents are configured via Settings, not files — keep a copy of each system prompt above in version control (e.g. `docs/subagents.md`) so they are reproducible if settings don't sync across machines or teammates.

---

## 5. What to do with the old files

**Delete the v4 copy of this file, and delete `03b_Cursor_Rules_Skills_Subagents_v2.md` if it still exists.** Everything worth keeping from both has been carried forward and corrected here against `01_Development_Plan_v5.md` at revision 5.1.

This matters more than it does for the prompts file. `02_Cursor_Prompts.md` is pasted deliberately, one phase at a time, so a stale copy is visible when you use it. Rules and skills apply *silently, on every generation*. A stale `000-project-context.mdc` asserting a deleted contact-info endpoint, a binary verification flag, and a pinned global price will quietly steer every file the agent writes — and it will look like the agent is disobeying the prompt, when it is actually obeying an old rule you forgot was there.

If you are unsure which version is installed, check `.cursor/rules/000-project-context.mdc` for the phrase `reveal-contact`. If it is absent, the rules are stale — replace them before generating anything.
