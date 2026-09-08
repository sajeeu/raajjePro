import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { OTP_ADDRESS_LIMIT } from '../src/modules/auth/otp.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { createUser, freshEmail, RecordingEmailTransport } from './helpers/users.js';

interface Err {
  error: { code: string; details?: { attemptsRemaining?: number } };
}
interface RequestData {
  data: { expiresAt: string; resendAvailableAt: string };
}
interface Injected {
  statusCode: number;
  body: string;
}

describe.skipIf(databaseUrl === undefined)('forgot password (plan §Phase 3b)', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-08T09:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  function post(url: string, payload: Record<string, unknown>) {
    return ctx.app.inject({
      method: 'POST',
      url: `/v1/auth/password-reset/${url}`,
      remoteAddress: freshIp(),
      payload,
    });
  }

  /** A verified, active account plus the code that reaches its inbox. */
  async function requestCodeFor(email: string) {
    const res = await post('request', { email });
    expect(res.statusCode).toBe(200);
    const code = mail.latestCodeFor(email);
    expect(code).toMatch(/^\d{6}$/);
    return { body: res.json<RequestData>().data, code: code ?? '' };
  }

  async function verifiedUser() {
    const user = await createUser(ctx.prisma, { emailVerified: true });
    return user;
  }

  /**
   * Two `request` responses a caller must not be able to tell apart. Compares
   * the raw body rather than the parsed one — what defeats enumeration is the
   * bytes on the wire being the same, and they can be: the envelope is a bare
   * `{ data }` with no request id, and the clock only moves when a test moves
   * it, so two silent responses in one test render identically.
   */
  function expectIndistinguishable(actual: Injected, reference: Injected) {
    expect(actual.statusCode).toBe(reference.statusCode);
    expect(actual.body).toBe(reference.body);
  }

  /** Messages this transport has delivered to `to`, across the whole file. */
  function mailCountFor(to: string) {
    return mail.sent.filter((m) => m.to === to.toLowerCase()).length;
  }

  it('the full cycle: request → verify → confirm, and the new password signs in', async () => {
    const user = await verifiedUser();
    const { code } = await requestCodeFor(user.email);

    const verified = await post('verify', { email: user.email, code });
    expect(verified.statusCode).toBe(200);
    expect(verified.json<{ data: { codeValid: boolean } }>().data.codeValid).toBe(true);

    const confirmed = await post('confirm', {
      email: user.email,
      code,
      newPassword: 'a brand new password',
    });
    expect(confirmed.statusCode).toBe(200);

    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      remoteAddress: freshIp(),
      payload: { email: user.email, password: 'a brand new password' },
    });
    expect(login.statusCode).toBe(200);

    // And the password it replaced no longer does.
    const old = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      remoteAddress: freshIp(),
      payload: { email: user.email, password: user.password },
    });
    expect(old.statusCode).toBe(401);
  });

  it('every refresh token is invalid afterwards — the Done-when clause', async () => {
    const user = await verifiedUser();
    const full = await ctx.prisma.user.findUniqueOrThrow({
      where: { id: user.id },
      include: { providerProfile: true },
    });
    const meta = { ip: freshIp(), userAgent: 'vitest', requestId: 'r' };
    const phone = await ctx.app.auth.openSession(full, meta, time.clock(), 'phone');
    const tablet = await ctx.app.auth.openSession(full, meta, time.clock(), 'tablet');

    const { code } = await requestCodeFor(user.email);
    await post('confirm', { email: user.email, code, newPassword: 'another new password' });

    for (const tokens of [phone, tablet]) {
      const refreshed = await ctx.app.inject({
        method: 'POST',
        url: '/v1/auth/refresh',
        remoteAddress: freshIp(),
        payload: { refreshToken: tokens.refreshToken },
      });
      expect(refreshed.statusCode).toBe(401);
    }
    const live = await ctx.prisma.userSession.findMany({
      where: { userId: user.id, revokedAt: null },
    });
    expect(live).toHaveLength(0);
    const revoked = await ctx.prisma.userSession.findMany({ where: { userId: user.id } });
    expect(revoked.every((s) => s.revokedReason === 'password_reset')).toBe(true);
  });

  it('the code is single use — a second confirm with it is refused', async () => {
    const user = await verifiedUser();
    const { code } = await requestCodeFor(user.email);
    expect(
      (await post('confirm', { email: user.email, code, newPassword: 'first new one' })).statusCode,
    ).toBe(200);

    const again = await post('confirm', { email: user.email, code, newPassword: 'second new one' });
    expect(again.statusCode).toBe(422);
    expect(again.json<Err>().error.code).toBe('OTP_EXPIRED');
  });

  it('verify does not spend the code — the same one still confirms', async () => {
    const user = await verifiedUser();
    const { code } = await requestCodeFor(user.email);
    expect((await post('verify', { email: user.email, code })).statusCode).toBe(200);
    expect((await post('verify', { email: user.email, code })).statusCode).toBe(200);
    expect(
      (await post('confirm', { email: user.email, code, newPassword: 'still works fine' }))
        .statusCode,
    ).toBe(200);
  });

  it('a code expires after 30 minutes, not the OTP clock of 10', async () => {
    const user = await verifiedUser();
    const { body, code } = await requestCodeFor(user.email);
    expect(new Date(body.expiresAt).getTime() - time.clock().getTime()).toBe(30 * 60_000);

    time.advance(29 * 60_000);
    expect((await post('verify', { email: user.email, code })).statusCode).toBe(200);
    time.advance(2 * 60_000);
    const late = await post('verify', { email: user.email, code });
    expect(late.statusCode).toBe(422);
    expect(late.json<Err>().error.code).toBe('OTP_EXPIRED');
  });

  it('five wrong codes invalidate the live one, and the right code no longer works', async () => {
    const user = await verifiedUser();
    const { code } = await requestCodeFor(user.email);
    const wrong = code === '000000' ? '111111' : '000000';

    for (let attempt = 1; attempt <= 4; attempt += 1) {
      const res = await post('verify', { email: user.email, code: wrong });
      expect(res.json<Err>().error.code).toBe('OTP_INCORRECT');
      expect(res.json<Err>().error.details?.attemptsRemaining).toBe(5 - attempt);
    }
    const fifth = await post('verify', { email: user.email, code: wrong });
    expect(fifth.json<Err>().error.code).toBe('OTP_INVALIDATED');

    const rightCodeNow = await post('confirm', {
      email: user.email,
      code,
      newPassword: 'should not get in',
    });
    expect(rightCodeNow.json<Err>().error.code).toBe('OTP_EXPIRED');
  });

  it('an unregistered address gets the same body and no mail — closes ledger row P3', async () => {
    const user = await verifiedUser();
    const real = await post('request', { email: user.email });
    const unknown = freshEmail();
    const nobody = await post('request', { email: unknown });

    expectIndistinguishable(nobody, real);
    expect(mail.latestCodeFor(unknown)).toBeNull();
  });

  it('a rate-limited address gets that same body, never the 429 that would out it', async () => {
    const user = await verifiedUser();
    // Only a real account can accumulate the rows the send limits count, so a
    // 429 escaping here would be an existence oracle on its own. Fill the
    // per-address limit, then ask once more and measure the refusal against an
    // address that has no account at all.
    for (let i = 0; i < OTP_ADDRESS_LIMIT; i++) {
      const filling = await post('request', { email: user.email });
      expect(filling.statusCode).toBe(200);
    }
    expect(mailCountFor(user.email)).toBe(OTP_ADDRESS_LIMIT);

    const overLimit = await post('request', { email: user.email });
    const nobody = await post('request', { email: freshEmail() });

    expect(overLimit.statusCode).toBe(200);
    expectIndistinguishable(overLimit, nobody);
    // And the swallowed request really did send nothing — the limit throws
    // inside the transaction, before the row and the mail.
    expect(mailCountFor(user.email)).toBe(OTP_ADDRESS_LIMIT);
    expect(
      await ctx.prisma.emailOtp.count({ where: { userId: user.id, purpose: 'password_reset' } }),
    ).toBe(OTP_ADDRESS_LIMIT);
  });

  it('an unverified address gets the same body and no mail', async () => {
    const unverified = await createUser(ctx.prisma, { emailVerified: false });
    const res = await post('request', { email: unverified.email });
    expect(res.statusCode).toBe(200);
    expect(mail.latestCodeFor(unverified.email)).toBeNull();
    expect(
      await ctx.prisma.emailOtp.count({
        where: { userId: unverified.id, purpose: 'password_reset' },
      }),
    ).toBe(0);
  });

  it('a frozen account cannot be reset back into use', async () => {
    const user = await verifiedUser();
    await ctx.prisma.user.update({ where: { id: user.id }, data: { status: 'frozen' } });
    const res = await post('request', { email: user.email });
    expect(res.statusCode).toBe(200);
    expect(mail.latestCodeFor(user.email)).toBeNull();
  });

  it('an unknown address fails verify and confirm exactly as a stale code does', async () => {
    const user = await verifiedUser();
    const stale = await post('verify', { email: user.email, code: '123456' });
    const unknown = await post('verify', { email: freshEmail(), code: '123456' });
    expect(unknown.statusCode).toBe(stale.statusCode);
    expect(unknown.json<Err>().error.code).toBe(stale.json<Err>().error.code);
    expect(unknown.json<Err>().error.code).toBe('OTP_EXPIRED');
  });

  it('the reset email says what the code does and never carries a link', async () => {
    const user = await verifiedUser();
    await requestCodeFor(user.email);
    const message = [...mail.sent].reverse().find((m) => m.to === user.email);
    expect(message?.subject).toBe('Your RaajjePro password reset code');
    expect(message?.text).toContain('password reset code');
    expect(message?.text).toContain('30 minutes');
    expect(message?.text).not.toMatch(/https?:\/\//);
  });

  it('the confirm is audited without the address ever reaching the log', async () => {
    const user = await verifiedUser();
    const { code } = await requestCodeFor(user.email);
    await post('confirm', { email: user.email, code, newPassword: 'audited change here' });

    const entry = await ctx.prisma.auditLogEntry.findFirst({
      where: { action: 'user.password.reset', targetId: user.id },
      orderBy: { createdAt: 'desc' },
    });
    expect(entry).not.toBeNull();
    expect(entry?.actorType).toBe('user');
    expect(entry?.reason).toBe('forgot_password');
    expect(JSON.stringify(entry)).not.toContain(user.email);
  });

  it('validation: a short new password is refused before anything is spent', async () => {
    const user = await verifiedUser();
    const { code } = await requestCodeFor(user.email);
    const res = await post('confirm', { email: user.email, code, newPassword: 'short' });
    expect(res.statusCode).toBe(400);
    expect(res.json<Err>().error.code).toBe('VALIDATION_FAILED');
    // Still spendable: the rejection happened at the schema, before the code.
    expect(
      (await post('confirm', { email: user.email, code, newPassword: 'long enough now' }))
        .statusCode,
    ).toBe(200);
  });

  it('no response in the flow carries a phone number', async () => {
    const user = await verifiedUser();
    const phone = await ctx.prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    const { code } = await requestCodeFor(user.email);
    const bodies = [
      (await post('verify', { email: user.email, code })).body,
      (await post('confirm', { email: user.email, code, newPassword: 'no phone in here' })).body,
    ];
    for (const body of bodies) {
      expect(body).not.toContain(phone.phoneE164 ?? 'unreachable');
    }
  });
});
