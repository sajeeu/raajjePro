/**
 * §1h's saved preferences, on the wire — `Saved Preferences.dc.html`.
 *
 * "**Saved addresses** with labels, **preferred time windows**, and
 * **standing service instructions** ('gate code', 'ask for the manager'),
 * reused across bookings." Three sections, one read.
 */

export interface SavedAddressDto {
  id: string;
  label: string;
  islandId: string;
  /** §0.0 item 12's convention, rendered here: `Dh. Meedhoo` or `Kulhudhuffushi`. */
  islandDisplayName: string;
  addressLine: string;
  createdAt: string;
}

export interface SavedTimeWindowDto {
  id: string;
  /** ISO weekdays, 1 = Monday … 7 = Sunday. */
  weekdays: number[];
  /** `HH:MM`, Maldives time. */
  startTime: string;
  endTime: string;
  /** What the chip prints — "Weekdays · 9:00–12:00". Rendered by the server. */
  label: string;
  createdAt: string;
}

export interface SavedPreferencesDto {
  addresses: SavedAddressDto[];
  timeWindows: SavedTimeWindowDto[];
  /** "Shared with the provider on every booking." */
  standingInstructions: string | null;
}

/**
 * The Maldivian working week is **Sunday to Thursday**; Friday and Saturday
 * are the weekend. "Weekdays" on a chip has to mean what a customer in Malé
 * means by it, which is not the ISO default.
 */
const MALDIVES_WEEKDAYS = [7, 1, 2, 3, 4];
const MALDIVES_WEEKEND = [5, 6];
/** Sunday first, which is how a Maldivian week reads. */
const DISPLAY_ORDER = [7, 1, 2, 3, 4, 5, 6];
const LONG = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const SHORT = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function sameSet(a: readonly number[], b: readonly number[]): boolean {
  return a.length === b.length && a.every((d) => b.includes(d));
}

export function weekdaysLabel(weekdays: readonly number[]): string {
  if (weekdays.length === 7) return 'Every day';
  if (sameSet(weekdays, MALDIVES_WEEKDAYS)) return 'Weekdays';
  if (sameSet(weekdays, MALDIVES_WEEKEND)) return 'Weekend';
  const ordered = DISPLAY_ORDER.filter((d) => weekdays.includes(d));
  if (ordered.length === 1) return LONG[ordered[0] ?? 0] ?? '';
  return ordered.map((d) => SHORT[d]).join(', ');
}

/** `9:00` rather than `09:00` — the artboard's form, and how a time is said aloud. */
function shortClock(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${String(h)}:${String(m).padStart(2, '0')}`;
}

export function timeWindowLabel(window: {
  weekdays: readonly number[];
  startMinute: number;
  endMinute: number;
}): string {
  return `${weekdaysLabel(window.weekdays)} · ${shortClock(window.startMinute)}–${shortClock(window.endMinute)}`;
}
