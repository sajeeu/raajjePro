import 'dotenv/config';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import type { FastifyInstance } from 'fastify';

import { buildApp, type AppDeps } from '../../src/app.js';
import { loadConfig, type Config } from '../../src/config/env.js';
import type { Clock } from '../../src/core/clock.js';
import { createPrismaClient } from '../../src/db/client.js';
import type { SnsMessage, SnsMessageValidator } from '../../src/modules/email/sns/validator.js';
import { FileEmailTransport } from '../../src/modules/email/transports/file.js';
import {
  UnregisteredTokenError,
  type PushMessage,
  type PushTarget,
  type PushTransport,
} from '../../src/modules/push/types.js';

/** Accepts anything shaped like an SNS message; the signature itself is sns-validator's job — used wherever a test needs the webhook route without real SNS. */
export class TrustingValidator implements SnsMessageValidator {
  validate(raw: string): Promise<SnsMessage> {
    return Promise.resolve(JSON.parse(raw) as SnsMessage);
  }
}

/**
 * The push vendor stand-in. No Firebase project and no Apple developer account
 * exist and neither is procured by Phase 3c
 * (docs/decisions/15-phase-3c-push.md), so what the tests assert is what the
 * sender was ASKED to do: which tokens it addressed, with what copy, in what
 * order relative to the email.
 *
 * `failFor` makes a token fail; `unregisterFor` makes the vendor report it
 * dead, which is the only way to exercise token cleanup without an uninstall.
 */
export class RecordingPushTransport implements PushTransport {
  readonly sent: { message: PushMessage; target: PushTarget }[] = [];
  readonly failFor = new Set<string>();
  readonly unregisterFor = new Set<string>();

  deliver(message: PushMessage, target: PushTarget): Promise<{ providerMessageId: string }> {
    if (this.unregisterFor.has(target.token)) {
      return Promise.reject(new UnregisteredTokenError());
    }
    if (this.failFor.has(target.token)) {
      return Promise.reject(new Error('vendor said no'));
    }
    this.sent.push({ message, target });
    return Promise.resolve({ providerMessageId: `test-${String(this.sent.length)}` });
  }

  tokens(): string[] {
    return this.sent.map((s) => s.target.token);
  }
}

export const databaseUrl = process.env.DATABASE_URL;

/**
 * A distinct source address per call. The rate-limit store is Postgres-backed
 * and its counters persist forever by design (see the "counters survive an
 * app restart" test) — a fixed IP shared across many test runs accumulates
 * hits against the same window, so any test that repeats a request enough
 * times to approach a real tier's limit (most visibly the admin login route's
 * own 10-per-15-minutes) must not share the default inject address with a
 * previous run.
 */
export function freshIp(): string {
  const [a, b] = [Math.floor(Math.random() * 200) + 10, Math.floor(Math.random() * 250)];
  return `10.${String(a)}.${String(b)}.${String(Math.floor(Math.random() * 250) + 1)}`;
}

export interface TestAppOptions {
  clock?: Clock;
  anonPerMinute?: number;
  authPerMinute?: number;
  sessionIdleMinutes?: number;
  sessionAbsoluteHours?: number;
  reauthMinutes?: number;
  accessTokenMinutes?: number;
  refreshTokenDays?: number;
  otpExpiryMinutes?: number;
  passwordResetExpiryMinutes?: number;
  deps?: Partial<AppDeps>;
  /** Extra routes registered after the app's own — for testing middleware in isolation. */
  routes?: (app: FastifyInstance) => void;
}

export function testConfig(options: TestAppOptions = {}): Config {
  const base = loadConfig({
    ...process.env,
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    ADMIN_TOTP_ENCRYPTION_KEY:
      process.env.ADMIN_TOTP_ENCRYPTION_KEY ?? Buffer.alloc(32, 1).toString('base64'),
    AUTH_JWT_SECRET: process.env.AUTH_JWT_SECRET ?? Buffer.alloc(32, 2).toString('base64'),
    EMAIL_FROM_ADDRESS: 'test@raajjepro.local',
    EMAIL_TRANSPORT: 'file',
    SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:123456789012:raajjepro-ses-events',
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
    auth: {
      ...base.auth,
      accessTokenMinutes: options.accessTokenMinutes ?? base.auth.accessTokenMinutes,
      refreshTokenDays: options.refreshTokenDays ?? base.auth.refreshTokenDays,
      otpExpiryMinutes: options.otpExpiryMinutes ?? base.auth.otpExpiryMinutes,
      passwordResetExpiryMinutes:
        options.passwordResetExpiryMinutes ?? base.auth.passwordResetExpiryMinutes,
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
    emailTransport:
      options.deps?.emailTransport ?? new FileEmailTransport(join(tmpdir(), 'raajjepro-test-mail')),
    pushTransport: options.deps?.pushTransport ?? new RecordingPushTransport(),
    snsValidator: options.deps?.snsValidator ?? new TrustingValidator(),
    ...options.deps,
  });
  if (options.routes) {
    options.routes(app);
  }
  await app.ready();
  return { app, prisma, config };
}
