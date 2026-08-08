# RaajjePro — Cursor-Ready Prompts (v5.1)

**Regenerated against `01_Development_Plan_v5.md`** (Rounds 8 through 12 folded in). The previous version of this file targeted **v4** and is now actively wrong in ways Cursor will enforce against you. Delete it. The four differences that matter most:

- **v4 had a contact-info unlock.** `GET /v1/bookings/:id/contact-info` and the whole unlock-at-`payment_claimed` mechanism are gone. Phone numbers are exchanged through exactly **one** endpoint, `POST /v1/bookings/:id/reveal-contact`, emergency bookings only, under seven conditions. Every other endpoint returning a phone number is a defect.
- **v4 had a binary verified badge.** Verification is now three tiers — Bronze, Silver, Gold (§1e). Emergency capability requires **Silver or above**, not "verified".
- **v4 had no provider onboarding screen** and said so explicitly. Phase 6a is now a real flow, sequenced before the wizard.
- **v4 had one admin panel phase.** It is now three: 10a (money and identity queues), 10b (accounts, config, search, shell), 10c (ops dashboard).

## How to use this file

1. Work top to bottom. Don't start phase N+1 until phase N's Definition of Done is met.
2. Before pasting anything, make sure `.cursor/rules/` and `skills/` (from `03_Cursor_Rules_Skills_Subagents.md` **v5.1**) are in the repo. Every prompt below assumes those are active. **If you still have v4 or earlier rules in place, replace them first** — they assert a contact-info endpoint this plan deleted, a binary `verificationStatus` it replaced, and a pinned global subscription price it made per-provider. Rules auto-apply on every generation, so a stale one fights you silently.
3. Paste each prompt into a **fresh Cursor chat/composer session**. Don't chain phases in one thread.
4. Where a prompt says "no mockup yet — propose a design," Cursor stops and shows you the layout before writing implementation code.
5. Attach the relevant mockup image(s) for any prompt that references one.
6. **Every frontend phase must specify its loading, empty, error and populated states as part of its own Definition of Done** (plan §3 preamble). Phase 20's state audit is a backstop, not the first time these get designed.

## Phase order

`0 → 1 → 2 → 3 → 3b → 3c → 4 → 5 → 6 → 6a → 7 → 8 → 8a → 9 → 9a → 10 → 10a → 10b → 11 → 12 → 13 → 14 → 15 → 16 → 17.1 → 17.2 → 17.3 → 17.4 → 18 → 19 → 20 → 21 → 10c → 22 → 23 → 24`

**New since v4:** Phase 6a (Become a Provider onboarding), Phase 10b (admin accounts/config/search/shell), Phase 10c (admin ops dashboard — sequenced after Phase 21 because its trend lines read the ProductEvent log).

**Removed from the pre-v4 sequence:** Phase 8b (credit wallet), Phase 8c (advertising), Phase 17a (completion-based trial trigger). All deferred to post-v1 or deleted outright — see plan §6.

**Run in parallel, not in sequence:** Phase 23's data-protection and identity-document research gates Phases 5 and 1e directly. Start it when you start Phase 5, not when you reach Phase 23.


---

## Phase 0 — Repository & Environment Foundation

```
Set up the RaajjePro monorepo foundation. Infrastructure only — no business logic, no UI beyond a placeholder screen.

Context: RaajjePro is a Local Service Marketplace (Maldives). Stack: TypeScript backend (Fastify + Prisma + PostgreSQL), Flutter frontend (mobile-first). Read .cursor/rules/ fully before writing anything.

Do:
1. Create /backend and /frontend as siblings in the repo root.
2. /backend: TypeScript strict mode, Fastify entrypoint, folders by domain module (identity, users, providers, listings, categories, service-areas, bookings, reservations, payments, verification, reviews, notifications, push, media, messaging, search, moderation, admin). Empty module folders are fine — establish the pattern with one working example.
3. /frontend: standard Flutter project, feature-based structure (lib/features/<feature>, lib/core, lib/shared), Riverpod as the state management dependency.
4. ESLint + Prettier on backend; `flutter analyze`-clean lint config on frontend. Commit hooks running both.
5. Wire up a job runner (pg_cron or equivalent) with ONE no-op scheduled job that observably fires. The plan depends on time-based transitions in seven places (three distinct accept timeouts, quote expiry, payment escalation, completion checks, trial/subscription lifecycle, slot regeneration) — a working runner is a Phase 0 deliverable, not something to discover you need at Phase 17.
6. Root README documenting the five conventions every later phase assumes: UUID primary keys on every entity; integer-laari money (MVR × 100, never float or decimal-string); soft-delete everywhere (visibility/status field, nothing hard-deleted); client-supplied idempotency keys on money-adjacent and creation POSTs; and additive-only API evolution within /v1 — never remove or repurpose a field, because mobile clients cannot be force-updated and a breaking change strands installed app versions.
7. Minimal CI (GitHub Actions is fine) running lint + build on both apps on push. No deployment yet.
8. .env.example covering DB connection, JWT secrets, object storage (TWO buckets — media, and a separate private bucket for identity documents), email provider (transactional, load-bearing) and push (FCM/APNs) placeholders — NO SMS provider, deliberately. No real secrets committed.

Do NOT: add business entities, real screens beyond a placeholder splash route, or auth logic.

Definition of done: `npm install && npm run build` succeeds in /backend, `flutter pub get && flutter analyze` is clean in /frontend, both apps boot, and the scheduled no-op job is observably firing on its interval.
```

---

## Phase 1 — Design System & Shared UI Foundation (Flutter)

```
Build the RaajjePro Flutter design system as reusable, documented widgets. No real screens — build a "component gallery" debug route rendering every widget with sample data.

Derive tokens from the attached mockups: color palette, typography scale, spacing scale, corner radii, elevation. Do not invent a new visual language; extract what the mockups already use.

Build:
1. Tokens: colors, text styles, spacing, radii, shadows — as a Theme extension, not scattered constants.
2. Buttons: primary, secondary, text, destructive. Each with EXPLICIT pressed, disabled, and loading states. A button that triggers a network call must show its own loading state rather than a page-level spinner.
3. Inputs: text field, password field with show/hide, search field, dropdown, multi-select, toggle, checkbox, radio, stepper. Each with normal, focused, error, and disabled states, and inline error text beneath rather than a toast.
4. Cards: listing card, provider card, booking card, review card, notification row.
5. Feedback: toast/snackbar, inline banner (info/warning/error/success), confirmation dialog, bottom sheet.
6. State widgets — these are used by every later phase and must exist now: skeleton loader (shimmer), empty state (icon + headline + body + optional action), error state (message + retry), and an offline banner.
7. Status chips: booking statuses, verification tier badges (Bronze/Silver/Gold — three distinct treatments, see plan §1e for the exact public copy each carries), and listing visibility states.
8. Layout scaffolds: app bar variants, bottom nav, section header.

Accessibility is part of this phase, not a later pass: every interactive widget has a minimum 48x48 touch target, a visible focus state, a semantic label, and respects reduced-motion (shimmer and transitions degrade to static/instant when the OS flag is set).

Do NOT build screens, routing, or API calls.

Definition of done: the component gallery route renders every widget in every state; toggling the OS reduced-motion setting visibly disables shimmer and transition animation; a screen reader announces each interactive widget meaningfully.
```
*(Attach: all available mockups, for token extraction)*

---

## Phase 2 — Backend Core Infrastructure

```
Build the RaajjePro backend's shared infrastructure. No business domains yet — this is what every later module depends on.

1. Fastify app factory, config loading with schema validation (fail fast on a missing env var, never at first use), structured logging with request IDs.
2. Prisma set up against PostgreSQL. UUID primary keys by default. One trivial entity to prove migrations run.
3. STANDARD RESPONSE ENVELOPE — every endpoint, success and failure, uses it. Errors carry a stable machine-readable `code`, a human-readable `message`, and optional `details`. Frontend routing depends on distinguishing codes, so never return a bare string.
4. Zod validation middleware. A malformed request returns 400 in the standard envelope, never a stack trace.
5. RATE LIMITING — global default plus per-endpoint tiers, stricter on auth, OTP, payment, emergency-booking, and MESSAGING endpoints. Messaging carries its own per-conversation and per-user tier: the enquiry channel's content policy is deliberately permissive, so an uncapped-volume channel with only after-the-fact block-and-report is a real spam and harassment surface. Build the tier mechanism now; later phases attach their limits.
6. IDEMPOTENCY — a reusable middleware keyed on (userId, operation, client-supplied key), returning the ORIGINAL result on a repeat rather than re-executing. Money-adjacent and creation POSTs use it from Phase 8 onward.
7. ADMIN IDENTITY MODEL — a real one, not a stub. Admin users, a single `admin` role for v1, login, session.
   TOTP MFA IS MANDATORY on every admin account (Round 12) — authenticator app, NOT SMS, because there is no SMS in this system. Enrolment is required before the account can take any action, with recovery codes issued once at enrolment.
   SESSION CONTROLS: active-session list with force-logout, a short idle timeout, and re-authentication before viewing an identity document.
   IP ALLOWLISTING remains deliberately out of scope — it locks the admin out when travelling. Do not add it and do not leave a TODO implying it is coming.
8. AUDIT LOG — every admin action records admin ID, timestamp, action, target, and reason. Queryable by date, admin, and action type. This is not optional logging: several later phases require the reason field to be mandatory at the API level.
9. API VERSIONING POLICY, written into the README: additive-only within /v1. Never remove or repurpose a field. Document the deprecation process before the first breaking change is needed, not after.
10. /v1/health returning 200 with build info.

Definition of done: /v1/health returns 200; a malformed request returns the standard envelope with a stable code; a repeated idempotent POST returns the original result rather than executing twice; rate limits trigger and return the correct code; an admin action appears in the queryable audit log with its reason.
```

---

## Phase 3 — Identity & Authentication

```
Build the Identity & Authentication module, backend and frontend, matching the attached Login and Register mockups exactly.

Backend:
1. User entity: id, full name, email (UNIQUE), emailVerified flag, phone (UNIQUE, and deliberately NOT verified), password hash, createdAt. Provider status is a SEPARATE ProviderProfile entity built in Phase 5 — do not merge provider fields into User.
2. POST /v1/auth/register — validates name, email, phone, password (min 8), terms acceptance. bcrypt or argon2, never custom hashing.
3. POST /v1/auth/login — short-lived JWT access token + longer-lived refresh token, rotated on use.
4. POST /v1/auth/refresh, POST /v1/auth/logout, GET /v1/auth/me.
5. Refresh tokens are PER-DEVICE, so revoking one device does not log out the others. Required by the session-management screen below — build the token model that way from the start.
6. Social auth: a provider-agnostic SocialAuthProvider interface with stubs (Facebook/Google/Viber) returning "not yet configured". Establish the seam; do not fake an OAuth flow.
7. EMAIL VERIFICATION — THERE IS NO SMS ANYWHERE IN THIS SYSTEM. Older documentation described SMS OTP, an SmsSender interface, and a phoneVerified flag. All of it is removed. Do not build an SmsSender. Do not integrate an SMS vendor.
   POST /v1/auth/email/send-otp, POST /v1/auth/email/verify-otp. Provider-agnostic EmailSender interface with a dev stub logging the OTP. Build the real state machine (generation, expiry, attempt limiting); only delivery is stubbed.
8. RATE LIMITS, EXACT — implement all three, not one of them:
   - 3 OTP sends per email address per 15 minutes
   - 5 OTP sends per user account per hour
   - 5 verification attempts per issued OTP, after which that OTP is invalidated and a new send is required
   Hitting a send limit returns error code OTP_RATE_LIMITED with the seconds remaining, so the UI can render a real countdown rather than a generic failure.
9. PHONE IS UNIQUE BUT UNVERIFIED. Put a database-level unique constraint on BOTH email and phone. A registration attempt against an in-use email OR an in-use phone is BLOCKED AT THE FIELD, naming which one is taken, offering login or password reset — never a generic error, never a silent overwrite.
   UNIQUENESS IS NOT OWNERSHIP. Nothing proves the number belongs to whoever typed it, because the mechanism that proved it is gone. Never render a phone number with a check mark and never describe it as verified anywhere in the UI or the API.
10. ACCOUNT RECOVERY — email is now the primary credential, so recovery runs through MANUAL ADMIN REVIEW against the account record and identity evidence. Build the request and queue path; the admin side lands in Phase 10b. The same queue also handles two problems the unique-phone constraint creates: SQUATTING (someone registers with a number they do not own, permanently blocking the real holder, who has no self-serve proof) and NUMBER RECYCLING (a reassigned Maldivian number stays locked to a dormant account). Both are resolved by an admin releasing the number.
11. `requireAuth` guard. Then a stricter `requireEmailVerified` guard composing it and additionally checking emailVerified, rejecting with a DISTINCT error code (EMAIL_NOT_VERIFIED) so the frontend routes to verification specifically rather than showing a generic auth error. THIS REPLACES requirePhoneVerified EVERYWHERE — Phases 17 and 18 gate booking, enquiry and messaging on it. If you see requirePhoneVerified in older documentation, it is obsolete.
12. Account settings: change password / change email / change phone (each re-verified); active session list + revoke per device; GET /v1/users/me/data-export returning the user's own data as JSON; account deletion.
13. ACCOUNT DELETION SEMANTICS — App Store requires this, and the semantics changed in v5.1. Anonymise all authored content: name/email/phone replaced with a placeholder, listings and reviews PRESERVED so provider rating aggregates stay intact. Soft-delete, not purge. Identity documents are PURGED, not anonymised. Two additions:
    - REVIEW AUTHORSHIP IS RETAINED INTERNALLY — never shown publicly, never returned in any response, but preserved so a review disputed later can still be traced. Without it a customer can post a fabricated review, delete their account, and sever the accountability trail by design.
    - ADMIN INTERNAL NOTES about the user (Phase 10b) are deleted with the account. Only the audit log's structured reason fields persist.
14. DELETION IS QUEUED, NEVER REFUSED. A deletion request is ACCEPTED IMMEDIATELY and the account frozen (no new bookings, no new listings, excluded from search). Anonymisation executes automatically once every non-terminal booking reaches a terminal state, with a HARD 30-DAY BACKSTOP after which it proceeds regardless. Do not implement this as an error when bookings are open: `payment_unresolved` only clears when a human acts, so refusing could block a user indefinitely on admin inaction, and both app stores require in-app deletion to actually work.

Frontend:
1. Login screen — pixel-match Login.png: gradient header banner, "Welcome back", email field, password with show/hide, "Remember me", "Forgot password?" (route stub, Phase 3b), Sign In, "or continue with" divider, social row (show a "coming soon" state on tap, never fake success), "Create an account" link.
2. Register screen — pixel-match Register.png: same header, Full Name, Email + Phone side by side, Password + Confirm with show/hide, terms checkbox with linked ToS/Privacy route stubs, Create Account, same social row.
3. Email verification screen — no mockup exists. Propose a minimal design (OTP input, resend with a cooldown driven by the real OTP_RATE_LIMITED seconds-remaining value, matching the established input/button language) before implementing. Triggered right after registration. Include a "check your spam folder" hint — email OTP has a delivery failure mode SMS did not.
4. Wire both screens to real endpoints. Display real validation errors INLINE, not as generic toasts — "email already registered", "passwords don't match", "password too short".
5. Store tokens with flutter_secure_storage or equivalent; silent refresh; redirect to Home on success. A user reaches Home and browses WITHOUT completing phone verification — it is enforced later at booking/enquiry/messaging, never at login.
6. Account settings sub-screens — propose designs before implementing. The deletion screen must state plainly what queued deletion means: the account is frozen now, remaining bookings finish, deletion completes automatically. Never present it as a refusal.

Every screen above specifies its loading, empty, error and populated states as part of this phase, not Phase 20.

Definition of done: register → verify → logout → login works end to end; wrong password and duplicate email show correct inline errors; token refresh works without forcing re-login; an unverified user browses Home/Explore normally but is rejected with EMAIL_NOT_VERIFIED against a temporary protected test route, and passes it after completing OTP; registering with an already-used email is blocked naming the email, and with an already-used phone is blocked naming the phone, each offering login or reset; all three OTP rate limits are verified independently; no phone number is described as verified anywhere in the UI or API; an email confirmation link verifies, and a recovery attempt without a verified email is refused; revoking one device's session leaves other devices logged in; a deletion request with an open booking is ACCEPTED and freezes the account rather than erroring, completes automatically when that booking terminates, and completes anyway at the 30-day backstop; a deleted account's reviews remain with anonymised attribution, the aggregate rating is unchanged, and internal authorship is still resolvable by a direct query.
```
*(Attach: Login.png, Register.png)*

---

## Phase 3b — Forgot Password Flow

```
Build the forgot-password flow, backend and frontend. No mockup exists — propose the screens before implementing, reusing Phase 1's input and button language exactly.

Backend:
1. POST /v1/auth/password/forgot — accepts email. ALWAYS returns success regardless of whether the account exists; never confirm or deny an email's existence.
2. Single-use, time-limited reset token (60 minutes), invalidated on use and on password change.
3. POST /v1/auth/password/reset — token + new password. On success, REVOKE ALL refresh tokens for that user across every device: a password reset is the action someone takes when they believe they are compromised.
4. Rate limit reset requests per email and per IP.

Frontend:
1. Request screen: email field, submit, and a confirmation state that says an email has been sent IF the account exists — matching the non-enumerating backend rather than implying the address was found.
2. Reset screen reached from the emailed link: new password + confirm, with the same strength rules and inline errors as Register.
3. An expired or already-used token shows a specific, recoverable message with a path back to request a new one — never a dead end.

Specify loading, empty, error and populated states for both screens as part of this phase.

Definition of done: the full request → email → reset → login-with-new-password cycle works; a reused token is rejected with a recoverable message; resetting logs out every other device; requesting a reset for a non-existent email is indistinguishable from a real one.
```

---

## Phase 3c — Push Notification Infrastructure

```
Build push notification DELIVERY infrastructure. Notification CONTENT and types come later in Phase 19 — this phase is the transport and its fallback chain.

This phase is deliberately sequenced ahead of Phases 9a and 17, which depend on it. Phase 17's provider accept prompt is load-bearing on real-time delivery and must not wait on infrastructure built after it.

1. FCM + APNs integration behind a single provider-agnostic PushSender interface. Device token registration and de-registration, multiple devices per user, stale-token pruning on delivery rejection.
2. TWO-RUNG FALLBACK — push → email. THERE IS NO SMS RUNG; older documentation described push → SMS → email and is obsolete. If push permission is ALREADY KNOWN DENIED, send email IMMEDIATELY in parallel with the futile push attempt — do not wait. If push is permitted but delivery is unconfirmed after 30 MINUTES, send email.
3. EMERGENCY PROMPTS SEND EMAIL UNCONDITIONALLY, in parallel with push, not just on push failure — a 30-minute response window cannot absorb a silent push failure.
   EMAIL IS NOW THE ONLY CHANNEL THAT WORKS WHEN PUSH FAILS, so its deliverability is load-bearing: bounce and complaint handling and a monitored sending reputation are part of this phase, not an afterthought.
4. Delivery observability from day one: record attempt, channel used, and outcome per notification. Phase 21 alerts on a fallback-invocation rate above 5%.
5. NO IN-APP TOGGLE FOR BOOKING NOTIFICATIONS. Do not build a notification-preferences screen for transactional sends; they always deliver. Marketing and digest sends remain opt-in.
   BE HONEST ABOUT WHAT THIS CAN ENFORCE: iOS and Android both let a user revoke notification permission at the OS level and no app can override that. "Always enabled" means only that we ship no switch — the OS-denied case is exactly what the email fallback covers. Do not attempt to block app usage on denied permission.
6. EMAIL is three separately controllable channels, not one: OTP email, notification/fallback email, and marketing email. Phase 10b attaches kill switches to each independently. Do NOT build a single global email toggle — it would take down authentication, since email is now the ONLY OTP channel and the only fallback.

Frontend: permission request at a moment that explains why it is being asked (not on first launch, cold); graceful handling of an OS-denied permission with an in-app explanation that email will be used instead, plus a persistent reminder that the provider may miss booking requests; deep-link handling from a tapped notification into the right screen.

Definition of done: a push delivers to a real device; disabling push at the OS level causes an EMAIL fallback immediately, not at the end of the window; an emergency prompt sends email even when push succeeds; the app exposes no toggle for booking notifications; delivery outcomes and bounces are recorded per channel; killing the notification-email channel leaves OTP email working.
```

---

## Phase 4 — Categories Module

```
Build the Categories module, backend and frontend, matching the attached Explore mockup exactly.

1. Category entity: id, name, slug, icon reference, sortOrder, active flag, and THREE fields later phases read as defaults:
   - bookingMode: enum ('slot' | 'request') — how customers book in this category
   - emergencyCapable: boolean — whether listings here may offer emergency bookings AT ALL
   - minimumLeadTimeMinutes: integer — how far ahead a slot must be to remain bookable
   - emergencyAcceptWindowMinutes: integer or null — how long an emergency request stays open before auto-declining
2. SEED EXACTLY 12 CATEGORIES, in this order, with these values. The mockup's grid is 3 columns × 4 rows and the count matters:
   Cleaning (slot, not emergency) · Plumbing (request, EMERGENCY) · Electrical (request, EMERGENCY) · AC Repair (request, EMERGENCY) · Beauty (slot, not emergency) · Photography (request, not emergency) · Gardening (request, not emergency) · Computer (request, not emergency) · Moving (request, not emergency) · Fitness (slot, not emergency) · Events (request, not emergency) · Boat Charter (request, not emergency)
   Set a sensible minimumLeadTimeMinutes per category — the value differs by trade and is configurable, so do not hardcode one number globally.
3. ONLY Plumbing, Electrical, AC Repair and MOVING are emergencyCapable. Moving was added in Round 12. This is a safety decision, not configuration: the admin panel (Phase 10b) can edit category names, icons, lead times and active flags, but NOT this flag and NOT bookingMode while live data exists. Enforce at the service layer.
3b. emergencyAcceptWindowMinutes per category: 30 for Plumbing, Electrical and AC Repair; 120 for MOVING; null where not emergency-capable. A mover needs a vehicle and usually a crew, so the 30-minute figure set for a tradesperson with hand tools does not transfer.
4. GET /v1/categories (active only, sorted), GET /v1/categories/:slug.
5. Admin-only POST/PATCH/DELETE against REAL admin auth from Phase 2 — not a stub, not an open endpoint.
6. Deactivating a category never deletes it and never orphans listings; existing listings keep working.

Frontend:
1. Explore screen — pixel-match the attached mockup: 3-column icon grid, 12 items, category names beneath.
2. Tapping a category routes to category results (Phase 15 builds the results themselves — route stub for now).
3. Loading state uses Phase 1's skeleton; a category with no listings yet is handled in Phase 15, not here.

Definition of done: all 12 categories render in the mockup's grid exactly; the API returns them sorted; a non-admin token is rejected from every write endpoint; attempting to set emergencyCapable on a fourth category fails at the service layer.
```
*(Attach: Explore.png)*

---

## Phase 5 — Provider Profiles

```
Build the Provider Profiles backend module. BACKEND-ONLY — no Flutter code. ProviderProfile is a distinct domain entity from User; never merge provider fields into the User table.

CRITICAL — read before designing the schema.

(a) PUBLIC VISIBILITY IS DERIVED, NEVER STORED. An earlier revision had a stored `lifecycleStatus` flipped one-way on first publish. It drifts: a provider who unpublishes their only listing stays 'active' forever with an empty public profile. Do not add such a field. If you have seen one in older project documentation, it is obsolete.

(b) THERE IS NO CONTACT-INFO ENDPOINT IN THIS MODULE OR ANY OTHER. Older documentation described whatsappHandle and viberHandle fields and a GET /v1/bookings/:id/contact-info endpoint. All of it is deleted. Do not create those fields. Do not create that endpoint.

1. ProviderProfile entity: id, userId (FK, one-to-one), businessName (optional), bio, yearsOfExperience, createdAt, and:
   - verificationTier: enum ('none' | 'bronze' | 'silver' | 'gold'). This is what the badge renders and what other systems gate on. Admin-transitioned, except the auto-granted Silver route built in Phase 10a.
   - verificationStatus: enum ('unverified' | 'pending' | 'verified') — the REVIEW state of a pending submission, NOT the badge. Both fields exist; they are not the same axis.
   - subscriptionPriceLaari: integer — the provider's own subscription price, set at first confirmed payment (Phase 8a). Never read a global price constant.
   - jobsCompletedCount: DERIVED from the booking event log, never a hand-maintained counter that can drift. Document your approach.
   - suspendedAt / suspendedReason: set by admin (Phase 10b), and an INPUT TO VISIBILITY — see item 6.
2. CONTACT DETAIL — phone number only, and it lives on User from Phase 3. Do not duplicate it here and do not add messaging-app handles. The phone number is returned to another user by EXACTLY ONE endpoint in the entire system, built in Phase 17.3: POST /v1/bookings/:id/reveal-contact, emergency bookings only, under seven conditions. Nothing in this module exposes it.
3. PAYMENT DETAILS — load-bearing, and no earlier phase creates them: bank name, account name, account number, and/or free-text transfer instructions. Phase 17's payment prompt displays these to the customer, because the off-platform transfer cannot happen without them. Treat as SENSITIVE: excluded from every response except the booking-scoped payment step, and excluded from all logs. Write the DTO mapping so this is structurally enforced, not remembered.
4. acceptingNewCustomers — a boolean at PROVIDER level, not on the Listing entity. One toggle gates all of a provider's listings, and Phase 8a's billing pause keys off it coherently.
5. getOrCreateProviderProfile(userId) — idempotent. Returns the existing profile or creates one. Called by Phase 6a's onboarding flow, and as a fallback by Phase 8's draft-creation endpoint for anyone who reaches the wizard without it. Export it.
6. findVisibleProviders(...) — THE single shared gate used by Featured Providers, search, and the public profile endpoint. A provider is visible if and only if count(listings WHERE status='published' AND visibility='active') > 0 AND the provider is not suspended. BOTH conditions. Without the suspension check, a suspended provider stays listed and apparently bookable, and rejection happens only server-side after the customer has already committed.
7. GET /v1/providers/me (404 if none), PATCH /v1/providers/me (cannot modify verificationTier, verificationStatus, subscriptionPriceLaari or suspension — those transition only through admin paths).
8. Read the per-category bookingMode and minimumLeadTimeMinutes defaults from Phase 4's seed and expose them — Phases 8 and 9a consume them.

Definition of done: getOrCreateProviderProfile called twice for one user returns the same row (proven by test); findVisibleProviders EXCLUDES a provider whose only listing is a draft and INCLUDES them the instant one is published, with no stored status field involved; the SAME function excludes a suspended provider from search, Home and the public profile in one test; unpublishing makes them invisible again immediately; payment details are absent from every response this module exposes; grep the module for "whatsapp", "viber" and "contact-info" and find nothing.
```

---

## Phase 6 — Customer Profile Module

```
Build the Customer Profile module, pixel-matching the attached Profile mockup.

1. GET /v1/users/me/profile-summary — ONE call populating the whole screen. Do not make the Profile screen fan out to five endpoints.
2. PATCH /v1/users/me.
3. Frontend: Profile screen pixel-matching the mockup, five rows navigating to sub-screens (route stubs where the target phase has not landed).
4. ROLE SWITCHER — an explicit customer ⇄ provider mode control. Providers are the only paying users; their workspace must not be buried. Propose the switcher's placement and the resulting provider-mode IA before implementing. This is the one navigation change that departs from the original mockups, so show it before building it.
5. ROUTING RULE: switching to provider mode for the FIRST time routes into Phase 6a's onboarding flow, never straight to the dashboard. A returning provider goes straight to My Services Dashboard. A provider mid-onboarding resumes where they left off.

Specify loading, empty, error and populated states for the Profile screen as part of this phase.

Definition of done: Profile reflects live data from one call; every row navigates; switching to provider mode for the first time reaches the onboarding flow, and reaches My Services Dashboard directly on every subsequent switch.
```
*(Attach: Profile.png)*

---

## Phase 6a — Become a Provider: Onboarding Flow

```
Build the "Become a Provider" onboarding flow in Flutter. NEW in v5 — earlier project documentation stated there was no separate onboarding screen and that the Create/Edit Service Wizard WAS onboarding. That is obsolete. Ignore it.

No mockup exists. Propose a design before implementing — 2 to 3 screens reusing the established system from Phase 1, not a new visual language.

Screen 1 — Intro. What being a provider on RaajjePro means, in plain terms: publish a service, get bookings, get paid directly by the customer, communicate entirely through the app. Subscription and monetization stay INVISIBLE here — that is Phase 8a/10a's job, later. A single CTA into the next step.
  - Include a "Not right now" action that returns the user to customer mode cleanly, leaving NO orphaned draft and NO resume prompt nagging them from the role switcher. Resume-where-you-left-off is correct for someone who intends to finish; it is wrong for someone who read what was involved and decided against it. Choosing to start again later begins fresh.

Screen 2 — Account details. Collects what Phase 5 needs before a listing can meaningfully exist:
  - phone number, pre-filled from Phase 3's verified number and CONFIRMED rather than re-typed
  - VERIFIED EMAIL — required to complete onboarding (Phase 3 built the confirmation flow). If not yet verified, this step blocks on it with a resend action.
  - payment/bank transfer details
  - acceptingNewCustomers toggle, defaulted on
  Calls getOrCreateProviderProfile, then PATCH /v1/providers/me. REUSE Phase 5's existing update endpoint; do not create a parallel one.

Screen 3 — Hand off directly into the Phase 9 wizard's Step 1 with a fresh draft, so the very next thing the provider does is describe their first service.

A provider who abandons after step 1 or 2 and returns later resumes from where they left off, reusing Phase 9's resume-a-draft pattern one level earlier in the funnel.

Specify loading, empty, error and populated states as part of this phase — including the state where email verification is pending.

Definition of done: a brand-new user reaching this via Home's "Become a Provider" CTA or Phase 6's role switcher lands on the intro screen, NOT the wizard; "Not right now" returns to customer mode with no draft created and no resume prompt appearing afterward; completing account details persists phone, email and payment details via the existing Phase 5 endpoint; onboarding cannot complete without a verified email; the flow hands off into a fresh wizard draft; a provider who already completed onboarding never sees it again.
```

---

## Phase 7 — Service Areas & Location Module

```
Build the Service Areas & Location module.

1. Island reference data — seed a REAL list of Maldivian islands, not five placeholder entries. Later phases' search and filtering are only meaningful against real data.
2. ProviderServiceArea join table (providerId, islandId).
3. POST /v1/providers/me/service-areas, DELETE /v1/providers/me/service-areas/:id, GET /v1/islands?search=.
4. Frontend: a searchable island multi-select as a REUSABLE WIDGET. Build it standalone, not screen-specific — Phase 9's wizard Location step imports this exact widget rather than rebuilding it.
5. Header location bottom sheet: lets a customer pick a browsing island, persisted for the session.

Specify loading, empty (no search results), and error states for the multi-select as part of this phase.

Definition of done: the multi-select works standalone against real API data; typing filters correctly against the real island list; the header bottom sheet sets a browsing island that persists across screens for the session.
```

---

## Phase 8 — Service Listings: Backend Domain

```
Build the Service Listings backend domain. BACKEND-ONLY — Phase 9 builds the wizard UI against it.

1. Listing entity: id, providerId, categoryId, name, shortDescription, longDescription, pricingModel enum (fixed/hourly/daily/range/quote), price fields (INTEGER LAARI, never float), coverImage, gallery, status enum ('draft' | 'published'), visibility enum ('active' | 'hidden_over_cap' | 'hidden_suspended' | 'hidden_moderation'), bookingMode, isEmergency, createdAt, updatedAt.
2. bookingMode DEFAULTS from the listing's category (Phase 4 seed) and is OVERRIDABLE per listing. Store it on the listing; do not resolve it through the category at read time, or a later category edit would silently change how live listings behave.
3. EMERGENCY ELIGIBILITY — a listing may set isEmergency: true ONLY IF BOTH hold:
   - its category is emergencyCapable (Phase 4: Plumbing, Electrical, AC Repair and Moving)
   - the provider's verificationTier is 'silver' OR 'gold'
   NOTE: the bar is SILVER OR ABOVE, not "verified". Older documentation said verificationStatus === 'verified'; that is obsolete. Enforce on the publish path AND the update path, and re-check at booking creation in Phase 17.3, because a provider whose tier is later reduced must stop receiving emergency requests immediately.
4. REQUIRED TO PUBLISH — enforced server-side, not just in the wizard UI: name, category, at least one service area, pricing, and A COVER IMAGE. The cover image is required, not optional; a published listing with no cover renders as a broken card everywhere it appears.
5. Draft autosave endpoint: PATCH /v1/listings/:id accepting partial updates, so the wizard can save per-step.
6. POST /v1/listings requires a client-supplied IDEMPOTENCY KEY (Phase 2 middleware) — a retry on a flaky connection must not create orphan drafts.
7. Entitlement check on publish: count the provider's active published listings against getProviderEntitlements (Phase 8a). Over cap, reject with a SPECIFIC code the UI can route to billing, never a generic error.
8. Soft-delete only. A deleted listing's bookings, reviews and conversations survive per Phase 18 and 22's lifecycle rules.
9. GET /v1/listings/:id, GET /v1/providers/me/listings?status=.

Definition of done: a draft can be created and patched step by step; publish is REJECTED with distinct codes for each missing required field including the cover image; a provider at their listing cap gets the entitlement code, not a generic 400; a repeated POST with the same idempotency key returns the original listing rather than creating a second; isEmergency is rejected for a Bronze provider and accepted for a Silver one in the same category.
```

---

## Phase 8a — Subscription & Trial

```
Build the Subscription & Trial backend module. BACKEND-ONLY — Phase 10a builds the billing UI.

1. ProviderSubscription entity: providerId, tier, status ('trialing' | 'active' | 'free' | 'paused' | 'expired'), trialStartedAt, trialEndsAt, billingAnchorAt, currentPeriodEnd, pausedAt, cumulativePausedDays.
2. PRICE IS PER-PROVIDER, NOT GLOBAL. Read providerProfile.subscriptionPriceLaari, set at first confirmed payment, defaulting to MVR 150 = 15000 laari. The first 100 providers take a reduced introductory rate honoured for 12 MONTHS from the billing anchor, then converting to standard with 30 days' notice delivered through Phase 19. Do NOT hardcode a single global price — older documentation pinned one, and the conversion measurement depends on two real price points coexisting.
3. TRIAL STARTS ON WHICHEVER OF THREE TRIGGERS FIRES FIRST:
   - the transition of ANY booking into `confirmed` where this is the provider's first — HOOK ON THE STATE TRANSITION, NOT ON ONE ENDPOINT, so an admin resolving payment_unresolved to confirmed also fires it
   - POST /v1/providers/me/subscription/start-trial — an explicit provider-initiated "Try Premium"
   - a PROACTIVE prompt fired 7 days after the provider's first published listing if no booking has landed and no trial has started
   All three call the same startTrial(providerId), which is a no-op if a trial has ever run for that account. The third trigger matters because a new provider is capped at one listing and reaching `confirmed` takes days to weeks — without it the confirmed-booking trigger is close to decorative for exactly the provider it needs to reach.
4. Trial is 30 CALENDAR DAYS.
5. BILLING ANCHOR, NOT CALENDAR MONTH: 30-day periods from billingAnchorAt. PAUSING SHIFTS THE ANCHOR by the paused duration. Never imply month boundaries in data or copy — after a few pauses no two providers share an anchor.
6. PAUSE: capped at 10 CUMULATIVE days, keyed off the provider-level acceptingNewCustomers toggle. Resuming manually within the cap preserves the remaining allowance. At the cap, pause auto-ends and the clock forcibly resumes. ONE function shared by `trialing` and `active` — identical semantics, not two implementations.
7. getProviderEntitlements(providerId) — reads LIVE database state on every call, NEVER caches. A `pending` payment submission grants exactly nothing.
8. DOWNGRADE IS NON-DESTRUCTIVE AND REVERSIBLE. Listings over the free cap get visibility 'hidden_over_cap', never deleted. Analytics disable. THE BADGE IS UNAFFECTED — verification tier never depends on payment state. Any confirmed payment restores everything.
   - PROTECTED LISTINGS: a listing with a booking in accepted / awaiting_payment / payment_claimed / payment_unresolved / confirmed AND a future scheduledFor stays visible REGARDLESS of cap, until that booking reaches a terminal state.
   - Among UNPROTECTED listings, keep the HIGHEST-PERFORMING one visible: confirmed bookings over the trailing 90 days, falling back to views on a tie, and only to recency where neither exists. Older documentation said "most recently updated" — that was gameable by touching a listing, and is obsolete. The provider can override from the dashboard.
9. Scheduled jobs on Phase 0's runner (never check-on-read): 7-day-out warning, expiry → grace (7 days, nothing changes), grace → downgrade, win-back notifications at 7 and 30 days post-downgrade.
10. Trial abuse prevention: one trial per USER ACCOUNT, not per phone number — a provider who changes phone keeps their remaining trial.

Definition of done: a trial starts on first confirmed booking AND independently on an explicit request AND independently on the 7-day proactive prompt, and NEVER twice; an admin resolving payment_unresolved to confirmed fires the trial hook; pause behaves identically during trial and paid period and correctly shifts the billing anchor; hitting the pause cap forcibly resumes; a downgrade skips hiding any listing with a confirmed future booking and hides it the moment that booking completes; among unprotected listings the highest-booking-count one survives, not the most recently edited; a pending submission grants exactly nothing; two providers on different subscriptionPriceLaari values both bill correctly.
```

---

## Phase 9 — Create/Edit Service Wizard: Frontend

```
Build the 7-step Create/Edit Service Wizard in Flutter, pixel-matching the attached mockups, wired to Phase 8.

Global behavior:
- Step progress bar, 7 clickable pills (Details, Location, Pricing, Media, Availability, Extra Info, Review). Completed steps show a green check. The user navigates to ANY step at ANY time, including jumping straight to Review.
- PROGRESS FRAMING: show "N required fields left to publish" alongside or instead of "Step 1 of 7". Only five things are actually required; leading with the step count overstates the commitment.
- Sticky footer: Back + Continue on steps 1–6; Save Draft + Preview + Publish on step 7. "Draft" badge top-right at all times.
- OFFLINE RESILIENCE — this is the highest-value conversion flow in the app and must not silently lose work on a weak atoll connection: every step's autosave PATCH is queued locally on failure and replayed on reconnect, with a visible pending indicator. Phases 17 and 18 reuse this exact pattern, so build it as shared infrastructure, not wizard-local code.
- Before creating a NEW draft, check entitlements against the current active-listing count. At or over the cap, show an upgrade prompt routing to billing (Phase 10a) — never a generic error.

Step 1 — Details (Create_service_widget1.jpg): name with 0/80 counter, 12-CATEGORY icon grid (single-select — this is 12, including Boat Charter), subcategory input, short description. TAGS ARE SELECTABLE CHIPS, not a free-text field (Round 12): render a category-scoped set of suggested tags as tappable pills, with free text underneath for anything not covered. Typing a tag from memory asks a provider to guess what customers search for; showing the options turns it into recognition.

Step 2 — Location (Create_service_widget2.jpg): IMPORT AND REUSE the island multi-select widget from Phase 7. Do not rebuild it. Include the "Maldives only" banner.

Step 3 — Pricing (Create_service_widget3.jpg): pricing model selector (Fixed/Hourly/Daily/Range/Quote with subtitles), price input(s) with MVR prefix — two fields for Range, one otherwise. Values are integer laari underneath.

Step 4 — Media (Create_service_widget4.jpg): COVER IMAGE IS REQUIRED, not optional — surface it as a required field in the progress count and block publish without it. JPG/PNG/WEBP, max 10MB, recommended dimensions shown. 3-column gallery grid up to 8 with add/remove, image guidelines as static help.

Step 5 — Availability (Create_service_widget5.jpg): 7-day toggle pill grid, business hours From/To pickers, Appointment Required toggle, and the static "calendar sync coming in a future update" note.
  TWO CHANGES FROM THE MOCKUP: (a) "Accepting New Customers" is NO LONGER per-listing — it is provider-level and lives in the dashboard, so remove it from this step. (b) The Emergency toggle appears here ONLY if the category is emergencyCapable AND the provider's verificationTier is silver or gold; otherwise show why it is unavailable, with a route to verification.
  Also surface the listing's bookingMode (defaulted from the category) with a plain-language explanation of what each means to a customer — "customers pick from your published time slots" vs "customers send you a request and you propose a time and price".

Step 6 — Extra Info (Create_service_widget6.jpg): collapsible accordions — Professional Background expanded by default, Communication / FAQs / Warranty collapsed. All fields optional.

Step 7 — Review (Create_service_widget7.jpg): if required fields are missing, the amber "Required fields missing" banner listing each with a "Fix" link navigating directly to that step. Section summaries otherwise.

Specify loading, empty, error and populated states for every step as part of this phase.

Definition of done: a service can be created end to end; steps can be filled in any order including jumping straight to Review; the app can be killed mid-wizard and resumed with nothing lost; airplane-mode edits queue and replay on reconnect with a visible pending state; publish is blocked with the exact missing-field list including a missing cover image; the emergency toggle is hidden for a Bronze provider and shown for a Silver one.
```
*(Attach: Create_service_widget1.jpg through 7.jpg)*

---

## Phase 9a — Availability, Time Slots & Reservations

```
Build the availability, time-slot and reservation engine. This is a HARD PREREQUISITE for Phase 17 — do not let it get absorbed into that phase, which is already the largest in the plan.

1. AvailabilityRule per listing: weekday, start time, end time, slot duration, plus per-date overrides (blackout dates, one-off availability).
2. TimeSlot entity: listingId, providerId, startsAt, endsAt, status ('open' | 'reserved' | 'booked'), generated from rules.
3. Nightly generation job on Phase 0's runner maintaining a 60-DAY ROLLING WINDOW per listing. Idempotent — re-running must not duplicate slots.
4. THE DOUBLE-BOOKING CONSTRAINT — this is the single most important line in the phase. Use a PostgreSQL exclusion constraint:
   EXCLUDE USING gist (providerId WITH =, tstzrange(startsAt, endsAt) WITH &&)
   scoped to non-terminal reservations. NOT a unique index on (providerId, listingId, startsAt) — older documentation specified that, and it is wrong twice over: it let one provider be booked three times at 10:00 across three different listings, and it detected nothing about overlapping DURATIONS. The constraint is provider-scoped and range-based. Application code must not be able to override it.
5. Reservation entity supporting FIRM reservations (a booked slot) and PROVISIONAL ones (a quote offered in Phase 17.2, expiring with the quote's 72-hour window).
6. SLOT QUERY GUARANTEE — the customer-facing picker filters on startsAt > now() PLUS the category's minimumLeadTimeMinutes, IN ADDITION to status = 'open'. This is a QUERY-TIME guarantee, not a dependency on the nightly job having run: a slot that was open five minutes ago and simply was not cleaned up must never appear bookable, and a slot five minutes from now does not give the provider a realistic chance to prepare.
7. Provider-side availability management screens — no mockup. Propose before implementing: weekly rule editor, calendar view of generated slots, per-slot override.
8. Releasing a reservation (cancel, decline, timeout) returns its slot to 'open' atomically.

Definition of done: rules generate correct slots across a 60-day window; re-running the job changes nothing; 1,000 concurrent booking attempts against one slot produce EXACTLY ONE winner; a slot-based and a request-based booking overlapping in time on the SAME provider across TWO DIFFERENT listings is rejected by the constraint; a past-dated slot with status 'open' never appears in the picker; a slot inside the category's minimum lead time never appears in the picker; releasing a reservation reopens the slot.
```

---

## Phase 10 — My Services Dashboard (Provider)

```
Build the My Services Dashboard, pixel-matching the attached mockup. This is the provider's home in provider mode.

1. Listing cards with status badges (Draft / Published / Hidden), per-listing quick stats, and edit / preview / publish / unpublish actions.
2. THE PROVIDER-LEVEL "Accepting New Customers" TOGGLE LIVES HERE, not in the wizard. It gates every listing at once and Phase 8a's billing pause keys off it — so the copy must state plainly that turning it off also pauses billing, and how many paused days remain of the 10-day cap.
3. VERIFICATION BADGE reflects verificationTier alone — never subscription state. Show the current tier (Bronze/Silver/Gold) with the exact public copy from plan §1e, plus what the NEXT tier requires and how to get it. A provider on Silver via the automatic 5-clean-bookings route must understand they were promoted and why.
4. A listing hidden by downgrade ('hidden_over_cap') shows WHY, that it is intact and not deleted, and what restores it — never a bare "hidden" badge.
5. DASHBOARD ACCESS IS NEVER GATED. A provider with only drafts reaches this screen normally, with stats at zero. Do not redirect them anywhere.

Specify loading, empty (no listings yet — with a clear next action), error and populated states as part of this phase.

Definition of done: the dashboard matches the mockup; the accepting-new-customers toggle updates provider-level state and its copy states the billing consequence; a hidden-over-cap listing explains itself; a provider with zero listings sees a useful empty state, not an error.
```
*(Attach: My_services.png)*

---

## Phase 10a — Provider Billing UI & Admin Panel: Money & Identity Queues

```
Two parts. Part 1 is Flutter. Part 2 is the FIRST slice of a SEPARATE internal React web app — not a Flutter screen.

PART 1 — Provider Billing (Flutter). No mockups; propose first.
1. Subscription status: trial countdown / next billing date / free-tier state, upgrade CTA, and a "Try Premium" CTA for a provider who has never started a trial. Show the provider's OWN price (subscriptionPriceLaari), and where they are on an introductory rate, when it converts.
2. Payment Proof Submission: bank details, generated reference code, upload, submit. Build it ONCE, parameterised by purpose — the PaymentSubmission purpose enum stays open for post-v1 uses.
3. The submitted state says "pending admin confirmation" with NO implication of instant activation. Nothing is granted on submission.
4. A rejection shows the REASON, with immediate RESUBMIT (no cooldown) and APPEAL actions.
5. Invoice list with PDF download per confirmed payment.

PART 2 — Admin Panel (separate internal React web app). Propose the stack before building; optimise for low effort.
1. Pending PaymentSubmission list with proof image, submitter, amount, reference code.
2. Confirm / reject (REASON REQUIRED) / REVERSE, all audit-logged. Reversal is an explicit endpoint, never a database edit.
3. Bank-statement CSV import with reference-code auto-matching, proposing matches for one-click confirmation.
4. UNMATCHED-TRANSACTION QUEUE for rows the matcher cannot resolve — a garbled reference, an amount that does not match the submission, or a payment split across two transfers. Each resolvable manually against a searchable list of open submissions. The importer assumes clean data; real manual bank transfers routinely are not.
5. IDENTITY VERIFICATION QUEUE — three tiers, not a binary approve:
   - Bronze: government ID matching the account name, AND the admin confirms the account's phone number by calling it or matching it against the document. No trade evidence. This phone check exists because there is no SMS verification anywhere in the system — below Bronze a number is unproven self-declared text.
   - Silver: Bronze + photos of completed work + EITHER a customer reference the admin contacts OR 5 completed on-platform bookings with no unresolved dispute.
   - Gold: Silver + business registration OR a recognised trade certificate.
   PHOTOS ARE NEVER SUFFICIENT ALONE AT ANY TIER — they are trivially reusable.
   THE 5-CLEAN-BOOKINGS ROUTE TO SILVER GRANTS AUTOMATICALLY, with NO admin review. Build it as a scheduled/triggered check, not a queue item. Only ID checks, customer references, and Gold paperwork reach a human — that is what makes three tiers affordable against one reviewer.
   Tiers do NOT expire. A confirmed-fraud dispute outcome or an accumulated dispute pattern triggers a review that may demote or revoke.
   Documents served via short-lived signed URLs, every access logged (which admin, which document, when), stored in a SEPARATE private bucket, purged 90 days after a decision and immediately on account deletion. The decision, evidence type and reviewing admin persist; the images do not.
6. payment_unresolved queue with a 5-BUSINESS-DAY resolution target and an alert when an item ages past it or the queue exceeds 25 open items.
7. Audit log viewer (Phase 2).
8. SECURITY — mandatory and specified, not left to judgment. This app renders user-authored text (listing descriptions, review bodies, enquiry messages) and is the tool that approves money. A malicious provider can plant a payload in a description and report their own listing to guarantee an admin views it.
   - Build in React (or another framework with default-on JSX escaping). Never server-render raw HTML string concatenation.
   - NO dangerouslySetInnerHTML anywhere, enforced by an ESLint rule that FAILS THE BUILD.
   - CSP header: default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'. No unsafe-inline, no CDN origins.
   - User-authored fields render as TEXT NODES ONLY — never as HTML, never as an href without scheme validation.
   - Test with a stored <script>, an <img onerror>, and a javascript: URL in a listing description, a review body, and an enquiry message.
9. Real admin auth from Phase 2. Never publicly reachable without credentials. Do NOT add MFA, IP allowlisting or session hardening — deliberately out of v1 scope (plan §7).

Definition of done: a provider submits with proof and sees pending; an admin confirms and the entitlement activates; a rejection surfaces its reason with working resubmit and appeal; CSV import proposes correct matches and routes unresolvable rows to the unmatched queue; a provider hitting 5 clean bookings is promoted to Silver with NO admin action; a Gold submission without registration or a certificate is rejected with a reason; all three XSS payloads render inert in every admin view; an aged payment_unresolved item triggers its alert.
```

---

## Phase 10b — Admin Panel: Accounts, Config, Search & Shell

```
Extend the Phase 10a React admin app. Same app, same auth, same audit log — not a new stack.

Phase 10a gave the admin a way to approve money and identity but no way to look at a user, change configuration, or find anything without knowing which queue it is in. This phase closes that.

ACCOUNT MANAGEMENT
1. User directory: search by phone or name, filterable by role (customer/provider) and status.
2. Detail view: profile, listings, booking history, reports filed by and against, verification history — in one place.
3. SUSPEND / UNSUSPEND, reason required, audit-logged. Suspension blocks new bookings and listing publication; existing non-terminal bookings are unaffected until they resolve on their own.
4. SUSPENSION FEEDS findVisibleProviders (Phase 5) — a suspended provider disappears from search, Home and the public profile through that ONE shared query. Their listing pages return a neutral unavailable state, not a booking form.
5. BAN AND HARD-DELETE ARE NOT PANEL ACTIONS. They remain manual database operations, deliberately — a single unhardened admin credential should not have one-click destructive reach over an account.
6. READ-ONLY "VIEW AS USER": renders the user's own view of their listings, bookings and subscription state. No ability to act as them. Access-logged with viewing admin, target and timestamp.
   MESSAGE CONTENT IS EXCLUDED. Chat is the sole coordination channel and carries home addresses, gate codes and photos of people's houses. An admin reaches a thread only through a specific report or dispute that names it, scoped to that thread and logged separately.
7. RECOVERY AND NUMBER-RELEASE QUEUE (Phase 3): review a recovery request against the account record and identity evidence, approve or reject, reason required. The same queue handles the two problems the unique-phone constraint creates — SQUATTING (someone registered a number they do not own, permanently blocking the real holder) and NUMBER RECYCLING (a reassigned number locked to a dormant account). Releasing a number frees it for re-registration and is audit-logged.

CONFIG MANAGEMENT
8. Categories editable: name, icon, active/inactive, minimumLeadTimeMinutes — CRUD, audit-logged.
9. bookingMode IS EDITABLE ONLY WHILE NO LIVE DATA DEPENDS ON IT. Block the change outright when any published listing in that category has open time slots or non-terminal bookings, and NAME the blocking listings. Flipping a category from slot to request would otherwise orphan every published TimeSlot and leave confirmed bookings pointing at a mode their listing no longer has.
10. EMERGENCY-ELIGIBLE CATEGORIES ARE NOT EDITABLE. Code-defined (Plumbing, Electrical, AC Repair). A safety decision, not configuration.
11. Launch-mode threshold (Phase 16's 50-listing gate) editable, with the current published-listing count shown beside it.

INTERNAL NOTES
12. Free-text notes attachable to a user, a booking, or a verification/dispute case. Timestamped, attributed, never visible to the subject. Shown inline on the relevant record, not on a separate screen. DELETED with the subject's account (Phase 3).

ALERTING
13. The Phase 10a in-panel alerts additionally fire OUTBOUND — email or Slack/Telegram — so a single admin who has not opened the panel still gets the SLA-breach warning. New disputes and verification submissions push on arrival too.
14. DE-DUPLICATE PER THRESHOLD CROSSING: notify once when a threshold is crossed, and again only after it clears and re-crosses. An alert firing every fifteen minutes while a queue is deep gets muted within a day, which is the exact failure this mechanism exists to prevent.

KILL SWITCHES
15. Admin-flippable, audit-logged flags for: emergency bookings, new registrations, new listing publication, and the emergency contact reveal.
16. EMAIL IS THREE SEPARATE SWITCHES: OTP email, notification/fallback email, marketing email. A single outbound-email switch would kill OTP — now the ONLY verification channel — locking every user out of registration and new-device login, and simultaneously disabling the push fallback. That is a platform outage, not an incident control.
17. A persistent banner while any flag is off, in the panel and where relevant in the Flutter app.

SEARCH, TABLES, SHELL
18. Command-palette global search (⌘K) across users (phone/name), bookings (ID) and payments (reference code); typed input routes to the matching record type.
19. Shared list conventions on EVERY queue and list: filter by status/date/type, sortable columns, server-side pagination with a visible total, a shared date-range control with presets.
20. CSV export of the current filtered view — IDs, statuses, dates, amounts and counts ONLY. NEVER phone numbers, names, email addresses or bank details. An unrestricted directory export would let every phone number on the platform leave in one click from a credential with no MFA.
21. Persistent sidebar with a live open-count badge per queue; consistent severity colour coding so anything past its SLA is flagged the same way everywhere.

DELIBERATELY NOT IN THIS PHASE — do not add them or leave TODOs implying they are coming: bulk queue actions and keyboard triage; a proactive risk-signal dashboard; provider broadcast messaging; general booking-state override beyond dispute and payment_unresolved resolution.

This is a web app: keyboard, hover, focus and pointer states apply. Do not import mobile assumptions.

Definition of done: any user, booking or payment is findable by phone/name/ID/reference in under two actions; suspending a provider removes them from search and Home via findVisibleProviders and blocks new bookings without touching an in-progress one; view-as-user renders listings and bookings and exposes NO message content; a bookingMode change is refused while the category has open slots and names them; flipping OTP SMS does not affect notification SMS; a kill switch shows its banner within one page load; a pushed alert arrives outside the panel and does NOT repeat while the threshold stays breached; a user-directory CSV export contains no phone number, name, email or bank detail.
```

---

## Phase 11 — Reviews & Ratings

```
Build Reviews & Ratings. BACKEND-focused; review display lands in Phases 12 and 13.

1. Review tied to a COMPLETED booking. One review per booking, enforced at the database level.
2. Rating aggregation per listing and per provider, with a star breakdown, computed TRANSACTIONALLY on write — never a periodic recompute that can drift.
3. This is only safe because Phase 17's auto-completion exists: gating reviews on completion is correct precisely because a provider can no longer block completion indefinitely by staying silent.
4. Soft-delete. A hidden review is excluded from aggregates.
5. AUTHORSHIP IS RETAINED INTERNALLY after the author's account is anonymised — never shown publicly, never returned in any response, but preserved so a disputed review can still be traced and adjudicated. Without it, a customer can post a fabricated review, delete their account, and sever the accountability trail by design.
6. Review anti-spam: rate limit, and FLAG implausibly-fast reviews for a human look rather than auto-rejecting them.

Definition of done: a review can only be posted against a completed booking, once; aggregates update transactionally and match a manual recount; hiding a review changes the aggregate immediately; a review whose author deleted their account still resolves to an internal author ID by direct query while exposing nothing publicly.
```

---

## Phase 12 — Service Preview (Public Listing Page)

```
Build the Service Preview screen, pixel-matching the attached mockup. This is the public listing page and the primary conversion surface.

1. Gallery, name, category, provider summary with VERIFICATION TIER BADGE (Bronze/Silver/Gold, using the exact copy from plan §1e — never a generic "Verified"), rating and review count, pricing, description, service areas, FAQs, warranty, reviews list.
2. BOOKING MODE MUST BE SIGNALLED, not discovered on tap. "Book instantly" for slot-based, "Request a time" for request-based, plus an "Emergency available" marker where applicable. A customer expecting to pick a time must never land in a form instead, or vice versa.
3. Primary CTA routes into the correct Phase 17 booking variant for this listing's bookingMode.
4. MESSAGE BUTTON — opens a Phase 18 `enquiry` thread scoped to this listing, available to any phone-verified user BEFORE any booking exists. Route stub until Phase 18 lands.
5. Favourite toggle (Phase 14), share via the deep link (Phase 16).
6. Report affordance on the listing and on individual reviews (Phase 22).

Specify loading (skeleton), error, and the no-reviews-yet empty state as part of this phase.

Definition of done: the screen matches the mockup; the booking-mode affordance is correct for each of the three modes; the verification badge shows tier-specific copy; a guest tapping Book or Message routes to login rather than failing; the no-reviews state reads as normal rather than broken.
```
*(Attach: Service_preview.png)*

---

## Phase 13 — Provider Public Profile Page

```
Build the Provider Public Profile. No mockup — propose a design first, reusing established components.

1. Reached from Service Preview and from search results. Shows businessName, bio, years of experience, VERIFICATION TIER with its tier-specific copy, jobsCompletedCount (derived, never a stored counter), aggregate rating, service areas, and all of that provider's published active listings.
2. GATED THROUGH findVisibleProviders (Phase 5) — a provider with no published active listing, or a suspended one, is not reachable here. Return a neutral not-available state, never a 500 or an empty shell.
3. NO CONTACT DETAILS OF ANY KIND. No phone, no messaging handles. There is no endpoint in this system that would supply them to this screen.
4. Response-time and accept-rate metrics (Phase 19) display here where data exists, and read "No data yet" for a new provider — never a blank or a zero that reads worse than no metric at all.
5. Report affordance (Phase 22).

Specify loading, error, and the not-available state as part of this phase.

Definition of done: the profile renders for a visible provider and returns the neutral state for a draft-only or suspended one; no response feeding this screen contains a phone number; a brand-new provider's metrics read "No data yet".
```

---

## Phase 14 — Favorites (Saved Services)

```
Build Favorites. Small phase, straightforward.

1. Favorite join table (userId, listingId), unique per pair.
2. POST/DELETE /v1/users/me/favorites/:listingId, GET /v1/users/me/favorites.
3. Requires `requireAuth` only — NOT phone verification. Saving is a browsing action, not a transactional one.
4. Frontend: the toggle on listing cards and Service Preview with OPTIMISTIC UPDATE and rollback on failure; the Saved Services list screen (no mockup — propose first).
5. A favourited listing that is later unpublished or hidden stays in the list with a clear unavailable state rather than vanishing silently or 404-ing.

Specify loading, empty (nothing saved yet, with a route into Explore), and error states as part of this phase.

Definition of done: toggling updates instantly and rolls back visibly on a failed request; the list survives a listing being unpublished; a guest tapping the toggle routes to login.
```

---

## Phase 15 — Search & Discovery

```
Build Search & Discovery, backend and frontend.

1. GET /v1/search with: free-text query across listing name and description, category filter, island/service-area filter, price range, bookingMode filter, emergency-available filter, minimum rating, and verification tier.
2. ALL RESULTS GO THROUGH findVisibleProviders (Phase 5) — draft-only and suspended providers never appear. One gate, not a filter reimplemented per query.
3. SEARCH VISIBILITY IS NEVER PAYWALLED. Free-tier providers appear in results identically to paid ones. Subscription buys PRIORITY PLACEMENT within results, never presence in them.
4. Appropriate indexes plus a SHORT-TTL CACHE (30–60 seconds) in front of search, category-browse and Home responses. Deliberately NO explicit invalidation: the TTL is short enough that suspension, category edits and the launch-mode flip self-correct within a minute, which avoids a bust-key matrix across every mutable input. Revisit read replicas once Phase 21 shows real read volume.
5. Server-side pagination. Never return an unbounded result set.
6. Frontend: search results and category results screens (no mockups — propose first), filter sheet, sort control. SORT ORDER IS FIXED AS: distance, then rating, then price (Round 12) — distance leads because a provider who cannot reach your island is not a result at all. Each result card carries its BOOKING MODE AFFORDANCE, same as Service Preview.

Specify loading (skeleton), no-results (with a suggestion to broaden filters, naming which filter is narrowing most), and error states as part of this phase.

Definition of done: every filter works independently and in combination; a free-tier provider appears in results at the same rank rules as a paid one apart from priority placement; a suspended provider disappears from results within the cache TTL; no-results reads as actionable rather than as a failure; p95 latency meets the plan's §5 target under a seeded catalogue.
```

---

## Phase 16 — Home Feed (Customer)

```
Build the Home feed, pixel-matching the attached mockup. This is the app's front door.

1. Sections: search entry, category shortcuts, featured providers, recent/nearby listings — all sourced through findVisibleProviders and the Phase 15 query layer.
2. LAUNCH MODE — a distinct Home variant for a thin catalogue, shown while the platform has fewer than the threshold number of published active listings (default 50, admin-editable in Phase 10b). It reframes the feed around browsing categories and "new on RaajjePro" rather than rendering half-empty carousels that make the platform look abandoned. Propose this variant's layout before building it.
3. TRUST GRID COPY MUST STATE WHAT VERIFICATION MEANS. In the Maldives a customer may read "Verified Provider" as "has a good track record" rather than "passed an ID and trade check". Use the tier-specific copy from plan §1e verbatim — "ID checked by RaajjePro" / "ID checked, work verified" / "ID checked, registered trade". Never a bare "Verified".
4. DEEP LINKS / WEB FALLBACK: listings and provider profiles resolve via real URLs with universal links / app links and a minimal web fallback page. An earlier revision justified open guest browsing partly on SEO while having no web surface to index, and shipped a Share button with nothing to share.
5. "Become a Provider" CTA routes into Phase 6a's onboarding flow — NOT into the wizard directly, and NOT into the dashboard.
6. Every card carries its booking-mode affordance.

Specify loading (skeleton), correctly-empty, and error states per section as part of this phase.

Definition of done: every section shows live, correctly-empty, or correctly-loading state; launch mode renders convincingly against a twenty-listing seed and switches off when the threshold is crossed; a shared listing URL opens the app when installed and the fallback page when not; the trust grid never says a bare "Verified".
```
*(Attach: Home.png)*

---

## Phase 17 — Bookings Module

The largest phase in the plan and the highest-risk one. No mockups — propose each frontend piece before implementing.

**Build in four sequential slices, each independently testable.** Phase 17 carries three booking modes, five scheduled jobs, quote flows, recurring series, reschedule, and dispute paths. Attempting it in one pass is the single largest delivery risk in this plan. Do not merge these prompts.

### Phase 17.1 — Slot-based core

```
Build the slot-based booking core. Slot bookings ONLY — request-based and emergency come in 17.2 and 17.3.

1. Booking entity, full shape now so later slices only add behaviour: listingId, customerId, providerId, bookingMode ('slot'|'request'|'emergency'), timeSlotId (nullable), reservationId (nullable), status, agreedAmount (integer laari, nullable until set), amountKind ('listing_price'|'quote'|'callout_fee'), quotedAmount, finalAmount (integer laari, nullable — emergency only), scheduledFor, amountSetAt, paymentClaimedAt, paymentAttestedAt, completedAt, completedVia ('confirmed'|'unconfirmed'), statusHistory.
2. Status machine: requested → accepted → awaiting_payment → payment_claimed → confirmed → completed, with declined, cancelled, disputed → dispute_resolved, and payment_unresolved. NEITHER disputed NOR payment_unresolved is terminal — an admin resolves both.
3. POST /v1/listings/:id/bookings — reserves the slot INSIDE the booking-creation transaction against Phase 9a's exclusion constraint. requireEmailVerified. Idempotency key required.
4. PATCH /v1/bookings/:id/accept — sets agreedAmount from the listing price. Slot bookings pass through to awaiting_payment immediately, so the customer's payment prompt appears at once.
5. PATCH /v1/bookings/:id/decline — provider; frees the slot; DISTINCT from dispute, with its own status and its own endpoint.
6. PATCH /v1/bookings/:id/claim-payment — customer self-attestation. NO proof upload. Status payment_claimed.
7. PATCH /v1/bookings/:id/confirm-payment-received — provider → confirmed.
8. PATCH /v1/bookings/:id/dispute — either party → disputed; files a Report (Phase 22).
9. PATCH /v1/bookings/:id/complete — provider → completed, completedVia 'confirmed'.
10. PATCH /v1/bookings/:id/cancel — customer, pre-payment; frees the reservation.
11. SCHEDULED JOBS on Phase 0's runner:
    - requested older than 24 HOURS → auto-decline, release the slot, notify the customer
    - payment_claimed with no provider response after 7 DAYS → payment_unresolved, notify BOTH parties, file a Report. NO entitlement and NO additional access is granted by this transition. An earlier revision auto-confirmed here, recording an attestation that may never have happened.
    - confirmed 7 days past scheduledFor with no completion → prompt the customer "Did this happen?"; a further 3-day non-response auto-completes with completedVia 'unconfirmed'
12. TRIAL-START HOOK fires on the STATE TRANSITION INTO confirmed, not from one endpoint — so an admin resolving payment_unresolved to confirmed also fires it (Phase 8a).
13. THERE IS NO CONTACT-INFO ENDPOINT. Older documentation described GET /v1/bookings/:id/contact-info. It is deleted. Do not create it. The only phone-number path in the system is built in 17.3 and applies to emergency bookings alone.

Frontend:
1. Slot picker showing OPEN SLOTS ONLY, filtered per Phase 9a's query guarantee.
2. Provider accept prompt: job details and customer name only. NO contact details, no chat yet. Accept/decline with a 24-hour countdown.
3. THE ACCEPT PROMPT QUEUES AND REPLAYS OFFLINE, reusing Phase 9's pattern. A provider tapping Accept on a weak connection must not lose the action or be left unsure it registered — record locally, show pending, replay on reconnect.
4. Payment prompt: the provider's payment details, agreedAmount shown explicitly and labelled by amountKind, HONEST COPY, "I've Paid".
5. Provider receipt prompt: three visually distinct actions — "Payment Received", "Payment Not Received", "Decline Booking".
6. "Did this happen?" prompt at the 7-day post-scheduled mark.
7. Bookings tab: status filter pills, detail view, status timeline showing when each transition happened and who caused it, distinct badges for every status including awaiting_payment and payment_unresolved.
8. "Book again" on a completed booking — pre-fills a new request against the same provider and listing, routed by that listing's current bookingMode.
9. Calendar export on a confirmed booking — an ICS download or subscribe link.

HONEST FRAMING IS MANDATORY. Never "Payment Verified". Never a lock or verified-checkmark on this flow. Use "Provider confirmed receipt." RaajjePro has no visibility into the actual bank transfer and the UI must never imply otherwise.

Definition of done: the slot lifecycle works end to end; 1,000 concurrent attempts on one slot yield exactly one winner; an unresponsive provider auto-declines at 24 hours and the slot reopens; an unresolved payment claim escalates at day 7 WITHOUT unlocking anything; an accept tapped in airplane mode replays on reconnect; "Book again" opens a correctly-routed new request; a confirmed booking exports a valid ICS entry; no response shape in this module contains a phone number.
```

### Phase 17.2 — Request-based bookings and quotes

```
Add the request-based booking path to Phase 17.1's module.

1. Extra statuses inserted before the 17.1 machine: awaiting_quote → quote_offered → accepted.
2. POST booking for a request-based listing captures a PREFERRED DATE/TIME WINDOW (not an exact slot) plus job details and location.
3. PATCH /v1/bookings/:id/quote — provider proposes a concrete date/time AND price. This creates a PROVISIONAL RESERVATION on the proposed time (Phase 9a), expiring with the quote's 72-hour window. Without it the provider could sell that time to someone else in the interim and the customer's approval would fail on a constraint violation after they had already agreed a price.
4. PATCH /v1/bookings/:id/approve-quote — converts the provisional reservation to firm and transitions to accepted. Reject releases it.
5. THE BOOKING CHAT OPENS WHEN THE QUOTE IS OFFERED, not at accepted. This is the one window where negotiation is most likely — the provider proposes Tuesday 2pm at a price and the customer wants Tuesday 3pm — and an earlier revision left it with no channel at all, so the customer's only levers were approve or reject as offered, forcing the provider to guess again from scratch while the clock and the reservation churned.
6. SCHEDULED JOB — quote_offered older than 72 HOURS FROM THE QUOTE TIMESTAMP (not from booking creation) → quote expires, provisional reservation releases, booking closes. An earlier revision auto-declined 24 hours after booking creation, which would have killed quotes submitted at hour 23 before the customer ever saw them.
7. Everything from accepted onward is IDENTICAL to 17.1. Do not fork the downstream flow.

Frontend:
1. Request entry with a preferred-window picker LEADING WITH QUICK-PICK CHIPS — "Tomorrow morning", "Tomorrow afternoon", "This week", "This weekend" — with free text underneath for anything more specific. A blank text field as the primary interaction asks more of the customer than most bookings need.
2. Provider quote composer reached from the accept prompt; offering a quote lands the provider IN THE CHAT THREAD, not back on a list.
3. Customer quote review: proposed time, price, expiry countdown, approve/reject, and the chat thread inline so a counter-proposal is possible without leaving.

Definition of done: a quote creates a provisional reservation that blocks the same time for others; the quote expires on its OWN 72-hour clock and releases the reservation; the chat is open and usable at quote_offered before any approval; approval converts to firm atomically; the downstream flow is shared code with 17.1, not a copy.
```

### Phase 17.3 — Emergency bookings

```
Add the emergency booking path. This slice carries the ONLY contact-information exception in the entire system — read item 6 carefully.

1. POST booking with bookingMode 'emergency' captures NO timing constraint (no slot, no window) and VALIDATES THREE THINGS: the category is emergencyCapable (Plumbing/Electrical/AC Repair only), the provider's verificationTier is SILVER OR GOLD, and the customer is within the emergency rate limit.
2. RATE LIMIT: 3 emergency requests per customer per 24 hours, 10 per 7 days.
3. THE REQUEST BROADCASTS TO EVERY ELIGIBLE PROVIDER AT ONCE — emergency-capable category, island match, verificationTier silver or gold, acceptingNewCustomers on. Older documentation sent an emergency to ONE provider and deferred fan-out to post-v1; that is reversed. Sequential dispatch is the wrong shape for the one booking type where minutes matter.
4. A PROVIDER ACCEPTS *WITH* THEIR CALLOUT FEE, IN ONE CALL. There is no separate set-amount step any more. PATCH /v1/bookings/:id/emergency-accept takes calloutFee. The claim resolves atomically — exactly one winner; losers get a distinct ALREADY_CLAIMED error code, never a generic failure. Status → emergency_offered (a new non-terminal status no other booking mode can reach).
4b. THE FIRST ACCEPTANCE DOES NOT BIND THE CUSTOMER. It is an OFFER — provider, tier, rating, callout fee. PATCH /v1/bookings/:id/emergency-offer-response takes accept or reject.
   - Accept → agreedAmount = calloutFee, amountKind 'callout_fee', status → awaiting_payment.
   - Reject → back to requested, RE-BROADCAST, and add that provider to the booking's rejectedProviderIds so they are excluded from later rounds.
   - SCHEDULED JOB, offer expiry: emergency_offered older than 5 MINUTES → release the provider, return to requested, re-broadcast.
   Without the offer step, first-accept-wins would commit the customer to an unknown provider at an unknown price.
5. scheduledFor IS SET TO THE ACCEPTANCE TIMESTAMP so the 7-day completion timeout fires normally. Without it, emergency bookings would have no natural scheduled time, the completion timeout could never fire, and a provider could block reviews forever by staying silent.
6. THE CONTACT REVEAL — POST /v1/bookings/:id/reveal-contact. This is the ONLY endpoint in the entire system that returns a phone number to another user. Validate ALL SEVEN conditions server-side:
   - bookingMode is 'emergency'. No slot or request booking may ever reach this path.
   - status is accepted or later. NEVER at requested — a provider who has not committed gets nothing.
   - THE CUSTOMER INITIATES. No automatic reveal, no provider-initiated reveal.
   - THE REVEAL IS MUTUAL AND SIMULTANEOUS — both parties see each other's number, or neither does. A one-way reveal would hand the customer a lever the provider never agreed to.
   - The counterparty is NOTIFIED at the moment of reveal, in-app and by push.
   - It EXPIRES 24 hours after the booking reaches a terminal state; the endpoint returns nothing for that booking afterward.
   - Every reveal is LOGGED (bookingId, requesting user, timestamp) and surfaces in Phase 22's moderation signals.
   It is also gated by Phase 10b's kill switch and must be disableable at runtime without a deploy.
   WhatsApp and Viber handles are NOT collected anywhere in this system and cannot be revealed by this or anything else. Do NOT reintroduce GET /v1/bookings/:id/contact-info — it is a different, far broader thing and it is deleted.
7. COMPLETION REQUIRES finalAmount. PATCH /v1/bookings/:id/complete REJECTS an emergency booking without it — the real settled total once parts and labour were added to the callout fee. It gates completion exactly as agreedAmount gates awaiting_payment. It was optional in an earlier revision, which meant it would be reliably present on clean cheap jobs and reliably absent on the padded bill a customer was disputing, inverting the evidentiary value it exists to provide.
8. NO CALENDAR RESERVATION — an emergency is an interruption to the published calendar, not a block on it.
9. THE OVERALL REQUEST WINDOW IS PER-CATEGORY, read from emergencyAcceptWindowMinutes (Phase 4): 30 minutes for Plumbing, Electrical and AC Repair, 120 for Moving. SCHEDULED JOB: a requested emergency booking older than its category's window → auto-decline, notify, offer one tap to re-broadcast or convert to a normal request-based booking. OFFER REJECTIONS AND EXPIRIES DO NOT RESET THIS CLOCK — the window governs the whole request, so a customer who rejects three offers has spent that time. Rejections do NOT consume the customer's emergency rate limit, which applies to requests, not offers.
10. VERIFICATION REVOCATION CASCADE — when a provider's verificationTier drops below silver, handle in-flight emergency bookings BY PAYMENT STATE, not uniformly: at accepted or awaiting_payment, AUTO-CANCEL with both parties notified; at payment_claimed, confirmed or later, ROUTE TO THE ADMIN QUEUE as a dispute and leave otherwise untouched. Auto-cancelling a booking the customer has already paid for off-platform would strand real money with no platform recourse.
11. Accept-then-cancel patterns are logged as a provider-level moderation signal (Phase 22).

Frontend:
1. Emergency/ASAP entry: job details and location, with copy setting the expectation that providers respond with a callout fee and parts and labour settle directly afterward.
2. Provider urgent accept prompt with a 30-MINUTE countdown, visually distinct from the 24-hour one.
3. Provider accept-with-fee: ONE screen where the callout fee is entered as part of accepting, copy stating parts and labour settle directly with the customer, and a clear "already claimed by someone else" state for a lost race.
3b. Customer offer card: provider name, verification tier, rating and callout fee, with Accept and Reject, a countdown on the 5-minute offer window, AND a second countdown on the overall request window so the customer can see what rejecting costs them.
4. THE CONTACT-REVEAL REQUEST — a customer-initiated action on the emergency booking detail, stating before it is tapped that BOTH numbers become visible to each other and that the provider will be told. Never a silent or one-sided reveal.
5. Emergency completion: a REQUIRED "Final amount charged" field in the complete-job flow, distinct from the callout fee shown earlier in the timeline.
6. Emergency no-acceptance state: "No one accepted in time" with one tap to try another provider or convert to a scheduled request.

Definition of done: an emergency booking on an ineligible category is rejected; one by a BRONZE provider is rejected and by a SILVER provider accepted; the rate limit triggers; a broadcast reaches every eligible provider and nobody outside the eligibility rule; two simultaneous accepts resolve to one winner with the loser receiving ALREADY_CLAIMED; a rejected offer re-broadcasts and never returns to the rejected provider; an unanswered offer expires at 5 minutes and re-broadcasts WITHOUT resetting the overall window; the request window expires at 30 minutes for Plumbing and 120 for Moving and offers both fallbacks; the reveal endpoint REJECTS a non-emergency booking, a requested-state booking, and a provider-initiated call; it reveals BOTH numbers or neither; it returns nothing 24 hours after terminal state; it is disabled by the kill switch; completion is REJECTED without a final amount; revoking verification auto-cancels an accepted emergency booking but routes a payment_claimed one to admin instead.
```

### Phase 17.4 — Recurring series and reschedule

```
Add recurring series and reschedule to the bookings module.

1. RecurringSeries links a customer, provider and listing to a weekly cadence. SLOT-BASED LISTINGS ONLY — predictable duration is what makes "same time next week" meaningful.
2. EACH OCCURRENCE STILL REQUIRES AN INDIVIDUAL PROVIDER ACCEPT. Recurrence is a convenience, not a standing pre-authorisation — this preserves the "provider always gets a real chance to decline" principle the whole booking redesign is built around. The UI streamlines it to a one-tap "Same time next week?".
3. A MISSED OCCURRENCE DOES NOT KILL THE SERIES. If an occurrence auto-declines at the 24-hour timeout, that week is SKIPPED, both parties are notified explicitly ("this week was not confirmed; your series continues next week"), and the series continues. THREE CONSECUTIVE MISSES pause the series and notify the customer to reconfirm.
4. Cancelling one occurrence does not cancel the series; cancelling the series stops future occurrences.
5. PATCH /v1/bookings/:id/reschedule — another open slot (slot-based) or a new proposed time (request-based). FREES THE OLD RESERVATION ATOMICALLY in the same transaction that takes the new one; a reschedule must never leave the provider double-blocked or double-free.

Definition of done: a series generates occurrences on cadence, each requiring its own accept; one missed occurrence skips that week and both parties are told, with the series intact; three consecutive misses pause it; reschedule holds exactly one reservation at every moment, verified under concurrent attempts.
```

---

## Phase 18 — Messaging Module

```
Build the Messaging module. Chat is THE SOLE COORDINATION CHANNEL for every booking on this platform — with the single emergency exception built in 17.3 — so its reliability is job-coordination reliability, not a nice-to-have.

1. Conversation types:
   - `enquiry` — scoped to a LISTING, not a booking. Available to any phone-verified user BEFORE any booking exists. EVERYTHING IS ALLOWED: appliance make/model/serial, property details, photos of the issue, availability questions, price ranges. The point is to let a plumber ask "is it a split unit or ducted?" and get an answer.
   - `booking` — opens at quote_offered for request-based bookings (17.2) and at accepted for slot and emergency, and STAYS OPEN FOR THE ENTIRE LIFE OF THE BOOKING INCLUDING AFTER COMPLETION. It is never torn down and never replaced by a "real" contact channel, because there isn't one.
2. requireEmailVerified on both types.
3. CONTACT-PATTERN DETECTION IS COMPLETELY SILENT (Round 12). No banner, no reminder, no redaction, no interference of any kind — the sender sees NOTHING. Older documentation described an inline nudge near the composer; it is removed. In-app messaging carries no friction.
   DETECTION STILL RUNS INVISIBLY. Every match is recorded and feeds the provider-level aggregate in item 4. The aggregate is the enforcement mechanism and it never depended on telling the sender.
   Why detection never blocks: Maldivian mobiles are 7 digits beginning 7 or 9; AC serials are 7–15 digit strings; model numbers are alphanumeric with digit runs. These are not reliably distinguishable, and a hard block would fire on exactly the content the enquiry channel exists to carry. Photos are allowed too, so a photo of a business card passes a text filter regardless.
4. EVERY DETECTION IS LOGGED (conversationId, senderId, matched pattern, timestamp) and aggregated into Phase 22's moderation signals as a PROVIDER-LEVEL figure — "tripped detection in 40 of 52 enquiries" — not per-message noise.
5. MESSAGE RATE LIMIT — per-conversation and per-user, using Phase 2's tier mechanism. The content policy is deliberately permissive, so an uncapped channel with only after-the-fact block-and-report is a real spam and harassment surface.
6. BLOCK — TWO DISTINCT ACTIONS, presented together, because the scope was previously undefined for a feature framed as safety-relevant:
   - "Mute this conversation" — silences one thread, nothing else.
   - "Block this person" — ACCOUNT-LEVEL. Neither party can message the other or create a new booking against them, enforced SERVER-SIDE at both conversation-creation and booking-creation.
   A BLOCK NEVER SEVERS A LIVE BOOKING'S CHAT. Since chat is the sole coordination channel, killing it mid-job would leave a scheduled visit uncoordinated. The block takes effect immediately for all FUTURE bookings and messages, but the existing booking's thread stays open until that booking reaches a terminal state, with a visible notice to both parties explaining why.
7. PROVIDER-SIDE "DECLINE FUTURE BOOKINGS FROM THIS CUSTOMER" — self-service, enforced at booking creation, INDEPENDENT of the Report → admin-review path. A provider who has had a bad experience otherwise has no protection during a moderation SLA measured in days. One-directional; it does not silence the existing conversation.
8. MESSAGES QUEUE AND REPLAY OFFLINE, same shared pattern as Phase 9's wizard and 17.1's accept prompt. A message that silently fails to send is a coordination failure. Queued messages show a pending state and send on reconnect.
9. RETENTION AND SIZE: content and attachments retained for the life of the account and purged with it under Phase 3's anonymisation rule; attachments capped at the same per-file size as listing media (Phase 8).
10. Enquiry-thread lifecycle: if the listing is hidden by downgrade, both threads stay READABLE to participants but the `enquiry` side accepts no new messages, with an explanatory state. A `booking` thread tied to a non-terminal booking is NEVER affected by its listing's visibility. If the listing is soft-deleted, the enquiry thread becomes read-only and drops out of the conversation list after 30 days.
11. Report from within a conversation (Phase 22).

Frontend: conversation list covering both types, thread view, pending/sent/failed states per message. NO nudge banner — the composer carries nothing beyond the normal send affordance.

Definition of done: an enquiry thread delivers a message containing an appliance serial number WITHOUT obstruction and logs a detection where one fires; a message containing a phone-shaped string sends with NO visible interference whatsoever while still producing a logged detection; a message sent in airplane mode queues, shows pending, and delivers on reconnect; the message rate limit triggers; a booking thread remains open and usable after completion; blocking prevents future bookings while leaving a live booking's thread open with its notice; a provider who declines future bookings from a customer stops receiving them while the existing conversation stays intact; detection aggregates are queryable per provider.
```

---

## Phase 19 — Notifications Module

```
Build notification CONTENT. Phase 3c owns delivery — call its PushSender, never reimplement transport.

1. Notification entity: userId, type, payload, readAt, createdAt.
2. Types: booking_requested, booking_accepted, booking_declined, booking_auto_declined, emergency_no_acceptance, contact_revealed, amount_set, payment_claimed, payment_confirmed, payment_unresolved, payment_disputed, dispute_resolved, booking_completed, booking_auto_completed, completion_check_prompt, recurring_occurrence_missed, recurring_series_paused, payment_submission_confirmed, payment_submission_rejected, verification_tier_granted, verification_rejected, verification_tier_revoked, trial_ending_7d, trial_prompt_7d_post_publish, subscription_ending_7d, introductory_price_converting_30d, downgraded_to_free, winback_7d, winback_30d, new_message, new_enquiry, new_review.
3. Weekly provider digest EMAIL, opt-in, to the verified address from Phase 3: views, bookings, reviews, top-performing listings.
4. Provider analytics dashboard: per-listing views, booking counts, conversion rate, rating trend, response time, and accept rate.
5. TWO METRICS, NOT ONE — response time alone flatters a provider who ignores most requests and answers only the ones they want:
   - ACCEPT RATE counts EXPLICIT RESPONSES ONLY: accepted ÷ (accepted + declined). A request-based QUOTE OFFERED COUNTS AS AN ACCEPTANCE, since the provider did commit.
   - Auto-declines at the 24-hour or 30-minute timeout are EXCLUDED from accept rate entirely and feed a separate, more forgiving RESPONSE RATE: responded ÷ received.
   Folding timeouts into one number would score a provider who was asleep identically to one who actively refused. Those are not the same behaviour.
6. BOTH METRICS READ "No data yet" for a provider with no history — never a blank, and never a zero that reads worse than no metric at all.
7. Notification centre screen (no mockup — propose first); live badge counts.

Specify loading, empty (no notifications, which is normal not broken), and error states as part of this phase.

Definition of done: every type fires through Phase 3c's sender; the digest sends on schedule to opt-in providers with verified emails only; a provider who let a request time out sees it reflected in response rate but NOT in accept rate; a provider who offered a quote sees it counted as an acceptance; a brand-new provider's metrics read "No data yet".
```

---

## Phase 20 — Hardening, QA & Launch Readiness

```
Harden the platform. This phase verifies what earlier phases specified — it is not where those things get designed for the first time.

1. Contract tests across every module. E2E on the critical path: register → verify → publish → slot published → customer books → provider accepts → payment attested → confirmed → completed → review.
2. CONCURRENCY TESTS SPECIFICALLY:
   - simultaneous slot booking
   - A SLOT-BASED AND A REQUEST-BASED BOOKING OVERLAPPING IN TIME ON THE SAME PROVIDER ACROSS TWO DIFFERENT LISTINGS — this is what the pre-v4 unique-index constraint missed entirely
   - a load test firing 1,000 CONCURRENT BOOKING ATTEMPTS asserting ZERO double-books — the regression canary for the whole transaction model
   - simultaneous admin confirmation of one payment submission
   - repeated idempotent POSTs
3. SECURITY: authorization on EVERY endpoint including reads; rate-limit verification across all tiers including messaging; admin auth; no sensitive data in logs; the three XSS payloads against every admin view.
4. THE CONTACT-INFO AUDIT — inspect EVERY response shape in the bookings, providers, listings, search and messaging modules and assert that none returns a phone number, with the single documented exception of POST /v1/bookings/:id/reveal-contact under its seven conditions. Verify by reading the response shapes, not only the ones expected to carry it.
5. STATE AUDIT across every screen: loading / empty / error / populated. This is a BACKSTOP verifying what each phase already specified — if you are designing these states for the first time here, the earlier phase was not done.
6. Performance: payload sizes, pagination, N+1 audit, verified against the plan's §5 targets.
7. Accessibility sweep: focus visibility, touch targets, screen-reader announcements on state changes, reduced-motion handling.

Definition of done: the full E2E path passes; 1,000 concurrent attempts produce zero double-books; the cross-listing overlap is rejected; every endpoint enforces authorization on reads as well as writes; the contact-info audit finds exactly one permitted path; §5's latency targets are met under a seeded catalogue.
```

---

## Phase 21 — Observability & Crash Reporting

```
Build observability. Note one sequencing correction: FLUTTER CRASH REPORTING IS PULLED FORWARD TO PHASE 3 — it wants to exist from the first real screen, not after twenty phases of building blind. This phase covers what remains.

1. Backend error tracking with request correlation IDs.
2. Uptime monitoring on /v1/health AND on the payment-submission endpoints specifically.
3. NOTIFICATION-DELIVERY OBSERVABILITY (Phase 3c): fallback-invocation rate, ALERTING ABOVE 5%. A rising email-fallback rate means push is quietly failing, which degrades the accept prompt the whole booking model depends on.
4. ProductEvent log — Phase 10c's dashboard reads this, so the event set must be complete before that phase: draft_created, listing_published, slot_published, booking_requested, booking_accepted, emergency_requested, emergency_unaccepted, contact_revealed, amount_set, payment_claimed, booking_confirmed, booking_completed, enquiry_started, contact_pattern_detected, trial_started, trial_converted, trial_expired, search_performed, verification_tier_granted.

Definition of done: deliberate backend and Flutter exceptions both surface within minutes; a broken payment endpoint triggers an alert; every event type is confirmed logging; the email-fallback alert fires when forced above threshold.
```

---

## Phase 10c — Admin Ops Dashboard

```
Add the ops dashboard to the Phase 10a/10b React admin app.

SEQUENCED HERE DELIBERATELY, not with 10b: the trend lines read Phase 21's ProductEvent log, so this is the only part of the admin panel that has to wait. Everything operationally needed from first launch shipped in 10b.

1. KPI cards: open items across every queue, bookings today and this week by status, active/trial/paid provider counts, published listings against the launch-mode threshold.
2. TWO TREND LINES: bookings over time, and trial-to-paid conversion SPLIT BY subscriptionPriceLaari COHORT. The cohort split is the point — it is what makes the introductory-pricing decision measurable rather than a guess.
3. Recent-activity feed: the latest audit-log entries — what was approved, rejected or resolved, and by whom.

Definition of done: the trial-to-paid line matches a manual query of the same data and correctly separates the introductory-rate cohort from the standard-rate one.
```

---

## Phase 22 — Content Moderation & Reporting

```
Build content moderation and reporting. The admin queue EXTENDS Phase 10a/10b's panel and reuses its auth and audit log — do not build a second admin surface.

1. Report entity: reporterId, targetType ('listing'|'review'|'user'|'booking'|'message'|'photo'), targetId, reason enum, status, reviewedBy, reviewedAt, RESOLUTION REASON.
2. Booking disputes and payment_unresolved escalations from Phase 17 FILE HERE AUTOMATICALLY, with both parties' history shown together.
3. ACTIONING HIDES, NEVER DELETES — reversible via the soft-delete visibility flag.
4. HIDDEN CONTENT STAYS VISIBLE TO ITS OWNER, who sees the category and reason and can appeal. Everyone else cannot find it.
5. Dispute resolution uses a FIXED ENUMERATION, never free text: resolved_for_customer, resolved_for_provider, inconclusive, fraud_confirmed, withdrawn. An unstructured outcome produces an audit log you cannot measure fairness against.
6. Review anti-spam: rate limit, and FLAG implausibly-fast reviews for a human look rather than auto-rejecting.
7. LISTING FREE-TEXT SCANNING for contact patterns — the provider-side leakage vector the chat nudge does not close. A provider publishing their own number in a description or FAQ is the realistic leak, and they have the incentive.
8. Contact-pattern aggregates from Phase 18 surface here as a PROVIDER-LEVEL SIGNAL, not per-message noise: "tripped detection in 40 of 52 enquiries". This is the enforcement mechanism that replaces an earlier revision's hard block.
9. Emergency accept-then-cancel patterns, and contact-reveal request patterns from 17.3, surface as provider-level and customer-level signals.
10. A confirmed-fraud outcome or an accumulated dispute pattern TRIGGERS A VERIFICATION REVIEW that may demote or revoke a tier (Phase 10a).
11. Report affordances: Service Preview overlay, review cards, provider profile, conversation threads, listing photos.

NOT IN SCOPE, deliberately: a proactive risk-signal dashboard ranking users by accumulated signals. Signals surface alongside a filed report. Do not build a standing queue.

Definition of done: each report type reaches the queue with enough context to act; actioning hides content from everyone but its owner; the owner sees the reason and can appeal; a Phase 17 dispute appears with both parties' history; dispute resolution rejects a free-text outcome; a provider with repeated contact-pattern detections is visible as an aggregate; a fraud_confirmed outcome triggers a verification review.
```

---

## Phase 23 — Legal, Compliance & App Store Readiness

```
NOT PRIMARILY A CODING TASK. Build screens and section structure with CLEARLY-MARKED PLACEHOLDERS. Do NOT write binding legal language — that is for a qualified human.

START THIS IN PARALLEL WITH PHASE 5, not when you reach this point in the sequence. Its data-protection and identity-document research gates Phases 5 and 1e directly — those are the phases that actually collect and store ID documents and bank details, and discovering a different required retention model after they ship is a rebuild, not a course correction.

1. Unified Terms of Service (customers and providers) + a SEPARATE Provider Agreement covering subscription, trial, cancellation, the manual bank-transfer process, and dispute handling.
2. Privacy Policy. IT MUST COVER, because these are non-obvious and currently undocumented: admin access to message content via a named report or dispute (never via view-as-user); identity-document retention and the 90-day purge; internal retention of review authorship after account anonymisation; and what queued account deletion means in practice.
3. Provider Agreement linked from the Payment Proof Submission flow, where it is most relevant.
4. Identity verification screens and the FORMAL EVIDENCE CHECKLIST implementing the three tiers — including the rejection-reason taxonomy and the resubmission path. A rejected provider must get a real reason.
5. App Store account deletion: built in Phase 3 with queued semantics. VERIFY it meets the current requirement — an accepted-and-queued deletion satisfies the rule; a refusal would not.
6. Support contact path in-app.

THREE RESEARCH QUESTIONS, none of which are coding tasks, all of which can change earlier work:
   - App Store subscription compliance: does selling a subscription this way require in-app purchase? A negative answer forces a data-model change, so resolve it before Phase 8a goes deep.
   - Maldivian data-protection status and what it requires of identity-document handling.
   - GST obligations on the subscription revenue.

Definition of done: every legal screen renders with clearly-marked placeholder content and correct navigation; the verification checklist matches the three tiers exactly; the privacy policy's structure has a named section for each of the four items in point 2; all three research questions have written answers.
```

---

## Phase 24 — Staging Environment & Deployment Hardening

```
Build the staging environment and harden deployment.

1. Staging environment mirroring production configuration, with its own database and its own object storage buckets. NEVER point staging at production data.
2. Migration strategy: forward-only, reviewed, tested against a production-shaped dataset before release.
3. BACKUPS WITH A DRILLED RESTORE — RPO 24 hours, RTO 4 hours. DRILL THE RESTORE in this phase; an untested backup is an assumption, not a recovery plan.
4. Secrets management. No secrets in the repo, in CI logs, or in error payloads.
5. Deployment: zero-downtime or clearly-communicated maintenance windows; a documented rollback procedure.
6. Seed script producing a realistic dataset — enough providers, listings, slots and bookings to exercise launch mode, search ranking, and the concurrency tests.
7. RUN A SYNTHETIC SLOT-GENERATION BENCHMARK against 2,000 providers to confirm the nightly job completes inside its window before it becomes a 3am page.

Definition of done: staging runs the full stack independently of production; a backup is restored end-to-end in a drill and the app boots against it; a rollback is executed successfully at least once; the slot-generation benchmark completes within the maintenance window at 2,000 providers.
```
