import type { PrismaClient } from '../../generated/prisma/client.js';

const ISLAND = {
  select: { id: true, name: true, atollAbbr: true, nameAmbiguous: true },
} as const;

/**
 * §1h's saved preferences, data access only. Every read filters on
 * `deletedAt: null` (invariant 8: soft delete, and a removed row is gone
 * from every user-visible read).
 */
export class SavedPreferencesRepository {
  constructor(private readonly prisma: PrismaClient) {}

  listAddresses(userId: string) {
    return this.prisma.savedAddress.findMany({
      where: { userId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
      include: { island: ISLAND },
    });
  }

  listTimeWindows(userId: string) {
    return this.prisma.savedTimeWindow.findMany({
      where: { userId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });
  }

  findPreferences(userId: string) {
    return this.prisma.savedPreferences.findUnique({ where: { userId } });
  }

  countAddresses(userId: string): Promise<number> {
    return this.prisma.savedAddress.count({ where: { userId, deletedAt: null } });
  }

  countTimeWindows(userId: string): Promise<number> {
    return this.prisma.savedTimeWindow.count({ where: { userId, deletedAt: null } });
  }

  findActiveIsland(islandId: string) {
    return this.prisma.island.findFirst({ where: { id: islandId, isActive: true }, ...ISLAND });
  }

  createAddress(data: { userId: string; label: string; islandId: string; addressLine: string }) {
    return this.prisma.savedAddress.create({ data, include: { island: ISLAND } });
  }

  /** Scoped to the owner in the `where`, so a stranger's id updates nothing. */
  async updateAddress(
    userId: string,
    id: string,
    data: { label: string; islandId: string; addressLine: string },
  ): Promise<boolean> {
    const { count } = await this.prisma.savedAddress.updateMany({
      where: { id, userId, deletedAt: null },
      data,
    });
    return count === 1;
  }

  findAddress(userId: string, id: string) {
    return this.prisma.savedAddress.findFirst({
      where: { id, userId, deletedAt: null },
      include: { island: ISLAND },
    });
  }

  async softDeleteAddress(userId: string, id: string, at: Date): Promise<boolean> {
    const { count } = await this.prisma.savedAddress.updateMany({
      where: { id, userId, deletedAt: null },
      data: { deletedAt: at },
    });
    return count === 1;
  }

  createTimeWindow(data: {
    userId: string;
    weekdays: number[];
    startMinute: number;
    endMinute: number;
  }) {
    return this.prisma.savedTimeWindow.create({ data });
  }

  async softDeleteTimeWindow(userId: string, id: string, at: Date): Promise<boolean> {
    const { count } = await this.prisma.savedTimeWindow.updateMany({
      where: { id, userId, deletedAt: null },
      data: { deletedAt: at },
    });
    return count === 1;
  }

  upsertInstructions(userId: string, text: string | null) {
    return this.prisma.savedPreferences.upsert({
      where: { userId },
      create: { userId, standingInstructions: text },
      update: { standingInstructions: text },
    });
  }
}
