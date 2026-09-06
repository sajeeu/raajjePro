import { describe, expect, it } from 'vitest';

import {
  decryptSecret,
  encryptSecret,
  hashPassword,
  hashToken,
  newRecoveryCodes,
  newSessionToken,
  verifyPassword,
} from '../src/modules/admin-auth/crypto.js';

describe('admin-auth crypto', () => {
  it('hashes with argon2id and verifies', async () => {
    const hash = await hashPassword('correct horse battery staple');
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(await verifyPassword(hash, 'correct horse battery staple')).toBe(true);
    expect(await verifyPassword(hash, 'wrong')).toBe(false);
  });

  it('session tokens are unique and their hash is what gets stored', () => {
    const a = newSessionToken();
    const b = newSessionToken();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(hashToken(a)).toMatch(/^[0-9a-f]{64}$/);
    expect(hashToken(a)).not.toContain(a);
  });

  it('encrypts a TOTP secret so the ciphertext differs each time and decrypts back', () => {
    const key = Buffer.alloc(32, 9);
    const c1 = encryptSecret('JBSWY3DPEHPK3PXP', key);
    const c2 = encryptSecret('JBSWY3DPEHPK3PXP', key);
    expect(c1).not.toBe(c2);
    expect(c1).not.toContain('JBSWY3DPEHPK3PXP');
    expect(decryptSecret(c1, key)).toBe('JBSWY3DPEHPK3PXP');
    expect(() => decryptSecret(c1, Buffer.alloc(32, 8))).toThrow();
  });

  it('issues ten distinct recovery codes in xxxxx-xxxxx form', () => {
    const codes = newRecoveryCodes();
    expect(codes).toHaveLength(10);
    expect(new Set(codes).size).toBe(10);
    for (const code of codes) expect(code).toMatch(/^[a-z0-9]{5}-[a-z0-9]{5}$/);
  });
});
