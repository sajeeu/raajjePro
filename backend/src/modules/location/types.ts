import type { Island } from '../../generated/prisma/client.js';

/**
 * What an island looks like on the wire (§Phase 7, §0.0 item 12).
 *
 * **`id` is the identifier and `name` is not.** Sixteen normalised names occur
 * in more than one atoll, so a client storing or matching on `name` — a
 * service area, a booking location, a filter — is a defect. The name is here
 * to be *read*.
 *
 * **The atoll travels with the island.** A screen that resolves the ambiguity
 * when the customer picks and then shows the bare name afterwards has not
 * fixed anything, so every shape carrying an island carries `atollName` and
 * `atollAbbr` with it.
 */
export interface IslandDto {
  id: string;
  /** The register spelling, apostrophes intact — `An'golhitheemu`, `Male'`. */
  name: string;
  /**
   * What a screen prints. §0.0 item 12's display convention, decided by the
   * server so that every surface renders the same string: an ambiguous name is
   * qualified in the Maldivian form — `Dh. Meedhoo` — and an unambiguous one
   * stands alone as `Kulhudhuffushi`. Prefixing all 192 was considered and
   * rejected; it adds a code to the names that never needed one.
   */
  displayName: string;
  atollName: string;
  atollAbbr: string;
  /** True where the name is shared with another island, so `displayName` carries the atoll code. */
  nameAmbiguous: boolean;
}

export function toIslandDto(row: Island): IslandDto {
  return {
    id: row.id,
    name: row.name,
    displayName: row.nameAmbiguous ? `${row.atollAbbr}. ${row.name}` : row.name,
    atollName: row.atollName,
    atollAbbr: row.atollAbbr,
    nameAmbiguous: row.nameAmbiguous,
  };
}
