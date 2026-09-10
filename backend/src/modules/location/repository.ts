import type { Island, PrismaClient, ProviderServiceArea } from '../../generated/prisma/client.js';

/** A service-area row with the island it points at — the only shape the DTO layer needs. */
export type ServiceAreaWithIsland = ProviderServiceArea & { island: Island };

/**
 * Island and service-area reads and writes (§Phase 7).
 *
 * Islands are ordered by `name` rather than by `displayName`: the qualifier is
 * a rendering of the atoll code, and sorting on it would file `Dh. Meedhoo`
 * under D while `Kulhudhuffushi` files under K — the same list ordered two
 * different ways depending on whether a name happens to be shared.
 */
export class LocationRepository {
  constructor(private readonly prisma: PrismaClient) {}

  /** Every active island, for a picker that has not been typed into yet. */
  findAllActive(): Promise<Island[]> {
    return this.prisma.island.findMany({
      where: { isActive: true },
      orderBy: [{ name: 'asc' }, { atollAbbr: 'asc' }],
    });
  }

  /**
   * Every active island whose normalised qualified form contains
   * [normalisedQuery] — "matches anywhere in the name", and matches the atoll
   * code too, because `searchQualified` is the code followed by the name.
   *
   * **No `take`.** §0.0 item 12 forbids a cap; see the service for why the set
   * is bounded anyway. `normalisedQuery` has already been reduced to
   * `[a-z0-9]`, so it carries no `LIKE` metacharacters.
   */
  searchActive(normalisedQuery: string): Promise<Island[]> {
    return this.prisma.island.findMany({
      where: { isActive: true, searchQualified: { contains: normalisedQuery } },
      orderBy: [{ name: 'asc' }, { atollAbbr: 'asc' }],
    });
  }

  findById(id: string): Promise<Island | null> {
    return this.prisma.island.findUnique({ where: { id } });
  }

  /**
   * The provider's current service areas. `removedAt: null` is the soft-delete
   * filter (invariant 8) — a removed island keeps its row and is simply not
   * current.
   */
  findCurrentServiceAreas(providerProfileId: string): Promise<ServiceAreaWithIsland[]> {
    return this.prisma.providerServiceArea.findMany({
      where: { providerProfileId, removedAt: null },
      include: { island: true },
      orderBy: [{ island: { name: 'asc' } }, { island: { atollAbbr: 'asc' } }],
    });
  }

  /**
   * The same set as `findCurrentServiceAreas`, counted rather than loaded —
   * §Phase 6a's onboarding check only needs "at least one" and the Profile
   * screen asks for it on every load.
   */
  countCurrentServiceAreas(providerProfileId: string): Promise<number> {
    return this.prisma.providerServiceArea.count({
      where: { providerProfileId, removedAt: null },
    });
  }

  /**
   * Adds an island, or revives a previously removed one. Upsert on the unique
   * `(providerProfileId, islandId)` pair, which is what makes the operation
   * idempotent by construction: a retried request converges on the one row
   * rather than creating a second.
   */
  addServiceArea(providerProfileId: string, islandId: string, now: Date): Promise<void> {
    return this.prisma.providerServiceArea
      .upsert({
        where: { providerProfileId_islandId: { providerProfileId, islandId } },
        create: { providerProfileId, islandId, addedAt: now },
        update: { removedAt: null, addedAt: now },
      })
      .then(() => undefined);
  }

  /**
   * Invariant 8: stamps `removedAt` rather than deleting the row. `updateMany`
   * so that removing an island that is not currently a service area is a
   * no-op instead of a crash — the client's view can lag a moment.
   */
  async removeServiceArea(providerProfileId: string, islandId: string, now: Date): Promise<void> {
    await this.prisma.providerServiceArea.updateMany({
      where: { providerProfileId, islandId, removedAt: null },
      data: { removedAt: now },
    });
  }
}
