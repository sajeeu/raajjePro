# Phase 3 — Identity & Authentication (backend): implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user identity to the Phase 2 API — register, login, JWT access + rotated per-device refresh tokens, email OTP with both send limits, the `requireEmailVerified` guard, account settings (password, email, phone, sessions, export, deletion), and the anonymisation job — so every backend line of §Phase 3's Done-when passes against `EMAIL_TRANSPORT=file`.

**Architecture:** A `modules/auth` domain (users, sessions, refresh tokens, OTP, guards) and a `modules/account` domain (settings, export, deletion, anonymisation) plug into the Phase 2 `buildApp` beside the admin modules. A `plugins/user-auth.ts` onRequest hook turns a bearer JWT into `request.principal` by verifying the signature and then loading the session row, so revocation is immediate. Rate-limit tiers, idempotency and audit are the Phase 2 mechanisms, reused. The first Node-side job runner (`jobs/runner.ts`) runs anonymisation under a Postgres advisory lock and writes the Phase 0 heartbeat row.

**Tech Stack:** Node 22 · TypeScript 6 (strict, `exactOptionalPropertyTypes`, NodeNext ESM — imports end in `.js`) · Fastify 5.12 · `fastify-type-provider-zod` 7 + Zod 4 · Prisma 7 (`prisma-client` generator, `@prisma/adapter-pg`) · `@node-rs/argon2` 2 · **`jose` 6.2.12** (new) · Vitest 5.

**Spec:** `docs/superpowers/specs/2026-09-06-phase-3-identity-design.md` — read it first; this plan argues from it. The plan `01_Development_Plan_v5.md` §Phase 3 is the acceptance criteria.

## Global Constraints

- Plan §Phase 3 and §1e govern; `CLAUDE.md` invariants apply throughout (1a, 1c "no SMS", 4, 8, 10). `archive/` is never read.
- UUID primary keys (`String @id @default(uuid()) @db.Uuid`), `snake_case` columns via `@map`/`@@map`, `Timestamptz(6)` timestamps. **No row is ever `DELETE`d**; `User.status` is the soft-delete field.
- Envelope: success `{ data, meta? }`; error `{ error: { code, message, details? }, requestId }`. Error codes are exactly those in the spec's §7 table — they are API surface. New codes: `ACCESS_TOKEN_EXPIRED`, `REFRESH_TOKEN_ROTATED` (401); `EMAIL_IN_USE`, `PHONE_IN_USE` (409); `EMAIL_NOT_VERIFIED`, `ACCOUNT_FROZEN`, `EMAIL_ALREADY_VERIFIED`, `EMAIL_UNCHANGED`, `OTP_EXPIRED`, `OTP_INCORRECT`, `OTP_INVALIDATED`, `SOCIAL_AUTH_UNAVAILABLE` (422); `OTP_RATE_LIMITED` (429).
- Tokens: access JWT HS256, `iss` `raajjepro`, `aud` `raajjepro-app`, claims `sub` + `sid`, `AUTH_ACCESS_TOKEN_MINUTES=15`. Refresh: 32 random bytes base64url, stored sha256, one row per issue, `AUTH_REFRESH_TOKEN_DAYS=30` sliding, reuse grace **30 s** (constant `REFRESH_REUSE_GRACE_MS`).
- OTP: six digits via `crypto.randomInt(0, 1_000_000)` zero-padded; `AUTH_OTP_EXPIRY_MINUTES=10`; `codeHash = sha256(`${id}|${code}`)`; limits **3 per address per 15 min** and **5 per account per hour** (constants); **5 attempts** invalidate every live code for the purpose.
- Phone: `dialCode` matches `^\+[1-9]\d{0,3}$`; national digits after stripping spaces, dashes, dots are 6–15; dial code digits + national digits ≤ 15. Stored `phoneE164` (+ `phoneDialCode` so the DTO can split it back). Phone is **never** verified and **never** in any response but the holder's own `me` and export.
- Password: 8–512 characters, argon2id via `modules/admin-auth/crypto.ts` (`hashPassword`, `verifyPassword`, `DUMMY_PASSWORD_HASH`, `hashToken`, `newSessionToken`) — imported, not copied.
- Every mutating handler starts with a comment naming who may call it. Business logic lives in services; routes validate and delegate. Every state change writes an audit row in the same transaction where one exists.
- Logging redaction list gains `refreshToken`, `accessToken`, `newEmail`, `fullName`, `phoneE164`, `number`. Bodies are never logged.
- Lint stays clean under the existing `eslint.config.js` (`strictTypeChecked`, `no-floating-promises`, `consistent-type-imports`). Run `npm run lint && npm run typecheck` before every commit. Dependencies pinned exactly (`.npmrc` has `save-exact=true`).
- Commits: no AI attribution trailers, imperative summary line, every task ends in a commit, push at the end of the phase (memory: push after committing).
- Tests run against the Docker database (`docker compose up -d`; `TEST_DATABASE_URL` in `backend/.env` points at `raajjepro_test`; migrate it with `DATABASE_URL="$TEST_DATABASE_URL" npm run db:deploy`). They `describe.skipIf(databaseUrl === undefined)`. Isolation is by uniqueness — `randomUUID()` in emails, phones and `freshIp()` — never by truncation. Time is moved with `controllableClock`, never by waiting.

## File structure

```
backend/src/
  config/env.ts                       + AUTH_* variables → config.auth (Task 1)
  core/principal.ts                   + UserPrincipal, Principal union (Task 2)
  core/logging.ts                     + six redacted keys (Task 9)
  app.ts                              + user-auth plugin, auth/account modules, runner deps (Tasks 2–8)
  main.ts                             + starts the JobRunner (Task 8)
  plugins/user-auth.ts                bearer JWT → request.principal (Task 3)
  modules/auth/tokens.ts              signAccessToken, verifyAccessToken, newRefreshToken (Task 2)
  modules/auth/guards.ts              userOf, requireAuth, requireEmailVerified, requireActiveAccount (Task 2)
  modules/auth/phone.ts               normalisePhone (Task 4)
  modules/auth/repository.ts          UserRepository (Tasks 3–5, extended)
  modules/auth/dto.ts                 userDto, sessionDto (Task 3)
  modules/auth/service.ts             AuthService — sessions, refresh, login, register (Tasks 3, 5)
  modules/auth/otp.ts                 OtpService — send with limits, confirm, invalidate (Task 4)
  modules/auth/social.ts              SocialAuthProvider, SocialAuthRegistry, four stubs (Task 5)
  modules/auth/schema.ts              Zod schemas (Tasks 3–5)
  modules/auth/routes.ts              /v1/auth/* (Tasks 3–5)
  modules/account/service.ts          AccountService — password, email, phone, export, deletion (Tasks 6–7)
  modules/account/export.ts           ExportContributors registry (Task 7)
  modules/account/anonymise.ts        AnonymisationHooks, AccountAnonymiser, DeletionBlocker (Task 8)
  modules/account/schema.ts, routes.ts  /v1/users/me/* (Tasks 6–7)
  jobs/runner.ts                      JobRunner (Task 8)
  jobs/anonymise-accounts.ts          the job definition (Task 8)
backend/prisma/schema.prisma + migrations/<ts>_phase3_identity/ (Task 1)
backend/test/
  helpers/app.ts                      + auth options, AUTH_JWT_SECRET default, deletionBlocker (Task 1)
  helpers/users.ts                    RecordingEmailTransport, createUser, registerUser, otpFrom, bearer (Task 3, extended Task 5)
  <one test file per task, named in each task>
docs/decisions/12-phase-3-identity.md · docs/deferred-verification.md rows · backend/.env.example · README.md · HANDOVER.md · .github/workflows/ci.yml (Task 9)
```

---

### Task 1: Config, `jose`, Prisma schema and the `phase3_identity` migration

**Files:**
- Modify: `backend/package.json` (add `jose`)
- Modify: `backend/src/config/env.ts`
- Modify: `backend/.env.example`, `backend/.env` (add `AUTH_JWT_SECRET`)
- Modify: `backend/prisma/schema.prisma`
- Create: `backend/prisma/migrations/<timestamp>_phase3_identity/migration.sql` (generated)
- Modify: `backend/test/helpers/app.ts`
- Test: `backend/test/config.test.ts`, `backend/test/schema-phase3.test.ts`

**Interfaces:**
- Produces: `config.auth: { jwtSecret: Buffer; accessTokenMinutes: number; refreshTokenDays: number; otpExpiryMinutes: number }`; Prisma models `User`, `ProviderProfile`, `UserSession`, `RefreshToken`, `EmailOtp`; enums `UserStatus`, `VerificationTier`, `VerificationStatus`, `UserSessionRevokedReason`, `OtpPurpose`; `AuditActorType.user`; `TestAppOptions.accessTokenMinutes | refreshTokenDays | otpExpiryMinutes`.

- [ ] **Step 1: Install `jose`**

```bash
cd backend && npm install jose@6.2.12
```

- [ ] **Step 2: Write the failing config tests**

Append to `backend/test/config.test.ts` inside the `describe('loadConfig')` block. Also add `AUTH_JWT_SECRET: Buffer.alloc(32, 9).toString('base64'),` to the `minimal` object at the top of the file, and add these assertions to the existing `'applies the documented defaults'` test:

```ts
    expect(config.auth.accessTokenMinutes).toBe(15);
    expect(config.auth.refreshTokenDays).toBe(30);
    expect(config.auth.otpExpiryMinutes).toBe(10);
    expect(config.auth.jwtSecret).toEqual(Buffer.alloc(32, 9));
```

New tests:

```ts
  it('requires AUTH_JWT_SECRET and rejects one that is not 32 bytes', () => {
    const { AUTH_JWT_SECRET: _omit, ...withoutSecret } = minimal;
    expect(() => loadConfig(withoutSecret)).toThrow(/AUTH_JWT_SECRET/);
    expect(() =>
      loadConfig({ ...minimal, AUTH_JWT_SECRET: Buffer.alloc(16).toString('base64') }),
    ).toThrow(/AUTH_JWT_SECRET/);
  });

  it('refuses a JWT secret equal to the TOTP encryption key', () => {
    const same = Buffer.alloc(32, 7).toString('base64');
    expect(() =>
      loadConfig({ ...minimal, ADMIN_TOTP_ENCRYPTION_KEY: same, AUTH_JWT_SECRET: same }),
    ).toThrow(/AUTH_JWT_SECRET: must differ/);
  });
```

Also update the existing `'names every missing or malformed variable in one error'` test to expect `AUTH_JWT_SECRET` in the joined issues.

- [ ] **Step 3: Run to verify failure**

Run: `cd backend && npx vitest run test/config.test.ts`
Expected: FAIL — `config.auth` undefined / `AUTH_JWT_SECRET` not reported.

- [ ] **Step 4: Extend `config/env.ts`**

In the Zod `schema` object add, after the `RATE_LIMIT_*` lines:

```ts
  AUTH_JWT_SECRET: base32Key,
  AUTH_ACCESS_TOKEN_MINUTES: int(15),
  AUTH_REFRESH_TOKEN_DAYS: int(30),
  AUTH_OTP_EXPIRY_MINUTES: int(10),
```

Add to the `Config` interface:

```ts
  auth: {
    /** HS256 key for user access tokens. 32 bytes; must differ from the TOTP key. */
    jwtSecret: Buffer;
    accessTokenMinutes: number;
    refreshTokenDays: number;
    otpExpiryMinutes: number;
  };
```

In the business-rule block (before `if (issues.length > 0)`), add:

```ts
  if (
    cleaned.AUTH_JWT_SECRET !== undefined &&
    cleaned.AUTH_JWT_SECRET === cleaned.ADMIN_TOTP_ENCRYPTION_KEY
  ) {
    issues.push('AUTH_JWT_SECRET: must differ from ADMIN_TOTP_ENCRYPTION_KEY');
  }
```

In the returned object add:

```ts
    auth: {
      jwtSecret: v.AUTH_JWT_SECRET,
      accessTokenMinutes: v.AUTH_ACCESS_TOKEN_MINUTES,
      refreshTokenDays: v.AUTH_REFRESH_TOKEN_DAYS,
      otpExpiryMinutes: v.AUTH_OTP_EXPIRY_MINUTES,
    },
```

- [ ] **Step 5: `.env.example` and `.env`**

Append to `backend/.env.example` after the rate-limiting block:

```
# --- User authentication (Phase 3) ------------------------------------------
# 32 random bytes, base64. Signs user access tokens (HS256). Must differ from
# ADMIN_TOTP_ENCRYPTION_KEY. Generate with:  openssl rand -base64 32
# The value below is for the local container only.
AUTH_JWT_SECRET=AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=
# Access tokens are short-lived; the client refreshes silently. Refresh tokens
# rotate on every use and slide forward this many days (plan §2: per-device).
AUTH_ACCESS_TOKEN_MINUTES=15
AUTH_REFRESH_TOKEN_DAYS=30
# How long an emailed verification code stays valid. The send and attempt
# limits (3/address/15 min, 5/account/hour, 5 attempts) are plan-pinned
# constants in code, not configuration.
AUTH_OTP_EXPIRY_MINUTES=10
```

Add the same four lines to `backend/.env` (gitignored).

- [ ] **Step 6: Test helper defaults**

In `backend/test/helpers/app.ts`, extend `TestAppOptions` with `accessTokenMinutes?: number; refreshTokenDays?: number; otpExpiryMinutes?: number;`. In `testConfig`, pass `AUTH_JWT_SECRET: process.env.AUTH_JWT_SECRET ?? Buffer.alloc(32, 2).toString('base64'),` to `loadConfig` and add to the returned object:

```ts
    auth: {
      ...base.auth,
      accessTokenMinutes: options.accessTokenMinutes ?? base.auth.accessTokenMinutes,
      refreshTokenDays: options.refreshTokenDays ?? base.auth.refreshTokenDays,
      otpExpiryMinutes: options.otpExpiryMinutes ?? base.auth.otpExpiryMinutes,
    },
```

- [ ] **Step 7: Run config tests**

Run: `npx vitest run test/config.test.ts` — Expected: PASS.

- [ ] **Step 8: Prisma schema**

Append to `backend/prisma/schema.prisma`. Also change `enum AuditActorType` to add `user` between `admin` and `system`.

```prisma
// ---------------------------------------------------------------------------
// Phase 3 — identity & authentication
// ---------------------------------------------------------------------------

enum UserStatus {
  active
  frozen
  anonymised

  @@map("user_status")
}

/// A customer or provider account (plan §Phase 3). `status` is the soft-delete
/// field: `frozen` after a deletion request, `anonymised` when the job has
/// replaced name, email and phone. `phoneE164` is deliberately NOT unique —
/// exclusivity begins at Bronze (§0.0 item 8a) and is enforced in the service.
model User {
  id                  String     @id @default(uuid()) @db.Uuid
  email               String     @unique
  emailVerifiedAt     DateTime?  @map("email_verified_at") @db.Timestamptz(6)
  passwordHash        String     @map("password_hash")
  fullName            String     @map("full_name")
  phoneE164           String?    @map("phone_e164")
  phoneDialCode       String?    @map("phone_dial_code")
  status              UserStatus @default(active)
  termsAcceptedAt     DateTime   @map("terms_accepted_at") @db.Timestamptz(6)
  deletionRequestedAt DateTime?  @map("deletion_requested_at") @db.Timestamptz(6)
  deletionDeadlineAt  DateTime?  @map("deletion_deadline_at") @db.Timestamptz(6)
  anonymisedAt        DateTime?  @map("anonymised_at") @db.Timestamptz(6)
  passwordChangedAt   DateTime   @default(now()) @map("password_changed_at") @db.Timestamptz(6)
  createdAt           DateTime   @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt           DateTime   @updatedAt @map("updated_at") @db.Timestamptz(6)

  providerProfile ProviderProfile?
  sessions        UserSession[]
  otps            EmailOtp[]

  @@index([phoneE164])
  @@index([status, deletionDeadlineAt])
  @@map("app_user")
}

enum VerificationTier {
  none
  bronze
  silver
  gold

  @@map("verification_tier")
}

enum VerificationStatus {
  unverified
  pending
  verified

  @@map("verification_status")
}

/// The provider half of an account. Phase 3 creates it with only the columns
/// Phase 3 reads — Business/Trade Name from the Register provider variant,
/// and the tier the Bronze-uniqueness rule checks. Phase 5 adds the rest
/// additively (plan §Phase 5). `verificationTier` is what the badge renders;
/// `verificationStatus` is only the review state of a pending submission.
model ProviderProfile {
  id                 String             @id @default(uuid()) @db.Uuid
  userId             String             @unique @map("user_id") @db.Uuid
  user               User               @relation(fields: [userId], references: [id])
  businessName       String?            @map("business_name")
  verificationTier   VerificationTier   @default(none) @map("verification_tier")
  verificationStatus VerificationStatus @default(unverified) @map("verification_status")
  createdAt          DateTime           @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt          DateTime           @updatedAt @map("updated_at") @db.Timestamptz(6)

  @@map("provider_profile")
}

enum UserSessionRevokedReason {
  logout
  revoked_by_user
  refresh_expired
  refresh_reuse
  password_change
  email_change
  anonymised

  @@map("user_session_revoked_reason")
}

/// One per signed-in device. The credential is the RefreshToken rows below;
/// the access JWT carries this row's id as `sid` so revocation is immediate.
model UserSession {
  id            String                    @id @default(uuid()) @db.Uuid
  userId        String                    @map("user_id") @db.Uuid
  user          User                      @relation(fields: [userId], references: [id])
  deviceName    String                    @map("device_name")
  ipAddress     String                    @map("ip_address")
  userAgent     String                    @map("user_agent")
  createdAt     DateTime                  @default(now()) @map("created_at") @db.Timestamptz(6)
  lastSeenAt    DateTime                  @map("last_seen_at") @db.Timestamptz(6)
  revokedAt     DateTime?                 @map("revoked_at") @db.Timestamptz(6)
  revokedReason UserSessionRevokedReason? @map("revoked_reason")

  refreshTokens RefreshToken[]

  @@index([userId, revokedAt])
  @@map("user_session")
}

/// One row per refresh token ever issued; the live one for a session has
/// rotated_at NULL. Keeping rotated rows is what lets a replayed old token be
/// told apart from garbage (spec §3).
model RefreshToken {
  id           String      @id @default(uuid()) @db.Uuid
  sessionId    String      @map("session_id") @db.Uuid
  session      UserSession @relation(fields: [sessionId], references: [id])
  tokenHash    String      @unique @map("token_hash")
  createdAt    DateTime    @default(now()) @map("created_at") @db.Timestamptz(6)
  expiresAt    DateTime    @map("expires_at") @db.Timestamptz(6)
  rotatedAt    DateTime?   @map("rotated_at") @db.Timestamptz(6)
  replacedById String?     @map("replaced_by_id") @db.Uuid

  @@index([sessionId, rotatedAt])
  @@map("refresh_token")
}

enum OtpPurpose {
  verify_email
  change_email

  @@map("otp_purpose")
}

/// An emailed six-digit code. Never deleted: the two indexes are the two
/// send-limit counts (plan §Phase 3: 3/address/15 min AND 5/account/hour).
model EmailOtp {
  id             String        @id @db.Uuid
  userId         String        @map("user_id") @db.Uuid
  user           User          @relation(fields: [userId], references: [id])
  purpose        OtpPurpose
  targetEmail    String        @map("target_email")
  codeHash       String        @map("code_hash")
  attempts       Int           @default(0)
  expiresAt      DateTime      @map("expires_at") @db.Timestamptz(6)
  consumedAt     DateTime?     @map("consumed_at") @db.Timestamptz(6)
  invalidatedAt  DateTime?     @map("invalidated_at") @db.Timestamptz(6)
  emailMessageId String?       @map("email_message_id") @db.Uuid
  emailMessage   EmailMessage? @relation(fields: [emailMessageId], references: [id])
  createdAt      DateTime      @default(now()) @map("created_at") @db.Timestamptz(6)

  @@index([userId, purpose, createdAt])
  @@index([targetEmail, createdAt])
  @@map("email_otp")
}
```

`EmailOtp.id` has no `@default(uuid())` on purpose: the service generates the id first so the code hash can be keyed by it. Add `otps EmailOtp[]` to the `EmailMessage` model's relation list.

- [ ] **Step 9: Generate the migration and apply it to both databases**

```bash
cd backend
npx prisma migrate dev --name phase3_identity        # application database, generates SQL + client
DATABASE_URL="$(grep ^TEST_DATABASE_URL .env | cut -d= -f2-)" npm run db:deploy
```

Open the generated `migration.sql` and confirm it contains `ALTER TYPE "audit_actor_type" ADD VALUE 'user';` and `CREATE TABLE "app_user"`. Do not hand-edit it.

- [ ] **Step 10: Write the schema test**

`backend/test/schema-phase3.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('phase 3 schema', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  const user = (email: string, phone: string | null) => ({
    email,
    passwordHash: 'x',
    fullName: 'Test',
    phoneE164: phone,
    phoneDialCode: phone === null ? null : '+960',
    termsAcceptedAt: new Date(),
  });

  it('email is unique at the database; phone is not (uniqueness begins at Bronze, §0.0 item 8a)', async () => {
    const email = `u-${randomUUID()}@example.test`;
    const phone = `+960${String(Math.floor(Math.random() * 9_000_000) + 1_000_000)}`;
    await prisma.user.create({ data: user(email, phone) });
    await expect(prisma.user.create({ data: user(email, null) })).rejects.toThrow();
    await expect(
      prisma.user.create({ data: user(`u-${randomUUID()}@example.test`, phone) }),
    ).resolves.toBeDefined();
  });

  it('a provider profile defaults to tier none and status unverified, one per user', async () => {
    const u = await prisma.user.create({ data: user(`u-${randomUUID()}@example.test`, null) });
    const profile = await prisma.providerProfile.create({ data: { userId: u.id } });
    expect(profile.verificationTier).toBe('none');
    expect(profile.verificationStatus).toBe('unverified');
    await expect(prisma.providerProfile.create({ data: { userId: u.id } })).rejects.toThrow();
  });

  it('the audit actor type accepts user', async () => {
    const row = await prisma.auditLogEntry.create({
      data: {
        actorType: 'user',
        actorId: randomUUID(),
        action: 'test.user_actor',
        targetType: 'test',
        targetId: randomUUID(),
        reason: 'schema test',
      },
    });
    expect(row.actorType).toBe('user');
  });
});
```

- [ ] **Step 11: Run all tests, lint, typecheck**

Run: `npm test && npm run lint && npm run typecheck` — Expected: all PASS (the Phase 2 suite still green; the new file passes).

- [ ] **Step 12: Commit**

```bash
git add backend/package.json backend/package-lock.json backend/src/config/env.ts backend/.env.example backend/prisma backend/test/helpers/app.ts backend/test/config.test.ts backend/test/schema-phase3.test.ts
git commit -m "Phase 3 schema and config: users, sessions, refresh tokens, OTPs, minimal provider profile"
```

---

### Task 2: Access tokens, `UserPrincipal`, and the three guards

**Files:**
- Create: `backend/src/modules/auth/tokens.ts`
- Modify: `backend/src/core/principal.ts`
- Create: `backend/src/modules/auth/guards.ts`
- Test: `backend/test/auth-tokens.test.ts`, `backend/test/auth-guards.test.ts`

**Interfaces:**
- Consumes: `config.auth.jwtSecret` (Task 1); `newSessionToken`, `hashToken` from `modules/admin-auth/crypto.ts`.
- Produces:
  - `signAccessToken(input: { userId: string; sessionId: string; now: Date; ttlMinutes: number; secret: Buffer }): Promise<{ token: string; expiresAt: Date }>`
  - `verifyAccessToken(token: string, secret: Buffer, now: Date): Promise<{ ok: true; userId: string; sessionId: string } | { ok: false; reason: 'expired' | 'invalid' }>`
  - `newRefreshToken(): string` (alias of `newSessionToken`) and re-export `hashToken`.
  - `UserPrincipal = { kind: 'user'; id: string; sessionId: string; emailVerified: boolean; status: 'active' | 'frozen' }`; `Principal = AdminPrincipal | UserPrincipal`; `FastifyRequest.sessionRejection` widened to `'UNAUTHENTICATED' | 'SESSION_EXPIRED' | 'ACCESS_TOKEN_EXPIRED'`.
  - `userOf(request): UserPrincipal`, `requireAuth`, `requireEmailVerified`, `requireActiveAccount` (all `async (request, reply) => Promise<void>`).

- [ ] **Step 1: Write the failing token tests**

`backend/test/auth-tokens.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { newRefreshToken, signAccessToken, verifyAccessToken } from '../src/modules/auth/tokens.js';

const secret = Buffer.alloc(32, 5);
const other = Buffer.alloc(32, 6);
const now = new Date('2026-09-06T10:00:00Z');

describe('access tokens', () => {
  it('signs and verifies a token carrying the user and session ids', async () => {
    const { token, expiresAt } = await signAccessToken({
      userId: '11111111-1111-4111-8111-111111111111',
      sessionId: '22222222-2222-4222-8222-222222222222',
      now,
      ttlMinutes: 15,
      secret,
    });
    expect(expiresAt.toISOString()).toBe('2026-09-06T10:15:00.000Z');
    const result = await verifyAccessToken(token, secret, now);
    expect(result).toEqual({
      ok: true,
      userId: '11111111-1111-4111-8111-111111111111',
      sessionId: '22222222-2222-4222-8222-222222222222',
    });
  });

  it('reports expiry as expired, not invalid, so the client knows to refresh', async () => {
    const { token } = await signAccessToken({ userId: 'u', sessionId: 's', now, ttlMinutes: 15, secret });
    const late = new Date(now.getTime() + 15 * 60_000 + 1_000);
    expect(await verifyAccessToken(token, secret, late)).toEqual({ ok: false, reason: 'expired' });
  });

  it('rejects a wrong key, a tampered payload and garbage as invalid', async () => {
    const { token } = await signAccessToken({ userId: 'u', sessionId: 's', now, ttlMinutes: 15, secret });
    expect(await verifyAccessToken(token, other, now)).toEqual({ ok: false, reason: 'invalid' });
    const [h, p, s] = token.split('.');
    const tampered = `${h}.${Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(p ?? '', 'base64url').toString()), sid: 'x' })).toString('base64url')}.${s}`;
    expect(await verifyAccessToken(tampered, secret, now)).toEqual({ ok: false, reason: 'invalid' });
    expect(await verifyAccessToken('not.a.jwt', secret, now)).toEqual({ ok: false, reason: 'invalid' });
    expect(await verifyAccessToken('', secret, now)).toEqual({ ok: false, reason: 'invalid' });
  });

  it('rejects a token with the wrong audience or issuer', async () => {
    const { SignJWT } = await import('jose');
    const foreign = await new SignJWT({ sid: 's' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('u')
      .setIssuer('someone-else')
      .setAudience('raajjepro-app')
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(Math.floor(now.getTime() / 1000) + 900)
      .sign(secret);
    expect(await verifyAccessToken(foreign, secret, now)).toEqual({ ok: false, reason: 'invalid' });
  });

  it('refresh tokens are 32 random bytes, base64url, and never repeat', () => {
    const a = newRefreshToken();
    const b = newRefreshToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a).not.toBe(b);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run test/auth-tokens.test.ts` — Expected: FAIL, module not found.

- [ ] **Step 3: Implement `tokens.ts`**

```ts
import { errors, jwtVerify, SignJWT } from 'jose';

import { hashToken, newSessionToken } from '../admin-auth/crypto.js';

export const ACCESS_TOKEN_ISSUER = 'raajjepro';
export const ACCESS_TOKEN_AUDIENCE = 'raajjepro-app';

export interface AccessTokenClaims {
  userId: string;
  sessionId: string;
}

export type VerifiedAccessToken =
  | ({ ok: true } & AccessTokenClaims)
  | { ok: false; reason: 'expired' | 'invalid' };

/**
 * User access tokens (plan §2: JWT access + refresh rotation). HS256 under
 * AUTH_JWT_SECRET; `sub` is the user id and `sid` the session id, so the
 * auth plugin can load the session row and honour a revocation immediately
 * rather than at expiry. Nothing mutable (email, verified flag, status) is
 * carried in the token — it is read from the row on every request.
 */
export async function signAccessToken(input: {
  userId: string;
  sessionId: string;
  now: Date;
  ttlMinutes: number;
  secret: Buffer;
}): Promise<{ token: string; expiresAt: Date }> {
  const issuedAt = Math.floor(input.now.getTime() / 1000);
  const expiresAt = new Date(input.now.getTime() + input.ttlMinutes * 60_000);
  const token = await new SignJWT({ sid: input.sessionId })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(input.userId)
    .setIssuer(ACCESS_TOKEN_ISSUER)
    .setAudience(ACCESS_TOKEN_AUDIENCE)
    .setIssuedAt(issuedAt)
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(input.secret);
  return { token, expiresAt };
}

export async function verifyAccessToken(
  token: string,
  secret: Buffer,
  now: Date,
): Promise<VerifiedAccessToken> {
  if (token.length === 0) return { ok: false, reason: 'invalid' };
  try {
    const { payload } = await jwtVerify(token, secret, {
      algorithms: ['HS256'],
      issuer: ACCESS_TOKEN_ISSUER,
      audience: ACCESS_TOKEN_AUDIENCE,
      currentDate: now,
    });
    if (typeof payload.sub !== 'string' || typeof payload.sid !== 'string') {
      return { ok: false, reason: 'invalid' };
    }
    return { ok: true, userId: payload.sub, sessionId: payload.sid };
  } catch (error) {
    if (error instanceof errors.JWTExpired) return { ok: false, reason: 'expired' };
    return { ok: false, reason: 'invalid' };
  }
}

/** 32 random bytes, base64url — the same generator the admin session cookie uses. */
export const newRefreshToken = newSessionToken;
export { hashToken };
```

- [ ] **Step 4: Run token tests** — `npx vitest run test/auth-tokens.test.ts` — Expected: PASS.

- [ ] **Step 5: Widen the principal**

Replace `backend/src/core/principal.ts` with:

```ts
/**
 * Who is making the request. Two kinds: an admin session (Phase 2) and a user
 * session (Phase 3). Set by an onRequest plugin; read by guards, the rate
 * limiter and the idempotency middleware. A principal existing does not mean
 * it may act: the guards decide that.
 */
export interface AdminPrincipal {
  kind: 'admin';
  id: string;
  sessionId: string;
  mfaVerified: boolean;
  totpEnrolled: boolean;
  reauthenticatedAt: Date | null;
}

export interface UserPrincipal {
  kind: 'user';
  id: string;
  sessionId: string;
  emailVerified: boolean;
  /** `anonymised` never reaches here — that session is rejected by the plugin. */
  status: 'active' | 'frozen';
}

export type Principal = AdminPrincipal | UserPrincipal;

declare module 'fastify' {
  interface FastifyRequest {
    principal?: Principal;
    /** Why a presented credential was rejected — the guard turns this into the error code. */
    sessionRejection?: 'SESSION_EXPIRED' | 'UNAUTHENTICATED' | 'ACCESS_TOKEN_EXPIRED';
  }
}
```

Then fix the one compile error this creates: `modules/admin-auth/guards.ts` `principalOf` must narrow on kind — change its body to:

```ts
  if (request.principal === undefined || request.principal.kind !== 'admin') {
    throw new AuthenticationError(
      request.sessionRejection ?? 'UNAUTHENTICATED',
      'Sign in to continue',
    );
  }
  return request.principal;
```

Run `npm run typecheck` — Expected: clean.

- [ ] **Step 6: Write the failing guard tests**

`backend/test/auth-guards.test.ts` — registers three test routes on a test app and injects principals directly, the way `test/idempotency.test.ts` does:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { UserPrincipal } from '../src/core/principal.js';
import {
  requireActiveAccount,
  requireAuth,
  requireEmailVerified,
} from '../src/modules/auth/guards.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

function principalFrom(header: unknown): UserPrincipal | undefined {
  if (typeof header !== 'string' || header === '') return undefined;
  const [emailVerified, status] = header.split(':');
  return {
    kind: 'user',
    id: '11111111-1111-4111-8111-111111111111',
    sessionId: '22222222-2222-4222-8222-222222222222',
    emailVerified: emailVerified === 'verified',
    status: status === 'frozen' ? 'frozen' : 'active',
  };
}

describe.skipIf(databaseUrl === undefined)('user guards', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp({
      routes: (app) => {
        const inject = (request: { principal?: unknown; headers: Record<string, unknown> }, _r: unknown, done: () => void) => {
          const p = principalFrom(request.headers['x-test-principal']);
          if (p !== undefined) request.principal = p;
          done();
        };
        app.get('/v1/_test/auth', { onRequest: inject, preHandler: requireAuth }, async () => ({ data: 'ok' }));
        app.get('/v1/_test/verified', { onRequest: inject, preHandler: requireEmailVerified }, async () => ({ data: 'ok' }));
        app.get('/v1/_test/active', { onRequest: inject, preHandler: requireActiveAccount }, async () => ({ data: 'ok' }));
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const code = (res: { json: <T>() => T }) => res.json<{ error: { code: string } }>().error.code;

  it('requireAuth: no principal → 401 UNAUTHENTICATED; a user → 200', async () => {
    const none = await ctx.app.inject({ method: 'GET', url: '/v1/_test/auth' });
    expect(none.statusCode).toBe(401);
    expect(code(none)).toBe('UNAUTHENTICATED');
    const ok = await ctx.app.inject({ method: 'GET', url: '/v1/_test/auth', headers: { 'x-test-principal': 'unverified:active' } });
    expect(ok.statusCode).toBe(200);
  });

  it('requireEmailVerified: unverified → 422 EMAIL_NOT_VERIFIED; verified → 200; browsing routes stay open', async () => {
    const no = await ctx.app.inject({ method: 'GET', url: '/v1/_test/verified', headers: { 'x-test-principal': 'unverified:active' } });
    expect(no.statusCode).toBe(422);
    expect(code(no)).toBe('EMAIL_NOT_VERIFIED');
    const yes = await ctx.app.inject({ method: 'GET', url: '/v1/_test/verified', headers: { 'x-test-principal': 'verified:active' } });
    expect(yes.statusCode).toBe(200);
    const anon = await ctx.app.inject({ method: 'GET', url: '/v1/_test/verified' });
    expect(anon.statusCode).toBe(401);
    const browse = await ctx.app.inject({ method: 'GET', url: '/v1/health', headers: { 'x-test-principal': 'unverified:active' } });
    expect(browse.statusCode).toBe(200);
  });

  it('requireActiveAccount: frozen → 422 ACCOUNT_FROZEN; active → 200', async () => {
    const frozen = await ctx.app.inject({ method: 'GET', url: '/v1/_test/active', headers: { 'x-test-principal': 'verified:frozen' } });
    expect(frozen.statusCode).toBe(422);
    expect(code(frozen)).toBe('ACCOUNT_FROZEN');
    const active = await ctx.app.inject({ method: 'GET', url: '/v1/_test/active', headers: { 'x-test-principal': 'verified:active' } });
    expect(active.statusCode).toBe(200);
  });
});
```

(The `inject` helper's parameter types: use `FastifyRequest` and `FastifyReply` imports rather than the inline shapes if the type checker complains; the behaviour is the same.)

- [ ] **Step 7: Run to verify failure** — `npx vitest run test/auth-guards.test.ts` — Expected: FAIL, module not found.

- [ ] **Step 8: Implement `guards.ts`**

```ts
import type { FastifyReply, FastifyRequest } from 'fastify';

import { AuthenticationError, BusinessRuleError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';

/**
 * The user principal, narrowed past `undefined` and past the admin kind. A
 * real runtime check, not a cast — an admin cookie must never satisfy a user
 * route.
 */
export function userOf(request: FastifyRequest): UserPrincipal {
  if (request.principal === undefined || request.principal.kind !== 'user') {
    throw new AuthenticationError(
      request.sessionRejection ?? 'UNAUTHENTICATED',
      request.sessionRejection === 'ACCESS_TOKEN_EXPIRED'
        ? 'Your access token has expired — refresh it'
        : request.sessionRejection === 'SESSION_EXPIRED'
          ? 'Signed out for your security — sign in again'
          : 'Sign in to continue',
    );
  }
  return request.principal;
}

// Declared `async` for the same reason the admin guards are: Fastify needs a
// two-argument hook to return a Promise, and a plain function returning
// undefined on its non-throwing path hangs the request. Keep them async.

/** Any signed-in user, verified or not. Browsing needs nothing; this is for "your own stuff". */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  userOf(request);
}

/**
 * Stricter than requireAuth (plan §Phase 3, CLAUDE.md 1c): the guard booking,
 * enquiry and messaging endpoints carry. 422 with its own code so the app
 * can route straight to Verify Email.
 */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireEmailVerified(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const p = userOf(request);
  if (!p.emailVerified) {
    throw new BusinessRuleError(
      'EMAIL_NOT_VERIFIED',
      'Verify your email address to book, enquire or message',
    );
  }
}

/**
 * A deletion request freezes the account: no new bookings, no new listings
 * (plan §Phase 3). Later phases place this on those endpoints; everything in
 * Phase 3 itself stays usable while frozen.
 */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireActiveAccount(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const p = userOf(request);
  if (p.status !== 'active') {
    throw new BusinessRuleError(
      'ACCOUNT_FROZEN',
      'This account is being deleted and cannot start anything new',
    );
  }
}
```

- [ ] **Step 9: Run guard tests, lint, typecheck** — `npx vitest run test/auth-guards.test.ts && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add backend/src/modules/auth/tokens.ts backend/src/modules/auth/guards.ts backend/src/core/principal.ts backend/src/modules/admin-auth/guards.ts backend/test/auth-tokens.test.ts backend/test/auth-guards.test.ts
git commit -m "User access tokens, the user principal, and the requireAuth / requireEmailVerified / requireActiveAccount guards"
```

---

### Task 3: Sessions — repository, `AuthService` core, the user-auth plugin, and `/refresh` `/logout` `/me` `/sessions`

**Files:**
- Create: `backend/src/modules/auth/repository.ts`, `backend/src/modules/auth/dto.ts`, `backend/src/modules/auth/service.ts`, `backend/src/modules/auth/schema.ts`, `backend/src/modules/auth/routes.ts`
- Create: `backend/src/plugins/user-auth.ts`
- Modify: `backend/src/app.ts` (decorate `auth`, register plugin and routes)
- Create: `backend/test/helpers/users.ts`
- Test: `backend/test/auth-sessions.test.ts`

**Interfaces:**
- Consumes: Task 2's `signAccessToken`, `verifyAccessToken`, `newRefreshToken`, `hashToken`, `userOf`, `requireAuth`; `AuditService.record(db, entry)`; `RequestMeta` shape from `modules/admin-auth/service.ts` (`{ ip, userAgent, requestId }`).
- Produces:
  - `UserRepository` methods: `findByEmail(email)`, `findById(id)` (both include `providerProfile`), `createSession(db, {...})`, `createRefreshToken(db, {sessionId, tokenHash, createdAt, expiresAt})`, `findSessionById(id)` (includes `user` with `providerProfile`), `findRefreshTokenByHash(hash)` (includes `session.user`), `rotateRefreshToken(db, tokenHash, now, newId)` → `RefreshToken | null` (the conditional UPDATE), `touchSession(sessionId, now)`, `revokeSession(db, sessionId, now, reason)`, `revokeOtherSessions(db, userId, keepSessionId, now, reason)`, `revokeAllSessions(db, userId, now, reason)`, `listLiveSessions(userId)`.
  - `AuthService`: `openSession(user, meta, now, deviceName)` → `TokenPair`, `resolveAccessToken(token)` → `{ principal } | { rejection }`, `refresh(refreshToken, meta)` → `TokenPair`, `logout(principal, meta)`, `listSessions(userId)`, `revokeSession(principal, sessionId, meta)`.
  - `TokenPair = { accessToken: string; accessTokenExpiresAt: Date; refreshToken: string; refreshTokenExpiresAt: Date }`.
  - `userDto(user: User & { providerProfile: ProviderProfile | null })`, `sessionDto(session, currentSessionId)`.
  - `app.auth: AuthService`. Test helpers: `RecordingEmailTransport`, `createUser(prisma, overrides?)`, `bearer(token)`.

- [ ] **Step 1: Write the test helper**

`backend/test/helpers/users.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { hashPassword } from '../../src/modules/admin-auth/crypto.js';
import type { EmailTransport, OutboundEmail } from '../../src/modules/email/types.js';
import type { PrismaClient, User } from '../../src/generated/prisma/client.js';

export const USER_PASSWORD = 'correct horse battery';

/** Keeps every delivered email in memory so a test can read the OTP out of it without touching the disk. */
export class RecordingEmailTransport implements EmailTransport {
  readonly sent: OutboundEmail[] = [];
  deliver(email: OutboundEmail): Promise<{ providerMessageId: string }> {
    this.sent.push(email);
    return Promise.resolve({ providerMessageId: `rec-${randomUUID()}` });
  }
  /** The six-digit code in the most recent message to `to`, or null. */
  latestCodeFor(to: string): string | null {
    const match = [...this.sent].reverse().find((e) => e.to === to.toLowerCase());
    return match?.text.match(/\b(\d{6})\b/)?.[1] ?? null;
  }
}

export function freshEmail(): string {
  return `user-${randomUUID()}@example.test`;
}

export function freshPhone(): string {
  return String(Math.floor(Math.random() * 9_000_000) + 1_000_000);
}

/** Inserts a user straight into the database — for tests of everything downstream of registration. */
export async function createUser(
  prisma: PrismaClient,
  overrides: Partial<{ email: string; emailVerified: boolean; phone: string | null; password: string }> = {},
): Promise<User & { password: string }> {
  const password = overrides.password ?? USER_PASSWORD;
  const phone = overrides.phone === undefined ? freshPhone() : overrides.phone;
  const user = await prisma.user.create({
    data: {
      email: (overrides.email ?? freshEmail()).toLowerCase(),
      emailVerifiedAt: overrides.emailVerified === true ? new Date() : null,
      passwordHash: await hashPassword(password),
      fullName: 'Test User',
      phoneE164: phone === null ? null : `+960${phone}`,
      phoneDialCode: phone === null ? null : '+960',
      termsAcceptedAt: new Date(),
    },
  });
  return { ...user, password };
}

export function bearer(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}
```

- [ ] **Step 2: Write the failing session tests**

`backend/test/auth-sessions.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { TokenPair } from '../src/modules/auth/service.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, createUser, RecordingEmailTransport } from './helpers/users.js';

type Err = { error: { code: string } };

describe.skipIf(databaseUrl === undefined)('user sessions — refresh, logout, me, sessions', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  async function openSession(deviceName = 'Test phone'): Promise<{ userId: string; tokens: TokenPair }> {
    const user = await createUser(ctx.prisma);
    const full = await ctx.prisma.user.findUniqueOrThrow({ where: { id: user.id }, include: { providerProfile: true } });
    const tokens = await ctx.app.auth.openSession(full, { ip: freshIp(), userAgent: 'vitest', requestId: 'r' }, time.clock(), deviceName);
    return { userId: user.id, tokens };
  }

  it('GET /me returns the DTO — never the hash, never a token — and no header is 401 UNAUTHENTICATED', async () => {
    const { userId, tokens } = await openSession();
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(tokens.accessToken) });
    expect(res.statusCode).toBe(200);
    const me = res.json<{ data: Record<string, unknown> }>().data;
    expect(me.id).toBe(userId);
    expect(me.emailVerified).toBe(false);
    expect(me.status).toBe('active');
    expect(me.isProvider).toBe(false);
    expect(res.body).not.toContain('passwordHash');
    expect(res.body).not.toContain(tokens.refreshToken);
    const none = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me' });
    expect(none.statusCode).toBe(401);
    expect(none.json<Err>().error.code).toBe('UNAUTHENTICATED');
  });

  it('an expired access token is ACCESS_TOKEN_EXPIRED; a revoked session is SESSION_EXPIRED', async () => {
    const { tokens } = await openSession();
    time.advance(16 * 60_000);
    const expired = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(tokens.accessToken) });
    expect(expired.statusCode).toBe(401);
    expect(expired.json<Err>().error.code).toBe('ACCESS_TOKEN_EXPIRED');
    time.advance(-16 * 60_000);
    await ctx.app.inject({ method: 'POST', url: '/v1/auth/logout', headers: bearer(tokens.accessToken) });
    const revoked = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(tokens.accessToken) });
    expect(revoked.statusCode).toBe(401);
    expect(revoked.json<Err>().error.code).toBe('SESSION_EXPIRED');
  });

  it('refresh rotates: the new pair works, the old refresh token is refused, reuse after 30 s revokes the session', async () => {
    const { tokens } = await openSession();
    const first = await ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: tokens.refreshToken } });
    expect(first.statusCode).toBe(200);
    const next = first.json<{ data: { tokens: TokenPair } }>().data.tokens;
    expect(next.refreshToken).not.toBe(tokens.refreshToken);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(next.accessToken) })).statusCode).toBe(200);

    // Inside the grace window: a client retry, not theft.
    time.advance(10_000);
    const retry = await ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: tokens.refreshToken } });
    expect(retry.statusCode).toBe(401);
    expect(retry.json<Err>().error.code).toBe('REFRESH_TOKEN_ROTATED');
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(next.accessToken) })).statusCode).toBe(200);

    // Past the grace window: replay of a rotated token revokes everything.
    time.advance(31_000);
    const reuse = await ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: tokens.refreshToken } });
    expect(reuse.statusCode).toBe(401);
    expect(reuse.json<Err>().error.code).toBe('SESSION_EXPIRED');
    const dead = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(next.accessToken) });
    expect(dead.json<Err>().error.code).toBe('SESSION_EXPIRED');
    const deadRefresh = await ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: next.refreshToken } });
    expect(deadRefresh.statusCode).toBe(401);
  });

  it('two concurrent refreshes with one token → exactly one success', async () => {
    const { tokens } = await openSession();
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: tokens.refreshToken } }),
      ),
    );
    expect(results.filter((r) => r.statusCode === 200)).toHaveLength(1);
    expect(results.filter((r) => r.json<Err>().error?.code === 'REFRESH_TOKEN_ROTATED')).toHaveLength(4);
  });

  it('an expired refresh token is SESSION_EXPIRED and marks the session refresh_expired', async () => {
    const { tokens } = await openSession();
    time.advance(31 * 24 * 3_600_000);
    const res = await ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: tokens.refreshToken } });
    expect(res.statusCode).toBe(401);
    expect(res.json<Err>().error.code).toBe('SESSION_EXPIRED');
    time.advance(-31 * 24 * 3_600_000);
    const unknown = await ctx.app.inject({ method: 'POST', url: '/v1/auth/refresh', remoteAddress: freshIp(), payload: { refreshToken: 'a'.repeat(43) } });
    expect(unknown.json<Err>().error.code).toBe('UNAUTHENTICATED');
  });

  it('sessions list marks the current device; revoking one leaves the other live; a foreign id is 404', async () => {
    const user = await createUser(ctx.prisma);
    const full = await ctx.prisma.user.findUniqueOrThrow({ where: { id: user.id }, include: { providerProfile: true } });
    const meta = { ip: freshIp(), userAgent: 'vitest', requestId: 'r' };
    const phone = await ctx.app.auth.openSession(full, meta, time.clock(), 'iPhone 14');
    const tablet = await ctx.app.auth.openSession(full, meta, time.clock(), 'Pixel 7');
    const list = await ctx.app.inject({ method: 'GET', url: '/v1/auth/sessions', headers: bearer(phone.accessToken) });
    const rows = list.json<{ data: { id: string; deviceName: string; current: boolean }[] }>().data;
    expect(rows).toHaveLength(2);
    expect(rows.find((r) => r.current)?.deviceName).toBe('iPhone 14');
    expect(list.body).not.toContain('ipAddress');
    const other = rows.find((r) => !r.current);
    const revoke = await ctx.app.inject({ method: 'DELETE', url: `/v1/auth/sessions/${other?.id ?? ''}`, headers: bearer(phone.accessToken) });
    expect(revoke.statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(tablet.accessToken) })).json<Err>().error.code).toBe('SESSION_EXPIRED');
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(phone.accessToken) })).statusCode).toBe(200);

    const stranger = await openSession();
    const foreign = await ctx.app.inject({ method: 'DELETE', url: `/v1/auth/sessions/${stranger.tokens.refreshToken.length > 0 ? rows[0]?.id ?? '' : ''}`, headers: bearer(stranger.tokens.accessToken) });
    expect(foreign.statusCode).toBe(404);
  });

  it('an admin cookie never satisfies a user route', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: { cookie: 'rp_admin_session=whatever' } });
    expect(res.statusCode).toBe(401);
  });
});
```

- [ ] **Step 3: Run to verify failure** — `npx vitest run test/auth-sessions.test.ts` — Expected: FAIL (modules missing).

- [ ] **Step 4: Repository**

`backend/src/modules/auth/repository.ts`:

```ts
import type {
  PrismaClient,
  ProviderProfile,
  RefreshToken,
  User,
  UserSession,
  UserSessionRevokedReason,
} from '../../generated/prisma/client.js';
import type { Db } from '../audit/types.js';

export type UserWithProfile = User & { providerProfile: ProviderProfile | null };
export type SessionWithUser = UserSession & { user: UserWithProfile };

/** Data access for user identity. No rules here — the services own them. */
export class UserRepository {
  constructor(private readonly prisma: PrismaClient) {}

  findByEmail(email: string): Promise<UserWithProfile | null> {
    return this.prisma.user.findUnique({ where: { email }, include: { providerProfile: true } });
  }

  findById(id: string): Promise<UserWithProfile | null> {
    return this.prisma.user.findUnique({ where: { id }, include: { providerProfile: true } });
  }

  createSession(
    db: Db,
    data: { userId: string; deviceName: string; ipAddress: string; userAgent: string; now: Date },
  ): Promise<UserSession> {
    return db.userSession.create({
      data: {
        userId: data.userId,
        deviceName: data.deviceName,
        ipAddress: data.ipAddress,
        userAgent: data.userAgent,
        createdAt: data.now,
        lastSeenAt: data.now,
      },
    });
  }

  createRefreshToken(
    db: Db,
    data: { id?: string; sessionId: string; tokenHash: string; createdAt: Date; expiresAt: Date },
  ): Promise<RefreshToken> {
    return db.refreshToken.create({
      data: {
        ...(data.id === undefined ? {} : { id: data.id }),
        sessionId: data.sessionId,
        tokenHash: data.tokenHash,
        createdAt: data.createdAt,
        expiresAt: data.expiresAt,
      },
    });
  }

  findSessionById(id: string): Promise<SessionWithUser | null> {
    return this.prisma.userSession.findUnique({
      where: { id },
      include: { user: { include: { providerProfile: true } } },
    });
  }

  findRefreshTokenByHash(
    tokenHash: string,
  ): Promise<(RefreshToken & { session: SessionWithUser }) | null> {
    return this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { session: { include: { user: { include: { providerProfile: true } } } } },
    });
  }

  /**
   * The rotation is one conditional UPDATE so two racing refreshes with the
   * same token cannot both win — `updateMany` returns the affected count and
   * the caller treats 0 as "lost the race or not live".
   */
  async rotateRefreshToken(
    db: Db,
    tokenHash: string,
    now: Date,
    replacedById: string,
  ): Promise<boolean> {
    const result = await db.refreshToken.updateMany({
      where: { tokenHash, rotatedAt: null, expiresAt: { gt: now } },
      data: { rotatedAt: now, replacedById },
    });
    return result.count === 1;
  }

  touchSession(sessionId: string, now: Date): Promise<{ count: number }> {
    return this.prisma.userSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { lastSeenAt: now },
    });
  }

  revokeSession(
    db: Db,
    sessionId: string,
    now: Date,
    reason: UserSessionRevokedReason,
  ): Promise<{ count: number }> {
    return db.userSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { revokedAt: now, revokedReason: reason },
    });
  }

  revokeOtherSessions(
    db: Db,
    userId: string,
    keepSessionId: string,
    now: Date,
    reason: UserSessionRevokedReason,
  ): Promise<{ count: number }> {
    return db.userSession.updateMany({
      where: { userId, revokedAt: null, id: { not: keepSessionId } },
      data: { revokedAt: now, revokedReason: reason },
    });
  }

  revokeAllSessions(
    db: Db,
    userId: string,
    now: Date,
    reason: UserSessionRevokedReason,
  ): Promise<{ count: number }> {
    return db.userSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: now, revokedReason: reason },
    });
  }

  listLiveSessions(userId: string): Promise<UserSession[]> {
    return this.prisma.userSession.findMany({
      where: { userId, revokedAt: null },
      orderBy: { lastSeenAt: 'desc' },
    });
  }
}
```

- [ ] **Step 5: DTOs**

`backend/src/modules/auth/dto.ts`:

```ts
import type { UserSession } from '../../generated/prisma/client.js';
import type { UserWithProfile } from './repository.js';

export interface UserDto {
  id: string;
  fullName: string;
  email: string;
  emailVerified: boolean;
  /** Own-read only. Split back into the parts the client collected. */
  phone: { dialCode: string; number: string } | null;
  status: 'active' | 'frozen' | 'anonymised';
  deletionDeadlineAt: string | null;
  isProvider: boolean;
  createdAt: string;
}

/**
 * The one mapping every route uses for a user. Structural exclusion
 * (backend/CLAUDE.md): the hash, tokens and session ids are simply not
 * fields here. The phone is present because the only consumer of this DTO is
 * the account holder — there is no other-user read in Phase 3.
 */
export function userDto(user: UserWithProfile): UserDto {
  const phone =
    user.phoneE164 === null || user.phoneDialCode === null
      ? null
      : { dialCode: user.phoneDialCode, number: user.phoneE164.slice(user.phoneDialCode.length) };
  return {
    id: user.id,
    fullName: user.fullName,
    email: user.email,
    emailVerified: user.emailVerifiedAt !== null,
    phone,
    status: user.status,
    deletionDeadlineAt: user.deletionDeadlineAt?.toISOString() ?? null,
    isProvider: user.providerProfile !== null,
    createdAt: user.createdAt.toISOString(),
  };
}

/** Never the IP, never the user agent, never a token hash. */
export function sessionDto(session: UserSession, currentSessionId: string) {
  return {
    id: session.id,
    deviceName: session.deviceName,
    createdAt: session.createdAt.toISOString(),
    lastSeenAt: session.lastSeenAt.toISOString(),
    current: session.id === currentSessionId,
  };
}
```

- [ ] **Step 6: The service core**

`backend/src/modules/auth/service.ts` (Task 5 adds `login` and `register` to this class):

```ts
import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import { AuthenticationError, NotFoundError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';
import type { PrismaClient, UserSession } from '../../generated/prisma/client.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import { UserRepository, type UserWithProfile } from './repository.js';
import { hashToken, newRefreshToken, signAccessToken, verifyAccessToken } from './tokens.js';

export type { RequestMeta };

export interface TokenPair {
  accessToken: string;
  accessTokenExpiresAt: Date;
  refreshToken: string;
  refreshTokenExpiresAt: Date;
}

export type AccessResolution =
  | { principal: UserPrincipal }
  | { rejection: 'UNAUTHENTICATED' | 'SESSION_EXPIRED' | 'ACCESS_TOKEN_EXPIRED' };

/** A rotated refresh token presented again within this window is a client retry, not a theft. */
export const REFRESH_REUSE_GRACE_MS = 30_000;

/** Device names are client-supplied text; bounded and defaulted here, never trusted for anything else. */
export function cleanDeviceName(input: string | undefined): string {
  const trimmed = (input ?? '').trim().slice(0, 80);
  return trimmed.length === 0 ? 'Unknown device' : trimmed;
}

/**
 * User identity (plan §Phase 3): JWT access + rotated per-device refresh
 * tokens, sessions listed and revoked per device. Every state change writes
 * an audit row in the same transaction.
 */
export class AuthService {
  readonly repo: UserRepository;

  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      audit: AuditService;
      clock: Clock;
      config: Config;
    },
  ) {
    this.repo = new UserRepository(deps.prisma);
  }

  /** Who may call: the service itself, after a password or registration has been accepted. */
  async openSession(
    user: UserWithProfile,
    meta: RequestMeta,
    now: Date,
    deviceName: string | undefined,
    action: 'user.login.succeeded' | 'user.registered' = 'user.login.succeeded',
  ): Promise<TokenPair> {
    const refreshToken = newRefreshToken();
    const refreshTokenExpiresAt = this.refreshExpiry(now);
    const session = await this.deps.prisma.$transaction(async (tx) => {
      const created = await this.repo.createSession(tx, {
        userId: user.id,
        deviceName: cleanDeviceName(deviceName),
        ipAddress: meta.ip,
        userAgent: meta.userAgent.slice(0, 512),
        now,
      });
      await this.repo.createRefreshToken(tx, {
        sessionId: created.id,
        tokenHash: hashToken(refreshToken),
        createdAt: now,
        expiresAt: refreshTokenExpiresAt,
      });
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: user.id,
        action,
        targetType: 'user_session',
        targetId: created.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      return created;
    });
    const access = await this.signAccess(user.id, session.id, now);
    return {
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken,
      refreshTokenExpiresAt,
    };
  }

  /** Bearer token → principal. Signature first, then the row, so a revocation is honoured at once. */
  async resolveAccessToken(token: string): Promise<AccessResolution> {
    const now = this.deps.clock();
    const verified = await verifyAccessToken(token, this.deps.config.auth.jwtSecret, now);
    if (!verified.ok) {
      return { rejection: verified.reason === 'expired' ? 'ACCESS_TOKEN_EXPIRED' : 'UNAUTHENTICATED' };
    }
    const session = await this.repo.findSessionById(verified.sessionId);
    if (session === null || session.userId !== verified.userId) return { rejection: 'UNAUTHENTICATED' };
    if (session.revokedAt !== null || session.user.status === 'anonymised') {
      return { rejection: 'SESSION_EXPIRED' };
    }
    if (now.getTime() - session.lastSeenAt.getTime() > 60_000) {
      await this.repo.touchSession(session.id, now);
    }
    return {
      principal: {
        kind: 'user',
        id: session.userId,
        sessionId: session.id,
        emailVerified: session.user.emailVerifiedAt !== null,
        status: session.user.status === 'frozen' ? 'frozen' : 'active',
      },
    };
  }

  /** Who may call: anyone holding a refresh token — the token is the credential. */
  async refresh(refreshToken: string, meta: RequestMeta): Promise<TokenPair> {
    const now = this.deps.clock();
    const presentedHash = hashToken(refreshToken);
    const existing = await this.repo.findRefreshTokenByHash(presentedHash);
    if (existing === null) throw new AuthenticationError('UNAUTHENTICATED', 'Sign in to continue');
    const session = existing.session;
    const dead = () => new AuthenticationError('SESSION_EXPIRED', 'Signed out for your security — sign in again');

    if (session.revokedAt !== null || session.user.status === 'anonymised') throw dead();

    if (existing.rotatedAt !== null) {
      // Already rotated. A retry inside the grace window is a flaky-network
      // client re-sending; beyond it, someone is replaying a stolen token
      // and the whole device session is revoked (plan §2 rotation).
      if (now.getTime() - existing.rotatedAt.getTime() <= REFRESH_REUSE_GRACE_MS) {
        throw new AuthenticationError('REFRESH_TOKEN_ROTATED', 'This refresh token was already used — retry with the newest one');
      }
      await this.revokeBySystem(session, now, 'refresh_reuse', meta);
      throw dead();
    }
    if (existing.expiresAt.getTime() <= now.getTime()) {
      await this.revokeBySystem(session, now, 'refresh_expired', meta);
      throw dead();
    }

    const nextToken = newRefreshToken();
    const nextExpiresAt = this.refreshExpiry(now);
    const nextId = crypto.randomUUID();
    const rotated = await this.deps.prisma.$transaction(async (tx) => {
      const won = await this.repo.rotateRefreshToken(tx, presentedHash, now, nextId);
      if (!won) return false;
      await this.repo.createRefreshToken(tx, {
        id: nextId,
        sessionId: session.id,
        tokenHash: hashToken(nextToken),
        createdAt: now,
        expiresAt: nextExpiresAt,
      });
      return true;
    });
    if (!rotated) {
      // Lost a race with a concurrent refresh of the same token — by
      // definition inside the grace window.
      throw new AuthenticationError('REFRESH_TOKEN_ROTATED', 'This refresh token was already used — retry with the newest one');
    }
    await this.repo.touchSession(session.id, now);
    const access = await this.signAccess(session.userId, session.id, now);
    return {
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: nextToken,
      refreshTokenExpiresAt: nextExpiresAt,
    };
  }

  /** Who may call: the signed-in user, for their own current session. */
  async logout(principal: UserPrincipal, meta: RequestMeta): Promise<void> {
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, principal.sessionId, now, 'logout');
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.logout',
        targetType: 'user_session',
        targetId: principal.sessionId,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  /** Who may call: the signed-in user; lists their own live sessions only. */
  listSessions(userId: string): Promise<UserSession[]> {
    return this.repo.listLiveSessions(userId);
  }

  /** Who may call: the signed-in user, for one of their own sessions. A foreign id is 404, never 403. */
  async revokeSession(principal: UserPrincipal, sessionId: string, meta: RequestMeta): Promise<void> {
    const now = this.deps.clock();
    const target = await this.deps.prisma.userSession.findFirst({
      where: { id: sessionId, userId: principal.id, revokedAt: null },
    });
    if (target === null) throw new NotFoundError('No such session');
    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, target.id, now, sessionId === principal.sessionId ? 'logout' : 'revoked_by_user');
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.session.revoked',
        targetType: 'user_session',
        targetId: target.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  private async revokeBySystem(
    session: UserSession,
    now: Date,
    reason: 'refresh_reuse' | 'refresh_expired',
    meta: RequestMeta,
  ): Promise<void> {
    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, session.id, now, reason);
      await this.deps.audit.record(tx, {
        actorType: 'system',
        action: 'user.session.revoked',
        targetType: 'user_session',
        targetId: session.id,
        reason,
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  private signAccess(userId: string, sessionId: string, now: Date) {
    return signAccessToken({
      userId,
      sessionId,
      now,
      ttlMinutes: this.deps.config.auth.accessTokenMinutes,
      secret: this.deps.config.auth.jwtSecret,
    });
  }

  private refreshExpiry(now: Date): Date {
    return new Date(now.getTime() + this.deps.config.auth.refreshTokenDays * 86_400_000);
  }
}
```

Add `import { randomUUID } from 'node:crypto';` and use `randomUUID()` where `crypto.randomUUID()` appears. Also widen `AuditEntryInput.actorType` in `modules/audit/types.ts` to `'admin' | 'user' | 'system'`.

- [ ] **Step 7: The plugin**

`backend/src/plugins/user-auth.ts`:

```ts
import type { FastifyInstance } from 'fastify';

/**
 * User session resolution (plan §Phase 3). Runs onRequest, beside the admin
 * cookie plugin and before rate limiting so counters key on the user. No
 * header means an anonymous request — browsing needs nothing. A header is
 * verified as a JWT and then resolved to its session row, so a revoked
 * device or a frozen account is seen on the very next request. The rejection
 * reason is left for the guard to report; a public route ignores it.
 */
export function registerUserAuth(app: FastifyInstance): void {
  app.addHook('onRequest', async (request) => {
    const header = request.headers.authorization;
    if (header === undefined) return;
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() !== 'bearer' || token === undefined || token.length === 0) {
      request.sessionRejection = 'UNAUTHENTICATED';
      return;
    }
    const resolution = await app.auth.resolveAccessToken(token);
    if ('principal' in resolution) {
      request.principal = resolution.principal;
    } else {
      request.sessionRejection = resolution.rejection;
    }
  });
}
```

- [ ] **Step 8: Schemas and routes**

`backend/src/modules/auth/schema.ts` (Tasks 4–5 add to it):

```ts
import { z } from 'zod';

export const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
export const sessionIdParams = z.object({ id: z.uuid() });
export const deviceName = z.string().trim().max(80).optional();
```

`backend/src/modules/auth/routes.ts`:

```ts
import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { sessionDto, userDto } from './dto.js';
import { requireAuth, userOf } from './guards.js';
import { refreshBody, sessionIdParams } from './schema.js';
import type { TokenPair } from './service.js';

export function tokensDto(t: TokenPair) {
  return {
    accessToken: t.accessToken,
    accessTokenExpiresAt: t.accessTokenExpiresAt.toISOString(),
    refreshToken: t.refreshToken,
    refreshTokenExpiresAt: t.refreshTokenExpiresAt.toISOString(),
  };
}

export function registerAuthRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/auth';

  // Who may call: anyone holding a refresh token. Own tier: 30/min per IP.
  r.post(
    `${prefix}/refresh`,
    {
      schema: { body: refreshBody },
      config: { rateLimit: { max: 30, timeWindow: '1 minute', keyGenerator: (req) => `ip:${req.ip}` } },
    },
    async (request, reply) => {
      const tokens = await app.auth.refresh(request.body.refreshToken, requestMeta(request));
      return reply.send(ok({ tokens: tokensDto(tokens) }));
    },
  );

  // Who may call: the signed-in user, for their own current session.
  r.post(`${prefix}/logout`, { preHandler: requireAuth }, async (request, reply) => {
    await app.auth.logout(userOf(request), requestMeta(request));
    return reply.send(ok({ loggedOut: true }));
  });

  // Who may call: the signed-in user, about themselves. Verified or not — browsing is free.
  r.get(`${prefix}/me`, { preHandler: requireAuth }, async (request, reply) => {
    const p = userOf(request);
    const user = await app.auth.repo.findById(p.id);
    if (user === null) throw new Error('principal without a user row');
    return reply.send(ok(userDto(user)));
  });

  // Who may call: the signed-in user; their own live sessions only.
  r.get(`${prefix}/sessions`, { preHandler: requireAuth }, async (request, reply) => {
    const p = userOf(request);
    const sessions = await app.auth.listSessions(p.id);
    return reply.send(ok(sessions.map((s) => sessionDto(s, p.sessionId))));
  });

  // Who may call: the signed-in user, for one of their own sessions.
  r.delete(
    `${prefix}/sessions/:id`,
    { schema: { params: sessionIdParams }, preHandler: requireAuth },
    async (request, reply) => {
      await app.auth.revokeSession(userOf(request), request.params.id, requestMeta(request));
      return reply.send(ok({ revoked: request.params.id }));
    },
  );
}
```

- [ ] **Step 9: Wire into `app.ts`**

Add to the `FastifyInstance` augmentation: `auth: AuthService;`. After the `adminAuth` decoration: `app.decorate('auth', new AuthService({ prisma: deps.prisma, audit, clock: deps.clock, config }));`. After `await registerAdminSession(app);` add `registerUserAuth(app);` (before `registerRateLimit`). After `registerAdminAuthRoutes(app);` add `registerAuthRoutes(app);`.

- [ ] **Step 10: Run, lint, typecheck** — `npx vitest run test/auth-sessions.test.ts test/auth-guards.test.ts && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add backend/src backend/test
git commit -m "User sessions: rotated per-device refresh tokens, bearer resolution, logout, me, session list and revoke"
```

---

### Task 4: Phone normalisation and the OTP service — both send limits, five attempts, `/verify-email/send` and `/confirm`

**Files:**
- Create: `backend/src/modules/auth/phone.ts`, `backend/src/modules/auth/otp.ts`
- Modify: `backend/src/modules/auth/schema.ts`, `backend/src/modules/auth/routes.ts`, `backend/src/app.ts`
- Test: `backend/test/auth-phone.test.ts`, `backend/test/auth-otp.test.ts`

**Interfaces:**
- Consumes: `app.email: EmailSender` (Phase 2), `config.auth.otpExpiryMinutes`, `requireAuth`/`userOf`, `AuditService`.
- Produces:
  - `normalisePhone(input: { dialCode: string; number: string }): { e164: string; dialCode: string }` — throws `ValidationError` with `path: 'phone'`.
  - `OtpService`: `send(input: { userId: string; purpose: 'verify_email' | 'change_email'; targetEmail: string; meta: RequestMeta }): Promise<OtpSendResult>`, `confirm(input: { userId; purpose; code; meta }): Promise<{ targetEmail: string }>`, `invalidateAll(db, userId, purpose, now)`.
  - `OtpSendResult = { status: 'sent' | 'suppressed' | 'failed'; expiresAt: Date; resendAvailableAt: Date }`.
  - Constants `OTP_ADDRESS_LIMIT = 3`, `OTP_ADDRESS_WINDOW_MS = 15 * 60_000`, `OTP_ACCOUNT_LIMIT = 5`, `OTP_ACCOUNT_WINDOW_MS = 60 * 60_000`, `OTP_ATTEMPT_LIMIT = 5`, `OTP_RESEND_COOLDOWN_MS = 60_000`.
  - `class OtpRateLimitedError extends AppError` (429 `OTP_RATE_LIMITED`, `details: { retryAfterSeconds, limit: 'address' | 'account' }`, sets `Retry-After` via `retryAfterSeconds` field — extend `RateLimitedError` handling in `core/error-handler.ts` to any `AppError` carrying `retryAfterSeconds`).
  - `app.otp: OtpService`.

- [ ] **Step 1: Phone tests**

`backend/test/auth-phone.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { ValidationError } from '../src/core/errors.js';
import { normalisePhone } from '../src/modules/auth/phone.js';

describe('normalisePhone (plan §Phase 3: E.164, +960 default, 6–15 digits, foreign numbers welcome)', () => {
  it('stores a Maldivian number as +960 plus digits and strips separators', () => {
    expect(normalisePhone({ dialCode: '+960', number: '777-1234' })).toEqual({ e164: '+9607771234', dialCode: '+960' });
    expect(normalisePhone({ dialCode: ' +960 ', number: '777 12.34' })).toEqual({ e164: '+9607771234', dialCode: '+960' });
  });

  it('accepts a foreign number and does not apply the 7-or-9 heuristic', () => {
    expect(normalisePhone({ dialCode: '+44', number: '7700900123' })).toEqual({ e164: '+447700900123', dialCode: '+44' });
    expect(normalisePhone({ dialCode: '+960', number: '3001234' })).toEqual({ e164: '+9603001234', dialCode: '+960' });
  });

  it('rejects too few or too many digits, a bad dial code, and an E.164 overflow — each at path phone', () => {
    for (const input of [
      { dialCode: '+960', number: '12345' },
      { dialCode: '+960', number: '1234567890123456' },
      { dialCode: '960', number: '7771234' },
      { dialCode: '+0', number: '7771234' },
      { dialCode: '+1234', number: '123456789012' }, // 4 + 12 = 16 digits
      { dialCode: '+960', number: '77a1234' },
    ]) {
      let caught: unknown;
      try {
        normalisePhone(input);
      } catch (error) {
        caught = error;
      }
      expect(caught, JSON.stringify(input)).toBeInstanceOf(ValidationError);
      expect((caught as ValidationError).details).toEqual([expect.objectContaining({ path: 'phone' })]);
    }
  });
});
```

- [ ] **Step 2: Run to fail** — `npx vitest run test/auth-phone.test.ts` — Expected: FAIL.

- [ ] **Step 3: Implement `phone.ts`**

```ts
import { ValidationError } from '../../core/errors.js';

const DIAL_CODE = /^\+[1-9]\d{0,3}$/;
const E164_MAX_DIGITS = 15;
const NATIONAL_MIN = 6;
const NATIONAL_MAX = 15;

/**
 * Phone numbers (plan §Phase 3): stored E.164 with a country code, `+960`
 * the default the client supplies, 6–15 national digits. No Maldivian 7/9
 * prefix rule — resort guests and expatriate residents hold foreign numbers
 * and rejecting them is a silently lost signup. Nothing here verifies the
 * number; nothing anywhere does.
 */
export function normalisePhone(input: { dialCode: string; number: string }): {
  e164: string;
  dialCode: string;
} {
  const dialCode = input.dialCode.trim();
  const national = input.number.replace(/[\s.\-]/g, '');
  const fail = (message: string) =>
    new ValidationError([{ path: 'phone', message }], 'Phone number is not valid');
  if (!DIAL_CODE.test(dialCode)) throw fail('Dial code must look like +960');
  if (!/^\d+$/.test(national)) throw fail('Phone number may contain digits only');
  if (national.length < NATIONAL_MIN || national.length > NATIONAL_MAX) {
    throw fail(`Phone number must be ${String(NATIONAL_MIN)} to ${String(NATIONAL_MAX)} digits`);
  }
  if (dialCode.length - 1 + national.length > E164_MAX_DIGITS) {
    throw fail('Phone number is too long for its dial code');
  }
  return { e164: `${dialCode}${national}`, dialCode };
}
```

- [ ] **Step 4: Run phone tests** — Expected: PASS.

- [ ] **Step 5: OTP tests**

`backend/test/auth-otp.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, createUser, RecordingEmailTransport } from './helpers/users.js';

type Err = { error: { code: string; details?: { retryAfterSeconds?: number; limit?: string; attemptsRemaining?: number } } };

describe.skipIf(databaseUrl === undefined)('email OTP — send limits, attempts, verification', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  async function signedIn(emailVerified = false) {
    const user = await createUser(ctx.prisma, { emailVerified });
    const full = await ctx.prisma.user.findUniqueOrThrow({ where: { id: user.id }, include: { providerProfile: true } });
    const tokens = await ctx.app.auth.openSession(full, { ip: freshIp(), userAgent: 'vitest', requestId: 'r' }, time.clock(), 'phone');
    return { user, headers: bearer(tokens.accessToken) };
  }
  const send = (headers: Record<string, string>) =>
    ctx.app.inject({ method: 'POST', url: '/v1/auth/verify-email/send', headers, remoteAddress: freshIp() });
  const confirm = (headers: Record<string, string>, code: string) =>
    ctx.app.inject({ method: 'POST', url: '/v1/auth/verify-email/confirm', headers, payload: { code } });

  it('sends a six-digit code by email on the otp channel with the user id attached, and confirms it', async () => {
    const { user, headers } = await signedIn();
    const res = await send(headers);
    expect(res.statusCode).toBe(200);
    expect(res.json<{ data: { status: string } }>().data.status).toBe('sent');
    const code = mail.latestCodeFor(user.email);
    expect(code).toMatch(/^\d{6}$/);
    const last = mail.sent[mail.sent.length - 1];
    expect(last?.channel).toBe('otp');
    expect(last?.recipientUserId).toBe(user.id);
    expect(last?.text).not.toMatch(/https?:\/\//);
    const ok = await confirm(headers, code ?? '');
    expect(ok.statusCode).toBe(200);
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers });
    expect(me.json<{ data: { emailVerified: boolean } }>().data.emailVerified).toBe(true);
    const logged = await ctx.prisma.emailOtp.findFirst({ where: { userId: user.id }, include: { emailMessage: true } });
    expect(logged?.emailMessage?.recipientUserId).toBe(user.id);
    const again = await send(headers);
    expect(again.json<Err>().error.code).toBe('EMAIL_ALREADY_VERIFIED');
  });

  it('address limit: three sends per 15 minutes, the fourth is OTP_RATE_LIMITED with the wait and the limit named', async () => {
    const { headers } = await signedIn();
    for (let i = 0; i < 3; i += 1) {
      expect((await send(headers)).statusCode).toBe(200);
      time.advance(60_000);
    }
    const fourth = await send(headers);
    expect(fourth.statusCode).toBe(429);
    const err = fourth.json<Err>().error;
    expect(err.code).toBe('OTP_RATE_LIMITED');
    expect(err.details?.limit).toBe('address');
    expect(err.details?.retryAfterSeconds).toBe(12 * 60);
    expect(fourth.headers['retry-after']).toBe(String(12 * 60));
    time.advance(12 * 60_000 + 1_000);
    expect((await send(headers)).statusCode).toBe(200);
  });

  it('account limit: five sends per hour across addresses, the sixth is limited by account', async () => {
    const { user, headers } = await signedIn();
    // Three to the account's own address, then two change-email sends to other addresses.
    for (let i = 0; i < 3; i += 1) expect((await send(headers)).statusCode).toBe(200);
    for (const target of ['a', 'b']) {
      await ctx.app.otp.send({ userId: user.id, purpose: 'change_email', targetEmail: `${target}-${user.id}@example.test`, meta: { ip: '10.0.0.1', userAgent: '', requestId: 'r' } });
    }
    time.advance(16 * 60_000); // the 15-minute address window has passed
    const sixth = await send(headers);
    expect(sixth.statusCode).toBe(429);
    expect(sixth.json<Err>().error.details?.limit).toBe('account');
    expect(sixth.json<Err>().error.details?.retryAfterSeconds).toBe(44 * 60);
    time.advance(44 * 60_000 + 1_000);
    expect((await send(headers)).statusCode).toBe(200);
  });

  it('ten concurrent sends → exactly three succeed', async () => {
    const { headers } = await signedIn();
    const results = await Promise.all(Array.from({ length: 10 }, () => send(headers)));
    expect(results.filter((r) => r.statusCode === 200)).toHaveLength(3);
    expect(results.filter((r) => r.statusCode === 429)).toHaveLength(7);
  });

  it('five wrong attempts invalidate every live code; the right one then fails; a fresh send works again', async () => {
    const { user, headers } = await signedIn();
    await send(headers);
    const real = mail.latestCodeFor(user.email) ?? '';
    const wrong = real === '000000' ? '111111' : '000000';
    for (let i = 1; i <= 4; i += 1) {
      const res = await confirm(headers, wrong);
      expect(res.statusCode).toBe(422);
      expect(res.json<Err>().error.code).toBe('OTP_INCORRECT');
      expect(res.json<Err>().error.details?.attemptsRemaining).toBe(5 - i);
    }
    const fifth = await confirm(headers, wrong);
    expect(fifth.json<Err>().error.code).toBe('OTP_INVALIDATED');
    const late = await confirm(headers, real);
    expect(late.json<Err>().error.code).toBe('OTP_EXPIRED');
    time.advance(60_000);
    await send(headers);
    const fresh = mail.latestCodeFor(user.email) ?? '';
    expect((await confirm(headers, fresh)).statusCode).toBe(200);
  });

  it('every live code works until it expires; an expired one is OTP_EXPIRED', async () => {
    const { user, headers } = await signedIn();
    await send(headers);
    const first = mail.latestCodeFor(user.email) ?? '';
    time.advance(60_000);
    await send(headers);
    const second = mail.latestCodeFor(user.email) ?? '';
    expect(second).not.toBe(first);
    // Both live: the FIRST one still verifies.
    expect((await confirm(headers, first)).statusCode).toBe(200);
    const other = await signedIn();
    await send(other.headers);
    time.advance(11 * 60_000);
    const expired = await confirm(other.headers, mail.latestCodeFor(other.user.email) ?? '');
    expect(expired.json<Err>().error.code).toBe('OTP_EXPIRED');
  });

  it('a suppressed address is reported as suppressed, not pretended sent', async () => {
    const { user, headers } = await signedIn();
    await ctx.prisma.emailSuppression.create({ data: { address: user.email, reason: 'manual' } });
    const res = await send(headers);
    expect(res.statusCode).toBe(200);
    expect(res.json<{ data: { status: string } }>().data.status).toBe('suppressed');
  });
});
```

- [ ] **Step 6: Run to fail** — `npx vitest run test/auth-otp.test.ts` — Expected: FAIL.

- [ ] **Step 7: Let the error handler set `Retry-After` for any error carrying it**

In `backend/src/core/errors.ts` add after `RateLimitedError`:

```ts
/** Any error that should carry a Retry-After header. RateLimitedError is one; the OTP send limit is another. */
export interface RetryAfterCarrier {
  retryAfterSeconds: number;
}

export function carriesRetryAfter(error: AppError): error is AppError & RetryAfterCarrier {
  return typeof (error as Partial<RetryAfterCarrier>).retryAfterSeconds === 'number';
}
```

In `core/error-handler.ts` replace `if (error instanceof RateLimitedError)` with `if (carriesRetryAfter(error))` (and update the import). `RateLimitedError` already has the field, so behaviour is unchanged for it.

- [ ] **Step 8: Implement `otp.ts`**

```ts
import { createHash, randomInt, randomUUID } from 'node:crypto';

import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import { AppError, BusinessRuleError } from '../../core/errors.js';
import type { OtpPurpose, PrismaClient } from '../../generated/prisma/client.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import type { Db } from '../audit/types.js';
import type { EmailSender } from '../email/types.js';

export const OTP_ADDRESS_LIMIT = 3;
export const OTP_ADDRESS_WINDOW_MS = 15 * 60_000;
export const OTP_ACCOUNT_LIMIT = 5;
export const OTP_ACCOUNT_WINDOW_MS = 60 * 60_000;
export const OTP_ATTEMPT_LIMIT = 5;
/** What the client shows as its resend countdown. Advisory — the two limits above are the rule. */
export const OTP_RESEND_COOLDOWN_MS = 60_000;

export interface OtpSendResult {
  status: 'sent' | 'suppressed' | 'failed';
  expiresAt: Date;
  resendAvailableAt: Date;
}

/** 429 with the seconds remaining, so the UI shows a real countdown (plan §Phase 3). */
export class OtpRateLimitedError extends AppError {
  constructor(
    public readonly retryAfterSeconds: number,
    limit: 'address' | 'account',
  ) {
    super(429, 'OTP_RATE_LIMITED', 'Too many codes requested — wait before asking for another', {
      retryAfterSeconds,
      limit,
    });
  }
}

function codeHashFor(id: string, code: string): string {
  return createHash('sha256').update(`${id}|${code}`).digest('hex');
}

/**
 * Emailed six-digit codes (plan §Phase 3). Both send limits are enforced here,
 * not by the route tier — they key on the address and the account, not the
 * IP — inside a transaction that locks the user row, so concurrent sends
 * cannot slip a fourth one through. Every live code for a purpose stays valid
 * until it expires; five wrong attempts invalidate all of them.
 */
export class OtpService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      email: EmailSender;
      audit: AuditService;
      clock: Clock;
      config: Config;
    },
  ) {}

  /** Who may call: the auth and account services, for the signed-in user they are acting for. */
  async send(input: {
    userId: string;
    purpose: OtpPurpose;
    targetEmail: string;
    meta: RequestMeta;
  }): Promise<OtpSendResult> {
    const now = this.deps.clock();
    const targetEmail = input.targetEmail.trim().toLowerCase();
    const id = randomUUID();
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const expiresAt = new Date(now.getTime() + this.deps.config.auth.otpExpiryMinutes * 60_000);

    await this.deps.prisma.$transaction(async (tx) => {
      // Serialise per user: the two counts below and the insert must not
      // interleave with another send for the same account. Raw SQL because
      // Prisma has no row lock; "app_user" is the mapped table name.
      await tx.$queryRaw`SELECT id FROM app_user WHERE id = ${input.userId}::uuid FOR UPDATE`;
      await this.assertUnderLimits(tx, input.userId, targetEmail, now);
      await tx.emailOtp.create({
        data: {
          id,
          userId: input.userId,
          purpose: input.purpose,
          targetEmail,
          codeHash: codeHashFor(id, code),
          expiresAt,
          createdAt: now,
        },
      });
    });

    const outcome = await this.deps.email.send({
      channel: 'otp',
      to: targetEmail,
      recipientUserId: input.userId,
      subject: 'Your RaajjePro verification code',
      text: [
        `Your RaajjePro verification code is ${code}.`,
        '',
        `It expires in ${String(this.deps.config.auth.otpExpiryMinutes)} minutes.`,
        "If you didn't ask for this code, you can ignore this email — nothing changes without it.",
      ].join('\n'),
    });
    await this.deps.prisma.emailOtp.update({ where: { id }, data: { emailMessageId: outcome.messageId } });
    return {
      status: outcome.status,
      expiresAt,
      resendAvailableAt: new Date(now.getTime() + OTP_RESEND_COOLDOWN_MS),
    };
  }

  /**
   * Who may call: the auth and account services, for the signed-in user.
   * Returns the address the matched code was sent to — the caller decides
   * what verifying it means (mark verified, or switch the account's email).
   */
  async confirm(input: {
    userId: string;
    purpose: OtpPurpose;
    code: string;
    meta: RequestMeta;
  }): Promise<{ targetEmail: string }> {
    const now = this.deps.clock();
    const code = input.code.trim();
    const live = await this.deps.prisma.emailOtp.findMany({
      where: {
        userId: input.userId,
        purpose: input.purpose,
        consumedAt: null,
        invalidatedAt: null,
        expiresAt: { gt: now },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (live.length === 0) {
      throw new BusinessRuleError('OTP_EXPIRED', 'That code has expired — request a fresh one');
    }
    const match = live.find((row) => row.codeHash === codeHashFor(row.id, code));
    if (match !== undefined) {
      const consumed = await this.deps.prisma.emailOtp.updateMany({
        where: { id: match.id, consumedAt: null },
        data: { consumedAt: now },
      });
      if (consumed.count === 0) {
        throw new BusinessRuleError('OTP_EXPIRED', 'That code was already used — request a fresh one');
      }
      return { targetEmail: match.targetEmail };
    }
    // Wrong: one attempt against every live code, since we cannot know which
    // one was meant. The fifth failure invalidates them all.
    const ids = live.map((row) => row.id);
    await this.deps.prisma.emailOtp.updateMany({ where: { id: { in: ids } }, data: { attempts: { increment: 1 } } });
    const attempts = Math.max(...live.map((row) => row.attempts)) + 1;
    if (attempts >= OTP_ATTEMPT_LIMIT) {
      await this.invalidateAll(this.deps.prisma, input.userId, input.purpose, now);
      throw new BusinessRuleError(
        'OTP_INVALIDATED',
        'That code has been invalidated after 5 incorrect attempts — request a fresh one',
      );
    }
    throw new BusinessRuleError('OTP_INCORRECT', "That code isn't right", {
      attemptsRemaining: OTP_ATTEMPT_LIMIT - attempts,
    });
  }

  invalidateAll(db: Db, userId: string, purpose: OtpPurpose, now: Date): Promise<{ count: number }> {
    return db.emailOtp.updateMany({
      where: { userId, purpose, consumedAt: null, invalidatedAt: null },
      data: { invalidatedAt: now },
    });
  }

  private async assertUnderLimits(db: Db, userId: string, targetEmail: string, now: Date): Promise<void> {
    const [byAddress, byAccount] = await Promise.all([
      db.emailOtp.findMany({
        where: { targetEmail, createdAt: { gt: new Date(now.getTime() - OTP_ADDRESS_WINDOW_MS) } },
        orderBy: { createdAt: 'asc' },
        select: { createdAt: true },
      }),
      db.emailOtp.findMany({
        where: { userId, createdAt: { gt: new Date(now.getTime() - OTP_ACCOUNT_WINDOW_MS) } },
        orderBy: { createdAt: 'asc' },
        select: { createdAt: true },
      }),
    ]);
    const waits: { seconds: number; limit: 'address' | 'account' }[] = [];
    const oldestAddress = byAddress[0];
    if (byAddress.length >= OTP_ADDRESS_LIMIT && oldestAddress !== undefined) {
      waits.push({
        seconds: Math.ceil((oldestAddress.createdAt.getTime() + OTP_ADDRESS_WINDOW_MS - now.getTime()) / 1000),
        limit: 'address',
      });
    }
    const oldestAccount = byAccount[0];
    if (byAccount.length >= OTP_ACCOUNT_LIMIT && oldestAccount !== undefined) {
      waits.push({
        seconds: Math.ceil((oldestAccount.createdAt.getTime() + OTP_ACCOUNT_WINDOW_MS - now.getTime()) / 1000),
        limit: 'account',
      });
    }
    const worst = waits.sort((a, b) => b.seconds - a.seconds)[0];
    if (worst !== undefined) throw new OtpRateLimitedError(Math.max(worst.seconds, 1), worst.limit);
  }
}
```

Note the address-window count is over `targetEmail` regardless of which user sent — the plan's limit is per address. The `FOR UPDATE` lock serialises per user; two *different* users hammering one address can still race past the address count by one. That is acceptable and noted: the address limit's purpose is protecting a mailbox from a flood, and the per-user lock plus the route tier bound the flood.

- [ ] **Step 9: Schema, routes, wiring**

Add to `schema.ts`: `export const otpCodeBody = z.object({ code: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code') });`

Add to `routes.ts` inside `registerAuthRoutes`:

```ts
  // Who may call: the signed-in user whose email is not yet verified. Domain
  // limits are the rule (3/address/15 min, 5/account/hour); this tier only
  // stops a misbehaving client turning them into a flood of 429s.
  r.post(
    `${prefix}/verify-email/send`,
    { preHandler: requireAuth, config: { rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` } } },
    async (request, reply) => {
      const p = userOf(request);
      const user = await app.auth.repo.findById(p.id);
      if (user === null) throw new Error('principal without a user row');
      if (user.emailVerifiedAt !== null) {
        throw new BusinessRuleError('EMAIL_ALREADY_VERIFIED', 'This email address is already verified');
      }
      const result = await app.otp.send({ userId: p.id, purpose: 'verify_email', targetEmail: user.email, meta: requestMeta(request) });
      return reply.send(ok({ status: result.status, expiresAt: result.expiresAt.toISOString(), resendAvailableAt: result.resendAvailableAt.toISOString() }));
    },
  );

  // Who may call: the signed-in user. Tier 10/5 min per principal — above the
  // 5-attempt rule so the fifth failure is answered by invalidation, not 429.
  r.post(
    `${prefix}/verify-email/confirm`,
    { schema: { body: otpCodeBody }, preHandler: requireAuth, config: { rateLimit: { max: 10, timeWindow: '5 minutes' } } },
    async (request, reply) => {
      const p = userOf(request);
      await app.auth.markEmailVerified(p, request.body.code, requestMeta(request));
      return reply.send(ok({ emailVerified: true }));
    },
  );
```

Add to `AuthService`:

```ts
  /** Who may call: the signed-in user, with a code from their inbox. */
  async markEmailVerified(principal: UserPrincipal, code: string, meta: RequestMeta): Promise<void> {
    const { targetEmail } = await this.deps.otp.confirm({ userId: principal.id, purpose: 'verify_email', code, meta });
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.updateMany({ where: { id: principal.id, email: targetEmail, emailVerifiedAt: null }, data: { emailVerifiedAt: now } });
      await this.deps.audit.record(tx, {
        actorType: 'user', actorId: principal.id, action: 'user.email.verified',
        targetType: 'user', targetId: principal.id, reason: 'otp_confirmed',
        requestId: meta.requestId, ipAddress: meta.ip,
      });
    });
  }
```

`AuthService`'s constructor deps gain `otp: OtpService`. In `app.ts`: build `const otp = new OtpService({ prisma: deps.prisma, email: <the EmailService instance>, audit, clock: deps.clock, config })` — pull the `EmailService` construction into a local `const email = new EmailService(...)` before decorating so both can use it — then `app.decorate('otp', otp)` and pass `otp` into `AuthService`. Add `otp: OtpService;` to the `FastifyInstance` augmentation.

- [ ] **Step 10: Run, lint, typecheck** — `npx vitest run test/auth-otp.test.ts test/auth-phone.test.ts test/auth-sessions.test.ts && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add backend/src backend/test
git commit -m "Email OTP: both send limits inside a per-user lock, five attempts then invalidation, verify-email routes; phone normalisation"
```

---

### Task 5: Register, login, `getOrCreateProviderProfile`, and the social-auth stubs

**Files:**
- Modify: `backend/src/modules/auth/repository.ts`, `backend/src/modules/auth/service.ts`, `backend/src/modules/auth/schema.ts`, `backend/src/modules/auth/routes.ts`, `backend/src/app.ts`
- Create: `backend/src/modules/auth/social.ts`
- Modify: `backend/test/helpers/users.ts` (add `registerUser`)
- Test: `backend/test/auth-register-login.test.ts`

**Interfaces:**
- Consumes: Task 3 `openSession`, Task 4 `normalisePhone`, `OtpService.send`, `hashPassword`/`verifyPassword`/`DUMMY_PASSWORD_HASH`.
- Produces:
  - `UserRepository.create(db, data)`, `UserRepository.phoneHeldAtBronzeOrAbove(e164, excludingUserId?)` → `boolean`, `UserRepository.getOrCreateProviderProfile(db, userId, businessName?)`.
  - `AuthService.register(input: RegisterInput, meta)` → `{ user: UserWithProfile; tokens: TokenPair; verification: OtpSendResult }`; `AuthService.login(email, password, deviceName, meta)` → `{ user; tokens }`.
  - `RegisterInput = { role: 'customer' | 'provider'; fullName; email; phone: { dialCode; number }; password; businessName?: string; deviceName?: string }`.
  - `SocialAuthProvider { readonly name: SocialProviderName; verify(idToken: string): Promise<SocialIdentity> }`, `SocialProviderName = 'apple' | 'google' | 'facebook' | 'viber'`, `SocialIdentity = { providerUserId: string; email?: string; fullName?: string }`, `SocialAuthRegistry.get(name)`, `stubProviders()`.
  - `registerUser(app, overrides?)` test helper → `{ email, phone, password, userId, tokens, headers }`.
  - Constants `MIN_USER_PASSWORD_LENGTH = 8`, `MAX_USER_PASSWORD_LENGTH = 512`.

- [ ] **Step 1: Extend the test helper**

Append to `backend/test/helpers/users.ts`:

```ts
import type { FastifyInstance } from 'fastify';
import { freshIp } from './app.js';

export interface RegisteredUser {
  userId: string;
  email: string;
  phone: string;
  password: string;
  tokens: { accessToken: string; refreshToken: string };
  headers: { authorization: string };
}

/** Registers through the real route, exactly as the app does. */
export async function registerUser(
  app: FastifyInstance,
  overrides: Partial<{ role: 'customer' | 'provider'; email: string; phone: string; dialCode: string; businessName: string; password: string }> = {},
): Promise<RegisteredUser> {
  const email = overrides.email ?? freshEmail();
  const phone = overrides.phone ?? freshPhone();
  const password = overrides.password ?? USER_PASSWORD;
  const role = overrides.role ?? 'customer';
  const res = await app.inject({
    method: 'POST',
    url: '/v1/auth/register',
    remoteAddress: freshIp(),
    headers: { 'idempotency-key': randomUUID() },
    payload: {
      role,
      fullName: 'Aishath Test',
      email,
      phone: { dialCode: overrides.dialCode ?? '+960', number: phone },
      password,
      ...(role === 'provider' ? { businessName: overrides.businessName ?? 'Test Trade' } : {}),
      acceptTerms: true,
      deviceName: 'vitest',
    },
  });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  const body = res.json<{ data: { user: { id: string }; tokens: { accessToken: string; refreshToken: string } } }>().data;
  return { userId: body.user.id, email, phone, password, tokens: body.tokens, headers: bearer(body.tokens.accessToken) };
}
```

- [ ] **Step 2: Failing tests**

`backend/test/auth-register-login.test.ts`:

```ts
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, freshEmail, freshPhone, RecordingEmailTransport, registerUser, USER_PASSWORD } from './helpers/users.js';

type Err = { error: { code: string; details?: { path: string; message: string }[] } };

describe.skipIf(databaseUrl === undefined)('register and login', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const post = (payload: unknown, headers: Record<string, string> = { 'idempotency-key': randomUUID() }) =>
    ctx.app.inject({ method: 'POST', url: '/v1/auth/register', remoteAddress: freshIp(), headers, payload });

  const validBody = (over: Record<string, unknown> = {}) => ({
    role: 'customer',
    fullName: 'Aishath Naeema',
    email: freshEmail(),
    phone: { dialCode: '+960', number: freshPhone() },
    password: USER_PASSWORD,
    acceptTerms: true,
    ...over,
  });

  it('registers a customer: 201, signed in, unverified, OTP sent, terms recorded, audited', async () => {
    const email = freshEmail();
    const res = await post(validBody({ email: ` ${email.toUpperCase()} ` }));
    expect(res.statusCode).toBe(201);
    const data = res.json<{ data: { user: Record<string, unknown>; tokens: Record<string, string>; verification: { status: string } } }>().data;
    expect(data.user.email).toBe(email.toLowerCase());
    expect(data.user.emailVerified).toBe(false);
    expect(data.user.isProvider).toBe(false);
    expect(data.verification.status).toBe('sent');
    expect(mail.latestCodeFor(email)).toMatch(/^\d{6}$/);
    expect(res.body).not.toContain('passwordHash');
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(data.tokens.accessToken ?? '') });
    expect(me.statusCode).toBe(200);
    const row = await ctx.prisma.user.findUniqueOrThrow({ where: { email: email.toLowerCase() } });
    expect(row.termsAcceptedAt).toBeTruthy();
    expect(row.phoneE164?.startsWith('+960')).toBe(true);
    const audit = await ctx.prisma.auditLogEntry.findFirst({ where: { action: 'user.registered', actorId: row.id } });
    expect(audit?.actorType).toBe('user');
    expect(JSON.stringify(audit?.metadata)).not.toContain(email.toLowerCase());
  });

  it('registers a provider with a business name and creates the minimal ProviderProfile at tier none', async () => {
    const res = await post(validBody({ role: 'provider', businessName: 'Rasheed Plumbing Services' }));
    expect(res.statusCode).toBe(201);
    const data = res.json<{ data: { user: { id: string; isProvider: boolean } } }>().data;
    expect(data.user.isProvider).toBe(true);
    const profile = await ctx.prisma.providerProfile.findUniqueOrThrow({ where: { userId: data.user.id } });
    expect(profile.businessName).toBe('Rasheed Plumbing Services');
    expect(profile.verificationTier).toBe('none');
    expect(profile.verificationStatus).toBe('unverified');
    // getOrCreateProviderProfile is idempotent (§1a).
    const again = await ctx.app.auth.repo.getOrCreateProviderProfile(ctx.prisma, data.user.id);
    expect(again.id).toBe(profile.id);
  });

  it('validates the body: provider without a business name, customer with one, unaccepted terms, short password', async () => {
    for (const [body, path] of [
      [validBody({ role: 'provider' }), 'businessName'],
      [validBody({ businessName: 'Nope' }), 'businessName'],
      [validBody({ acceptTerms: false }), 'acceptTerms'],
      [validBody({ password: 'short' }), 'password'],
      [validBody({ phone: { dialCode: '+960', number: '123' } }), 'phone'],
    ] as const) {
      const res = await post(body);
      expect(res.statusCode, path).toBe(400);
      expect(res.json<Err>().error.details?.some((d) => d.path.startsWith(path)), path).toBe(true);
    }
  });

  it('a duplicate email is blocked at the field, naming it, whatever the case', async () => {
    const first = await registerUser(ctx.app);
    const res = await post(validBody({ email: first.email.toUpperCase() }));
    expect(res.statusCode).toBe(409);
    const err = res.json<Err>().error;
    expect(err.code).toBe('EMAIL_IN_USE');
    expect(err.details?.[0]?.path).toBe('email');
    expect(res.body).not.toContain(first.phone);
  });

  it('a duplicate phone is blocked only when held at Bronze or above, and formatting variants collide', async () => {
    const shared = freshPhone();
    const holder = await registerUser(ctx.app, { role: 'provider', phone: shared });
    // Held at tier none: another account may claim it silently.
    expect((await post(validBody({ phone: { dialCode: '+960', number: shared } }))).statusCode).toBe(201);
    await ctx.prisma.providerProfile.update({ where: { userId: holder.userId }, data: { verificationTier: 'bronze' } });
    const blocked = await post(validBody({ phone: { dialCode: '+960', number: `${shared.slice(0, 3)}-${shared.slice(3)}` } }));
    expect(blocked.statusCode).toBe(409);
    expect(blocked.json<Err>().error.code).toBe('PHONE_IN_USE');
    expect(blocked.json<Err>().error.details?.[0]?.path).toBe('phone');
    // A different dial code is a different number.
    expect((await post(validBody({ phone: { dialCode: '+44', number: shared } }))).statusCode).toBe(201);
  });

  it('registration needs an Idempotency-Key and replays the original result on a retry', async () => {
    const body = validBody();
    const none = await ctx.app.inject({ method: 'POST', url: '/v1/auth/register', remoteAddress: freshIp(), payload: body });
    expect(none.statusCode).toBe(400);
    expect(none.json<Err>().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');
    const key = randomUUID();
    const ip = freshIp();
    const a = await ctx.app.inject({ method: 'POST', url: '/v1/auth/register', remoteAddress: ip, headers: { 'idempotency-key': key }, payload: body });
    const b = await ctx.app.inject({ method: 'POST', url: '/v1/auth/register', remoteAddress: ip, headers: { 'idempotency-key': key }, payload: body });
    expect(a.statusCode).toBe(201);
    expect(b.statusCode).toBe(201);
    expect(b.headers['idempotent-replayed']).toBe('true');
    expect(b.body).toBe(a.body);
    expect(await ctx.prisma.user.count({ where: { email: (body.email as string).toLowerCase() } })).toBe(1);
  });

  it('login: right password → tokens; wrong password, unknown email and a frozen-then-anonymised account all read INVALID_CREDENTIALS', async () => {
    const u = await registerUser(ctx.app);
    const login = (email: string, password: string) =>
      ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: freshIp(), payload: { email, password, deviceName: 'Pixel 7' } });
    const ok = await login(u.email, u.password);
    expect(ok.statusCode).toBe(200);
    expect(ok.json<{ data: { tokens: { accessToken: string } } }>().data.tokens.accessToken).toBeTruthy();
    const wrong = await login(u.email, 'not the password');
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    const unknown = await login(freshEmail(), u.password);
    expect(unknown.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    const failed = await ctx.prisma.auditLogEntry.findFirst({ where: { action: 'user.login.failed', targetId: u.userId } });
    expect(failed?.reason).toBe('wrong_password');
    await ctx.prisma.user.update({ where: { id: u.userId }, data: { status: 'anonymised' } });
    expect((await login(u.email, u.password)).json<Err>().error.code).toBe('INVALID_CREDENTIALS');
  });

  it('a frozen account still signs in and its DTO says so', async () => {
    const u = await registerUser(ctx.app);
    await ctx.prisma.user.update({ where: { id: u.userId }, data: { status: 'frozen', deletionDeadlineAt: new Date('2026-10-06T10:00:00Z') } });
    const res = await ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: freshIp(), payload: { email: u.email, password: u.password } });
    expect(res.statusCode).toBe(200);
    expect(res.json<{ data: { user: { status: string; deletionDeadlineAt: string } } }>().data.user.status).toBe('frozen');
  });

  it('login is tiered 10 per 15 minutes per IP', async () => {
    const ip = freshIp();
    const u = await registerUser(ctx.app);
    for (let i = 0; i < 10; i += 1) {
      await ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: ip, payload: { email: u.email, password: 'wrong wrong wrong' } });
    }
    const eleventh = await ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: ip, payload: { email: u.email, password: u.password } });
    expect(eleventh.statusCode).toBe(429);
  });

  it('social sign-in exists as a contract and every provider is a stub', async () => {
    for (const provider of ['apple', 'google', 'facebook', 'viber']) {
      const res = await ctx.app.inject({ method: 'POST', url: `/v1/auth/social/${provider}`, remoteAddress: freshIp(), payload: { idToken: 'x'.repeat(40) } });
      expect(res.statusCode, provider).toBe(422);
      expect(res.json<Err>().error.code).toBe('SOCIAL_AUTH_UNAVAILABLE');
    }
    expect((await ctx.app.inject({ method: 'POST', url: '/v1/auth/social/myspace', remoteAddress: freshIp(), payload: { idToken: 'x'.repeat(40) } })).statusCode).toBe(400);
  });
});
```

- [ ] **Step 3: Run to fail** — `npx vitest run test/auth-register-login.test.ts` — Expected: FAIL.

- [ ] **Step 4: Repository additions**

Add to `UserRepository`:

```ts
  create(
    db: Db,
    data: {
      email: string;
      passwordHash: string;
      fullName: string;
      phoneE164: string;
      phoneDialCode: string;
      now: Date;
    },
  ): Promise<User> {
    return db.user.create({
      data: {
        email: data.email,
        passwordHash: data.passwordHash,
        fullName: data.fullName,
        phoneE164: data.phoneE164,
        phoneDialCode: data.phoneDialCode,
        termsAcceptedAt: data.now,
        passwordChangedAt: data.now,
        createdAt: data.now,
      },
    });
  }

  /**
   * The Bronze-uniqueness rule (plan §Phase 3, Round 15): a number is
   * exclusive only once an account holding it has a ProviderProfile at
   * bronze or above. Below that, several accounts may hold it.
   */
  async phoneHeldAtBronzeOrAbove(phoneE164: string, excludingUserId?: string): Promise<boolean> {
    const holder = await this.prisma.user.findFirst({
      where: {
        phoneE164,
        status: { not: 'anonymised' },
        ...(excludingUserId === undefined ? {} : { id: { not: excludingUserId } }),
        providerProfile: { is: { verificationTier: { in: ['bronze', 'silver', 'gold'] } } },
      },
      select: { id: true },
    });
    return holder !== null;
  }

  /** Idempotent (§1a). Phase 6a and Phase 8 call this too; Phase 5 extends what it sets. */
  async getOrCreateProviderProfile(db: Db, userId: string, businessName?: string): Promise<ProviderProfile> {
    const existing = await db.providerProfile.findUnique({ where: { userId } });
    if (existing !== null) return existing;
    return db.providerProfile.create({
      data: { userId, ...(businessName === undefined ? {} : { businessName }) },
    });
  }
```

- [ ] **Step 5: Service additions**

Add to `service.ts` (imports: `ConflictError`, `BusinessRuleError` unused here; `hashPassword`, `verifyPassword`, `DUMMY_PASSWORD_HASH` from `../admin-auth/crypto.js`; `normalisePhone` from `./phone.js`; `Prisma` from the generated client for `PrismaClientKnownRequestError`; `OtpSendResult`):

```ts
export const MIN_USER_PASSWORD_LENGTH = 8;
export const MAX_USER_PASSWORD_LENGTH = 512;

export interface RegisterInput {
  role: 'customer' | 'provider';
  fullName: string;
  email: string;
  phone: { dialCode: string; number: string };
  password: string;
  businessName?: string;
  deviceName?: string;
}

export function emailInUse(): ConflictError {
  const error = new ConflictError('EMAIL_IN_USE', 'This email already has a RaajjePro account.');
  return Object.assign(error, {
    details: [{ path: 'email', message: 'This email already has a RaajjePro account.' }],
  });
}

export function phoneInUse(): ConflictError {
  const error = new ConflictError('PHONE_IN_USE', 'This number belongs to a verified provider account.');
  return Object.assign(error, {
    details: [{ path: 'phone', message: 'This number belongs to a verified provider account.' }],
  });
}
```

`ConflictError`'s constructor takes no details; rather than `Object.assign` on a readonly field, change `core/errors.ts`'s `ConflictError` to accept an optional third `details?: unknown` argument and pass it to `super` — an additive change. Then `emailInUse()` becomes `new ConflictError('EMAIL_IN_USE', msg, [{ path: 'email', message: msg }])`.

Methods on `AuthService`:

```ts
  /** Who may call: anyone — this is how an account begins. Idempotency-Key required by the route. */
  async register(input: RegisterInput, meta: RequestMeta): Promise<{ user: UserWithProfile; tokens: TokenPair; verification: OtpSendResult }> {
    const email = input.email.trim().toLowerCase();
    const phone = normalisePhone(input.phone);
    const now = this.deps.clock();

    if ((await this.repo.findByEmail(email)) !== null) throw emailInUse();
    if (await this.repo.phoneHeldAtBronzeOrAbove(phone.e164)) throw phoneInUse();

    const passwordHash = await hashPassword(input.password);
    let created: User;
    try {
      created = await this.deps.prisma.$transaction(async (tx) => {
        const user = await this.repo.create(tx, {
          email,
          passwordHash,
          fullName: input.fullName.trim(),
          phoneE164: phone.e164,
          phoneDialCode: phone.dialCode,
          now,
        });
        if (input.role === 'provider') {
          await this.repo.getOrCreateProviderProfile(tx, user.id, input.businessName?.trim());
        }
        await this.deps.audit.record(tx, {
          actorType: 'user',
          actorId: user.id,
          action: 'user.registered',
          targetType: 'user',
          targetId: user.id,
          reason: 'user_initiated',
          metadata: { role: input.role },
          requestId: meta.requestId,
          ipAddress: meta.ip,
        });
        return user;
      });
    } catch (error) {
      // The unique index is the last line against a concurrent duplicate.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw emailInUse();
      throw error;
    }
    const user = await this.repo.findById(created.id);
    if (user === null) throw new Error('user vanished after create');
    const tokens = await this.openSession(user, meta, now, input.deviceName, 'user.login.succeeded');
    const verification = await this.deps.otp.send({ userId: user.id, purpose: 'verify_email', targetEmail: email, meta });
    return { user, tokens, verification };
  }

  /** Who may call: anyone with an email and password. Tier: 10 per 15 min per IP (route). */
  async login(emailInput: string, password: string, deviceName: string | undefined, meta: RequestMeta): Promise<{ user: UserWithProfile; tokens: TokenPair }> {
    const email = emailInput.trim().toLowerCase();
    const user = await this.repo.findByEmail(email);
    // One argon2 verification whatever happens, so timing does not reveal existence.
    const passwordOk = await verifyPassword(user?.passwordHash ?? DUMMY_PASSWORD_HASH, password);
    const invalid = () => new AuthenticationError('INVALID_CREDENTIALS', 'That email and password combination didn\'t work');
    if (user === null) throw invalid();
    if (!passwordOk || user.status === 'anonymised') {
      await this.deps.audit.record(this.deps.prisma, {
        actorType: 'system',
        action: 'user.login.failed',
        targetType: 'user',
        targetId: user.id,
        reason: user.status === 'anonymised' ? 'account_anonymised' : 'wrong_password',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      throw invalid();
    }
    const tokens = await this.openSession(user, meta, this.deps.clock(), deviceName);
    return { user, tokens };
  }
```

Note `openSession`'s `action` parameter: register records `user.registered` in its own transaction and then `user.login.succeeded` for the session it opens — two rows, both true.

- [ ] **Step 6: Social stubs**

`backend/src/modules/auth/social.ts`:

```ts
import { BusinessRuleError } from '../../core/errors.js';

export const SOCIAL_PROVIDERS = ['apple', 'google', 'facebook', 'viber'] as const;
export type SocialProviderName = (typeof SOCIAL_PROVIDERS)[number];

export interface SocialIdentity {
  providerUserId: string;
  email?: string;
  fullName?: string;
}

/**
 * Provider-agnostic social sign-in (plan §Phase 3: "interface with stubs";
 * Apple added by §1 divergence 6 because App Review requires it wherever
 * another third-party sign-in exists). Real implementations are post-v1
 * (plan §6). The interface fixes the seam; the stubs fix the client contract.
 */
export interface SocialAuthProvider {
  readonly name: SocialProviderName;
  verify(idToken: string): Promise<SocialIdentity>;
}

class StubProvider implements SocialAuthProvider {
  constructor(readonly name: SocialProviderName) {}
  verify(): Promise<SocialIdentity> {
    return Promise.reject(
      new BusinessRuleError(
        'SOCIAL_AUTH_UNAVAILABLE',
        `Sign-in with ${this.name} isn't available yet — use your email and password`,
      ),
    );
  }
}

export class SocialAuthRegistry {
  private readonly providers: Map<SocialProviderName, SocialAuthProvider>;
  constructor(providers: SocialAuthProvider[]) {
    this.providers = new Map(providers.map((p) => [p.name, p]));
  }
  get(name: SocialProviderName): SocialAuthProvider {
    const provider = this.providers.get(name);
    if (provider === undefined) throw new Error(`no social provider registered for ${name}`);
    return provider;
  }
}

export function stubProviders(): SocialAuthProvider[] {
  return SOCIAL_PROVIDERS.map((name) => new StubProvider(name));
}
```

- [ ] **Step 7: Schemas and routes**

Add to `schema.ts`:

```ts
import { MAX_USER_PASSWORD_LENGTH, MIN_USER_PASSWORD_LENGTH } from './service.js';
import { SOCIAL_PROVIDERS } from './social.js';

export const emailField = z.string().trim().pipe(z.email()).pipe(z.string().max(320));
export const passwordField = z.string().min(MIN_USER_PASSWORD_LENGTH).max(MAX_USER_PASSWORD_LENGTH);
export const phoneField = z.object({ dialCode: z.string().trim().min(2).max(5), number: z.string().trim().min(1).max(40) });

export const registerBody = z
  .object({
    role: z.enum(['customer', 'provider']),
    fullName: z.string().trim().min(1).max(120),
    email: emailField,
    phone: phoneField,
    password: passwordField,
    businessName: z.string().trim().min(1).max(120).optional(),
    acceptTerms: z.literal(true, { error: 'You need to accept the terms to continue' }),
    deviceName,
  })
  .superRefine((body, ctx) => {
    if (body.role === 'provider' && body.businessName === undefined) {
      ctx.addIssue({ code: 'custom', path: ['businessName'], message: 'Business or trade name is required' });
    }
    if (body.role === 'customer' && body.businessName !== undefined) {
      ctx.addIssue({ code: 'custom', path: ['businessName'], message: 'Only a provider account has a business name' });
    }
  });

export const loginBody = z.object({ email: emailField, password: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH), deviceName });
export const socialParams = z.object({ provider: z.enum(SOCIAL_PROVIDERS) });
export const socialBody = z.object({ idToken: z.string().min(20).max(8192), deviceName });
```

(`phone` detail validation is `normalisePhone`'s job, so its `ValidationError` carries `path: 'phone'`; Zod only bounds the strings.) If importing `service.js` from `schema.js` creates an import cycle the type checker dislikes, move the two password constants into `tokens.ts` — they are constants, not behaviour.

Routes, inside `registerAuthRoutes`:

```ts
  // Who may call: anyone — an account begins here. Creation POST, so
  // Idempotency-Key is required (subject anon:<ip> — the Phase 2 proposal,
  // confirmed in the Phase 3 spec). Tier 5/hour per IP.
  r.post(
    `${prefix}/register`,
    {
      schema: { body: registerBody },
      config: {
        idempotency: { operation: 'auth.register' },
        rateLimit: { max: 5, timeWindow: '1 hour', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const result = await app.auth.register(request.body, requestMeta(request));
      return reply.code(201).send(
        ok({
          user: userDto(result.user),
          tokens: tokensDto(result.tokens),
          verification: {
            status: result.verification.status,
            expiresAt: result.verification.expiresAt.toISOString(),
            resendAvailableAt: result.verification.resendAvailableAt.toISOString(),
          },
        }),
      );
    },
  );

  // Who may call: anyone with credentials. Tier 10 per 15 min per IP, keyed explicitly.
  r.post(
    `${prefix}/login`,
    { schema: { body: loginBody }, config: { rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` } } },
    async (request, reply) => {
      const { email, password, deviceName: device } = request.body;
      const result = await app.auth.login(email, password, device, requestMeta(request));
      return reply.send(ok({ user: userDto(result.user), tokens: tokensDto(result.tokens) }));
    },
  );

  // Who may call: anyone with a third-party id token. Every provider is a stub in v1.
  r.post(
    `${prefix}/social/:provider`,
    { schema: { params: socialParams, body: socialBody }, config: { rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` } } },
    async (request, reply) => {
      const identity = await app.social.get(request.params.provider).verify(request.body.idToken);
      // Unreachable while every provider is a stub; when one becomes real, this
      // is where identity → user lookup/creation is added.
      return reply.send(ok({ identity }));
    },
  );
```

Note the test expects an unknown provider to be 400 (Zod on params). In `app.ts`: `app.decorate('social', new SocialAuthRegistry(stubProviders()))` and `social: SocialAuthRegistry;` in the augmentation.

- [ ] **Step 8: Run, lint, typecheck** — `npx vitest run test/auth-register-login.test.ts && npm test && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/src backend/test
git commit -m "Register and login: field-level duplicate email, Bronze-only phone exclusivity, minimal provider profile, social stubs"
```

---

### Task 6: Account settings — change password, change email (OTP to the new address), change phone, `assertRecoverableByEmail`

**Files:**
- Create: `backend/src/modules/account/service.ts`, `backend/src/modules/account/schema.ts`, `backend/src/modules/account/routes.ts`
- Modify: `backend/src/app.ts`
- Test: `backend/test/account-settings.test.ts`

**Interfaces:**
- Consumes: `AuthService.repo` (`UserRepository`), `OtpService`, `normalisePhone`, `emailInUse`/`phoneInUse`, `requireAuth`/`userOf`, `hashPassword`/`verifyPassword`.
- Produces: `AccountService` with `changePassword(principal, currentPassword, newPassword, meta)`, `requestEmailChange(principal, newEmail, currentPassword, meta)` → `OtpSendResult & { newEmail }`, `confirmEmailChange(principal, code, meta)` → `UserWithProfile`, `changePhone(principal, phone, meta)` → `UserWithProfile`, `assertRecoverableByEmail(user: { emailVerifiedAt: Date | null })` (throws `BusinessRuleError('EMAIL_NOT_VERIFIED')`). `app.account: AccountService`. Routes under `/v1/users/me`.

- [ ] **Step 1: Failing tests**

`backend/test/account-settings.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { assertRecoverableByEmail } from '../src/modules/account/service.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, freshEmail, freshPhone, RecordingEmailTransport, registerUser } from './helpers/users.js';

type Err = { error: { code: string; details?: { path: string }[] } };

describe.skipIf(databaseUrl === undefined)('account settings', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const login = (email: string, password: string, deviceName = 'other') =>
    ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: freshIp(), payload: { email, password, deviceName } });

  it('change password: wrong current → INVALID_CREDENTIALS at the field; right → other sessions revoked, this one kept, new password works', async () => {
    const u = await registerUser(ctx.app);
    const other = (await login(u.email, u.password)).json<{ data: { tokens: { accessToken: string } } }>().data.tokens;
    const wrong = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-password', headers: u.headers, payload: { currentPassword: 'nope nope nope', newPassword: 'a brand new password' } });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    const ok = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-password', headers: u.headers, payload: { currentPassword: u.password, newPassword: 'a brand new password' } });
    expect(ok.statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(other.accessToken) })).json<Err>().error.code).toBe('SESSION_EXPIRED');
    expect((await login(u.email, u.password)).statusCode).toBe(401);
    expect((await login(u.email, 'a brand new password')).statusCode).toBe(200);
    const row = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
    expect(row.passwordChangedAt.getTime()).toBe(time.clock().getTime());
  });

  it('change email: OTP goes to the NEW address, an in-use address is refused, confirm switches and re-verifies, other sessions revoked', async () => {
    const u = await registerUser(ctx.app);
    const taken = await registerUser(ctx.app);
    const inUse = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/request', headers: u.headers, payload: { newEmail: taken.email, currentPassword: u.password } });
    expect(inUse.statusCode).toBe(409);
    expect(inUse.json<Err>().error.code).toBe('EMAIL_IN_USE');
    const same = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/request', headers: u.headers, payload: { newEmail: u.email, currentPassword: u.password } });
    expect(same.json<Err>().error.code).toBe('EMAIL_UNCHANGED');
    const badPw = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/request', headers: u.headers, payload: { newEmail: freshEmail(), currentPassword: 'wrong wrong wrong' } });
    expect(badPw.json<Err>().error.code).toBe('INVALID_CREDENTIALS');

    const newEmail = freshEmail();
    const other = (await login(u.email, u.password)).json<{ data: { tokens: { accessToken: string } } }>().data.tokens;
    const req = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/request', headers: u.headers, payload: { newEmail, currentPassword: u.password } });
    expect(req.statusCode).toBe(200);
    expect(mail.latestCodeFor(newEmail)).toMatch(/^\d{6}$/);
    expect(mail.latestCodeFor(u.email)).not.toBe(mail.latestCodeFor(newEmail));
    const confirm = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/confirm', headers: u.headers, payload: { code: mail.latestCodeFor(newEmail) ?? '' } });
    expect(confirm.statusCode).toBe(200);
    const me = confirm.json<{ data: { email: string; emailVerified: boolean } }>().data;
    expect(me.email).toBe(newEmail.toLowerCase());
    expect(me.emailVerified).toBe(true);
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(other.accessToken) })).json<Err>().error.code).toBe('SESSION_EXPIRED');
    expect((await login(newEmail, u.password)).statusCode).toBe(200);
    expect((await login(u.email, u.password)).statusCode).toBe(401);
    const audit = await ctx.prisma.auditLogEntry.findFirst({ where: { action: 'user.email.changed', actorId: u.userId } });
    expect(JSON.stringify(audit)).not.toContain(newEmail.toLowerCase());
  });

  it('change email confirm refuses an address that became in-use between request and confirm', async () => {
    const u = await registerUser(ctx.app);
    const target = freshEmail();
    await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/request', headers: u.headers, payload: { newEmail: target, currentPassword: u.password } });
    await registerUser(ctx.app, { email: target });
    const confirm = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/change-email/confirm', headers: u.headers, payload: { code: mail.latestCodeFor(target) ?? '' } });
    expect(confirm.statusCode).toBe(409);
    expect(confirm.json<Err>().error.code).toBe('EMAIL_IN_USE');
  });

  it('change phone: format re-checked, Bronze-uniqueness re-checked, stored as entered, never marked verified', async () => {
    const u = await registerUser(ctx.app);
    const bad = await ctx.app.inject({ method: 'PATCH', url: '/v1/users/me/phone', headers: u.headers, payload: { dialCode: '+960', number: '12' } });
    expect(bad.statusCode).toBe(400);
    expect(bad.json<Err>().error.details?.[0]?.path).toBe('phone');
    const bronze = await registerUser(ctx.app, { role: 'provider' });
    await ctx.prisma.providerProfile.update({ where: { userId: bronze.userId }, data: { verificationTier: 'bronze' } });
    const held = await ctx.app.inject({ method: 'PATCH', url: '/v1/users/me/phone', headers: u.headers, payload: { dialCode: '+960', number: bronze.phone } });
    expect(held.statusCode).toBe(409);
    expect(held.json<Err>().error.code).toBe('PHONE_IN_USE');
    const fresh = freshPhone();
    const ok = await ctx.app.inject({ method: 'PATCH', url: '/v1/users/me/phone', headers: u.headers, payload: { dialCode: '+44', number: fresh } });
    expect(ok.statusCode).toBe(200);
    const dto = ok.json<{ data: Record<string, unknown> }>().data;
    expect(dto.phone).toEqual({ dialCode: '+44', number: fresh });
    expect(JSON.stringify(dto)).not.toMatch(/phoneVerified|verified":true/);
    // Keeping your own number is fine even at Bronze.
    await ctx.prisma.providerProfile.create({ data: { userId: u.userId, verificationTier: 'bronze' } });
    expect((await ctx.app.inject({ method: 'PATCH', url: '/v1/users/me/phone', headers: u.headers, payload: { dialCode: '+44', number: fresh } })).statusCode).toBe(200);
  });

  it('assertRecoverableByEmail: unverified throws EMAIL_NOT_VERIFIED, verified passes (the rule Phase 3b\'s reset calls)', () => {
    expect(() => assertRecoverableByEmail({ emailVerifiedAt: null })).toThrow(/EMAIL_NOT_VERIFIED|Verify/);
    expect(() => assertRecoverableByEmail({ emailVerifiedAt: new Date() })).not.toThrow();
  });

  it('every account route is 401 without a token', async () => {
    for (const [method, url] of [
      ['POST', '/v1/users/me/change-password'],
      ['POST', '/v1/users/me/change-email/request'],
      ['POST', '/v1/users/me/change-email/confirm'],
      ['PATCH', '/v1/users/me/phone'],
    ] as const) {
      const res = await ctx.app.inject({ method, url, payload: {} });
      expect(res.statusCode, `${method} ${url}`).toBe(401);
    }
  });
});
```

- [ ] **Step 2: Run to fail** — `npx vitest run test/account-settings.test.ts` — Expected: FAIL.

- [ ] **Step 3: Service**

`backend/src/modules/account/service.ts`:

```ts
import type { Clock } from '../../core/clock.js';
import { AuthenticationError, BusinessRuleError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';
import { Prisma, type PrismaClient } from '../../generated/prisma/client.js';
import { hashPassword, verifyPassword } from '../admin-auth/crypto.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import type { OtpSendResult, OtpService } from '../auth/otp.js';
import { normalisePhone } from '../auth/phone.js';
import type { UserRepository, UserWithProfile } from '../auth/repository.js';
import { emailInUse, phoneInUse } from '../auth/service.js';

/**
 * Email is the recovery channel (plan §Phase 3, Round 11), and only a verified
 * address can serve as one. Phase 3b's reset flow calls this before sending
 * anything; because its confirmation must not reveal whether an account
 * exists, the throw there becomes a silent non-send. The rule is the same.
 */
export function assertRecoverableByEmail(user: { emailVerifiedAt: Date | null }): void {
  if (user.emailVerifiedAt === null) {
    throw new BusinessRuleError('EMAIL_NOT_VERIFIED', 'Verify your email address before it can be used to recover your account');
  }
}

/** Account settings (plan §Phase 3): each change re-checks the credential, re-verifies where the plan says, and is audited. */
export class AccountService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      repo: UserRepository;
      otp: OtpService;
      audit: AuditService;
      clock: Clock;
    },
  ) {}

  private async loadOrThrow(userId: string): Promise<UserWithProfile> {
    const user = await this.deps.repo.findById(userId);
    if (user === null) throw new AuthenticationError('UNAUTHENTICATED', 'Sign in to continue');
    return user;
  }

  private async verifyCurrentPassword(user: UserWithProfile, password: string): Promise<void> {
    if (!(await verifyPassword(user.passwordHash, password))) {
      throw new AuthenticationError('INVALID_CREDENTIALS', 'Your current password is not right');
    }
  }

  /** Who may call: the signed-in user, for their own account. Revokes every other device. */
  async changePassword(principal: UserPrincipal, currentPassword: string, newPassword: string, meta: RequestMeta): Promise<void> {
    const user = await this.loadOrThrow(principal.id);
    await this.verifyCurrentPassword(user, currentPassword);
    const passwordHash = await hashPassword(newPassword);
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: user.id }, data: { passwordHash, passwordChangedAt: now } });
      await this.deps.repo.revokeOtherSessions(tx, user.id, principal.sessionId, now, 'password_change');
      await this.deps.audit.record(tx, {
        actorType: 'user', actorId: user.id, action: 'user.password.changed',
        targetType: 'user', targetId: user.id, reason: 'user_initiated',
        requestId: meta.requestId, ipAddress: meta.ip,
      });
    });
  }

  /** Who may call: the signed-in user. Sends the code to the NEW address; nothing changes until it is confirmed. */
  async requestEmailChange(principal: UserPrincipal, newEmailInput: string, currentPassword: string, meta: RequestMeta): Promise<OtpSendResult & { newEmail: string }> {
    const user = await this.loadOrThrow(principal.id);
    await this.verifyCurrentPassword(user, currentPassword);
    const newEmail = newEmailInput.trim().toLowerCase();
    if (newEmail === user.email) throw new BusinessRuleError('EMAIL_UNCHANGED', 'That is already your email address');
    if ((await this.deps.repo.findByEmail(newEmail)) !== null) throw emailInUse();
    const result = await this.deps.otp.send({ userId: user.id, purpose: 'change_email', targetEmail: newEmail, meta });
    return { ...result, newEmail };
  }

  /** Who may call: the signed-in user, with the code from the new inbox. Uniqueness is re-checked here — the index is the last word. */
  async confirmEmailChange(principal: UserPrincipal, code: string, meta: RequestMeta): Promise<UserWithProfile> {
    const { targetEmail } = await this.deps.otp.confirm({ userId: principal.id, purpose: 'change_email', code, meta });
    if ((await this.deps.repo.findByEmail(targetEmail)) !== null) throw emailInUse();
    const now = this.deps.clock();
    try {
      await this.deps.prisma.$transaction(async (tx) => {
        await tx.user.update({ where: { id: principal.id }, data: { email: targetEmail, emailVerifiedAt: now } });
        await this.deps.repo.revokeOtherSessions(tx, principal.id, principal.sessionId, now, 'email_change');
        await this.deps.otp.invalidateAll(tx, principal.id, 'verify_email', now);
        await this.deps.audit.record(tx, {
          actorType: 'user', actorId: principal.id, action: 'user.email.changed',
          targetType: 'user', targetId: principal.id, reason: 'otp_confirmed',
          requestId: meta.requestId, ipAddress: meta.ip,
        });
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw emailInUse();
      throw error;
    }
    return this.loadOrThrow(principal.id);
  }

  /** Who may call: the signed-in user. Format and Bronze-uniqueness re-checked; the number is never verified. */
  async changePhone(principal: UserPrincipal, phone: { dialCode: string; number: string }, meta: RequestMeta): Promise<UserWithProfile> {
    const normalised = normalisePhone(phone);
    if (await this.deps.repo.phoneHeldAtBronzeOrAbove(normalised.e164, principal.id)) throw phoneInUse();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: principal.id }, data: { phoneE164: normalised.e164, phoneDialCode: normalised.dialCode } });
      await this.deps.audit.record(tx, {
        actorType: 'user', actorId: principal.id, action: 'user.phone.changed',
        targetType: 'user', targetId: principal.id, reason: 'user_initiated',
        requestId: meta.requestId, ipAddress: meta.ip,
      });
    });
    return this.loadOrThrow(principal.id);
  }
}
```

- [ ] **Step 4: Schema and routes**

`backend/src/modules/account/schema.ts`:

```ts
import { z } from 'zod';

import { emailField, otpCodeBody, passwordField, phoneField } from '../auth/schema.js';
import { MAX_USER_PASSWORD_LENGTH } from '../auth/service.js';

export const changePasswordBody = z.object({
  currentPassword: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
  newPassword: passwordField,
});
export const changeEmailRequestBody = z.object({
  newEmail: emailField,
  currentPassword: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
});
export const changeEmailConfirmBody = otpCodeBody;
export const changePhoneBody = phoneField;
```

`backend/src/modules/account/routes.ts` (Task 7 adds two more routes):

```ts
import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { userDto } from '../auth/dto.js';
import { requireAuth, userOf } from '../auth/guards.js';
import { changeEmailConfirmBody, changeEmailRequestBody, changePasswordBody, changePhoneBody } from './schema.js';

export function registerAccountRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/users/me';
  const perPrincipal = (max: number, timeWindow: string) => ({ rateLimit: { max, timeWindow } });

  // Who may call: the signed-in user, for their own account. Password-guessing surface: 10/15 min per principal.
  r.post(`${prefix}/change-password`, { schema: { body: changePasswordBody }, preHandler: requireAuth, config: perPrincipal(10, '15 minutes') }, async (request, reply) => {
    await app.account.changePassword(userOf(request), request.body.currentPassword, request.body.newPassword, requestMeta(request));
    return reply.send(ok({ changed: true }));
  });

  // Who may call: the signed-in user. Same tier — it takes the current password.
  r.post(`${prefix}/change-email/request`, { schema: { body: changeEmailRequestBody }, preHandler: requireAuth, config: perPrincipal(10, '15 minutes') }, async (request, reply) => {
    const result = await app.account.requestEmailChange(userOf(request), request.body.newEmail, request.body.currentPassword, requestMeta(request));
    return reply.send(ok({ status: result.status, expiresAt: result.expiresAt.toISOString(), resendAvailableAt: result.resendAvailableAt.toISOString() }));
  });

  // Who may call: the signed-in user. 10/5 min per principal, above the 5-attempt rule.
  r.post(`${prefix}/change-email/confirm`, { schema: { body: changeEmailConfirmBody }, preHandler: requireAuth, config: perPrincipal(10, '5 minutes') }, async (request, reply) => {
    const user = await app.account.confirmEmailChange(userOf(request), request.body.code, requestMeta(request));
    return reply.send(ok(userDto(user)));
  });

  // Who may call: the signed-in user. The number is stored as given and never marked verified.
  r.patch(`${prefix}/phone`, { schema: { body: changePhoneBody }, preHandler: requireAuth }, async (request, reply) => {
    const user = await app.account.changePhone(userOf(request), request.body, requestMeta(request));
    return reply.send(ok(userDto(user)));
  });
}
```

Wire in `app.ts`: `account: AccountService;` in the augmentation; `app.decorate('account', new AccountService({ prisma: deps.prisma, repo: authService.repo, otp, audit, clock: deps.clock }))` (keep the `AuthService` instance in a local `authService` before decorating); `registerAccountRoutes(app);` after the auth routes.

- [ ] **Step 5: Run, lint, typecheck** — `npx vitest run test/account-settings.test.ts && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src backend/test
git commit -m "Account settings: change password, change email re-verified at the new address, change phone; the recovery-by-email rule"
```

---

### Task 7: Data export and the deletion request

**Files:**
- Create: `backend/src/modules/account/export.ts`
- Modify: `backend/src/modules/account/service.ts`, `backend/src/modules/account/routes.ts`, `backend/src/app.ts`
- Test: `backend/test/account-export-deletion.test.ts`

**Interfaces:**
- Produces: `ExportContributor = { key: string; collect(userId: string): Promise<unknown> }`; `ExportContributors.register(c)`, `.collectAll(userId)` → `Record<string, unknown>`; `AccountService.exportData(userId)` → `DataExport`; `AccountService.requestDeletion(principal, meta)` → `{ status: 'frozen'; deletionRequestedAt: Date; deletionDeadlineAt: Date }`; constant `DELETION_BACKSTOP_DAYS = 30`; `app.exportContributors`.

- [ ] **Step 1: Failing tests**

`backend/test/account-export-deletion.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { RecordingEmailTransport, registerUser } from './helpers/users.js';

describe.skipIf(databaseUrl === undefined)('data export and deletion request', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
    ctx.app.exportContributors.register({ key: 'testSection', collect: (userId) => Promise.resolve({ forUser: userId, rows: [1, 2, 3] }) });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('export returns complete own data as an attachment: account with phone, profile, sessions, contributor sections — no hash, no tokens', async () => {
    const u = await registerUser(ctx.app, { role: 'provider', businessName: 'Export Trade' });
    await ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: freshIp(), payload: { email: u.email, password: u.password, deviceName: 'Second device' } });
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/users/me/data-export', headers: u.headers });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-disposition']).toMatch(/attachment; filename="raajjepro-export-2026-09-06\.json"/);
    const body = res.json<{ data: Record<string, any> }>().data;
    expect(body.exportedAt).toBe(time.clock().toISOString());
    expect(body.account.email).toBe(u.email.toLowerCase());
    expect(body.account.phone).toEqual({ dialCode: '+960', number: u.phone });
    expect(body.account.termsAcceptedAt).toBeTruthy();
    expect(body.providerProfile.businessName).toBe('Export Trade');
    expect(body.providerProfile.verificationTier).toBe('none');
    expect(body.sessions).toHaveLength(2);
    expect(body.sessions.map((s: { deviceName: string }) => s.deviceName).sort()).toEqual(['Second device', 'vitest']);
    expect(body.testSection).toEqual({ forUser: u.userId, rows: [1, 2, 3] });
    expect(res.body).not.toContain('passwordHash');
    expect(res.body).not.toContain(u.tokens.refreshToken);
    expect(res.body).not.toContain('tokenHash');
  });

  it('a deletion request is accepted at once (202), freezes the account, keeps the session, and repeats idempotently', async () => {
    const u = await registerUser(ctx.app);
    const res = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/deletion-request', headers: u.headers });
    expect(res.statusCode).toBe(202);
    const data = res.json<{ data: { status: string; deletionRequestedAt: string; deletionDeadlineAt: string } }>().data;
    expect(data.status).toBe('frozen');
    expect(data.deletionRequestedAt).toBe('2026-09-06T10:00:00.000Z');
    expect(data.deletionDeadlineAt).toBe('2026-10-06T10:00:00.000Z');
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers });
    expect(me.statusCode).toBe(200);
    expect(me.json<{ data: { status: string } }>().data.status).toBe('frozen');
    time.advance(3_600_000);
    const again = await ctx.app.inject({ method: 'POST', url: '/v1/users/me/deletion-request', headers: u.headers });
    expect(again.statusCode).toBe(202);
    expect(again.json<{ data: { deletionRequestedAt: string } }>().data.deletionRequestedAt).toBe('2026-09-06T10:00:00.000Z');
    time.advance(-3_600_000);
    const audits = await ctx.prisma.auditLogEntry.count({ where: { action: 'user.deletion.requested', actorId: u.userId } });
    expect(audits).toBe(1);
  });
});
```

- [ ] **Step 2: Run to fail** — Expected: FAIL.

- [ ] **Step 3: `export.ts`**

```ts
export interface ExportContributor {
  /** The top-level key the section appears under. Stable — the export is a client-visible document. */
  key: string;
  collect(userId: string): Promise<unknown>;
}

/**
 * `GET /v1/users/me/data-export` (plan §Phase 3) grows by registration:
 * Phase 11 adds reviews, 17 bookings, 18 messages, each from its own module,
 * so the export is complete without this module knowing about them.
 */
export class ExportContributors {
  private readonly contributors = new Map<string, ExportContributor>();

  register(contributor: ExportContributor): void {
    if (this.contributors.has(contributor.key)) throw new Error(`export section already registered: ${contributor.key}`);
    this.contributors.set(contributor.key, contributor);
  }

  async collectAll(userId: string): Promise<Record<string, unknown>> {
    const sections: Record<string, unknown> = {};
    for (const [key, contributor] of this.contributors) sections[key] = await contributor.collect(userId);
    return sections;
  }
}
```

- [ ] **Step 4: Service additions**

Add `exportContributors: ExportContributors` to `AccountService`'s deps, and:

```ts
export const DELETION_BACKSTOP_DAYS = 30;

  /** Who may call: the signed-in user, for their own data. Own data — so the phone is present; nothing about anyone else ever is. */
  async exportData(userId: string): Promise<Record<string, unknown>> {
    const user = await this.loadOrThrow(userId);
    const sessions = await this.deps.repo.listLiveSessions(userId);
    const dto = userDto(user);
    return {
      exportedAt: this.deps.clock().toISOString(),
      account: {
        id: user.id,
        fullName: user.fullName,
        email: user.email,
        emailVerifiedAt: user.emailVerifiedAt?.toISOString() ?? null,
        phone: dto.phone,
        status: user.status,
        createdAt: user.createdAt.toISOString(),
        termsAcceptedAt: user.termsAcceptedAt.toISOString(),
      },
      providerProfile:
        user.providerProfile === null
          ? null
          : { businessName: user.providerProfile.businessName, verificationTier: user.providerProfile.verificationTier },
      sessions: sessions.map((s) => ({ deviceName: s.deviceName, createdAt: s.createdAt.toISOString(), lastSeenAt: s.lastSeenAt.toISOString() })),
      ...(await this.deps.exportContributors.collectAll(userId)),
    };
  }

  /**
   * Who may call: the signed-in user. Queued, never refused (plan §Phase 3,
   * Round 9): accepted immediately, frozen at once, anonymised by the job when
   * open bookings terminate or at the 30-day backstop. A repeat returns the
   * original dates. Sessions stay live — open bookings still need chat.
   */
  async requestDeletion(principal: UserPrincipal, meta: RequestMeta): Promise<{ status: 'frozen'; deletionRequestedAt: Date; deletionDeadlineAt: Date }> {
    const now = this.deps.clock();
    const deadline = new Date(now.getTime() + DELETION_BACKSTOP_DAYS * 86_400_000);
    const result = await this.deps.prisma.$transaction(async (tx) => {
      const frozen = await tx.user.updateMany({
        where: { id: principal.id, status: 'active' },
        data: { status: 'frozen', deletionRequestedAt: now, deletionDeadlineAt: deadline },
      });
      if (frozen.count === 1) {
        await this.deps.audit.record(tx, {
          actorType: 'user', actorId: principal.id, action: 'user.deletion.requested',
          targetType: 'user', targetId: principal.id, reason: 'user_initiated',
          requestId: meta.requestId, ipAddress: meta.ip,
        });
      }
      return tx.user.findUniqueOrThrow({ where: { id: principal.id } });
    });
    if (result.deletionRequestedAt === null || result.deletionDeadlineAt === null) {
      throw new Error('frozen user without deletion dates');
    }
    return { status: 'frozen', deletionRequestedAt: result.deletionRequestedAt, deletionDeadlineAt: result.deletionDeadlineAt };
  }
```

Import `userDto` from `../auth/dto.js`.

- [ ] **Step 5: Routes**

Add inside `registerAccountRoutes`:

```ts
  // Who may call: the signed-in user, for their own data. Synchronous JSON as plan §Phase 3 specifies.
  r.get(`${prefix}/data-export`, { preHandler: requireAuth, config: perPrincipal(10, '1 hour') }, async (request, reply) => {
    const data = await app.account.exportData(userOf(request).id);
    const date = app.deps.clock().toISOString().slice(0, 10);
    void reply.header('content-disposition', `attachment; filename="raajjepro-export-${date}.json"`);
    return reply.send(ok(data));
  });

  // Who may call: the signed-in user. 202: queued, never refused. Tier 5/hour per principal.
  r.post(`${prefix}/deletion-request`, { preHandler: requireAuth, config: perPrincipal(5, '1 hour') }, async (request, reply) => {
    const result = await app.account.requestDeletion(userOf(request), requestMeta(request));
    return reply.code(202).send(ok({
      status: result.status,
      deletionRequestedAt: result.deletionRequestedAt.toISOString(),
      deletionDeadlineAt: result.deletionDeadlineAt.toISOString(),
    }));
  });
```

In `app.ts`: `const exportContributors = new ExportContributors(); app.decorate('exportContributors', exportContributors);` and pass it into `AccountService`; add `exportContributors: ExportContributors;` to the augmentation.

- [ ] **Step 6: Run, lint, typecheck** — `npx vitest run test/account-export-deletion.test.ts && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/src backend/test
git commit -m "Data export with contributor sections, and the deletion request: 202, frozen, 30-day deadline, idempotent"
```

---

### Task 8: The job runner and the anonymisation job

**Files:**
- Create: `backend/src/jobs/runner.ts`, `backend/src/jobs/anonymise-accounts.ts`, `backend/src/modules/account/anonymise.ts`
- Modify: `backend/src/app.ts` (`AppDeps.deletionBlocker`, decorate `anonymisation`), `backend/src/main.ts` (start the runner), `backend/test/helpers/app.ts` (pass `deletionBlocker`)
- Test: `backend/test/job-runner-node.test.ts`, `backend/test/account-anonymisation.test.ts`

**Interfaces:**
- Produces:
  - `DeletionBlocker { hasOpenBookings(userId: string): Promise<boolean> }`, `neverBlocks: DeletionBlocker`.
  - `AnonymisationHook = (tx: Prisma.TransactionClient, userId: string, now: Date) => Promise<void>`; `AnonymisationHooks.register(name, hook)`, `.list()`.
  - `AccountAnonymiser.anonymise(userId, now, reason: 'bookings_terminal' | 'deletion_backstop')`, `.findDue(now, blocker)` → `{ userId; reason }[]`, `.runDue(now, blocker)` → `{ processed: number; failed: number }`.
  - `JobRunner` (`{ prisma, clock, log }`): `register(job: { name; everyMs; run(now: Date): Promise<void> })`, `runOnce(name, now?)`, `start()`, `stop()`.
  - `anonymiseAccountsJob(anonymiser, blocker)` → a job definition named `anonymise-deleted-accounts`, every 5 minutes.
  - `app.anonymisation: AnonymisationHooks`, `app.anonymiser: AccountAnonymiser`, `app.jobs: JobRunner` (registered, not started — `main.ts` starts it).

- [ ] **Step 1: Runner tests**

`backend/test/job-runner-node.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { JobRunner } from '../src/jobs/runner.js';
import { controllableClock, databaseUrl } from './helpers/app.js';

const silent = { info: () => undefined, warn: () => undefined, error: () => undefined };

describe.skipIf(databaseUrl === undefined)('JobRunner (Node-side jobs)', () => {
  let prisma: PrismaClient;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('runOnce runs the job and upserts its heartbeat row with the clock time', async () => {
    const runner = new JobRunner({ prisma, clock: time.clock, log: silent });
    const name = `test-job-${Math.random().toString(36).slice(2)}`;
    let runs = 0;
    runner.register({ name, everyMs: 60_000, run: () => { runs += 1; return Promise.resolve(); } });
    await runner.runOnce(name);
    await runner.runOnce(name);
    expect(runs).toBe(2);
    const beat = await prisma.jobHeartbeat.findUniqueOrThrow({ where: { jobName: name } });
    expect(beat.firedAt.getTime()).toBe(time.clock().getTime());
  });

  it('a failing job is logged and does not write a heartbeat, and the runner survives it', async () => {
    const warned: string[] = [];
    const runner = new JobRunner({ prisma, clock: time.clock, log: { ...silent, error: (_o, msg) => { warned.push(msg); } } });
    const name = `test-job-${Math.random().toString(36).slice(2)}`;
    runner.register({ name, everyMs: 60_000, run: () => Promise.reject(new Error('boom')) });
    await runner.runOnce(name);
    expect(warned).toContain('job failed');
    expect(await prisma.jobHeartbeat.findUnique({ where: { jobName: name } })).toBeNull();
  });

  it('two runners cannot run the same job at once — the advisory lock makes the second skip', async () => {
    const a = new JobRunner({ prisma, clock: time.clock, log: silent });
    const b = new JobRunner({ prisma, clock: time.clock, log: silent });
    const name = `test-job-${Math.random().toString(36).slice(2)}`;
    let concurrent = 0;
    let peak = 0;
    const job = { name, everyMs: 60_000, run: async () => { concurrent += 1; peak = Math.max(peak, concurrent); await new Promise((r) => setTimeout(r, 150)); concurrent -= 1; } };
    a.register(job);
    b.register(job);
    const [ra, rb] = await Promise.all([a.runOnce(name), b.runOnce(name)]);
    expect(peak).toBe(1);
    expect([ra, rb].filter((r) => r === 'skipped')).toHaveLength(1);
  });

  it('start() schedules and stop() clears without leaking a timer', async () => {
    const runner = new JobRunner({ prisma, clock: time.clock, log: silent });
    let runs = 0;
    runner.register({ name: `test-job-${Math.random().toString(36).slice(2)}`, everyMs: 20, run: () => { runs += 1; return Promise.resolve(); } });
    runner.start();
    await new Promise((r) => setTimeout(r, 120));
    runner.stop();
    const after = runs;
    await new Promise((r) => setTimeout(r, 60));
    expect(runs).toBeGreaterThanOrEqual(2);
    expect(runs).toBe(after);
  });
});
```

- [ ] **Step 2: Anonymisation tests**

`backend/test/account-anonymisation.test.ts`:

```ts
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { DeletionBlocker } from '../src/modules/account/anonymise.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, RecordingEmailTransport, registerUser } from './helpers/users.js';

type Err = { error: { code: string } };

describe.skipIf(databaseUrl === undefined)('account anonymisation (plan §Phase 3: queued, frozen, 30-day backstop)', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();
  const blocked = new Set<string>();
  const blocker: DeletionBlocker = { hasOpenBookings: (userId) => Promise.resolve(blocked.has(userId)) };
  const hookCalls: string[] = [];

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail, deletionBlocker: blocker } });
    ctx.app.anonymisation.register('test-hook', async (tx, userId) => {
      hookCalls.push(userId);
      await tx.auditLogEntry.create({ data: { actorType: 'system', action: 'test.hook_ran', targetType: 'user', targetId: userId, reason: 'test' } });
    });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  async function frozenUser() {
    const u = await registerUser(ctx.app);
    await ctx.app.inject({ method: 'POST', url: '/v1/users/me/deletion-request', headers: u.headers });
    return u;
  }

  it('an account with no open bookings is anonymised on the next run: identity replaced, sessions dead, login impossible, hook ran in the transaction', async () => {
    const u = await frozenUser();
    const result = await ctx.app.anonymiser.runDue(time.clock(), blocker);
    expect(result.processed).toBeGreaterThanOrEqual(1);
    const row = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
    expect(row.status).toBe('anonymised');
    expect(row.fullName).toBe('Deleted user');
    expect(row.email).toBe(`deleted-${u.userId}@anonymised.raajjepro.invalid`);
    expect(row.phoneE164).toBeNull();
    expect(row.emailVerifiedAt).toBeNull();
    expect(row.anonymisedAt?.getTime()).toBe(time.clock().getTime());
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers })).json<Err>().error.code).toBe('SESSION_EXPIRED');
    const login = await ctx.app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: freshIp(), payload: { email: u.email, password: u.password } });
    expect(login.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    expect(hookCalls).toContain(u.userId);
    expect(await ctx.prisma.auditLogEntry.count({ where: { action: 'test.hook_ran', targetId: u.userId } })).toBe(1);
    const audit = await ctx.prisma.auditLogEntry.findFirst({ where: { action: 'user.anonymised', targetId: u.userId } });
    expect(audit?.reason).toBe('bookings_terminal');
    expect(audit?.actorType).toBe('system');
    // The original address is free to register again.
    expect((await registerUser(ctx.app, { email: u.email })).email).toBe(u.email);
  });

  it('an open booking holds anonymisation until the booking terminates', async () => {
    const u = await frozenUser();
    blocked.add(u.userId);
    await ctx.app.anonymiser.runDue(time.clock(), blocker);
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe('frozen');
    expect((await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers })).statusCode).toBe(200);
    blocked.delete(u.userId);
    await ctx.app.anonymiser.runDue(time.clock(), blocker);
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe('anonymised');
  });

  it('…and completes anyway at the 30-day backstop, with reason deletion_backstop', async () => {
    const u = await frozenUser();
    blocked.add(u.userId);
    time.advance(29 * 86_400_000);
    await ctx.app.anonymiser.runDue(time.clock(), blocker);
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe('frozen');
    time.advance(86_400_000 + 1_000);
    await ctx.app.anonymiser.runDue(time.clock(), blocker);
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe('anonymised');
    const audit = await ctx.prisma.auditLogEntry.findFirst({ where: { action: 'user.anonymised', targetId: u.userId } });
    expect(audit?.reason).toBe('deletion_backstop');
    time.advance(-(30 * 86_400_000 + 1_000));
    blocked.delete(u.userId);
  });

  it('a hook that throws rolls the user back untouched, and the run continues to the next user', async () => {
    const bad = await frozenUser();
    const good = await frozenUser();
    ctx.app.anonymisation.register('failing-hook', (_tx, userId) => userId === bad.userId ? Promise.reject(new Error('purge failed')) : Promise.resolve());
    const result = await ctx.app.anonymiser.runDue(time.clock(), blocker);
    expect(result.failed).toBeGreaterThanOrEqual(1);
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: bad.userId } })).status).toBe('frozen');
    expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: good.userId } })).status).toBe('anonymised');
  });

  it('the provider profile keeps its tier but loses the business name', async () => {
    const u = await registerUser(ctx.app, { role: 'provider', businessName: 'Gone Trade' });
    await ctx.prisma.providerProfile.update({ where: { userId: u.userId }, data: { verificationTier: 'silver' } });
    await ctx.app.inject({ method: 'POST', url: '/v1/users/me/deletion-request', headers: u.headers });
    await ctx.app.anonymiser.runDue(time.clock(), blocker);
    const profile = await ctx.prisma.providerProfile.findUniqueOrThrow({ where: { userId: u.userId } });
    expect(profile.businessName).toBeNull();
    expect(profile.verificationTier).toBe('silver');
  });
});
```

- [ ] **Step 3: Run both to fail** — Expected: FAIL.

- [ ] **Step 4: `jobs/runner.ts`**

```ts
import type { Clock } from '../core/clock.js';
import type { PrismaClient } from '../generated/prisma/client.js';

export interface JobDefinition {
  name: string;
  everyMs: number;
  run(now: Date): Promise<void>;
}

export interface JobLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
  error(obj: Record<string, unknown>, msg: string): void;
}

/**
 * Node-side scheduled work (plan §2 "pg_cron or equivalent"; backend/CLAUDE.md:
 * a transition that should happen at a time is made to happen by a job, never
 * check-on-read). pg_cron stays for SQL-only jobs; this runs jobs that call
 * into Node — anonymisation runs hooks that reach a bucket, which SQL cannot.
 *
 * One transaction-scoped advisory lock per job means two API instances never
 * run the same job at once. A successful run upserts the Phase 0 heartbeat
 * row, so `readHeartbeat`'s notion of "observably firing" covers these jobs
 * with no second mechanism. A failure is logged and the schedule continues.
 */
export class JobRunner {
  private readonly jobs = new Map<string, JobDefinition>();
  private readonly timers: NodeJS.Timeout[] = [];

  constructor(private readonly deps: { prisma: PrismaClient; clock: Clock; log: JobLogger }) {}

  register(job: JobDefinition): void {
    if (this.jobs.has(job.name)) throw new Error(`job already registered: ${job.name}`);
    this.jobs.set(job.name, job);
  }

  /** Runs one job now. Returns 'skipped' when another instance holds its lock. Tests call this; start() calls it on a timer. */
  async runOnce(name: string, now: Date = this.deps.clock()): Promise<'ran' | 'skipped' | 'failed'> {
    const job = this.jobs.get(name);
    if (job === undefined) throw new Error(`no such job: ${name}`);
    try {
      return await this.deps.prisma.$transaction(
        async (tx) => {
          const [lock] = await tx.$queryRaw<{ locked: boolean }[]>`SELECT pg_try_advisory_xact_lock(hashtext(${`job:${name}`})) AS locked`;
          if (lock?.locked !== true) return 'skipped';
          await job.run(now);
          await tx.jobHeartbeat.upsert({
            where: { jobName: name },
            create: { jobName: name, firedAt: now },
            update: { firedAt: now },
          });
          return 'ran';
        },
        { timeout: 60_000 },
      );
    } catch (error) {
      this.deps.log.error({ err: error, job: name }, 'job failed');
      return 'failed';
    }
  }

  start(): void {
    for (const job of this.jobs.values()) {
      const timer = setInterval(() => {
        void this.runOnce(job.name);
      }, job.everyMs);
      timer.unref();
      this.timers.push(timer);
    }
    this.deps.log.info({ jobs: [...this.jobs.keys()] }, 'job runner started');
  }

  stop(): void {
    for (const timer of this.timers) clearInterval(timer);
    this.timers.length = 0;
  }
}
```

Note: the job's own work runs inside the runner's transaction so the lock covers it. `AccountAnonymiser.runDue` therefore takes a `Db` and opens **no** transaction of its own for the loop — it uses a savepoint-free per-user strategy: each user is processed by a nested call that catches its own error. Because Prisma interactive transactions cannot nest, the anonymiser processes each user through `prisma.$transaction` **outside** the runner's lock transaction when called from the job — so the job's `run` closure calls `anonymiser.runDue(now, blocker)` which uses its own `prisma`, while the runner's transaction only holds the lock and writes the heartbeat. That is the shape implemented below; the lock still serialises instances.

- [ ] **Step 5: `modules/account/anonymise.ts`**

```ts
import { randomBytes } from 'node:crypto';

import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';
import { hashPassword } from '../admin-auth/crypto.js';
import type { AuditService } from '../audit/service.js';
import type { UserRepository } from '../auth/repository.js';

/** Phase 17 supplies the real one; until then nothing blocks. */
export interface DeletionBlocker {
  hasOpenBookings(userId: string): Promise<boolean>;
}
export const neverBlocks: DeletionBlocker = { hasOpenBookings: () => Promise.resolve(false) };

export type AnonymisationHook = (tx: Prisma.TransactionClient, userId: string, now: Date) => Promise<void>;

/**
 * Later phases register what anonymisation must also do — Phase 10a/23 purge
 * identity documents, 10b deletes internal notes, 11 strips review
 * attribution, 18 purges messages. Every hook runs inside the same
 * transaction as the user row change: a failing hook leaves the user frozen
 * and untouched, to be retried on the next run.
 */
export class AnonymisationHooks {
  private readonly hooks = new Map<string, AnonymisationHook>();
  register(name: string, hook: AnonymisationHook): void {
    if (this.hooks.has(name)) throw new Error(`anonymisation hook already registered: ${name}`);
    this.hooks.set(name, hook);
  }
  list(): [string, AnonymisationHook][] {
    return [...this.hooks.entries()];
  }
}

export type AnonymisationReason = 'bookings_terminal' | 'deletion_backstop';

export class AccountAnonymiser {
  constructor(
    private readonly deps: { prisma: PrismaClient; repo: UserRepository; audit: AuditService; hooks: AnonymisationHooks },
  ) {}

  /** Frozen users whose deadline has passed, or who have no open bookings. */
  async findDue(now: Date, blocker: DeletionBlocker): Promise<{ userId: string; reason: AnonymisationReason }[]> {
    const frozen = await this.deps.prisma.user.findMany({
      where: { status: 'frozen' },
      select: { id: true, deletionDeadlineAt: true },
      orderBy: { deletionRequestedAt: 'asc' },
    });
    const due: { userId: string; reason: AnonymisationReason }[] = [];
    for (const user of frozen) {
      if (user.deletionDeadlineAt !== null && user.deletionDeadlineAt.getTime() <= now.getTime()) {
        due.push({ userId: user.id, reason: 'deletion_backstop' });
      } else if (!(await blocker.hasOpenBookings(user.id))) {
        due.push({ userId: user.id, reason: 'bookings_terminal' });
      }
    }
    return due;
  }

  async runDue(now: Date, blocker: DeletionBlocker): Promise<{ processed: number; failed: number }> {
    let processed = 0;
    let failed = 0;
    for (const { userId, reason } of await this.findDue(now, blocker)) {
      try {
        await this.anonymise(userId, now, reason);
        processed += 1;
      } catch {
        failed += 1;
      }
    }
    return { processed, failed };
  }

  /** One user, one transaction: identity replaced, sessions revoked, codes invalidated, hooks run, audited. */
  async anonymise(userId: string, now: Date, reason: AnonymisationReason): Promise<void> {
    const passwordHash = await hashPassword(randomBytes(32).toString('hex'));
    await this.deps.prisma.$transaction(async (tx) => {
      const changed = await tx.user.updateMany({
        where: { id: userId, status: 'frozen' },
        data: {
          fullName: 'Deleted user',
          email: `deleted-${userId}@anonymised.raajjepro.invalid`,
          phoneE164: null,
          phoneDialCode: null,
          passwordHash,
          emailVerifiedAt: null,
          status: 'anonymised',
          anonymisedAt: now,
        },
      });
      if (changed.count === 0) return; // raced with another run, or no longer frozen
      await tx.providerProfile.updateMany({ where: { userId }, data: { businessName: null } });
      await this.deps.repo.revokeAllSessions(tx, userId, now, 'anonymised');
      await tx.emailOtp.updateMany({ where: { userId, consumedAt: null, invalidatedAt: null }, data: { invalidatedAt: now } });
      for (const [, hook] of this.deps.hooks.list()) await hook(tx, userId, now);
      await this.deps.audit.record(tx, {
        actorType: 'system',
        action: 'user.anonymised',
        targetType: 'user',
        targetId: userId,
        reason,
        metadata: { hooksRun: this.deps.hooks.list().length },
      });
    });
  }
}
```

- [ ] **Step 6: `jobs/anonymise-accounts.ts`**

```ts
import type { AccountAnonymiser, DeletionBlocker } from '../modules/account/anonymise.js';
import type { JobDefinition } from './runner.js';

export const ANONYMISE_JOB_NAME = 'anonymise-deleted-accounts';

/** Every five minutes: anonymise frozen accounts that are due (plan §Phase 3). */
export function anonymiseAccountsJob(anonymiser: AccountAnonymiser, blocker: DeletionBlocker): JobDefinition {
  return {
    name: ANONYMISE_JOB_NAME,
    everyMs: 5 * 60_000,
    async run(now) {
      await anonymiser.runDue(now, blocker);
    },
  };
}
```

- [ ] **Step 7: Wire**

`app.ts`: add `deletionBlocker?: DeletionBlocker;` to `AppDeps` (optional, default `neverBlocks`); augmentation gains `anonymisation: AnonymisationHooks; anonymiser: AccountAnonymiser; jobs: JobRunner;`. Construct `const anonymisation = new AnonymisationHooks(); const anonymiser = new AccountAnonymiser({ prisma: deps.prisma, repo: authService.repo, audit, hooks: anonymisation }); const jobs = new JobRunner({ prisma: deps.prisma, clock: deps.clock, log: app.log }); jobs.register(anonymiseAccountsJob(anonymiser, deps.deletionBlocker ?? neverBlocks));` and decorate all three. Do **not** start the runner in `buildApp`. In `main.ts`, after `buildApp`: `app.jobs.start();` and in `shutdown`: `app.jobs.stop();` before `app.close()`. In `test/helpers/app.ts`, `deps` is already spread into `buildApp`, so `deletionBlocker` passes through — no change needed beyond the type.

- [ ] **Step 8: Run, lint, typecheck** — `npx vitest run test/job-runner-node.test.ts test/account-anonymisation.test.ts && npm run lint && npm run typecheck` — Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/src backend/test
git commit -m "Node job runner under an advisory lock, and the anonymisation job: due when bookings terminate or at 30 days, hooks in-transaction"
```

---

### Task 9: Redaction, the Done-when end-to-end run, leak tests, CI, and the documents

**Files:**
- Modify: `backend/src/core/logging.ts`
- Modify: `.github/workflows/ci.yml` (add `AUTH_JWT_SECRET` to both env blocks)
- Test: `backend/test/phase3-done-when.test.ts`, extend `backend/test/logging.test.ts`
- Create: `docs/decisions/12-phase-3-identity.md`
- Modify: `docs/deferred-verification.md`, `README.md`, `HANDOVER.md`, `docs/decisions/10-phase-2-backend-core.md` (mark the three "Phase 3 must confirm" items resolved)

- [ ] **Step 1: Redaction keys**

In `backend/src/core/logging.ts` change `SENSITIVE_KEYS` to:

```ts
const SENSITIVE_KEYS = [
  'password', 'currentPassword', 'newPassword', 'email', 'newEmail', 'phone', 'phoneE164', 'number',
  'fullName', 'code', 'token', 'accessToken', 'refreshToken', 'idToken', 'secret', 'recoveryCodes',
];
```

Add to `test/logging.test.ts`'s first test a nested object `{ tokens: { accessToken: 'eyJ-top', refreshToken: 'rt-secret' }, newEmail: 'n@x.test', phoneE164: '+9607771234' }` and assert none of those literal values appear in the output.

- [ ] **Step 2: The Done-when test**

`backend/test/phase3-done-when.test.ts` — the file transport is used deliberately here (the plan and §0.0 item 17 say the code is read from the written file):

```ts
import { randomUUID } from 'node:crypto';
import { mkdtemp, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Writable } from 'node:stream';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildApp } from '../src/app.js';
import { createPrismaClient } from '../src/db/client.js';
import { requireEmailVerified } from '../src/modules/auth/guards.js';
import { FileEmailTransport } from '../src/modules/email/transports/file.js';
import { controllableClock, databaseUrl, freshIp, testConfig, TrustingValidator } from './helpers/app.js';
import { bearer, freshEmail, freshPhone, USER_PASSWORD } from './helpers/users.js';

type Err = { error: { code: string } };

/** Reads the six-digit code out of the JSON the file transport wrote — exactly as a person reads it out of a mailbox. */
async function codeFromMailDir(dir: string, to: string): Promise<string> {
  const files = (await readdir(dir)).sort();
  for (const file of files.reverse()) {
    const message = JSON.parse(await readFile(join(dir, file), 'utf8')) as { to: string; text: string };
    if (message.to === to.toLowerCase()) {
      const code = message.text.match(/\b(\d{6})\b/)?.[1];
      if (code !== undefined) return code;
    }
  }
  throw new Error(`no code written for ${to}`);
}

describe.skipIf(databaseUrl === undefined)('§Phase 3 Done-when — the full cycle against the file transport', () => {
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const lines: string[] = [];
  let mailDir: string;
  let app: Awaited<ReturnType<typeof buildApp>>;
  let prisma: ReturnType<typeof createPrismaClient>;

  beforeAll(async () => {
    mailDir = await mkdtemp(join(tmpdir(), 'raajjepro-phase3-mail-'));
    const config = { ...testConfig({ clock: time.clock }), logLevel: 'info' as const };
    prisma = createPrismaClient(config.databaseUrl);
    app = await buildApp(config, {
      prisma,
      clock: time.clock,
      emailTransport: new FileEmailTransport(mailDir),
      snsValidator: new TrustingValidator(),
    });
    // Capture every log line so the no-PII rule can be asserted over a real run.
    const stream = new Writable({ write(chunk: Buffer, _e, cb) { lines.push(chunk.toString('utf8')); cb(); } });
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-explicit-any
    (app.log as any)[Symbol.for('pino.stream')] = stream; // if unsupported by the pino version, build the app with loggerOptions(config) + { stream } instead, as test/logging.test.ts does
    app.get('/v1/_test/needs-verified', { preHandler: requireEmailVerified }, async () => ({ data: 'ok' }));
    await app.ready();
  });
  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('register → verify (code read from the written mail) → logout → login; unverified browses but is rejected by requireEmailVerified', async () => {
    const email = freshEmail();
    const phone = freshPhone();
    const register = await app.inject({
      method: 'POST', url: '/v1/auth/register', remoteAddress: freshIp(), headers: { 'idempotency-key': randomUUID() },
      payload: { role: 'customer', fullName: 'Aishath Naeema', email, phone: { dialCode: '+960', number: phone }, password: USER_PASSWORD, acceptTerms: true, deviceName: 'Done-when phone' },
    });
    expect(register.statusCode).toBe(201);
    const first = register.json<{ data: { tokens: { accessToken: string } } }>().data.tokens;

    // Unverified: browses freely, is refused by the guard with its own code.
    expect((await app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(first.accessToken) })).statusCode).toBe(200);
    const refused = await app.inject({ method: 'GET', url: '/v1/_test/needs-verified', headers: bearer(first.accessToken) });
    expect(refused.statusCode).toBe(422);
    expect(refused.json<Err>().error.code).toBe('EMAIL_NOT_VERIFIED');

    const code = await codeFromMailDir(mailDir, email);
    const confirm = await app.inject({ method: 'POST', url: '/v1/auth/verify-email/confirm', headers: bearer(first.accessToken), payload: { code } });
    expect(confirm.statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/v1/_test/needs-verified', headers: bearer(first.accessToken) })).statusCode).toBe(200);

    expect((await app.inject({ method: 'POST', url: '/v1/auth/logout', headers: bearer(first.accessToken) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(first.accessToken) })).json<Err>().error.code).toBe('SESSION_EXPIRED');

    const login = await app.inject({ method: 'POST', url: '/v1/auth/login', remoteAddress: freshIp(), payload: { email, password: USER_PASSWORD, deviceName: 'Done-when phone' } });
    expect(login.statusCode).toBe(200);
    const second = login.json<{ data: { tokens: { accessToken: string }; user: { emailVerified: boolean } } }>().data;
    expect(second.user.emailVerified).toBe(true);
    expect((await app.inject({ method: 'GET', url: '/v1/auth/me', headers: bearer(second.tokens.accessToken) })).statusCode).toBe(200);

    // No response to anyone but the holder carries the phone: the sessions list and every error body above are phone-free.
    const sessions = await app.inject({ method: 'GET', url: '/v1/auth/sessions', headers: bearer(second.tokens.accessToken) });
    expect(sessions.body).not.toContain(phone);
    expect(refused.body).not.toContain(phone);

    // No log line from the whole run carries the email, phone, password or code.
    const output = lines.join('\n');
    expect(output).not.toContain(email.toLowerCase());
    expect(output).not.toContain(phone);
    expect(output).not.toContain(USER_PASSWORD);
    expect(output).not.toContain(code);
  });
});
```

If attaching a stream to an already-built Fastify logger proves impossible, restructure: build the app with `Fastify({ logger: loggerOptionsForStream(config, stream) })` is not available through `buildApp`; instead add an optional `logStream?: Writable` to `AppDeps` that `buildApp` passes as `loggerOptions(config)`'s `stream` — an additive test seam — and drop the `Symbol.for` line.

- [ ] **Step 3: CI**

In `.github/workflows/ci.yml` add `AUTH_JWT_SECRET: AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=` beside both `ADMIN_TOTP_ENCRYPTION_KEY` lines (job env and the boot step env).

- [ ] **Step 4: Run everything** — `cd backend && npm test && npm run lint && npm run typecheck && npm run build` — Expected: all PASS. Then the manual Done-when run against the dev server: `npm run dev` in one terminal; in another, register with `curl` (Idempotency-Key header, a real-looking address), find the newest file in `backend/.mail/`, read the code, confirm, logout, login. Record what was seen in the decision record.

- [ ] **Step 5: Decision record**

Write `docs/decisions/12-phase-3-identity.md` in the shape of `10-phase-2-backend-core.md`: status line (built date, plan revision 5.20, §Phase 3); "The decisions" — a table pointing at the spec's fourteen rows without restating the reasoning; "What was built" — plan item → module → files; "Where the build departed from the design" — filled from the SDD ledger's review findings as they happen (never hypothetical); "Prototype divergences flagged" — the data-export delivery copy in `Account Settings.dc.html` (plan says synchronous JSON; the prototype says emailed within a day) and the `· Malé` location on sessions rows (no geolocation exists); "Done-when, line by line" — each §Phase 3 line with met / met for the mechanism (ledger row id) / owned by the frontend plan; "Unverified" — no real mailbox, no Sentry DSN; "What Phase 3b / 5 / 6 / 11 / 17 must pick up" — `assertRecoverableByEmail`, the four ProviderProfile columns and `getOrCreateProviderProfile`, saved preferences deferral, `AnonymisationHooks`, `ExportContributors`, `DeletionBlocker`, `requireActiveAccount`.

- [ ] **Step 6: Ledger rows**

Append to `docs/deferred-verification.md`. Under **Open — closed at deployment**:

| # | What is unverified | Closed by |
|---|---|---|
| L8 | The OTP mail reaching a real inbox with the six-digit code readable, and the sender/subject rendering as intended. Phase 3 verified the whole register → verify → login cycle against `EMAIL_TRANSPORT=file`. | Register with an address you control after L1; the code from that inbox verifies the account. |
| L9 | A Flutter exception reaching Sentry. The `CrashReporter` interface is wired; without `SENTRY_DSN` it is a no-op. | A forced test exception in a build with a real DSN appears in the Sentry project within minutes. |

Under **Open — closed by a later phase** (replace the "Empty." paragraph with a table, keeping the note about the recovery guard resolved: it was testable and is tested — `assertRecoverableByEmail`):

| # | What is unverified | Closed by |
|---|---|---|
| P1 | A deleted account's reviews remain with anonymised attribution. Phase 3 built `AnonymisationHooks` and tested that a registered hook runs in the anonymisation transaction. | Phase 11 registers the review hook and its test asserts a review survives with the author anonymised. |
| P2 | A deletion request with an open booking completes automatically when that booking terminates. Phase 3 built the `DeletionBlocker` seam and tested it with an injected blocker. | Phase 17 supplies the real blocker; its test creates a booking, requests deletion, terminates the booking and sees anonymisation on the next run. |
| P3 | A password-reset attempt for an unverified email is refused without revealing existence. Phase 3 built and tested `assertRecoverableByEmail`. | Phase 3b's reset flow calls it and its test asserts an identical response with no mail sent for an unverified address. |

- [ ] **Step 7: README, HANDOVER, Phase 2 record**

`README.md`: extend the "Running locally" block with `npm run dev` then a register `curl`, and one sentence: with `EMAIL_TRANSPORT=file` the verification code is in the newest JSON file under `backend/.mail/`. Update the "Phases 0, 1 and 2 are built" sentence to include Phase 3's backend. `HANDOVER.md`: in "What this repository is, right now", add Phase 3 backend built and what the Flutter plan covers; add the deferral of saved preferences and the two seams to the outstanding list; point "next" at the frontend plan then `/phase-3b`. `docs/decisions/10-phase-2-backend-core.md`: under "What Phase 3 must confirm", add one line per item saying how Phase 3 resolved it (`anon:<ip>` confirmed; `recipientUserId` filled by `OtpService.send`; `requireEmailVerified` is a `BusinessRuleError` with code `EMAIL_NOT_VERIFIED`).

- [ ] **Step 8: `scripts/verify.sh`, then commit and push**

Run `scripts/verify.sh` from the repo root — Expected: every line `ok`. Then:

```bash
git add -A backend docs README.md HANDOVER.md .github/workflows/ci.yml
git commit -m "Phase 3 backend: Done-when run against the file transport, redaction, ledger rows and the decision record"
git fetch origin && git rebase origin/main && git push origin main
```

---

## Self-review against the spec

- **§1 data model** — Task 1 (all five models, both enums, `AuditActorType.user`; `phoneDialCode` added as an implementation detail so the DTO can split the number, noted in the plan's constraints).
- **§2 principal, guards, plugin order** — Task 2 (principal, guards), Task 3 (plugin registered after admin session, before rate limit; `lastSeenAt` touched at most once a minute).
- **§3 tokens and sessions** — Task 3 (login's session creation via `openSession`, refresh with the conditional rotation, grace window, expiry, logout, list, revoke with 404 for a foreign id); password/email change revoking the others — Task 6.
- **§4 registration, phone, OTP** — Task 4 (phone rules, both limits inside a `FOR UPDATE` lock, attempts, `recipientUserId`, no-links mail text, suppressed reported honestly), Task 5 (register order of checks, `EMAIL_IN_USE`/`PHONE_IN_USE` with `details[0].path`, `P2002` mapping, idempotency operation `auth.register`, provider profile at `none`, login, social stubs, tiers).
- **§5 account settings** — Task 6 (all four change routes, `EMAIL_UNCHANGED`, re-check at confirm, `assertRecoverableByEmail`), Task 7 (export with `Content-Disposition`, contributor registry, deletion 202 idempotent, sessions kept).
- **§6 deletion pipeline and runner** — Task 8 (advisory lock, heartbeat upsert, hooks in-transaction, blocker seam, backstop, `providerProfile.businessName → null`, sessions revoked, OTPs invalidated, audit reasons).
- **§7 errors and tiers** — every code in the spec table is thrown somewhere above; `Retry-After` on `OTP_RATE_LIMITED` via `carriesRetryAfter` (Task 4); tiers on login, register, refresh, social, OTP send/confirm, change-password, change-email, export, deletion.
- **§9 documents** — Task 9. **§10 verification table** — every backend row maps to a test named above; the frontend rows are the frontend plan's.
- **Placeholders** — none: every step has its code or exact command. **Type consistency** — `RequestMeta` is imported from `admin-auth/service.js` everywhere; `userOf` (not `principalOf`) for users; `OtpSendResult` shape identical in Tasks 4, 5, 6; `UserWithProfile` from `repository.ts` used by dto/service/account; `TokenPair` from `service.ts` used by routes and tests.
