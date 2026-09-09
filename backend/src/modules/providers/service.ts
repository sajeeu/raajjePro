import { NotFoundError } from '../../core/errors.js';
import type {
  BookingMode,
  Prisma,
  PrismaClient,
  ProviderProfile,
} from '../../generated/prisma/client.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import type { CategoryService } from '../categories/service.js';
import {
  NO_CONDUCT,
  noConductRecorded,
  type ProviderConductRecord,
  type ProviderConductSource,
} from './conduct.js';
import { ProviderRepository } from './repository.js';
import type { UpdateOwnProviderBody } from './schema.js';
import {
  toOwnProviderDto,
  toPaymentDetailsDto,
  toPublicProviderDto,
  type OwnProviderDto,
  type PaymentDetailsDto,
  type PublicProviderDto,
} from './types.js';
import {
  NO_PUBLISHED_LISTINGS,
  ProviderVisibility,
  type PublishedListingSource,
  type VisibleProviderFilters,
} from './visibility.js';

interface Deps {
  prisma: PrismaClient;
  categories: CategoryService;
  audit: AuditService;
  /** Phase 8 supplies the real one; before listings exist, nobody is publicly visible. */
  listings?: PublishedListingSource;
  /** Phase 11 supplies the real one; before bookings exist, no conduct number is computable. */
  conduct?: ProviderConductSource;
}

/**
 * Provider profiles (§Phase 5).
 *
 * The provider half of an account: who they are, how a customer pays them,
 * whether they are taking work, what tier their evidence reached, and the read
 * surface for §1f's conduct numbers. Public visibility is not stored on any of
 * it — `visibility.findVisibleProviders` derives it (§1a), and this service
 * exposes that one helper rather than letting each consumer rebuild the rule.
 */
export class ProviderProfileService {
  readonly repo: ProviderRepository;
  readonly visibility: ProviderVisibility;
  private readonly categories: CategoryService;
  private readonly conduct: ProviderConductSource;
  private readonly audit: AuditService;

  constructor(deps: Deps) {
    this.repo = new ProviderRepository(deps.prisma);
    this.categories = deps.categories;
    this.audit = deps.audit;
    this.conduct = deps.conduct ?? noConductRecorded;
    this.visibility = new ProviderVisibility(deps.prisma, deps.listings ?? NO_PUBLISHED_LISTINGS);
  }

  /**
   * Idempotent (§1a, §Phase 5 Done-when: "called twice returns one row").
   * Phase 6a's onboarding calls it, and Phase 8's draft creation calls it as a
   * fallback for anyone who reaches the wizard without a profile.
   */
  getOrCreateProviderProfile(userId: string, businessName?: string): Promise<ProviderProfile> {
    return this.repo.getOrCreate(userId, businessName);
  }

  /**
   * Who may call: the signed-in user, for their own profile.
   *
   * **A read never creates.** An earlier pass called `getOrCreate` here, and
   * that made merely opening the screen turn a customer into a provider
   * permanently: `isProvider` on `userDto` is `providerProfile !== null`, and
   * §Phase 6's role switcher and §Phase 6a's "a provider who already
   * completed onboarding never sees it again" both route on it. Nothing is
   * ever hard-deleted (invariant 8), so the flip was irreversible. §1a names
   * the creation moments — Phase 6a's onboarding and the first
   * `POST /v1/listings` — and a GET is not one of them.
   */
  async readOwn(userId: string): Promise<OwnProviderDto> {
    const row = await this.repo.findByUserId(userId);
    if (row === null) {
      throw new NotFoundError('This account has no provider profile yet');
    }
    return toOwnProviderDto(row, await this.conductFor(row.id));
  }

  /**
   * Who may call: the signed-in user, for their own profile.
   *
   * The tier, the review status, §1g's ownership attribute, the subscription
   * price and the suspension columns are not in `UpdateOwnProviderBody`, so
   * this cannot write any of them — see the note in `schema.ts` for why each
   * one is somebody else's to set.
   *
   * **The write creates the profile where the read does not.** §Phase 6a's
   * account-details step is `getOrCreateProviderProfile` followed by this
   * endpoint, and a user sending a business name and bank details is
   * unambiguously acting as a provider — which is the implicit-creation
   * moment §1a describes. Merely opening a screen is not.
   *
   * **A change to the payment details is audited**, with field names and no
   * values. Phase 3 already audits self-service password, email and phone
   * changes; the destination account is the one self-service field with a
   * fraud pattern behind it — take a session, change where the money goes,
   * collect off-platform — and Phase 10a's receipt analysis checks a
   * submission against this account, so a dispute needs to be able to
   * establish when it changed. Nothing else here is audited: a bio edit is
   * not a security event.
   */
  async updateOwn(
    userId: string,
    body: UpdateOwnProviderBody,
    meta?: RequestMeta,
  ): Promise<OwnProviderDto> {
    await this.repo.getOrCreate(userId);
    const changedPaymentFields = PAYMENT_FIELDS.filter((f) => body[f] !== undefined);

    const row = await this.repo.transaction(async (tx) => {
      const updated = await this.repo.update(userId, withoutAbsentKeys(body), tx);
      if (changedPaymentFields.length > 0) {
        await this.audit.record(tx, {
          actorType: 'user',
          actorId: userId,
          action: 'provider.payment_details.changed',
          targetType: 'provider_profile',
          targetId: updated.id,
          reason: 'user_initiated',
          // Field names only. Root CLAUDE.md 1d: audit metadata references
          // IDs and enums, never a raw payment value.
          metadata: { changed: changedPaymentFields.join(', ') },
          ...(meta === undefined ? {} : { requestId: meta.requestId, ipAddress: meta.ip }),
        });
      }
      return updated;
    });
    return toOwnProviderDto(row, await this.conductFor(row.id));
  }

  /**
   * Who may call: anyone. **Applies §1a itself** — a provider with no
   * published listing, or a suspended one, is *not found* even by direct id,
   * which is §Phase 13's Done-when and the reason there is no empty public
   * profile to render.
   *
   * The gate is enforced here rather than left to the caller. An earlier pass
   * documented it as the consumer's job, and that is precisely the
   * per-consumer-remembers pattern §1a exists to remove: one of Phases 12,
   * 13, 15 and 16 would eventually have skipped it, and the failure mode is a
   * suspended provider rendering as bookable.
   *
   * There is no unchecked variant. `findVisibleProviders` below does not need
   * one — it already holds the rows it resolved and maps them directly — and
   * an unchecked mapper reachable by name is the hole this method just closed,
   * waiting to be reopened by the next caller in a hurry.
   *
   * Carries no phone number and no payment detail: `PublicProviderDto` has no
   * field for either.
   */
  async readPublic(providerId: string): Promise<PublicProviderDto> {
    if (!(await this.visibility.isVisible(providerId))) {
      throw new NotFoundError('No such provider');
    }
    const row = await this.repo.findById(providerId);
    if (row === null) throw new NotFoundError('No such provider');
    return toPublicProviderDto(row, await this.conductFor(row.id));
  }

  /**
   * §1a's single shared gate, re-exported so every consumer reaches it through
   * this service: search (Phase 15), Featured Providers (Phase 16) and the
   * public profile (Phase 13). None of them may reimplement the rule, and none
   * of them adds its own suspension filter — suspension is an input here.
   */
  async findVisibleProviders(
    filters: VisibleProviderFilters = {},
    paging: { limit?: number; cursor?: string } = {},
  ): Promise<{ items: PublicProviderDto[]; nextCursor: string | null }> {
    const page = await this.visibility.findVisibleProviders(filters, paging);
    const conduct = await this.conduct.metricsFor(page.items.map((p) => p.id));
    return {
      items: page.items.map((row) => toPublicProviderDto(row, conduct.get(row.id) ?? NO_CONDUCT)),
      nextCursor: page.nextCursor,
    };
  }

  /**
   * The provider's bank transfer details, for **a booking's payment step and
   * nothing else** (§1c, §Phase 5).
   *
   * Payment details are not contact information — a bank account number is not
   * a way to reach a person — and the off-platform transfer cannot happen
   * without them, which is why this one exception to the exclusion exists.
   * Phase 17 calls this from the payment step of a booking it has already
   * authorized the caller against; the booking-scoped check is Phase 17's,
   * because only Phase 17 can see a booking. This function deliberately takes
   * no viewer: it is not a route and must never become one.
   */
  async paymentDetailsForBooking(providerId: string): Promise<PaymentDetailsDto> {
    const row = await this.repo.findById(providerId);
    if (row === null) throw new NotFoundError('No such provider');
    return toPaymentDetailsDto(row);
  }

  /**
   * §Phase 5's `bookingMode` default lookup, read from Phase 4's seed and
   * **overridable per listing** (§1c) — Phase 8 stores the override on the
   * listing and falls back to this. Read, never hardcoded: an admin can change
   * a category's mode from Phase 10b.
   */
  async defaultBookingModeForCategory(categoryId: string): Promise<BookingMode> {
    // `repo.findById`, not the public list: a deactivated category is a
    // reversible soft delete (invariant 8), and a listing already in one still
    // needs its booking-mode default. Reading the active list only would make
    // this throw exactly when a category is retired — and it was N cursor
    // round trips plus an in-memory scan where this is one query.
    const category = await this.categories.repo.findById(categoryId);
    if (category === null) throw new NotFoundError('No such category');
    return category.bookingMode;
  }

  private async conductFor(providerId: string): Promise<ProviderConductRecord> {
    const found = await this.conduct.metricsFor([providerId]);
    return found.get(providerId) ?? NO_CONDUCT;
  }
}

/**
 * The four columns whose change is a security event. Kept beside the update so
 * a fifth payment field added later cannot be added without meeting this list.
 */
const PAYMENT_FIELDS = [
  'bankName',
  'bankAccountName',
  'bankAccountNumber',
  'transferInstructions',
] as const satisfies readonly (keyof UpdateOwnProviderBody)[];

/**
 * Drops keys the caller never sent. Under `exactOptionalPropertyTypes` a
 * present-but-undefined key is not the same as an absent one and Prisma's
 * update input rejects the former — the same note as `CategoryService`. An
 * explicit `null` survives, because clearing a field is a real edit.
 */
function withoutAbsentKeys(body: UpdateOwnProviderBody): Prisma.ProviderProfileUpdateInput {
  const data: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(body)) {
    if (value !== undefined) data[key] = value;
  }
  return data;
}
