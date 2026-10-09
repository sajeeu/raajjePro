import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, NotFoundError } from '../../core/errors.js';
import { minutesOfDay, wallClockOf } from '../../core/maldives-time.js';
import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';
import type { ExportContributor } from '../account/export.js';
import type { AnonymisationHooks } from '../account/anonymise.js';
import { SavedPreferencesRepository } from './repository.js';
import {
  timeWindowLabel,
  type SavedAddressDto,
  type SavedPreferencesDto,
  type SavedTimeWindowDto,
} from './types.js';

/**
 * How many of each a customer may keep.
 *
 * 🔧 **Not in the plan — a bound, recorded in
 * `docs/decisions/31-phase-17-4-recurring-reschedule-callback.md`.** §1h
 * names the three sections and no limit, and backend/CLAUDE.md requires any
 * set a user can grow without bound to be paged. A screen of saved addresses
 * that needs paging has stopped being a shortcut; twenty is far past what
 * the artboard's "Home" and "Office" suggest anyone needs, and it lets the
 * read stay one unpaged document.
 */
export const MAX_SAVED_ADDRESSES = 20;
export const MAX_SAVED_TIME_WINDOWS = 20;

type AddressRow = Prisma.SavedAddressGetPayload<{
  include: { island: { select: { id: true; name: true; atollAbbr: true; nameAmbiguous: true } } };
}>;

function islandDisplay(island: { name: string; atollAbbr: string; nameAmbiguous: boolean }) {
  return island.nameAmbiguous ? `${island.atollAbbr}. ${island.name}` : island.name;
}

function toAddressDto(row: AddressRow): SavedAddressDto {
  return {
    id: row.id,
    label: row.label,
    islandId: row.islandId,
    islandDisplayName: islandDisplay(row.island),
    addressLine: row.addressLine,
    createdAt: row.createdAt.toISOString(),
  };
}

function toTimeWindowDto(row: {
  id: string;
  weekdays: number[];
  startMinute: number;
  endMinute: number;
  createdAt: Date;
}): SavedTimeWindowDto {
  return {
    id: row.id,
    weekdays: row.weekdays,
    startTime: wallClockOf(row.startMinute),
    endTime: wallClockOf(row.endMinute),
    label: timeWindowLabel(row),
    createdAt: row.createdAt.toISOString(),
  };
}

/**
 * §1h's saved preferences, reattributed to §Phase 17.4 by the owner on
 * 2026-09-10: "reused across bookings" and "carried forward by Book Again".
 *
 * Every method is the signed-in user's own. There is no read of anybody
 * else's preferences, and the standing instructions reach a provider only
 * inside a booking the customer makes — never through this module.
 */
export class SavedPreferencesService {
  private readonly repo: SavedPreferencesRepository;

  constructor(private readonly deps: { prisma: PrismaClient; clock: Clock }) {
    this.repo = new SavedPreferencesRepository(deps.prisma);
  }

  async read(userId: string): Promise<SavedPreferencesDto> {
    const [addresses, windows, prefs] = await Promise.all([
      this.repo.listAddresses(userId),
      this.repo.listTimeWindows(userId),
      this.repo.findPreferences(userId),
    ]);
    return {
      addresses: addresses.map(toAddressDto),
      timeWindows: windows.map(toTimeWindowDto),
      standingInstructions: prefs?.standingInstructions ?? null,
    };
  }

  async addAddress(
    userId: string,
    input: { label: string; islandId: string; addressLine: string },
  ): Promise<SavedAddressDto> {
    await this.assertIsland(input.islandId);
    if ((await this.repo.countAddresses(userId)) >= MAX_SAVED_ADDRESSES) {
      throw limitReached('addresses', MAX_SAVED_ADDRESSES);
    }
    return toAddressDto(await this.repo.createAddress({ userId, ...input }));
  }

  async updateAddress(
    userId: string,
    id: string,
    input: { label: string; islandId: string; addressLine: string },
  ): Promise<SavedAddressDto> {
    await this.assertIsland(input.islandId);
    if (!(await this.repo.updateAddress(userId, id, input))) throw addressNotFound();
    const row = await this.repo.findAddress(userId, id);
    if (row === null) throw addressNotFound();
    return toAddressDto(row);
  }

  async removeAddress(userId: string, id: string): Promise<void> {
    if (!(await this.repo.softDeleteAddress(userId, id, this.deps.clock()))) {
      throw addressNotFound();
    }
  }

  async addTimeWindow(
    userId: string,
    input: { weekdays: number[]; startTime: string; endTime: string },
  ): Promise<SavedTimeWindowDto> {
    if ((await this.repo.countTimeWindows(userId)) >= MAX_SAVED_TIME_WINDOWS) {
      throw limitReached('time windows', MAX_SAVED_TIME_WINDOWS);
    }
    const row = await this.repo.createTimeWindow({
      userId,
      weekdays: [...input.weekdays].sort((a, b) => a - b),
      startMinute: minutesOfDay(input.startTime),
      endMinute: minutesOfDay(input.endTime),
    });
    return toTimeWindowDto(row);
  }

  async removeTimeWindow(userId: string, id: string): Promise<void> {
    if (!(await this.repo.softDeleteTimeWindow(userId, id, this.deps.clock()))) {
      throw new NotFoundError('No such time window', 'SAVED_TIME_WINDOW_NOT_FOUND');
    }
  }

  async setStandingInstructions(userId: string, text: string): Promise<SavedPreferencesDto> {
    await this.repo.upsertInstructions(userId, text === '' ? null : text);
    return this.read(userId);
  }

  /**
   * What Book Again carries forward (§1h): the standing instructions and the
   * first preferred window's label. One read, for one screen.
   */
  async forBooking(
    userId: string,
  ): Promise<{ standingInstructions: string | null; preferredWindowLabel: string | null }> {
    const [prefs, windows] = await Promise.all([
      this.repo.findPreferences(userId),
      this.repo.listTimeWindows(userId),
    ]);
    const first = windows[0];
    return {
      standingInstructions: prefs?.standingInstructions ?? null,
      preferredWindowLabel: first === undefined ? null : timeWindowLabel(first),
    };
  }

  private async assertIsland(islandId: string): Promise<void> {
    // By id, never by name (§0.0 item 12); an island no longer in the register
    // cannot be newly saved against.
    if ((await this.repo.findActiveIsland(islandId)) === null) {
      throw new NotFoundError('No such island', 'ISLAND_NOT_FOUND');
    }
  }
}

function addressNotFound(): NotFoundError {
  return new NotFoundError('No such address', 'SAVED_ADDRESS_NOT_FOUND');
}

function limitReached(what: string, max: number): BusinessRuleError {
  return new BusinessRuleError(
    'SAVED_PREFERENCE_LIMIT_REACHED',
    `You can keep up to ${String(max)} saved ${what} — remove one to add another`,
    { max },
  );
}

/**
 * §Phase 3's data export: a saved address is the user's own data and leaves
 * with it. Ids and the user's own text only.
 */
export function savedPreferencesExportContributor(prisma: PrismaClient): ExportContributor {
  const service = new SavedPreferencesService({ prisma, clock: () => new Date() });
  return {
    key: 'savedPreferences',
    collect: (userId: string) => service.read(userId),
  };
}

/**
 * §Phase 3's anonymisation. An address and a gate code are personal data, so
 * on deletion the text is blanked and the rows are stamped deleted — never
 * removed (invariant 8).
 */
export function registerSavedPreferencesAnonymisation(hooks: AnonymisationHooks): void {
  hooks.register('saved-preferences', async (tx, userId, now) => {
    await tx.savedAddress.updateMany({
      where: { userId },
      data: { label: '', addressLine: '', deletedAt: now },
    });
    await tx.savedTimeWindow.updateMany({
      where: { userId, deletedAt: null },
      data: { deletedAt: now },
    });
    await tx.savedPreferences.updateMany({
      where: { userId },
      data: { standingInstructions: null },
    });
  });
}
