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
    ADMIN_TOTP_ENCRYPTION_KEY:
      process.env.ADMIN_TOTP_ENCRYPTION_KEY ?? Buffer.alloc(32, 1).toString('base64'),
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
