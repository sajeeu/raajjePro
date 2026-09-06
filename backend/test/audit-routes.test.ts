import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, databaseUrl } from './helpers/app.js';
import { CSRF, createEnrolledAdmin, loginAndVerify } from './helpers/admin.js';

interface Entry {
  id: string;
  action: string;
  actorId: string | null;
  targetId: string;
  reason: string;
  createdAt: string;
}

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
    const sessions = await ctx.app.inject({
      method: 'GET',
      url: '/v1/admin/auth/sessions',
      headers: { cookie },
    });
    const target = sessions
      .json<{ data: { id: string; current: boolean }[] }>()
      .data.find((s) => !s.current);
    expect(target).toBeDefined();
    expect(other.verifyStatus).toBe(200);

    const revoke = await ctx.app.inject({
      method: 'DELETE',
      url: `/v1/admin/auth/sessions/${target?.id ?? ''}`,
      headers: { cookie, ...CSRF },
      payload: { reason: 'left signed in at the café' },
    });
    expect(revoke.statusCode).toBe(200);

    const byAction = await ctx.app.inject({
      method: 'GET',
      url: `/v1/admin/audit-log?action=admin.session.revoked&actorId=${admin.adminId}`,
      headers: { cookie },
    });
    expect(byAction.statusCode).toBe(200);
    const items = byAction.json<{ data: Entry[]; meta: { nextCursor: string | null } }>();
    expect(items.data).toHaveLength(1);
    expect(items.data[0]).toMatchObject({
      action: 'admin.session.revoked',
      actorId: admin.adminId,
      targetId: target?.id,
      reason: 'left signed in at the café',
    });
    expect(items.data[0]).not.toHaveProperty('ipAddress');

    const from = encodeURIComponent(new Date(Date.now() - 60_000).toISOString());
    const to = encodeURIComponent(new Date(Date.now() + 60_000).toISOString());
    const byDate = await ctx.app.inject({
      method: 'GET',
      url: `/v1/admin/audit-log?from=${from}&to=${to}&actorId=${admin.adminId}&limit=2`,
      headers: { cookie },
    });
    const page = byDate.json<{ data: Entry[]; meta: { nextCursor: string | null } }>();
    expect(page.data).toHaveLength(2);
    expect(page.meta.nextCursor).not.toBeNull();
    const next = await ctx.app.inject({
      method: 'GET',
      url: `/v1/admin/audit-log?actorId=${admin.adminId}&limit=2&cursor=${page.meta.nextCursor ?? ''}`,
      headers: { cookie },
    });
    expect(next.statusCode).toBe(200);
    expect(next.json<{ data: Entry[] }>().data[0]?.id).not.toBe(page.data[0]?.id);
  });

  it('rejects a bad limit and a malformed cursor with the envelope', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const { cookie } = await loginAndVerify(ctx.app, admin.email, admin.secret);
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/admin/audit-log?limit=1000',
          headers: { cookie },
        })
      ).statusCode,
    ).toBe(400);
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/admin/audit-log?cursor=!!!',
          headers: { cookie },
        })
      ).statusCode,
    ).toBe(400);
  });
});
