import { errors, jwtVerify, SignJWT } from 'jose';

import { hashToken, newSessionToken } from '../admin-auth/crypto.js';

export const ACCESS_TOKEN_ISSUER = 'raajjepro';
export const ACCESS_TOKEN_AUDIENCE = 'raajjepro-app';

export interface AccessTokenClaims {
  userId: string;
  sessionId: string;
}

export type VerifiedAccessToken =
  ({ ok: true } & AccessTokenClaims) | { ok: false; reason: 'expired' | 'invalid' };

/**
 * User access tokens (plan §2: JWT access + refresh rotation). HS256 under
 * AUTH_JWT_SECRET; `sub` is the user id and `sid` the session id, so the
 * auth plugin can load the session row and honour a revocation immediately
 * rather than at expiry. Nothing mutable (email, verified flag, status) is
 * carried in the token — it is read from the row on every request.
 */
export async function signAccessToken(input: {
  userId: string;
  sessionId: string;
  now: Date;
  ttlMinutes: number;
  secret: Buffer;
}): Promise<{ token: string; expiresAt: Date }> {
  const issuedAt = Math.floor(input.now.getTime() / 1000);
  const expiresAt = new Date(input.now.getTime() + input.ttlMinutes * 60_000);
  const token = await new SignJWT({ sid: input.sessionId })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(input.userId)
    .setIssuer(ACCESS_TOKEN_ISSUER)
    .setAudience(ACCESS_TOKEN_AUDIENCE)
    .setIssuedAt(issuedAt)
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(input.secret);
  return { token, expiresAt };
}

export async function verifyAccessToken(
  token: string,
  secret: Buffer,
  now: Date,
): Promise<VerifiedAccessToken> {
  if (token.length === 0) return { ok: false, reason: 'invalid' };
  try {
    const { payload } = await jwtVerify(token, secret, {
      algorithms: ['HS256'],
      issuer: ACCESS_TOKEN_ISSUER,
      audience: ACCESS_TOKEN_AUDIENCE,
      currentDate: now,
    });
    if (typeof payload.sub !== 'string' || typeof payload.sid !== 'string') {
      return { ok: false, reason: 'invalid' };
    }
    return { ok: true, userId: payload.sub, sessionId: payload.sid };
  } catch (error) {
    if (error instanceof errors.JWTExpired) return { ok: false, reason: 'expired' };
    return { ok: false, reason: 'invalid' };
  }
}

/** 32 random bytes, base64url — the same generator the admin session cookie uses. */
export const newRefreshToken = newSessionToken;
export { hashToken };
