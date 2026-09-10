import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * The signature behind a "presigned" URL on the local transport.
 *
 * With a real object store the store signs the URL and enforces the terms.
 * With a local directory there is no store to do that, so this file is what
 * a presigned URL *is* here: a token binding the object key, the permitted
 * operation, the declared content type and the size ceiling to an expiry,
 * signed with a server secret. The receiving route trusts the token and
 * nothing else about the request.
 *
 * The token is the authorization, which is exactly the property a presigned
 * URL has and exactly why the upload route below it carries no session guard
 * — the same as an S3 presigned PUT, which no AWS credential accompanies.
 */

export type MediaTokenOperation = 'put' | 'get';

export interface MediaTokenClaims {
  op: MediaTokenOperation;
  /** The object this token addresses, and the only one it addresses. */
  key: string;
  /** Milliseconds since the epoch. */
  exp: number;
  /** Upload only: the type the store will accept. */
  ct?: string;
  /** Upload only: the ceiling the store enforces on the body. */
  max?: number;
}

export class MediaTokenError extends Error {
  constructor(
    message: string,
    readonly reason: 'malformed' | 'bad_signature' | 'expired',
  ) {
    super(message);
    this.name = 'MediaTokenError';
  }
}

/**
 * `<base64url(json claims)>.<base64url(hmac)>`.
 *
 * The claims travel in the token rather than in a server-side table because
 * that is what makes it presigned: the receiving route needs no lookup, so
 * the store can be swapped for one that never talks to this database.
 */
export function signMediaToken(secret: Buffer, claims: MediaTokenClaims): string {
  const payload = Buffer.from(JSON.stringify(claims), 'utf8').toString('base64url');
  return `${payload}.${hmac(secret, payload)}`;
}

/**
 * Verifies and decodes. Throws `MediaTokenError` — never returns a partly
 * trusted result, and never tells the caller *what* the claims were on a bad
 * signature.
 *
 * The signature is compared with `timingSafeEqual`. It matters here for the
 * same reason it matters on a session token: the token is the only
 * authorization the upload route has, and a comparison that returns early
 * leaks how much of a forged signature was right.
 */
export function verifyMediaToken(secret: Buffer, token: string, now: Date): MediaTokenClaims {
  const dot = token.indexOf('.');
  if (dot <= 0 || dot === token.length - 1) {
    throw new MediaTokenError('Malformed upload token', 'malformed');
  }
  const payload = token.slice(0, dot);
  const provided = Buffer.from(token.slice(dot + 1), 'utf8');
  const expected = Buffer.from(hmac(secret, payload), 'utf8');
  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    throw new MediaTokenError('Upload token signature does not match', 'bad_signature');
  }

  let claims: MediaTokenClaims;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as MediaTokenClaims;
  } catch {
    throw new MediaTokenError('Malformed upload token', 'malformed');
  }
  if (typeof claims.key !== 'string' || typeof claims.exp !== 'number') {
    throw new MediaTokenError('Malformed upload token', 'malformed');
  }
  if (claims.exp <= now.getTime()) {
    throw new MediaTokenError('This upload link has expired', 'expired');
  }
  return claims;
}

function hmac(secret: Buffer, payload: string): string {
  return createHmac('sha256', secret).update(payload).digest('base64url');
}
