/**
 * "SES has no searchable activity UI, so the message log is ours to build…
 * Phase 10b needs to answer 'did this provider actually receive the emergency
 * alert?' in one lookup" (§Phase 3c). This is the lookup; Phase 10b puts a
 * screen on it.
 */
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';

import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { CSRF, createEnrolledAdmin, loginAndVerify } from './helpers/admin.js';
import { createUser } from './helpers/users.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import type { NotificationContext } from '../src/modules/push/types.js';

const describeIfDb = databaseUrl === undefined ? describe.skip : describe;

const emergency: NotificationContext = {
  kind: 'emergency_dispatch',
  bookingType: 'AC Repair',
  customerFirstName: 'Ibrahim',
  islandName: 'Kulhudhuffushi',
};

describeIfDb('Phase 3c — the delivery-log lookup', () => {
  let app: FastifyInstance;
  let prisma: PrismaClient;

  beforeAll(async () => {
    ({ app, prisma } = await buildTestApp());
  });
  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('answers "did this provider get the emergency alert?" in one lookup, by user id', async () => {
    const provider = await createUser(prisma, { emailVerified: true });
    const dispatch = await app.notifications.dispatch({
      userId: provider.id,
      urgency: 'emergency',
      context: emergency,
    });

    const { items } = await app.emailLog.query({ recipientUserId: provider.id, limit: 50 });
    expect(items).toHaveLength(1);
    expect(items[0]?.channel).toBe('notification');
    expect(items[0]?.subject).toContain('AC Repair');

    // And the dispatch points at the message, so the two halves join up.
    const row = await prisma.pushDispatch.findUniqueOrThrow({
      where: { id: dispatch.dispatchId },
    });
    expect(row.emailMessageId).toBe(items[0]?.id);
  });

  it('an address is matched however it was typed', async () => {
    const address = `Mixed-${randomUUID()}@Example.Test`;
    await prisma.emailMessage.create({
      data: { channel: 'otp', toAddress: address.toLowerCase(), subject: 'x', status: 'sent' },
    });
    const { items } = await app.emailLog.query({
      address: `  ${address.toUpperCase()} `,
      limit: 10,
    });
    expect(items).toHaveLength(1);
  });

  it('carries the SNS events, which is what turns "we sent it" into "they got it"', async () => {
    const message = await prisma.emailMessage.create({
      data: {
        channel: 'notification',
        toAddress: `evt-${randomUUID()}@example.test`,
        subject: 'x',
        status: 'delivered',
      },
    });
    await prisma.emailEvent.create({
      data: {
        snsMessageId: randomUUID(),
        messageId: message.id,
        eventType: 'Delivery',
        occurredAt: new Date(),
        payload: {},
      },
    });
    const { items } = await app.emailLog.query({ address: message.toAddress, limit: 10 });
    expect(items[0]?.events.map((e) => e.eventType)).toEqual(['Delivery']);
  });

  it('paginates rather than returning an unbounded set', async () => {
    const address = `page-${randomUUID()}@example.test`;
    for (let i = 0; i < 3; i += 1) {
      await prisma.emailMessage.create({
        data: { channel: 'otp', toAddress: address, subject: `m${String(i)}`, status: 'sent' },
      });
    }
    const first = await app.emailLog.query({ address, limit: 2 });
    expect(first.items).toHaveLength(2);
    expect(first.nextCursor).not.toBeNull();
    const second = await app.emailLog.query({
      address,
      limit: 2,
      cursor: first.nextCursor ?? '',
    });
    expect(second.items).toHaveLength(1);
    expect(second.nextCursor).toBeNull();
  });

  it('the route is admin-only — the rows carry recipient email addresses', async () => {
    const anonymous = await app.inject({
      method: 'GET',
      url: '/v1/admin/message-log',
      headers: { 'x-forwarded-for': freshIp() },
    });
    expect(anonymous.statusCode).toBe(401);

    const admin = await createEnrolledAdmin(app);
    const { cookie } = await loginAndVerify(app, admin.email, admin.secret);
    const res = await app.inject({
      method: 'GET',
      url: '/v1/admin/message-log?limit=1',
      headers: { cookie, ...CSRF, 'x-forwarded-for': freshIp() },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json<{ data: unknown[] }>().data).toBeInstanceOf(Array);
  });
});
