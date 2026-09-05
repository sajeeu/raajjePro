# Phase 2 — Backend Core Infrastructure: design

**Status: approved 2026-09-05, before implementation. Plan revision 5.19, §Phase 2, plus the §0.0 item 8 / §4 Sequencing "Phase 0–2 window" SES prerequisite.**

This document does not restate §Phase 2. It records the decisions the plan leaves to the implementer, the concrete contract those decisions produce, and how each Done-when item is verified. Where it and the plan disagree, the plan wins and the disagreement is a defect here.

## What the plan pins, and what it leaves open

Pinned by §Phase 2 and §2: Fastify under `/v1`; the seven error classes; correlation IDs and no PII in logs; a typed, fail-fast config; a standard envelope; Prisma with UUID / soft-delete / integer-laari conventions; `GET /v1/health`; global rate-limit tiers (unauthenticated per IP, authenticated per user) with per-endpoint overrides; idempotency keyed on `(userId, operation, clientKey)` returning the original result; a real admin identity model with one `admin` role, mandatory TOTP with recovery codes issued once, session list with force-logout, a short idle timeout, re-authentication before viewing an identity document; an audit log queryable by date / admin / action; the additive-only `/v1` deprecation policy written down. From §0.0 item 8 and §4: SES bounce/complaint handling — SNS event destination, stored per-message result, suppression list honoured before send — built here, then production access requested before Phase 3.

Left open, and decided here (product owner, 2026-09-05):

| Decision | Choice | Alternatives declined |
|---|---|---|
| Where rate-limit counters and idempotency records live | **PostgreSQL for both.** No new infrastructure; correct across restarts and instances. | In-memory counters (per-process, reset on restart); Redis (a service the plan has not asked for). |
| Admin session transport | **Opaque token in an `HttpOnly; Secure; SameSite=Strict` cookie, backed by a server-side session row.** JS never holds the credential — the point of Phase 10a's CSP posture. | Bearer token held in page memory (reachable by the XSS payloads 10a is designed against); JWT (force-logout needs a denylist, so the session row returns anyway). |
| Session timings | **Idle 15 min · absolute 12 h · re-auth valid 5 min.** All three are config values. | 30/24h/10; 10/8h/2. |
| How the first admin exists | **CLI on the server: `npm run admin:create -- --email …`**, password prompted, TOTP enrolled at first login. No in-panel "add admin" in v1. | Env-var bootstrap at boot; a network-reachable bootstrap endpoint. |
| Idempotency key transport | **`Idempotency-Key` request header.** Works for every content type and stays out of the Zod body schemas. README's "fixed in Phase 2" note resolves to this. | A `clientKey` body field. |
| Global tier numbers | **60/min anonymous per IP, 300/min authenticated per principal**; admin login 10 per 15 min per IP. Config values. | — |
| Development email transport | **`FileEmailSender`** writing each message as JSON to gitignored `backend/.mail/`, so an OTP can be read locally without AWS. Production config refuses anything but `ses`. | Console logging (PII in logs); refusing to boot without AWS. |
| SNS signature verification | **In-house with Node `crypto`** (~60 lines, unit-testable with a generated keypair). | The unmaintained `sns-validator` package. |

## 1. Server shape

`src/app.ts` exports `buildApp(config, deps): FastifyInstance`. It registers cross-cutting plugins in a fixed order — request id and logging, error handler, admin-session resolution (sets `request.principal`), rate limiting, idempotency — and then each module's routes under `/v1`. `src/main.ts` loads config, creates the Prisma client, calls `buildApp`, listens. Tests call `buildApp` and use `app.inject()`: no port, no network, real Prisma.

```
backend/src/
  main.ts                 boot
  app.ts                  buildApp()
  config/env.ts           Zod-typed config, fail-fast
  core/errors.ts          AppError hierarchy
  core/envelope.ts        ok() / fail()
  core/error-handler.ts   setErrorHandler + setNotFoundHandler
  core/logging.ts         pino options, redaction, request-id
  plugins/rate-limit.ts   @fastify/rate-limit + Postgres store
  plugins/idempotency.ts  preHandler/onSend pair
  plugins/admin-session.ts  cookie → session row → request.principal
  modules/health/
  modules/admin-auth/     routes · service · repository · schema · guards
  modules/audit/          service · routes
  modules/email/          EmailSender · EmailService · transports · suppression · sns
  cli/admin-create.ts
  db/client.ts, jobs/     unchanged from Phase 0
```

Modules follow `backend/CLAUDE.md`: routes, service, repository, Zod schema, types, tests; business logic in the service.

## 2. Envelope, errors, logging, config

**Envelope.** Success: `{ "data": <payload> }`, with `"meta": { "nextCursor": string | null }` on paginated lists. Error: `{ "error": { "code": string, "message": string, "details"?: unknown }, "requestId": string }`. Every response carries `X-Request-Id`.

**Errors.** One class per §Phase 2 category, each with a fixed HTTP status and a stable `code`:

| Class | Status | Code |
|---|---|---|
| `ValidationError` | 400 | `VALIDATION_FAILED` — `details` is `[{ path, message }]` from Zod, never the raw issue object |
| `AuthenticationError` | 401 | `UNAUTHENTICATED`, `SESSION_EXPIRED`, `INVALID_CREDENTIALS`, `MFA_REQUIRED` |
| `AuthorizationError` | 403 | `FORBIDDEN`, `MFA_ENROLMENT_REQUIRED`, `REAUTHENTICATION_REQUIRED`, `CSRF_HEADER_MISSING` |
| `BusinessRuleError` | 422 | supplied by the caller (Phase 3's `EMAIL_NOT_VERIFIED` is `new BusinessRuleError('EMAIL_NOT_VERIFIED', …)`); Phase 2 uses `IDEMPOTENCY_KEY_REUSED`, `PASSWORD_TOO_SHORT`, `MFA_ALREADY_ENROLLED`, `INVALID_MFA_CODE` |
| `ConflictError` | 409 | `CONFLICT`, `IDEMPOTENT_REQUEST_IN_PROGRESS` |
| `NotFoundError` | 404 | `NOT_FOUND` |
| `InfrastructureError` | 503 | `INFRASTRUCTURE_UNAVAILABLE` |
| `RateLimitedError` | 429 | `RATE_LIMITED` — `details.retryAfterSeconds`; `Retry-After` header |
| anything else | 500 | `INTERNAL_ERROR` — message replaced by a fixed string; the real error is logged with the request id |

Fastify's own 404, body-parse failures (400 `MALFORMED_BODY`) and `FST_ERR_VALIDATION` are routed through the same handler, so a malformed request of any kind gets the envelope. Error codes are stable identifiers; renaming one is a breaking change (`backend/CLAUDE.md`).

**Logging.** Fastify's pino. `X-Request-Id` is honoured when it is a UUID and generated otherwise; it is `reqId` on every log line and `requestId` in every error body. Redaction paths: `req.headers.authorization`, `req.headers.cookie`, `res.headers["set-cookie"]`, and every key named `password`, `email`, `phone`, `code`, `token`, `secret`, `recoveryCodes` at any depth. Request completion lines carry method, path without query string, status, duration, client IP. Bodies are never logged. `LOG_LEVEL` defaults to `info`; `debug` still redacts.

**Config.** `loadConfig(env): Config` parses one Zod schema, collects every issue, and throws a single error naming all missing or malformed variables. `main.ts` prints that and exits 1 before touching the database. Production-only refinements: `EMAIL_TRANSPORT` must be `ses`; `ADMIN_ORIGIN` must be `https:`; cookies are always `Secure` in production. Variables, all added to `.env.example` with comments:

```
PORT=3000  HOST=0.0.0.0  LOG_LEVEL=info  TRUST_PROXY=false
ADMIN_ORIGIN=http://localhost:5173
ADMIN_SESSION_IDLE_MINUTES=15  ADMIN_SESSION_ABSOLUTE_HOURS=12  ADMIN_REAUTH_MINUTES=5
ADMIN_TOTP_ENCRYPTION_KEY=<32 bytes, base64>     # TOTP seeds encrypted at rest (AES-256-GCM)
RATE_LIMIT_ANON_PER_MINUTE=60  RATE_LIMIT_AUTH_PER_MINUTE=300
EMAIL_TRANSPORT=file|ses  EMAIL_FROM_ADDRESS=
AWS_REGION=  SES_CONFIGURATION_SET_OTP=  SES_CONFIGURATION_SET_NOTIFICATION=  SES_CONFIGURATION_SET_MARKETING=
SES_EVENTS_TOPIC_ARN=
```

AWS credentials come from the SDK default chain (instance role, or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` in the host environment); they are not part of our schema. `requireEnv` from Phase 0 is removed once its two call sites (`main.ts`, `jobs/status.ts`) use `loadConfig`.

## 3. Rate limiting and idempotency

**Rate limiting.** `@fastify/rate-limit` with a custom store over `rate_limit_counter(key text PK, count int, window_started_at timestamptz)`, an UNLOGGED table. One atomic statement per counted request:

```sql
INSERT INTO rate_limit_counter (key, count, window_started_at) VALUES ($1, 1, now())
ON CONFLICT (key) DO UPDATE SET
  count = CASE WHEN rate_limit_counter.window_started_at + $2::interval <= now() THEN 1 ELSE rate_limit_counter.count + 1 END,
  window_started_at = CASE WHEN rate_limit_counter.window_started_at + $2::interval <= now() THEN now() ELSE rate_limit_counter.window_started_at END
RETURNING count, window_started_at;
```

Rows are reused across windows and never deleted — the soft-delete rule holds, no sweep job is needed, and the table is bounded by distinct subjects × routes. Key: `<routeId>:u:<principalId>` when `request.principal` is set, else `<routeId>:ip:<address>`; `max` is `RATE_LIMIT_AUTH_PER_MINUTE` or `RATE_LIMIT_ANON_PER_MINUTE` accordingly. Per-endpoint override is Fastify's route `config.rateLimit = { max, timeWindow }`; Phase 2 sets `POST /v1/admin/auth/login` to 10 per 15 min per IP and `POST /v1/admin/auth/mfa/verify` to 5 per 5 min per session. The 429 body is the envelope (`RATE_LIMITED`, `details.retryAfterSeconds`) and `Retry-After` is set. `TRUST_PROXY` controls whether `X-Forwarded-For` is believed; it is `false` unless the deployment sits behind a known proxy.

Session resolution runs before rate limiting (plugin order), so authenticated requests are keyed by principal.

**Idempotency.** Routes opt in with `config.idempotency = { operation: '<domain>.<verb>' }`. The client sends `Idempotency-Key: <1–128 chars>`. Table `idempotency_record(id, subject, operation, client_key, request_hash, status in_progress|completed|abandoned, response_status, response_headers jsonb, response_body jsonb, created_at, completed_at; UNIQUE (subject, operation, client_key))`.

preHandler:
1. No header → 400 `IDEMPOTENCY_KEY_REQUIRED`.
2. `subject` = `request.principal.id`, else `anon:<ip>` (see note).
3. `request_hash` = sha256 of `method + path + canonical JSON body`.
4. `INSERT … ON CONFLICT DO NOTHING RETURNING id`. Inserted → continue to the handler; `request.idempotency = { id }`.
5. Not inserted → read the existing row. `in_progress` → 409 `IDEMPOTENT_REQUEST_IN_PROGRESS`. `completed` with matching hash → reply with the stored status, `Content-Type`, body and `Idempotent-Replayed: true`; the handler does not run. `completed` with a different hash → 422 `IDEMPOTENCY_KEY_REUSED`.

onSend (only when `request.idempotency` is set): store status, content-type and body, mark `completed`. A handler that throws leaves the row `in_progress` only until the error handler runs; the error handler marks it `completed` with the error envelope so the client's retry replays the same failure rather than hanging on 409 — except for 5xx and `RateLimitedError`, where the row is deleted-by-status (`status = 'abandoned'`) so a retry may succeed. Records are never deleted. Stored bodies may contain the caller's own data; that is the database, not a log, and the redaction rule is about logs.

*Note for Phase 3:* the plan's key is `(userId, operation, clientKey)`. Registration is a creation POST with no user yet; the `anon:<ip>` fallback is this spec's proposal for it and Phase 3 confirms or replaces it.

## 4. Admin identity

**Tables** (all UUID ids, `created_at`/`updated_at`, snake_case via `@@map`):

- `admin_user`: `email` (unique, stored lower-cased), `password_hash` (argon2id), `role` (`'admin'`, the only value in v1), `status` (`active` | `disabled` — the soft-delete field), `totp_secret_encrypted` (AES-256-GCM under `ADMIN_TOTP_ENCRYPTION_KEY`; nullable until enrolment starts), `totp_enrolled_at` (nullable; null = enrolment pending), `password_changed_at`.
- `admin_session`: `admin_id`, `token_hash` (sha256 of the 32-byte random cookie token; the token itself is never stored), `created_at`, `last_seen_at`, `expires_at` (absolute), `mfa_verified_at` (nullable), `reauthenticated_at` (nullable), `ip_address`, `user_agent`, `revoked_at`, `revoked_reason` (`logout` | `force_logout` | `idle_timeout` | `absolute_expiry` | `mfa_failures` | `password_change`).
- `admin_recovery_code`: `admin_id`, `code_hash` (sha256 — codes are high-entropy, no slow hash needed), `used_at`, `revoked_at`. Ten per issue; regeneration revokes the unused ones.
- `audit_log_entry`: append-only. `actor_type` (`admin` | `system`), `actor_id` (nullable for system), `action` (dotted string), `target_type`, `target_id`, `reason` (text, **required**), `metadata` (jsonb; IDs and enums only, never email/phone/document content), `request_id`, `ip_address`, `created_at`. Indexes on `(created_at)`, `(actor_id, created_at)`, `(action, created_at)`. No update path exists in code.

**Session lifecycle.** `POST /login` verifies the password with argon2id — against a fixed dummy hash when the email is unknown, so timing does not reveal existence — and on success creates a session with `mfa_verified_at = null`, sets the cookie (`Path=/v1/admin`), and returns `{ state: 'mfa_required' | 'mfa_enrolment_required' }` with the admin's id and email. Nothing else is reachable in either state: `requireAdmin` rejects an unenrolled admin with 403 `MFA_ENROLMENT_REQUIRED` and an enrolled-but-unverified session with 401 `MFA_REQUIRED`. Idle: `last_seen_at + ADMIN_SESSION_IDLE_MINUTES < now` → the session is revoked (`idle_timeout`) and the request gets 401 `SESSION_EXPIRED`; each authenticated request advances `last_seen_at`. Absolute: `expires_at` is set at creation and never moves. `requireRecentReauth` demands `reauthenticated_at` within `ADMIN_REAUTH_MINUTES`, else 403 `REAUTHENTICATION_REQUIRED`; Phase 10a places it in front of identity-document access.

**Endpoints**, all under `/v1/admin/auth` unless noted; guard named on each:

| Method & path | Guard | Effect |
|---|---|---|
| `POST /login` | none (rate-limited 10/15 min/IP) | as above |
| `POST /mfa/enrol` | password-verified session, not yet enrolled | generates a secret, stores it encrypted, returns `{ otpauthUri, secret }` |
| `POST /mfa/enrol/confirm` `{ code }` | same | verifies, sets `totp_enrolled_at`, `mfa_verified_at`; returns `{ recoveryCodes: string[10] }` — the only time they are shown |
| `POST /mfa/verify` `{ code }` | enrolled, `mfa_verified_at` null | accepts a TOTP (±1 step) or an unused recovery code (marks it used); five consecutive failures revoke the session (`mfa_failures`) |
| `POST /reauth` `{ password, code }` | `requireAdmin` | sets `reauthenticated_at` |
| `POST /mfa/recovery-codes/regenerate` | `requireAdmin` + `requireRecentReauth` | revokes unused codes, issues ten new ones |
| `POST /logout` | `requireAdmin` | revokes current session (`logout`), clears cookie |
| `GET /sessions` | `requireAdmin` | own active sessions: id, createdAt, lastSeenAt, ipAddress, userAgent, `current` |
| `DELETE /sessions/:id` `{ reason }` | `requireAdmin` | revokes one of own sessions (`force_logout`) |
| `GET /me` | `requireAdmin` | id, email, `totpEnrolled`, `reauthenticatedAt` |
| `GET /v1/admin/audit-log` | `requireAdmin` | filters `from`, `to`, `actorId`, `action`; cursor pagination `(created_at, id)`, `limit` ≤ 100 |

Sessions are listed and revoked for the calling admin only. With a single reviewer this is the whole use case; cross-admin revocation is a Phase 10b question if a second admin ever exists.

**CSRF and CORS.** Every mutating request under `/v1/admin` must carry `X-Requested-With: RaajjePro-Admin` (a custom header forces a CORS preflight, which a cross-origin form cannot pass); missing → 403 `CSRF_HEADER_MISSING`. `@fastify/cors` allows only `ADMIN_ORIGIN`, with credentials. `SameSite=Strict` is the second layer.

**Passwords.** Minimum 12 characters, maximum 512, no composition rules (NIST 800-63B). argon2id via `@node-rs/argon2` (prebuilt binaries) at its defaults.

**Audit calls.** `audit.record(tx, entry)` runs inside the same Prisma transaction as the action. Phase 2 actions: `admin.created` (CLI, actor `system`), `admin.login.succeeded`, `admin.login.failed` (target = admin id; an unknown email produces a log line carrying only the request id and IP — never the address — and no audit row), `admin.mfa.enrolled`, `admin.mfa.verified`, `admin.mfa.recovery_code_used`, `admin.mfa.recovery_codes_regenerated`, `admin.reauthenticated`, `admin.logout`, `admin.session.revoked`. For system-initiated events the reason is the fixed string `user_initiated` or `idle_timeout`; for `DELETE /sessions/:id` the reason is the request body's, required.

**CLI.** `npm run admin:create -- --email <addr>` reads the password from the terminal without echo, enforces the minimum length, refuses an existing email, inserts the admin and an `admin.created` audit row, prints the id. It never prints or accepts a TOTP secret.

## 5. Email

**Interface.** Every module sends through this and nothing else:

```ts
interface OutboundEmail { channel: 'otp' | 'notification' | 'marketing'; to: string; subject: string; text: string; html?: string; recipientUserId?: string }
interface SendOutcome { messageId: string; status: 'sent' | 'suppressed' | 'failed' }
interface EmailSender { send(email: OutboundEmail): Promise<SendOutcome> }
```

`EmailService implements EmailSender`. Order of operations, which is the "honoured before send" rule: normalise the address (trim, lower-case) → look up an active `email_suppression` row → **if found, write `email_message` with status `suppressed` and return; the transport is never called** → otherwise write the row as `queued`, call the transport with the channel's configuration set, record `provider_message_id` and `sent`, or `failed` with the error class name (not the message — it may echo the address).

**Transports** implement `EmailTransport { deliver(email, configurationSet): Promise<{ providerMessageId }> }`: `SesEmailTransport` (SESv2 `SendEmail`, `ConfigurationSetName` from the channel) and `FileEmailTransport` (one JSON file per message in `backend/.mail/`, gitignored; development and test only — the config module refuses it in production).

**Tables.**
- `email_message`: `channel`, `to_address`, `recipient_user_id` (nullable — Phase 3 fills it), `subject`, `status` (`queued` | `sent` | `failed` | `suppressed` | `delivered` | `bounced` | `complained` | `rejected` | `delivery_delayed`), `configuration_set`, `provider_message_id` (unique, nullable), `failure_reason`, `created_at`, `sent_at`, `last_event_at`. This is the per-message log Phase 10b reads to answer "did this user receive it?" — one lookup by `recipient_user_id` or `to_address`.
- `email_event`: `sns_message_id` (unique — SNS retries), `message_id` (nullable FK; an event for a message we did not send is stored and flagged), `provider_message_id`, `event_type`, `occurred_at`, `payload` (jsonb, the SES event as received), `received_at`.
- `email_suppression`: `address` (normalised), `reason` (`hard_bounce` | `complaint` | `manual`), `source_event_id` (nullable), `created_at`, `lifted_at`, `lifted_by_admin_id`, `lift_reason`. Active = `lifted_at IS NULL`; a partial unique index on `address WHERE lifted_at IS NULL`. Lifting is Phase 10b's endpoint; the column exists now so nothing is ever deleted.

**Webhook.** `POST /v1/webhooks/ses-events`, raw JSON body, no session (the SNS signature is the authentication), anonymous rate tier raised to 600/min for this route.

1. Parse the SNS envelope. Verify the signature: `SigningCertURL` must be `https:` with host matching `^sns\.[a-z0-9-]+\.amazonaws\.com$`; the certificate is fetched once and cached by URL; the canonical string is built per the SNS specification for `Notification` and `SubscriptionConfirmation`/`UnsubscribeConfirmation`; `SignatureVersion` 1 → SHA1withRSA, 2 → SHA256withRSA. Failure → 400 `INVALID_SNS_SIGNATURE`, logged with the request id, no further processing.
2. `TopicArn` must equal `SES_EVENTS_TOPIC_ARN` → otherwise 403 `UNEXPECTED_SNS_TOPIC`.
3. `SubscriptionConfirmation` → GET `SubscribeURL` (same host rule) and return 200. `UnsubscribeConfirmation` → log, 200.
4. `Notification` → parse `Message` as an SES event. Insert `email_event` (dedup on `sns_message_id`; a duplicate returns 200 without re-applying). Then:
   - `Send` → message `sent` (no-op if already later); `Delivery` → `delivered`; `Reject` → `rejected`; `DeliveryDelay` → `delivery_delayed`; `Bounce` → `bounced`; `Complaint` → `complained`; `RenderingFailure` → `failed`.
   - `Bounce` with `bounceType = "Permanent"` → one `email_suppression(reason = hard_bounce)` per `bouncedRecipients[].emailAddress`, unless one is already active. `Transient`/`Undetermined` → status only.
   - `Complaint` → `email_suppression(reason = complaint)` per `complainedRecipients[].emailAddress`.
   - Status never moves backwards from a terminal state (`bounced`, `complained`, `rejected`, `delivered`) on an out-of-order `Send`.
5. Always 200 once stored, so SNS stops retrying; processing failures after storage are logged, not surfaced.

**Unverifiable here.** A real SES send, a real SNS delivery, and the subscription handshake need an AWS account with a verified domain, which is outstanding on the owner's side. Everything else is unit- or integration-tested: suppression before send with a fake transport, signature pass/fail/wrong host/wrong topic with a test-generated RSA keypair, every event type's effect on `email_message` and `email_suppression`, and retry dedup.

## 6. Health, documentation, CI

`GET /v1/health`: 200 `{ data: { status: 'ok', database: 'reachable', jobRunner: 'firing' | 'not-firing', lastHeartbeatAt } }`. If the database query fails → 503 `INFRASTRUCTURE_UNAVAILABLE` (§5 measures availability against this route; a dead database must read as down). `jobRunner: 'not-firing'` is reported, not treated as down. Anonymous tier applies.

Written in this phase:
- `docs/api/versioning.md` — the additive-only rule, what counts as breaking (removing/renaming/retyping a field or error code, tightening validation, changing a default), how a field is deprecated (documented, still served, `Deprecation` header on the route, removal only in a `/v2` that ships alongside `/v1` for as long as installed clients call it). §2 asks for this before the first breaking change is needed.
- `docs/ops/ses-production-access.md` — the owner's runbook: domain identity and DKIM/SPF/DMARC; three configuration sets and their names; one SNS topic; an event destination on each set publishing Send/Delivery/Bounce/Complaint/Reject/DeliveryDelay/RenderingFailure to it; an HTTPS subscription to `https://<api>/v1/webhooks/ses-events`; the environment variables; the attestation text for the production-access request, stating what this handling does.
- `docs/decisions/09-phase-2-backend-core.md` — decisions, written after the build in the style of `08-…`.
- `README.md` (idempotency header, running the server, `admin:create`), `HANDOVER.md` (Phase 2 built; SES request now unblocked), `backend/.env.example`.
- CI: after `db:deploy`, start the server in the background, poll `/v1/health` for 200, stop it. Replaces the Phase 0 "boot and exit" step; the heartbeat check stays.

## 7. Migration

One Prisma migration, `phase2_core_infrastructure`, adding the eight tables above. The generated SQL is edited only to make `rate_limit_counter` UNLOGGED and to add the partial unique index on `email_suppression`; both are noted in the migration file. `JobHeartbeat` is untouched. Prisma models carry the same header comment convention as Phase 0's schema.

## 8. Verification against Done-when

| §Phase 2 Done-when | Test |
|---|---|
| `/v1/health` returns 200 | inject → 200, envelope `data.status === 'ok'`; with a Prisma client pointed at a dead URL → 503 `INFRASTRUCTURE_UNAVAILABLE` |
| A malformed request returns the standard envelope | invalid JSON → 400 `MALFORMED_BODY`; schema violation → 400 `VALIDATION_FAILED` with `[{path,message}]`; unknown route → 404 `NOT_FOUND`; each carries `requestId` and `X-Request-Id`; a thrown non-AppError → 500 `INTERNAL_ERROR` with no stack and no original message |
| A repeated idempotent POST returns the original result | test-only route registered on the test app: same key → identical status and body, `Idempotent-Replayed: true`, handler ran once; 20 concurrent sends → handler ran once, others 409 or replay; same key different body → 422; missing header → 400 |
| Rate limits trigger correctly | anonymous: request 61 in a minute → 429 with `Retry-After`; authenticated: request 61 passes; per-route override: 11th login attempt → 429 while other routes still answer |
| An admin action appears in the queryable audit log | login → MFA → `DELETE /sessions/:id` with reason → `GET /audit-log` filtered by `action`, by `actorId`, by `from/to` each return the entry with admin id, timestamp, action, target, reason |

Plus the rules the plan states without a Done-when line: unenrolled admin → 403 `MFA_ENROLMENT_REQUIRED` on every admin route; recovery codes returned exactly once and a used one rejected on reuse; five MFA failures revoke the session; idle timeout at 15 min with the clock advanced; absolute expiry does not slide; force-logout invalidates that session and no other; `requireRecentReauth` rejects at 5 min + 1 s; suppression prevents the transport call; SNS signature/topic checks; permanent bounce and complaint suppress, transient does not; duplicate SNS message id is a no-op; no log line contains an email address (assert on captured pino output).

## Out of scope, deliberately

Kill switches and the SES channel switches (Phase 10b — but the three configuration sets are wired now so they have something to switch). User authentication and `requireAuth`/`requireEmailVerified` (Phase 3). Lifting a suppression (Phase 10b). Cross-admin session revocation. IP allowlisting, second-admin sign-off (§7). A read cache (§2 — Phases 15/16). Any Flutter or React code.
