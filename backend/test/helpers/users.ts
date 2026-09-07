import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';

import { hashPassword } from '../../src/modules/admin-auth/crypto.js';
import type { EmailTransport, OutboundEmail } from '../../src/modules/email/types.js';
import type { PrismaClient, User } from '../../src/generated/prisma/client.js';
import { freshIp } from './app.js';

export const USER_PASSWORD = 'correct horse battery';

/** Keeps every delivered email in memory so a test can read the OTP out of it without touching the disk. */
export class RecordingEmailTransport implements EmailTransport {
  readonly sent: OutboundEmail[] = [];
  deliver(email: OutboundEmail): Promise<{ providerMessageId: string }> {
    this.sent.push(email);
    return Promise.resolve({ providerMessageId: `rec-${randomUUID()}` });
  }
  /** The six-digit code in the most recent message to `to`, or null. */
  latestCodeFor(to: string): string | null {
    const match = [...this.sent].reverse().find((e) => e.to === to.toLowerCase());
    return match?.text.match(/\b(\d{6})\b/)?.[1] ?? null;
  }
}

export function freshEmail(): string {
  return `user-${randomUUID()}@example.test`;
}

export function freshPhone(): string {
  return String(Math.floor(Math.random() * 9_000_000) + 1_000_000);
}

/** Inserts a user straight into the database — for tests of everything downstream of registration. */
export async function createUser(
  prisma: PrismaClient,
  overrides: Partial<{
    email: string;
    emailVerified: boolean;
    phone: string | null;
    password: string;
  }> = {},
): Promise<User & { password: string }> {
  const password = overrides.password ?? USER_PASSWORD;
  const phone = overrides.phone === undefined ? freshPhone() : overrides.phone;
  const user = await prisma.user.create({
    data: {
      email: (overrides.email ?? freshEmail()).toLowerCase(),
      emailVerifiedAt: overrides.emailVerified === true ? new Date() : null,
      passwordHash: await hashPassword(password),
      fullName: 'Test User',
      phoneE164: phone === null ? null : `+960${phone}`,
      phoneDialCode: phone === null ? null : '+960',
      termsAcceptedAt: new Date(),
    },
  });
  return { ...user, password };
}

export function bearer(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}

export interface RegisteredUser {
  userId: string;
  email: string;
  phone: string;
  password: string;
  tokens: { accessToken: string; refreshToken: string };
  headers: { authorization: string };
}

/** Registers through the real route, exactly as the app does. */
export async function registerUser(
  app: FastifyInstance,
  overrides: Partial<{
    role: 'customer' | 'provider';
    email: string;
    phone: string;
    dialCode: string;
    businessName: string;
    password: string;
  }> = {},
): Promise<RegisteredUser> {
  const email = overrides.email ?? freshEmail();
  const phone = overrides.phone ?? freshPhone();
  const password = overrides.password ?? USER_PASSWORD;
  const role = overrides.role ?? 'customer';
  const res = await app.inject({
    method: 'POST',
    url: '/v1/auth/register',
    remoteAddress: freshIp(),
    headers: { 'idempotency-key': randomUUID() },
    payload: {
      role,
      fullName: 'Aishath Test',
      email,
      phone: { dialCode: overrides.dialCode ?? '+960', number: phone },
      password,
      ...(role === 'provider' ? { businessName: overrides.businessName ?? 'Test Trade' } : {}),
      acceptTerms: true,
      deviceName: 'vitest',
    },
  });
  if (res.statusCode !== 201) {
    throw new Error(`register failed: ${String(res.statusCode)} ${res.body}`);
  }
  const body = res.json<{
    data: { user: { id: string }; tokens: { accessToken: string; refreshToken: string } };
  }>().data;
  return {
    userId: body.user.id,
    email,
    phone,
    password,
    tokens: body.tokens,
    headers: bearer(body.tokens.accessToken),
  };
}
