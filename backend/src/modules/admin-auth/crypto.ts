import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

import { hash, hashSync, verify } from '@node-rs/argon2';

export const MIN_PASSWORD_LENGTH = 12;
export const MAX_PASSWORD_LENGTH = 512;

export function hashPassword(password: string): Promise<string> {
  return hash(password); // argon2id, library defaults
}

export function verifyPassword(passwordHash: string, password: string): Promise<boolean> {
  return verify(passwordHash, password).catch(() => false);
}

/** Verified against when the email is unknown, so timing does not reveal whether an account exists. */
export const DUMMY_PASSWORD_HASH = hashSync(randomBytes(32).toString('hex'));

export function newSessionToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** AES-256-GCM; output is base64url(iv ‖ tag ‖ ciphertext). */
export function encryptSecret(plain: string, key: Buffer): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]).toString('base64url');
}

export function decryptSecret(encoded: string, key: Buffer): string {
  const raw = Buffer.from(encoded, 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', key, raw.subarray(0, 12));
  decipher.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString('utf8');
}

const RECOVERY_ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789'; // no 0/o/1/l/i

export function newRecoveryCodes(count = 10): string[] {
  const codes = new Set<string>();
  while (codes.size < count) {
    const bytes = randomBytes(10);
    let s = '';
    for (const b of bytes) s += RECOVERY_ALPHABET.charAt(b % RECOVERY_ALPHABET.length);
    codes.add(`${s.slice(0, 5)}-${s.slice(5)}`);
  }
  return [...codes];
}

export function normaliseRecoveryCode(input: string): string {
  return input.trim().toLowerCase();
}
