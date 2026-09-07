import { describe, expect, it } from 'vitest';

import { ValidationError } from '../src/core/errors.js';
import { normalisePhone } from '../src/modules/auth/phone.js';

describe('normalisePhone (plan §Phase 3: E.164, +960 default, 6–15 digits, foreign numbers welcome)', () => {
  it('stores a Maldivian number as +960 plus digits and strips separators', () => {
    expect(normalisePhone({ dialCode: '+960', number: '777-1234' })).toEqual({
      e164: '+9607771234',
      dialCode: '+960',
    });
    expect(normalisePhone({ dialCode: ' +960 ', number: '777 12.34' })).toEqual({
      e164: '+9607771234',
      dialCode: '+960',
    });
  });

  it('accepts a foreign number and does not apply the 7-or-9 heuristic', () => {
    expect(normalisePhone({ dialCode: '+44', number: '7700900123' })).toEqual({
      e164: '+447700900123',
      dialCode: '+44',
    });
    expect(normalisePhone({ dialCode: '+960', number: '3001234' })).toEqual({
      e164: '+9603001234',
      dialCode: '+960',
    });
  });

  it('rejects too few or too many digits, a bad dial code, and an E.164 overflow — each at path phone', () => {
    for (const input of [
      { dialCode: '+960', number: '12345' },
      { dialCode: '+960', number: '1234567890123456' },
      { dialCode: '960', number: '7771234' },
      { dialCode: '+0', number: '7771234' },
      { dialCode: '+1234', number: '123456789012' }, // 4 + 12 = 16 digits
      { dialCode: '+960', number: '77a1234' },
    ]) {
      let caught: unknown;
      try {
        normalisePhone(input);
      } catch (error) {
        caught = error;
      }
      expect(caught, JSON.stringify(input)).toBeInstanceOf(ValidationError);
      expect((caught as ValidationError).details).toEqual([
        expect.objectContaining({ path: 'phone' }),
      ]);
    }
  });
});
