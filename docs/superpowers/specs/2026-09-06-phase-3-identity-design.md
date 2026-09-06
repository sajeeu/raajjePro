# Phase 3 — Identity & Authentication: design

**Status: approved 2026-09-06, before implementation. Plan revision 5.20, §Phase 3, §1e, and the §0.0 items that amend §Phase 3 — 6 (no SMS), 8a (phone uniqueness from Bronze), 17 (email built against the file transport).**

This document does not restate §Phase 3. It records the decisions the plan leaves to the implementer, the concrete contract those decisions produce, and how each Done-when item is verified. Where it and the plan disagree, the plan wins and the disagreement is a defect here.

The design reference for every screen is the set of prototypes in `mockups/design-composer/` — `Sign In`, `Register`, `Verify Email`, `Account Settings`, and `App States` for the session-expired state. §Phase 3 marks the OTP and account-settings screens "propose first"; those proposals were made and reviewed in design sessions 8 and 9 (`docs/design/sessions/09-identity*.md`, `10-account*.md`) and the prototypes are the approved result. Where a prototype and the plan disagree, the plan wins and the divergence is recorded below.

## What the plan pins, and what it leaves open

Pinned by §Phase 3, §1e, §2 and §0.0: register, login, JWT access + refresh rotation with per-device refresh tokens, logout, `me`; a provider-agnostic social-auth interface with stubs for Facebook, Google, Viber and (per §1 divergence 6) Apple; email OTP with `emailVerified` and a `requireEmailVerified` guard returning a distinct `EMAIL_NOT_VERIFIED`; OTP sends limited to **3 per address per 15 minutes and 5 per account per hour, both**, **5 attempts per code** then invalidated, breaches answered with `OTP_RATE_LIMITED` carrying the seconds remaining; phone collected in E.164 with `+960` default, 6–15 digits, foreign numbers accepted, never verified, never shown with a check mark; `email` unique at the database; phone unique **only against holders at Bronze or above**, blocked at the field naming it; duplicate email blocked at the field naming it with routes to sign in or reset; account settings — change password, change email (re-verified by OTP), change phone, active sessions with per-device revoke, data export as JSON from `GET /v1/users/me/data-export`, account deletion queued never refused, frozen at once, anonymised when open bookings terminate or at 30 days, ID documents purged, admin notes deleted with the account; recovery of a lost mailbox is manual admin review (Phase 10b), never automated; email sent only through `EmailSender` against `EMAIL_TRANSPORT=file` for now; bounce handling already exists and is not rebuilt.

Left open, and decided here (product owner, 2026-09-06):

| Decision | Choice | Alternatives declined |
|---|---|---|
| Where Business/Trade Name and `verificationTier` live before Phase 5 | **A minimal `ProviderProfile` now**: `userId`, `businessName`, `verificationTier` (default `none`), `verificationStatus` (default `unverified`), timestamps, plus `getOrCreateProviderProfile(userId)`. Registering as *Offer Services* creates the row. Phase 5 adds every other column additively. Recorded as a seam built one phase early. | A `signupBusinessName` hint on `User` (bends invariant 1, and leaves the Bronze-uniqueness rule with nothing to read); dropping the field from Register (contradicts plan §1 and the approved prototype). |
| Saved preferences (§Phase 3 account-settings bullet) | **Deferred past Phase 4.** A saved address carries an island; `Island` is seeded in Phase 4 and is never keyed by name (§0.0 item 12). Built after `Island` exists, with Phase 6 or Phase 7. Account Settings shows no Saved preferences row in this phase. | Windows and instructions now, addresses later (splits one feature); an `Island` table now (builds Phase 4's seed ahead of Phase 4). |
| Flutter crash reporting (§4: pulled forward from Phase 21) | **Sentry, behind a `CrashReporter` interface, disabled when no DSN is configured** — the same posture as SES. Phase 21 reuses it for the backend. | Firebase Crashlytics (needs a Firebase project now; 3c will bring Firebase for FCM); deferring to 3c (contradicts §4). |
| Done-when lines that need Phase 11 or Phase 17 entities | **Build the seams, verify end to end at the owning phase.** Anonymisation runs a hook registry later phases register into; the open-bookings check is a `DeletionBlocker` seam answering "none" until Phase 17; the 30-day backstop is tested by advancing the clock. Each is recorded as *met for the mechanism* in those words, with a row in `docs/deferred-verification.md` naming the phase that closes it — never as met outright. | Stub `Review` and `Booking` tables here; stop the phase with the lines open. |
| "A recovery attempt without a verified email is refused" | **Testable now as a guard, so tested now.** `assertRecoverableByEmail(user)` in the auth service throws 422 `EMAIL_NOT_VERIFIED` for an unverified account and is the one predicate Phase 3b's reset flow calls before sending anything (3b's confirmation must not reveal existence, so there the refusal becomes a silent non-send — the predicate is the same). The full flow lands in 3b; the rule itself is asserted here. | Deferring the whole line to 3b (the ledger's own rule: if a line is testable now, test it now). |
| Access token | **JWT, HS256 under `AUTH_JWT_SECRET`, 15 minutes**, claims `sub` (user id) and `sid` (session id). The auth plugin verifies it *and then loads the session and user in one query*, so revocation, freezing and email verification take effect on the next request rather than at token expiry. | Opaque access tokens (the plan says JWT); an asymmetric key (one issuer, no third-party verifier); trusting the JWT alone (force-logout would not work until expiry). |
| Refresh token | **Opaque 32 random bytes, stored as sha256, one row per issue, rotated on every refresh, 30 days sliding.** Presenting a token that was already rotated **more than 30 seconds ago** revokes the whole session (`refresh_reuse`); within 30 seconds it is treated as a client retry race and answered 401 `REFRESH_TOKEN_ROTATED` without revocation. | A single `refreshTokenHash` column overwritten in place (cannot distinguish a stolen old token from garbage); no grace window (a mobile retry would sign the real user out). |
| OTP shape | **Six digits, 10-minute expiry, sha256 at rest keyed by the row id, every live code for a purpose stays valid until it expires** (the approved Verify Email copy says so). Both send limits enforced in the domain — they key on address and account, not IP — inside a transaction that locks the user row, so concurrent sends cannot slip a fourth through. Five wrong attempts invalidate every live code for that purpose (`OTP_INVALIDATED`). | A link (the prototypes settled code entry; a link needs deep links the app does not have); superseding older codes on resend (contradicts the approved copy and punishes slow mail). |
| User password rules | **Minimum 8, maximum 512, no composition rules, argon2id** via the Phase 2 crypto module. | 12 like admins (admin credentials guard money and identity; a customer password guards a booking history). |
| Registration idempotency subject | **`anon:<ip>` confirmed** — the Phase 2 proposal. Client keys are UUIDs, so accounts behind one NAT address cannot collide. | `anon:<sha256(email)>`. |
| Data export delivery | **Synchronous JSON from `GET /v1/users/me/data-export`, as §Phase 3 says.** The Flutter screen hands the document to the OS share sheet. The `Account Settings` prototype's copy — "arrives as a file sent to your email, usually within a day" — contradicts the plan and is flagged for correction. Sections come from an `ExportContributor` registry later phases add to. | An emailed export job (the prototype's copy; not what the plan specifies). |
| Marketing and weekly-digest toggles on Account Settings | **Left to Phase 19**, which owns the digest. The Phase 3 screen renders the rows §Phase 3 names and nothing else. | Two boolean columns now. |
| "Change phone (re-verified)" | **Format and Bronze-uniqueness are re-checked; the number is never verified.** §0.0 item 6 removed phone verification system-wide and outranks the parenthetical. | — |
| Device identity for sessions | **The client sends `deviceName`** (≤ 80 chars, from `device_info_plus`). No IP geolocation — the prototype's `· Malé` is dropped. | — |
| App-level scheduled work | **A Node job runner** (`src/jobs/runner.ts`): interval-driven, one Postgres transaction-scoped advisory lock per job so two instances never run the same job at once, each run upserting the Phase 0 `job_heartbeat` row for its job name. pg_cron stays for SQL-only jobs; anonymisation calls hooks later phases register in Node (purging documents from a bucket is not SQL). | A SQL anonymisation job under pg_cron (cannot run Node hooks); a queue service (not in the plan). |
| Deletion request and sessions | **Sessions stay live after a deletion request.** The prototype returns the user to Home in the frozen state, and §Phase 3 wants open bookings to run to completion — that needs chat, which needs a session. Anonymisation revokes everything. *(Refines the approved design summary, which said sessions are revoked at request time.)* | Revoke at request. |

## 1. Data model

One Prisma migration, `phase3_identity`. Every model follows the schema header conventions (UUID ids, `snake_case` via `@map`, `Timestamptz(6)`, a status field instead of deletion).

- **`User`** — `email` (unique, stored lower-cased), `emailVerifiedAt` (nullable; null = unverified), `passwordHash` (argon2id), `fullName`, `phoneE164` (nullable in the schema for anonymisation; required at registration; indexed, **not unique** — §0.0 item 8a), `status` (`active` | `frozen` | `anonymised` — the soft-delete field), `termsAcceptedAt`, `deletionRequestedAt`, `deletionDeadlineAt`, `anonymisedAt`, `passwordChangedAt`, `createdAt`, `updatedAt`.
- **`ProviderProfile`** (minimal, see decision) — `userId` (unique FK), `businessName` (nullable), `verificationTier` (`none` | `bronze` | `silver` | `gold`, default `none`), `verificationStatus` (`unverified` | `pending` | `verified`, default `unverified`), `createdAt`, `updatedAt`. The two enums are the ones §1e names; Phase 5 must not redefine them.
- **`UserSession`** — one per device. `userId`, `deviceName`, `ipAddress`, `userAgent`, `createdAt`, `lastSeenAt`, `revokedAt`, `revokedReason` (`logout` | `revoked_by_user` | `refresh_expired` | `refresh_reuse` | `password_change` | `email_change` | `anonymised`). Index `(userId, revokedAt)`. A separate enum from Phase 2's admin one; the two lifecycles share only the word.
- **`RefreshToken`** — `sessionId`, `tokenHash` (unique, sha256 of the 32-byte token), `createdAt`, `expiresAt`, `rotatedAt` (nullable), `replacedById` (nullable). The current token for a session is the one with `rotatedAt IS NULL`.
- **`EmailOtp`** — `userId`, `purpose` (`verify_email` | `change_email`), `targetEmail` (the address the code went to — the account's current address, or the new one for a change), `codeHash`, `attempts`, `expiresAt`, `consumedAt`, `invalidatedAt`, `emailMessageId` (nullable FK to `email_message`, so "did the code actually go out?" is one join), `createdAt`. Indexes `(userId, purpose, createdAt)` and `(targetEmail, createdAt)` — the two rate-limit counts.
- **`AuditActorType`** gains `user`. User-initiated security events are audited with `actorType: 'user'`, `actorId` = user id: `user.registered`, `user.login.succeeded`, `user.login.failed` (target = user id, wrong password or frozen; an unknown email produces a log line, never an audit row — same rule as admins), `user.logout`, `user.session.revoked`, `user.email.verified`, `user.password.changed`, `user.email.changed`, `user.phone.changed`, `user.deletion.requested`; and with `actorType: 'system'`: `user.session.revoked` (reason `refresh_reuse` | `refresh_expired`), `user.anonymised` (reason `bookings_terminal` | `deletion_backstop`). Metadata is ids and enums only.

## 2. Request principal, guards, plugin order

`core/principal.ts` becomes `type Principal = AdminPrincipal | UserPrincipal` with `UserPrincipal = { kind: 'user'; id; sessionId; emailVerified: boolean; status: 'active' | 'frozen' }`.

`plugins/user-auth.ts` runs `onRequest`, registered beside the admin-session plugin and before rate limiting so counters key on the user. It reads `Authorization: Bearer <jwt>`; no header means an anonymous request and nothing happens. With a header: verify signature, `iss`, `aud`, `exp` (`jose`); then load the session with its user by `sid`. Outcomes, kept on `request.sessionRejection` for the guard to report:

| Situation | Code (401) | Client behaviour |
|---|---|---|
| No header, malformed or badly signed token | `UNAUTHENTICATED` | sign in |
| Signature valid, `exp` passed | `ACCESS_TOKEN_EXPIRED` | refresh silently, retry once |
| Session revoked, refresh expired, or user anonymised | `SESSION_EXPIRED` | "Signed out for your security" (App States) |

A live session sets `request.principal` and advances `lastSeenAt` when it is more than a minute stale (one write per minute per device, not per request).

Guards in `modules/auth/guards.ts`, all `async` for the reason Phase 2's guards document:

- `requireAuth` — a user principal, else 401 with the rejection code.
- `requireEmailVerified` — `requireAuth`, then `emailVerified`, else **422 `EMAIL_NOT_VERIFIED`** (`BusinessRuleError`, as the Phase 2 spec reserved). This is the guard booking, enquiry and messaging endpoints will carry; nothing in this phase is gated by it except a test-only route that proves it.
- `requireActiveAccount` — `requireAuth`, then `status === 'active'`, else **422 `ACCOUNT_FROZEN`**. The freeze §Phase 3 describes ("no new bookings, no new listings") is enforced by later phases placing this guard; it exists now so the rule has a name.
- `principalOf(request)` narrows to `UserPrincipal` (the admin module keeps its own).

Plugin order in `buildApp`: logging and errors → admin session → **user auth** → rate limit → idempotency → modules. The rate limiter's `subjectKey` already keys `u:<principal.id>` for any principal.

## 3. Tokens and sessions

**Login** (`POST /v1/auth/login { email, password, deviceName? }`): argon2id verify against the stored hash, or against `DUMMY_PASSWORD_HASH` when the email is unknown so timing does not reveal existence. Wrong password, unknown email and an anonymised account all answer 401 `INVALID_CREDENTIALS` with one message. A `frozen` account signs in normally — the DTO carries `status: 'frozen'` and `deletionDeadlineAt`, and the app shows the frozen state. Success creates a `UserSession` and a `RefreshToken`, audits, and returns:

```json
{ "data": { "user": <UserDto>, "tokens": { "accessToken", "accessTokenExpiresAt", "refreshToken", "refreshTokenExpiresAt" } } }
```

**Refresh** (`POST /v1/auth/refresh { refreshToken }`, anonymous): one conditional statement — `UPDATE refresh_token SET rotated_at = now(), replaced_by_id = <new> WHERE token_hash = $1 AND rotated_at IS NULL AND expires_at > now() RETURNING …` — so two racing refreshes with the same token cannot both win. Winner: new `RefreshToken` row, new access token, `lastSeenAt` touched, same `sid`. No row matched: look the hash up; if it exists with `rotatedAt` more than 30 s ago → revoke the session (`refresh_reuse`, audited, actor `system`) and 401 `SESSION_EXPIRED`; within 30 s → 401 `REFRESH_TOKEN_ROTATED`; expired → revoke (`refresh_expired`) and 401 `SESSION_EXPIRED`; unknown → 401 `UNAUTHENTICATED`. A revoked or anonymised session never refreshes.

**Logout** (`POST /v1/auth/logout`, `requireAuth`): revokes the current session (`logout`). **Sessions** (`GET /v1/auth/sessions`): the caller's live sessions — `id, deviceName, createdAt, lastSeenAt, current` — never IPs or tokens; `DELETE /v1/auth/sessions/:id` revokes one of the caller's own (`revoked_by_user`; a foreign id is 404, never 403, so ids are not confirmable). Revoking one device leaves every other session live — the Done-when line the test pins.

**Password change** revokes every other session (`password_change`) and re-issues nothing: the current session continues. **Email change** (confirmed) revokes every other session (`email_change`) for the same reason — the credential changed under them.

**Config** (`.env.example`, all with comments): `AUTH_JWT_SECRET` (32 bytes base64, distinct from `ADMIN_TOTP_ENCRYPTION_KEY`), `AUTH_ACCESS_TOKEN_MINUTES=15`, `AUTH_REFRESH_TOKEN_DAYS=30`, `AUTH_OTP_EXPIRY_MINUTES=10`. Fixed constants, not config, because the plan pins them: the two send limits, the 5-attempt limit, the 30-day deletion backstop, the 30-second refresh grace, the password bounds.

## 4. Registration, phone, OTP

**Register** (`POST /v1/auth/register`, anonymous, `Idempotency-Key` required, operation `auth.register`):

```json
{ "role": "customer" | "provider", "fullName", "email", "phone": { "dialCode": "+960", "number": "7771234" }, "password", "businessName"?, "acceptTerms": true, "deviceName"? }
```

Order of checks, each a distinct field-level failure:

1. Zod: `fullName` 1–120 after trim; `email` trimmed, valid, ≤ 320; `dialCode` matches `^\+[1-9]\d{0,3}$`; `number` stripped of spaces, dashes and dots is 6–15 digits **and** dial code plus number is at most 15 digits (E.164's ceiling — the plan's 6–15 is the national part); `password` 8–512; `businessName` 1–120, required when `role = provider`, refused when `customer`; `acceptTerms` must be `true`.
2. Email in use (case-insensitive) → **409 `EMAIL_IN_USE`**, `details: [{ path: 'email', message: 'This email already has a RaajjePro account.' }]`. The client renders the field error with its Sign in / Reset password routes.
3. Phone in use by an account whose `ProviderProfile.verificationTier` is `bronze` or above → **409 `PHONE_IN_USE`**, `details: [{ path: 'phone', … }]`. Held only by accounts at `none`, or by no ProviderProfile at all → accepted silently.
4. Create `User` (`status: active`, `termsAcceptedAt: now`), and when `role = provider` a `ProviderProfile` with the business name — in one transaction, with `user.registered` audited (metadata: `role`). The unique index on `email` is the last line of defence against a concurrent duplicate; a `P2002` on it is mapped to the same `EMAIL_IN_USE`.
5. Open a session exactly as login does, send the verification OTP (below), and return **201** `{ user, tokens, verification: { status: 'sent' | 'suppressed' | 'failed', resendAvailableAt } }`. `suppressed` and `failed` are reported honestly so the screen can say the code is not coming rather than pretend it is.

Phone is stored as `phoneE164` = dial code + national digits. It is returned only in the account holder's own reads (`GET /v1/auth/me`, the data export) and in nobody else's — there is no other-user read of a user in this phase, and `userDto` is the single mapping every route uses, so the exclusion is structural.

**OTP send** (`POST /v1/auth/verify-email/send`, `requireAuth`; also called internally by register and by change-email). In one transaction that first locks the user row (`SELECT id FROM "user" WHERE id = $1 FOR UPDATE` — raw SQL because Prisma has no row lock, and the count-then-insert below is the race it guards):

1. Already verified (for `verify_email`) → 422 `EMAIL_ALREADY_VERIFIED`.
2. Count `EmailOtp` rows for `targetEmail` in the last 15 minutes; ≥ 3 → **429 `OTP_RATE_LIMITED`**, `details.retryAfterSeconds` = oldest-in-window `createdAt` + 15 min − now, `details.limit: 'address'`.
3. Count rows for `userId` in the last hour; ≥ 5 → the same code, `retryAfterSeconds` from that window, `details.limit: 'account'`. When both apply, the larger wait wins and `limit` names it.
4. Generate six digits (`crypto.randomInt`), insert the row with `codeHash = sha256(`${id}|${code}`)` and `expiresAt = now + AUTH_OTP_EXPIRY_MINUTES`, send through `EmailSender` on channel `otp` with `recipientUserId` set (this is the first caller with a user id — Phase 2's open item closes here), store the returned `emailMessageId` on the row.

The email: subject `Your RaajjePro verification code`, plain text carrying the code, its expiry, and a line that it should be ignored if not requested. **No links**, matching §Phase 3c's posture for every transactional mail. Response: `{ status, resendAvailableAt, expiresAt }`.

**OTP confirm** (`POST /v1/auth/verify-email/confirm { code }`, `requireAuth`): load the live codes for `(userId, purpose)` — unconsumed, not invalidated, unexpired. None → 422 `OTP_EXPIRED` ("request a fresh code"). Compare the hash against each; a match consumes that row, sets `emailVerifiedAt`, audits `user.email.verified`. No match → `attempts + 1` on every live row (`updateMany`); if any row now has 5 → invalidate all live rows and answer **422 `OTP_INVALIDATED`**; otherwise **422 `OTP_INCORRECT`** with `details.attemptsRemaining`. Route tier 10 per 5 minutes per principal sits above the 5-attempt rule so the fifth failure reaches the service and is answered by the invalidation, not the limiter.

**Social auth** (`POST /v1/auth/social/:provider { idToken, deviceName? }`, `provider ∈ apple | google | facebook | viber`): `SocialAuthProvider { name; verify(idToken): Promise<{ providerUserId, email?, fullName? }> }` behind a `SocialAuthRegistry`. All four are stubs that throw **422 `SOCIAL_AUTH_UNAVAILABLE`**; real implementations are post-v1 (§6). The route exists so the client contract is fixed; an unknown provider is 404.

## 5. Account settings

All under `/v1/users/me`, all `requireAuth`, all audited. A `frozen` account may use every one of them (nothing here creates a booking or listing).

| Method & path | Body | Effect |
|---|---|---|
| `POST /change-password` | `{ currentPassword, newPassword }` | verify current (401 `INVALID_CREDENTIALS` if wrong), hash new, set `passwordChangedAt`, revoke every *other* session (`password_change`) |
| `POST /change-email/request` | `{ newEmail, currentPassword }` | verify password; `newEmail` unused (409 `EMAIL_IN_USE`) and different from the current (422 `EMAIL_UNCHANGED`); send OTP purpose `change_email`, `targetEmail = newEmail`, under the same two limits (the per-address count runs against the new address) |
| `POST /change-email/confirm` | `{ code }` | verify as in §4 against `change_email`; on match re-check uniqueness (a `P2002` here → `EMAIL_IN_USE`), set `email = targetEmail`, `emailVerifiedAt = now`, revoke every other session (`email_change`), audit `user.email.changed` (metadata: none — neither address is logged) |
| `PATCH /phone` | `{ dialCode, number }` | same validation as registration; Bronze-uniqueness re-checked (409 `PHONE_IN_USE`); stored; never marked verified; audit `user.phone.changed` |
| `GET /data-export` | — | 200 with `Content-Disposition: attachment; filename="raajjepro-export-<date>.json"`. Body: `{ exportedAt, account: { id, fullName, email, emailVerifiedAt, phone: { dialCode, number }, status, createdAt, termsAcceptedAt }, providerProfile: { businessName, verificationTier } or null, sessions: [{ deviceName, createdAt, lastSeenAt }], …sections }` where `…sections` are whatever `ExportContributor`s later phases register (`{ key, collect(userId): Promise<unknown> }`) — Phase 11 adds reviews, 17 bookings, 18 messages. Own data, so the phone is present; nothing about any other user ever is |
| `POST /deletion-request` | — | if `active`: `status = frozen`, `deletionRequestedAt = now`, `deletionDeadlineAt = now + 30 days`, audit; **202** `{ status: 'frozen', deletionRequestedAt, deletionDeadlineAt }`. If already `frozen`: the same 202 with the original dates — a retry is not a second request. Never 4xx for open bookings: there is no such state |

`GET /v1/auth/me` returns `UserDto`: `id, fullName, email, emailVerified, phone: { dialCode, number }, status, deletionDeadlineAt, isProvider, createdAt`. No hash, no token, no session id.

## 6. Deletion pipeline and the job runner

**`src/jobs/runner.ts`.** `JobRunner` takes `{ prisma, clock, log }`; `register({ name, everyMs, run })`; `start()` schedules each job on `setInterval`; `stop()` clears them. Each tick opens a transaction, takes `pg_try_advisory_xact_lock(hashtext('job:' + name))` and skips the tick if another instance holds it; runs `run(tx, now)`; on success upserts `job_heartbeat` for `name` (the Phase 0 table, so `readHeartbeat`'s idea of "observably firing" extends to Node jobs without a second mechanism). Failures are logged with the job name and never stop the interval. `main.ts` starts it; tests call `runOnce(name, now)` with a controllable clock and never start the interval. The Phase 0 no-op job is untouched.

**Anonymisation job** (`anonymise-deleted-accounts`, every 5 minutes): select users where `status = frozen` and (`deletionDeadlineAt <= now` **or** `deletionBlocker.hasOpenBookings(userId)` is false), then for each, in its own transaction:

1. `User`: `fullName → 'Deleted user'`, `email → deleted-<id>@anonymised.raajjepro.invalid` (unique by construction, satisfies the unique index), `phoneE164 → null`, `passwordHash → hash of 32 random bytes` (nobody can ever sign in), `emailVerifiedAt → null`, `status → anonymised`, `anonymisedAt → now`.
2. `ProviderProfile.businessName → null` — the tier and status are retained (they are a decision record, not identity).
3. Every session revoked (`anonymised`); every live OTP invalidated; every refresh token for those sessions left as-is (their sessions are dead).
4. Every registered **anonymisation hook** runs: `AnonymisationHooks.register(name, (tx, userId, now) => Promise<void>)`. Phase 10a/23 registers the identity-document purge, Phase 10b the internal-notes deletion, Phase 11 reviews' attribution, Phase 18 message purge. This phase registers none and tests that a registered hook runs inside the same transaction and that its failure rolls the user back untouched.
5. Audit `user.anonymised`, actor `system`, reason `bookings_terminal` or `deletion_backstop`, metadata `{ hooksRun: n }`.

`DeletionBlocker` is an `AppDeps` field with a default that always answers `false`. Phase 17 supplies the real one. Its presence in the selection query is what "completes automatically when that booking terminates" will hang from; the test here injects a blocker that says `true` and asserts the user is untouched until the deadline, then anonymised at the deadline with the clock advanced.

## 7. Errors and rate tiers introduced

| Code | Status | Where |
|---|---|---|
| `INVALID_CREDENTIALS` (existing) | 401 | login, change-password, change-email/request |
| `ACCESS_TOKEN_EXPIRED`, `SESSION_EXPIRED` (existing), `UNAUTHENTICATED` (existing), `REFRESH_TOKEN_ROTATED` | 401 | auth plugin, refresh |
| `EMAIL_IN_USE`, `PHONE_IN_USE` | 409 | register, change-email, phone |
| `EMAIL_NOT_VERIFIED`, `ACCOUNT_FROZEN` | 422 | guards |
| `EMAIL_ALREADY_VERIFIED`, `EMAIL_UNCHANGED`, `OTP_EXPIRED`, `OTP_INCORRECT`, `OTP_INVALIDATED`, `SOCIAL_AUTH_UNAVAILABLE` | 422 | OTP and social routes |
| `OTP_RATE_LIMITED` | 429 | OTP send; `details.retryAfterSeconds`, `details.limit`; `Retry-After` header |

Route tiers (all above the plan's stricter-on-auth rule; the global tiers stay): login 10 / 15 min per IP; register 5 / hour per IP; refresh 30 / min per IP; social 10 / 15 min per IP; OTP send 10 / 15 min per IP (the domain limits above are the real rule; this stops a client hammering the endpoint into 429s from the domain); OTP confirm 10 / 5 min per principal; change-password and change-email/request 10 / 15 min per principal; deletion-request 5 / hour per principal.

Logging: `SENSITIVE_KEYS` gains `refreshToken`, `accessToken`, `newEmail`, `fullName`, `phoneE164`, `number` — and `req.headers.authorization` was already redacted.

## 8. Frontend

New dependencies (pinned in `pubspec.yaml`): `flutter_riverpod`, `http`, `flutter_secure_storage`, `device_info_plus`, `share_plus`, `sentry_flutter`. Nothing for OTP boxes or pin fields — the six-box entry is built from the design tokens so it stays inside the design system.

**`lib/core/api/`** — `ApiClient`: base URL from `--dart-define=API_BASE_URL` (default `http://localhost:3000`), attaches the bearer token, decodes the envelope into a value or an `ApiException(code, message, details)`. On `ACCESS_TOKEN_EXPIRED` it refreshes once through a single in-flight future (so ten parallel calls cause one refresh) and retries; on `SESSION_EXPIRED` or a failed refresh it clears tokens and moves the auth state to `sessionExpired`. Network failure is `ApiNetworkException`, which screens render as their offline/error state — never a raw message.

**`lib/core/auth/`** — `TokenStore` over `flutter_secure_storage`; `AuthController` (Riverpod `Notifier<AuthState>`: `unknown → guest | signedIn(user) | sessionExpired`), restoring from storage on boot and re-reading `me` in the background. `FormDraftStore` keeps in-progress form text in memory across the session-expired → sign-in → return path, which is the one promise the App States screen makes.

**`lib/core/crash/`** — `CrashReporter { init(); recordError(error, stack); setUser(id?) }` with `SentryCrashReporter` (active only when `--dart-define=SENTRY_DSN` is non-empty) and `NoopCrashReporter`. `main.dart` wraps `runApp` in `runZonedGuarded` and routes `FlutterError.onError` through it. User id only — never email or phone — is attached.

**`lib/features/auth/`** (screens match their prototypes; states listed are each screen's own definition of done):

- **Sign In** — gradient header, email, password with reveal, the single failure banner that keeps both values, `Forgot password?` (routes to a Phase 3b placeholder for now), the four third-party buttons each answering with an inline "isn't available yet" notice on tap (the backend stub), `Create Account`, `Continue as Guest`, and the guest line. States: default · failed · submitting (button's own loading) · offline (inline).
- **Register** — the Find/Offer Services toggle, full name, email, phone with dial-code prefix (`+960` default, the foreign-number hint when changed), Business / Trade Name with its disclaimer when Offer Services, password and confirm with reveal, terms and privacy acceptance linking to the Phase 23 placeholder pages, `Create Account` / `Create Provider Account`. States: default · field errors from `VALIDATION_FAILED` · `EMAIL_IN_USE` under the email field with Sign in and Reset password · `PHONE_IN_USE` under the phone field with its "if it's yours, sign in" copy · submitting · offline. On 201 it routes to Verify Email carrying `verification.status`, so a suppressed or failed send is shown, not hidden.
- **Verify Email** — the address in full with `Not your address? Change it` (routes to Change email), six boxes with auto-advance and backspace-retreat, `Verify Email` (own loading), the **resend countdown** (60 s locally after each send, then the button), the **rate-limit wait** driven by `retryAfterSeconds` (a separate timer, in `m:ss`), wrong-code with attempts remaining, invalidated with `Send a fresh code`, resent confirmation, success with `Continue`, and the footer with `I'll do this later`. States: entry · resent · wrong_code · code_invalidated · rate_limited · success · send_failed (the honest state for `suppressed`/`failed`).
- **Session expired** — the App States copy: `Signed out for your security`, the one promise, `Sign In Again`. After sign-in the draft store restores what was typed.

**`lib/features/account/`**:

- **Account Settings** — the header with name and email, rows `Change password` · `Change email` · `Change phone` · `Active sessions` · `Download my data`, and the red `Delete account` row. States: populated · loading (skeleton rows) · error (`EmptyState.error` "Couldn't load settings") · frozen (a banner with the deadline when `status == frozen`, and the delete row reading `Deletion in progress`).
- **Active sessions** — one row per device: name, "active now" or a relative last-used age, `This device` marker with `Sign out`, `Revoke` on the others with a confirming sheet and a toast naming only that device. States: populated (never empty — this device is always present) · loading · error · revoking (the row's own spinner).
- **Download my data** — the contents list and `Request my data`; on success the JSON goes to the share sheet. States: default · fetching · shared · error.
- **Delete account** — confirm (the four facts, `Type DELETE to confirm`, the destructive button enabled only on a match, `Keep my account`) → frozen (the three facts, the deadline, `Done`). No rejected state exists.
- **Change password** — current, new, confirm, requirements stated before submission; success toast; `INVALID_CREDENTIALS` under the current-password field.
- **Change email** — step 1 new address and current password; step 2 the Verify Email entry reused with purpose `change_email` and the new address shown. `EMAIL_IN_USE` under the field. On success the header updates.
- **Change phone** — dial code and number, shown afterwards exactly as entered, with no check mark and no "verified" anywhere. `PHONE_IN_USE` under the field.

Routing stays the plain named-route table `app.dart` already uses; the root widget picks Sign In, the placeholder Home or Session expired from `AuthController`. The placeholder Home gains a temporary `Account settings` action so the sub-screens are reachable until Phase 6 builds Profile; it is removed then. Guests reach the placeholder Home unchallenged — browsing is free and nothing in this phase gates them.

Tests (`flutter test`): every screen's every state renders (pumping two frames, never `pumpAndSettle` over a spinner); `AuthController` refresh-and-retry, single in-flight refresh, session-expired transition and draft restore against a fake `ApiClient`; the Register field-error mapping for `EMAIL_IN_USE` and `PHONE_IN_USE`; the Verify Email timers driven by a fake clock; a design-rule test that no auth or account screen contains the word "verified" next to a phone value or a check icon adjacent to one.

## 9. Documentation written in this phase

- `docs/decisions/12-phase-3-identity.md` — the decisions table above, what changed during the build, the prototype divergences (data-export delivery copy; `· Malé` on sessions), and a pointer to the ledger rows this phase added.
- `docs/deferred-verification.md` — the rows this phase adds, each with what closes it: under *closed at deployment*, the OTP mail reaching a real inbox with a readable code (closed by registering with an address you control), and a Flutter exception reaching Sentry (closed by a forced test crash against a real DSN); under *closed by a later phase*, anonymised review attribution (Phase 11), deletion completing when an open booking terminates (Phase 17), and the reset flow refusing an unverified email without revealing existence (Phase 3b). Nothing this phase can test today goes in the ledger.
- `backend/.env.example` — the four `AUTH_*` variables. `README.md` — running the app against the file transport and reading the OTP from `backend/.mail/`. `HANDOVER.md` — Phase 3 built, 3b next, saved preferences deferred, the two seams later phases fill.
- `frontend/lib/README.md` — the two new feature directories and `core/api`, `core/auth`, `core/crash`.

## 10. Verification against Done-when

| §Phase 3 Done-when | Test |
|---|---|
| Full register → verify → logout → login cycle works | route test: register (201, tokens, `verification.status: 'sent'`) → read the code from the JSON the file transport wrote → confirm (200, `me.emailVerified: true`) → logout (200) → `me` with the old access token → 401 `SESSION_EXPIRED` → login (200, new tokens) → `me` 200. Run once more against the dev server by hand, reading `backend/.mail/` |
| An unverified user browses freely but is rejected by `requireEmailVerified` | `GET /v1/auth/me` and a test-only unguarded route answer 200 for an unverified user; a test-only route behind `requireEmailVerified` answers 422 `EMAIL_NOT_VERIFIED`, then 200 after confirm |
| Duplicate email blocked naming the email, offering login or reset | second register with the same address (any case) → 409 `EMAIL_IN_USE`, `details[0].path === 'email'`; widget test: the field error renders with Sign in and Reset password |
| Duplicate phone blocked naming the phone | seed a user with a `ProviderProfile` at `bronze`; register with the same E.164 → 409 `PHONE_IN_USE`, `details[0].path === 'phone'`; the same number held at `none` or by a customer → 201. Formatting variants (`777 1234` vs `7771234`) collide |
| Both OTP rate limits verified independently | address limit: three sends → fourth 429 `OTP_RATE_LIMITED`, `limit: 'address'`, `retryAfterSeconds ≤ 900`; advance 15 min → 200. Account limit: five sends across two different target addresses (verify then change-email) → sixth 429, `limit: 'account'`, `retryAfterSeconds ≤ 3600`; advance 1 h → 200. Concurrency: ten simultaneous sends → exactly three 200s. Attempts: five wrong codes → `OTP_INVALIDATED`, the right code now → `OTP_EXPIRED`-class refusal, a fresh send works |
| A deleted account's reviews remain with anonymised attribution | **mechanism only**: a registered anonymisation hook runs in the anonymisation transaction with the user id; a hook that throws rolls the user back. End-to-end assertion lands in Phase 11 with the `Review` table |
| Export returns complete data | export after registering, verifying and opening a second session: every account field present, phone present, two sessions, a registered test contributor's section present under its key; no `passwordHash`, no token, no other user's data |
| Deletion request with an open booking is accepted and freezes rather than erroring | `DeletionBlocker` injected to answer `true` → `POST /deletion-request` 202, `status: frozen`; the job runs → user untouched; blocker flips to `false` → next run anonymises. **Verified end to end in Phase 17** when the real blocker exists |
| …and completes anyway at the 30-day backstop | blocker fixed at `true`; clock advanced 30 days + 1 s → the job anonymises; email, name and phone replaced; sessions revoked; login → `INVALID_CREDENTIALS`; audit `user.anonymised` reason `deletion_backstop` |
| An email confirmation link verifies and a recovery attempt without one is refused | the OTP is the confirmation (see decisions); the verify path above covers the first half. Second half: `assertRecoverableByEmail` throws `EMAIL_NOT_VERIFIED` for an unverified user and passes for a verified one — unit-tested here, and wired to a test-only route to show the 422 shape. The reset flow that calls it, and its silent non-send, is **verified end to end in Phase 3b** (ledger row) |

Plus the rules the plan states without a Done-when line: refresh rotation — the old token fails, the new one works, reuse after the grace window revokes the session and a fresh refresh with the *new* token also fails; reuse inside 30 s answers `REFRESH_TOKEN_ROTATED` without revoking; two concurrent refreshes → exactly one success; revoking one session leaves another live; password change revokes the others and not the current; change-email re-verifies via OTP to the new address and refuses an address in use at confirm time; phone change never sets any verified marker (there is none to set — asserted by schema, not by test); no response outside the holder's own `me` and export contains `phoneE164` (an authenticated read of `GET /v1/auth/sessions` and every error body is asserted phone-free); a `frozen` user may still sign in and read `me`; an anonymised user cannot; `user.registered` and `user.login.failed` audit rows carry no email in metadata; a captured pino log of a full register → login run contains no email, phone, password, code or token.

## Out of scope, deliberately

Forgot-password (Phase 3b — this phase leaves `passwordChangedAt`, session revocation and `emailVerifiedAt` for it to use). Push and device tokens (3c). The Profile screen and role switcher (6) — Account Settings is reached from a temporary action on the placeholder Home until then. Saved preferences (deferred, see decisions). Marketing/digest toggles (19). Admin recovery queue, suspension, the new-registrations kill switch, view-as-user (10b). Identity documents and the verification queue (10a/23) — this phase only creates the tier column they will write. Real social sign-in (§6 post-v1). Any Phase 5 ProviderProfile column beyond the four named. Terms and privacy text (23 — the links go to clearly-marked placeholders).
