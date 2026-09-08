import { randomUUID } from 'node:crypto';
import { mkdtemp, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Writable } from 'node:stream';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildApp } from '../src/app.js';
import { createPrismaClient } from '../src/db/client.js';
import { requireEmailVerified } from '../src/modules/auth/guards.js';
import { FileEmailTransport } from '../src/modules/email/transports/file.js';
import {
  controllableClock,
  databaseUrl,
  freshIp,
  RecordingPushTransport,
  testConfig,
  TrustingValidator,
} from './helpers/app.js';
import { bearer, freshEmail, freshPhone, USER_PASSWORD } from './helpers/users.js';

interface Err {
  error: { code: string };
}

/** Reads the six-digit code out of the JSON the file transport wrote — exactly as a person reads it out of a mailbox. */
async function codeFromMailDir(dir: string, to: string): Promise<string> {
  const files = (await readdir(dir)).sort();
  for (const file of files.reverse()) {
    const message = JSON.parse(await readFile(join(dir, file), 'utf8')) as {
      to: string;
      text: string;
    };
    if (message.to === to.toLowerCase()) {
      const code = /\b(\d{6})\b/.exec(message.text)?.[1];
      if (code !== undefined) return code;
    }
  }
  throw new Error(`no code written for ${to}`);
}

describe.skipIf(databaseUrl === undefined)(
  '§Phase 3 Done-when — the full cycle against the file transport',
  () => {
    const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
    const lines: string[] = [];
    let mailDir: string;
    let app: Awaited<ReturnType<typeof buildApp>>;
    let prisma: ReturnType<typeof createPrismaClient>;

    beforeAll(async () => {
      mailDir = await mkdtemp(join(tmpdir(), 'raajjepro-phase3-mail-'));
      const config = { ...testConfig({ clock: time.clock }), logLevel: 'info' as const };
      prisma = createPrismaClient(config.databaseUrl);
      // Capture every log line so the no-PII rule can be asserted over a real run.
      // See AppDeps.logStream in src/app.ts — a test seam, since there is no
      // supported way to attach a stream to an already-built Fastify logger.
      const stream = new Writable({
        write(chunk: Buffer, _e, cb) {
          lines.push(chunk.toString('utf8'));
          cb();
        },
      });
      app = await buildApp(config, {
        prisma,
        clock: time.clock,
        emailTransport: new FileEmailTransport(mailDir),
        pushTransport: new RecordingPushTransport(),
        snsValidator: new TrustingValidator(),
        logStream: stream,
      });
      app.get('/v1/_test/needs-verified', { preValidation: requireEmailVerified }, () => ({
        data: 'ok',
      }));
      await app.ready();
    });
    afterAll(async () => {
      await app.close();
      await prisma.$disconnect();
    });

    it('register → verify (code read from the written mail) → logout → login; unverified browses but is rejected by requireEmailVerified', async () => {
      const email = freshEmail();
      const phone = freshPhone();
      const register = await app.inject({
        method: 'POST',
        url: '/v1/auth/register',
        remoteAddress: freshIp(),
        headers: { 'idempotency-key': randomUUID() },
        payload: {
          role: 'customer',
          fullName: 'Aishath Naeema',
          email,
          phone: { dialCode: '+960', number: phone },
          password: USER_PASSWORD,
          acceptTerms: true,
          deviceName: 'Done-when phone',
        },
      });
      expect(register.statusCode).toBe(201);
      const first = register.json<{ data: { tokens: { accessToken: string } } }>().data.tokens;

      // Unverified: browses freely, is refused by the guard with its own code.
      expect(
        (
          await app.inject({
            method: 'GET',
            url: '/v1/auth/me',
            headers: bearer(first.accessToken),
          })
        ).statusCode,
      ).toBe(200);
      const refused = await app.inject({
        method: 'GET',
        url: '/v1/_test/needs-verified',
        headers: bearer(first.accessToken),
      });
      expect(refused.statusCode).toBe(422);
      expect(refused.json<Err>().error.code).toBe('EMAIL_NOT_VERIFIED');

      const code = await codeFromMailDir(mailDir, email);
      const confirm = await app.inject({
        method: 'POST',
        url: '/v1/auth/verify-email/confirm',
        headers: bearer(first.accessToken),
        payload: { code },
      });
      expect(confirm.statusCode).toBe(200);
      expect(
        (
          await app.inject({
            method: 'GET',
            url: '/v1/_test/needs-verified',
            headers: bearer(first.accessToken),
          })
        ).statusCode,
      ).toBe(200);

      expect(
        (
          await app.inject({
            method: 'POST',
            url: '/v1/auth/logout',
            headers: bearer(first.accessToken),
          })
        ).statusCode,
      ).toBe(200);
      expect(
        (
          await app.inject({
            method: 'GET',
            url: '/v1/auth/me',
            headers: bearer(first.accessToken),
          })
        ).json<Err>().error.code,
      ).toBe('SESSION_EXPIRED');

      const login = await app.inject({
        method: 'POST',
        url: '/v1/auth/login',
        remoteAddress: freshIp(),
        payload: { email, password: USER_PASSWORD, deviceName: 'Done-when phone' },
      });
      expect(login.statusCode).toBe(200);
      const second = login.json<{
        data: { tokens: { accessToken: string }; user: { emailVerified: boolean } };
      }>().data;
      expect(second.user.emailVerified).toBe(true);
      expect(
        (
          await app.inject({
            method: 'GET',
            url: '/v1/auth/me',
            headers: bearer(second.tokens.accessToken),
          })
        ).statusCode,
      ).toBe(200);

      // No response to anyone but the holder carries the phone: the sessions list and every error body above are phone-free.
      const sessions = await app.inject({
        method: 'GET',
        url: '/v1/auth/sessions',
        headers: bearer(second.tokens.accessToken),
      });
      expect(sessions.body).not.toContain(phone);
      expect(refused.body).not.toContain(phone);

      // No log line from the whole run carries the email, phone, password or code.
      const output = lines.join('\n');
      expect(output).not.toContain(email.toLowerCase());
      expect(output).not.toContain(phone);
      expect(output).not.toContain(USER_PASSWORD);
      expect(output).not.toContain(code);
    });
  },
);
