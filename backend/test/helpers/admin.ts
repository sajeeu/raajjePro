import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';
import { generate } from 'otplib';

import { freshIp } from './app.js';

export const CSRF = { 'x-requested-with': 'RaajjePro-Admin' };
export const PASSWORD = 'a long enough password';

export function cookieFrom(res: { headers: Record<string, unknown> }): string {
  const raw = res.headers['set-cookie'];
  const first: unknown = Array.isArray(raw) ? (raw as unknown[])[0] : raw;
  return String(first).split(';')[0] ?? '';
}

export function totpNow(secret: string): Promise<string> {
  return generate({ secret });
}

/** Creates an admin, logs in, enrols TOTP and verifies — the state every guarded route needs. */
export async function createEnrolledAdmin(app: FastifyInstance) {
  const email = `admin-${randomUUID()}@example.test`;
  const admin = await app.adminAuth.createAdmin(email, PASSWORD, {});
  const login = await app.inject({
    method: 'POST',
    url: '/v1/admin/auth/login',
    headers: CSRF,
    remoteAddress: freshIp(),
    payload: { email, password: PASSWORD },
  });
  const cookie = cookieFrom(login);
  const enrol = await app.inject({
    method: 'POST',
    url: '/v1/admin/auth/mfa/enrol',
    headers: { cookie, ...CSRF },
  });
  const { secret } = enrol.json<{ data: { secret: string; otpauthUri: string } }>().data;
  const confirm = await app.inject({
    method: 'POST',
    url: '/v1/admin/auth/mfa/enrol/confirm',
    headers: { cookie, ...CSRF },
    payload: { code: await totpNow(secret) },
  });
  const { recoveryCodes } = confirm.json<{ data: { recoveryCodes: string[] } }>().data;
  return { email, password: PASSWORD, adminId: admin.id, cookie, secret, recoveryCodes };
}

/** A fresh session for an already-enrolled admin, MFA-verified with the given secret. */
export async function loginAndVerify(app: FastifyInstance, email: string, secret: string) {
  const login = await app.inject({
    method: 'POST',
    url: '/v1/admin/auth/login',
    headers: CSRF,
    remoteAddress: freshIp(),
    payload: { email, password: PASSWORD },
  });
  const cookie = cookieFrom(login);
  const verify = await app.inject({
    method: 'POST',
    url: '/v1/admin/auth/mfa/verify',
    headers: { cookie, ...CSRF },
    payload: { code: await totpNow(secret) },
  });
  return { cookie, verifyStatus: verify.statusCode };
}
