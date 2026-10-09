import { describe, expect, it } from 'vitest';

import { buildIcs } from '../src/modules/bookings/ics.js';
import { timeWindowLabel, weekdaysLabel } from '../src/modules/saved-preferences/types.js';

/**
 * §Phase 17.4's two pure pieces: the ICS writer, whose three RFC 5545 traps
 * are easy to get wrong silently, and the saved-window labels, whose
 * "Weekdays" has to mean the Maldivian working week.
 */
describe('buildIcs', () => {
  const entry = {
    uid: 'booking-1@raajjepro',
    sequence: 0,
    stampedAt: new Date('2026-10-09T05:00:00.000Z'),
    startsAt: new Date('2026-10-13T09:00:00.000Z'),
    endsAt: new Date('2026-10-13T11:00:00.000Z'),
    summary: 'Home Deep Cleaning — Mariyam Shifa',
    description: 'Line one\nLine two; with a comma, and a back\\slash',
    location: 'Fehivina, 3rd floor, Malé',
  };

  it('writes UTC times in the basic format', () => {
    const ics = buildIcs(entry);
    expect(ics).toContain('DTSTART:20261013T090000Z\r\n');
    expect(ics).toContain('DTEND:20261013T110000Z\r\n');
  });

  it('escapes the four TEXT specials', () => {
    const unfolded = buildIcs(entry).replace(/\r\n /g, '');
    expect(unfolded).toContain(
      'DESCRIPTION:Line one\\nLine two\\; with a comma\\, and a back\\\\slash',
    );
    expect(unfolded).toContain('LOCATION:Fehivina\\, 3rd floor\\, Malé');
  });

  it('folds at 75 octets without splitting a multi-byte character', () => {
    const ics = buildIcs({ ...entry, summary: 'Malé '.repeat(40) });
    for (const line of ics.split('\r\n')) {
      expect(Buffer.byteLength(line, 'utf8')).toBeLessThanOrEqual(75);
      // A cut multi-byte character would decode to U+FFFD.
      expect(line).not.toContain('�');
    }
    expect(ics.replace(/\r\n /g, '')).toContain(`SUMMARY:${'Malé '.repeat(40)}`);
  });

  it('omits LOCATION when there is no place', () => {
    expect(buildIcs({ ...entry, location: null })).not.toContain('LOCATION:');
  });
});

describe('saved time-window labels', () => {
  it('reads the Maldivian week: Sunday to Thursday are weekdays, Friday and Saturday the weekend', () => {
    expect(weekdaysLabel([1, 2, 3, 4, 7])).toBe('Weekdays');
    expect(weekdaysLabel([5, 6])).toBe('Weekend');
    expect(weekdaysLabel([1, 3, 5])).toBe('Mon, Wed, Fri');
    expect(weekdaysLabel([6])).toBe('Saturday');
    expect(weekdaysLabel([1, 2, 3, 4, 5, 6, 7])).toBe('Every day');
    // Sunday first in a list — mirrored by the app's preview (previewTimeWindowLabel).
    expect(weekdaysLabel([2, 7])).toBe('Sun, Tue');
  });

  it('prints the artboard’s form', () => {
    expect(timeWindowLabel({ weekdays: [7, 1, 2, 3, 4], startMinute: 540, endMinute: 720 })).toBe(
      'Weekdays · 9:00–12:00',
    );
    expect(timeWindowLabel({ weekdays: [6], startMinute: 840, endMinute: 1080 })).toBe(
      'Saturday · 14:00–18:00',
    );
  });
});
