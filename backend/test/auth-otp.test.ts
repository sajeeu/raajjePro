import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, createUser, RecordingEmailTransport } from './helpers/users.js';

interface Err {
  error: {
    code: string;
    details?: { retryAfterSeconds?: number; limit?: string; attemptsRemaining?: number };
  };
}

describe.skipIf(databaseUrl === undefined)(
  'email OTP — send limits, attempts, verification',
  () => {
    let ctx: Awaited<ReturnType<typeof buildTestApp>>;
    const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
    const mail = new RecordingEmailTransport();

    beforeAll(async () => {
      // accessTokenMinutes raised well past the default 15: several cases below
      // travel the clock far enough to clear the OTP address (15 min) and
      // account (60 min) windows, which would otherwise expire the bearer
      // token used to make the *next* request and fail on ACCESS_TOKEN_EXPIRED
      // — a collision with an unrelated system parameter, not the send-limit
      // rule actually under test here.
      ctx = await buildTestApp({
        clock: time.clock,
        deps: { emailTransport: mail },
        accessTokenMinutes: 90,
      });
    });
    afterAll(async () => {
      await ctx.app.close();
      await ctx.prisma.$disconnect();
    });

    async function signedIn(emailVerified = false) {
      const user = await createUser(ctx.prisma, { emailVerified });
      const full = await ctx.prisma.user.findUniqueOrThrow({
        where: { id: user.id },
        include: { providerProfile: true },
      });
      const tokens = await ctx.app.auth.openSession(
        full,
        { ip: freshIp(), userAgent: 'vitest', requestId: 'r' },
        time.clock(),
        'phone',
      );
      return { user, headers: bearer(tokens.accessToken) };
    }
    const send = (headers: Record<string, string>) =>
      ctx.app.inject({
        method: 'POST',
        url: '/v1/auth/verify-email/send',
        headers,
        remoteAddress: freshIp(),
      });
    const confirm = (headers: Record<string, string>, code: string) =>
      ctx.app.inject({
        method: 'POST',
        url: '/v1/auth/verify-email/confirm',
        headers,
        payload: { code },
      });

    it('sends a six-digit code by email on the otp channel with the user id attached, and confirms it', async () => {
      const { user, headers } = await signedIn();
      const res = await send(headers);
      expect(res.statusCode).toBe(200);
      expect(res.json<{ data: { status: string } }>().data.status).toBe('sent');
      const code = mail.latestCodeFor(user.email);
      expect(code).toMatch(/^\d{6}$/);
      const last = mail.sent[mail.sent.length - 1];
      expect(last?.channel).toBe('otp');
      expect(last?.recipientUserId).toBe(user.id);
      expect(last?.text).not.toMatch(/https?:\/\//);
      const ok = await confirm(headers, code ?? '');
      expect(ok.statusCode).toBe(200);
      const me = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers });
      expect(me.json<{ data: { emailVerified: boolean } }>().data.emailVerified).toBe(true);
      const logged = await ctx.prisma.emailOtp.findFirst({
        where: { userId: user.id },
        include: { emailMessage: true },
      });
      expect(logged?.emailMessage?.recipientUserId).toBe(user.id);
      const again = await send(headers);
      expect(again.json<Err>().error.code).toBe('EMAIL_ALREADY_VERIFIED');
    });

    it('address limit: three sends per 15 minutes, the fourth is OTP_RATE_LIMITED with the wait and the limit named', async () => {
      const { headers } = await signedIn();
      for (let i = 0; i < 3; i += 1) {
        expect((await send(headers)).statusCode).toBe(200);
        time.advance(60_000);
      }
      const fourth = await send(headers);
      expect(fourth.statusCode).toBe(429);
      const err = fourth.json<Err>().error;
      expect(err.code).toBe('OTP_RATE_LIMITED');
      expect(err.details?.limit).toBe('address');
      expect(err.details?.retryAfterSeconds).toBe(12 * 60);
      expect(fourth.headers['retry-after']).toBe(String(12 * 60));
      time.advance(12 * 60_000 + 1_000);
      expect((await send(headers)).statusCode).toBe(200);
    });

    it('account limit: five sends per hour across addresses, the sixth is limited by account', async () => {
      const { user, headers } = await signedIn();
      // Three to the account's own address, then two change-email sends to other addresses.
      for (let i = 0; i < 3; i += 1) expect((await send(headers)).statusCode).toBe(200);
      for (const target of ['a', 'b']) {
        await ctx.app.otp.send({
          userId: user.id,
          purpose: 'change_email',
          targetEmail: `${target}-${user.id}@example.test`,
          meta: { ip: '10.0.0.1', userAgent: '', requestId: 'r' },
        });
      }
      time.advance(16 * 60_000); // the 15-minute address window has passed
      const sixth = await send(headers);
      expect(sixth.statusCode).toBe(429);
      expect(sixth.json<Err>().error.details?.limit).toBe('account');
      expect(sixth.json<Err>().error.details?.retryAfterSeconds).toBe(44 * 60);
      time.advance(44 * 60_000 + 1_000);
      expect((await send(headers)).statusCode).toBe(200);
    });

    it('ten concurrent sends → exactly three succeed', async () => {
      const { headers } = await signedIn();
      const results = await Promise.all(Array.from({ length: 10 }, () => send(headers)));
      expect(results.filter((r) => r.statusCode === 200)).toHaveLength(3);
      expect(results.filter((r) => r.statusCode === 429)).toHaveLength(7);
    });

    it('five wrong attempts invalidate every live code; the right one then fails; a fresh send works again', async () => {
      const { user, headers } = await signedIn();
      await send(headers);
      const real = mail.latestCodeFor(user.email) ?? '';
      const wrong = real === '000000' ? '111111' : '000000';
      for (let i = 1; i <= 4; i += 1) {
        const res = await confirm(headers, wrong);
        expect(res.statusCode).toBe(422);
        expect(res.json<Err>().error.code).toBe('OTP_INCORRECT');
        expect(res.json<Err>().error.details?.attemptsRemaining).toBe(5 - i);
      }
      const fifth = await confirm(headers, wrong);
      expect(fifth.json<Err>().error.code).toBe('OTP_INVALIDATED');
      const late = await confirm(headers, real);
      expect(late.json<Err>().error.code).toBe('OTP_EXPIRED');
      time.advance(60_000);
      await send(headers);
      const fresh = mail.latestCodeFor(user.email) ?? '';
      expect((await confirm(headers, fresh)).statusCode).toBe(200);
    });

    it('every live code works until it expires; an expired one is OTP_EXPIRED', async () => {
      const { user, headers } = await signedIn();
      await send(headers);
      const first = mail.latestCodeFor(user.email) ?? '';
      time.advance(60_000);
      await send(headers);
      const second = mail.latestCodeFor(user.email) ?? '';
      expect(second).not.toBe(first);
      // Both live: the FIRST one still verifies.
      expect((await confirm(headers, first)).statusCode).toBe(200);
      const other = await signedIn();
      await send(other.headers);
      time.advance(11 * 60_000);
      const expired = await confirm(other.headers, mail.latestCodeFor(other.user.email) ?? '');
      expect(expired.json<Err>().error.code).toBe('OTP_EXPIRED');
    });

    it('a suppressed address is reported as suppressed, not pretended sent', async () => {
      const { user, headers } = await signedIn();
      await ctx.prisma.emailSuppression.create({ data: { address: user.email, reason: 'manual' } });
      const res = await send(headers);
      expect(res.statusCode).toBe(200);
      expect(res.json<{ data: { status: string } }>().data.status).toBe('suppressed');
    });
  },
);
