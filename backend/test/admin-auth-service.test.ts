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
    await expect(service.createAdmin(email, 'short', {})).rejects.toMatchObject({
      code: 'PASSWORD_TOO_SHORT',
    });
    const admin = await service.createAdmin(email, PASSWORD, {});
    expect(admin.email).toBe(email.toLowerCase());
    expect(admin.totpEnrolledAt).toBeNull();
    await expect(service.createAdmin(email.toLowerCase(), PASSWORD, {})).rejects.toMatchObject({
      code: 'CONFLICT',
    });
    const entry = await prisma.auditLogEntry.findFirst({
      where: { action: 'admin.created', targetId: admin.id },
    });
    expect(entry?.actorType).toBe('system');
  });

  it('login yields a session in the enrolment-required state for a new admin, and INVALID_CREDENTIALS otherwise', async () => {
    const { service } = build();
    const email = `admin-${randomUUID()}@example.test`;
    await service.createAdmin(email, PASSWORD, {});
    const result = await service.login(email, PASSWORD, meta);
    expect(result.state).toBe('mfa_enrolment_required');
    expect(result.session.mfaVerifiedAt).toBeNull();
    await expect(service.login(email, 'wrong password!!', meta)).rejects.toMatchObject({
      code: 'INVALID_CREDENTIALS',
    });
    await expect(
      service.login(`nobody-${randomUUID()}@example.test`, PASSWORD, meta),
    ).rejects.toMatchObject({ code: 'INVALID_CREDENTIALS' });
    const failed = await prisma.auditLogEntry.count({
      where: { action: 'admin.login.failed', targetId: result.session.adminId },
    });
    expect(failed).toBe(1);
  });

  it('a disabled admin cannot log in', async () => {
    const { service } = build();
    const email = `admin-${randomUUID()}@example.test`;
    const admin = await service.createAdmin(email, PASSWORD, {});
    await prisma.adminUser.update({ where: { id: admin.id }, data: { status: 'disabled' } });
    await expect(service.login(email, PASSWORD, meta)).rejects.toMatchObject({
      code: 'INVALID_CREDENTIALS',
    });
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

    expect((await service.listSessions(admin.id)).map((s) => s.id).sort()).toEqual(
      [a.session.id, b.session.id].sort(),
    );
    await service.revokeSession(admin.id, a.session.id, 'lost laptop', meta);
    expect(await service.resolveSession(a.token)).toEqual({ rejection: 'UNAUTHENTICATED' });
    expect(await service.resolveSession(b.token)).toHaveProperty('principal');
    expect((await service.listSessions(admin.id)).map((s) => s.id)).toEqual([b.session.id]);

    await expect(
      service.revokeSession(randomUUID(), b.session.id, 'not mine', meta),
    ).rejects.toMatchObject({ code: 'NOT_FOUND' });
    const audit = await prisma.auditLogEntry.findFirst({
      where: { action: 'admin.session.revoked', targetId: a.session.id },
    });
    expect(audit?.reason).toBe('lost laptop');
  });
});
