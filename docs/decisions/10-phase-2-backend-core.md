# Phase 2 — backend core infrastructure, and where the build departed from the design

**Status: built 2026-09-06. Plan revision 5.19, §Phase 2, plus the §0.0 item 8 /
§4 Sequencing "Phase 0–2 window" SES prerequisite.**

Phase 2 turns `docs/superpowers/specs/2026-09-05-phase-2-backend-core-design.md`
into the server shape, admin identity, rate limiting, idempotency and email
infrastructure §Phase 2 asks for. `docs/decisions/09-phase-2-defaults.md`
recorded five decisions before the build started; this file records what
changed once code was actually written and reviewed against it, and what the
build leaves for Phase 3 and the account owner.

## The eight decisions

Decided in the design spec (§"What the plan pins, and what it leaves open") and
confirmed unchanged by the build. Not restated here — see the spec for the
full reasoning behind each.

| # | Decision | Choice |
|---|---|---|
| 1 | Rate-limit counters and idempotency records storage | PostgreSQL for both |
| 2 | Admin session transport | Opaque token in an `HttpOnly; Secure; SameSite=Strict` cookie, server-side session row |
| 3 | Session timings | Idle 15 min · absolute 12 h · re-auth valid 5 min |
| 4 | How the first admin exists | CLI (`npm run admin:create`), TOTP enrolled at first login |
| 5 | Idempotency key transport | `Idempotency-Key` request header |
| 6 | Global rate-limit tiers | 60/min anonymous per IP, 300/min authenticated per principal; admin login 10/15 min per IP |
| 7 | Development email transport | `FileEmailSender`, gitignored `backend/.mail/`, refused in production |
| 8 | SNS signature verification | `sns-validator` (changed from in-house — `docs/decisions/09-phase-2-defaults.md`) |

## What was built

| Plan item | Module | File(s) |
|---|---|---|
| Server shape, plugin order | `app.ts` | `backend/src/app.ts`, `backend/src/main.ts` |
| Typed fail-fast config | `config/env.ts` | `backend/src/config/env.ts`, `backend/.env.example` |
| Error hierarchy, envelope, error handling | `core/` | `backend/src/core/errors.ts`, `backend/src/core/envelope.ts`, `backend/src/core/error-handler.ts` |
| Correlation IDs, redacted logging | `core/logging.ts` | `backend/src/core/logging.ts` |
| `GET /v1/health` | `modules/health` | `backend/src/modules/health/routes.ts` |
| Rate limiting (Postgres store, per-route override) | `plugins/rate-limit.ts` | `backend/src/plugins/rate-limit.ts` |
| Idempotency (`Idempotency-Key`, replay, abandon-on-failure) | `plugins/idempotency.ts` | `backend/src/plugins/idempotency.ts` |
| Admin tables (user, session, recovery code, audit entry) | Prisma schema | `backend/prisma/schema.prisma`, `backend/prisma/migrations/` |
| Admin session resolution, CSRF, CORS | `plugins/admin-session.ts` | `backend/src/plugins/admin-session.ts` |
| Password hashing, TOTP crypto | `modules/admin-auth/crypto.ts` | `backend/src/modules/admin-auth/crypto.ts` |
| Login, sessions, guards | `modules/admin-auth/` | `backend/src/modules/admin-auth/{service,repository,routes,guards,schema}.ts` |
| MFA enrolment/verify, recovery codes, reauth | `modules/admin-auth/service.ts` | `backend/src/modules/admin-auth/service.ts` |
| Audit log service + queryable route | `modules/audit/` | `backend/src/modules/audit/{service,routes,types}.ts` |
| `admin:create` CLI | `cli/` | `backend/src/cli/admin-create.ts` |
| `EmailSender` interface, suppression-before-send | `modules/email/service.ts` | `backend/src/modules/email/{service,types}.ts` |
| SES and file transports | `modules/email/transports/` | `backend/src/modules/email/transports/{ses,file,index}.ts` |
| SNS signature verification | `modules/email/sns/validator.ts` | `backend/src/modules/email/sns/validator.ts` |
| SES event webhook, dedup, suppression on hard bounce/complaint | `modules/email/sns/routes.ts` | `backend/src/modules/email/sns/{routes,events}.ts` |
| Versioning policy | docs | `docs/api/versioning.md` |
| SES production-access runbook | docs | `docs/ops/ses-production-access.md` |
| CI boot smoke (`/v1/health`, job runner) | CI | `.github/workflows/ci.yml` |

## Where the build departed from the design

Each of these is a review finding from the build ledger
(`.superpowers/sdd/2026-09-06-phase-2-backend-core/progress.md`) that changed
the merged code — not a hypothetical risk, something the review actually
caught and a ruling actually fixed.

- **`loadConfig` short-circuited on the first Zod failure, before the
  production business-rule checks ran.** The design's config module promises
  to collect every issue and report them together; the first pass threw as
  soon as schema parsing failed, so a deployment with both a missing variable
  and a production-only violation (say, `EMAIL_TRANSPORT` not `ses` in
  production) learned about the schema issue on the first boot and the
  business-rule issue only on the second. Fixed: the business-rule checks now
  run against the raw env regardless of whether the schema itself parsed, so
  both kinds of problem land in one `ConfigError`. In the same review, the
  new dependencies were also found pinned with caret ranges rather than
  exact versions — a slip against the repo's own convention (Dependabot
  bumps them deliberately), not a design change — and were re-pinned exactly,
  with `backend/.npmrc`'s `save-exact=true` added so `npm install` cannot
  reintroduce a caret later.

- **Pino redaction matched exact key depth, not "any depth."** The design's
  redaction list named `email`, `phone`, `password`, etc. as redacted "at any
  depth," but the implementation's paths matched a fixed nesting (`*.field`),
  so a top-level `{ email }` on a log line was not redacted. Fixed by
  generating top-level and depth-1–3 paths from one shared key list, with a
  captured-log test asserting the leak is gone.

- **Rate-limit window TTL used two different clocks.** The counter's
  `Retry-After` was computed from the Node process clock while the window
  itself was tracked by Postgres's `now()`; under clock drift between the app
  host and the database, a client could be told to retry sooner or later than
  the window actually resets. Fixed by computing the TTL inside the same
  `RETURNING` clause that reads `now()`, so both come from one clock. The
  store's failure-to-count path was also found to fail open silently; a
  warning log was added so an operator can see it happening.

- **Idempotency had an abandoned-record takeover race.** A key whose prior
  attempt ended in `abandoned` status (5xx or 429) was reclaimed with a
  read-then-write: read the row, see `abandoned`, then write `in_progress`.
  Twenty concurrent retries against the same key ran the handler ten times
  instead of once. Fixed with a single conditional `UPDATE … WHERE
  status='abandoned' RETURNING`, plus a concurrency test asserting the handler
  runs exactly once under simultaneous retries.

- **Audit-log pagination's tie-break was untested.** Cursor pagination orders
  by `(created_at, id)` to break ties when two entries share a timestamp, but
  no test exercised that path — a regression there would have gone unnoticed
  until two audit rows actually landed in the same instant. A same-`createdAt`
  pagination test was added.

- **Session auto-expiry (idle timeout) wrote no audit row.** A session that
  expired for exceeding `ADMIN_SESSION_IDLE_MINUTES` was revoked in the
  database but left no trace in the audit log, even though the plan lists
  `idle_timeout` as a system-actor reason — implying it should be audited like
  any other revocation. Fixed: the auto-expiry path now writes
  `admin.session.expired` with actor `system` and reason `idle_timeout`,
  inside the same transaction as the revocation.

- **The admin-route CSRF/session hook keyed on the raw request URL.** Matching
  `request.url.startsWith('/v1/admin')` is foolable by an encoded slash or a
  path that merely starts with that string but resolves to a route outside
  it. Fixed to match on `request.routeOptions.url` — the already-resolved
  route pattern — which cannot be fooled the same way and is `undefined` for
  an unmatched route (the 404 handler answers those, so there is nothing to
  guard).

- **`/mfa/enrol/confirm` and `/reauth` had no stricter rate tier or lockout.**
  The design's Done-when list named the 10/15-min login tier and the 5/5-min
  `mfa/verify` tier with its five-failure session revocation, but said nothing
  about the two other code-guessing surfaces on the same login flow. Fixed:
  `mfa/enrol/confirm` now carries the same 5-failure revocation as
  `mfa/verify` under a 6/5-min tier (one above the failure limit, so the
  failing attempt that trips revocation still gets a response); `reauth`
  carries its own 10/15-min tier per principal.

- **`EmailService.send()` could mark a message `failed` for the wrong
  reason.** A single try/catch wrapped both the transport call and the
  `email_message` log write; if the vendor accepted the message but the
  subsequent database write threw, the message was logged as `failed` even
  though it had actually been sent — and the `failed`-status write itself was
  unguarded, so a write failure there could throw uncaught. Fixed by
  separating the transport call from the log writes: a log-write failure
  after a successful send is logged and the call still returns `sent`, and
  `send()` never rejects outward regardless of which write failed.

- **Two webhook-handling races surfaced under concurrent SNS delivery.** (1)
  The terminal-status regression guard — "status never moves backwards from
  `bounced`/`complained`/`rejected`/`delivered`" — read the current status
  outside the update transaction, so a late out-of-order `Send` event
  arriving concurrently with a `Delivery` event could still overwrite it. (2)
  Suppression inserts did a `findFirst` then `create`, which raced under
  concurrent bounce/complaint notifications for the same address and hit the
  partial unique index, rolling the whole event back and returning 500. Both
  fixed with single conditional statements — a conditional `UPDATE` for the
  status guard, `INSERT … ON CONFLICT (address) WHERE lifted_at IS NULL DO
  NOTHING` for suppression — plus concurrency tests for each.

## Deferred minors

Recorded in the ledger as accepted, not fixed — each judged too small to hold
up the phase:

- `genReqId` lowercases an honoured client-supplied `X-Request-Id` even when
  it was already a valid UUID; harmless, but worth a comment noting it.
- No test pins that an unmatched URL under `/v1/admin` returns 404 (route not
  found) rather than 403 (CSRF/session rejection) — the admin-session hook's
  early return on an unmatched route is correct today but unguarded by a test.
- `child()`'s rate-limit-scope fallback when `routeInfo` is an empty object
  (the decorator form of registration, unused today).
- A redundant `Retry-After` header set at the plugin level alongside the
  route-level one.
- A key longer than 128 characters shares the same `IDEMPOTENCY_KEY_REQUIRED`
  code as a missing key, rather than its own code.
- The idempotency middleware's `existing === null` branch is effectively dead
  code given the insert-then-read flow.
- No compound `(createdAt, id)` database index backs the audit log's
  tie-break pagination — fine at v1 scale, worth revisiting if the table
  grows large.
- An extra audit-log insert on the wrong-password login path creates a tiny
  timing asymmetry against the unknown-email path; negligible next to
  argon2's own cost.
- `admin:create`'s duplicate-email check is check-then-act rather than a
  single atomic statement — acceptable because it is a CLI run by one
  operator, not a concurrent HTTP path.
- `listActiveSessions` doesn't re-evaluate idle expiry proactively; a session
  past its idle window still lists until it is next presented to the server.
- `beginEnrolment` writes the pending TOTP secret without its own audit row
  (the state is pending, not yet a completed action; `admin.mfa.enrolled`
  covers the completed enrolment).
- The `.mail/` directory resolution in the file email transport is
  process-cwd-relative, per the controller's explicit instruction.
- The email webhook's test harness relies on a nested-Proxy Prisma wrapper
  whose closure-bound assumption about Prisma's method binding is a bit
  fragile; noted, not replaced.
- The raw SQL `INSERT` for `email_event` duplicates six columns across its
  two branches to avoid a `null::uuid` cast; a comment marks it rather than a
  rewrite.

## Unverified

Nothing in the SES/SNS live path has been exercised against a real AWS
account — see `docs/ops/ses-production-access.md` §9 for the specifics: a
real SES send, a real SNS delivery to the webhook, and the subscription
handshake itself. Everything else in this phase — including all of the
signature verification, event handling and suppression logic — is unit- and
integration-tested against synthetic payloads and a test-generated RSA
keypair.

The interactive `admin:create` password prompt (reads from the terminal
without echo) has not been run manually — this build environment has no TTY.
`test/audit-routes.test.ts` covers the audit-log query behavior the CLI's
output feeds into; the prompt itself needs a terminal to exercise.

## What Phase 3 must confirm

- **The `anon:<ip>` idempotency subject for registration.** The plan's
  idempotency key is `(userId, operation, clientKey)`; there is no user yet at
  registration. This spec's `anon:<ip>` fallback is a proposal for that gap,
  not a plan-mandated answer — Phase 3 either confirms it or replaces it.
- **`recipientUserId` on `OutboundEmail`.** The field exists on the interface
  and the `email_message` table now, nullable, unfilled by anything in Phase
  2. Phase 3 is the first caller with an actual user id to put there.
- **`requireEmailVerified` as a `BusinessRuleError`.** Root `CLAUDE.md`
  requires email verification, stricter than plain auth, enforced
  server-side on every relevant endpoint. Phase 2 defines the `BusinessRuleError`
  class (422) that this is expected to use, but no `requireEmailVerified` guard
  exists yet — Phase 3 is where it is built and where its error code is fixed.

## Next step for the owner

Request SES production access, per `docs/ops/ses-production-access.md`. The
bounce/complaint handling and suppression list that access request depends on
are built as of this phase; Phase 3 (OTP, registration, login) is untestable
against a sandboxed SES account, so this is the blocking step before Phase 3
starts.
