import { ValidationError } from '../../core/errors.js';

const DIAL_CODE = /^\+[1-9]\d{0,3}$/;
const E164_MAX_DIGITS = 15;
const NATIONAL_MIN = 6;
const NATIONAL_MAX = 15;

/**
 * Phone numbers (plan §Phase 3): stored E.164 with a country code, `+960`
 * the default the client supplies, 6–15 national digits. No Maldivian 7/9
 * prefix rule — resort guests and expatriate residents hold foreign numbers
 * and rejecting them is a silently lost signup. Nothing here verifies the
 * number; nothing anywhere does.
 */
export function normalisePhone(input: { dialCode: string; number: string }): {
  e164: string;
  dialCode: string;
} {
  const dialCode = input.dialCode.trim();
  const national = input.number.replace(/[\s.-]/g, '');
  const fail = (message: string) =>
    new ValidationError([{ path: 'phone', message }], 'Phone number is not valid');
  if (!DIAL_CODE.test(dialCode)) throw fail('Dial code must look like +960');
  if (!/^\d+$/.test(national)) throw fail('Phone number may contain digits only');
  if (national.length < NATIONAL_MIN || national.length > NATIONAL_MAX) {
    throw fail(`Phone number must be ${String(NATIONAL_MIN)} to ${String(NATIONAL_MAX)} digits`);
  }
  if (dialCode.length - 1 + national.length > E164_MAX_DIGITS) {
    throw fail('Phone number is too long for its dial code');
  }
  return { e164: `${dialCode}${national}`, dialCode };
}
