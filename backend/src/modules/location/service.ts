import { BusinessRuleError, NotFoundError } from '../../core/errors.js';
import type { Clock } from '../../core/clock.js';
import type { Island, PrismaClient } from '../../generated/prisma/client.js';
import type { ProviderProfileService } from '../providers/service.js';
import { islandMatchRank, normaliseIslandText } from './normalise.js';
import { LocationRepository } from './repository.js';
import { toIslandDto, type IslandDto } from './types.js';

interface Deps {
  prisma: PrismaClient;
  providers: ProviderProfileService;
  clock: Clock;
}

/**
 * Islands and provider service areas (§Phase 7).
 *
 * The island list is reference data seeded from the ministry register; the
 * service areas are the islands a provider works on, account-level. Phase 8
 * gives a *listing* its own areas — those are what discovery reads — and
 * §Phase 6a pre-fills the wizard from these.
 */
export class LocationService {
  readonly repo: LocationRepository;
  private readonly providers: ProviderProfileService;
  private readonly clock: Clock;

  constructor(deps: Deps) {
    this.repo = new LocationRepository(deps.prisma);
    this.providers = deps.providers;
    this.clock = deps.clock;
  }

  /**
   * Who may call: anyone, including a signed-out guest — the island picker is
   * in the header of the first screen a customer sees.
   *
   * §0.0 item 12's search rule, in one place:
   *
   *   - **matches anywhere in the name** from the first character typed, and
   *     **matches the atoll code too**, both from the one normalised
   *     `searchQualified` column;
   *   - **ignores case, accents and the Dhivehi apostrophe** on both sides —
   *     the stored column and the query go through the same
   *     `normaliseIslandText`;
   *   - **ranks prefix matches first**, then orders by name;
   *   - **returns every match, with no cap and no "show more"**, because
   *     truncating hides the one island the customer is looking for.
   *
   * 🔧 **Unpaginated on purpose, and it does not breach the pagination rule.**
   * `backend/CLAUDE.md` requires paging on any endpoint that can return an
   * *unbounded* set. This one cannot: islands are a closed register seeded
   * from a government extract, there is no endpoint in this phase that creates
   * one, and the whole set is 192 rows. Where the category list took a cursor
   * against a catalogue an admin can grow, §0.0 item 12 states the opposite
   * requirement here and states it as a product rule, so the cap is the thing
   * that would be the defect.
   *
   * **It never auto-selects.** A single match is returned as a list of one;
   * choosing is the customer's act, and a picker that resolves it for them
   * cannot be corrected when it guesses the wrong `Meedhoo`.
   */
  async searchIslands(search?: string): Promise<IslandDto[]> {
    const query = normaliseIslandText(search ?? '');
    if (query === '') return (await this.repo.findAllActive()).map(toIslandDto);

    const matches = await this.repo.searchActive(query);
    return rankForQuery(matches, query).map(toIslandDto);
  }

  /** Who may call: the signed-in provider, for their own profile. */
  async listOwnServiceAreas(userId: string): Promise<IslandDto[]> {
    const profile = await this.requireOwnProfile(userId);
    return this.currentAreas(profile.id);
  }

  /**
   * Who may call: the signed-in user, for their own provider profile.
   *
   * **This write creates the profile where a read does not** — the same rule
   * and the same reasoning as `PATCH /v1/providers/me` (§1a's implicit
   * creation): saying which islands you work on is unambiguously acting as a
   * provider, where merely opening a screen is not. `getOrCreateProviderProfile`
   * is idempotent, so a provider who already has one is unaffected.
   *
   * **No idempotency key.** `backend/CLAUDE.md` asks for one on every creation
   * POST so a retry cannot leave two rows; here the unique
   * `(providerProfileId, islandId)` pair gives that guarantee at the database
   * rather than by replaying a stored response, which is the stronger of the
   * two — a retry converges on the one row whatever key it carries.
   *
   * Returns the resulting service areas in full, so the client's list is exact
   * after every write rather than reconstructed from a status code.
   */
  async addOwnServiceArea(userId: string, islandId: string): Promise<IslandDto[]> {
    await this.requireActiveIsland(islandId);
    const profile = await this.providers.getOrCreateProviderProfile(userId);
    await this.repo.addServiceArea(profile.id, islandId, this.clock());
    return this.currentAreas(profile.id);
  }

  /**
   * Who may call: the signed-in provider, for their own profile.
   *
   * Invariant 8: the join row is stamped `removedAt`, never deleted, and
   * re-adding the island revives it. Removing an island that is not currently
   * a service area succeeds and changes nothing — the client's view is allowed
   * to lag, and there is nothing to protect by turning that into an error.
   *
   * Unlike the add, this does **not** create a provider profile: there is
   * nothing to remove from an account that has never been a provider, so it
   * answers `PROVIDER_PROFILE_NOT_FOUND` rather than quietly making one.
   */
  async removeOwnServiceArea(userId: string, islandId: string): Promise<IslandDto[]> {
    const profile = await this.requireOwnProfile(userId);
    await this.repo.removeServiceArea(profile.id, islandId, this.clock());
    return this.currentAreas(profile.id);
  }

  /** The islands a provider works on, for another module's DTO. */
  async serviceAreasFor(providerProfileId: string): Promise<IslandDto[]> {
    return this.currentAreas(providerProfileId);
  }

  private async currentAreas(providerProfileId: string): Promise<IslandDto[]> {
    const rows = await this.repo.findCurrentServiceAreas(providerProfileId);
    return rows.map((row) => toIslandDto(row.island));
  }

  private async requireOwnProfile(userId: string): Promise<{ id: string }> {
    const profile = await this.providers.repo.findByUserId(userId);
    if (profile === null) {
      throw new NotFoundError(
        'This account has no provider profile yet',
        'PROVIDER_PROFILE_NOT_FOUND',
      );
    }
    return profile;
  }

  /**
   * A deactivated island cannot be added. It is soft-deleted rather than gone
   * (invariant 8), so the row is still addressable by id — and a provider
   * declaring coverage of an island no customer can browse from would be a
   * service area nothing could ever match.
   */
  private async requireActiveIsland(islandId: string): Promise<Island> {
    const island = await this.repo.findById(islandId);
    if (island === null) throw new NotFoundError('No such island', 'ISLAND_NOT_FOUND');
    if (!island.isActive) {
      throw new BusinessRuleError('ISLAND_INACTIVE', 'That island is no longer available', [
        { path: 'islandId', message: 'This island is no longer available' },
      ]);
    }
    return island;
  }
}

/**
 * Prefix matches first, then by name, then by atoll code so the order is
 * total — two islands sharing a name must not swap places between requests.
 */
function rankForQuery(islands: Island[], query: string): Island[] {
  return [...islands].sort((a, b) => {
    const rank =
      islandMatchRank(query, { bare: a.searchName, qualified: a.searchQualified }) -
      islandMatchRank(query, { bare: b.searchName, qualified: b.searchQualified });
    if (rank !== 0) return rank;
    return a.name.localeCompare(b.name) || a.atollAbbr.localeCompare(b.atollAbbr);
  });
}
