import { describe, expect, it } from 'vitest';

import { newRefreshToken, signAccessToken, verifyAccessToken } from '../src/modules/auth/tokens.js';

const secret = Buffer.alloc(32, 5);
const other = Buffer.alloc(32, 6);
const now = new Date('2026-09-06T10:00:00Z');

describe('access tokens', () => {
  it('signs and verifies a token carrying the user and session ids', async () => {
    const { token, expiresAt } = await signAccessToken({
      userId: '11111111-1111-4111-8111-111111111111',
      sessionId: '22222222-2222-4222-8222-222222222222',
      now,
      ttlMinutes: 15,
      secret,
    });
    expect(expiresAt.toISOString()).toBe('2026-09-06T10:15:00.000Z');
    const result = await verifyAccessToken(token, secret, now);
    expect(result).toEqual({
      ok: true,
      userId: '11111111-1111-4111-8111-111111111111',
      sessionId: '22222222-2222-4222-8222-222222222222',
    });
  });

  it('reports expiry as expired, not invalid, so the client knows to refresh', async () => {
    const { token } = await signAccessToken({
      userId: 'u',
      sessionId: 's',
      now,
      ttlMinutes: 15,
      secret,
    });
    const late = new Date(now.getTime() + 15 * 60_000 + 1_000);
    expect(await verifyAccessToken(token, secret, late)).toEqual({ ok: false, reason: 'expired' });
  });

  it('rejects a wrong key, a tampered payload and garbage as invalid', async () => {
    const { token } = await signAccessToken({
      userId: 'u',
      sessionId: 's',
      now,
      ttlMinutes: 15,
      secret,
    });
    expect(await verifyAccessToken(token, other, now)).toEqual({ ok: false, reason: 'invalid' });
    const [h, p, s] = token.split('.');
    const tampered = `${h ?? ''}.${Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(p ?? '', 'base64url').toString()), sid: 'x' })).toString('base64url')}.${s ?? ''}`;
    expect(await verifyAccessToken(tampered, secret, now)).toEqual({
      ok: false,
      reason: 'invalid',
    });
    expect(await verifyAccessToken('not.a.jwt', secret, now)).toEqual({
      ok: false,
      reason: 'invalid',
    });
    expect(await verifyAccessToken('', secret, now)).toEqual({ ok: false, reason: 'invalid' });
  });

  it('rejects a token with the wrong audience or issuer', async () => {
    const { SignJWT } = await import('jose');
    const foreign = await new SignJWT({ sid: 's' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('u')
      .setIssuer('someone-else')
      .setAudience('raajjepro-app')
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(Math.floor(now.getTime() / 1000) + 900)
      .sign(secret);
    expect(await verifyAccessToken(foreign, secret, now)).toEqual({ ok: false, reason: 'invalid' });
  });

  it('refresh tokens are 32 random bytes, base64url, and never repeat', () => {
    const a = newRefreshToken();
    const b = newRefreshToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a).not.toBe(b);
  });
});
