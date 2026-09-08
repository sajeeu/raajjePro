/**
 * §Phase 3c's fallback chain. This is the file that matters most in the phase:
 * the rungs are the product decision, and the plan is explicit that an earlier
 * revision got them wrong in a way that made a fallback useless.
 *
 * Every test asserts a rule, not an implementation — what the sender was ASKED
 * to do and when the email went, never how the dispatcher is wired.
 */
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import {
  buildTestApp,
  controllableClock,
  databaseUrl,
  RecordingPushTransport,
} from './helpers/app.js';
import { createUser, RecordingEmailTransport } from './helpers/users.js';
import { FALLBACK_AFTER_MINUTES } from '../src/modules/push/dispatcher.js';
import { FallbackSweep } from '../src/modules/push/sweep.js';
import type { NotificationContext } from '../src/modules/push/types.js';
import type { FastifyInstance } from 'fastify';
import type { PrismaClient } from '../src/generated/prisma/client.js';

const describeIfDb = databaseUrl === undefined ? describe.skip : describe;

const acceptPrompt: NotificationContext = {
  kind: 'booking_accept_prompt',
  bookingType: 'Cleaning',
  customerFirstName: 'Aishath',
  islandName: 'Dh. Meedhoo',
};
const emergencyPrompt: NotificationContext = {
  kind: 'emergency_dispatch',
  bookingType: 'AC Repair',
  customerFirstName: 'Ibrahim',
  islandName: 'Kulhudhuffushi',
};

describeIfDb('Phase 3c — the two-rung fallback chain', () => {
  let app: FastifyInstance;
  let prisma: PrismaClient;
  let push: RecordingPushTransport;
  let mail: RecordingEmailTransport;
  const time = controllableClock(new Date('2026-09-08T08:00:00.000Z'));

  beforeAll(async () => {
    push = new RecordingPushTransport();
    mail = new RecordingEmailTransport();
    ({ app, prisma } = await buildTestApp({
      clock: time.clock,
      deps: { pushTransport: push, emailTransport: mail },
    }));
  });
  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  /** A user with one live Android registration and permission granted. */
  async function providerWithDevice(permission: 'granted' | 'denied' | 'unknown' = 'granted') {
    const user = await createUser(prisma, { emailVerified: true });
    await prisma.user.update({ where: { id: user.id }, data: { pushPermission: permission } });
    const token = `tok-${randomUUID()}`;
    await prisma.deviceToken.create({
      data: {
        userId: user.id,
        installationId: `inst-${randomUUID()}`,
        platform: 'android',
        token,
        deviceName: 'Pixel 8',
        lastSeenAt: time.clock(),
      },
    });
    return { user, token };
  }

  function mailTo(address: string) {
    return mail.sent.filter((m) => m.to === address.toLowerCase());
  }

  it('rung 1 — permission already denied: the email goes immediately, and the push is still attempted', async () => {
    const user = await createUser(prisma, { emailVerified: true });
    await prisma.user.update({ where: { id: user.id }, data: { pushPermission: 'denied' } });
    const token = `tok-${randomUUID()}`;
    await prisma.deviceToken.create({
      data: {
        userId: user.id,
        installationId: `inst-${randomUUID()}`,
        platform: 'android',
        token,
        deviceName: 'Old phone',
        lastSeenAt: time.clock(),
      },
    });

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context: acceptPrompt,
    });

    expect(result.emailSent).toBe(true);
    expect(result.emailReason).toBe('permission_denied');
    // "Do not wait" — nothing is armed for later, because the mail already went.
    expect(result.fallbackDueAt).toBeNull();
    expect(mailTo(user.email)).toHaveLength(1);
    // "in parallel with the (futile) push attempt": permission state is the
    // app's last report, and the user may have turned it back on since.
    expect(push.tokens()).toContain(token);
  });

  it('rung 1 also covers a provider with no live device at all', async () => {
    // Not a case §Phase 3c names. Same reasoning as a denial — push cannot
    // land — so waiting 30 minutes would only make the provider late.
    // docs/decisions/15-phase-3c-push.md records the decision.
    const user = await createUser(prisma, { emailVerified: true });

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context: acceptPrompt,
    });

    expect(result.pushAttempted).toBe(0);
    expect(result.emailSent).toBe(true);
    expect(result.emailReason).toBe('no_registered_device');
    expect(result.fallbackDueAt).toBeNull();
    expect(mailTo(user.email)).toHaveLength(1);
  });

  it('rung 2 — push permitted: no email at dispatch, a 30-minute timer instead', async () => {
    const { user } = await providerWithDevice();

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context: acceptPrompt,
    });

    expect(result.pushSent).toBe(1);
    expect(result.emailSent).toBe(false);
    expect(mailTo(user.email)).toHaveLength(0);
    expect(result.fallbackDueAt).toEqual(
      new Date(time.clock().getTime() + FALLBACK_AFTER_MINUTES * 60_000),
    );
  });

  it('rung 2 — the email goes at 30 minutes when nothing confirmed delivery', async () => {
    const { user } = await providerWithDevice();
    const before = mailTo(user.email).length;
    const dispatch = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context: acceptPrompt,
    });

    const sweep = new FallbackSweep({
      prisma,
      dispatcher: app.notifications,
      clock: time.clock,
      log: app.log,
    });

    // 29 minutes: nothing is due. Time is advanced, never waited for.
    time.advance(29 * 60_000);
    await sweep.run(time.clock());
    expect(mailTo(user.email)).toHaveLength(before);

    // 30 minutes: it goes.
    time.advance(60_000);
    await sweep.run(time.clock());
    expect(mailTo(user.email)).toHaveLength(before + 1);

    const row = await prisma.pushDispatch.findUniqueOrThrow({
      where: { id: dispatch.dispatchId },
    });
    expect(row.emailReason).toBe('unconfirmed_after_window');
    // Cleared, so a second sweep does not send a second mail.
    expect(row.fallbackDueAt).toBeNull();
    await sweep.run(time.clock());
    expect(mailTo(user.email)).toHaveLength(before + 1);
  });

  it('rung 2 — a device acking the push cancels the email entirely', async () => {
    const { user } = await providerWithDevice();
    const before = mailTo(user.email).length;
    const dispatch = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context: acceptPrompt,
    });

    await app.pushRegistration.acknowledge(user.id, dispatch.dispatchId, undefined);

    const sweep = new FallbackSweep({
      prisma,
      dispatcher: app.notifications,
      clock: time.clock,
      log: app.log,
    });
    time.advance(2 * 60 * 60_000);
    await sweep.run(time.clock());

    expect(mailTo(user.email)).toHaveLength(before);
    const row = await prisma.pushDispatch.findUniqueOrThrow({
      where: { id: dispatch.dispatchId },
    });
    expect(row.emailSentAt).toBeNull();
  });

  it('the vendor accepting a push is NOT delivery — only an ack is', async () => {
    // The regression this guards: treating the provider message id as
    // confirmation would silently disable the entire 30-minute rung.
    const { user } = await providerWithDevice();
    const before = mailTo(user.email).length;
    const dispatch = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context: acceptPrompt,
    });
    expect(dispatch.pushSent).toBe(1);

    const row = await prisma.pushDispatch.findUniqueOrThrow({
      where: { id: dispatch.dispatchId },
    });
    expect(row.confirmedAt).toBeNull();

    const sweep = new FallbackSweep({
      prisma,
      dispatcher: app.notifications,
      clock: time.clock,
      log: app.log,
    });
    time.advance((FALLBACK_AFTER_MINUTES + 1) * 60_000);
    await sweep.run(time.clock());
    expect(mailTo(user.email)).toHaveLength(before + 1);
  });

  it('emergency — push and email fire together, with no ladder, even on a granted device', async () => {
    const { user, token } = await providerWithDevice('granted');

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'emergency',
      context: emergencyPrompt,
    });

    expect(result.emailSent).toBe(true);
    expect(result.emailReason).toBe('emergency_parallel');
    expect(result.pushSent).toBe(1);
    expect(push.tokens()).toContain(token);
    expect(mailTo(user.email)).toHaveLength(1);
    // Nothing armed: there is no window left to wait out. An emergency
    // response window is 30 minutes (§1c) — the same length as the timer.
    expect(result.fallbackDueAt).toBeNull();
    const row = await prisma.pushDispatch.findUniqueOrThrow({
      where: { id: result.dispatchId },
    });
    expect(row.fallbackDueAt).toBeNull();
  });

  it('no fallback is ever keyed to the acceptance window', () => {
    // The defect §Phase 3c names by name: an earlier revision waited for the
    // 24-hour acceptance window, so a fallback could arrive at hour 23 on a
    // booking that had already died. 30 minutes, and only 30 minutes.
    expect(FALLBACK_AFTER_MINUTES).toBe(30);
    expect(FALLBACK_AFTER_MINUTES).toBeLessThan(24 * 60);
  });
});
