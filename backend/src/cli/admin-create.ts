/**
 * `npm run admin:create -- --email admin@example.com`
 *
 * How an admin account comes to exist (decision 2026-09-05: a server-side
 * CLI, no in-panel "add admin", no bootstrap endpoint). The password is read
 * from the terminal without echo. TOTP enrolment happens at the admin's first
 * login; nothing about MFA is printed or accepted here.
 */
import { parseArgs } from 'node:util';

import { loadConfig } from '../config/env.js';
import { systemClock } from '../core/clock.js';
import { createPrismaClient } from '../db/client.js';
import { AdminAuthService } from '../modules/admin-auth/service.js';
import { AuditService } from '../modules/audit/service.js';

function promptHidden(question: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const { stdin, stdout } = process;
    if (!stdin.isTTY) {
      reject(new Error('admin:create needs an interactive terminal to read the password'));
      return;
    }
    stdout.write(question);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    let value = '';
    const onData = (chunk: string) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n') {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.off('data', onData);
          stdout.write('\n');
          resolve(value);
          return;
        }
        if (ch === '\x03') {
          stdin.setRawMode(false);
          process.exit(130);
        }
        if (ch === '\x7f' || ch === '\b') {
          value = value.slice(0, -1);
        } else {
          value += ch;
        }
      }
    };
    stdin.on('data', onData);
  });
}

const { values } = parseArgs({ options: { email: { type: 'string' } } });
if (values.email === undefined) {
  console.error('usage: npm run admin:create -- --email <address>');
  process.exit(2);
}

const config = loadConfig(process.env);
const prisma = createPrismaClient(config.databaseUrl);
try {
  const password = await promptHidden('Password (min 12 characters): ');
  const confirm = await promptHidden('Repeat password: ');
  if (password !== confirm) {
    console.error('Passwords do not match.');
    process.exitCode = 1;
  } else {
    const audit = new AuditService(prisma, systemClock);
    const service = new AdminAuthService({ prisma, audit, clock: systemClock, config });
    const admin = await service.createAdmin(values.email, password, {});
    console.log(`Created admin ${admin.id}. They enrol an authenticator app at first login.`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
