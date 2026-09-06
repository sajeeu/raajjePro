import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { AuditService } from '../src/modules/audit/service.js';
import { createPrismaClient } from '../src/db/client.js';
import type { AuditLogEntry, PrismaClient } from '../src/generated/prisma/client.js';
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
        await audit.record(tx, {
          actorType: 'admin',
          actorId,
          action: 'test.rolled_back',
          targetType: 'thing',
          targetId: randomUUID(),
          reason: 'testing',
        });
        throw new Error('abort');
      }),
    ).rejects.toThrow('abort');
    expect(await prisma.auditLogEntry.count({ where: { actorId } })).toBe(0);
  });

  it('refuses an empty reason', async () => {
    const audit = new AuditService(prisma, () => new Date());
    await expect(
      audit.record(prisma, {
        actorType: 'system',
        action: 'x',
        targetType: 'y',
        targetId: 'z',
        reason: '   ',
      }),
    ).rejects.toThrow(/reason/);
  });

  it('queries by date, actor and action with a stable cursor', async () => {
    const time = controllableClock(new Date('2026-09-06T08:00:00Z'));
    const audit = new AuditService(prisma, time.clock);
    const actorId = randomUUID();
    const action = `test.${randomUUID()}`;
    for (let i = 0; i < 5; i += 1) {
      await audit.record(prisma, {
        actorType: 'admin',
        actorId,
        action,
        targetType: 't',
        targetId: String(i),
        reason: 'r',
      });
      time.advance(60_000);
    }
    await audit.record(prisma, {
      actorType: 'admin',
      actorId,
      action: 'other',
      targetType: 't',
      targetId: 'x',
      reason: 'r',
    });

    const byAction = await audit.query({ action, limit: 10 });
    expect(byAction.items.map((e) => e.targetId)).toEqual(['4', '3', '2', '1', '0']);

    const page1 = await audit.query({ actorId, limit: 4 });
    expect(page1.items).toHaveLength(4);
    expect(page1.nextCursor).not.toBeNull();
    const page2 = await audit.query({ actorId, limit: 4, cursor: page1.nextCursor ?? undefined });
    expect(page2.items).toHaveLength(2);
    expect(page2.nextCursor).toBeNull();

    const window = await audit.query({
      actorId,
      from: new Date('2026-09-06T08:01:30Z'),
      to: new Date('2026-09-06T08:03:30Z'),
      limit: 10,
    });
    expect(window.items.map((e) => e.targetId)).toEqual(['3', '2']);
  });

  it('paginates stably when several entries share a createdAt', async () => {
    const time = controllableClock(new Date('2026-09-06T08:00:00Z'));
    const audit = new AuditService(prisma, time.clock);
    const actorId = randomUUID();
    const recorded: AuditLogEntry[] = [];
    for (let i = 0; i < 5; i += 1) {
      // No time.advance() here — every entry shares the same createdAt, so
      // only the (createdAt, id) tie-break keeps pagination stable.
      recorded.push(
        await audit.record(prisma, {
          actorType: 'admin',
          actorId,
          action: 'test.same_instant',
          targetType: 't',
          targetId: String(i),
          reason: 'r',
        }),
      );
    }

    const seen: string[] = [];
    let cursor: string | undefined;
    for (let page = 0; page < 3; page += 1) {
      const result = await audit.query({ actorId, limit: 2, cursor });
      const ids = result.items.map((e) => e.id);
      expect(ids).toEqual([...ids].sort().reverse());
      seen.push(...ids);
      if (page < 2) {
        expect(result.nextCursor).not.toBeNull();
      } else {
        expect(result.nextCursor).toBeNull();
      }
      cursor = result.nextCursor ?? undefined;
    }

    expect(new Set(seen).size).toBe(5);
    expect(seen.sort()).toEqual(recorded.map((e) => e.id).sort());
  });
});
