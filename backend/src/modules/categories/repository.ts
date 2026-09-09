import type { Category, Prisma, PrismaClient } from '../../generated/prisma/client.js';

/** A Prisma client or an open transaction — writes take the caller's, so the audit entry commits with the change. */
type Db = PrismaClient | Prisma.TransactionClient;

/**
 * Category reads and writes. Every read is ordered by `sortOrder` — the grid
 * is drawn in that order and nothing downstream should have to sort.
 */
export class CategoryRepository {
  constructor(private readonly prisma: PrismaClient) {}

  /**
   * The public catalogue: active rows only (invariant 8's soft delete,
   * respected here). Ordered by `(sortOrder, id)` rather than `(sortOrder,
   * name)` because the cursor is built from that pair — a name can be
   * renamed underneath a paging client, an id cannot.
   *
   * Takes `limit + 1` so the caller can tell whether another page exists
   * without a second count query.
   */
  findActivePage(
    limit: number,
    after: { sortOrder: number; id: string } | null,
  ): Promise<Category[]> {
    return this.prisma.category.findMany({
      where: {
        isActive: true,
        ...(after === null
          ? {}
          : {
              OR: [
                { sortOrder: { gt: after.sortOrder } },
                { sortOrder: after.sortOrder, id: { gt: after.id } },
              ],
            }),
      },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
      take: limit + 1,
    });
  }

  /** The admin catalogue: deactivated rows included, so a soft delete stays reversible. */
  findAll(): Promise<Category[]> {
    return this.prisma.category.findMany({ orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] });
  }

  findById(id: string): Promise<Category | null> {
    return this.prisma.category.findUnique({ where: { id } });
  }

  /**
   * Case-insensitive on purpose: "plumbing" beside "Plumbing" would render as
   * two tiles, and the database's unique index is exact-match only. The
   * residual race — two admins creating differently-cased duplicates in the
   * same instant — is left open knowingly: this surface has one operator, and
   * the outcome is a cosmetic duplicate an admin fixes by renaming, not a
   * corrupted record. See `docs/decisions/16-phase-4-categories.md`.
   */
  findByName(name: string): Promise<Category | null> {
    return this.prisma.category.findFirst({
      where: { name: { equals: name, mode: 'insensitive' } },
    });
  }

  create(db: Db, data: Prisma.CategoryCreateInput): Promise<Category> {
    return db.category.create({ data });
  }

  update(db: Db, id: string, data: Prisma.CategoryUpdateInput): Promise<Category> {
    return db.category.update({ where: { id }, data });
  }

  /** Runs `fn` inside a transaction so the row change and its audit entry land together. */
  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }
}
