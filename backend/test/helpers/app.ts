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

/** Accepts anything shaped like an SNS message; the signature itself is sns-validator's job — used wherever a test needs the webhook route without real SNS. */
export class TrustingValidator implements SnsMessageValidator {
  validate(raw: string): Promise<SnsMessage> {
    return Promise.resolve(JSON.parse(raw) as SnsMessage);
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
    snsValidator: options.deps?.snsValidator ?? new TrustingValidator(),
    ...options.deps,
  });
  if (options.routes) {
    options.routes(app);
  }
  await app.ready();
  return { app, prisma, config };
}
