import { randomInt } from 'node:crypto';

/**
 * The alphabet a booking reference is drawn from.
 *
 * No `O`, `0`, `I`, `1`, `L` or `S`/`5`: a reference exists to be read out
 * loud in a dispute or typed off a screenshot, and every pair that collides in
 * a handwritten or spoken rendering costs more than the entropy it adds. What
 * is left is 26 symbols; eight of them is about 37 bits, which is ample for a
 * table that will never hold millions of rows and is protected by a unique
 * index either way.
 */
const ALPHABET = 'ABCDEFGHJKMNPQRTUVWXYZ2346789';

const LENGTH = 8;

/**
 * A human-quotable booking reference, e.g. `RP-7K4M2QXB`.
 *
 * `randomInt` rather than `Math.random`: a guessable reference is not a
 * security boundary here (every endpoint checks ownership) but it is printed
 * on an invoice-shaped screen and there is no reason to make it enumerable.
 *
 * Collisions are handled by the caller retrying against the unique index
 * rather than by checking first — a read-then-write has a race and the index
 * does not.
 */
export function generateBookingReference(): string {
  let out = '';
  for (let i = 0; i < LENGTH; i += 1) out += ALPHABET.charAt(randomInt(ALPHABET.length));
  return `RP-${out}`;
}
