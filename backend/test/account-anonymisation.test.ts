import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { ANONYMISE_JOB_NAME } from '../src/jobs/anonymise-accounts.js';
import type { DeletionBlocker } from '../src/modules/account/anonymise.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { RecordingEmailTransport, registerUser } from './helpers/users.js';

interface Err {
  error: { code: string };
}

describe.skipIf(databaseUrl === undefined)(
  'account anonymisation (plan §Phase 3: queued, frozen, 30-day backstop)',
  () => {
    let ctx: Awaited<ReturnType<typeof buildTestApp>>;
    const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
    const mail = new RecordingEmailTransport();
    const blocked = new Set<string>();
    const blocker: DeletionBlocker = {
      hasOpenBookings: (userId) => Promise.resolve(blocked.has(userId)),
    };
    const hookCalls: string[] = [];

    beforeAll(async () => {
      ctx = await buildTestApp({
        clock: time.clock,
        deps: { emailTransport: mail, deletionBlocker: blocker },
      });
      ctx.app.anonymisation.register('test-hook', async (tx, userId) => {
        hookCalls.push(userId);
        await tx.auditLogEntry.create({
          data: {
            actorType: 'system',
            action: 'test.hook_ran',
            targetType: 'user',
            targetId: userId,
            reason: 'test',
          },
        });
      });
    });
    afterAll(async () => {
      await ctx.app.close();
      await ctx.prisma.$disconnect();
    });

    async function frozenUser() {
      const u = await registerUser(ctx.app);
      await ctx.app.inject({
        method: 'POST',
        url: '/v1/users/me/deletion-request',
        headers: u.headers,
      });
      return u;
    }

    it('an account with no open bookings is anonymised on the next run: identity replaced, sessions dead, login impossible, hook ran in the transaction', async () => {
      const u = await frozenUser();
      const result = await ctx.app.anonymiser.runDue(time.clock(), blocker);
      expect(result.processed).toBeGreaterThanOrEqual(1);
      const row = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
      expect(row.status).toBe('anonymised');
      expect(row.fullName).toBe('Deleted user');
      expect(row.email).toBe(`deleted-${u.userId}@anonymised.raajjepro.invalid`);
      expect(row.phoneE164).toBeNull();
      expect(row.emailVerifiedAt).toBeNull();
      expect(row.anonymisedAt?.getTime()).toBe(time.clock().getTime());
      expect(
        (
          await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers })
        ).json<Err>().error.code,
      ).toBe('SESSION_EXPIRED');
      const login = await ctx.app.inject({
        method: 'POST',
        url: '/v1/auth/login',
        remoteAddress: freshIp(),
        payload: { email: u.email, password: u.password },
      });
      expect(login.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
      expect(hookCalls).toContain(u.userId);
      expect(
        await ctx.prisma.auditLogEntry.count({
          where: { action: 'test.hook_ran', targetId: u.userId },
        }),
      ).toBe(1);
      const audit = await ctx.prisma.auditLogEntry.findFirst({
        where: { action: 'user.anonymised', targetId: u.userId },
      });
      expect(audit?.reason).toBe('bookings_terminal');
      expect(audit?.actorType).toBe('system');
      // The original address is free to register again.
      expect((await registerUser(ctx.app, { email: u.email })).email).toBe(u.email);
    });

    it('an open booking holds anonymisation until the booking terminates', async () => {
      const u = await frozenUser();
      blocked.add(u.userId);
      await ctx.app.anonymiser.runDue(time.clock(), blocker);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe(
        'frozen',
      );
      expect(
        (await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers }))
          .statusCode,
      ).toBe(200);
      blocked.delete(u.userId);
      await ctx.app.anonymiser.runDue(time.clock(), blocker);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe(
        'anonymised',
      );
    });

    it('…and completes anyway at the 30-day backstop, with reason deletion_backstop', async () => {
      const u = await frozenUser();
      blocked.add(u.userId);
      time.advance(29 * 86_400_000);
      await ctx.app.anonymiser.runDue(time.clock(), blocker);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe(
        'frozen',
      );
      time.advance(86_400_000 + 1_000);
      await ctx.app.anonymiser.runDue(time.clock(), blocker);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe(
        'anonymised',
      );
      const audit = await ctx.prisma.auditLogEntry.findFirst({
        where: { action: 'user.anonymised', targetId: u.userId },
      });
      expect(audit?.reason).toBe('deletion_backstop');
      time.advance(-(30 * 86_400_000 + 1_000));
      blocked.delete(u.userId);
    });

    it('a hook that throws rolls the user back untouched, and the run continues to the next user', async () => {
      const bad = await frozenUser();
      const good = await frozenUser();
      ctx.app.anonymisation.register('failing-hook', (_tx, userId) =>
        userId === bad.userId ? Promise.reject(new Error('purge failed')) : Promise.resolve(),
      );
      const result = await ctx.app.anonymiser.runDue(time.clock(), blocker);
      expect(result.failed).toBeGreaterThanOrEqual(1);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: bad.userId } })).status).toBe(
        'frozen',
      );
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: good.userId } })).status).toBe(
        'anonymised',
      );
    });

    it('the provider profile keeps its tier but loses the business name', async () => {
      const u = await registerUser(ctx.app, { role: 'provider', businessName: 'Gone Trade' });
      await ctx.prisma.providerProfile.update({
        where: { userId: u.userId },
        data: { verificationTier: 'silver' },
      });
      await ctx.app.inject({
        method: 'POST',
        url: '/v1/users/me/deletion-request',
        headers: u.headers,
      });
      await ctx.app.anonymiser.runDue(time.clock(), blocker);
      const profile = await ctx.prisma.providerProfile.findUniqueOrThrow({
        where: { userId: u.userId },
      });
      expect(profile.businessName).toBeNull();
      expect(profile.verificationTier).toBe('silver');
    });

    it('the registered job runs the anonymiser through the real runner path — advisory lock held, heartbeat written', async () => {
      const u = await frozenUser();
      const result = await ctx.app.jobs.runOnce(ANONYMISE_JOB_NAME, time.clock());
      expect(result).toBe('ran');
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).status).toBe(
        'anonymised',
      );
      const heartbeat = await ctx.prisma.jobHeartbeat.findUniqueOrThrow({
        where: { jobName: ANONYMISE_JOB_NAME },
      });
      expect(heartbeat.firedAt.getTime()).toBe(time.clock().getTime());
    });
  },
);
