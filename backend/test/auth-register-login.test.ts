import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  bearer,
  freshEmail,
  freshPhone,
  RecordingEmailTransport,
  registerUser,
  USER_PASSWORD,
} from './helpers/users.js';

interface Err {
  error: { code: string; details?: { path: string; message: string }[] };
}

describe.skipIf(databaseUrl === undefined)('register and login', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const post = (
    payload: Record<string, unknown>,
    headers: Record<string, string> = { 'idempotency-key': randomUUID() },
  ) =>
    ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      remoteAddress: freshIp(),
      headers,
      payload,
    });

  const validBody = (over: Record<string, unknown> = {}) => ({
    role: 'customer',
    fullName: 'Aishath Naeema',
    email: freshEmail(),
    phone: { dialCode: '+960', number: freshPhone() },
    password: USER_PASSWORD,
    acceptTerms: true,
    ...over,
  });

  it('registers a customer: 201, signed in, unverified, OTP sent, terms recorded, audited', async () => {
    const email = freshEmail();
    const res = await post(validBody({ email: ` ${email.toUpperCase()} ` }));
    expect(res.statusCode).toBe(201);
    const data = res.json<{
      data: {
        user: Record<string, unknown>;
        tokens: Record<string, string>;
        verification: { status: string };
      };
    }>().data;
    expect(data.user.email).toBe(email.toLowerCase());
    expect(data.user.emailVerified).toBe(false);
    expect(data.user.isProvider).toBe(false);
    expect(data.verification.status).toBe('sent');
    expect(mail.latestCodeFor(email)).toMatch(/^\d{6}$/);
    expect(res.body).not.toContain('passwordHash');
    const me = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: bearer(data.tokens.accessToken ?? ''),
    });
    expect(me.statusCode).toBe(200);
    const row = await ctx.prisma.user.findUniqueOrThrow({ where: { email: email.toLowerCase() } });
    expect(row.termsAcceptedAt).toBeTruthy();
    expect(row.phoneE164?.startsWith('+960')).toBe(true);
    const audit = await ctx.prisma.auditLogEntry.findFirst({
      where: { action: 'user.registered', actorId: row.id },
    });
    expect(audit?.actorType).toBe('user');
    expect(JSON.stringify(audit?.metadata)).not.toContain(email.toLowerCase());
  });

  it('registers a provider with a business name and creates the minimal ProviderProfile at tier none', async () => {
    const res = await post(
      validBody({ role: 'provider', businessName: 'Rasheed Plumbing Services' }),
    );
    expect(res.statusCode).toBe(201);
    const data = res.json<{ data: { user: { id: string; isProvider: boolean } } }>().data;
    expect(data.user.isProvider).toBe(true);
    const profile = await ctx.prisma.providerProfile.findUniqueOrThrow({
      where: { userId: data.user.id },
    });
    expect(profile.businessName).toBe('Rasheed Plumbing Services');
    expect(profile.verificationTier).toBe('none');
    expect(profile.verificationStatus).toBe('unverified');
    // getOrCreateProviderProfile is idempotent (§1a).
    const again = await ctx.app.auth.repo.getOrCreateProviderProfile(ctx.prisma, data.user.id);
    expect(again.id).toBe(profile.id);
  });

  it('validates the body: provider without a business name, customer with one, unaccepted terms, short password', async () => {
    for (const [body, path] of [
      [validBody({ role: 'provider' }), 'businessName'],
      [validBody({ businessName: 'Nope' }), 'businessName'],
      [validBody({ acceptTerms: false }), 'acceptTerms'],
      [validBody({ password: 'short' }), 'password'],
      [validBody({ phone: { dialCode: '+960', number: '123' } }), 'phone'],
    ] as const) {
      const res = await post(body);
      expect(res.statusCode, path).toBe(400);
      expect(
        res.json<Err>().error.details?.some((d) => d.path.startsWith(path)),
        path,
      ).toBe(true);
    }
  });

  it('a duplicate email is blocked at the field, naming it, whatever the case', async () => {
    const first = await registerUser(ctx.app);
    const res = await post(validBody({ email: first.email.toUpperCase() }));
    expect(res.statusCode).toBe(409);
    const err = res.json<Err>().error;
    expect(err.code).toBe('EMAIL_IN_USE');
    expect(err.details?.[0]?.path).toBe('email');
    expect(res.body).not.toContain(first.phone);
  });

  it('a duplicate phone is blocked only when held at Bronze or above, and formatting variants collide', async () => {
    const shared = freshPhone();
    const holder = await registerUser(ctx.app, { role: 'provider', phone: shared });
    // Held at tier none: another account may claim it silently.
    expect(
      (await post(validBody({ phone: { dialCode: '+960', number: shared } }))).statusCode,
    ).toBe(201);
    await ctx.prisma.providerProfile.update({
      where: { userId: holder.userId },
      data: { verificationTier: 'bronze' },
    });
    const blocked = await post(
      validBody({
        phone: { dialCode: '+960', number: `${shared.slice(0, 3)}-${shared.slice(3)}` },
      }),
    );
    expect(blocked.statusCode).toBe(409);
    expect(blocked.json<Err>().error.code).toBe('PHONE_IN_USE');
    expect(blocked.json<Err>().error.details?.[0]?.path).toBe('phone');
    // A different dial code is a different number.
    expect((await post(validBody({ phone: { dialCode: '+44', number: shared } }))).statusCode).toBe(
      201,
    );
  });

  it('a pre-burned OTP address window never blocks registration itself: 201 with tokens, verification reported honestly as failed', async () => {
    // Burn the target address's send-limit window (3 per 15 min) from an
    // unrelated account before anyone registers it — e.g. someone typo'd it
    // into a change-email request three times. Registration must still
    // create the account and open a session; only the OTP send is refused.
    const target = freshEmail();
    const burner = await registerUser(ctx.app);
    for (let i = 0; i < 3; i += 1) {
      const burn = await ctx.app.inject({
        method: 'POST',
        url: '/v1/users/me/change-email/request',
        headers: burner.headers,
        payload: { newEmail: target, currentPassword: burner.password },
      });
      expect(burn.statusCode).toBe(200);
    }
    const res = await post(validBody({ email: target }));
    expect(res.statusCode).toBe(201);
    const data = res.json<{
      data: {
        tokens: { accessToken: string; refreshToken: string };
        verification: { status: string };
      };
    }>().data;
    expect(data.verification.status).toBe('failed');
    expect(data.tokens.accessToken).toBeTruthy();
    expect(data.tokens.refreshToken).toBeTruthy();
    expect(
      await ctx.prisma.user.findUnique({ where: { email: target.toLowerCase() } }),
    ).not.toBeNull();
    // The freshly minted session works even though no code went out.
    const me = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: bearer(data.tokens.accessToken),
    });
    expect(me.statusCode).toBe(200);
  });

  it('registration needs an Idempotency-Key and replays the original result on a retry', async () => {
    const body = validBody();
    const none = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      remoteAddress: freshIp(),
      payload: body,
    });
    expect(none.statusCode).toBe(400);
    expect(none.json<Err>().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');
    const key = randomUUID();
    const ip = freshIp();
    const a = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      remoteAddress: ip,
      headers: { 'idempotency-key': key },
      payload: body,
    });
    const b = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      remoteAddress: ip,
      headers: { 'idempotency-key': key },
      payload: body,
    });
    expect(a.statusCode).toBe(201);
    expect(b.statusCode).toBe(201);
    expect(b.headers['idempotent-replayed']).toBe('true');
    expect(b.body).toBe(a.body);
    expect(await ctx.prisma.user.count({ where: { email: body.email.toLowerCase() } })).toBe(1);
  });

  it('login: right password → tokens; wrong password, unknown email and a frozen-then-anonymised account all read INVALID_CREDENTIALS', async () => {
    const u = await registerUser(ctx.app);
    const login = (email: string, password: string) =>
      ctx.app.inject({
        method: 'POST',
        url: '/v1/auth/login',
        remoteAddress: freshIp(),
        payload: { email, password, deviceName: 'Pixel 7' },
      });
    const ok = await login(u.email, u.password);
    expect(ok.statusCode).toBe(200);
    expect(
      ok.json<{ data: { tokens: { accessToken: string } } }>().data.tokens.accessToken,
    ).toBeTruthy();
    const wrong = await login(u.email, 'not the password');
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    const unknown = await login(freshEmail(), u.password);
    expect(unknown.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    const failed = await ctx.prisma.auditLogEntry.findFirst({
      where: { action: 'user.login.failed', targetId: u.userId },
    });
    expect(failed?.reason).toBe('wrong_password');
    // The email resolved to a real user, so the row is attributed to them —
    // not to `system`, which is reserved for the unknown-email case (no row
    // at all, per the same rule admin login follows).
    expect(failed?.actorType).toBe('user');
    expect(failed?.actorId).toBe(u.userId);
    // Only the wrong-password attempt wrote a row — the unknown-email attempt
    // (which has no user to target) never reaches the audit call at all.
    expect(
      await ctx.prisma.auditLogEntry.count({
        where: { action: 'user.login.failed', targetId: u.userId },
      }),
    ).toBe(1);
    await ctx.prisma.user.update({ where: { id: u.userId }, data: { status: 'anonymised' } });
    expect((await login(u.email, u.password)).json<Err>().error.code).toBe('INVALID_CREDENTIALS');
  });

  it('a frozen account still signs in and its DTO says so', async () => {
    const u = await registerUser(ctx.app);
    await ctx.prisma.user.update({
      where: { id: u.userId },
      data: { status: 'frozen', deletionDeadlineAt: new Date('2026-10-06T10:00:00Z') },
    });
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      remoteAddress: freshIp(),
      payload: { email: u.email, password: u.password },
    });
    expect(res.statusCode).toBe(200);
    expect(
      res.json<{ data: { user: { status: string; deletionDeadlineAt: string } } }>().data.user
        .status,
    ).toBe('frozen');
  });

  it('login is tiered 10 per 15 minutes per IP', async () => {
    const ip = freshIp();
    const u = await registerUser(ctx.app);
    for (let i = 0; i < 10; i += 1) {
      await ctx.app.inject({
        method: 'POST',
        url: '/v1/auth/login',
        remoteAddress: ip,
        payload: { email: u.email, password: 'wrong wrong wrong' },
      });
    }
    const eleventh = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      remoteAddress: ip,
      payload: { email: u.email, password: u.password },
    });
    expect(eleventh.statusCode).toBe(429);
  });

  it('social sign-in exists as a contract and every provider is a stub', async () => {
    for (const provider of ['apple', 'google', 'facebook', 'viber']) {
      const res = await ctx.app.inject({
        method: 'POST',
        url: `/v1/auth/social/${provider}`,
        remoteAddress: freshIp(),
        payload: { idToken: 'x'.repeat(40) },
      });
      expect(res.statusCode, provider).toBe(422);
      expect(res.json<Err>().error.code).toBe('SOCIAL_AUTH_UNAVAILABLE');
    }
    // An unregistered provider name is a lookup miss, not a validation
    // failure — the contract is fixed even for a name nobody has heard of.
    const unknown = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/social/myspace',
      remoteAddress: freshIp(),
      payload: { idToken: 'x'.repeat(40) },
    });
    expect(unknown.statusCode).toBe(404);
    expect(unknown.json<Err>().error.code).toBe('NOT_FOUND');
  });
});
