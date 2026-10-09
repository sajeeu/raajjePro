/**
 * §Phase 17 frontend item 14: "**Calendar export** on a confirmed booking — an
 * ICS download or subscribe link, so a provider running several jobs a week
 * can see them alongside everything else in their life rather than only
 * inside the app."
 *
 * A download, not a subscribe link: the plan offers either, and a subscribe
 * feed is a long-lived unauthenticated URL onto somebody's job list, which is
 * a different security question from a file the signed-in user saves once.
 *
 * Pure: nothing here reads a clock or a database. RFC 5545 is strict about
 * three things a hand-rolled writer usually gets wrong, and each is handled
 * below — CRLF line endings, folding at 75 octets (not characters), and
 * escaping `\`, `;`, `,` and newlines in text values.
 *
 * ## What the entry carries, and what it never does
 *
 * The service, the counterparty's display name, the place and the booking
 * reference. **Never a phone number** (§1c) — an exported calendar entry is
 * a response shape like any other, and it is the easiest place to leak one,
 * because it lives on in somebody's calendar long after the booking ends.
 */

export interface CalendarEntry {
  /** Stable across re-exports, so a re-download updates the event rather than duplicating it. */
  uid: string;
  /** Bumped when the agreed time moves, so calendar apps accept the update. */
  sequence: number;
  stampedAt: Date;
  startsAt: Date;
  endsAt: Date;
  summary: string;
  description: string;
  location: string | null;
}

const CRLF = '\r\n';
const MAX_LINE_OCTETS = 75;

export function buildIcs(entry: CalendarEntry): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//RaajjePro//Bookings//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${escapeText(entry.uid)}`,
    `SEQUENCE:${String(entry.sequence)}`,
    `DTSTAMP:${utc(entry.stampedAt)}`,
    // UTC throughout. The Maldives keeps no daylight saving, but a calendar
    // app converts a `Z` time to its own zone correctly everywhere, and a
    // floating local time would land five hours wrong on a phone set to UTC.
    `DTSTART:${utc(entry.startsAt)}`,
    `DTEND:${utc(entry.endsAt)}`,
    `SUMMARY:${escapeText(entry.summary)}`,
    `DESCRIPTION:${escapeText(entry.description)}`,
    ...(entry.location === null ? [] : [`LOCATION:${escapeText(entry.location)}`]),
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return lines.map(fold).join(CRLF) + CRLF;
}

/** `20260901T090000Z` — RFC 5545's UTC DATE-TIME form. */
function utc(at: Date): string {
  return at
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}Z$/, 'Z');
}

/** RFC 5545 §3.3.11: backslash, semicolon, comma and newline are escaped in TEXT. */
function escapeText(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

/**
 * RFC 5545 §3.1: lines longer than 75 **octets** are folded with CRLF plus a
 * single space. Counted in UTF-8 bytes and split only on a character
 * boundary, so `Malé` or a Dhivehi name never has a multi-byte character cut
 * in half.
 */
function fold(line: string): string {
  const out: string[] = [];
  let current = '';
  let currentOctets = 0;
  // The continuation lines carry a leading space, which counts toward the 75.
  let limit = MAX_LINE_OCTETS;
  for (const char of line) {
    const octets = Buffer.byteLength(char, 'utf8');
    if (currentOctets + octets > limit) {
      out.push(current);
      current = '';
      currentOctets = 0;
      limit = MAX_LINE_OCTETS - 1;
    }
    current += char;
    currentOctets += octets;
  }
  out.push(current);
  return out.join(`${CRLF} `);
}
