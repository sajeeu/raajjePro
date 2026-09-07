import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { RecordingEmailTransport, registerUser } from './helpers/users.js';

describe.skipIf(databaseUrl === undefined)('data export and deletion request', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    // accessTokenMinutes raised well past the default 15: the idempotent-repeat
    // case below advances the clock by an hour and reuses the same bearer
    // token — the session itself must stay live (that's the point being
    // tested), but a stock-length access token would expire on its own and
    // mask that with an unrelated 401.
    ctx = await buildTestApp({
      clock: time.clock,
      accessTokenMinutes: 120,
      deps: { emailTransport: mail },
    });
    ctx.app.exportContributors.register({
      key: 'testSection',
      collect: (userId) => Promise.resolve({ forUser: userId, rows: [1, 2, 3] }),
    });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('export returns complete own data as an attachment: account with phone, profile, sessions, contributor sections — no hash, no tokens', async () => {
    const u = await registerUser(ctx.app, { role: 'provider', businessName: 'Export Trade' });
    await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      remoteAddress: freshIp(),
      payload: { email: u.email, password: u.password, deviceName: 'Second device' },
    });
    const res = await ctx.app.inject({
      method: 'GET',
      url: '/v1/users/me/data-export',
      headers: u.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-disposition']).toMatch(
      /attachment; filename="raajjepro-export-2026-09-06\.json"/,
    );
    const body = res.json<{ data: Record<string, unknown> }>().data;
    const account = body.account as { email: string; phone: unknown; termsAcceptedAt: unknown };
    const providerProfile = body.providerProfile as {
      businessName: string;
      verificationTier: string;
    };
    const sessions = body.sessions as { deviceName: string }[];
    expect(body.exportedAt).toBe(time.clock().toISOString());
    expect(account.email).toBe(u.email.toLowerCase());
    expect(account.phone).toEqual({ dialCode: '+960', number: u.phone });
    expect(account.termsAcceptedAt).toBeTruthy();
    expect(providerProfile.businessName).toBe('Export Trade');
    expect(providerProfile.verificationTier).toBe('none');
    expect(sessions).toHaveLength(2);
    expect(sessions.map((s) => s.deviceName).sort()).toEqual(['Second device', 'vitest']);
    expect(body.testSection).toEqual({ forUser: u.userId, rows: [1, 2, 3] });
    expect(res.body).not.toContain('passwordHash');
    expect(res.body).not.toContain(u.tokens.refreshToken);
    expect(res.body).not.toContain('tokenHash');
  });

  it('a deletion request is accepted at once (202), freezes the account, keeps the session, and repeats idempotently', async () => {
    const u = await registerUser(ctx.app);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/deletion-request',
      headers: u.headers,
    });
    expect(res.statusCode).toBe(202);
    const data = res.json<{
      data: { status: string; deletionRequestedAt: string; deletionDeadlineAt: string };
    }>().data;
    expect(data.status).toBe('frozen');
    expect(data.deletionRequestedAt).toBe('2026-09-06T10:00:00.000Z');
    expect(data.deletionDeadlineAt).toBe('2026-10-06T10:00:00.000Z');
    const me = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers });
    expect(me.statusCode).toBe(200);
    expect(me.json<{ data: { status: string } }>().data.status).toBe('frozen');
    time.advance(3_600_000);
    const again = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/deletion-request',
      headers: u.headers,
    });
    expect(again.statusCode).toBe(202);
    expect(again.json<{ data: { deletionRequestedAt: string } }>().data.deletionRequestedAt).toBe(
      '2026-09-06T10:00:00.000Z',
    );
    time.advance(-3_600_000);
    const audits = await ctx.prisma.auditLogEntry.count({
      where: { action: 'user.deletion.requested', actorId: u.userId },
    });
    expect(audits).toBe(1);
  });
});
