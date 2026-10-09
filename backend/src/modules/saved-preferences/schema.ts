import { z } from 'zod';

/**
 * `Saved Preferences.dc.html`'s three sections.
 *
 * Times arrive as `HH:MM` wall-clock strings, never instants — a preferred
 * window is a recurring time of day with no date, and an ISO timestamp would
 * invite a client to send it in its own timezone (the reason
 * `core/maldives-time.ts` gives for §Phase 9a's rules, which take the same
 * shape).
 */

const uuid = z.uuid();
const clockTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:MM, 24-hour');

export const addressParams = z.object({ id: uuid });
export const timeWindowParams = z.object({ id: uuid });

export const addressBody = z.object({
  label: z.string().trim().min(1).max(40),
  islandId: uuid,
  addressLine: z.string().trim().min(1).max(300),
});

export const timeWindowBody = z
  .object({
    weekdays: z
      .array(z.int().min(1).max(7))
      .min(1)
      .max(7)
      .refine((days) => new Set(days).size === days.length, 'Each day once'),
    startTime: clockTime,
    endTime: clockTime,
  })
  .refine((body) => body.startTime < body.endTime, {
    error: 'The window has to end after it starts',
    path: ['endTime'],
  });

export const standingInstructionsBody = z.object({
  /** Empty clears it. */
  text: z.string().trim().max(500),
});
