# Phase 2 — Backend Core Infrastructure: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Fastify API — envelope, errors, logging, config, rate limiting, idempotency, admin identity with mandatory TOTP and sessions, audit log, health — plus the SES bounce/complaint pipeline, so that every §Phase 2 Done-when line passes and SES production access can be requested.

**Architecture:** `buildApp(config, deps)` registers cross-cutting Fastify plugins in a fixed order (logging → error handler → admin session → rate limit → idempotency) and then domain modules under `/v1`. Every rule lives in a service; routes validate with Zod and call services. All state — sessions, counters, idempotency records, audit entries, email log — is in PostgreSQL via Prisma; nothing is ever deleted.

**Tech Stack:** Node 22 · TypeScript 7 (strict, `verbatimModuleSyntax`, NodeNext ESM — imports end in `.js`) · Fastify 5.12 · `fastify-type-provider-zod` 7 + Zod 4 · `@fastify/cookie` 11 · `@fastify/cors` 11 · `@fastify/rate-limit` 11 · Prisma 7 (`prisma-client` generator, `@prisma/adapter-pg`) · `@node-rs/argon2` 2 · `otplib` 13 · `sns-validator` 0.3 · `@aws-sdk/client-sesv2` 3 · Vitest 5.

**Spec:** `docs/superpowers/specs/2026-09-05-phase-2-backend-core-design.md` — read it first; this plan argues from it. `docs/decisions/09-phase-2-defaults.md` records why SNS verification uses `sns-validator`.

## Global Constraints

- Plan `01_Development_Plan_v5.md` §Phase 2 is the acceptance criteria; `CLAUDE.md` invariants apply throughout. `archive/` is never read.
- UUID primary keys (`String @id @default(uuid()) @db.Uuid`), `snake_case` columns via `@map`/`@@map`, `Timestamptz(6)` timestamps. No row is ever `DELETE`d; rate-limit counters are reused in place.
- Envelope: success `{ data, meta? }`; error `{ error: { code, message, details? }, requestId }`; `X-Request-Id` on every response. Error codes are exactly the ones in the spec's table — they are API surface.
- No PII in logs: pino redaction of `authorization`, `cookie`, `set-cookie`, `password`, `email`, `phone`, `code`, `token`, `secret`, `recoveryCodes`. Bodies never logged. Request-line path has no query string.
- Timings: `ADMIN_SESSION_IDLE_MINUTES=15`, `ADMIN_SESSION_ABSOLUTE_HOURS=12`, `ADMIN_REAUTH_MINUTES=5`. Tiers: `RATE_LIMIT_ANON_PER_MINUTE=60`, `RATE_LIMIT_AUTH_PER_MINUTE=300`; login 10 per 15 min per IP; `mfa/verify` 5 per 5 min per admin.
- Idempotency header is `Idempotency-Key` (1–128 chars). Cookie is `rp_admin_session`, `HttpOnly`, `SameSite=Strict`, `Path=/v1/admin`, `Secure` in production. CSRF header is `X-Requested-With: RaajjePro-Admin` on every non-GET under `/v1/admin`.
- Password minimum 12 characters, maximum 512, argon2id. TOTP secrets encrypted at rest with AES-256-GCM under `ADMIN_TOTP_ENCRYPTION_KEY`.
- Email: suppression checked **before** the transport is called; `EMAIL_TRANSPORT=file` refused in production; three SES configuration sets, one per channel.
- Lint must stay clean under the existing `eslint.config.js` (`strictTypeChecked`, `no-floating-promises`, `consistent-type-imports`). Prettier config unchanged. Run `npm run lint && npm run typecheck` before every commit.
- Commits: no AI attribution trailers; imperative summary line; every task ends in a commit; push at the end of the phase.
- Tests run against the Docker database (`docker compose up -d`, `npm run db:migrate`). They `describe.skipIf(databaseUrl === undefined)` like Phase 0's. Isolation is by uniqueness — `randomUUID()` in emails, addresses and `remoteAddress` — never by truncation.

## File structure

```
backend/src/
  main.ts                            boot: loadConfig → prisma → buildApp → listen (Task 3)
  app.ts                             buildApp(config, deps) (Task 2, extended by later tasks)
  config/env.ts                      loadConfig, Config type (Task 1)
  core/errors.ts                     AppError + subclasses (Task 2)
  core/envelope.ts                   ok(), fail() (Task 2)
  core/error-handler.ts              registerErrorHandling(app) (Task 2)
  core/logging.ts                    loggerOptions(config), genReqId (Task 2)
  core/clock.ts                      Clock type, systemClock (Task 2)
  core/canonical-json.ts             stable stringify for hashing (Task 6)
  plugins/rate-limit.ts              registerRateLimit(app, deps); PostgresRateLimitStore (Task 5)
  plugins/idempotency.ts             registerIdempotency(app, deps) (Task 6)
  plugins/admin-session.ts           registerAdminSession(app, deps); request.principal (Task 9)
  modules/health/routes.ts           GET /v1/health (Task 3)
  modules/audit/{types,repository,service,routes}.ts   (Tasks 7, 11)
  modules/admin-auth/crypto.ts       hashPassword, verifyPassword, DUMMY_HASH, newSessionToken, hashToken, encryptSecret, decryptSecret, newRecoveryCodes (Task 8)
  modules/admin-auth/repository.ts   AdminRepository (Task 8)
  modules/admin-auth/service.ts      AdminAuthService (Tasks 8, 10)
  modules/admin-auth/guards.ts       requireAdmin, requirePasswordSession, requireRecentReauth (Task 9)
  modules/admin-auth/schema.ts       Zod schemas (Task 9)
  modules/admin-auth/routes.ts       /v1/admin/auth/* (Tasks 9, 10)
  modules/email/types.ts             OutboundEmail, EmailSender, EmailTransport, SendOutcome (Task 12)
  modules/email/service.ts           EmailService (Task 12)
  modules/email/transports/file.ts   FileEmailTransport (Task 12)
  modules/email/transports/ses.ts    SesEmailTransport (Task 12)
  modules/email/sns/validator.ts     SnsMessageValidator + SnsValidatorAdapter (Task 13)
  modules/email/sns/events.ts        applySesEvent (Task 13)
  modules/email/sns/routes.ts        POST /v1/webhooks/ses-events (Task 13)
  cli/admin-create.ts                npm run admin:create (Task 11)
  db/client.ts, jobs/heartbeat.ts    unchanged; jobs/status.ts moves to loadConfig (Task 3)
backend/test/
  helpers/app.ts                     buildTestApp(overrides) — shared by every route test (Task 2)
  helpers/admin.ts                   createEnrolledAdmin(app) → { cookie, adminId } (Task 10)
  <one test file per task, named in each task>
backend/prisma/schema.prisma + migrations/<ts>_phase2_core_infrastructure/ (Task 4)
docs/api/versioning.md · docs/ops/ses-production-access.md · docs/decisions/10-phase-2-backend-core.md (Task 14)
```

---

### Task 1: Dependencies and the typed, fail-fast config module

**Files:**
- Modify: `backend/package.json` (dependencies, scripts)
- Create: `backend/src/config/env.ts` (replaces the contents of the Phase 0 file)
- Modify: `backend/.env.example`, `backend/.env`
- Test: `backend/test/config.test.ts`

**Interfaces:**
- Produces: `loadConfig(env: NodeJS.ProcessEnv): Config`, `ConfigError extends Error { issues: string[] }`, and the `Config` type below. Every later task reads `config.<field>`.

- [ ] **Step 1: Install dependencies**

```bash
cd backend
npm install fastify@5.12.3 @fastify/cookie@11.1.2 @fastify/cors@11.3.0 @fastify/rate-limit@11.2.0 fastify-type-provider-zod@7.0.0 zod@4.5.4 @node-rs/argon2@2.2.0 otplib@13.5.0 sns-validator@0.3.5 @aws-sdk/client-sesv2@3.1127.0
npm install -D @types/sns-validator@0.3.3
```

Then add to `scripts` in `backend/package.json`: `"admin:create": "tsx --env-file-if-exists=.env src/cli/admin-create.ts"`.

- [ ] **Step 2: Write the failing test**

`backend/test/config.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { ConfigError, loadConfig } from '../src/config/env.js';

const minimal = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://u:p@localhost:5435/db',
  ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
  EMAIL_FROM_ADDRESS: 'no-reply@example.test',
};

describe('loadConfig', () => {
  it('applies the documented defaults', () => {
    const config = loadConfig(minimal);
    expect(config.port).toBe(3000);
    expect(config.host).toBe('0.0.0.0');
    expect(config.logLevel).toBe('info');
    expect(config.trustProxy).toBe(false);
    expect(config.admin.sessionIdleMinutes).toBe(15);
    expect(config.admin.sessionAbsoluteHours).toBe(12);
    expect(config.admin.reauthMinutes).toBe(5);
    expect(config.admin.origin).toBe('http://localhost:5173');
    expect(config.rateLimit.anonPerMinute).toBe(60);
    expect(config.rateLimit.authPerMinute).toBe(300);
    expect(config.email.transport).toBe('file');
    expect(config.admin.totpEncryptionKey).toEqual(Buffer.alloc(32, 7));
  });

  it('names every missing or malformed variable in one error', () => {
    let caught: unknown;
    try {
      loadConfig({ NODE_ENV: 'test', PORT: 'abc' });
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(ConfigError);
    const issues = (caught as ConfigError).issues.join('\n');
    expect(issues).toContain('DATABASE_URL');
    expect(issues).toContain('ADMIN_TOTP_ENCRYPTION_KEY');
    expect(issues).toContain('EMAIL_FROM_ADDRESS');
    expect(issues).toContain('PORT');
  });

  it('rejects an encryption key that is not 32 bytes', () => {
    expect(() =>
      loadConfig({ ...minimal, ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(16).toString('base64') }),
    ).toThrow(/ADMIN_TOTP_ENCRYPTION_KEY/);
  });

  it('refuses the file transport and a plain-http admin origin in production', () => {
    const production = { ...minimal, NODE_ENV: 'production', EMAIL_TRANSPORT: 'file' };
    expect(() => loadConfig(production)).toThrow(/EMAIL_TRANSPORT/);
    expect(() =>
      loadConfig({
        ...production,
        EMAIL_TRANSPORT: 'ses',
        AWS_REGION: 'ap-south-1',
        SES_CONFIGURATION_SET_OTP: 'otp',
        SES_CONFIGURATION_SET_NOTIFICATION: 'n',
        SES_CONFIGURATION_SET_MARKETING: 'm',
        SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
      }),
    ).toThrow(/ADMIN_ORIGIN/);
  });

  it('requires the SES variables only when the transport is ses', () => {
    expect(() => loadConfig({ ...minimal, EMAIL_TRANSPORT: 'ses' })).toThrow(/AWS_REGION/);
    const config = loadConfig({
      ...minimal,
      EMAIL_TRANSPORT: 'ses',
      AWS_REGION: 'ap-south-1',
      SES_CONFIGURATION_SET_OTP: 'otp',
      SES_CONFIGURATION_SET_NOTIFICATION: 'n',
      SES_CONFIGURATION_SET_MARKETING: 'm',
      SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
    });
    expect(config.email.transport).toBe('ses');
    if (config.email.transport === 'ses') {
      expect(config.email.configurationSets.otp).toBe('otp');
    }
  });
});
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd backend && npx vitest run test/config.test.ts`
Expected: FAIL — `loadConfig` is not exported.

- [ ] **Step 4: Write the config module**

Replace `backend/src/config/env.ts` entirely:

```ts
/**
 * Typed configuration, validated once at startup (plan §Phase 2: "typed
 * config module, fail-fast on missing vars").
 *
 * Configuration comes from process environment variables and nowhere else —
 * see .env.example, which is the contract for what a deployment must provide.
 * Every failure is collected and reported together so a deployment with three
 * missing variables learns about all three on the first boot, not the third.
 */
import { z } from 'zod';

const bool = z.enum(['true', 'false']).transform((v) => v === 'true');
const int = (fallback: number) => z.coerce.number().int().positive().default(fallback);

const base32Key = z
  .string()
  .transform((v, ctx) => {
    const bytes = Buffer.from(v, 'base64');
    if (bytes.length !== 32) {
      ctx.addIssue({ code: 'custom', message: 'must be 32 bytes, base64-encoded' });
      return z.NEVER;
    }
    return bytes;
  });

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: int(3000),
  HOST: z.string().min(1).default('0.0.0.0'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  TRUST_PROXY: bool.default(false),
  DATABASE_URL: z.string().min(1),

  ADMIN_ORIGIN: z.string().min(1).default('http://localhost:5173'),
  ADMIN_SESSION_IDLE_MINUTES: int(15),
  ADMIN_SESSION_ABSOLUTE_HOURS: int(12),
  ADMIN_REAUTH_MINUTES: int(5),
  ADMIN_TOTP_ENCRYPTION_KEY: base32Key,

  RATE_LIMIT_ANON_PER_MINUTE: int(60),
  RATE_LIMIT_AUTH_PER_MINUTE: int(300),

  EMAIL_TRANSPORT: z.enum(['file', 'ses']).default('file'),
  EMAIL_FROM_ADDRESS: z.string().min(3),
  AWS_REGION: z.string().min(1).optional(),
  SES_CONFIGURATION_SET_OTP: z.string().min(1).optional(),
  SES_CONFIGURATION_SET_NOTIFICATION: z.string().min(1).optional(),
  SES_CONFIGURATION_SET_MARKETING: z.string().min(1).optional(),
  SES_EVENTS_TOPIC_ARN: z.string().min(1).optional(),
});

export type EmailChannel = 'otp' | 'notification' | 'marketing';

export interface SesEmailConfig {
  transport: 'ses';
  fromAddress: string;
  region: string;
  configurationSets: Record<EmailChannel, string>;
  eventsTopicArn: string;
}

export interface FileEmailConfig {
  transport: 'file';
  fromAddress: string;
  /** Directory the file transport writes into. Gitignored. */
  directory: string;
}

export interface Config {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  host: string;
  logLevel: 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace';
  trustProxy: boolean;
  databaseUrl: string;
  admin: {
    origin: string;
    sessionIdleMinutes: number;
    sessionAbsoluteHours: number;
    reauthMinutes: number;
    totpEncryptionKey: Buffer;
    cookieSecure: boolean;
  };
  rateLimit: { anonPerMinute: number; authPerMinute: number };
  email: SesEmailConfig | FileEmailConfig;
}

export class ConfigError extends Error {
  constructor(public readonly issues: string[]) {
    super(`Invalid configuration (see .env.example):\n  ${issues.join('\n  ')}`);
    this.name = 'ConfigError';
  }
}

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  // Empty strings are "unset": a CI runner that exports FOO= did not set FOO.
  const cleaned = Object.fromEntries(Object.entries(env).filter(([, v]) => v !== undefined && v !== ''));
  const parsed = schema.safeParse(cleaned);
  const issues: string[] = [];
  if (!parsed.success) {
    for (const issue of parsed.error.issues) {
      issues.push(`${issue.path.join('.')}: ${issue.message}`);
    }
    throw new ConfigError(issues);
  }
  const v = parsed.data;

  const production = v.NODE_ENV === 'production';
  if (production && v.EMAIL_TRANSPORT !== 'ses') {
    issues.push('EMAIL_TRANSPORT: must be "ses" in production');
  }
  if (production && !v.ADMIN_ORIGIN.startsWith('https://')) {
    issues.push('ADMIN_ORIGIN: must be an https:// origin in production');
  }

  let email: Config['email'];
  if (v.EMAIL_TRANSPORT === 'ses') {
    const required: [string, string | undefined][] = [
      ['AWS_REGION', v.AWS_REGION],
      ['SES_CONFIGURATION_SET_OTP', v.SES_CONFIGURATION_SET_OTP],
      ['SES_CONFIGURATION_SET_NOTIFICATION', v.SES_CONFIGURATION_SET_NOTIFICATION],
      ['SES_CONFIGURATION_SET_MARKETING', v.SES_CONFIGURATION_SET_MARKETING],
      ['SES_EVENTS_TOPIC_ARN', v.SES_EVENTS_TOPIC_ARN],
    ];
    for (const [name, value] of required) {
      if (value === undefined) issues.push(`${name}: required when EMAIL_TRANSPORT=ses`);
    }
    if (issues.length > 0) throw new ConfigError(issues);
    email = {
      transport: 'ses',
      fromAddress: v.EMAIL_FROM_ADDRESS,
      region: v.AWS_REGION ?? '',
      configurationSets: {
        otp: v.SES_CONFIGURATION_SET_OTP ?? '',
        notification: v.SES_CONFIGURATION_SET_NOTIFICATION ?? '',
        marketing: v.SES_CONFIGURATION_SET_MARKETING ?? '',
      },
      eventsTopicArn: v.SES_EVENTS_TOPIC_ARN ?? '',
    };
  } else {
    if (issues.length > 0) throw new ConfigError(issues);
    email = { transport: 'file', fromAddress: v.EMAIL_FROM_ADDRESS, directory: '.mail' };
  }

  return {
    nodeEnv: v.NODE_ENV,
    port: v.PORT,
    host: v.HOST,
    logLevel: v.LOG_LEVEL,
    trustProxy: v.TRUST_PROXY,
    databaseUrl: v.DATABASE_URL,
    admin: {
      origin: v.ADMIN_ORIGIN,
      sessionIdleMinutes: v.ADMIN_SESSION_IDLE_MINUTES,
      sessionAbsoluteHours: v.ADMIN_SESSION_ABSOLUTE_HOURS,
      reauthMinutes: v.ADMIN_REAUTH_MINUTES,
      totpEncryptionKey: v.ADMIN_TOTP_ENCRYPTION_KEY,
      cookieSecure: production,
    },
    rateLimit: { anonPerMinute: v.RATE_LIMIT_ANON_PER_MINUTE, authPerMinute: v.RATE_LIMIT_AUTH_PER_MINUTE },
    email,
  };
}
```

Keep the Phase 0 `requireEnv` export in this file for now — `main.ts` and `jobs/status.ts` still import it until Task 3 removes it.

- [ ] **Step 5: Update `.env.example` and `.env`**

Append to `backend/.env.example` (and mirror the same lines into your local `.env`, generating a real key with `openssl rand -base64 32`):

```
# --- HTTP server ------------------------------------------------------------
PORT=3000
HOST=0.0.0.0
# fatal | error | warn | info | debug | trace. Redaction applies at every level.
LOG_LEVEL=info
# Believe X-Forwarded-For. Only true behind a proxy you control.
TRUST_PROXY=false

# --- Admin panel (Phase 2 admin identity) -----------------------------------
# The React admin app's origin. CORS allows exactly this origin, with credentials.
# Must be https:// in production.
ADMIN_ORIGIN=http://localhost:5173
# Session controls (plan §Phase 2, Round 12). Idle slides on each request;
# absolute does not. Re-auth is what Phase 10a demands before an ID document.
ADMIN_SESSION_IDLE_MINUTES=15
ADMIN_SESSION_ABSOLUTE_HOURS=12
ADMIN_REAUTH_MINUTES=5
# 32 random bytes, base64. Encrypts TOTP seeds at rest (AES-256-GCM) so a
# database dump does not yield working authenticators. Generate with:
#   openssl rand -base64 32
# The value below is for the local container only.
ADMIN_TOTP_ENCRYPTION_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=

# --- Rate limiting (plan §Phase 2 global tiers) -----------------------------
RATE_LIMIT_ANON_PER_MINUTE=60
RATE_LIMIT_AUTH_PER_MINUTE=300

# --- Email (Amazon SES is the only vendor — CLAUDE.md invariant 10) ---------
# file: write each message as JSON into backend/.mail/ (development/test only;
#       refused in production). ses: send through Amazon SES v2.
EMAIL_TRANSPORT=file
EMAIL_FROM_ADDRESS=no-reply@raajjepro.local
# Required when EMAIL_TRANSPORT=ses. Credentials come from the AWS SDK default
# chain (instance role, or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the
# host environment) — never from this file.
AWS_REGION=
# Three configuration sets, one per channel, so Phase 10b can kill OTP,
# notification and marketing email independently and their reputation
# metrics stay separate.
SES_CONFIGURATION_SET_OTP=
SES_CONFIGURATION_SET_NOTIFICATION=
SES_CONFIGURATION_SET_MARKETING=
# The SNS topic the SES event destinations publish to. The webhook accepts
# notifications from this topic and no other.
SES_EVENTS_TOPIC_ARN=
```

Add `.mail/` to `backend/.gitignore`.

- [ ] **Step 6: Run the test, lint and typecheck**

Run: `cd backend && npx vitest run test/config.test.ts && npm run lint && npm run typecheck`
Expected: 5 tests pass; lint and typecheck clean. If ESLint complains about the `z.NEVER` branch or `ctx.addIssue` typing under Zod 4, use `ctx.issues.push({ code: 'custom', message: '...', input: v })` — Zod 4's transform context exposes `issues` as well as `addIssue`.

- [ ] **Step 7: Commit**

```bash
git add backend/package.json backend/package-lock.json backend/src/config/env.ts backend/test/config.test.ts backend/.env.example backend/.gitignore
git commit -m "Phase 2 — typed, fail-fast configuration and the server dependencies"
```

---

### Task 2: Envelope, error classes, error handler, logging, `buildApp()` skeleton

**Files:**
- Create: `backend/src/core/errors.ts`, `backend/src/core/envelope.ts`, `backend/src/core/error-handler.ts`, `backend/src/core/logging.ts`, `backend/src/core/clock.ts`, `backend/src/app.ts`
- Create: `backend/test/helpers/app.ts`
- Test: `backend/test/envelope.test.ts`

**Interfaces:**
- Produces:
  - `class AppError extends Error { readonly status: number; readonly code: string; readonly details?: unknown }` and subclasses `ValidationError(details)`, `AuthenticationError(code = 'UNAUTHENTICATED', message?)`, `AuthorizationError(code = 'FORBIDDEN', message?)`, `BusinessRuleError(code, message, details?)`, `ConflictError(code = 'CONFLICT', message?)`, `NotFoundError(message = 'Not found')`, `InfrastructureError(message?)`, `RateLimitedError(retryAfterSeconds)`.
  - `ok<T>(data: T, meta?: { nextCursor: string | null })` → `{ data, meta? }`; `fail(code, message, requestId, details?)`.
  - `buildApp(config: Config, deps: AppDeps): Promise<FastifyInstance>` where `AppDeps = { prisma: PrismaClient; clock: Clock }` (later tasks add `emailTransport`, `snsValidator`).
  - `type Clock = () => Date; export const systemClock: Clock`.
  - Test helper `buildTestApp(overrides?: { config?: Partial<ConfigOverrides>; clock?: Clock; routes?: (app) => void })`.

- [ ] **Step 1: Write the failing test**

`backend/test/helpers/app.ts`:

```ts
import 'dotenv/config';
import type { FastifyInstance } from 'fastify';

import { buildApp, type AppDeps } from '../../src/app.js';
import { loadConfig, type Config } from '../../src/config/env.js';
import type { Clock } from '../../src/core/clock.js';
import { createPrismaClient } from '../../src/db/client.js';

export const databaseUrl = process.env.DATABASE_URL;

export interface TestAppOptions {
  clock?: Clock;
  anonPerMinute?: number;
  authPerMinute?: number;
  sessionIdleMinutes?: number;
  sessionAbsoluteHours?: number;
  reauthMinutes?: number;
  deps?: Partial<AppDeps>;
  /** Extra routes registered after the app's own — for testing middleware in isolation. */
  routes?: (app: FastifyInstance) => void;
}

export function testConfig(options: TestAppOptions = {}): Config {
  const base = loadConfig({
    ...process.env,
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    ADMIN_TOTP_ENCRYPTION_KEY: process.env.ADMIN_TOTP_ENCRYPTION_KEY ?? Buffer.alloc(32, 1).toString('base64'),
    EMAIL_FROM_ADDRESS: 'test@raajjepro.local',
    EMAIL_TRANSPORT: 'file',
  });
  return {
    ...base,
    admin: {
      ...base.admin,
      sessionIdleMinutes: options.sessionIdleMinutes ?? base.admin.sessionIdleMinutes,
      sessionAbsoluteHours: options.sessionAbsoluteHours ?? base.admin.sessionAbsoluteHours,
      reauthMinutes: options.reauthMinutes ?? base.admin.reauthMinutes,
    },
    rateLimit: {
      anonPerMinute: options.anonPerMinute ?? 1000,
      authPerMinute: options.authPerMinute ?? 1000,
    },
  };
}

/** A clock the test can move. `advance(ms)` is how idle timeouts are tested — not by waiting. */
export function controllableClock(start = new Date()) {
  let now = start;
  const clock: Clock = () => now;
  return {
    clock,
    advance(ms: number) {
      now = new Date(now.getTime() + ms);
    },
    set(date: Date) {
      now = date;
    },
  };
}

export async function buildTestApp(options: TestAppOptions = {}) {
  const config = testConfig(options);
  const prisma = options.deps?.prisma ?? createPrismaClient(config.databaseUrl);
  const app = await buildApp(config, {
    prisma,
    clock: options.clock ?? (() => new Date()),
    ...options.deps,
  });
  if (options.routes) {
    options.routes(app);
  }
  await app.ready();
  return { app, prisma, config };
}
```

Note `LOG_LEVEL: 'silent'` — add `'silent'` to the `LOG_LEVEL` enum in `config/env.ts` (pino accepts it) and to the `Config['logLevel']` union.

`backend/test/envelope.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { BusinessRuleError } from '../src/core/errors.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('response envelope and error handling', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp({
      routes: (app) => {
        app.post(
          '/v1/_test/validated',
          { schema: { body: z.object({ name: z.string().min(2), amountLaari: z.number().int() }) } },
          async (request) => ({ data: request.body }),
        );
        app.get('/v1/_test/business-rule', async () => {
          throw new BusinessRuleError('EMAIL_NOT_VERIFIED', 'Verify your email first');
        });
        app.get('/v1/_test/explode', async () => {
          throw new Error('database password is hunter2');
        });
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('wraps a Zod violation in the envelope with path and message only', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/validated',
      payload: { name: 'x', amountLaari: 1.5 },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json<{ error: { code: string; details: { path: string; message: string }[] }; requestId: string }>();
    expect(body.error.code).toBe('VALIDATION_FAILED');
    expect(body.error.details.map((d) => d.path).sort()).toEqual(['amountLaari', 'name']);
    for (const detail of body.error.details) {
      expect(Object.keys(detail).sort()).toEqual(['message', 'path']);
    }
    expect(body.requestId).toBe(res.headers['x-request-id']);
  });

  it('wraps invalid JSON as MALFORMED_BODY', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/validated',
      headers: { 'content-type': 'application/json' },
      payload: '{ not json',
    });
    expect(res.statusCode).toBe(400);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('MALFORMED_BODY');
  });

  it('wraps an unknown route as NOT_FOUND', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/nowhere' });
    expect(res.statusCode).toBe(404);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('NOT_FOUND');
  });

  it('carries a business-rule code at 422', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/business-rule' });
    expect(res.statusCode).toBe(422);
    expect(res.json<{ error: { code: string; message: string } }>().error).toEqual({
      code: 'EMAIL_NOT_VERIFIED',
      message: 'Verify your email first',
    });
  });

  it('never leaks an unexpected error', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/explode' });
    expect(res.statusCode).toBe(500);
    expect(res.body).not.toContain('hunter2');
    expect(res.body).not.toContain('stack');
    expect(res.json<{ error: { code: string } }>().error.code).toBe('INTERNAL_ERROR');
  });

  it('honours a UUID X-Request-Id and replaces anything else', async () => {
    const given = '5a3d0e8c-2c3a-4d8e-9f1b-7c6a5b4d3e2f';
    const honoured = await ctx.app.inject({ method: 'GET', url: '/v1/nowhere', headers: { 'x-request-id': given } });
    expect(honoured.headers['x-request-id']).toBe(given);
    const replaced = await ctx.app.inject({ method: 'GET', url: '/v1/nowhere', headers: { 'x-request-id': 'evil\nheader' } });
    expect(replaced.headers['x-request-id']).not.toBe('evil\nheader');
    expect(replaced.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/envelope.test.ts`
Expected: FAIL — cannot resolve `../src/app.js`.

- [ ] **Step 3: Write `core/clock.ts`, `core/errors.ts`, `core/envelope.ts`**

`backend/src/core/clock.ts`:

```ts
/** Time is injected so idle timeouts and expiries are tested by moving a clock, not by waiting. */
export type Clock = () => Date;

export const systemClock: Clock = () => new Date();
```

`backend/src/core/errors.ts`:

```ts
/**
 * Error classes, one per category in plan §Phase 2. Each carries a fixed HTTP
 * status and a stable machine-readable `code` — the frontend routes on codes,
 * so renaming one is a breaking change (backend/CLAUDE.md, API contract).
 */
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ValidationError extends AppError {
  constructor(details: { path: string; message: string }[], message = 'Request failed validation') {
    super(400, 'VALIDATION_FAILED', message, details);
  }
}

export class AuthenticationError extends AppError {
  constructor(code = 'UNAUTHENTICATED', message = 'Authentication required') {
    super(401, code, message);
  }
}

export class AuthorizationError extends AppError {
  constructor(code = 'FORBIDDEN', message = 'Not allowed') {
    super(403, code, message);
  }
}

/** The code is the rule that was broken, e.g. EMAIL_NOT_VERIFIED. */
export class BusinessRuleError extends AppError {
  constructor(code: string, message: string, details?: unknown) {
    super(422, code, message, details);
  }
}

export class ConflictError extends AppError {
  constructor(code = 'CONFLICT', message = 'Conflict') {
    super(409, code, message);
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'Not found') {
    super(404, 'NOT_FOUND', message);
  }
}

export class InfrastructureError extends AppError {
  constructor(message = 'A dependency is unavailable') {
    super(503, 'INFRASTRUCTURE_UNAVAILABLE', message);
  }
}

export class RateLimitedError extends AppError {
  constructor(public readonly retryAfterSeconds: number) {
    super(429, 'RATE_LIMITED', 'Too many requests', { retryAfterSeconds });
  }
}
```

`backend/src/core/envelope.ts`:

```ts
/** The standard response envelope (plan §Phase 2). Every response, success or failure, is one of these two shapes. */
export interface SuccessEnvelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

export interface ErrorEnvelope {
  error: { code: string; message: string; details?: unknown };
  requestId: string;
}

export function ok<T>(data: T, meta?: { nextCursor: string | null }): SuccessEnvelope<T> {
  return meta === undefined ? { data } : { data, meta };
}

export function fail(code: string, message: string, requestId: string, details?: unknown): ErrorEnvelope {
  return details === undefined ? { error: { code, message }, requestId } : { error: { code, message, details }, requestId };
}
```

- [ ] **Step 4: Write `core/logging.ts` and `core/error-handler.ts`**

`backend/src/core/logging.ts`:

```ts
import { randomUUID } from 'node:crypto';
import type { IncomingMessage } from 'node:http';

import type { FastifyServerOptions } from 'fastify';

import type { Config } from '../config/env.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Correlation id: a client-supplied X-Request-Id is honoured only when it is a
 * UUID — anything else is replaced, so a header cannot inject into the log.
 */
export function genReqId(req: IncomingMessage): string {
  const given = req.headers['x-request-id'];
  const value = Array.isArray(given) ? given[0] : given;
  return value !== undefined && UUID.test(value) ? value.toLowerCase() : randomUUID();
}

/**
 * Structured logging with no PII (plan §Phase 2). Redaction is by key name at
 * any depth, so a new log call cannot leak an email by accident; bodies are
 * never logged at all because no serializer includes them.
 */
export function loggerOptions(config: Config): NonNullable<FastifyServerOptions['logger']> {
  return {
    level: config.logLevel,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'res.headers["set-cookie"]',
        '*.password',
        '*.email',
        '*.phone',
        '*.code',
        '*.token',
        '*.secret',
        '*.recoveryCodes',
        '*.*.password',
        '*.*.email',
        '*.*.phone',
        '*.*.code',
        '*.*.token',
        '*.*.secret',
        '*.*.recoveryCodes',
      ],
      censor: '[redacted]',
    },
    serializers: {
      req(req) {
        return {
          method: req.method,
          // Path only: a query string may carry an email or a reference code.
          path: req.url.split('?')[0],
          ip: req.ip,
        };
      },
      res(res) {
        return { statusCode: res.statusCode };
      },
    },
  };
}
```

`backend/src/core/error-handler.ts`:

```ts
import type { FastifyError, FastifyInstance } from 'fastify';
import { hasZodFastifySchemaValidationErrors } from 'fastify-type-provider-zod';

import { fail } from './envelope.js';
import { AppError, RateLimitedError } from './errors.js';

/**
 * Global error handling (plan §Phase 2): every failure — ours, Fastify's own
 * 404 and body-parse errors, Zod validation — leaves as the standard envelope.
 * Unexpected errors are logged with the request id and replaced by a fixed
 * message; internals never reach a client.
 */
export function registerErrorHandling(app: FastifyInstance): void {
  app.setNotFoundHandler(async (request, reply) => {
    return reply.code(404).send(fail('NOT_FOUND', 'No such route', request.id));
  });

  app.setErrorHandler(async (error: FastifyError | AppError, request, reply) => {
    if (error instanceof AppError) {
      if (error instanceof RateLimitedError) {
        void reply.header('retry-after', String(error.retryAfterSeconds));
      }
      return reply.code(error.status).send(fail(error.code, error.message, request.id, error.details));
    }

    if (hasZodFastifySchemaValidationErrors(error)) {
      const details = error.validation.map((v) => ({
        path: v.instancePath.replace(/^\//, '').replaceAll('/', '.'),
        message: v.message ?? 'Invalid value',
      }));
      return reply.code(400).send(fail('VALIDATION_FAILED', 'Request failed validation', request.id, details));
    }

    const code = 'code' in error ? error.code : undefined;
    if (typeof code === 'string' && code.startsWith('FST_ERR_CTP_')) {
      return reply.code(400).send(fail('MALFORMED_BODY', 'The request body could not be parsed', request.id));
    }

    request.log.error({ err: error }, 'unhandled error');
    return reply.code(500).send(fail('INTERNAL_ERROR', 'Something went wrong', request.id));
  });
}
```

- [ ] **Step 5: Write `app.ts`**

```ts
import Fastify, { type FastifyInstance } from 'fastify';
import { serializerCompiler, validatorCompiler, type ZodTypeProvider } from 'fastify-type-provider-zod';

import type { Config } from './config/env.js';
import type { Clock } from './core/clock.js';
import { registerErrorHandling } from './core/error-handler.js';
import { genReqId, loggerOptions } from './core/logging.js';
import type { PrismaClient } from './generated/prisma/client.js';

export interface AppDeps {
  prisma: PrismaClient;
  clock: Clock;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
    deps: AppDeps;
  }
}

/**
 * Builds the API. Plugins register in a fixed order — logging and errors, then
 * (later tasks) admin session, rate limit, idempotency — then the modules under
 * /v1. Tests call this and use inject(); main.ts calls it and listens.
 */
export async function buildApp(config: Config, deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({
    logger: loggerOptions(config),
    genReqId,
    requestIdHeader: false,
    trustProxy: config.trustProxy,
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);
  app.decorate('config', config);
  app.decorate('deps', deps);

  app.addHook('onSend', async (request, reply) => {
    void reply.header('x-request-id', request.id);
  });

  registerErrorHandling(app);

  return app;
}
```

- [ ] **Step 6: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run test/envelope.test.ts && npm run lint && npm run typecheck`
Expected: 6 pass. If `res.headers['x-request-id']` is missing on the 404 path, confirm the `onSend` hook is registered before `registerErrorHandling` (hooks added to the root instance apply to not-found replies).

- [ ] **Step 7: Commit**

```bash
git add backend/src/core backend/src/app.ts backend/test/helpers/app.ts backend/test/envelope.test.ts backend/src/config/env.ts
git commit -m "Phase 2 — Fastify app factory, standard envelope, error classes and redacted logging"
```

---

### Task 3: `GET /v1/health`, the server entrypoint, config everywhere

**Files:**
- Create: `backend/src/modules/health/routes.ts`
- Modify: `backend/src/app.ts` (register health), `backend/src/main.ts` (rewrite), `backend/src/jobs/status.ts` (use `loadConfig`), `backend/src/config/env.ts` (drop `requireEnv`)
- Test: `backend/test/health.test.ts`

**Interfaces:**
- Produces: `registerHealthRoutes(app)`; response `{ data: { status: 'ok', database: 'reachable', jobRunner: 'firing' | 'not-firing', lastHeartbeatAt: string | null } }`.

- [ ] **Step 1: Write the failing test**

`backend/test/health.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('GET /v1/health', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp();
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('returns 200 with the database reachable and the job runner state', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/health' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { status: string; database: string; jobRunner: string } }>();
    expect(body.data.status).toBe('ok');
    expect(body.data.database).toBe('reachable');
    expect(['firing', 'not-firing']).toContain(body.data.jobRunner);
  });

  it('returns 503 INFRASTRUCTURE_UNAVAILABLE when the database cannot be reached', async () => {
    const dead = createPrismaClient('postgresql://nobody:nothing@127.0.0.1:1/none?connect_timeout=1');
    const broken = await buildTestApp({ deps: { prisma: dead } });
    try {
      const res = await broken.app.inject({ method: 'GET', url: '/v1/health' });
      expect(res.statusCode).toBe(503);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('INFRASTRUCTURE_UNAVAILABLE');
    } finally {
      await broken.app.close();
      await dead.$disconnect();
    }
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/health.test.ts`
Expected: FAIL — 404 `NOT_FOUND`.

- [ ] **Step 3: Write the health module and register it**

`backend/src/modules/health/routes.ts`:

```ts
import type { FastifyInstance } from 'fastify';

import { ok } from '../../core/envelope.js';
import { InfrastructureError } from '../../core/errors.js';
import { readHeartbeat } from '../../jobs/heartbeat.js';

/**
 * GET /v1/health — public, no auth (it is what §5 measures availability
 * against). 503 when the database is unreachable: a dead database must never
 * read as up. A silent job runner is reported, not treated as down.
 */
export function registerHealthRoutes(app: FastifyInstance): void {
  app.get('/v1/health', async (_request, reply) => {
    const { prisma, clock } = app.deps;
    let heartbeat;
    try {
      heartbeat = await readHeartbeat(prisma, clock());
    } catch {
      throw new InfrastructureError('Database unreachable');
    }
    return reply.send(
      ok({
        status: 'ok',
        database: 'reachable',
        jobRunner: heartbeat.firing ? 'firing' : 'not-firing',
        lastHeartbeatAt: heartbeat.lastFiredAt?.toISOString() ?? null,
      }),
    );
  });
}
```

In `app.ts`, after `registerErrorHandling(app);` add:

```ts
  registerHealthRoutes(app);
```

with the import `import { registerHealthRoutes } from './modules/health/routes.js';`.

- [ ] **Step 4: Rewrite `main.ts` and `jobs/status.ts`; remove `requireEnv`**

`backend/src/main.ts`:

```ts
/**
 * Backend entrypoint: validate configuration, connect, build the app, listen.
 * A configuration error prints every issue and exits 1 before the database is
 * touched. SIGTERM/SIGINT close the server and the connection pool.
 */
import { buildApp } from './app.js';
import { ConfigError, loadConfig } from './config/env.js';
import { systemClock } from './core/clock.js';
import { createPrismaClient } from './db/client.js';

let config;
try {
  config = loadConfig(process.env);
} catch (error) {
  if (error instanceof ConfigError) {
    console.error(error.message);
    process.exit(1);
  }
  throw error;
}

const prisma = createPrismaClient(config.databaseUrl);
const app = await buildApp(config, { prisma, clock: systemClock });

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  await app.close();
  await prisma.$disconnect();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

await app.listen({ port: config.port, host: config.host });
```

(Later tasks extend the `deps` object here with the email transport and SNS validator — Task 12 and Task 13 say exactly what to add.)

In `backend/src/jobs/status.ts`, replace the `requireEnv` import and use with:

```ts
import { loadConfig } from '../config/env.js';
// ...
const prisma = createPrismaClient(loadConfig(process.env).databaseUrl);
```

Then delete the `requireEnv` function and its doc comment from `config/env.ts` (nothing imports it any more — confirm with `grep -rn requireEnv backend/src`).

- [ ] **Step 5: Run tests, lint, typecheck; boot the server once**

Run: `cd backend && npx vitest run && npm run lint && npm run typecheck`
Expected: all pass.

Then: `cd backend && (npm run dev &) ; sleep 4; curl -s -i localhost:3000/v1/health; kill %1`
Expected: `HTTP/1.1 200`, `x-request-id` header, body `{"data":{"status":"ok",...}}`.

- [ ] **Step 6: Commit**

```bash
git add backend/src
git commit -m "Phase 2 — /v1/health, the listening server, and config loaded once at boot"
```

---

### Task 4: Prisma schema and the `phase2_core_infrastructure` migration

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Create: `backend/prisma/migrations/<timestamp>_phase2_core_infrastructure/migration.sql` (generated, then edited as described)
- Test: `backend/test/schema.test.ts`

**Interfaces:**
- Produces the Prisma models `RateLimitCounter`, `IdempotencyRecord`, `AdminUser`, `AdminSession`, `AdminRecoveryCode`, `AuditLogEntry`, `EmailMessage`, `EmailEvent`, `EmailSuppression` and the enums below. Every later task's repository uses these names and fields exactly.

- [ ] **Step 1: Write the failing test**

`backend/test/schema.test.ts` — asserts the two hand-edited storage properties, which Prisma does not track and a regenerated migration would silently lose:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('phase 2 schema', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('keeps rate_limit_counter UNLOGGED', async () => {
    const rows = await prisma.$queryRaw<{ relpersistence: string }[]>`
      SELECT relpersistence FROM pg_class WHERE relname = 'rate_limit_counter'`;
    expect(rows[0]?.relpersistence).toBe('u');
  });

  it('allows one active suppression per address but keeps lifted ones', async () => {
    const address = `dup-${crypto.randomUUID()}@example.test`;
    await prisma.emailSuppression.create({ data: { address, reason: 'manual' } });
    await expect(
      prisma.emailSuppression.create({ data: { address, reason: 'manual' } }),
    ).rejects.toThrow();
    await prisma.emailSuppression.updateMany({ where: { address }, data: { liftedAt: new Date(), liftReason: 'test' } });
    await expect(prisma.emailSuppression.create({ data: { address, reason: 'manual' } })).resolves.toBeDefined();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/schema.test.ts`
Expected: FAIL — `emailSuppression` does not exist on the client.

- [ ] **Step 3: Add the models to `schema.prisma`**

Append after `JobHeartbeat` (keep the file's existing header comment; update its last sentence to "Phase 2 adds the infrastructure tables below."):

```prisma
// ---------------------------------------------------------------------------
// Phase 2 — core infrastructure
// ---------------------------------------------------------------------------

/// Rate-limit window counters. UNLOGGED (set in the migration): out of the WAL
/// and PITR stream, which is right for ephemeral state — and means an unclean
/// shutdown truncates the table and every limit fails open for one window.
/// Rows are keyed per (scope, subject) and reused across windows, never deleted.
model RateLimitCounter {
  key             String   @id
  count           Int
  windowStartedAt DateTime @map("window_started_at") @db.Timestamptz(6)

  @@map("rate_limit_counter")
}

enum IdempotencyStatus {
  in_progress
  completed
  abandoned

  @@map("idempotency_status")
}

/// One row per (subject, operation, client key). A repeat with the same body
/// replays response_status/response_body; nothing here is ever deleted.
model IdempotencyRecord {
  id              String            @id @default(uuid()) @db.Uuid
  subject         String
  operation       String
  clientKey       String            @map("client_key")
  requestHash     String            @map("request_hash")
  status          IdempotencyStatus
  responseStatus  Int?              @map("response_status")
  responseHeaders Json?             @map("response_headers")
  responseBody    Json?             @map("response_body")
  createdAt       DateTime          @default(now()) @map("created_at") @db.Timestamptz(6)
  completedAt     DateTime?         @map("completed_at") @db.Timestamptz(6)

  @@unique([subject, operation, clientKey])
  @@map("idempotency_record")
}

enum AdminStatus {
  active
  disabled

  @@map("admin_status")
}

/// Admin identity (plan §Phase 2). One role in v1. `status` is the soft-delete
/// field. The TOTP secret is AES-256-GCM ciphertext; null until enrolment starts.
model AdminUser {
  id                  String      @id @default(uuid()) @db.Uuid
  email               String      @unique
  passwordHash        String      @map("password_hash")
  role                String      @default("admin")
  status              AdminStatus @default(active)
  totpSecretEncrypted String?     @map("totp_secret_encrypted")
  totpEnrolledAt      DateTime?   @map("totp_enrolled_at") @db.Timestamptz(6)
  passwordChangedAt   DateTime    @default(now()) @map("password_changed_at") @db.Timestamptz(6)
  createdAt           DateTime    @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt           DateTime    @updatedAt @map("updated_at") @db.Timestamptz(6)

  sessions      AdminSession[]
  recoveryCodes AdminRecoveryCode[]

  @@map("admin_user")
}

enum SessionRevokedReason {
  logout
  force_logout
  idle_timeout
  absolute_expiry
  mfa_failures
  password_change

  @@map("session_revoked_reason")
}

/// A browser session. The cookie holds a random token; only its sha256 is here.
model AdminSession {
  id                String                @id @default(uuid()) @db.Uuid
  adminId           String                @map("admin_id") @db.Uuid
  admin             AdminUser             @relation(fields: [adminId], references: [id])
  tokenHash         String                @unique @map("token_hash")
  createdAt         DateTime              @default(now()) @map("created_at") @db.Timestamptz(6)
  lastSeenAt        DateTime              @map("last_seen_at") @db.Timestamptz(6)
  expiresAt         DateTime              @map("expires_at") @db.Timestamptz(6)
  mfaVerifiedAt     DateTime?             @map("mfa_verified_at") @db.Timestamptz(6)
  reauthenticatedAt DateTime?             @map("reauthenticated_at") @db.Timestamptz(6)
  mfaFailures       Int                   @default(0) @map("mfa_failures")
  ipAddress         String                @map("ip_address")
  userAgent         String                @map("user_agent")
  revokedAt         DateTime?             @map("revoked_at") @db.Timestamptz(6)
  revokedReason     SessionRevokedReason? @map("revoked_reason")

  @@index([adminId, revokedAt])
  @@map("admin_session")
}

model AdminRecoveryCode {
  id        String    @id @default(uuid()) @db.Uuid
  adminId   String    @map("admin_id") @db.Uuid
  admin     AdminUser @relation(fields: [adminId], references: [id])
  codeHash  String    @map("code_hash")
  createdAt DateTime  @default(now()) @map("created_at") @db.Timestamptz(6)
  usedAt    DateTime? @map("used_at") @db.Timestamptz(6)
  revokedAt DateTime? @map("revoked_at") @db.Timestamptz(6)

  @@index([adminId, codeHash])
  @@map("admin_recovery_code")
}

enum AuditActorType {
  admin
  system

  @@map("audit_actor_type")
}

/// Append-only. Every admin action: who, when, what, on what, why (plan
/// §Phase 2). `metadata` holds IDs and enums only — never an email, phone or
/// document. No code path updates or deletes a row.
model AuditLogEntry {
  id         String         @id @default(uuid()) @db.Uuid
  actorType  AuditActorType @map("actor_type")
  actorId    String?        @map("actor_id") @db.Uuid
  action     String
  targetType String         @map("target_type")
  targetId   String         @map("target_id")
  reason     String
  metadata   Json?
  requestId  String?        @map("request_id")
  ipAddress  String?        @map("ip_address")
  createdAt  DateTime       @default(now()) @map("created_at") @db.Timestamptz(6)

  @@index([createdAt])
  @@index([actorId, createdAt])
  @@index([action, createdAt])
  @@map("audit_log_entry")
}

enum EmailChannel {
  otp
  notification
  marketing

  @@map("email_channel")
}

enum EmailMessageStatus {
  queued
  sent
  failed
  suppressed
  delivered
  bounced
  complained
  rejected
  delivery_delayed

  @@map("email_message_status")
}

/// Per-message delivery log — SES has no searchable console, so this is what
/// answers "did this user actually receive it?" (plan §Phase 3c, §Phase 10b).
model EmailMessage {
  id                String             @id @default(uuid()) @db.Uuid
  channel           EmailChannel
  toAddress         String             @map("to_address")
  recipientUserId   String?            @map("recipient_user_id") @db.Uuid
  subject           String
  status            EmailMessageStatus
  configurationSet  String?            @map("configuration_set")
  providerMessageId String?            @unique @map("provider_message_id")
  failureReason     String?            @map("failure_reason")
  createdAt         DateTime           @default(now()) @map("created_at") @db.Timestamptz(6)
  sentAt            DateTime?          @map("sent_at") @db.Timestamptz(6)
  lastEventAt       DateTime?          @map("last_event_at") @db.Timestamptz(6)

  events EmailEvent[]

  @@index([toAddress, createdAt])
  @@index([recipientUserId, createdAt])
  @@map("email_message")
}

/// One row per SNS notification received from the SES event destination.
/// `snsMessageId` is unique because SNS retries.
model EmailEvent {
  id                String        @id @default(uuid()) @db.Uuid
  snsMessageId      String        @unique @map("sns_message_id")
  messageId         String?       @map("message_id") @db.Uuid
  message           EmailMessage? @relation(fields: [messageId], references: [id])
  providerMessageId String?       @map("provider_message_id")
  eventType         String        @map("event_type")
  occurredAt        DateTime      @map("occurred_at") @db.Timestamptz(6)
  payload           Json
  receivedAt        DateTime      @default(now()) @map("received_at") @db.Timestamptz(6)

  @@index([providerMessageId])
  @@map("email_event")
}

enum SuppressionReason {
  hard_bounce
  complaint
  manual

  @@map("suppression_reason")
}

/// Addresses we must not send to. Active while lifted_at IS NULL — a partial
/// unique index on that condition is added by hand in the migration. Lifting
/// (Phase 10b) sets lifted_at; nothing is deleted.
model EmailSuppression {
  id              String            @id @default(uuid()) @db.Uuid
  address         String
  reason          SuppressionReason
  sourceEventId   String?           @map("source_event_id") @db.Uuid
  createdAt       DateTime          @default(now()) @map("created_at") @db.Timestamptz(6)
  liftedAt        DateTime?         @map("lifted_at") @db.Timestamptz(6)
  liftedByAdminId String?           @map("lifted_by_admin_id") @db.Uuid
  liftReason      String?           @map("lift_reason")

  @@index([address])
  @@map("email_suppression")
}
```

- [ ] **Step 4: Generate the migration, then edit it**

Run: `cd backend && npx prisma migrate dev --name phase2_core_infrastructure --create-only`

Open the generated `migration.sql` and append at the end:

```sql
-- ---------------------------------------------------------------------------
-- Hand-edited additions. Prisma tracks neither of these, so a regenerated
-- migration would lose them; test/schema.test.ts asserts both.
-- ---------------------------------------------------------------------------

-- Ephemeral counters stay out of the WAL (and so out of PITR). An unclean
-- shutdown truncates the table: every limit fails open for one window.
ALTER TABLE "rate_limit_counter" SET UNLOGGED;

-- One ACTIVE suppression per address; lifted rows stay as history.
CREATE UNIQUE INDEX "email_suppression_active_address_key"
  ON "email_suppression" ("address") WHERE "lifted_at" IS NULL;
```

Then apply: `npx prisma migrate dev` (applies the edited migration and regenerates the client). If Prisma reports drift, it is because the edit happened after `--create-only`; that is expected and applies cleanly.

- [ ] **Step 5: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run test/schema.test.ts && npm run lint && npm run typecheck`
Expected: 2 pass.

- [ ] **Step 6: Commit**

```bash
git add backend/prisma backend/test/schema.test.ts
git commit -m "Phase 2 — schema: admin identity, sessions, audit log, idempotency, rate-limit counters, email log and suppression"
```

---

### Task 5: Rate limiting — global tiers, per-route override, Postgres store

**Files:**
- Create: `backend/src/plugins/rate-limit.ts`
- Modify: `backend/src/app.ts` (register after error handling, before modules)
- Test: `backend/test/rate-limit.test.ts`

**Interfaces:**
- Consumes: `request.principal?: { id: string }` — declared here as an optional decoration so the store can key on it; Task 9's admin-session plugin sets it. Until then it is always undefined.
- Produces: `registerRateLimit(app)`; route override via `config: { rateLimit: { max, timeWindow } }`; `RateLimitedError` on 429.

- [ ] **Step 1: Write the failing test**

`backend/test/rate-limit.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, databaseUrl } from './helpers/app.js';

/** Distinct address per test so counters persisted by earlier runs cannot interfere. */
function freshIp() {
  const [a, b] = [Math.floor(Math.random() * 200) + 10, Math.floor(Math.random() * 250)];
  return `10.${String(a)}.${String(b)}.${String(Math.floor(Math.random() * 250) + 1)}`;
}

describe.skipIf(databaseUrl === undefined)('rate limiting', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp({
      anonPerMinute: 3,
      authPerMinute: 5,
      routes: (app) => {
        app.get('/v1/_test/open', async () => ({ data: 'open' }));
        app.get('/v1/_test/strict', { config: { rateLimit: { max: 1, timeWindow: '15 minutes' } } }, async () => ({
          data: 'strict',
        }));
        // Pretend-authenticated route: sets a principal so the store keys on the user, not the IP.
        app.get(
          '/v1/_test/as-user',
          {
            onRequest: async (request) => {
              request.principal = { kind: 'admin', id: String(request.headers['x-test-user']), sessionId: '', mfaVerified: true, totpEnrolled: true, reauthenticatedAt: null };
            },
          },
          async () => ({ data: 'user' }),
        );
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('blocks the request after the anonymous tier with the envelope and Retry-After', async () => {
    const ip = freshIp();
    for (let i = 0; i < 3; i += 1) {
      const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip });
      expect(res.statusCode).toBe(200);
    }
    const blocked = await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip });
    expect(blocked.statusCode).toBe(429);
    const body = blocked.json<{ error: { code: string; details: { retryAfterSeconds: number } } }>();
    expect(body.error.code).toBe('RATE_LIMITED');
    expect(body.error.details.retryAfterSeconds).toBeGreaterThan(0);
    expect(Number(blocked.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('keys an authenticated request by principal, not IP', async () => {
    const ip = freshIp();
    const user = randomUUID();
    for (let i = 0; i < 5; i += 1) {
      const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/as-user', remoteAddress: ip, headers: { 'x-test-user': user } });
      expect(res.statusCode).toBe(200);
    }
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/_test/as-user', remoteAddress: ip, headers: { 'x-test-user': user } })).statusCode).toBe(429);
    // Same IP, different user: not affected.
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/_test/as-user', remoteAddress: ip, headers: { 'x-test-user': randomUUID() } })).statusCode).toBe(200);
  });

  it('a per-route override replaces the global tier for that route only', async () => {
    const ip = freshIp();
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/_test/strict', remoteAddress: ip })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/_test/strict', remoteAddress: ip })).statusCode).toBe(429);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip })).statusCode).toBe(200);
  });

  it('counters survive an app restart because they live in the database', async () => {
    const ip = freshIp();
    for (let i = 0; i < 3; i += 1) {
      await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip });
    }
    const second = await buildTestApp({ anonPerMinute: 3, routes: (app) => { app.get('/v1/_test/open', async () => ({ data: 'open' })); } });
    try {
      expect((await second.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip })).statusCode).toBe(429);
    } finally {
      await second.app.close();
      await second.prisma.$disconnect();
    }
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/rate-limit.test.ts`
Expected: FAIL — `request.principal` type error / every request returns 200.

- [ ] **Step 3: Declare `request.principal` and write the plugin**

Create `backend/src/core/principal.ts`:

```ts
/**
 * Who is making the request. Phase 2 knows one kind — an admin session. Phase 3
 * adds `user`. Set by an onRequest plugin; read by guards, the rate limiter and
 * the idempotency middleware. A principal existing does not mean it may act:
 * the guards decide that.
 */
export interface AdminPrincipal {
  kind: 'admin';
  id: string;
  sessionId: string;
  mfaVerified: boolean;
  totpEnrolled: boolean;
  reauthenticatedAt: Date | null;
}

export type Principal = AdminPrincipal;

declare module 'fastify' {
  interface FastifyRequest {
    principal?: Principal;
    /** Why a presented session was rejected — the guard turns this into the error code. */
    sessionRejection?: 'SESSION_EXPIRED' | 'UNAUTHENTICATED';
  }
}
```

`backend/src/plugins/rate-limit.ts`:

```ts
import rateLimit, { type FastifyRateLimitStore, type FastifyRateLimitStoreCtor } from '@fastify/rate-limit';
import type { FastifyInstance, FastifyRequest, RouteOptions } from 'fastify';

import { RateLimitedError } from '../core/errors.js';
import type { PrismaClient } from '../generated/prisma/client.js';

interface CounterRow {
  count: number;
  window_started_at: Date;
}

/**
 * Rate-limit counters in PostgreSQL (decision: no Redis, no per-process
 * memory). One atomic upsert per counted request; the row for a (scope,
 * subject) is reused across windows and never deleted. See the UNLOGGED note
 * on the model.
 */
function createPostgresStore(prisma: PrismaClient, scope: string): FastifyRateLimitStoreCtor {
  return class PostgresRateLimitStore implements FastifyRateLimitStore {
    incr(
      key: string,
      callback: (error: Error | null, result?: { current: number; ttl: number }) => void,
      timeWindow: number,
    ): void {
      const fullKey = `${scope}|${key}`;
      const windowSeconds = timeWindow / 1000;
      prisma
        .$queryRaw<CounterRow[]>`
          INSERT INTO rate_limit_counter (key, count, window_started_at)
          VALUES (${fullKey}, 1, now())
          ON CONFLICT (key) DO UPDATE SET
            count = CASE
              WHEN rate_limit_counter.window_started_at + make_interval(secs => ${windowSeconds}) <= now() THEN 1
              ELSE rate_limit_counter.count + 1 END,
            window_started_at = CASE
              WHEN rate_limit_counter.window_started_at + make_interval(secs => ${windowSeconds}) <= now() THEN now()
              ELSE rate_limit_counter.window_started_at END
          RETURNING count, window_started_at`
        .then((rows) => {
          const row = rows[0];
          if (row === undefined) {
            callback(new Error('rate limit upsert returned no row'));
            return;
          }
          const elapsed = Date.now() - row.window_started_at.getTime();
          callback(null, { current: row.count, ttl: Math.max(timeWindow - elapsed, 1) });
        })
        .catch((error: unknown) => {
          callback(error instanceof Error ? error : new Error(String(error)));
        });
    }

    child(routeOptions: RouteOptions & { path: string; prefix: string }): FastifyRateLimitStore {
      const Store = createPostgresStore(prisma, `${String(routeOptions.method)} ${routeOptions.prefix}${routeOptions.path}`);
      return new Store({});
    }
  };
}

function subjectKey(request: FastifyRequest): string {
  return request.principal ? `u:${request.principal.id}` : `ip:${request.ip}`;
}

/**
 * Global tiers (plan §Phase 2): anonymous per IP, authenticated per principal.
 * A route's `config.rateLimit` replaces the global tier for that route — that
 * is the per-endpoint override mechanism the plan asks for.
 */
export async function registerRateLimit(app: FastifyInstance): Promise<void> {
  const { anonPerMinute, authPerMinute } = app.config.rateLimit;
  await app.register(rateLimit, {
    global: true,
    store: createPostgresStore(app.deps.prisma, 'global'),
    keyGenerator: subjectKey,
    max: (request: FastifyRequest) => (request.principal ? authPerMinute : anonPerMinute),
    timeWindow: '1 minute',
    // A store failure must not take the API down with it; it fails open and logs.
    skipOnError: true,
    addHeadersOnExceeding: { 'x-ratelimit-limit': true, 'x-ratelimit-remaining': true, 'x-ratelimit-reset': true },
    addHeaders: { 'x-ratelimit-limit': true, 'x-ratelimit-remaining': true, 'x-ratelimit-reset': true, 'retry-after': true },
    errorResponseBuilder: (_request, context) => new RateLimitedError(Math.max(Math.ceil(context.ttl / 1000), 1)),
  });
}
```

In `app.ts`: `import './core/principal.js';` (for the module augmentation) and, after `registerErrorHandling(app);` and before `registerHealthRoutes(app);`, add `await registerRateLimit(app);`. The plugin must be registered before any route so its `onRoute` hook sees them all.

- [ ] **Step 4: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run test/rate-limit.test.ts && npm run lint && npm run typecheck`
Expected: 4 pass. If the 429 body is not our envelope, confirm the thrown `RateLimitedError` reaches `setErrorHandler` (it does when `errorResponseBuilder` returns an `Error` instance; the plugin throws what the builder returns).

- [ ] **Step 5: Commit**

```bash
git add backend/src/plugins/rate-limit.ts backend/src/core/principal.ts backend/src/app.ts backend/test/rate-limit.test.ts
git commit -m "Phase 2 — rate limiting: global tiers per IP and per principal, route overrides, counters in Postgres"
```

---

### Task 6: Idempotency middleware

**Files:**
- Create: `backend/src/core/canonical-json.ts`, `backend/src/plugins/idempotency.ts`
- Modify: `backend/src/app.ts`
- Test: `backend/test/idempotency.test.ts`

**Interfaces:**
- Produces: `registerIdempotency(app)`; routes opt in with `config: { idempotency: { operation: 'domain.verb' } }`; header `Idempotency-Key`; response header `Idempotent-Replayed: true` on a replay. `canonicalJson(value): string`.

- [ ] **Step 1: Write the failing test**

`backend/test/idempotency.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { buildTestApp, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('idempotency middleware', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  let handlerRuns = 0;

  beforeAll(async () => {
    ctx = await buildTestApp({
      routes: (app) => {
        app.post(
          '/v1/_test/create',
          {
            config: { idempotency: { operation: 'test.create' } },
            schema: { body: z.object({ name: z.string() }) },
            onRequest: async (request) => {
              request.principal = { kind: 'admin', id: String(request.headers['x-test-user'] ?? 'anon-user'), sessionId: '', mfaVerified: true, totpEnrolled: true, reauthenticatedAt: null };
            },
          },
          async (request, reply) => {
            handlerRuns += 1;
            await new Promise((r) => setTimeout(r, 25));
            return reply.code(201).send({ data: { id: randomUUID(), name: request.body.name, run: handlerRuns } });
          },
        );
        app.post(
          '/v1/_test/fails',
          { config: { idempotency: { operation: 'test.fails' } } },
          async () => {
            throw new Error('boom');
          },
        );
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const post = (key: string | undefined, body: unknown, user = randomUUID()) =>
    ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/create',
      payload: body,
      headers: { 'x-test-user': user, ...(key === undefined ? {} : { 'idempotency-key': key }) },
    });

  it('requires the header on an opted-in route', async () => {
    const res = await post(undefined, { name: 'a' });
    expect(res.statusCode).toBe(400);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');
  });

  it('replays the original status and body on a repeat', async () => {
    const key = randomUUID();
    const user = randomUUID();
    const before = handlerRuns;
    const first = await post(key, { name: 'a' }, user);
    const second = await post(key, { name: 'a' }, user);
    expect(first.statusCode).toBe(201);
    expect(second.statusCode).toBe(201);
    expect(second.body).toBe(first.body);
    expect(second.headers['idempotent-replayed']).toBe('true');
    expect(first.headers['idempotent-replayed']).toBeUndefined();
    expect(handlerRuns).toBe(before + 1);
  });

  it('rejects the same key with a different body', async () => {
    const key = randomUUID();
    const user = randomUUID();
    await post(key, { name: 'a' }, user);
    const res = await post(key, { name: 'b' }, user);
    expect(res.statusCode).toBe(422);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('IDEMPOTENCY_KEY_REUSED');
  });

  it('scopes the key to the subject: two users may use the same key', async () => {
    const key = randomUUID();
    const before = handlerRuns;
    await post(key, { name: 'a' }, randomUUID());
    await post(key, { name: 'a' }, randomUUID());
    expect(handlerRuns).toBe(before + 2);
  });

  it('runs the handler once under concurrent duplicates', async () => {
    const key = randomUUID();
    const user = randomUUID();
    const before = handlerRuns;
    const results = await Promise.all(Array.from({ length: 20 }, () => post(key, { name: 'c' }, user)));
    expect(handlerRuns).toBe(before + 1);
    const statuses = results.map((r) => r.statusCode);
    expect(statuses.filter((s) => s === 201).length).toBeGreaterThanOrEqual(1);
    for (const s of statuses) expect([201, 409]).toContain(s);
    const winners = results.filter((r) => r.statusCode === 201).map((r) => r.body);
    expect(new Set(winners).size).toBe(1);
  });

  it('does not pin a 5xx: a retry after a crash runs the handler again', async () => {
    const key = randomUUID();
    const first = await ctx.app.inject({ method: 'POST', url: '/v1/_test/fails', payload: {}, headers: { 'idempotency-key': key } });
    expect(first.statusCode).toBe(500);
    const record = await ctx.prisma.idempotencyRecord.findFirst({ where: { clientKey: key } });
    expect(record?.status).toBe('abandoned');
    const second = await ctx.app.inject({ method: 'POST', url: '/v1/_test/fails', payload: {}, headers: { 'idempotency-key': key } });
    expect(second.statusCode).toBe(500);
    expect(second.headers['idempotent-replayed']).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/idempotency.test.ts`
Expected: FAIL — `config.idempotency` is not a known type / no 400.

- [ ] **Step 3: Write `canonical-json.ts` and the plugin**

`backend/src/core/canonical-json.ts`:

```ts
/** JSON with object keys sorted at every depth, so equal bodies hash equal regardless of key order. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(sortKeys(value));
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      out[key] = sortKeys((value as Record<string, unknown>)[key]);
    }
    return out;
  }
  return value;
}
```

`backend/src/plugins/idempotency.ts`:

```ts
import { createHash } from 'node:crypto';

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

import { canonicalJson } from '../core/canonical-json.js';
import { BusinessRuleError, ConflictError, ValidationError } from '../core/errors.js';
import type { Prisma } from '../generated/prisma/client.js';

declare module 'fastify' {
  interface FastifyContextConfig {
    idempotency?: { operation: string };
  }
  interface FastifyRequest {
    idempotencyRecordId?: string;
  }
}

const HEADER = 'idempotency-key';

/**
 * Idempotency (plan §2, §Phase 2): keyed on (subject, operation, clientKey).
 * The first request with a key runs; a repeat with the same body replays the
 * stored response; the same key with a different body is refused. Records are
 * kept forever. The subject is the principal; before Phase 3 defines user
 * registration, an anonymous request falls back to its IP.
 */
export function registerIdempotency(app: FastifyInstance): void {
  const { prisma } = app.deps;

  app.addHook('preHandler', async (request: FastifyRequest, reply: FastifyReply) => {
    const opts = request.routeOptions.config.idempotency;
    if (opts === undefined) return;

    const header = request.headers[HEADER];
    const clientKey = Array.isArray(header) ? header[0] : header;
    if (clientKey === undefined || clientKey.length === 0 || clientKey.length > 128) {
      throw new ValidationError([{ path: 'Idempotency-Key', message: 'header required, 1–128 characters' }], 'Idempotency-Key header required');
    }

    const subject = request.principal ? request.principal.id : `anon:${request.ip}`;
    const requestHash = createHash('sha256')
      .update(`${request.method} ${request.url.split('?')[0] ?? ''}\n${canonicalJson(request.body ?? null)}`)
      .digest('hex');

    const inserted = await prisma.$queryRaw<{ id: string }[]>`
      INSERT INTO idempotency_record (id, subject, operation, client_key, request_hash, status, created_at)
      VALUES (gen_random_uuid(), ${subject}, ${opts.operation}, ${clientKey}, ${requestHash}, 'in_progress', now())
      ON CONFLICT (subject, operation, client_key) DO NOTHING
      RETURNING id`;
    const winner = inserted[0];
    if (winner !== undefined) {
      request.idempotencyRecordId = winner.id;
      return;
    }

    const existing = await prisma.idempotencyRecord.findUnique({
      where: { subject_operation_clientKey: { subject, operation: opts.operation, clientKey } },
    });
    if (existing === null) {
      throw new ConflictError('IDEMPOTENT_REQUEST_IN_PROGRESS', 'The same request is being processed');
    }
    if (existing.requestHash !== requestHash) {
      throw new BusinessRuleError('IDEMPOTENCY_KEY_REUSED', 'This Idempotency-Key was already used with a different request');
    }
    if (existing.status === 'in_progress') {
      throw new ConflictError('IDEMPOTENT_REQUEST_IN_PROGRESS', 'The same request is being processed');
    }
    if (existing.status === 'abandoned') {
      // The earlier attempt failed on our side; let this one run and take over the record.
      await prisma.idempotencyRecord.update({ where: { id: existing.id }, data: { status: 'in_progress', responseStatus: null, responseBody: null, responseHeaders: null, completedAt: null } });
      request.idempotencyRecordId = existing.id;
      return;
    }

    const headers = (existing.responseHeaders ?? {}) as Record<string, string>;
    void reply.code(existing.responseStatus ?? 200);
    for (const [name, value] of Object.entries(headers)) void reply.header(name, value);
    void reply.header('idempotent-replayed', 'true');
    return reply.send(existing.responseBody);
  });

  app.addHook('onSend', async (request, reply, payload: unknown) => {
    const id = request.idempotencyRecordId;
    if (id === undefined) return payload;
    const status = reply.statusCode;
    const transient = status >= 500 || status === 429;
    let body: Prisma.InputJsonValue | null = null;
    if (typeof payload === 'string' && payload.length > 0) {
      try {
        body = JSON.parse(payload) as Prisma.InputJsonValue;
      } catch {
        body = payload;
      }
    }
    const contentType = reply.getHeader('content-type');
    await prisma.idempotencyRecord.update({
      where: { id },
      data: transient
        ? { status: 'abandoned', completedAt: new Date() }
        : {
            status: 'completed',
            responseStatus: status,
            responseHeaders: typeof contentType === 'string' ? { 'content-type': contentType } : {},
            responseBody: body ?? undefined,
            completedAt: new Date(),
          },
    });
    return payload;
  });
}
```

In `app.ts`, after `await registerRateLimit(app);` add `registerIdempotency(app);`.

- [ ] **Step 4: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run test/idempotency.test.ts && npm run lint && npm run typecheck`
Expected: 6 pass. If Prisma's generated compound-unique input is not named `subject_operation_clientKey`, open `src/generated/prisma/models/IdempotencyRecord.ts` and use the name it generated.

- [ ] **Step 5: Commit**

```bash
git add backend/src/core/canonical-json.ts backend/src/plugins/idempotency.ts backend/src/app.ts backend/test/idempotency.test.ts
git commit -m "Phase 2 — idempotency middleware keyed on subject, operation and Idempotency-Key, replaying the original result"
```

---

### Task 7: Audit log service

**Files:**
- Create: `backend/src/modules/audit/types.ts`, `backend/src/modules/audit/service.ts`
- Test: `backend/test/audit.test.ts`

**Interfaces:**
- Produces:
  ```ts
  type Db = PrismaClient | Prisma.TransactionClient;
  interface AuditEntryInput { actorType: 'admin' | 'system'; actorId?: string | null; action: string; targetType: string; targetId: string; reason: string; metadata?: Record<string, string | number | boolean | null>; requestId?: string | null; ipAddress?: string | null }
  interface AuditQuery { from?: Date; to?: Date; actorId?: string; action?: string; cursor?: string; limit: number }
  class AuditService { constructor(prisma: PrismaClient, clock: Clock); record(db: Db, entry: AuditEntryInput): Promise<AuditLogEntry>; query(q: AuditQuery): Promise<{ items: AuditLogEntry[]; nextCursor: string | null }> }
  ```

- [ ] **Step 1: Write the failing test**

`backend/test/audit.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { AuditService } from '../src/modules/audit/service.js';
import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { controllableClock, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('AuditService', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('records inside the caller transaction and rolls back with it', async () => {
    const time = controllableClock(new Date('2026-09-06T08:00:00Z'));
    const audit = new AuditService(prisma, time.clock);
    const actorId = randomUUID();
    await expect(
      prisma.$transaction(async (tx) => {
        await audit.record(tx, { actorType: 'admin', actorId, action: 'test.rolled_back', targetType: 'thing', targetId: randomUUID(), reason: 'testing' });
        throw new Error('abort');
      }),
    ).rejects.toThrow('abort');
    expect(await prisma.auditLogEntry.count({ where: { actorId } })).toBe(0);
  });

  it('refuses an empty reason', async () => {
    const audit = new AuditService(prisma, () => new Date());
    await expect(
      audit.record(prisma, { actorType: 'system', action: 'x', targetType: 'y', targetId: 'z', reason: '   ' }),
    ).rejects.toThrow(/reason/);
  });

  it('queries by date, actor and action with a stable cursor', async () => {
    const time = controllableClock(new Date('2026-09-06T08:00:00Z'));
    const audit = new AuditService(prisma, time.clock);
    const actorId = randomUUID();
    const action = `test.${randomUUID()}`;
    for (let i = 0; i < 5; i += 1) {
      await audit.record(prisma, { actorType: 'admin', actorId, action, targetType: 't', targetId: String(i), reason: 'r' });
      time.advance(60_000);
    }
    await audit.record(prisma, { actorType: 'admin', actorId, action: 'other', targetType: 't', targetId: 'x', reason: 'r' });

    const byAction = await audit.query({ action, limit: 10 });
    expect(byAction.items.map((e) => e.targetId)).toEqual(['4', '3', '2', '1', '0']);

    const page1 = await audit.query({ actorId, limit: 4 });
    expect(page1.items).toHaveLength(4);
    expect(page1.nextCursor).not.toBeNull();
    const page2 = await audit.query({ actorId, limit: 4, cursor: page1.nextCursor ?? undefined });
    expect(page2.items).toHaveLength(2);
    expect(page2.nextCursor).toBeNull();

    const window = await audit.query({ actorId, from: new Date('2026-09-06T08:01:30Z'), to: new Date('2026-09-06T08:03:30Z'), limit: 10 });
    expect(window.items.map((e) => e.targetId)).toEqual(['3', '2']);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/audit.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the service**

`backend/src/modules/audit/types.ts`:

```ts
import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';

export type Db = PrismaClient | Prisma.TransactionClient;

export interface AuditEntryInput {
  actorType: 'admin' | 'system';
  actorId?: string | null;
  /** Dotted, stable, e.g. `admin.session.revoked`. */
  action: string;
  targetType: string;
  targetId: string;
  /** Required by the plan: every admin action records why. */
  reason: string;
  /** IDs, enums and counts only — never an email, phone, or document content. */
  metadata?: Record<string, string | number | boolean | null>;
  requestId?: string | null;
  ipAddress?: string | null;
}

export interface AuditQuery {
  from?: Date;
  to?: Date;
  actorId?: string;
  action?: string;
  cursor?: string;
  limit: number;
}
```

`backend/src/modules/audit/service.ts`:

```ts
import type { Clock } from '../../core/clock.js';
import { ValidationError } from '../../core/errors.js';
import type { AuditLogEntry, PrismaClient } from '../../generated/prisma/client.js';
import type { AuditEntryInput, AuditQuery, Db } from './types.js';

/**
 * The audit log (plan §Phase 2): append-only, every admin action with actor,
 * time, action, target and reason; queryable by date, admin and action.
 * `record` takes the caller's transaction so the entry commits with the action.
 */
export class AuditService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  async record(db: Db, entry: AuditEntryInput): Promise<AuditLogEntry> {
    if (entry.reason.trim().length === 0) {
      throw new ValidationError([{ path: 'reason', message: 'A reason is required' }]);
    }
    return db.auditLogEntry.create({
      data: {
        actorType: entry.actorType,
        actorId: entry.actorId ?? null,
        action: entry.action,
        targetType: entry.targetType,
        targetId: entry.targetId,
        reason: entry.reason.trim(),
        metadata: entry.metadata ?? undefined,
        requestId: entry.requestId ?? null,
        ipAddress: entry.ipAddress ?? null,
        createdAt: this.clock(),
      },
    });
  }

  async query(q: AuditQuery): Promise<{ items: AuditLogEntry[]; nextCursor: string | null }> {
    const cursor = q.cursor === undefined ? null : decodeCursor(q.cursor);
    const items = await this.prisma.auditLogEntry.findMany({
      where: {
        AND: [
          q.actorId === undefined ? {} : { actorId: q.actorId },
          q.action === undefined ? {} : { action: q.action },
          q.from === undefined ? {} : { createdAt: { gte: q.from } },
          q.to === undefined ? {} : { createdAt: { lte: q.to } },
          cursor === null
            ? {}
            : { OR: [{ createdAt: { lt: cursor.createdAt } }, { createdAt: cursor.createdAt, id: { lt: cursor.id } }] },
        ],
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: q.limit + 1,
    });
    const page = items.slice(0, q.limit);
    const last = page[page.length - 1];
    const nextCursor = items.length > q.limit && last !== undefined ? encodeCursor(last) : null;
    return { items: page, nextCursor };
  }
}

function encodeCursor(entry: { createdAt: Date; id: string }): string {
  return Buffer.from(`${entry.createdAt.toISOString()}|${entry.id}`).toString('base64url');
}

function decodeCursor(cursor: string): { createdAt: Date; id: string } {
  const [iso, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  const createdAt = new Date(iso ?? '');
  if (id === undefined || Number.isNaN(createdAt.getTime())) {
    throw new ValidationError([{ path: 'cursor', message: 'Malformed cursor' }]);
  }
  return { createdAt, id };
}
```

- [ ] **Step 4: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run test/audit.test.ts && npm run lint && npm run typecheck`
Expected: 3 pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/audit backend/test/audit.test.ts
git commit -m "Phase 2 — append-only audit log service with date, actor and action queries"
```

---

### Task 8: Admin identity — crypto helpers, repository, login and session service

**Files:**
- Create: `backend/src/modules/admin-auth/crypto.ts`, `backend/src/modules/admin-auth/repository.ts`, `backend/src/modules/admin-auth/service.ts`
- Test: `backend/test/admin-auth-crypto.test.ts`, `backend/test/admin-auth-service.test.ts`

**Interfaces:**
- Produces (`crypto.ts`): `hashPassword(p): Promise<string>`, `verifyPassword(hash, p): Promise<boolean>`, `DUMMY_PASSWORD_HASH: string`, `newSessionToken(): string` (43-char base64url), `hashToken(t): string` (sha256 hex), `encryptSecret(plain, key: Buffer): string`, `decryptSecret(cipher, key): string`, `newRecoveryCodes(): string[]` (10 × `xxxxx-xxxxx`), `MIN_PASSWORD_LENGTH = 12`, `MAX_PASSWORD_LENGTH = 512`.
- Produces (`service.ts`):
  ```ts
  interface RequestMeta { ip: string; userAgent: string; requestId: string }
  interface LoginResult { token: string; session: AdminSession; state: 'mfa_required' | 'mfa_enrolment_required' }
  class AdminAuthService {
    constructor(deps: { prisma: PrismaClient; audit: AuditService; clock: Clock; config: Config })
    createAdmin(email: string, password: string, meta: { requestId?: string }): Promise<AdminUser>     // used by the CLI
    login(email: string, password: string, meta: RequestMeta): Promise<LoginResult>
    resolveSession(token: string): Promise<{ principal: AdminPrincipal } | { rejection: 'SESSION_EXPIRED' | 'UNAUTHENTICATED' }>
    logout(sessionId: string, adminId: string, meta: RequestMeta): Promise<void>
    listSessions(adminId: string): Promise<AdminSession[]>
    revokeSession(adminId: string, sessionId: string, reason: string, meta: RequestMeta): Promise<void>
  }
  ```
  (Task 10 adds the MFA methods to the same class.)

- [ ] **Step 1: Write the failing crypto test**

`backend/test/admin-auth-crypto.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { decryptSecret, encryptSecret, hashPassword, hashToken, newRecoveryCodes, newSessionToken, verifyPassword } from '../src/modules/admin-auth/crypto.js';

describe('admin-auth crypto', () => {
  it('hashes with argon2id and verifies', async () => {
    const hash = await hashPassword('correct horse battery staple');
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(await verifyPassword(hash, 'correct horse battery staple')).toBe(true);
    expect(await verifyPassword(hash, 'wrong')).toBe(false);
  });

  it('session tokens are unique and their hash is what gets stored', () => {
    const a = newSessionToken();
    const b = newSessionToken();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(hashToken(a)).toMatch(/^[0-9a-f]{64}$/);
    expect(hashToken(a)).not.toContain(a);
  });

  it('encrypts a TOTP secret so the ciphertext differs each time and decrypts back', () => {
    const key = Buffer.alloc(32, 9);
    const c1 = encryptSecret('JBSWY3DPEHPK3PXP', key);
    const c2 = encryptSecret('JBSWY3DPEHPK3PXP', key);
    expect(c1).not.toBe(c2);
    expect(c1).not.toContain('JBSWY3DPEHPK3PXP');
    expect(decryptSecret(c1, key)).toBe('JBSWY3DPEHPK3PXP');
    expect(() => decryptSecret(c1, Buffer.alloc(32, 8))).toThrow();
  });

  it('issues ten distinct recovery codes in xxxxx-xxxxx form', () => {
    const codes = newRecoveryCodes();
    expect(codes).toHaveLength(10);
    expect(new Set(codes).size).toBe(10);
    for (const code of codes) expect(code).toMatch(/^[a-z0-9]{5}-[a-z0-9]{5}$/);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/admin-auth-crypto.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `crypto.ts`**

```ts
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

import { hash, hashSync, verify } from '@node-rs/argon2';

export const MIN_PASSWORD_LENGTH = 12;
export const MAX_PASSWORD_LENGTH = 512;

export function hashPassword(password: string): Promise<string> {
  return hash(password); // argon2id, library defaults
}

export function verifyPassword(passwordHash: string, password: string): Promise<boolean> {
  return verify(passwordHash, password).catch(() => false);
}

/** Verified against when the email is unknown, so timing does not reveal whether an account exists. */
export const DUMMY_PASSWORD_HASH = hashSync(randomBytes(32).toString('hex'));

export function newSessionToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** AES-256-GCM; output is base64url(iv ‖ tag ‖ ciphertext). */
export function encryptSecret(plain: string, key: Buffer): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]).toString('base64url');
}

export function decryptSecret(encoded: string, key: Buffer): string {
  const raw = Buffer.from(encoded, 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', key, raw.subarray(0, 12));
  decipher.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString('utf8');
}

const RECOVERY_ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789'; // no 0/o/1/l/i

export function newRecoveryCodes(count = 10): string[] {
  const codes = new Set<string>();
  while (codes.size < count) {
    const bytes = randomBytes(10);
    let s = '';
    for (const b of bytes) s += RECOVERY_ALPHABET[b % RECOVERY_ALPHABET.length];
    codes.add(`${s.slice(0, 5)}-${s.slice(5)}`);
  }
  return [...codes];
}

export function normaliseRecoveryCode(input: string): string {
  return input.trim().toLowerCase();
}
```

- [ ] **Step 4: Run the crypto test**

Run: `cd backend && npx vitest run test/admin-auth-crypto.test.ts`
Expected: 4 pass.

- [ ] **Step 5: Write the failing service test**

`backend/test/admin-auth-service.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { AdminAuthService } from '../src/modules/admin-auth/service.js';
import { AuditService } from '../src/modules/audit/service.js';
import { controllableClock, databaseUrl, testConfig } from './helpers/app.js';

const meta = { ip: '10.9.9.9', userAgent: 'vitest', requestId: randomUUID() };
const PASSWORD = 'a long enough password';

describe.skipIf(databaseUrl === undefined)('AdminAuthService — accounts and sessions', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  function build(options: { sessionIdleMinutes?: number; sessionAbsoluteHours?: number } = {}) {
    const time = controllableClock(new Date('2026-09-06T09:00:00Z'));
    const config = testConfig(options);
    const audit = new AuditService(prisma, time.clock);
    const service = new AdminAuthService({ prisma, audit, clock: time.clock, config });
    return { time, service, audit };
  }

  it('creates an admin with a lower-cased email, refuses short passwords and duplicates, and audits creation', async () => {
    const { service } = build();
    const email = `Admin-${randomUUID()}@Example.test`;
    await expect(service.createAdmin(email, 'short', {})).rejects.toMatchObject({ code: 'PASSWORD_TOO_SHORT' });
    const admin = await service.createAdmin(email, PASSWORD, {});
    expect(admin.email).toBe(email.toLowerCase());
    expect(admin.totpEnrolledAt).toBeNull();
    await expect(service.createAdmin(email.toLowerCase(), PASSWORD, {})).rejects.toMatchObject({ code: 'CONFLICT' });
    const entry = await prisma.auditLogEntry.findFirst({ where: { action: 'admin.created', targetId: admin.id } });
    expect(entry?.actorType).toBe('system');
  });

  it('login yields a session in the enrolment-required state for a new admin, and INVALID_CREDENTIALS otherwise', async () => {
    const { service } = build();
    const email = `admin-${randomUUID()}@example.test`;
    await service.createAdmin(email, PASSWORD, {});
    const result = await service.login(email, PASSWORD, meta);
    expect(result.state).toBe('mfa_enrolment_required');
    expect(result.session.mfaVerifiedAt).toBeNull();
    await expect(service.login(email, 'wrong password!!', meta)).rejects.toMatchObject({ code: 'INVALID_CREDENTIALS' });
    await expect(service.login(`nobody-${randomUUID()}@example.test`, PASSWORD, meta)).rejects.toMatchObject({ code: 'INVALID_CREDENTIALS' });
    const failed = await prisma.auditLogEntry.count({ where: { action: 'admin.login.failed', targetId: result.session.adminId } });
    expect(failed).toBe(1);
  });

  it('a disabled admin cannot log in', async () => {
    const { service } = build();
    const email = `admin-${randomUUID()}@example.test`;
    const admin = await service.createAdmin(email, PASSWORD, {});
    await prisma.adminUser.update({ where: { id: admin.id }, data: { status: 'disabled' } });
    await expect(service.login(email, PASSWORD, meta)).rejects.toMatchObject({ code: 'INVALID_CREDENTIALS' });
  });

  it('resolveSession slides the idle clock, expires at idle, and never slides the absolute expiry', async () => {
    const { service, time } = build({ sessionIdleMinutes: 15, sessionAbsoluteHours: 12 });
    const email = `admin-${randomUUID()}@example.test`;
    await service.createAdmin(email, PASSWORD, {});
    const { token } = await service.login(email, PASSWORD, meta);

    time.advance(14 * 60_000);
    expect(await service.resolveSession(token)).toHaveProperty('principal');
    time.advance(14 * 60_000); // 28 min since login, 14 since last seen — still live
    expect(await service.resolveSession(token)).toHaveProperty('principal');
    time.advance(15 * 60_000 + 1);
    expect(await service.resolveSession(token)).toEqual({ rejection: 'SESSION_EXPIRED' });
    expect(await service.resolveSession(token)).toEqual({ rejection: 'SESSION_EXPIRED' });

    const second = await service.login(email, PASSWORD, meta);
    for (let i = 0; i < 12 * 6; i += 1) {
      time.advance(10 * 60_000);
      const r = await service.resolveSession(second.token);
      if (i < 12 * 6 - 1) expect(r).toHaveProperty('principal');
      else expect(r).toEqual({ rejection: 'SESSION_EXPIRED' });
    }
    const row = await prisma.adminSession.findUnique({ where: { id: second.session.id } });
    expect(row?.revokedReason).toBe('absolute_expiry');
  });

  it('rejects an unknown token and a revoked session; revocation touches only the named session', async () => {
    const { service } = build();
    const email = `admin-${randomUUID()}@example.test`;
    const admin = await service.createAdmin(email, PASSWORD, {});
    const a = await service.login(email, PASSWORD, meta);
    const b = await service.login(email, PASSWORD, meta);
    expect(await service.resolveSession('not-a-token')).toEqual({ rejection: 'UNAUTHENTICATED' });

    expect((await service.listSessions(admin.id)).map((s) => s.id).sort()).toEqual([a.session.id, b.session.id].sort());
    await service.revokeSession(admin.id, a.session.id, 'lost laptop', meta);
    expect(await service.resolveSession(a.token)).toEqual({ rejection: 'UNAUTHENTICATED' });
    expect(await service.resolveSession(b.token)).toHaveProperty('principal');
    expect((await service.listSessions(admin.id)).map((s) => s.id)).toEqual([b.session.id]);

    await expect(service.revokeSession(randomUUID(), b.session.id, 'not mine', meta)).rejects.toMatchObject({ code: 'NOT_FOUND' });
    const audit = await prisma.auditLogEntry.findFirst({ where: { action: 'admin.session.revoked', targetId: a.session.id } });
    expect(audit?.reason).toBe('lost laptop');
  });
});
```

- [ ] **Step 6: Run it to verify it fails**

Run: `cd backend && npx vitest run test/admin-auth-service.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 7: Write the repository and the service**

`backend/src/modules/admin-auth/repository.ts`:

```ts
import type { AdminSession, AdminUser, PrismaClient, SessionRevokedReason } from '../../generated/prisma/client.js';
import type { Db } from '../audit/types.js';

/** Data access for admin identity. No rules here — the service owns them. */
export class AdminRepository {
  constructor(private readonly prisma: PrismaClient) {}

  findByEmail(email: string): Promise<AdminUser | null> {
    return this.prisma.adminUser.findUnique({ where: { email } });
  }

  findById(id: string): Promise<AdminUser | null> {
    return this.prisma.adminUser.findUnique({ where: { id } });
  }

  create(db: Db, data: { email: string; passwordHash: string; createdAt: Date }): Promise<AdminUser> {
    return db.adminUser.create({ data: { ...data, passwordChangedAt: data.createdAt } });
  }

  createSession(
    db: Db,
    data: { adminId: string; tokenHash: string; now: Date; expiresAt: Date; ipAddress: string; userAgent: string },
  ): Promise<AdminSession> {
    return db.adminSession.create({
      data: {
        adminId: data.adminId,
        tokenHash: data.tokenHash,
        createdAt: data.now,
        lastSeenAt: data.now,
        expiresAt: data.expiresAt,
        ipAddress: data.ipAddress,
        userAgent: data.userAgent,
      },
    });
  }

  findSessionByTokenHash(tokenHash: string): Promise<(AdminSession & { admin: AdminUser }) | null> {
    return this.prisma.adminSession.findUnique({ where: { tokenHash }, include: { admin: true } });
  }

  findSession(adminId: string, sessionId: string): Promise<AdminSession | null> {
    return this.prisma.adminSession.findFirst({ where: { id: sessionId, adminId, revokedAt: null } });
  }

  listActiveSessions(adminId: string, now: Date): Promise<AdminSession[]> {
    return this.prisma.adminSession.findMany({
      where: { adminId, revokedAt: null, expiresAt: { gt: now } },
      orderBy: { lastSeenAt: 'desc' },
    });
  }

  touchSession(sessionId: string, now: Date): Promise<AdminSession> {
    return this.prisma.adminSession.update({ where: { id: sessionId }, data: { lastSeenAt: now } });
  }

  revokeSession(db: Db, sessionId: string, now: Date, reason: SessionRevokedReason): Promise<AdminSession> {
    return db.adminSession.update({ where: { id: sessionId }, data: { revokedAt: now, revokedReason: reason } });
  }
}
```

`backend/src/modules/admin-auth/service.ts` (Task 10 appends the MFA methods):

```ts
import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import { AuthenticationError, BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { AdminPrincipal } from '../../core/principal.js';
import type { AdminSession, AdminUser, PrismaClient } from '../../generated/prisma/client.js';
import type { AuditService } from '../audit/service.js';
import {
  DUMMY_PASSWORD_HASH,
  hashPassword,
  hashToken,
  MAX_PASSWORD_LENGTH,
  MIN_PASSWORD_LENGTH,
  newSessionToken,
  verifyPassword,
} from './crypto.js';
import { AdminRepository } from './repository.js';

export interface RequestMeta {
  ip: string;
  userAgent: string;
  requestId: string;
}

export type LoginState = 'mfa_required' | 'mfa_enrolment_required';

export interface LoginResult {
  token: string;
  session: AdminSession;
  state: LoginState;
}

export type SessionResolution = { principal: AdminPrincipal } | { rejection: 'SESSION_EXPIRED' | 'UNAUTHENTICATED' };

/**
 * Admin identity (plan §Phase 2): one `admin` role, password + mandatory TOTP,
 * server-side sessions with idle and absolute expiry, force-logout, re-auth.
 * Every action that changes state writes an audit entry in the same
 * transaction.
 */
export class AdminAuthService {
  private readonly prisma: PrismaClient;
  private readonly audit: AuditService;
  private readonly clock: Clock;
  private readonly config: Config;
  private readonly repo: AdminRepository;

  constructor(deps: { prisma: PrismaClient; audit: AuditService; clock: Clock; config: Config }) {
    this.prisma = deps.prisma;
    this.audit = deps.audit;
    this.clock = deps.clock;
    this.config = deps.config;
    this.repo = new AdminRepository(deps.prisma);
  }

  /** Who may call: the server operator via the CLI (Task 11). There is no HTTP route for this in v1. */
  async createAdmin(emailInput: string, password: string, meta: { requestId?: string }): Promise<AdminUser> {
    const email = emailInput.trim().toLowerCase();
    assertPasswordLength(password);
    if ((await this.repo.findByEmail(email)) !== null) {
      throw new ConflictError('CONFLICT', 'An admin with this email already exists');
    }
    const passwordHash = await hashPassword(password);
    const now = this.clock();
    return this.prisma.$transaction(async (tx) => {
      const admin = await this.repo.create(tx, { email, passwordHash, createdAt: now });
      await this.audit.record(tx, {
        actorType: 'system',
        action: 'admin.created',
        targetType: 'admin_user',
        targetId: admin.id,
        reason: 'created from the server CLI',
        requestId: meta.requestId ?? null,
      });
      return admin;
    });
  }

  async login(emailInput: string, password: string, meta: RequestMeta): Promise<LoginResult> {
    const email = emailInput.trim().toLowerCase();
    const admin = await this.repo.findByEmail(email);
    // Always run one argon2 verification so an unknown email costs the same time as a wrong password.
    const passwordOk = await verifyPassword(admin?.passwordHash ?? DUMMY_PASSWORD_HASH, password);
    if (admin === null) {
      throw new AuthenticationError('INVALID_CREDENTIALS', 'Email or password is incorrect');
    }
    if (!passwordOk || admin.status !== 'active') {
      await this.audit.record(this.prisma, {
        actorType: 'system',
        action: 'admin.login.failed',
        targetType: 'admin_user',
        targetId: admin.id,
        reason: admin.status !== 'active' ? 'account_disabled' : 'wrong_password',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      throw new AuthenticationError('INVALID_CREDENTIALS', 'Email or password is incorrect');
    }

    const now = this.clock();
    const token = newSessionToken();
    const expiresAt = new Date(now.getTime() + this.config.admin.sessionAbsoluteHours * 3_600_000);
    const session = await this.prisma.$transaction(async (tx) => {
      const created = await this.repo.createSession(tx, {
        adminId: admin.id,
        tokenHash: hashToken(token),
        now,
        expiresAt,
        ipAddress: meta.ip,
        userAgent: meta.userAgent.slice(0, 512),
      });
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: admin.id,
        action: 'admin.login.succeeded',
        targetType: 'admin_session',
        targetId: created.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      return created;
    });
    return { token, session, state: admin.totpEnrolledAt === null ? 'mfa_enrolment_required' : 'mfa_required' };
  }

  /**
   * Turns a cookie token into a principal. Idle expiry slides on every call;
   * absolute expiry never moves. An expired session is revoked here so the
   * reason is recorded once, on the request that found it.
   */
  async resolveSession(token: string): Promise<SessionResolution> {
    if (token.length === 0) return { rejection: 'UNAUTHENTICATED' };
    const session = await this.repo.findSessionByTokenHash(hashToken(token));
    if (session === null || session.revokedAt !== null || session.admin.status !== 'active') {
      return { rejection: 'UNAUTHENTICATED' };
    }
    const now = this.clock();
    const idleLimit = session.lastSeenAt.getTime() + this.config.admin.sessionIdleMinutes * 60_000;
    if (session.expiresAt.getTime() <= now.getTime()) {
      await this.repo.revokeSession(this.prisma, session.id, now, 'absolute_expiry');
      return { rejection: 'SESSION_EXPIRED' };
    }
    if (idleLimit < now.getTime()) {
      await this.repo.revokeSession(this.prisma, session.id, now, 'idle_timeout');
      return { rejection: 'SESSION_EXPIRED' };
    }
    await this.repo.touchSession(session.id, now);
    return {
      principal: {
        kind: 'admin',
        id: session.adminId,
        sessionId: session.id,
        mfaVerified: session.mfaVerifiedAt !== null,
        totpEnrolled: session.admin.totpEnrolledAt !== null,
        reauthenticatedAt: session.reauthenticatedAt,
      },
    };
  }

  async logout(sessionId: string, adminId: string, meta: RequestMeta): Promise<void> {
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, sessionId, now, 'logout');
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'admin.logout',
        targetType: 'admin_session',
        targetId: sessionId,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  listSessions(adminId: string): Promise<AdminSession[]> {
    return this.repo.listActiveSessions(adminId, this.clock());
  }

  /** Who may call: the admin who owns the session. Another admin's session id is reported as not found, not forbidden. */
  async revokeSession(adminId: string, sessionId: string, reason: string, meta: RequestMeta): Promise<void> {
    const session = await this.repo.findSession(adminId, sessionId);
    if (session === null) throw new NotFoundError('No such active session');
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, sessionId, now, 'force_logout');
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'admin.session.revoked',
        targetType: 'admin_session',
        targetId: sessionId,
        reason,
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }
}

export function assertPasswordLength(password: string): void {
  if (password.length < MIN_PASSWORD_LENGTH) {
    throw new BusinessRuleError('PASSWORD_TOO_SHORT', `Password must be at least ${String(MIN_PASSWORD_LENGTH)} characters`);
  }
  if (password.length > MAX_PASSWORD_LENGTH) {
    throw new BusinessRuleError('PASSWORD_TOO_LONG', `Password must be at most ${String(MAX_PASSWORD_LENGTH)} characters`);
  }
}
```

- [ ] **Step 8: Run both tests, lint, typecheck**

Run: `cd backend && npx vitest run test/admin-auth-crypto.test.ts test/admin-auth-service.test.ts && npm run lint && npm run typecheck`
Expected: 9 pass.

- [ ] **Step 9: Commit**

```bash
git add backend/src/modules/admin-auth backend/test/admin-auth-crypto.test.ts backend/test/admin-auth-service.test.ts
git commit -m "Phase 2 — admin accounts, argon2id passwords, and sessions with idle and absolute expiry"
```

---

### Task 9: Admin session plugin, guards, CSRF/CORS, and the login/session routes

**Files:**
- Create: `backend/src/plugins/admin-session.ts`, `backend/src/modules/admin-auth/guards.ts`, `backend/src/modules/admin-auth/schema.ts`, `backend/src/modules/admin-auth/routes.ts`
- Modify: `backend/src/app.ts`
- Test: `backend/test/admin-auth-routes.test.ts`

**Interfaces:**
- Consumes: `AdminAuthService` (Task 8), `AuditService` (Task 7).
- Produces:
  - `app.adminAuth: AdminAuthService`, `app.audit: AuditService` decorations (built in `buildApp`).
  - `registerAdminSession(app)` — onRequest: CSRF header check on non-GET `/v1/admin/*`; cookie → `request.principal` / `request.sessionRejection`.
  - Guards (preHandlers): `requireAdmin`, `requirePasswordSession`, `requireRecentReauth`.
  - `ADMIN_COOKIE = 'rp_admin_session'`, `CSRF_HEADER = 'x-requested-with'`, `CSRF_VALUE = 'RaajjePro-Admin'`, `cookieOptions(config)`.
  - Routes: `POST /v1/admin/auth/login`, `GET /v1/admin/auth/me`, `POST /v1/admin/auth/logout`, `GET /v1/admin/auth/sessions`, `DELETE /v1/admin/auth/sessions/:id`.

- [ ] **Step 1: Write the failing test**

`backend/test/admin-auth-routes.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl } from './helpers/app.js';

const PASSWORD = 'a long enough password';
const csrf = { 'x-requested-with': 'RaajjePro-Admin' };

function cookieFrom(res: { headers: Record<string, unknown> }): string {
  const raw = res.headers['set-cookie'];
  const first = Array.isArray(raw) ? raw[0] : raw;
  return String(first).split(';')[0] ?? '';
}

describe.skipIf(databaseUrl === undefined)('admin auth routes — login and sessions', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  let email: string;

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, sessionIdleMinutes: 15 });
    email = `admin-${randomUUID()}@example.test`;
    await ctx.app.adminAuth.createAdmin(email, PASSWORD, {});
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('refuses a mutating admin request without the CSRF header', async () => {
    const res = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', payload: { email, password: PASSWORD } });
    expect(res.statusCode).toBe(403);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('CSRF_HEADER_MISSING');
  });

  it('logs in, sets a hardened cookie, and reports the enrolment-required state', async () => {
    const res = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, payload: { email, password: PASSWORD } });
    expect(res.statusCode).toBe(200);
    expect(res.json<{ data: { state: string } }>().data.state).toBe('mfa_enrolment_required');
    const setCookie = String(res.headers['set-cookie']);
    expect(setCookie).toContain('rp_admin_session=');
    expect(setCookie).toContain('HttpOnly');
    expect(setCookie).toContain('SameSite=Strict');
    expect(setCookie).toContain('Path=/v1/admin');
    expect(res.body).not.toContain('passwordHash');
  });

  it('validates the login body and rejects wrong credentials with the same code', async () => {
    const bad = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, payload: { email: 'not-an-email' } });
    expect(bad.statusCode).toBe(400);
    const wrong = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, payload: { email, password: 'wrong password 12' } });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json<{ error: { code: string } }>().error.code).toBe('INVALID_CREDENTIALS');
    const unknown = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, payload: { email: `x-${randomUUID()}@example.test`, password: 'wrong password 12' } });
    expect(unknown.json<{ error: { code: string } }>().error.code).toBe('INVALID_CREDENTIALS');
  });

  it('an unenrolled admin is refused on every guarded route with MFA_ENROLMENT_REQUIRED', async () => {
    const login = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, payload: { email, password: PASSWORD } });
    const cookie = cookieFrom(login);
    for (const [method, url] of [
      ['GET', '/v1/admin/auth/me'],
      ['GET', '/v1/admin/auth/sessions'],
      ['POST', '/v1/admin/auth/logout'],
      ['GET', '/v1/admin/audit-log'],
    ] as const) {
      const res = await ctx.app.inject({ method, url, headers: { cookie, ...csrf } });
      expect(res.statusCode, `${method} ${url}`).toBe(403);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('MFA_ENROLMENT_REQUIRED');
    }
  });

  it('no cookie → UNAUTHENTICATED; idle session → SESSION_EXPIRED', async () => {
    const none = await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me' });
    expect(none.statusCode).toBe(401);
    expect(none.json<{ error: { code: string } }>().error.code).toBe('UNAUTHENTICATED');

    const login = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, payload: { email, password: PASSWORD } });
    const cookie = cookieFrom(login);
    time.advance(16 * 60_000);
    const expired = await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me', headers: { cookie } });
    expect(expired.statusCode).toBe(401);
    expect(expired.json<{ error: { code: string } }>().error.code).toBe('SESSION_EXPIRED');
  });

  it('the login route carries its own stricter rate limit', async () => {
    const ip = `10.77.${String(Math.floor(Math.random() * 250))}.${String(Math.floor(Math.random() * 250) + 1)}`;
    let last = 0;
    for (let i = 0; i < 11; i += 1) {
      const res = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: csrf, remoteAddress: ip, payload: { email, password: 'wrong password 12' } });
      last = res.statusCode;
    }
    expect(last).toBe(429);
    // Other routes from the same IP still answer.
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/health', remoteAddress: ip })).statusCode).toBe(200);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/admin-auth-routes.test.ts`
Expected: FAIL — `app.adminAuth` undefined.

- [ ] **Step 3: Write the plugin and the guards**

`backend/src/plugins/admin-session.ts`:

```ts
import cookie from '@fastify/cookie';
import cors from '@fastify/cors';
import type { CookieSerializeOptions } from '@fastify/cookie';
import type { FastifyInstance } from 'fastify';

import type { Config } from '../config/env.js';
import { AuthorizationError } from '../core/errors.js';

export const ADMIN_COOKIE = 'rp_admin_session';
export const CSRF_HEADER = 'x-requested-with';
export const CSRF_VALUE = 'RaajjePro-Admin';
const ADMIN_PREFIX = '/v1/admin';
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export function cookieOptions(config: Config): CookieSerializeOptions {
  return {
    httpOnly: true,
    secure: config.admin.cookieSecure,
    sameSite: 'strict',
    path: ADMIN_PREFIX,
    maxAge: config.admin.sessionAbsoluteHours * 3600,
  };
}

/**
 * Admin session resolution. Runs onRequest, before rate limiting, so counters
 * key on the admin. Two jobs: (1) CSRF — every non-safe request under
 * /v1/admin must carry the custom header, which a cross-origin form cannot
 * send without a preflight that CORS refuses; (2) cookie → principal, with
 * the rejection reason kept for the guard to report.
 */
export async function registerAdminSession(app: FastifyInstance): Promise<void> {
  await app.register(cookie);
  await app.register(cors, {
    origin: app.config.admin.origin,
    credentials: true,
    allowedHeaders: ['content-type', 'x-requested-with', 'idempotency-key', 'x-request-id'],
    exposedHeaders: ['x-request-id', 'retry-after', 'idempotent-replayed'],
  });

  app.addHook('onRequest', async (request) => {
    if (!request.url.startsWith(ADMIN_PREFIX)) return;

    if (!SAFE_METHODS.has(request.method) && request.headers[CSRF_HEADER] !== CSRF_VALUE) {
      throw new AuthorizationError('CSRF_HEADER_MISSING', `${CSRF_HEADER}: ${CSRF_VALUE} header required`);
    }

    const token = request.cookies[ADMIN_COOKIE];
    if (token === undefined) {
      request.sessionRejection = 'UNAUTHENTICATED';
      return;
    }
    const resolution = await app.adminAuth.resolveSession(token);
    if ('principal' in resolution) {
      request.principal = resolution.principal;
    } else {
      request.sessionRejection = resolution.rejection;
    }
  });
}
```

`backend/src/modules/admin-auth/guards.ts`:

```ts
import type { FastifyReply, FastifyRequest } from 'fastify';

import { AuthenticationError, AuthorizationError } from '../../core/errors.js';
import type { AdminPrincipal } from '../../core/principal.js';

function adminPrincipal(request: FastifyRequest): AdminPrincipal {
  const p = request.principal;
  if (p === undefined) {
    throw new AuthenticationError(request.sessionRejection ?? 'UNAUTHENTICATED', 'Sign in to continue');
  }
  return p;
}

/** A live session whose password was verified. Enough for the MFA routes only. */
export async function requirePasswordSession(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  adminPrincipal(request);
}

/**
 * Who may pass: an active admin, TOTP enrolled, MFA verified on this session.
 * Nothing else in /v1/admin is reachable without this (plan §Phase 2: enrolment
 * required before the account can take any action).
 */
export async function requireAdmin(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const p = adminPrincipal(request);
  if (!p.totpEnrolled) throw new AuthorizationError('MFA_ENROLMENT_REQUIRED', 'Enrol an authenticator app to continue');
  if (!p.mfaVerified) throw new AuthenticationError('MFA_REQUIRED', 'Enter your authenticator code to continue');
}

/** requireAdmin plus a re-authentication within ADMIN_REAUTH_MINUTES. Phase 10a puts this before identity documents. */
export async function requireRecentReauth(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  await requireAdmin(request, reply);
  const p = request.principal as AdminPrincipal;
  const limitMs = request.server.config.admin.reauthMinutes * 60_000;
  const now = request.server.deps.clock().getTime();
  if (p.reauthenticatedAt === null || now - p.reauthenticatedAt.getTime() > limitMs) {
    throw new AuthorizationError('REAUTHENTICATION_REQUIRED', 'Confirm your password and authenticator code to continue');
  }
}
```

- [ ] **Step 4: Write the schemas and routes**

`backend/src/modules/admin-auth/schema.ts`:

```ts
import { z } from 'zod';

import { MAX_PASSWORD_LENGTH } from './crypto.js';

export const loginBody = z.object({
  email: z.string().trim().email().max(320),
  password: z.string().min(1).max(MAX_PASSWORD_LENGTH),
});

export const sessionIdParams = z.object({ id: z.uuid() });

export const revokeSessionBody = z.object({ reason: z.string().trim().min(1).max(500) });

export const mfaCodeBody = z.object({ code: z.string().trim().min(6).max(11) });

export const reauthBody = z.object({
  password: z.string().min(1).max(MAX_PASSWORD_LENGTH),
  code: z.string().trim().min(6).max(11),
});
```

`backend/src/modules/admin-auth/routes.ts` (Task 10 adds the MFA routes to this same function):

```ts
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import type { AdminPrincipal } from '../../core/principal.js';
import type { AdminSession } from '../../generated/prisma/client.js';
import { ADMIN_COOKIE, cookieOptions } from '../../plugins/admin-session.js';
import { requireAdmin } from './guards.js';
import { loginBody, revokeSessionBody, sessionIdParams } from './schema.js';
import type { RequestMeta } from './service.js';

export function requestMeta(request: FastifyRequest): RequestMeta {
  return { ip: request.ip, userAgent: request.headers['user-agent'] ?? '', requestId: request.id };
}

/** DTO: never the token hash, never the admin's password hash. */
function sessionDto(session: AdminSession, current: string) {
  return {
    id: session.id,
    createdAt: session.createdAt.toISOString(),
    lastSeenAt: session.lastSeenAt.toISOString(),
    expiresAt: session.expiresAt.toISOString(),
    ipAddress: session.ipAddress,
    userAgent: session.userAgent,
    current: session.id === current,
  };
}

export function registerAdminAuthRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/admin/auth';

  // Who may call: anyone — this is how a session begins. Stricter tier: 10 per 15 min per IP.
  r.post(
    `${prefix}/login`,
    { schema: { body: loginBody }, config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const result = await app.adminAuth.login(request.body.email, request.body.password, requestMeta(request));
      void reply.setCookie(ADMIN_COOKIE, result.token, cookieOptions(app.config));
      return reply.send(ok({ state: result.state, adminId: result.session.adminId }));
    },
  );

  // Who may call: the enrolled, MFA-verified admin, about themselves.
  r.get(`${prefix}/me`, { preHandler: requireAdmin }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    const admin = await app.deps.prisma.adminUser.findUniqueOrThrow({ where: { id: p.id } });
    return reply.send(
      ok({
        id: admin.id,
        email: admin.email,
        role: admin.role,
        totpEnrolled: admin.totpEnrolledAt !== null,
        reauthenticatedAt: p.reauthenticatedAt?.toISOString() ?? null,
      }),
    );
  });

  // Who may call: the enrolled, MFA-verified admin, for their own session.
  r.post(`${prefix}/logout`, { preHandler: requireAdmin }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    await app.adminAuth.logout(p.sessionId, p.id, requestMeta(request));
    void reply.clearCookie(ADMIN_COOKIE, cookieOptions(app.config));
    return reply.send(ok({ loggedOut: true }));
  });

  // Who may call: the enrolled, MFA-verified admin; lists their own sessions only.
  r.get(`${prefix}/sessions`, { preHandler: requireAdmin }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    const sessions = await app.adminAuth.listSessions(p.id);
    return reply.send(ok(sessions.map((s) => sessionDto(s, p.sessionId))));
  });

  // Who may call: the enrolled, MFA-verified admin, for one of their own sessions. Reason required (audit).
  r.delete(
    `${prefix}/sessions/:id`,
    { schema: { params: sessionIdParams, body: revokeSessionBody }, preHandler: requireAdmin },
    async (request, reply) => {
      const p = request.principal as AdminPrincipal;
      await app.adminAuth.revokeSession(p.id, request.params.id, request.body.reason, requestMeta(request));
      return reply.send(ok({ revoked: request.params.id }));
    },
  );
}
```

- [ ] **Step 5: Wire it into `app.ts`**

Add the decorations and the registration order. The full `buildApp` body after this task:

```ts
declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
    deps: AppDeps;
    audit: AuditService;
    adminAuth: AdminAuthService;
  }
}

export async function buildApp(config: Config, deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({ logger: loggerOptions(config), genReqId, requestIdHeader: false, trustProxy: config.trustProxy }).withTypeProvider<ZodTypeProvider>();
  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);
  app.decorate('config', config);
  app.decorate('deps', deps);

  const audit = new AuditService(deps.prisma, deps.clock);
  app.decorate('audit', audit);
  app.decorate('adminAuth', new AdminAuthService({ prisma: deps.prisma, audit, clock: deps.clock, config }));

  app.addHook('onSend', async (request, reply) => {
    void reply.header('x-request-id', request.id);
  });

  registerErrorHandling(app);
  await registerAdminSession(app); // before rate limiting: counters key on the principal
  await registerRateLimit(app);
  registerIdempotency(app);

  registerHealthRoutes(app);
  registerAdminAuthRoutes(app);
  return app;
}
```

Also add a placeholder `GET /v1/admin/audit-log` guarded by `requireAdmin` in `modules/audit/routes.ts` so the enrolment test's fourth route exists — Task 11 fills in its query logic:

```ts
import type { FastifyInstance } from 'fastify';
import { ok } from '../../core/envelope.js';
import { requireAdmin } from '../admin-auth/guards.js';

export function registerAuditRoutes(app: FastifyInstance): void {
  app.get('/v1/admin/audit-log', { preHandler: requireAdmin }, async (_request, reply) => reply.send(ok([], { nextCursor: null })));
}
```

and call `registerAuditRoutes(app);` after `registerAdminAuthRoutes(app);`.

- [ ] **Step 6: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run test/admin-auth-routes.test.ts && npm run lint && npm run typecheck`
Expected: 6 pass. If `request.cookies` is untyped, ensure `@fastify/cookie` is imported (its module augmentation adds it). If `z.uuid()`/`.email()` warn under Zod 4, use `z.uuid()` and `z.email()` top-level forms.

- [ ] **Step 7: Commit**

```bash
git add backend/src backend/test/admin-auth-routes.test.ts
git commit -m "Phase 2 — admin login, cookie sessions, CSRF and CORS, and the guards every admin route stands behind"
```

---

### Task 10: TOTP enrolment, verification, recovery codes, re-authentication

**Files:**
- Modify: `backend/src/modules/admin-auth/service.ts` (add methods), `backend/src/modules/admin-auth/routes.ts` (add routes), `backend/src/modules/admin-auth/repository.ts` (recovery-code access)
- Create: `backend/test/helpers/admin.ts`
- Test: `backend/test/admin-mfa.test.ts`

**Interfaces:**
- Produces on `AdminAuthService`:
  ```ts
  beginEnrolment(adminId, sessionId, meta): Promise<{ secret: string; otpauthUri: string }>
  confirmEnrolment(adminId, sessionId, code, meta): Promise<{ recoveryCodes: string[] }>
  verifyMfa(adminId, sessionId, code, meta): Promise<{ method: 'totp' | 'recovery_code' }>
  reauthenticate(adminId, sessionId, password, code, meta): Promise<void>
  regenerateRecoveryCodes(adminId, meta): Promise<{ recoveryCodes: string[] }>
  ```
- Routes: `POST /mfa/enrol`, `POST /mfa/enrol/confirm`, `POST /mfa/verify` (rate limit 5 per 5 min per principal), `POST /reauth`, `POST /mfa/recovery-codes/regenerate` (requireRecentReauth).
- Test helper: `createEnrolledAdmin(app, options?) → { email, password, adminId, cookie, secret, recoveryCodes }`.

- [ ] **Step 1: Write the test helper and the failing test**

`backend/test/helpers/admin.ts`:

```ts
import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';
import { generate } from 'otplib';

export const CSRF = { 'x-requested-with': 'RaajjePro-Admin' };
export const PASSWORD = 'a long enough password';

export function cookieFrom(res: { headers: Record<string, unknown> }): string {
  const raw = res.headers['set-cookie'];
  const first = Array.isArray(raw) ? raw[0] : raw;
  return String(first).split(';')[0] ?? '';
}

export function totpNow(secret: string): Promise<string> {
  return generate({ secret });
}

/** Creates an admin, logs in, enrols TOTP and verifies — the state every guarded route needs. */
export async function createEnrolledAdmin(app: FastifyInstance) {
  const email = `admin-${randomUUID()}@example.test`;
  const admin = await app.adminAuth.createAdmin(email, PASSWORD, {});
  const login = await app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email, password: PASSWORD } });
  const cookie = cookieFrom(login);
  const enrol = await app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/enrol', headers: { cookie, ...CSRF } });
  const { secret } = enrol.json<{ data: { secret: string; otpauthUri: string } }>().data;
  const confirm = await app.inject({
    method: 'POST',
    url: '/v1/admin/auth/mfa/enrol/confirm',
    headers: { cookie, ...CSRF },
    payload: { code: await totpNow(secret) },
  });
  const { recoveryCodes } = confirm.json<{ data: { recoveryCodes: string[] } }>().data;
  return { email, password: PASSWORD, adminId: admin.id, cookie, secret, recoveryCodes };
}

/** A fresh session for an already-enrolled admin, MFA-verified with the given secret. */
export async function loginAndVerify(app: FastifyInstance, email: string, secret: string) {
  const login = await app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email, password: PASSWORD } });
  const cookie = cookieFrom(login);
  const verify = await app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie, ...CSRF }, payload: { code: await totpNow(secret) } });
  return { cookie, verifyStatus: verify.statusCode };
}
```

`backend/test/admin-mfa.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl } from './helpers/app.js';
import { CSRF, PASSWORD, cookieFrom, createEnrolledAdmin, loginAndVerify, totpNow } from './helpers/admin.js';

describe.skipIf(databaseUrl === undefined)('admin MFA', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date());

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, reauthMinutes: 5 });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('enrolment: uri + secret once, confirm with a valid code, recovery codes returned exactly once, then /me works', async () => {
    const email = `admin-${randomUUID()}@example.test`;
    await ctx.app.adminAuth.createAdmin(email, PASSWORD, {});
    const login = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email, password: PASSWORD } });
    const cookie = cookieFrom(login);

    const enrol = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/enrol', headers: { cookie, ...CSRF } });
    expect(enrol.statusCode).toBe(200);
    const { secret, otpauthUri } = enrol.json<{ data: { secret: string; otpauthUri: string } }>().data;
    expect(otpauthUri).toMatch(/^otpauth:\/\/totp\/RaajjePro/);
    expect(otpauthUri).toContain(secret);

    const wrong = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/enrol/confirm', headers: { cookie, ...CSRF }, payload: { code: '000000' } });
    expect(wrong.statusCode).toBe(422);
    expect(wrong.json<{ error: { code: string } }>().error.code).toBe('INVALID_MFA_CODE');

    const confirm = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/enrol/confirm', headers: { cookie, ...CSRF }, payload: { code: await totpNow(secret) } });
    expect(confirm.statusCode).toBe(200);
    const { recoveryCodes } = confirm.json<{ data: { recoveryCodes: string[] } }>().data;
    expect(recoveryCodes).toHaveLength(10);

    const me = await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me', headers: { cookie } });
    expect(me.statusCode).toBe(200);
    expect(me.json<{ data: { totpEnrolled: boolean } }>().data.totpEnrolled).toBe(true);

    const again = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/enrol', headers: { cookie, ...CSRF } });
    expect(again.statusCode).toBe(422);
    expect(again.json<{ error: { code: string } }>().error.code).toBe('MFA_ALREADY_ENROLLED');
  });

  it('a new session on an enrolled account is MFA_REQUIRED until verified', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const login = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email: admin.email, password: PASSWORD } });
    expect(login.json<{ data: { state: string } }>().data.state).toBe('mfa_required');
    const cookie = cookieFrom(login);
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me', headers: { cookie } });
    expect(me.statusCode).toBe(401);
    expect(me.json<{ error: { code: string } }>().error.code).toBe('MFA_REQUIRED');
    const verify = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie, ...CSRF }, payload: { code: await totpNow(admin.secret) } });
    expect(verify.statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me', headers: { cookie } })).statusCode).toBe(200);
  });

  it('a recovery code verifies once and is refused on reuse', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const code = admin.recoveryCodes[0] ?? '';
    const first = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email: admin.email, password: PASSWORD } });
    const c1 = cookieFrom(first);
    const ok1 = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie: c1, ...CSRF }, payload: { code } });
    expect(ok1.statusCode).toBe(200);
    expect(ok1.json<{ data: { method: string } }>().data.method).toBe('recovery_code');

    const second = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email: admin.email, password: PASSWORD } });
    const c2 = cookieFrom(second);
    const reused = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie: c2, ...CSRF }, payload: { code } });
    expect(reused.statusCode).toBe(422);
    const audit = await ctx.prisma.auditLogEntry.count({ where: { action: 'admin.mfa.recovery_code_used', actorId: admin.adminId } });
    expect(audit).toBe(1);
  });

  it('five failed verifications revoke the session', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const login = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email: admin.email, password: PASSWORD } });
    const cookie = cookieFrom(login);
    for (let i = 0; i < 5; i += 1) {
      const res = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie, ...CSRF }, payload: { code: '000000' } });
      expect(res.statusCode).toBe(422);
    }
    const after = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie, ...CSRF }, payload: { code: await totpNow(admin.secret) } });
    expect(after.statusCode).toBe(401);
    const row = await ctx.prisma.adminSession.findFirst({ where: { adminId: admin.adminId, revokedReason: 'mfa_failures' } });
    expect(row).not.toBeNull();
  });

  it('re-authentication gates the recovery-code regeneration and expires after the configured window', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const { cookie } = await loginAndVerify(ctx.app, admin.email, admin.secret);
    const url = '/v1/admin/auth/mfa/recovery-codes/regenerate';
    const before = await ctx.app.inject({ method: 'POST', url, headers: { cookie, ...CSRF } });
    expect(before.statusCode).toBe(403);
    expect(before.json<{ error: { code: string } }>().error.code).toBe('REAUTHENTICATION_REQUIRED');

    const badReauth = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/reauth', headers: { cookie, ...CSRF }, payload: { password: 'wrong password 12', code: await totpNow(admin.secret) } });
    expect(badReauth.statusCode).toBe(401);
    const reauth = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/reauth', headers: { cookie, ...CSRF }, payload: { password: PASSWORD, code: await totpNow(admin.secret) } });
    expect(reauth.statusCode).toBe(200);

    const regenerated = await ctx.app.inject({ method: 'POST', url, headers: { cookie, ...CSRF } });
    expect(regenerated.statusCode).toBe(200);
    const fresh = regenerated.json<{ data: { recoveryCodes: string[] } }>().data.recoveryCodes;
    expect(fresh).toHaveLength(10);
    expect(fresh).not.toContain(admin.recoveryCodes[1]);
    // The old set is revoked.
    const login = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/login', headers: CSRF, payload: { email: admin.email, password: PASSWORD } });
    const oldCode = await ctx.app.inject({ method: 'POST', url: '/v1/admin/auth/mfa/verify', headers: { cookie: cookieFrom(login), ...CSRF }, payload: { code: admin.recoveryCodes[1] ?? '' } });
    expect(oldCode.statusCode).toBe(422);

    time.advance(5 * 60_000 + 1000);
    const stale = await ctx.app.inject({ method: 'POST', url, headers: { cookie, ...CSRF } });
    expect(stale.statusCode).toBe(403);
    time.set(new Date());
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/admin-mfa.test.ts`
Expected: FAIL — 404 on `/mfa/enrol`.

- [ ] **Step 3: Extend the repository**

Add to `AdminRepository`:

```ts
  setPendingTotpSecret(adminId: string, encrypted: string): Promise<AdminUser> {
    return this.prisma.adminUser.update({ where: { id: adminId }, data: { totpSecretEncrypted: encrypted } });
  }

  markEnrolled(db: Db, adminId: string, sessionId: string, now: Date): Promise<void> {
    return Promise.all([
      db.adminUser.update({ where: { id: adminId }, data: { totpEnrolledAt: now } }),
      db.adminSession.update({ where: { id: sessionId }, data: { mfaVerifiedAt: now, mfaFailures: 0 } }),
    ]).then(() => undefined);
  }

  markMfaVerified(db: Db, sessionId: string, now: Date): Promise<AdminSession> {
    return db.adminSession.update({ where: { id: sessionId }, data: { mfaVerifiedAt: now, mfaFailures: 0 } });
  }

  incrementMfaFailures(sessionId: string): Promise<AdminSession> {
    return this.prisma.adminSession.update({ where: { id: sessionId }, data: { mfaFailures: { increment: 1 } } });
  }

  markReauthenticated(sessionId: string, now: Date): Promise<AdminSession> {
    return this.prisma.adminSession.update({ where: { id: sessionId }, data: { reauthenticatedAt: now } });
  }

  async replaceRecoveryCodes(db: Db, adminId: string, hashes: string[], now: Date): Promise<void> {
    await db.adminRecoveryCode.updateMany({ where: { adminId, usedAt: null, revokedAt: null }, data: { revokedAt: now } });
    await db.adminRecoveryCode.createMany({ data: hashes.map((codeHash) => ({ adminId, codeHash, createdAt: now })) });
  }

  findUnusedRecoveryCode(adminId: string, codeHash: string) {
    return this.prisma.adminRecoveryCode.findFirst({ where: { adminId, codeHash, usedAt: null, revokedAt: null } });
  }

  markRecoveryCodeUsed(db: Db, id: string, now: Date) {
    return db.adminRecoveryCode.update({ where: { id }, data: { usedAt: now } });
  }
```

- [ ] **Step 4: Add the service methods**

Add these imports to `service.ts`: `import { generateSecret, generateURI, verify as verifyTotp } from 'otplib';` and from `./crypto.js`: `decryptSecret, encryptSecret, hashToken, newRecoveryCodes, normaliseRecoveryCode`. Then add to the class:

```ts
  static readonly MFA_FAILURE_LIMIT = 5;
  static readonly TOTP_ISSUER = 'RaajjePro Admin';

  /** Who may call: an admin with a password-verified session who has not yet enrolled. */
  async beginEnrolment(adminId: string, _sessionId: string, _meta: RequestMeta): Promise<{ secret: string; otpauthUri: string }> {
    const admin = await this.mustFindAdmin(adminId);
    if (admin.totpEnrolledAt !== null) throw new BusinessRuleError('MFA_ALREADY_ENROLLED', 'An authenticator is already enrolled');
    const secret = generateSecret();
    await this.repo.setPendingTotpSecret(adminId, encryptSecret(secret, this.config.admin.totpEncryptionKey));
    return { secret, otpauthUri: generateURI({ issuer: AdminAuthService.TOTP_ISSUER, label: admin.email, secret }) };
  }

  /** Who may call: same as beginEnrolment. Returns the recovery codes — the only time they are ever shown. */
  async confirmEnrolment(adminId: string, sessionId: string, code: string, meta: RequestMeta): Promise<{ recoveryCodes: string[] }> {
    const admin = await this.mustFindAdmin(adminId);
    if (admin.totpEnrolledAt !== null) throw new BusinessRuleError('MFA_ALREADY_ENROLLED', 'An authenticator is already enrolled');
    if (admin.totpSecretEncrypted === null) throw new BusinessRuleError('INVALID_MFA_CODE', 'Start enrolment first');
    if (!(await this.totpMatches(admin.totpSecretEncrypted, code))) {
      throw new BusinessRuleError('INVALID_MFA_CODE', 'That code is not valid');
    }
    const now = this.clock();
    const codes = newRecoveryCodes();
    await this.prisma.$transaction(async (tx) => {
      await this.repo.markEnrolled(tx, adminId, sessionId, now);
      await this.repo.replaceRecoveryCodes(tx, adminId, codes.map(hashToken), now);
      await this.audit.record(tx, { actorType: 'admin', actorId: adminId, action: 'admin.mfa.enrolled', targetType: 'admin_user', targetId: adminId, reason: 'user_initiated', requestId: meta.requestId, ipAddress: meta.ip });
    });
    return { recoveryCodes: codes };
  }

  /** Who may call: an enrolled admin on a session not yet MFA-verified. Five failures revoke the session. */
  async verifyMfa(adminId: string, sessionId: string, code: string, meta: RequestMeta): Promise<{ method: 'totp' | 'recovery_code' }> {
    const admin = await this.mustFindAdmin(adminId);
    if (admin.totpEnrolledAt === null || admin.totpSecretEncrypted === null) {
      throw new AuthorizationError('MFA_ENROLMENT_REQUIRED', 'Enrol an authenticator app first');
    }
    const now = this.clock();
    if (await this.totpMatches(admin.totpSecretEncrypted, code)) {
      await this.prisma.$transaction(async (tx) => {
        await this.repo.markMfaVerified(tx, sessionId, now);
        await this.audit.record(tx, { actorType: 'admin', actorId: adminId, action: 'admin.mfa.verified', targetType: 'admin_session', targetId: sessionId, reason: 'totp', requestId: meta.requestId, ipAddress: meta.ip });
      });
      return { method: 'totp' };
    }
    const recovery = await this.repo.findUnusedRecoveryCode(adminId, hashToken(normaliseRecoveryCode(code)));
    if (recovery !== null) {
      await this.prisma.$transaction(async (tx) => {
        await this.repo.markRecoveryCodeUsed(tx, recovery.id, now);
        await this.repo.markMfaVerified(tx, sessionId, now);
        await this.audit.record(tx, { actorType: 'admin', actorId: adminId, action: 'admin.mfa.recovery_code_used', targetType: 'admin_session', targetId: sessionId, reason: 'recovery_code', metadata: { recoveryCodeId: recovery.id }, requestId: meta.requestId, ipAddress: meta.ip });
      });
      return { method: 'recovery_code' };
    }
    const session = await this.repo.incrementMfaFailures(sessionId);
    if (session.mfaFailures >= AdminAuthService.MFA_FAILURE_LIMIT) {
      await this.prisma.$transaction(async (tx) => {
        await this.repo.revokeSession(tx, sessionId, now, 'mfa_failures');
        await this.audit.record(tx, { actorType: 'system', action: 'admin.session.revoked', targetType: 'admin_session', targetId: sessionId, reason: 'mfa_failures', requestId: meta.requestId, ipAddress: meta.ip });
      });
    }
    throw new BusinessRuleError('INVALID_MFA_CODE', 'That code is not valid');
  }

  /** Who may call: the enrolled, MFA-verified admin, for their own session. Password AND a fresh TOTP. */
  async reauthenticate(adminId: string, sessionId: string, password: string, code: string, meta: RequestMeta): Promise<void> {
    const admin = await this.mustFindAdmin(adminId);
    const passwordOk = await verifyPassword(admin.passwordHash, password);
    const codeOk = admin.totpSecretEncrypted !== null && (await this.totpMatches(admin.totpSecretEncrypted, code));
    if (!passwordOk || !codeOk) throw new AuthenticationError('INVALID_CREDENTIALS', 'Password or code is incorrect');
    const now = this.clock();
    await this.repo.markReauthenticated(sessionId, now);
    await this.audit.record(this.prisma, { actorType: 'admin', actorId: adminId, action: 'admin.reauthenticated', targetType: 'admin_session', targetId: sessionId, reason: 'user_initiated', requestId: meta.requestId, ipAddress: meta.ip });
  }

  /** Who may call: the enrolled, MFA-verified, recently re-authenticated admin. Old unused codes are revoked. */
  async regenerateRecoveryCodes(adminId: string, meta: RequestMeta): Promise<{ recoveryCodes: string[] }> {
    const now = this.clock();
    const codes = newRecoveryCodes();
    await this.prisma.$transaction(async (tx) => {
      await this.repo.replaceRecoveryCodes(tx, adminId, codes.map(hashToken), now);
      await this.audit.record(tx, { actorType: 'admin', actorId: adminId, action: 'admin.mfa.recovery_codes_regenerated', targetType: 'admin_user', targetId: adminId, reason: 'user_initiated', requestId: meta.requestId, ipAddress: meta.ip });
    });
    return { recoveryCodes: codes };
  }

  private async mustFindAdmin(adminId: string): Promise<AdminUser> {
    const admin = await this.repo.findById(adminId);
    if (admin === null || admin.status !== 'active') throw new AuthenticationError('UNAUTHENTICATED', 'Sign in to continue');
    return admin;
  }

  private async totpMatches(encryptedSecret: string, code: string): Promise<boolean> {
    if (!/^\d{6}$/.test(code.trim())) return false;
    const secret = decryptSecret(encryptedSecret, this.config.admin.totpEncryptionKey);
    const result = await verifyTotp({ secret, token: code.trim(), epochTolerance: 30 });
    return result.valid;
  }
```

- [ ] **Step 5: Add the routes**

In `registerAdminAuthRoutes`, add (imports: `requirePasswordSession`, `requireRecentReauth`, `mfaCodeBody`, `reauthBody`):

```ts
  // Who may call: a password-verified session that has not enrolled yet.
  r.post(`${prefix}/mfa/enrol`, { preHandler: requirePasswordSession }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    return reply.send(ok(await app.adminAuth.beginEnrolment(p.id, p.sessionId, requestMeta(request))));
  });

  // Who may call: same. Recovery codes come back once, here, and never again.
  r.post(`${prefix}/mfa/enrol/confirm`, { schema: { body: mfaCodeBody }, preHandler: requirePasswordSession }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    return reply.send(ok(await app.adminAuth.confirmEnrolment(p.id, p.sessionId, request.body.code, requestMeta(request))));
  });

  // Who may call: an enrolled admin's unverified session. Own tier: 5 per 5 min per principal.
  r.post(
    `${prefix}/mfa/verify`,
    { schema: { body: mfaCodeBody }, preHandler: requirePasswordSession, config: { rateLimit: { max: 5, timeWindow: '5 minutes' } } },
    async (request, reply) => {
      const p = request.principal as AdminPrincipal;
      return reply.send(ok(await app.adminAuth.verifyMfa(p.id, p.sessionId, request.body.code, requestMeta(request))));
    },
  );

  // Who may call: the enrolled, MFA-verified admin, for their own session.
  r.post(`${prefix}/reauth`, { schema: { body: reauthBody }, preHandler: requireAdmin }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    await app.adminAuth.reauthenticate(p.id, p.sessionId, request.body.password, request.body.code, requestMeta(request));
    return reply.send(ok({ reauthenticatedAt: app.deps.clock().toISOString() }));
  });

  // Who may call: the enrolled, MFA-verified admin who re-authenticated within ADMIN_REAUTH_MINUTES.
  r.post(`${prefix}/mfa/recovery-codes/regenerate`, { preHandler: requireRecentReauth }, async (request, reply) => {
    const p = request.principal as AdminPrincipal;
    return reply.send(ok(await app.adminAuth.regenerateRecoveryCodes(p.id, requestMeta(request))));
  });
```

- [ ] **Step 6: Run the tests, lint, typecheck**

Run: `cd backend && npx vitest run test/admin-mfa.test.ts test/admin-auth-routes.test.ts && npm run lint && npm run typecheck`
Expected: all pass. The `mfa/verify` rate limit (5 per 5 min) and the failure limit (5) coincide; the test drives exactly five failures then one more, which hits the revoked session before the sixth counted request — if the sixth returns 429 instead of 401, set the route tier to `max: 6` and note it in the route comment (both limits are defensible; the session revocation is the rule the plan states).

- [ ] **Step 7: Commit**

```bash
git add backend/src/modules/admin-auth backend/test/helpers/admin.ts backend/test/admin-mfa.test.ts
git commit -m "Phase 2 — mandatory TOTP enrolment, verification with recovery codes, and re-authentication"
```

---

### Task 11: Audit-log query route and the `admin:create` CLI

**Files:**
- Modify: `backend/src/modules/audit/routes.ts`
- Create: `backend/src/cli/admin-create.ts`
- Test: `backend/test/audit-routes.test.ts`

**Interfaces:**
- Produces: `GET /v1/admin/audit-log?from&to&actorId&action&cursor&limit` → `{ data: AuditEntryDto[], meta: { nextCursor } }` where `AuditEntryDto = { id, actorType, actorId, action, targetType, targetId, reason, metadata, requestId, createdAt }` (no `ipAddress` — not needed by the viewer, and an IP is quasi-PII).

- [ ] **Step 1: Write the failing test**

`backend/test/audit-routes.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, databaseUrl } from './helpers/app.js';
import { CSRF, createEnrolledAdmin, loginAndVerify } from './helpers/admin.js';

interface Entry { id: string; action: string; actorId: string | null; targetId: string; reason: string; createdAt: string }

describe.skipIf(databaseUrl === undefined)('GET /v1/admin/audit-log', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  beforeAll(async () => {
    ctx = await buildTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('an admin action appears and is filterable by action, actor and date', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const { cookie } = await loginAndVerify(ctx.app, admin.email, admin.secret);
    const other = await loginAndVerify(ctx.app, admin.email, admin.secret);
    const sessions = await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/sessions', headers: { cookie } });
    const target = sessions.json<{ data: { id: string; current: boolean }[] }>().data.find((s) => !s.current);
    expect(target).toBeDefined();
    expect(other.verifyStatus).toBe(200);

    const revoke = await ctx.app.inject({ method: 'DELETE', url: `/v1/admin/auth/sessions/${target?.id ?? ''}`, headers: { cookie, ...CSRF }, payload: { reason: 'left signed in at the café' } });
    expect(revoke.statusCode).toBe(200);

    const byAction = await ctx.app.inject({ method: 'GET', url: `/v1/admin/audit-log?action=admin.session.revoked&actorId=${admin.adminId}`, headers: { cookie } });
    expect(byAction.statusCode).toBe(200);
    const items = byAction.json<{ data: Entry[]; meta: { nextCursor: string | null } }>();
    expect(items.data).toHaveLength(1);
    expect(items.data[0]).toMatchObject({ action: 'admin.session.revoked', actorId: admin.adminId, targetId: target?.id, reason: 'left signed in at the café' });
    expect(items.data[0]).not.toHaveProperty('ipAddress');

    const from = encodeURIComponent(new Date(Date.now() - 60_000).toISOString());
    const to = encodeURIComponent(new Date(Date.now() + 60_000).toISOString());
    const byDate = await ctx.app.inject({ method: 'GET', url: `/v1/admin/audit-log?from=${from}&to=${to}&actorId=${admin.adminId}&limit=2`, headers: { cookie } });
    const page = byDate.json<{ data: Entry[]; meta: { nextCursor: string | null } }>();
    expect(page.data).toHaveLength(2);
    expect(page.meta.nextCursor).not.toBeNull();
    const next = await ctx.app.inject({ method: 'GET', url: `/v1/admin/audit-log?actorId=${admin.adminId}&limit=2&cursor=${page.meta.nextCursor ?? ''}`, headers: { cookie } });
    expect(next.statusCode).toBe(200);
    expect(next.json<{ data: Entry[] }>().data[0]?.id).not.toBe(page.data[0]?.id);
  });

  it('rejects a bad limit and a malformed cursor with the envelope', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const { cookie } = await loginAndVerify(ctx.app, admin.email, admin.secret);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/admin/audit-log?limit=1000', headers: { cookie } })).statusCode).toBe(400);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/admin/audit-log?cursor=!!!', headers: { cookie } })).statusCode).toBe(400);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/audit-routes.test.ts`
Expected: FAIL — empty list.

- [ ] **Step 3: Replace `modules/audit/routes.ts`**

```ts
import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { ok } from '../../core/envelope.js';
import type { AuditLogEntry } from '../../generated/prisma/client.js';
import { requireAdmin } from '../admin-auth/guards.js';

const query = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  actorId: z.uuid().optional(),
  action: z.string().trim().min(1).max(100).optional(),
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

/** DTO: everything the viewer needs; the IP stays in the table. */
function dto(e: AuditLogEntry) {
  return {
    id: e.id,
    actorType: e.actorType,
    actorId: e.actorId,
    action: e.action,
    targetType: e.targetType,
    targetId: e.targetId,
    reason: e.reason,
    metadata: e.metadata,
    requestId: e.requestId,
    createdAt: e.createdAt.toISOString(),
  };
}

export function registerAuditRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  // Who may call: the enrolled, MFA-verified admin. Read access is guarded too — the log names targets.
  r.get('/v1/admin/audit-log', { schema: { querystring: query }, preHandler: requireAdmin }, async (request, reply) => {
    const q = request.query;
    const { items, nextCursor } = await app.audit.query({
      ...(q.from === undefined ? {} : { from: q.from }),
      ...(q.to === undefined ? {} : { to: q.to }),
      ...(q.actorId === undefined ? {} : { actorId: q.actorId }),
      ...(q.action === undefined ? {} : { action: q.action }),
      ...(q.cursor === undefined ? {} : { cursor: q.cursor }),
      limit: q.limit,
    });
    return reply.send(ok(items.map(dto), { nextCursor }));
  });
}
```

- [ ] **Step 4: Write the CLI**

`backend/src/cli/admin-create.ts`:

```ts
/**
 * `npm run admin:create -- --email admin@example.com`
 *
 * How an admin account comes to exist (decision 2026-09-05: a server-side
 * CLI, no in-panel "add admin", no bootstrap endpoint). The password is read
 * from the terminal without echo. TOTP enrolment happens at the admin's first
 * login; nothing about MFA is printed or accepted here.
 */
import { parseArgs } from 'node:util';

import { loadConfig } from '../config/env.js';
import { systemClock } from '../core/clock.js';
import { createPrismaClient } from '../db/client.js';
import { AdminAuthService } from '../modules/admin-auth/service.js';
import { AuditService } from '../modules/audit/service.js';

function promptHidden(question: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const { stdin, stdout } = process;
    if (!stdin.isTTY) {
      reject(new Error('admin:create needs an interactive terminal to read the password'));
      return;
    }
    stdout.write(question);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    let value = '';
    const onData = (chunk: string) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n') {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.off('data', onData);
          stdout.write('\n');
          resolve(value);
          return;
        }
        if (ch === '') {
          stdin.setRawMode(false);
          process.exit(130);
        }
        if (ch === '' || ch === '\b') {
          value = value.slice(0, -1);
        } else {
          value += ch;
        }
      }
    };
    stdin.on('data', onData);
  });
}

const { values } = parseArgs({ options: { email: { type: 'string' } } });
if (values.email === undefined) {
  console.error('usage: npm run admin:create -- --email <address>');
  process.exit(2);
}

const config = loadConfig(process.env);
const prisma = createPrismaClient(config.databaseUrl);
try {
  const password = await promptHidden('Password (min 12 characters): ');
  const confirm = await promptHidden('Repeat password: ');
  if (password !== confirm) {
    console.error('Passwords do not match.');
    process.exitCode = 1;
  } else {
    const audit = new AuditService(prisma, systemClock);
    const service = new AdminAuthService({ prisma, audit, clock: systemClock, config });
    const admin = await service.createAdmin(values.email, password, {});
    console.log(`Created admin ${admin.id}. They enrol an authenticator app at first login.`);
  }
} finally {
  await prisma.$disconnect();
}
```

- [ ] **Step 5: Run the test, lint, typecheck, and the CLI once**

Run: `cd backend && npx vitest run test/audit-routes.test.ts && npm run lint && npm run typecheck`
Expected: 2 pass.

Then: `cd backend && npm run admin:create -- --email you@example.test` — type a 12+ character password twice; expect `Created admin <uuid>`. Run it again with the same email; expect the 409 message from `ConflictError` printed as an unhandled rejection — acceptable for a CLI, but if you prefer, wrap in try/catch and print `error.message`.

- [ ] **Step 6: Commit**

```bash
git add backend/src/modules/audit/routes.ts backend/src/cli backend/test/audit-routes.test.ts
git commit -m "Phase 2 — queryable audit log endpoint and the admin:create CLI"
```

---

### Task 12: Email — `EmailSender`, suppression before send, file and SES transports

**Files:**
- Create: `backend/src/modules/email/types.ts`, `backend/src/modules/email/service.ts`, `backend/src/modules/email/transports/file.ts`, `backend/src/modules/email/transports/ses.ts`, `backend/src/modules/email/transports/index.ts`
- Modify: `backend/src/app.ts` (decorate `app.email`), `backend/src/main.ts` (build the transport)
- Test: `backend/test/email-service.test.ts`

**Interfaces:**
- Produces (`types.ts`):
  ```ts
  type EmailChannel = 'otp' | 'notification' | 'marketing'   // re-exported from config
  interface OutboundEmail { channel: EmailChannel; to: string; subject: string; text: string; html?: string; recipientUserId?: string }
  interface SendOutcome { messageId: string; status: 'sent' | 'suppressed' | 'failed' }
  interface EmailSender { send(email: OutboundEmail): Promise<SendOutcome> }
  interface EmailTransport { deliver(email: OutboundEmail, from: string, configurationSet: string | null): Promise<{ providerMessageId: string }> }
  ```
- `EmailService implements EmailSender`, constructor `(prisma, transport, config: Config['email'], clock)`. `normaliseAddress(a): string`.
- `AppDeps` gains `emailTransport: EmailTransport`; `app.email: EmailSender`.
- `createEmailTransport(config: Config['email']): EmailTransport`.

- [ ] **Step 1: Write the failing test**

`backend/test/email-service.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { EmailService } from '../src/modules/email/service.js';
import type { EmailTransport, OutboundEmail } from '../src/modules/email/types.js';
import { databaseUrl } from './helpers/app.js';

class RecordingTransport implements EmailTransport {
  calls: { email: OutboundEmail; configurationSet: string | null }[] = [];
  fail = false;
  async deliver(email: OutboundEmail, _from: string, configurationSet: string | null) {
    if (this.fail) throw new Error(`SES said no to ${email.to}`);
    this.calls.push({ email, configurationSet });
    return { providerMessageId: `ses-${randomUUID()}` };
  }
}

const sesConfig = {
  transport: 'ses' as const,
  fromAddress: 'no-reply@raajjepro.test',
  region: 'ap-south-1',
  configurationSets: { otp: 'cs-otp', notification: 'cs-notif', marketing: 'cs-mkt' },
  eventsTopicArn: 'arn:aws:sns:ap-south-1:1:t',
};

describe.skipIf(databaseUrl === undefined)('EmailService', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('sends through the transport with the channel configuration set and logs the message', async () => {
    const transport = new RecordingTransport();
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `User-${randomUUID()}@Example.test`;
    const outcome = await service.send({ channel: 'otp', to, subject: 'Your code', text: '123456' });
    expect(outcome.status).toBe('sent');
    expect(transport.calls[0]?.configurationSet).toBe('cs-otp');
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('sent');
    expect(row.toAddress).toBe(to.toLowerCase());
    expect(row.providerMessageId).toMatch(/^ses-/);
    expect(row.configurationSet).toBe('cs-otp');
  });

  it('honours the suppression list BEFORE calling the transport', async () => {
    const transport = new RecordingTransport();
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `bounced-${randomUUID()}@example.test`;
    await prisma.emailSuppression.create({ data: { address: to, reason: 'hard_bounce' } });
    const outcome = await service.send({ channel: 'notification', to: to.toUpperCase(), subject: 's', text: 't' });
    expect(outcome.status).toBe('suppressed');
    expect(transport.calls).toHaveLength(0);
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('suppressed');
    expect(row.providerMessageId).toBeNull();
  });

  it('a lifted suppression no longer blocks', async () => {
    const transport = new RecordingTransport();
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `lifted-${randomUUID()}@example.test`;
    await prisma.emailSuppression.create({ data: { address: to, reason: 'complaint', liftedAt: new Date(), liftReason: 'user asked' } });
    expect((await service.send({ channel: 'marketing', to, subject: 's', text: 't' })).status).toBe('sent');
    expect(transport.calls[0]?.configurationSet).toBe('cs-mkt');
  });

  it('records a transport failure without the recipient address in the reason', async () => {
    const transport = new RecordingTransport();
    transport.fail = true;
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `fail-${randomUUID()}@example.test`;
    const outcome = await service.send({ channel: 'otp', to, subject: 's', text: 't' });
    expect(outcome.status).toBe('failed');
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('failed');
    expect(row.failureReason).toBe('Error');
    expect(row.failureReason).not.toContain(to);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/email-service.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write types, service, transports**

`backend/src/modules/email/types.ts`:

```ts
import type { EmailChannel } from '../../config/env.js';

export type { EmailChannel };

export interface OutboundEmail {
  channel: EmailChannel;
  to: string;
  subject: string;
  text: string;
  html?: string;
  /** Phase 3 sets this so Phase 10b can answer "did this user get it?" by user id. */
  recipientUserId?: string;
}

export interface SendOutcome {
  /** The email_message row id — the handle for the delivery log. */
  messageId: string;
  status: 'sent' | 'suppressed' | 'failed';
}

/** What every domain module sends through. Nothing calls SES directly (CLAUDE.md invariant 10). */
export interface EmailSender {
  send(email: OutboundEmail): Promise<SendOutcome>;
}

/** The vendor boundary. SES in production; a file in development. */
export interface EmailTransport {
  deliver(email: OutboundEmail, from: string, configurationSet: string | null): Promise<{ providerMessageId: string }>;
}
```

`backend/src/modules/email/service.ts`:

```ts
import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import type { EmailSender, EmailTransport, OutboundEmail, SendOutcome } from './types.js';

export function normaliseAddress(address: string): string {
  return address.trim().toLowerCase();
}

/**
 * The one sender (plan §0.0 item 8, §4): looks the address up in the
 * suppression list FIRST — a suppressed address is logged as such and the
 * transport is never contacted — then logs the message, delivers through the
 * channel's configuration set, and records the provider id or the failure.
 */
export class EmailService implements EmailSender {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly transport: EmailTransport,
    private readonly config: Config['email'],
    private readonly clock: Clock,
  ) {}

  async send(email: OutboundEmail): Promise<SendOutcome> {
    const to = normaliseAddress(email.to);
    const configurationSet = this.config.transport === 'ses' ? this.config.configurationSets[email.channel] : null;
    const now = this.clock();

    const suppressed = await this.prisma.emailSuppression.findFirst({ where: { address: to, liftedAt: null } });
    if (suppressed !== null) {
      const row = await this.prisma.emailMessage.create({
        data: { channel: email.channel, toAddress: to, recipientUserId: email.recipientUserId ?? null, subject: email.subject, status: 'suppressed', configurationSet, createdAt: now },
      });
      return { messageId: row.id, status: 'suppressed' };
    }

    const row = await this.prisma.emailMessage.create({
      data: { channel: email.channel, toAddress: to, recipientUserId: email.recipientUserId ?? null, subject: email.subject, status: 'queued', configurationSet, createdAt: now },
    });
    try {
      const { providerMessageId } = await this.transport.deliver({ ...email, to }, this.config.fromAddress, configurationSet);
      await this.prisma.emailMessage.update({ where: { id: row.id }, data: { status: 'sent', providerMessageId, sentAt: this.clock() } });
      return { messageId: row.id, status: 'sent' };
    } catch (error) {
      // The class name only: a vendor message can echo the recipient address.
      const failureReason = error instanceof Error ? error.name : 'UnknownError';
      await this.prisma.emailMessage.update({ where: { id: row.id }, data: { status: 'failed', failureReason } });
      return { messageId: row.id, status: 'failed' };
    }
  }
}
```

`backend/src/modules/email/transports/file.ts`:

```ts
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { EmailTransport, OutboundEmail } from '../types.js';

/** Development/test transport: one JSON file per message in a gitignored directory, so an OTP can be read locally without AWS. */
export class FileEmailTransport implements EmailTransport {
  constructor(private readonly directory: string) {}

  async deliver(email: OutboundEmail, from: string, configurationSet: string | null): Promise<{ providerMessageId: string }> {
    await mkdir(this.directory, { recursive: true });
    const providerMessageId = `file-${randomUUID()}`;
    const file = join(this.directory, `${new Date().toISOString().replaceAll(':', '-')}-${providerMessageId}.json`);
    await writeFile(file, JSON.stringify({ providerMessageId, from, configurationSet, ...email }, null, 2));
    return { providerMessageId };
  }
}
```

`backend/src/modules/email/transports/ses.ts`:

```ts
import { SendEmailCommand, SESv2Client } from '@aws-sdk/client-sesv2';

import type { EmailTransport, OutboundEmail } from '../types.js';

/** Amazon SES v2. Credentials come from the SDK default chain. `ConfigurationSetName` is what routes events to the right SNS destination and keeps channel reputations apart. */
export class SesEmailTransport implements EmailTransport {
  private readonly client: SESv2Client;

  constructor(region: string) {
    this.client = new SESv2Client({ region });
  }

  async deliver(email: OutboundEmail, from: string, configurationSet: string | null): Promise<{ providerMessageId: string }> {
    const result = await this.client.send(
      new SendEmailCommand({
        FromEmailAddress: from,
        Destination: { ToAddresses: [email.to] },
        ...(configurationSet === null ? {} : { ConfigurationSetName: configurationSet }),
        Content: {
          Simple: {
            Subject: { Data: email.subject, Charset: 'UTF-8' },
            Body: {
              Text: { Data: email.text, Charset: 'UTF-8' },
              ...(email.html === undefined ? {} : { Html: { Data: email.html, Charset: 'UTF-8' } }),
            },
          },
        },
      }),
    );
    if (result.MessageId === undefined) throw new Error('SES returned no MessageId');
    return { providerMessageId: result.MessageId };
  }
}
```

`backend/src/modules/email/transports/index.ts`:

```ts
import type { Config } from '../../../config/env.js';
import type { EmailTransport } from '../types.js';
import { FileEmailTransport } from './file.js';
import { SesEmailTransport } from './ses.js';

export function createEmailTransport(config: Config['email']): EmailTransport {
  return config.transport === 'ses' ? new SesEmailTransport(config.region) : new FileEmailTransport(config.directory);
}
```

- [ ] **Step 4: Wire into the app and `main.ts`**

In `app.ts`: add `emailTransport: EmailTransport` to `AppDeps`; declare `email: EmailSender` on `FastifyInstance`; after the `adminAuth` decoration add `app.decorate('email', new EmailService(deps.prisma, deps.emailTransport, config.email, deps.clock));`.

In `main.ts`: `emailTransport: createEmailTransport(config.email)` in the deps object.

In `test/helpers/app.ts`: default `emailTransport` to `new FileEmailTransport(join(tmpdir(), 'raajjepro-test-mail'))` unless `options.deps.emailTransport` is given.

- [ ] **Step 5: Run the test, lint, typecheck**

Run: `cd backend && npx vitest run && npm run lint && npm run typecheck`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src backend/test
git commit -m "Phase 2 — EmailSender with the suppression list honoured before send, SES and file transports, per-message log"
```

---

### Task 13: SES event webhook — SNS validation, event storage, suppression on bounce/complaint

**Files:**
- Create: `backend/src/modules/email/sns/validator.ts`, `backend/src/modules/email/sns/events.ts`, `backend/src/modules/email/sns/routes.ts`
- Modify: `backend/src/app.ts`, `backend/src/main.ts`, `backend/test/helpers/app.ts`
- Test: `backend/test/ses-events.test.ts`, `backend/test/sns-validator.test.ts`

**Interfaces:**
- Produces:
  ```ts
  interface SnsMessage { Type: 'Notification' | 'SubscriptionConfirmation' | 'UnsubscribeConfirmation'; MessageId: string; TopicArn: string; Message: string; Timestamp: string; SubscribeURL?: string }
  interface SnsMessageValidator { validate(rawBody: string): Promise<SnsMessage> }   // rejects on bad signature/structure
  class SnsValidatorAdapter implements SnsMessageValidator                            // wraps sns-validator
  applySesEvent(prisma, clock, snsMessageId: string, event: SesEvent): Promise<'applied' | 'duplicate'>
  ```
- `AppDeps` gains `snsValidator: SnsMessageValidator`; `POST /v1/webhooks/ses-events`.

- [ ] **Step 1: Write the failing tests**

`backend/test/sns-validator.test.ts` — the adapter's own checks that need no network:

```ts
import { describe, expect, it } from 'vitest';

import { SnsValidatorAdapter } from '../src/modules/email/sns/validator.js';

describe('SnsValidatorAdapter', () => {
  const adapter = new SnsValidatorAdapter();

  it('rejects a body that is not JSON', async () => {
    await expect(adapter.validate('nope')).rejects.toThrow();
  });

  it('rejects a message missing required fields', async () => {
    await expect(adapter.validate(JSON.stringify({ Type: 'Notification' }))).rejects.toThrow();
  });

  it('rejects a signing certificate not hosted by AWS SNS before fetching anything', async () => {
    await expect(
      adapter.validate(
        JSON.stringify({
          Type: 'Notification',
          MessageId: 'm',
          TopicArn: 'arn:aws:sns:ap-south-1:1:t',
          Message: '{}',
          Timestamp: '2026-09-06T00:00:00.000Z',
          SignatureVersion: '1',
          Signature: 'AAAA',
          SigningCertURL: 'https://attacker.example/cert.pem',
        }),
      ),
    ).rejects.toThrow();
  });
});
```

`backend/test/ses-events.test.ts` — the route and the event logic with a fake validator:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { EmailService } from '../src/modules/email/service.js';
import type { SnsMessage, SnsMessageValidator } from '../src/modules/email/sns/validator.js';
import type { EmailTransport } from '../src/modules/email/types.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

const TOPIC = 'arn:aws:sns:ap-south-1:123456789012:raajjepro-ses-events';

/** Accepts anything shaped like an SNS message; the signature itself is sns-validator's job. */
class TrustingValidator implements SnsMessageValidator {
  async validate(raw: string): Promise<SnsMessage> {
    return JSON.parse(raw) as SnsMessage;
  }
}
class RefusingValidator implements SnsMessageValidator {
  async validate(): Promise<SnsMessage> {
    throw new Error('The message signature is invalid.');
  }
}

const transport: EmailTransport = {
  async deliver() {
    return { providerMessageId: `ses-${randomUUID()}` };
  },
};

function sns(type: SnsMessage['Type'], message: unknown, overrides: Partial<SnsMessage> = {}): string {
  return JSON.stringify({
    Type: type,
    MessageId: randomUUID(),
    TopicArn: TOPIC,
    Message: typeof message === 'string' ? message : JSON.stringify(message),
    Timestamp: new Date().toISOString(),
    ...overrides,
  });
}

function sesEvent(eventType: string, providerMessageId: string, to: string, extra: Record<string, unknown> = {}) {
  return {
    eventType,
    mail: { messageId: providerMessageId, timestamp: new Date().toISOString(), destination: [to], source: 'no-reply@raajjepro.test' },
    ...extra,
  };
}

describe.skipIf(databaseUrl === undefined)('POST /v1/webhooks/ses-events', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  let email: EmailService;

  beforeAll(async () => {
    ctx = await buildTestApp({ deps: { emailTransport: transport, snsValidator: new TrustingValidator() } });
    email = new EmailService(
      ctx.prisma,
      transport,
      { transport: 'ses', fromAddress: 'no-reply@raajjepro.test', region: 'ap-south-1', configurationSets: { otp: 'a', notification: 'b', marketing: 'c' }, eventsTopicArn: TOPIC },
      () => new Date(),
    );
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const post = (body: string, headers: Record<string, string> = {}) =>
    ctx.app.inject({ method: 'POST', url: '/v1/webhooks/ses-events', payload: body, headers: { 'content-type': 'text/plain; charset=UTF-8', ...headers } });

  async function sent(to: string) {
    const outcome = await email.send({ channel: 'notification', to, subject: 's', text: 't' });
    const row = await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    return { id: row.id, providerMessageId: row.providerMessageId ?? '' };
  }

  it('rejects a message from an unexpected topic', async () => {
    const res = await post(sns('Notification', sesEvent('Delivery', 'x', 'a@b.test'), { TopicArn: 'arn:aws:sns:ap-south-1:1:other' }));
    expect(res.statusCode).toBe(403);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('UNEXPECTED_SNS_TOPIC');
  });

  it('rejects an invalid signature with 400 and stores nothing', async () => {
    const refusing = await buildTestApp({ deps: { emailTransport: transport, snsValidator: new RefusingValidator() } });
    try {
      const before = await ctx.prisma.emailEvent.count();
      const res = await refusing.app.inject({ method: 'POST', url: '/v1/webhooks/ses-events', payload: sns('Notification', {}), headers: { 'content-type': 'text/plain' } });
      expect(res.statusCode).toBe(400);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('INVALID_SNS_SIGNATURE');
      expect(await ctx.prisma.emailEvent.count()).toBe(before);
    } finally {
      await refusing.app.close();
      await refusing.prisma.$disconnect();
    }
  });

  it('Delivery marks the message delivered; a duplicate SNS id is a no-op', async () => {
    const to = `d-${randomUUID()}@example.test`;
    const m = await sent(to);
    const body = sns('Notification', sesEvent('Delivery', m.providerMessageId, to, { delivery: { timestamp: new Date().toISOString(), recipients: [to] } }));
    expect((await post(body)).statusCode).toBe(200);
    expect((await post(body)).statusCode).toBe(200);
    const row = await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } });
    expect(row.status).toBe('delivered');
    expect(await ctx.prisma.emailEvent.count({ where: { messageId: m.id } })).toBe(1);
  });

  it('a permanent bounce suppresses every bounced recipient; a transient one does not', async () => {
    const to = `hb-${randomUUID()}@example.test`;
    const m = await sent(to);
    await post(sns('Notification', sesEvent('Bounce', m.providerMessageId, to, { bounce: { bounceType: 'Permanent', bounceSubType: 'General', bouncedRecipients: [{ emailAddress: to.toUpperCase() }], timestamp: new Date().toISOString() } })));
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } })).status).toBe('bounced');
    const suppression = await ctx.prisma.emailSuppression.findFirst({ where: { address: to, liftedAt: null } });
    expect(suppression?.reason).toBe('hard_bounce');
    expect(suppression?.sourceEventId).not.toBeNull();

    const soft = `sb-${randomUUID()}@example.test`;
    const m2 = await sent(soft);
    await post(sns('Notification', sesEvent('Bounce', m2.providerMessageId, soft, { bounce: { bounceType: 'Transient', bounceSubType: 'MailboxFull', bouncedRecipients: [{ emailAddress: soft }], timestamp: new Date().toISOString() } })));
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m2.id } })).status).toBe('bounced');
    expect(await ctx.prisma.emailSuppression.count({ where: { address: soft } })).toBe(0);

    // And the suppression is honoured by the sender.
    expect((await email.send({ channel: 'otp', to, subject: 's', text: 't' })).status).toBe('suppressed');
  });

  it('a complaint suppresses and a second complaint does not duplicate the row', async () => {
    const to = `c-${randomUUID()}@example.test`;
    const m = await sent(to);
    const body = () => sns('Notification', sesEvent('Complaint', m.providerMessageId, to, { complaint: { complainedRecipients: [{ emailAddress: to }], timestamp: new Date().toISOString() } }));
    await post(body());
    await post(body());
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } })).status).toBe('complained');
    expect(await ctx.prisma.emailSuppression.count({ where: { address: to, liftedAt: null } })).toBe(1);
  });

  it('an out-of-order Send never moves a terminal status back', async () => {
    const to = `o-${randomUUID()}@example.test`;
    const m = await sent(to);
    await post(sns('Notification', sesEvent('Delivery', m.providerMessageId, to, { delivery: { recipients: [to] } })));
    await post(sns('Notification', sesEvent('Send', m.providerMessageId, to)));
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } })).status).toBe('delivered');
  });

  it('an event for an unknown provider id is stored with no message link', async () => {
    const body = sns('Notification', sesEvent('Reject', `unknown-${randomUUID()}`, 'nobody@example.test', { reject: { reason: 'Bad content' } }));
    expect((await post(body)).statusCode).toBe(200);
    const parsed = JSON.parse(body) as { MessageId: string };
    const event = await ctx.prisma.emailEvent.findUniqueOrThrow({ where: { snsMessageId: parsed.MessageId } });
    expect(event.messageId).toBeNull();
  });

  it('confirms a subscription only for the expected topic, via the SNS host', async () => {
    const calls: string[] = [];
    const confirming = await buildTestApp({
      deps: { emailTransport: transport, snsValidator: new TrustingValidator() },
      routes: (app) => {
        app.decorate('confirmSubscription', async (url: string) => {
          calls.push(url);
        });
      },
    });
    try {
      const good = sns('SubscriptionConfirmation', 'You have chosen to subscribe', { SubscribeURL: 'https://sns.ap-south-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc' });
      expect((await confirming.app.inject({ method: 'POST', url: '/v1/webhooks/ses-events', payload: good, headers: { 'content-type': 'text/plain' } })).statusCode).toBe(200);
      const evil = sns('SubscriptionConfirmation', 'x', { SubscribeURL: 'https://attacker.example/confirm' });
      expect((await confirming.app.inject({ method: 'POST', url: '/v1/webhooks/ses-events', payload: evil, headers: { 'content-type': 'text/plain' } })).statusCode).toBe(400);
      expect(calls).toEqual(['https://sns.ap-south-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc']);
    } finally {
      await confirming.app.close();
      await confirming.prisma.$disconnect();
    }
  });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd backend && npx vitest run test/sns-validator.test.ts test/ses-events.test.ts`
Expected: FAIL — modules not found.

- [ ] **Step 3: Write the validator adapter**

`backend/src/modules/email/sns/validator.ts`:

```ts
import MessageValidator from 'sns-validator';

export interface SnsMessage {
  Type: 'Notification' | 'SubscriptionConfirmation' | 'UnsubscribeConfirmation';
  MessageId: string;
  TopicArn: string;
  Message: string;
  Timestamp: string;
  Subject?: string;
  SubscribeURL?: string;
  Token?: string;
}

/** Verifies an inbound SNS message. Rejects on malformed structure, a non-AWS certificate host, or a bad signature. */
export interface SnsMessageValidator {
  validate(rawBody: string): Promise<SnsMessage>;
}

export const SNS_HOST = /^sns\.[a-zA-Z0-9-]{3,}\.amazonaws\.com$/;

/**
 * `sns-validator` (decision 09): checks the SigningCertURL host against the
 * SNS pattern before fetching, rebuilds the string-to-sign in the documented
 * order, verifies SHA1/SHA256-withRSA per SignatureVersion, caches the cert.
 */
export class SnsValidatorAdapter implements SnsMessageValidator {
  private readonly validator = new MessageValidator(SNS_HOST);

  validate(rawBody: string): Promise<SnsMessage> {
    return new Promise((resolve, reject) => {
      this.validator.validate(rawBody, (error, message) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(message as unknown as SnsMessage);
      });
    });
  }
}

/** True only for an https URL on an SNS host — the rule for SubscribeURL before we GET it. */
export function isSnsUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && SNS_HOST.test(parsed.host);
  } catch {
    return false;
  }
}
```

If `@types/sns-validator` types `validate`'s callback message as `Record<string, unknown>`, the cast above is what bridges it; do not widen `SnsMessage`.

- [ ] **Step 4: Write the event application**

`backend/src/modules/email/sns/events.ts`:

```ts
import { z } from 'zod';

import type { Clock } from '../../../core/clock.js';
import type { EmailMessageStatus, PrismaClient } from '../../../generated/prisma/client.js';
import { normaliseAddress } from '../service.js';

const recipient = z.object({ emailAddress: z.string() });

/** The SES event-publishing JSON, the parts we act on. Unknown fields pass through into `payload`. */
export const sesEventSchema = z.object({
  eventType: z.string(),
  mail: z.object({ messageId: z.string(), timestamp: z.string().optional(), destination: z.array(z.string()).optional() }),
  bounce: z.object({ bounceType: z.string(), bounceSubType: z.string().optional(), bouncedRecipients: z.array(recipient), timestamp: z.string().optional() }).optional(),
  complaint: z.object({ complainedRecipients: z.array(recipient), timestamp: z.string().optional() }).optional(),
});
export type SesEvent = z.infer<typeof sesEventSchema>;

const STATUS_FOR_EVENT: Record<string, EmailMessageStatus | undefined> = {
  Send: 'sent',
  Delivery: 'delivered',
  Bounce: 'bounced',
  Complaint: 'complained',
  Reject: 'rejected',
  DeliveryDelay: 'delivery_delayed',
  'Rendering Failure': 'failed',
  RenderingFailure: 'failed',
};

const TERMINAL: ReadonlySet<EmailMessageStatus> = new Set(['delivered', 'bounced', 'complained', 'rejected']);

/**
 * Stores the event (dedup on the SNS message id — SNS retries), moves the
 * message's status forward, and suppresses recipients of a permanent bounce or
 * a complaint. Transient bounces change status only. A terminal status never
 * moves backwards on a late `Send`.
 */
export async function applySesEvent(prisma: PrismaClient, clock: Clock, snsMessageId: string, event: SesEvent, rawPayload: unknown): Promise<'applied' | 'duplicate'> {
  const now = clock();
  const message = await prisma.emailMessage.findUnique({ where: { providerMessageId: event.mail.messageId } });
  const occurredAt = parseDate(event.bounce?.timestamp ?? event.complaint?.timestamp ?? event.mail.timestamp) ?? now;

  return prisma.$transaction(async (tx) => {
    const inserted = await tx.$queryRaw<{ id: string }[]>`
      INSERT INTO email_event (id, sns_message_id, message_id, provider_message_id, event_type, occurred_at, payload, received_at)
      VALUES (gen_random_uuid(), ${snsMessageId}, ${message?.id ?? null}::uuid, ${event.mail.messageId}, ${event.eventType}, ${occurredAt}, ${JSON.stringify(rawPayload)}::jsonb, ${now})
      ON CONFLICT (sns_message_id) DO NOTHING
      RETURNING id`;
    const eventRow = inserted[0];
    if (eventRow === undefined) return 'duplicate';

    const next = STATUS_FOR_EVENT[event.eventType];
    if (message !== null && next !== undefined) {
      const regress = TERMINAL.has(message.status) && !TERMINAL.has(next);
      if (!regress) {
        await tx.emailMessage.update({ where: { id: message.id }, data: { status: next, lastEventAt: occurredAt } });
      } else {
        await tx.emailMessage.update({ where: { id: message.id }, data: { lastEventAt: occurredAt } });
      }
    }

    const toSuppress: { address: string; reason: 'hard_bounce' | 'complaint' }[] = [];
    if (event.eventType === 'Bounce' && event.bounce?.bounceType === 'Permanent') {
      for (const r of event.bounce.bouncedRecipients) toSuppress.push({ address: normaliseAddress(r.emailAddress), reason: 'hard_bounce' });
    }
    if (event.eventType === 'Complaint' && event.complaint !== undefined) {
      for (const r of event.complaint.complainedRecipients) toSuppress.push({ address: normaliseAddress(r.emailAddress), reason: 'complaint' });
    }
    for (const s of toSuppress) {
      const active = await tx.emailSuppression.findFirst({ where: { address: s.address, liftedAt: null } });
      if (active === null) {
        await tx.emailSuppression.create({ data: { address: s.address, reason: s.reason, sourceEventId: eventRow.id, createdAt: now } });
      }
    }
    return 'applied';
  });
}

function parseDate(value: string | undefined): Date | null {
  if (value === undefined) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}
```

- [ ] **Step 5: Write the route**

First, in `config/env.ts`, give `FileEmailConfig` an `eventsTopicArn: string | null` field populated from the optional `SES_EVENTS_TOPIC_ARN` (so the webhook can be exercised with the file transport, and routes never read `process.env`). In `test/helpers/app.ts`, set `SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:123456789012:raajjepro-ses-events'` in the env passed to `loadConfig`.

`backend/src/modules/email/sns/routes.ts`:

```ts
import type { FastifyInstance } from 'fastify';

import { ok } from '../../../core/envelope.js';
import { AppError, AuthorizationError, ValidationError } from '../../../core/errors.js';
import { applySesEvent, sesEventSchema } from './events.js';
import { isSnsUrl } from './validator.js';

declare module 'fastify' {
  interface FastifyInstance {
    /** GETs an SNS SubscribeURL. Decorated so tests can observe it without network. */
    confirmSubscription: (url: string) => Promise<void>;
  }
}

/** The spec's code for a message that fails SNS structure, host or signature checks. */
export class InvalidSnsSignatureError extends AppError {
  constructor() {
    super(400, 'INVALID_SNS_SIGNATURE', 'SNS signature or structure invalid');
  }
}

/**
 * POST /v1/webhooks/ses-events — the SNS HTTPS subscription for the three SES
 * configuration sets' event destinations. No session: the SNS signature is
 * the authentication. Always 200 once an event is stored so SNS stops
 * retrying; a rejected message gets 400/403 and is not stored.
 */
export async function registerSesEventRoutes(app: FastifyInstance): Promise<void> {
  if (!app.hasDecorator('confirmSubscription')) {
    app.decorate('confirmSubscription', async (url: string) => {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`subscription confirmation returned ${String(res.status)}`);
    });
  }

  await app.register(async (scope) => {
    // SNS posts text/plain. Take the raw string: the validator needs the exact bytes that were signed.
    scope.addContentTypeParser(['text/plain', 'application/json'], { parseAs: 'string' }, (_req, body, done) => {
      done(null, body);
    });

    scope.post('/v1/webhooks/ses-events', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (request, reply) => {
      const raw = typeof request.body === 'string' ? request.body : '';
      let message;
      try {
        message = await app.deps.snsValidator.validate(raw);
      } catch (error) {
        request.log.warn({ err: error instanceof Error ? error.message : 'unknown' }, 'sns message rejected');
        throw new InvalidSnsSignatureError();
      }

      const expectedTopic = app.config.email.eventsTopicArn;
      if (expectedTopic !== null && message.TopicArn !== expectedTopic) {
        throw new AuthorizationError('UNEXPECTED_SNS_TOPIC', 'Notification is not from the configured topic');
      }

      if (message.Type === 'SubscriptionConfirmation') {
        if (message.SubscribeURL === undefined || !isSnsUrl(message.SubscribeURL)) {
          throw new InvalidSnsSignatureError();
        }
        await app.confirmSubscription(message.SubscribeURL);
        request.log.info({ topic: message.TopicArn }, 'sns subscription confirmed');
        return reply.send(ok({ confirmed: true }));
      }
      if (message.Type === 'UnsubscribeConfirmation') {
        request.log.warn({ topic: message.TopicArn }, 'sns unsubscribe confirmation received');
        return reply.send(ok({ acknowledged: true }));
      }

      let payload: unknown;
      try {
        payload = JSON.parse(message.Message);
      } catch {
        throw new ValidationError([{ path: 'Message', message: 'not JSON' }], 'SNS message rejected');
      }
      const parsed = sesEventSchema.safeParse(payload);
      if (!parsed.success) {
        throw new ValidationError([{ path: 'Message', message: 'not an SES event' }], 'SNS message rejected');
      }
      const result = await applySesEvent(app.deps.prisma, app.deps.clock, message.MessageId, parsed.data, payload);
      return reply.send(ok({ result }));
    });
  });
}
```

`SesEmailConfig.eventsTopicArn` is already a string; make `Config['email']['eventsTopicArn']` readable on both variants (`string` on SES, `string | null` on file).

- [ ] **Step 6: Wire it up**

`app.ts`: `snsValidator: SnsMessageValidator` on `AppDeps`; `await registerSesEventRoutes(app);` after `registerAuditRoutes(app);`.
`main.ts`: `snsValidator: new SnsValidatorAdapter()`.
`test/helpers/app.ts`: default `snsValidator` to the `TrustingValidator` stub — move that class from the test into the helper and export it, importing it back into `ses-events.test.ts`. (The `SES_EVENTS_TOPIC_ARN` env and the `FileEmailConfig.eventsTopicArn` field were done in Step 5.)

- [ ] **Step 7: Run the tests, lint, typecheck**

Run: `cd backend && npx vitest run && npm run lint && npm run typecheck`
Expected: all pass. `sns-validator` is CommonJS with `export = MessageValidator` in `@types/sns-validator`; under NodeNext + `esModuleInterop`, `import MessageValidator from 'sns-validator'` is the correct form. If lint flags `@typescript-eslint/no-unsafe-*` on the callback, type the callback parameters explicitly: `(error: Error | null, message?: Record<string, unknown>)`.

- [ ] **Step 8: Commit**

```bash
git add backend/src backend/test
git commit -m "Phase 2 — SES event webhook: SNS validation, stored per-message events, suppression on hard bounce and complaint"
```

---

### Task 14: Documentation, CI boot smoke, decision record, Done-when run

**Files:**
- Create: `docs/api/versioning.md`, `docs/ops/ses-production-access.md`, `docs/decisions/10-phase-2-backend-core.md`
- Modify: `README.md`, `HANDOVER.md`, `.github/workflows/ci.yml`, `backend/CLAUDE.md` (one line: the idempotency header name)

- [ ] **Step 1: Write `docs/api/versioning.md`**

Content, in this order, each a short section: (1) *Rule* — additive-only within `/v1`, citing plan §2 "API versioning"; installed mobile clients cannot be force-updated. (2) *What is breaking* — removing or renaming a field, an error code or a route; changing a field's type or meaning; tightening validation a current client passes; changing a default; making an optional field required; changing an enum value's meaning. (3) *What is additive* — new optional field, new route, new enum value clients are told to treat unknown values of as "other", new error code on a new condition, loosening validation. (4) *Deprecating a field* — keep serving it; document it here with the date and the replacement; the route sets `Deprecation: true` and `Sunset: <date>` headers; monitor use via the request log; remove only in `/v2`. (5) *When a breaking change is unavoidable* — `/v2` ships beside `/v1`; `/v1` stays until Phase 21's product events show no installed client version calling it for 90 days; the Flutter app carries a minimum-supported-version check from Phase 20 onward (a pointer, not a build). (6) *Error codes are API* — list where they live (`core/errors.ts` and each module's service) and that renaming one follows the deprecation process.

- [ ] **Step 2: Write `docs/ops/ses-production-access.md`**

The owner's runbook. Sections: (1) *Why this exists* — plan §0.0 item 8 / §4: the sandbox sends 200/day to verified addresses only; leaving it requires attesting that bounce and complaint handling exists; it does, as of this phase. (2) *Domain identity* — verify the sending domain in SES (ap-south-1 or the region you choose; put the same in `AWS_REGION`); enable Easy DKIM and publish the three CNAMEs; SPF `v=spf1 include:amazonses.com -all`; DMARC `v=DMARC1; p=quarantine; rua=mailto:<address>`; custom MAIL FROM subdomain. (3) *Three configuration sets* — `raajjepro-otp`, `raajjepro-notification`, `raajjepro-marketing`; the names go in the three `SES_CONFIGURATION_SET_*` variables. (4) *One SNS topic* — `raajjepro-ses-events`; its ARN goes in `SES_EVENTS_TOPIC_ARN`. (5) *Event destinations* — on each configuration set, an SNS destination to that topic publishing Send, Delivery, Bounce, Complaint, Reject, DeliveryDelay, Rendering Failure. (6) *HTTPS subscription* — subscribe the topic to `https://<api-host>/v1/webhooks/ses-events`; the API confirms it automatically and logs `sns subscription confirmed`; verify with `SELECT count(*) FROM email_event`. (7) *Production access request* — Service Quotas → SES → "Request production access"; mail type Transactional; website URL; use-case text (draft it: marketplace transactional email — OTP, booking notifications, admin alerts; volumes; recipients are registered users who requested an account; bounces and complaints are consumed through an SNS event destination into a suppression list checked before every send; marketing is opt-in and on a separate configuration set). (8) *After approval* — set `EMAIL_TRANSPORT=ses` in the deployment; send one OTP-channel test to a real mailbox; confirm the `Delivery` event row appears. (9) *What is unverified until then* — a real send, a real SNS delivery, the handshake.

- [ ] **Step 3: Write `docs/decisions/10-phase-2-backend-core.md`**

Same shape as `08-phase-1-design-system.md`: status line; the eight decisions (link the spec, do not restate the plan); a "What was built" table (plan item → module → file); the two deliberate deviations from the design sketch during build, if any (write them honestly — an empty section is fine); what is unverified (SES/SNS live path); what Phase 3 must confirm (the `anon:<ip>` idempotency subject for registration; `recipientUserId` on `OutboundEmail`; `requireEmailVerified` as a `BusinessRuleError`); the SES production access request as the owner's next step.

- [ ] **Step 4: Update README, HANDOVER, backend/CLAUDE.md**

README: "Phases 0, 1 and 2 are built"; in *Running locally* add `npm run dev` (now a server on :3000), `curl localhost:3000/v1/health`, `npm run admin:create -- --email …`; in *Idempotency keys* replace "(the transport — header or body field — is fixed in Phase 2 …)" with "the `Idempotency-Key` request header (fixed in Phase 2)"; stack row: Fastify 5 present. HANDOVER: "Phases 0–2 are built" paragraph; the outstanding-items list's SES bullet becomes "**Request SES production access now** — `docs/ops/ses-production-access.md` is the runbook; Phase 3 waits on it"; `Phase 3 is next: /phase-3`. `backend/CLAUDE.md`: in the idempotency line, name the header.

- [ ] **Step 5: CI boot smoke**

In `.github/workflows/ci.yml`, replace the "Boot and confirm the job runner fires" step with:

```yaml
      - name: Boot the server, check /v1/health, confirm the job runner fires
        env:
          ADMIN_TOTP_ENCRYPTION_KEY: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
          EMAIL_FROM_ADDRESS: ci@raajjepro.local
          PORT: 3000
        run: |
          npm start &
          for attempt in $(seq 1 20); do
            if curl -fsS localhost:3000/v1/health >/dev/null; then break; fi
            sleep 1
          done
          curl -fsS localhost:3000/v1/health | tee health.json
          kill %1
          for attempt in $(seq 1 14); do
            if npm run --silent jobs:status; then exit 0; fi
            sleep 5
          done
          echo "job runner never fired"; exit 1
```

Add the same two env vars (`ADMIN_TOTP_ENCRYPTION_KEY`, `EMAIL_FROM_ADDRESS`) to the backend job's `env:` block so `npm test` has them.

- [ ] **Step 6: Run the Done-when list end to end**

```bash
cd backend && npm run lint && npm run typecheck && npm run build && npx vitest run
cd .. && scripts/verify.sh
```

Expected: everything green. Then the manual pass against a running server (`npm run dev` in one terminal):

| Done-when | Command | Expect |
|---|---|---|
| health 200 | `curl -i localhost:3000/v1/health` | 200, `x-request-id`, `"status":"ok"` |
| malformed → envelope | `curl -i -X POST localhost:3000/v1/admin/auth/login -H 'x-requested-with: RaajjePro-Admin' -H 'content-type: application/json' -d '{'` | 400 `MALFORMED_BODY` with `requestId` |
| idempotent replay | covered by `test/idempotency.test.ts` (no creation POST exists yet outside tests — Phase 3's registration is the first) | test green |
| rate limits | `for i in $(seq 1 11); do curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:3000/v1/admin/auth/login -H 'x-requested-with: RaajjePro-Admin' -H 'content-type: application/json' -d '{"email":"a@b.c","password":"xxxxxxxxxxxx"}'; done` | ten `401`, then `429` |
| audit log | `npm run admin:create`, log in with a REST client, enrol with an authenticator app, `DELETE /sessions/:id` with a reason, `GET /v1/admin/audit-log?action=admin.session.revoked` | the entry, with reason |

- [ ] **Step 7: Commit and push**

```bash
git add docs README.md HANDOVER.md .github/workflows/ci.yml backend/CLAUDE.md
git commit -m "Phase 2 — versioning policy, SES production-access runbook, decision record, CI boot smoke"
git push
```

---

## Self-review against the spec

- §1 server shape → Tasks 2, 3, 9 (`buildApp`, plugin order). ✔
- §2 envelope/errors/logging/config → Tasks 1, 2. `MALFORMED_BODY`, `VALIDATION_FAILED` details shape, request-id rule, redaction list all present. ✔
- §3 rate limiting (Postgres store, reuse, override, 429 shape) → Task 5; idempotency (header, statuses, replay header, abandoned on 5xx/429, `anon:<ip>`) → Task 6. ✔
- §4 admin identity: tables → Task 4; crypto/login/sessions → Task 8; plugin/guards/CSRF/CORS/routes → Task 9; MFA/recovery/reauth → Task 10; audit route + CLI → Task 11. `requireRecentReauth` exported for Phase 10a. Sessions listed/revoked for self only. ✔
- §5 email: interface, suppression-before-send, transports, log → Task 12; webhook, dedup, suppression on Permanent bounce/Complaint, no regression, SubscribeURL host rule, topic check → Task 13. ✔
- §6 health 503 → Task 3; docs, CI → Task 14. §7 migration edits → Task 4. §8 Done-when → Tasks 2, 3, 5, 6, 11 tests + Task 14 manual table. ✔
- Type consistency checked: `AdminPrincipal` fields (`kind,id,sessionId,mfaVerified,totpEnrolled,reauthenticatedAt`) match between Tasks 5, 6, 8, 9, 10; `RequestMeta`, `requestMeta()`; `AuditService.record(db, entry)`; `EmailTransport.deliver(email, from, configurationSet)`; `SnsMessageValidator.validate(raw)`; `buildTestApp` options used in Tasks 5–13.
- Known seam for the executor: Task 13 Step 5 asks for the `INVALID_SNS_SIGNATURE` code and the `FileEmailConfig.eventsTopicArn` field — both are stated explicitly, do them as written rather than leaving the first draft.

