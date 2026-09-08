/**
 * §Phase 3c's observability clause: "log every fallback invocation with
 * reason. Alert if the email fallback exceeds 5% of accept prompts in a
 * rolling day — that indicates a push-integration regression, not user
 * preference." Plus the reputation metrics it asks to be watched rather than
 * merely collected, and the Done-when clause "fallback invocations and
 * bounces appear in logs".
 */
import { randomUUID } from 'node:crypto';
import { Writable } from 'node:stream';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';

import {
  buildTestApp,
  controllableClock,
  databaseUrl,
  RecordingPushTransport,
} from './helpers/app.js';
import { createUser } from './helpers/users.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { FALLBACK_ALERT_RATE, NotificationHealth } from '../src/modules/push/health.js';
import type { NotificationContext } from '../src/modules/push/types.js';

const describeIfDb = databaseUrl === undefined ? describe.skip : describe;

const context: NotificationContext = {
  kind: 'booking_accept_prompt',
  bookingType: 'Cleaning',
  customerFirstName: 'Aishath',
  islandName: 'Dh. Meedhoo',
};

/**
 * A rolling-day window nobody else is in.
 *
 * These tests count rows over the last 24 hours, and the suite deliberately
 * never cleans up (test/setup.ts) — so a fixed instant means the second run of
 * this file counts the first run's rows too. Same isolate-by-unique-key idiom
 * as `freshIp()`, applied to time instead of an address.
 */
function privateWindow(): Date {
  const days = Math.floor(Math.random() * 100_000);
  return new Date(Date.UTC(2100, 0, 1) + days * 86_400_000);
}

/** Captures pino output so a test can read the records a real run produces. */
function captureLog(): { lines: Record<string, unknown>[]; stream: Writable } {
  const lines: Record<string, unknown>[] = [];
  const stream = new Writable({
    write(chunk, _enc, cb) {
      for (const line of String(chunk).split('\n')) {
        if (line.trim().length > 0) lines.push(JSON.parse(line) as Record<string, unknown>);
      }
      cb();
    },
  });
  return { lines, stream };
}

describeIfDb('Phase 3c — notification observability', () => {
  let app: FastifyInstance;
  let prisma: PrismaClient;
  let lines: Record<string, unknown>[];
  const time = controllableClock(new Date('2026-09-08T09:00:00.000Z'));

  beforeAll(async () => {
    const captured = captureLog();
    lines = captured.lines;
    ({ app, prisma } = await buildTestApp({
      clock: time.clock,
      deps: { pushTransport: new RecordingPushTransport(), logStream: captured.stream },
    }));
    // The app builds with LOG_LEVEL=silent; the health checks log at info.
    app.log.level = 'info';
  });
  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('every fallback invocation is logged with its reason and no PII', async () => {
    const user = await createUser(prisma, { emailVerified: true });
    await prisma.user.update({ where: { id: user.id }, data: { pushPermission: 'denied' } });

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context,
    });

    const record = lines.find(
      (l) => l.event === 'notification.fallback' && l.dispatchId === result.dispatchId,
    );
    expect(record).toBeDefined();
    expect(record?.reason).toBe('permission_denied');
    expect(record?.kind).toBe('booking_accept_prompt');
    // IDs and enums only (root CLAUDE.md 1d) — never the address it went to.
    const serialised = JSON.stringify(record);
    expect(serialised).not.toContain(user.email);
    expect(serialised).not.toContain('Aishath');
  });

  it('the 5% metric counts accept prompts only — emergency parallel sends are excluded', async () => {
    // Emergency emails on every single dispatch by design. Folding those in
    // would peg the rate near 100% and the alert would stop meaning anything.
    const health = new NotificationHealth({ prisma, clock: time.clock, log: app.log });
    const before = await health.fallbackRate(time.clock());

    const user = await createUser(prisma, { emailVerified: true });
    for (let i = 0; i < 5; i += 1) {
      await app.notifications.dispatch({
        userId: user.id,
        urgency: 'emergency',
        context: { ...context, kind: 'emergency_dispatch' },
      });
    }

    const after = await health.fallbackRate(time.clock());
    expect(after.prompts).toBe(before.prompts);
    expect(after.fallbacks).toBe(before.fallbacks);
  });

  it('the alert fires above 5% and stays quiet below it', async () => {
    // A window of this run's own, so the count is this test's dispatches and
    // nothing else's — including this file's own previous runs.
    time.set(privateWindow());
    const health = new NotificationHealth({ prisma, clock: time.clock, log: app.log });

    const reachable = await createUser(prisma, { emailVerified: true });
    await prisma.deviceToken.create({
      data: {
        userId: reachable.id,
        installationId: `inst-${randomUUID()}`,
        platform: 'android',
        token: `tok-${randomUUID()}`,
        deviceName: 'Pixel',
        lastSeenAt: time.clock(),
      },
    });
    const denied = await createUser(prisma, { emailVerified: true });
    await prisma.user.update({ where: { id: denied.id }, data: { pushPermission: 'denied' } });

    // 19 prompts that reach a device, 1 that falls back: 5%, which is not
    // "exceeds 5%".
    for (let i = 0; i < 19; i += 1) {
      await app.notifications.dispatch({ userId: reachable.id, urgency: 'standard', context });
    }
    await app.notifications.dispatch({ userId: denied.id, urgency: 'standard', context });

    const atThreshold = await health.fallbackRate(time.clock());
    expect(atThreshold.prompts).toBe(20);
    expect(atThreshold.rate).toBe(FALLBACK_ALERT_RATE);
    expect(atThreshold.breaching).toBe(false);

    // One more fallback tips it over.
    await app.notifications.dispatch({ userId: denied.id, urgency: 'standard', context });
    const over = await health.fallbackRate(time.clock());
    expect(over.breaching).toBe(true);

    lines.length = 0;
    await health.check(time.clock());
    const alert = lines.find((l) => l.event === 'notification.fallback_rate');
    expect(alert).toBeDefined();
    expect(alert?.level).toBe(50); // pino error
    expect(alert?.threshold).toBe(FALLBACK_ALERT_RATE);
  });

  it('a rate over zero prompts is unknown, not zero — and never alerts', async () => {
    const at = privateWindow();
    const empty = new NotificationHealth({
      prisma,
      // A window of its own, with no dispatch in it at all.
      clock: () => at,
      log: app.log,
    });
    const rate = await empty.fallbackRate();
    expect(rate.prompts).toBe(0);
    expect(rate.rate).toBeNull();
    expect(rate.breaching).toBe(false);
  });

  it('bounces are counted and surfaced — losing email means losing the only fallback', async () => {
    time.set(privateWindow());
    const health = new NotificationHealth({ prisma, clock: time.clock, log: app.log });

    // Ten accepted messages, one of which bounced: 10%, past AWS's pause line.
    for (let i = 0; i < 9; i += 1) {
      await prisma.emailMessage.create({
        data: {
          channel: 'notification',
          toAddress: `ok-${randomUUID()}@example.test`,
          subject: 'x',
          status: 'delivered',
          createdAt: time.clock(),
        },
      });
    }
    await prisma.emailMessage.create({
      data: {
        channel: 'notification',
        toAddress: `bad-${randomUUID()}@example.test`,
        subject: 'x',
        status: 'bounced',
        createdAt: time.clock(),
      },
    });

    const reputation = await health.reputationRate(time.clock());
    expect(reputation.sent).toBe(10);
    expect(reputation.bounced).toBe(1);
    expect(reputation.bounceRate).toBeCloseTo(0.1);

    lines.length = 0;
    await health.check(time.clock());
    const record = lines.find((l) => l.event === 'email.reputation');
    expect(record).toBeDefined();
    expect(record?.level).toBe(50);
    expect(record?.bounced).toBe(1);
  });

  it('both jobs are registered on the runner, so nothing depends on being called by hand', () => {
    // Scheduled work runs on the job runner, never as check-on-read
    // (backend/CLAUDE.md). Nobody reads a dispatch row, so a check-on-read
    // fallback would simply never fire.
    const noop = { everyMs: 1, run: () => Promise.resolve() };
    expect(() => {
      app.jobs.register({ name: 'push-fallback-sweep', ...noop });
    }).toThrow(/already registered/);
    expect(() => {
      app.jobs.register({ name: 'notification-health', ...noop });
    }).toThrow(/already registered/);
  });
});
