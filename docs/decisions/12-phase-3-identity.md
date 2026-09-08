# Phase 3 — Identity & Authentication, and where the build departed from the design

**Status: built 2026-09-07. Plan revision 5.20, §Phase 3, §1e, and the §0.0 items
that amend §Phase 3 — 6 (no SMS), 8a (phone uniqueness from Bronze), 17 (email
built against the file transport).**

Phase 3 turns `docs/superpowers/specs/2026-09-06-phase-3-identity-design.md`
into register/login, JWT access + refresh rotation, email OTP, the three user
guards, account settings, data export, the deletion pipeline and the anonymisation
job. That design spec recorded the decisions the plan leaves to the implementer
before the build started; this file records what changed once code was actually
written and reviewed against it, and what the build leaves for later phases.

## The decisions

Decided in the design spec (§"What the plan pins, and what it leaves open") and
confirmed unchanged by the build. Not restated here — see the spec for the full
reasoning behind each.

| # | Decision | Choice |
|---|---|---|
| 1 | Where Business/Trade Name and `verificationTier` live before Phase 5 | A minimal `ProviderProfile` now (`userId`, `businessName`, `verificationTier` default `none`, `verificationStatus` default `unverified`), created by `getOrCreateProviderProfile` when a *provider* registers |
| 2 | Saved preferences (§Phase 3 account-settings bullet) | Deferred past Phase 4 — needs `Island`, which Phase 4 seeds |
| 3 | Flutter crash reporting (pulled forward from Phase 21) | Sentry behind a `CrashReporter` interface, no-op with no DSN |
| 4 | Done-when lines needing Phase 11/17 entities | Build the seams, verify end to end at the owning phase; each recorded as met for the mechanism with a ledger row |
| 5 | "A recovery attempt without a verified email is refused" | Testable now as a guard, so tested now — `assertRecoverableByEmail` |
| 6 | Access token | JWT HS256 under `AUTH_JWT_SECRET`, 15 minutes, claims `sub`/`sid`; session and user reloaded on every request |
| 7 | Refresh token | Opaque 32 random bytes, sha256 at rest, rotated every refresh, 30-day sliding window, 30-second reuse-grace before `refresh_reuse` revokes the session |
| 8 | OTP shape | Six digits, 10-minute expiry, sha256 at rest, both send limits enforced inside one locked transaction, five wrong attempts invalidate every live code |
| 9 | User password rules | Minimum 8, maximum 512, no composition rules, argon2id |
| 10 | Registration idempotency subject | `anon:<ip>` confirmed |
| 11 | Data export delivery | Synchronous JSON from `GET /v1/users/me/data-export`, sections from an `ExportContributor` registry |
| 12 | Marketing and weekly-digest toggles on Account Settings | Left to Phase 19 |
| 13 | "Change phone (re-verified)" | Format and Bronze-uniqueness re-checked; the number is never verified |
| 14 | Device identity for sessions | Client sends `deviceName`; no IP geolocation |
| 15 | App-level scheduled work | A Node job runner (`src/jobs/runner.ts`), one Postgres advisory lock per job, heartbeat upsert |
| 16 | Deletion request and sessions | Sessions stay live after a deletion request; anonymisation revokes everything |

## What was built

| Plan item | Module | File(s) |
|---|---|---|
| Schema: users, sessions, refresh tokens, OTPs, minimal provider profile | Prisma schema | `backend/prisma/schema.prisma`, `backend/prisma/migrations/20260907043955_phase3_identity/` |
| `AUTH_JWT_SECRET` and the auth config block | `config/env.ts` | `backend/src/config/env.ts`, `backend/.env.example` |
| Access tokens, the widened `Principal` union, the three user guards | `core/principal.ts`, `modules/auth/{tokens,guards}.ts` | `backend/src/core/principal.ts`, `backend/src/modules/auth/tokens.ts`, `backend/src/modules/auth/guards.ts` |
| Sessions: repository, `AuthService` core, `user-auth` plugin, `/refresh` `/logout` `/me` `/sessions` | `modules/auth/{repository,dto,service,schema,routes}.ts`, `plugins/user-auth.ts` | `backend/src/modules/auth/repository.ts`, `backend/src/modules/auth/dto.ts`, `backend/src/modules/auth/service.ts`, `backend/src/modules/auth/schema.ts`, `backend/src/modules/auth/routes.ts`, `backend/src/plugins/user-auth.ts` |
| Phone normalisation, the OTP service, `verify-email/send` + `/confirm` | `modules/auth/{phone,otp}.ts` | `backend/src/modules/auth/phone.ts`, `backend/src/modules/auth/otp.ts`, `backend/src/core/errors.ts` (`RetryAfterCarrier`) |
| Register, login, field-level duplicate email/phone, Bronze-only phone exclusivity, social-auth stubs | `modules/auth/{service,social,schema,routes,repository}.ts` | `backend/src/modules/auth/social.ts` |
| Account settings: change password, change email (re-verified at the new address), change phone, `assertRecoverableByEmail` | `modules/account/{service,schema,routes}.ts` | `backend/src/modules/account/service.ts`, `backend/src/modules/account/schema.ts`, `backend/src/modules/account/routes.ts` |
| Data export with contributor sections; deletion request (202, frozen, 30-day deadline, idempotent) | `modules/account/{export,service,routes}.ts` | `backend/src/modules/account/export.ts` |
| Job runner (advisory lock, heartbeat), anonymisation job and hooks | `jobs/{runner,anonymise-accounts}.ts`, `modules/account/anonymise.ts` | `backend/src/jobs/runner.ts`, `backend/src/jobs/anonymise-accounts.ts`, `backend/src/modules/account/anonymise.ts`, `backend/src/main.ts` |
| Redaction keys, the Done-when end-to-end test, CI secret | `core/logging.ts` | `backend/src/core/logging.ts`, `backend/src/app.ts` (`AppDeps.logStream` test seam), `backend/test/phase3-done-when.test.ts`, `.github/workflows/ci.yml` |

## Where the build departed from the design

Each of these is a review finding from the build ledger
(`.superpowers/sdd/2026-09-06-phase-3-identity-backend/`) that changed the
merged code — not a hypothetical risk, something the review actually caught
and a ruling actually fixed.

- **Every `preHandler: requireAuth` on the Phase 3 routes let an
  unauthenticated, malformed request answer 400 instead of 401.** Fastify
  validates a route's body/params between `preValidation` and `preHandler`
  (`onRequest → preParsing → preValidation → Validation → preHandler →
  handler`), so a guard attached at `preHandler` runs after validation — an
  anonymous caller sending a body that also fails schema validation got 400,
  never reaching the guard. Found first on the account-settings routes (Task
  6), confirmed present on every Phase 3 `auth` route in the same commit's
  follow-up review, and fixed by moving all of them (`logout`, `me`,
  `sessions` GET, `sessions/:id` DELETE, `verify-email/send`,
  `verify-email/confirm`, and the four `/v1/users/me/*` account routes) to
  `preValidation`. `guards.ts` now documents the rule on `requireAuth` so a
  future route doesn't repeat it. `modules/admin-auth/routes.ts` (Phase 2)
  still uses `preHandler` throughout and was explicitly left alone — flagged
  as the same class of bug likely existing there too, but out of scope for
  this phase.
- **`markEmailVerified` could report success and audit a verification that
  never happened.** It updated the user row keyed on `{ id, email:
  targetEmail, emailVerifiedAt: null }` without checking the row count — if
  the account's email had changed since the code was issued, or the account
  was already verified by a second concurrent request, the `updateMany`
  matched zero rows, yet the route still returned 200 and wrote a
  `user.email.verified` audit entry. Fixed to check `updated.count === 0` and
  throw `OTP_EXPIRED` before the audit call, inside the same transaction, so
  the whole thing rolls back rather than fabricating a success.
- **Pino redaction matched exact key depth, not "any depth," across the
  whole Phase 3 field set.** Following the pattern Phase 2 already fixed for
  its own keys, this task's `SENSITIVE_KEYS` list was extended to the full
  set the plan's fields require (`currentPassword`, `newPassword`,
  `newEmail`, `phoneE164`, `number`, `fullName`, `accessToken`,
  `refreshToken`, `idToken`) and a nested-object test was added asserting none
  of those literal values survive a real log line.
- **No test exercised the anonymisation job through its actual production
  path.** Every existing test either called `anonymiser.runDue(...)`
  directly or drove `JobRunner` with a synthetic job — nothing ran the
  registered `anonymise-deleted-accounts` job through `JobRunner.runOnce`,
  which is the one path where the runner's advisory-lock transaction and the
  anonymiser's own per-user transaction actually compose across two pooled
  connections. Fixed with one added test asserting the registered job runs
  end to end and writes the heartbeat.

## Prototype divergences flagged

- **`Account Settings.dc.html`'s data-export copy** — "arrives as a file sent
  to your email, usually within a day" — contradicts the plan, which
  specifies a synchronous `GET /v1/users/me/data-export` returning the data
  directly. The backend implements the plan's synchronous shape; the
  prototype's copy is flagged for correction in a later design pass, not
  built against.
- **The `· Malé` suffix on a sessions-list row** implies IP geolocation. No
  such mechanism exists anywhere in this build — the client sends only a
  `deviceName` string. The prototype's location suffix is flagged as
  unbuildable as drawn; `sessionDto` carries no location field.

## Done-when, line by line

Plan §Phase 3's Done-when sentence, taken clause by clause:

- **"Full register → verify → logout → login cycle works"** — met.
  `test/phase3-done-when.test.ts` runs it end to end against the real file
  transport and a real Postgres database, reading the OTP out of the written
  JSON file exactly as a person would from a mailbox.
- **"An unverified user browses freely but is rejected by
  `requireEmailVerified`"** — met. Same test: `/v1/auth/me` (browsing) is 200
  before verification; a route guarded by `requireEmailVerified` is 422
  `EMAIL_NOT_VERIFIED` before, 200 after.
- **"Registering with an already-used email is blocked naming the email,
  and with an already-used phone is blocked naming the phone, each offering
  login or reset"** — met. `test/auth-register-login.test.ts` asserts
  `EMAIL_IN_USE`/`PHONE_IN_USE` with `details[0].path` naming the field;
  phone blocking is Bronze-and-above only, per §Phase 3's Round 15 rule.
- **"Both OTP rate limits verified independently"** — met.
  `test/auth-otp.test.ts` exercises the 3-per-address-per-15-minutes and
  5-per-account-per-hour limits as two separate concurrency scenarios inside
  one locked transaction, each answering `OTP_RATE_LIMITED` with
  `retryAfterSeconds`.
- **"A deleted account's reviews remain with anonymised attribution"** — met
  for the mechanism (ledger row P1). `AnonymisationHooks` and
  `AccountAnonymiser` are built and tested with a registered hook running
  inside the anonymisation transaction; there is no `Review` entity yet for
  a real hook to attach to.
- **"Export returns complete data"** — met. `test/account-export-deletion.test.ts`
  asserts the export's `account`/`providerProfile`/`sessions` sections and
  that a registered `ExportContributor`'s section is included, with no
  password hash, token hash, or other-user data anywhere in the body.
- **"A deletion request with an open booking is accepted and freezes the
  account rather than erroring, completes automatically when that booking
  terminates, and completes anyway at the 30-day backstop"** — met for the
  mechanism (ledger row P2) for "completes when the booking terminates" (the
  `DeletionBlocker` seam is built and tested with an injected blocker; there
  is no real booking yet to terminate), and met outright for "accepted and
  frozen rather than erroring" and for the 30-day backstop —
  `test/account-anonymisation.test.ts` advances the clock past the deadline
  and asserts anonymisation fires with reason `deletion_backstop` regardless
  of blocker state.
- **"An email confirmation link verifies and a recovery attempt without one
  is refused"** — the plan's phrasing describes a link; this build's
  approved design (decision 24 in the linked spec) is a six-digit code, not
  a link, so "verifies" is met via the code-confirm flow. "A recovery
  attempt without one is refused" is met for the guard (ledger row P3):
  `assertRecoverableByEmail` is built and unit-tested to throw
  `EMAIL_NOT_VERIFIED` for an unverified account; the full reset flow that
  calls it is Phase 3b's.

## Unverified

Nothing in this phase reaches a real mailbox — every email-dependent flow
(registration, OTP, verification) is built and verified against
`EMAIL_TRANSPORT=file`, per §0.0 item 17 and
`docs/decisions/11-email-deferred-to-deployment.md`. `docs/deferred-verification.md`
row L8 records what a real inbox closes.

Flutter crash reporting (`CrashReporter`, pulled forward to this phase per
the design spec) is built: the interface and a no-op implementation active
only without a `SENTRY_DSN` (`frontend/lib/core/crash/`), exercised by
`test/core/crash/crash_reporter_test.dart`. Nothing has run against a real
Sentry project — that needs a real DSN, which this build does not have.
`docs/deferred-verification.md` row L9 records what closes it.

## What Phase 3b / 5 / 6 / 11 / 17 must pick up

- **`assertRecoverableByEmail`** (`backend/src/modules/account/service.ts`) —
  Phase 3b's password-reset flow calls this before sending anything; its own
  confirmation step must not reveal account existence, so there the refusal
  becomes a silent non-send rather than a visible error.
- **The four `ProviderProfile` columns and `getOrCreateProviderProfile`**
  (`backend/src/modules/auth/repository.ts`) — Phase 5 adds every other
  provider-profile column additively onto this minimal row, built one phase
  early so Business/Trade Name and `verificationTier` have somewhere to live
  at registration.
- **Saved preferences**, deferred out of this phase's Account Settings
  screen — Phase 6 or Phase 7 builds it once `Island` exists (Phase 4), never
  keyed by island name (§0.0 item 12).
- **`AnonymisationHooks`** (`backend/src/modules/account/anonymise.ts`) —
  Phase 11 registers the review-anonymisation hook; its test asserts a review
  survives with the author anonymised (ledger row P1).
- **`ExportContributors`** (`backend/src/modules/account/export.ts`) — every
  later phase that owns user-authored data registers a contributor so it
  appears in the export; nothing currently registers one beyond the account
  section itself.
- **`DeletionBlocker`** (`backend/src/modules/account/anonymise.ts`) — Phase
  17 supplies the real check against open bookings, replacing `neverBlocks`
  (ledger row P2).
- **`requireActiveAccount`** (`backend/src/modules/auth/guards.ts`) — built
  and exported in this phase but not yet attached to any route; later phases
  place it on booking- and listing-creation endpoints, per the plan's freeze
  rule.

## Frontend

Nine tasks (`.superpowers/sdd/2026-09-06-phase-3-identity-frontend/`) built
the Flutter half against `01_Development_Plan_v5.md` §Phase 3 and §1e:
`core/api`, `core/auth`, `core/crash`, Sign In, Register, Verify Email
(email OTP, shared with change-email), Session expired, `AuthGate` and the
route table, Account Settings and its sessions/download/delete sub-screens,
and — this task — Change password, Change email and Change phone. Per-file
detail is in `frontend/lib/README.md`; this section carries only what
changed once code met the design and the plan, and what a later phase must
know.

### Done-when, frontend clause

Plan §Phase 3's line — "Frontend: Login, Register (pixel-match), OTP
verification screen, account settings sub-screens" — clause by clause:

- **Login** — Sign In (`frontend/lib/features/auth/presentation/sign_in_screen.dart`),
  every listed state tested in `test/features/auth/sign_in_screen_test.dart`.
- **Register (pixel-match)** — `register_screen.dart` against
  `Register.dc.html`, `EMAIL_IN_USE`/`PHONE_IN_USE` field renderings and the
  provider variant's Business/Trade Name field, tested in
  `test/features/auth/register_screen_test.dart`.
- **OTP verification screen** — `verify_email_screen.dart`, one screen
  serving two purposes (`OtpPurpose.verifyEmail` / `.changeEmail`), all
  eight modes and both clocks tested in
  `test/features/auth/verify_email_screen_test.dart`.
- **Account settings sub-screens** — `account_settings_screen.dart`,
  `active_sessions_screen.dart`, `download_data_screen.dart`,
  `delete_account_screen.dart` (Task 8), and this task's
  `change_password_screen.dart`, `change_email_screen.dart`,
  `change_phone_screen.dart`, each with its own controller
  (`account_controller.dart`, `change_controllers.dart`) and test file under
  `test/features/account/`. `test/features/auth/phone_never_verified_test.dart`
  is the cross-screen design-rule test (root CLAUDE.md §0.0 item 6): no tick
  icon beside a phone-shaped `Text`, no `Text` combining a phone number with
  the word "verified", checked across Register (after `PHONE_IN_USE`),
  Change phone (before and after success) and Account Settings populated.

### Prototype divergences and non-prototype copy

Every one-line item below is copy or layout the prototypes do not specify
(`Account Settings.dc.html`'s three change rows only carry a `toastMsg`
placeholder — "Opens change password", "Opens change email — verify
pattern", "Opens change phone" — with no sub-screen drawn) or a deliberate
departure from what they do specify. Each is flagged here, not silently
resolved either way, per root CLAUDE.md's scope-discipline rule.

- **Sign In omits the prototype's icon badge beside the wordmark** and
  renders `Continue as Guest` as a secondary button, not the prototype's
  inline link — the plan's own sample screen shows a button there.
- **The generic error banner `Something went wrong. Please try again.`**
  (Sign In, Register, Verify Email, and this task's three change screens)
  is not prototype copy — `App States.dc.html` has no generic-error state
  drawn; it is one fixed string reused everywhere a server code is
  unrecognised, per the routing-on-`code` rule.
- **The expired-code copy `That code has expired. Send a fresh one.`**
  (Verify Email) is not prototype copy — `OTP_EXPIRED` is its own mode,
  distinct from the 5-wrong-attempts `OTP_INVALIDATED` copy the prototype
  does carry.
- **The frozen-account row subtitle `No new bookings or listings until it
  completes`** (Account Settings) is not prototype copy.
- **Data export goes to the OS share sheet**, not the prototype's "emailed
  within a day" — the plan specifies a synchronous
  `GET /v1/users/me/data-export` (backend decision above), so there is
  nothing to email; flagged for a later design-copy correction, not built
  against.
- **Session rows omit the prototype's `· Malé` location suffix** — no
  mechanism in this build geolocates a session; the client sends only a
  `deviceName` string (same finding as the backend section above, extended
  to the row that renders it).
- **The Register email hint is `you@example.mv`**, not the fixture's sample
  address `aishath@example.mv` — a hint whose text exactly matches typed
  content stays mounted at opacity 0 rather than leaving the tree, which
  would be a second match for any `find.text` on that value. The same hint
  is reused on Sign In and this task's Change email.

### This task (9): Change password, email, phone

- **The Session Expired promise is backed here, for the first time, by a
  test.** `FormDraftStore` existed since Task 2 and Register (Task 5) saves
  a draft on the same path, but this task is where a screen actually
  restores one on the next build after sign-in and a test asserts the round
  trip. `ChangeFormController.run` saves the caller-supplied `draft` map
  under the screen's route name whenever a submit answers `SESSION_EXPIRED`;
  each screen's `initState` calls `FormDraftStore.take` for its own key.
  Change password's draft is always `const {}` — every one of its three
  fields is a password, and a password is never written to the draft store
  — so its round-trip test asserts the save-and-restore path runs without
  crashing and prefills nothing, which is the correct behaviour for a
  screen with no non-secret field to keep.
- **Brief-vs-toolchain: `ChangeFormController.run<T>` under Dart 3.13.** The
  brief's `ChangePasswordController.submit` passed `changePassword` (which
  returns `Future<void>`) straight into `run<T>` and compared the result
  with `!= null`; with `T` inferred as `void`, that comparison does not
  analyze under Dart 3.13 (a bare `void` excludes `null`). Fixed minimally:
  the action wraps the `void` API call and resolves `true`, so `run` carries
  a real `bool`.
- **Brief-vs-backend: `changePhoneBody` is the bare `{dialCode, number}`
  shape** (`backend/src/modules/auth/schema.ts`'s `phoneField`, reused
  as-is for `PATCH /v1/users/me/phone`), not a `phone`-nested body, so a
  `VALIDATION_FAILED` field path is `dialCode` or `number`, never `phone` —
  only the client's own `PHONE_IN_USE` mapping uses the `phone` key.
  `change_phone_screen.dart` renders whichever of the three keys the server
  used under the one field the screen shows.
- **Change phone's `PHONE_IN_USE` copy is shorter than Register's own**:
  "This number belongs to a verified provider account." with no inline
  sign-in link — Register's longer copy offers a route to sign in because
  the visitor may not yet have an account open; Change phone's visitor is
  already signed in, so that link has nothing to add.
- **Build-configuration note: `frontend/android/app/build.gradle.kts`
  now pins `compileSdk = 37`**, replacing `compileSdk =
  flutter.compileSdkVersion` (which resolved to 36). Surfaced only during
  this task's manual emulator run, not by any earlier `flutter analyze` or
  `flutter test` gate: `flutter_secure_storage` 11.0.0 (already a Task 1/2
  dependency, for `TokenStore`) requires `compileSdk` 37 or later, and the
  Gradle build fails outright (`checkDebugAarMetadata`) below it. AGP
  9.1's own "the maximum recommended compileSdk is 36" warning is expected
  and not a regression — it is AGP being one release behind the plugin's
  floor, not a real ceiling. `minSdk` and `targetSdk` are untouched. No
  other Android config changed.

### Flagged, not done

- **A shared checkbox widget under `lib/shared/`.** Register's terms
  checkbox (`register_screen.dart`) is bespoke, built once and not
  generalised; a second caller should trigger extracting it, not this task
  inventing a shared widget nobody else needs yet.
- **Folding `SettingsRow` onto `AppCard.row`.** `SettingsRow`
  (`features/account/presentation/widgets/settings_row.dart`) already
  builds on `AppCard`'s built-in `Pressable` path rather than double-wrapping
  it (documented in that file); collapsing the two into one shared
  `AppCard.row` constructor is a `shared/` change out of scope for this
  phase and is left for whoever next needs the same row shape outside
  `features/account/`.

### Riverpod 3 note

`frontend/CLAUDE.md` now states the rule this phase's controllers
(`account_controller.dart`, and by the same reasoning every
`AsyncNotifierProvider` that renders its own error state) apply: pass
`retry: null` so a failed `build()` does not silently retry with
exponential backoff for up to ~30s before the screen's own error branch
ever shows.

### Dev-server walkthrough

See the report for this task
(`.superpowers/sdd/2026-09-06-phase-3-identity-frontend/task-9-report.md`)
for the emulator run's step-by-step outcome — screens reached, and the OTP
code read back out of `backend/.mail/` under the file transport
(§0.0 item 17).
