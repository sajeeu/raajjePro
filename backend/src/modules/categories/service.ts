import { BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { Category, Prisma, PrismaClient } from '../../generated/prisma/client.js';
import type { AuditService } from '../audit/service.js';
import type { RequestMeta } from '../admin-auth/service.js';
import { CategoryRepository } from './repository.js';
import type { CreateCategoryBody, UpdateCategoryBody } from './schema.js';
import {
  toAdminCategoryDto,
  toCategoryDto,
  type AdminCategoryDto,
  type CategoryDto,
} from './types.js';

interface Deps {
  prisma: PrismaClient;
  audit: AuditService;
}

/**
 * The category catalogue (§Phase 4).
 *
 * Reads are public and unconditional; every write is an admin action and is
 * audited in the same transaction as the row it changes. The catalogue is
 * open — nothing here checks a name against a list — but a category's
 * *configuration* has to hold together, because §1c's composed emergency rule
 * and invariant 13's quote clock both read these columns and cannot evaluate
 * against a half-set row. Those coherence rules live in `assertCoherent`.
 */
export class CategoryService {
  readonly repo: CategoryRepository;
  private readonly audit: AuditService;

  constructor(deps: Deps) {
    this.repo = new CategoryRepository(deps.prisma);
    this.audit = deps.audit;
  }

  /**
   * Who may call: anyone, signed in or not. Active only, in `sortOrder`.
   *
   * Paged, because the catalogue is explicitly unlimited (§Phase 4) and
   * `backend/CLAUDE.md` makes pagination mandatory on any endpoint that can
   * return an unbounded set. In practice the twelve fit in one page and the
   * cursor is never used; it exists so that an admin creating a hundredth
   * category cannot make this response unbounded.
   */
  async listPublic(
    options: { limit?: number; cursor?: string } = {},
  ): Promise<{ items: CategoryDto[]; nextCursor: string | null }> {
    const limit = options.limit ?? DEFAULT_PAGE;
    const after = options.cursor === undefined ? null : decodeCursor(options.cursor);
    const rows = await this.repo.findActivePage(limit, after);
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    return {
      items: page.map(toCategoryDto),
      nextCursor: rows.length > limit && last !== undefined ? encodeCursor(last) : null,
    };
  }

  /** Every category a downstream module needs, cursor walked for it. */
  async listAllPublic(): Promise<CategoryDto[]> {
    const all: CategoryDto[] = [];
    let cursor: string | undefined;
    do {
      const page = await this.listPublic(cursor === undefined ? {} : { cursor });
      all.push(...page.items);
      cursor = page.nextCursor ?? undefined;
    } while (cursor !== undefined);
    return all;
  }

  /** Who may call: an admin. Includes deactivated rows — the only way back from a soft delete. */
  async listForAdmin(): Promise<AdminCategoryDto[]> {
    return (await this.repo.findAll()).map(toAdminCategoryDto);
  }

  async create(
    body: CreateCategoryBody,
    actor: { adminId: string; meta: RequestMeta },
  ): Promise<AdminCategoryDto> {
    const { reason, ...fields } = body;
    assertCoherent(fields);
    const clash = await this.repo.findByName(fields.name);
    if (clash !== null) {
      throw new ConflictError('CATEGORY_NAME_TAKEN', `A category named "${fields.name}" exists`, [
        { path: 'name', message: 'This name is already in use' },
      ]);
    }
    const row = await this.repo.transaction(async (tx) => {
      const created = await this.repo.create(tx, fields);
      await this.recordAudit(tx, actor, 'category.created', created, reason, {
        name: created.name,
      });
      return created;
    });
    return toAdminCategoryDto(row);
  }

  async update(
    id: string,
    body: UpdateCategoryBody,
    actor: { adminId: string; meta: RequestMeta },
  ): Promise<AdminCategoryDto> {
    const { reason, ...patch } = body;
    const current = await this.repo.findById(id);
    if (current === null) throw new NotFoundError('No such category');

    // The rule is checked against the row that *would* result, not against the
    // patch: clearing `emergencyMinimumTier` alone is only invalid because the
    // stored `emergencyCapable` is true, and the patch alone cannot say that.
    // Merged field by field rather than by spread — `??` cannot be used here
    // because `null` is a meaningful value on four of these, so an absent key
    // and an explicit null have to stay distinguishable.
    assertCoherent({
      emergencyCapable: patch.emergencyCapable ?? current.emergencyCapable,
      emergencyAcceptWindowMinutes:
        patch.emergencyAcceptWindowMinutes === undefined
          ? current.emergencyAcceptWindowMinutes
          : patch.emergencyAcceptWindowMinutes,
      emergencyMinimumTier:
        patch.emergencyMinimumTier === undefined
          ? current.emergencyMinimumTier
          : patch.emergencyMinimumTier,
      emergencyEtaPresetsMinutes:
        patch.emergencyEtaPresetsMinutes ?? current.emergencyEtaPresetsMinutes,
      quoteExpiryMinutes:
        patch.quoteExpiryMinutes === undefined
          ? current.quoteExpiryMinutes
          : patch.quoteExpiryMinutes,
      quoteApprovalMinutes:
        patch.quoteApprovalMinutes === undefined
          ? current.quoteApprovalMinutes
          : patch.quoteApprovalMinutes,
    });

    if (patch.name !== undefined && patch.name !== current.name) {
      const clash = await this.repo.findByName(patch.name);
      if (clash !== null && clash.id !== id) {
        throw new ConflictError('CATEGORY_NAME_TAKEN', `A category named "${patch.name}" exists`, [
          { path: 'name', message: 'This name is already in use' },
        ]);
      }
    }

    const changed = Object.keys(patch).sort();
    const row = await this.repo.transaction(async (tx) => {
      const updated = await this.repo.update(tx, id, withoutAbsentKeys(patch));
      await this.recordAudit(tx, actor, 'category.updated', updated, reason, {
        changed: changed.join(', '),
      });
      return updated;
    });
    return toAdminCategoryDto(row);
  }

  /**
   * Invariant 8 and invariant 1d: a category is never deleted, only
   * deactivated. It drops out of `GET /v1/categories` and out of Explore, and
   * an admin can set `isActive` back through PATCH — which is why the admin
   * list returns inactive rows.
   */
  async deactivate(
    id: string,
    reason: string,
    actor: { adminId: string; meta: RequestMeta },
  ): Promise<AdminCategoryDto> {
    const current = await this.repo.findById(id);
    if (current === null) throw new NotFoundError('No such category');
    if (!current.isActive) return toAdminCategoryDto(current);

    const row = await this.repo.transaction(async (tx) => {
      const updated = await this.repo.update(tx, id, { isActive: false });
      await this.recordAudit(tx, actor, 'category.deactivated', updated, reason, {
        name: updated.name,
      });
      return updated;
    });
    return toAdminCategoryDto(row);
  }

  private recordAudit(
    tx: Prisma.TransactionClient,
    actor: { adminId: string; meta: RequestMeta },
    action: string,
    row: Category,
    reason: string,
    metadata: Record<string, string | number | boolean | null>,
  ) {
    return this.audit.record(tx, {
      actorType: 'admin',
      actorId: actor.adminId,
      action,
      targetType: 'category',
      targetId: row.id,
      reason,
      metadata,
      requestId: actor.meta.requestId,
      ipAddress: actor.meta.ip,
    });
  }
}

/**
 * Drops keys the caller never sent. Under `exactOptionalPropertyTypes` a
 * present-but-undefined key is not the same as an absent one, and Prisma's
 * update input rejects the former — see the same note in `AuditService.record`.
 */
function withoutAbsentKeys(patch: Omit<UpdateCategoryBody, 'reason'>): Prisma.CategoryUpdateInput {
  const data: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(patch)) {
    if (value !== undefined) data[key] = value;
  }
  return data;
}

/** One page is far larger than the seeded twelve; the cursor is the guarantee, not the norm. */
const DEFAULT_PAGE = 100;

/** `(sortOrder, id)` — see `findActivePage` for why the name is not in it. */
function encodeCursor(row: Category): string {
  return Buffer.from(`${String(row.sortOrder)}:${row.id}`, 'utf8').toString('base64url');
}

function decodeCursor(cursor: string): { sortOrder: number; id: string } | null {
  const raw = Buffer.from(cursor, 'base64url').toString('utf8');
  const separator = raw.indexOf(':');
  if (separator === -1) return null;
  const sortOrder = Number(raw.slice(0, separator));
  const id = raw.slice(separator + 1);
  // A malformed cursor reads as "start from the beginning" rather than 500ing
  // — it is a client-supplied opaque string and the page it names is public.
  return Number.isInteger(sortOrder) && id.length > 0 ? { sortOrder, id } : null;
}

/** The subset of a category the coherence rules read. */
interface Configurable {
  emergencyCapable: boolean;
  emergencyAcceptWindowMinutes: number | null;
  emergencyMinimumTier: string | null;
  emergencyEtaPresetsMinutes: number[];
  quoteExpiryMinutes: number | null;
  quoteApprovalMinutes: number | null;
}

/**
 * Two rules, both derived from §1c rather than stated in §Phase 4's field
 * list, and both there because a downstream module would otherwise read a
 * null it has no defined behaviour for:
 *
 *  1. §1c's composed emergency rule gates on the category's
 *     `emergencyMinimumTier` and dispatch runs on its
 *     `emergencyAcceptWindowMinutes`. An emergency-capable category missing
 *     either has no bar and no clock — so the fields move together, and a
 *     non-capable category carries none of them.
 *  2. Invariant 13's two quote windows are one mechanism: a quote that
 *     expires but can never be approved, or the reverse, is not a
 *     configuration anyone meant.
 *
 * Neither rule constrains *which* tier or *how many* minutes — those stay
 * admin-editable, exactly as §Phase 4 requires.
 */
function assertCoherent(c: Configurable): void {
  const problems: { path: string; message: string }[] = [];

  if (c.emergencyCapable) {
    if (c.emergencyMinimumTier === null)
      problems.push({
        path: 'emergencyMinimumTier',
        message: 'An emergency-capable category needs a minimum verification tier',
      });
    if (c.emergencyAcceptWindowMinutes === null)
      problems.push({
        path: 'emergencyAcceptWindowMinutes',
        message: 'An emergency-capable category needs a response window',
      });
  } else {
    if (c.emergencyMinimumTier !== null)
      problems.push({
        path: 'emergencyMinimumTier',
        message: 'Only an emergency-capable category carries a minimum tier',
      });
    if (c.emergencyAcceptWindowMinutes !== null)
      problems.push({
        path: 'emergencyAcceptWindowMinutes',
        message: 'Only an emergency-capable category carries a response window',
      });
    if (c.emergencyEtaPresetsMinutes.length > 0)
      problems.push({
        path: 'emergencyEtaPresetsMinutes',
        message: 'Only an emergency-capable category carries arrival presets',
      });
  }

  if ((c.quoteExpiryMinutes === null) !== (c.quoteApprovalMinutes === null))
    problems.push({
      path: 'quoteApprovalMinutes',
      message: 'Set both quote windows or neither',
    });

  if (problems.length > 0)
    throw new BusinessRuleError(
      'CATEGORY_CONFIG_INCOHERENT',
      'This category configuration is incomplete',
      problems,
    );
}
