import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, NotFoundError } from '../../core/errors.js';
import type {
  Category,
  Listing,
  ListingMedia,
  ListingVisibility,
  Prisma,
  PrismaClient,
  ProviderProfile,
} from '../../generated/prisma/client.js';
import { LocationRepository } from '../location/repository.js';
import { toIslandDto } from '../location/types.js';
import type { MediaService } from '../media/service.js';
import type { CategoryService } from '../categories/service.js';
import type { ProviderProfileService } from '../providers/service.js';
import {
  assertCallbackAllowed,
  assertEmergencyAllowed,
  emergencyEligibility,
} from './emergency.js';
import { FREE_TIER_ONLY, type ProviderEntitlementReader } from './entitlements.js';
import { ListingEvents } from './events.js';
import {
  assertPriceRangeOrdered,
  assertPricingAndModeAgree,
  missingRequiredFields,
} from './publish.js';
import { ListingRepository } from './repository.js';
import type { CreateListingBody, ListOwnListingsQuery, UpdateListingBody } from './schema.js';
import { toOwnListingDto, type OwnListingDto } from './types.js';

interface Deps {
  prisma: PrismaClient;
  providers: ProviderProfileService;
  categories: CategoryService;
  media: MediaService;
  clock: Clock;
  /** §Phase 8a replaces this with `getProviderEntitlements`; the callers do not change. */
  entitlements?: ProviderEntitlementReader;
}

/**
 * Service listings (§Phase 8).
 *
 * ## The two halves of invariant 2
 *
 * "Publishing a basic service listing must remain simple; advanced details
 * are always optional. **A draft must be saveable with zero required fields
 * filled. Only publish enforces required fields.**"
 *
 * So `create` and `update` validate *shape* and *claims* — is this a real
 * island, may this provider advertise emergency work, is this price unit one
 * the category offers — and never completeness. `publish` is the only method
 * that asks whether the listing is finished.
 *
 * ## What publish enforces, all in one place
 *
 * 1. The six required fields (`publish.ts`), as a structured missing list.
 * 2. The entitlement cap (`entitlements.ts`) — §Phase 8's own correction, v1
 *    checked it only at draft creation "so drafts made during a trial could
 *    all be published after downgrade".
 * 3. `pricingModel` vs `bookingMode` — `range` and `quote` force request mode.
 * 4. §1c's composed emergency rule, re-checked at the moment of going live.
 */
export class ListingService {
  readonly repo: ListingRepository;
  readonly events: ListingEvents;
  private readonly prisma: PrismaClient;
  private readonly providers: ProviderProfileService;
  private readonly categories: CategoryService;
  private readonly media: MediaService;
  private readonly locations: LocationRepository;
  private readonly clock: Clock;
  private readonly entitlements: ProviderEntitlementReader;

  constructor(deps: Deps) {
    this.prisma = deps.prisma;
    this.repo = new ListingRepository(deps.prisma);
    this.events = new ListingEvents(deps.prisma, deps.clock);
    this.providers = deps.providers;
    this.categories = deps.categories;
    this.media = deps.media;
    this.locations = new LocationRepository(deps.prisma);
    this.clock = deps.clock;
    this.entitlements = deps.entitlements ?? FREE_TIER_ONLY;
  }

  /**
   * Who may call: any signed-in, non-frozen user, for themselves.
   *
   * **Creates the provider profile implicitly** (§Phase 8, §1a): starting a
   * listing is acting as a provider, which is one of §1a's creation moments
   * alongside §Phase 6a's onboarding and `PATCH /v1/providers/me`. Idempotent
   * — `getOrCreateProviderProfile` is the shared one, so a customer who
   * reaches the wizard without onboarding gets exactly one profile.
   *
   * **No cap check here, deliberately.** §Phase 8 is explicit that checking
   * the cap at draft creation was v1's mistake, and the wizard's own
   * over-limit sheet fires at publish and says "This draft is saved and isn't
   * going anywhere". A provider on the free tier may hold any number of
   * drafts; what is capped is how many are live.
   */
  async createDraft(userId: string, body: CreateListingBody): Promise<OwnListingDto> {
    const profile = await this.providers.getOrCreateProviderProfile(userId);
    const category =
      body.categoryId === undefined ? null : await this.requireCategory(body.categoryId);
    const row = await this.repo.create({
      providerProfileId: profile.id,
      ...(category === null
        ? {}
        : // §1c: the mode is defaulted from the category seed and stays
          // provider-overridable from step 5.
          { categoryId: category.id, bookingMode: category.bookingMode }),
    });
    return this.present(row, profile);
  }

  /** Who may call: the owner. Not-found covers "not yours" as well, so ids cannot be probed. */
  async readOwn(userId: string, listingId: string): Promise<OwnListingDto> {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    return this.present(listing, profile);
  }

  /** Who may call: the owner, for their own listings. */
  async listOwn(
    userId: string,
    query: ListOwnListingsQuery,
  ): Promise<{ items: OwnListingDto[]; nextCursor: string | null }> {
    const profile = await this.providers.repo.findByUserId(userId);
    // A customer who has never acted as a provider has no listings, and a
    // read must not create the profile (§Phase 5's `readOwn` note).
    if (profile === null) return { items: [], nextCursor: null };

    const limit = query.limit ?? 20;
    const after = query.cursor === undefined ? null : decodeCursor(query.cursor);
    const rows = await this.repo.findOwnedPage(profile.id, limit, after, query.status);
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    return {
      items: await Promise.all(page.map((row) => this.present(row, profile))),
      nextCursor: rows.length > limit && last !== undefined ? encodeCursor(last) : null,
    };
  }

  /**
   * Who may call: the owner, for their own listing.
   *
   * One PATCH per wizard step, and a step may be half-filled. What is
   * checked is never completeness — see the class note — but three claims
   * that must not be storable even in a draft:
   *
   *   - an island id that is not a real, active island;
   *   - a media id that is not this listing's, or whose upload never finished;
   *   - `isEmergency` or the callback guarantee where §1c and Round 28 say no
   *     (§Phase 8: "enforced on publish **and update**").
   *
   * The pricing/booking-mode rule is checked here **only once the listing is
   * published**. On a draft the two fields are being filled in and a
   * transient disagreement between step 3 and step 5 is normal; on a live
   * listing it would mean a customer could reach a bookable slot at an
   * unknown price.
   */
  async updateOwn(
    userId: string,
    listingId: string,
    body: UpdateListingBody,
  ): Promise<OwnListingDto> {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    const now = this.clock();

    // The category after this patch — the one every rule below reads.
    const categoryId = body.categoryId === undefined ? listing.categoryId : body.categoryId;
    const category = categoryId === null ? null : await this.requireCategory(categoryId);

    const data: Prisma.ListingUncheckedUpdateInput = {};
    for (const [key, value] of Object.entries(body)) {
      if (value === undefined) continue;
      if (key === 'serviceAreaIslandIds' || key === 'galleryMediaIds') continue;
      data[key as keyof Prisma.ListingUncheckedUpdateInput] = value as never;
    }

    // Changing the category re-defaults the booking mode, unless the same
    // patch sets it. Step 5's radio is what overrides it after that; leaving
    // the old category's default behind would silently keep a slot-mode
    // listing in a request-only trade.
    if (body.categoryId !== undefined && body.bookingMode === undefined) {
      data.bookingMode = category?.bookingMode ?? null;
    }

    const nextMode = (data.bookingMode ?? listing.bookingMode) as Listing['bookingMode'];
    const nextModel = (data.pricingModel ?? listing.pricingModel) as Listing['pricingModel'];

    assertPriceRangeOrdered(
      body.priceMinLaari === undefined ? listing.priceMinLaari : body.priceMinLaari,
      body.priceMaxLaari === undefined ? listing.priceMaxLaari : body.priceMaxLaari,
    );
    if (listing.status === 'published') {
      assertPricingAndModeAgree(nextModel, nextMode);
    }
    if (body.isEmergency === true) {
      assertEmergencyAllowed({
        category: requireCategoryFor(category, 'isEmergency'),
        providerTier: profile.verificationTier,
      });
    }
    if (body.callbackGuaranteeOffered === true) {
      assertCallbackAllowed(requireCategoryFor(category, 'callbackGuaranteeOffered'));
    }
    // A category change can invalidate claims made under the previous one —
    // an emergency Electrical listing re-pointed at Cleaning, say. Cleared
    // rather than refused: the provider is mid-edit and the claim, not the
    // category choice, is the thing that has stopped being true.
    if (body.categoryId !== undefined) {
      const emergencyStillOk =
        (data.isEmergency ?? listing.isEmergency) === false ||
        (category !== null &&
          emergencyEligibility({ category, providerTier: profile.verificationTier }).eligible);
      if (!emergencyStillOk) data.isEmergency = false;
      const callbackStillOk =
        (data.callbackGuaranteeOffered ?? listing.callbackGuaranteeOffered) === false ||
        category?.callbackEligible === true;
      if (!callbackStillOk) data.callbackGuaranteeOffered = false;
    }

    if (body.serviceAreaIslandIds !== undefined) {
      await this.assertIslandsExist(body.serviceAreaIslandIds);
    }
    if (body.coverMediaId !== undefined && body.coverMediaId !== null) {
      await this.assertRenderableMedia(listing.id, body.coverMediaId, 'coverMediaId');
    }
    if (body.galleryMediaIds !== undefined) {
      for (const id of body.galleryMediaIds) {
        await this.assertRenderableMedia(listing.id, id, 'galleryMediaIds');
      }
    }

    const updated = await this.repo.transaction(async (tx) => {
      if (body.serviceAreaIslandIds !== undefined) {
        await this.repo.replaceServiceAreas(listing.id, body.serviceAreaIslandIds, now, tx);
      }
      if (body.galleryMediaIds !== undefined) {
        await this.setGalleryOrder(listing.id, body.galleryMediaIds, tx);
      }
      return this.repo.update(listing.id, data, tx);
    });
    return this.present(updated, profile);
  }

  /**
   * Who may call: the owner, for their own listing.
   *
   * The gate §Phase 8 describes, in the order a provider can act on: what is
   * missing first (they can fix it), then the rules that would make the
   * listing incoherent, then the cap (which they cannot fix by editing).
   */
  async publish(userId: string, listingId: string): Promise<OwnListingDto> {
    const { listing, profile } = await this.ownedOr404(userId, listingId);

    const serviceAreaCount = await this.repo.countServiceAreas(listing.id);
    const cover = await this.repo.findCover(listing.coverMediaId);
    const category =
      listing.categoryId === null ? null : await this.requireCategory(listing.categoryId);
    const missing = missingRequiredFields({
      listing,
      serviceAreaCount,
      coverIsStored: isRenderable(cover),
    });
    if (missing.length > 0) {
      throw new BusinessRuleError(
        'LISTING_INCOMPLETE',
        missing.length === 1
          ? 'One required field is still empty'
          : `${String(missing.length)} required fields are still empty`,
        // The structured list §Phase 8 asks for, carrying the wizard step so
        // the review screen's Fix link knows where to send the provider.
        missing,
      );
    }

    // Unreachable: a null category is one of the six, so the throw above
    // already fired. Written as the same refusal rather than a cast, because
    // a cast here would be the one place this method could proceed without a
    // category if the required-field list ever changed.
    if (category === null) {
      throw new BusinessRuleError('LISTING_INCOMPLETE', 'One required field is still empty', [
        { field: 'categoryId', step: 'details', message: 'Category' },
      ]);
    }
    assertPricingAndModeAgree(listing.pricingModel, listing.bookingMode);
    if (listing.isEmergency) {
      assertEmergencyAllowed({ category, providerTier: profile.verificationTier });
    }
    if (listing.callbackGuaranteeOffered) {
      assertCallbackAllowed(category);
    }
    await this.assertWithinCap(profile.id, listing.id);

    const now = this.clock();
    const updated = await this.repo.update(listing.id, {
      status: 'published',
      // Publishing a listing the provider had hidden brings it back into
      // view; §1b's other two hidden values are not this endpoint's to clear.
      visibility: listing.visibility === 'hidden_by_provider' ? 'active' : listing.visibility,
      publishedAt: now,
      firstPublishedAt: listing.firstPublishedAt ?? now,
    });
    return this.present(updated, profile);
  }

  /**
   * Who may call: the owner, for their own listing.
   *
   * §1b, Round 17: the provider may set `active` or `hidden_by_provider` and
   * nothing else. `hidden_over_cap` is the entitlement system's and
   * `hidden_by_admin` is moderation's — the Zod enum is what enforces that,
   * so this method never has to.
   *
   * **Coming back to `active` re-checks the cap**, and it has to: a provider
   * at the cap who hid one listing and published another would otherwise
   * un-hide the first and hold two live. Publish is not the only door into
   * the visible set.
   */
  async setVisibility(
    userId: string,
    listingId: string,
    visibility: Extract<ListingVisibility, 'active' | 'hidden_by_provider'>,
  ): Promise<OwnListingDto> {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    if (visibility === 'active' && listing.status === 'published') {
      await this.assertWithinCap(profile.id, listing.id);
    }
    const updated = await this.repo.update(listing.id, { visibility });
    return this.present(updated, profile);
  }

  /**
   * Who may call: the owner, for their own listing.
   *
   * Invariant 8: soft delete, and nothing cascades. The row stays, its media
   * stays in the store, its service areas stay, and its event log stays —
   * a booking or a review that referenced this listing must still resolve.
   * What changes is that `deletedAt` drops it out of
   * `PUBLICLY_VISIBLE_LISTING`, so it leaves every public query and stops
   * counting toward §1a's provider visibility in the same moment.
   *
   * `docs/decisions/21-phase-8-service-listings.md` documents the cascade
   * rules for bookings, reviews and reserved slots, which §Phase 8 asks for
   * and which no phase can yet enforce.
   */
  async softDelete(userId: string, listingId: string): Promise<OwnListingDto> {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    const updated = await this.repo.update(listing.id, { deletedAt: this.clock() });
    return this.present(updated, profile);
  }

  // -------------------------------------------------------------------------
  // Media
  // -------------------------------------------------------------------------

  /**
   * Who may call: the owner, for their own listing. Step 1 of the three-step
   * upload — the row is created here so the object key is the server's.
   */
  async createMediaUpload(userId: string, listingId: string, contentType: string) {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    const issued = this.media.issueUploadTarget('listing-media', contentType);
    const row = await this.repo.createMedia({
      listingId: listing.id,
      objectKey: issued.objectKey,
      contentType,
    });
    return { media: row, target: issued.target, profile };
  }

  /**
   * Who may call: the owner. Step 3 — the bytes are read back, sniffed,
   * size-checked, EXIF-stripped and rewritten (`MediaService.finalise`), and
   * only then does the row become `stored`.
   *
   * A row that never reaches `stored` can never become a cover: the publish
   * gate treats a pending cover as a missing one, which is what stops an
   * abandoned upload satisfying the field §0.2 added to prevent a blank
   * thumbnail.
   */
  async finaliseMedia(userId: string, listingId: string, mediaId: string) {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    const row = await this.repo.findMedia(listing.id, mediaId);
    if (row === null) throw new NotFoundError('No such image');

    const finalised = await this.media.finalise(row.objectKey, row.contentType);
    const updated = await this.repo.updateMedia(row.id, {
      status: 'stored',
      byteSize: finalised.byteSize,
      storedAt: this.clock(),
    });
    return { media: updated, profile };
  }

  /**
   * Who may call: the owner. Invariant 8 — the row is stamped, the object
   * stays. Removing the cover clears `coverMediaId`, which makes the listing
   * incomplete again; it does **not** unpublish it, because a listing losing
   * its picture is a thing to fix rather than a reason to take a live service
   * away from a customer mid-booking.
   */
  async removeMedia(userId: string, listingId: string, mediaId: string): Promise<OwnListingDto> {
    const { listing, profile } = await this.ownedOr404(userId, listingId);
    const row = await this.repo.findMedia(listing.id, mediaId);
    if (row === null) throw new NotFoundError('No such image');
    const now = this.clock();
    const updated = await this.repo.transaction(async (tx) => {
      await this.repo.updateMedia(row.id, { removedAt: now, sortOrder: null }, tx);
      return listing.coverMediaId === row.id
        ? this.repo.update(listing.id, { coverMediaId: null }, tx)
        : listing;
    });
    return this.present(updated, profile);
  }

  // -------------------------------------------------------------------------
  // §1c, Round 17 — a downward tier change re-evaluates published listings
  // -------------------------------------------------------------------------

  /**
   * Clears `isEmergency` on every published listing this provider no longer
   * meets the bar for, and returns the ones it changed.
   *
   * > A downward tier change re-evaluates published emergency listings —
   * > Round 17. §1e handled revocation for *live bookings* but said nothing
   * > about the *listing*, leaving a gold provider demoted to silver still
   * > advertising emergency Electrical work behind a credential they no
   * > longer hold.
   *
   * **Who calls it:** the phase that can change a tier, which is §Phase 10a's
   * verification queue. It does not exist yet, so nothing in this phase calls
   * this from a route — the rule lives here because it is a rule about
   * listings, and the alternative is Phase 10a writing a second copy of the
   * emergency gate. Ledger row **P8-3** carries the wiring.
   *
   * Upward changes are deliberately not handled: §1c says "upward changes
   * never auto-enable — the provider opts in".
   */
  async reevaluateEmergencyEligibility(providerProfileId: string): Promise<Listing[]> {
    const profile = await this.providers.repo.findById(providerProfileId);
    if (profile === null) throw new NotFoundError('No such provider');

    const cleared: Listing[] = [];
    for (const listing of await this.repo.findPublishedEmergency(providerProfileId)) {
      if (listing.category === null) continue;
      const verdict = emergencyEligibility({
        category: listing.category,
        providerTier: profile.verificationTier,
      });
      if (verdict.eligible) continue;
      cleared.push(await this.repo.update(listing.id, { isEmergency: false }));
    }
    return cleared;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /**
   * Authorization for every method above, in one place. Answers not-found
   * for a listing that does not exist, one owned by somebody else, and one
   * already soft-deleted — the same answer for all three, so the endpoint
   * cannot be used to learn which listing ids are real.
   */
  private async ownedOr404(
    userId: string,
    listingId: string,
  ): Promise<{ listing: Listing; profile: ProviderProfile }> {
    const profile = await this.providers.repo.findByUserId(userId);
    if (profile === null) throw new NotFoundError('No such listing');
    const listing = await this.repo.findOwned(listingId, profile.id);
    if (listing === null) throw new NotFoundError('No such listing');
    return { listing, profile };
  }

  /**
   * §1b's cap, read through the seam §Phase 8a fills.
   *
   * The message names the listing already live, because that is the choice
   * the provider actually has — the wizard's own sheet says "Emergency
   * Plumbing & Pipe Repair is already live… upgrading lets you publish
   * several services side by side, or you can swap which one is live".
   */
  private async assertWithinCap(providerProfileId: string, excludeId: string): Promise<void> {
    const cap = await this.entitlements.activeListingCap(providerProfileId);
    const active = await this.repo.countActive(providerProfileId, excludeId);
    if (active < cap) return;
    const live = await this.repo.findActive(providerProfileId, excludeId);
    throw new BusinessRuleError(
      'LISTING_CAP_REACHED',
      cap === 1
        ? 'Your plan publishes one service at a time'
        : `Your plan publishes ${String(cap)} services at a time`,
      {
        activeListingCap: cap,
        activeListingCount: active,
        liveListings: live.map((row) => ({ id: row.id, name: row.name })),
      },
    );
  }

  private async requireCategory(categoryId: string): Promise<Category> {
    // `repo.findById`, not the public active list: a deactivated category is
    // a reversible soft delete (invariant 8) and a listing already in one
    // still has to be readable and editable. §Phase 5's
    // `defaultBookingModeForCategory` reads it the same way and for the same
    // reason.
    const row = await this.categories.repo.findById(categoryId);
    if (row === null) throw new NotFoundError('No such category', 'CATEGORY_NOT_FOUND');
    return row;
  }

  /**
   * §0.0 item 12: an island is addressed by UUID and never by name. This
   * checks the ids are real and active before they are stored, so a typo
   * fails at the step the provider is on rather than at publish.
   */
  private async assertIslandsExist(islandIds: string[]): Promise<void> {
    if (islandIds.length === 0) return;
    const found = await this.prisma.island.findMany({
      where: { id: { in: islandIds }, isActive: true },
      select: { id: true },
    });
    const known = new Set(found.map((row) => row.id));
    const unknown = islandIds.filter((id) => !known.has(id));
    if (unknown.length === 0) return;
    throw new BusinessRuleError(
      'ISLAND_NOT_FOUND',
      'One of those islands is not in the register',
      unknown.map((id) => ({ path: 'serviceAreaIslandIds', message: id })),
    );
  }

  /**
   * The image exists, belongs to this listing, has really been uploaded, and
   * is not one moderation has hidden.
   *
   * The last clause matters on its own: §Phase 22 can hide a single reported
   * photo, and a provider must not be able to answer that by promoting it to
   * their cover — which would put it back on every card and in every search
   * result, the most visible place it could be.
   */
  private async assertRenderableMedia(
    listingId: string,
    mediaId: string,
    path: string,
  ): Promise<void> {
    const row = await this.repo.findMedia(listingId, mediaId);
    if (row === null) {
      throw new BusinessRuleError('MEDIA_NOT_FOUND', 'That image does not belong to this listing', [
        { path, message: mediaId },
      ]);
    }
    if (row.status !== 'stored') {
      throw new BusinessRuleError('MEDIA_NOT_UPLOADED', 'That upload has not finished', [
        { path, message: mediaId },
      ]);
    }
    if (row.hiddenByAdminAt !== null) {
      throw new BusinessRuleError('MEDIA_HIDDEN_BY_ADMIN', 'That image has been hidden by review', [
        { path, message: mediaId },
      ]);
    }
  }

  /** The gallery is the given order; the cover is named separately and is never a gallery slot. */
  private async setGalleryOrder(
    listingId: string,
    mediaIds: string[],
    tx: Prisma.TransactionClient,
  ): Promise<void> {
    const wanted = new Set(mediaIds);
    // Anything dropped from the gallery keeps its row and its bytes — it is
    // out of the gallery, not deleted (invariant 8). `DELETE` here would be
    // the one place in this module that hard-removes something.
    await tx.listingMedia.updateMany({
      where: { listingId, removedAt: null, id: { notIn: [...wanted] } },
      data: { sortOrder: null },
    });
    for (const [index, id] of mediaIds.entries()) {
      await tx.listingMedia.update({ where: { id }, data: { sortOrder: index } });
    }
  }

  /**
   * Builds the wire shape. Loads the listing's own service areas, its media
   * and its category, and asks the two gates for their current answer so the
   * client renders the server's reason rather than its own.
   */
  private async present(listing: Listing, profile: ProviderProfile): Promise<OwnListingDto> {
    const category =
      listing.categoryId === null ? null : await this.categories.repo.findById(listing.categoryId);
    const areas = await this.repo.findServiceAreas(listing.id);
    const cover = await this.repo.findCover(listing.coverMediaId);
    const gallery = (await this.repo.findGallery(listing.id)).filter(
      (row) => row.id !== listing.coverMediaId,
    );

    const emergency =
      category === null
        ? ({
            eligible: false,
            code: 'EMERGENCY_CATEGORY_NOT_CAPABLE',
            message: 'Choose a category first',
          } as const)
        : emergencyEligibility({ category, providerTier: profile.verificationTier });

    return toOwnListingDto({
      listing,
      serviceAreas: areas.map((row) => toIslandDto(row.island)),
      cover,
      gallery,
      emergency,
      providerTier: profile.verificationTier,
      requiredTier: category?.emergencyMinimumTier ?? null,
      callbackAvailable: category?.callbackEligible ?? false,
      missingRequiredFields: missingRequiredFields({
        listing,
        serviceAreaCount: areas.length,
        coverIsStored: isRenderable(cover),
      }),
      mediaUrl: (objectKey) => this.media.readUrl(objectKey),
    });
  }
}

/**
 * Whether a cover image is one a customer would actually see: uploaded,
 * still there, and not hidden by moderation.
 *
 * A listing whose cover has been hidden by §Phase 22 becomes **incomplete**
 * again rather than publishing with a blank thumbnail — which is the whole
 * reason §0.2 item 4 made the cover a required field.
 */
function isRenderable(media: ListingMedia | null): boolean {
  return (
    media !== null &&
    media.status === 'stored' &&
    media.removedAt === null &&
    media.hiddenByAdminAt === null
  );
}

/**
 * Every one of these rules is a fact *about a category*, so setting one
 * before choosing a category is not a thing that can be answered — refused
 * rather than silently allowed, which would store a claim nothing had checked.
 */
function requireCategoryFor(category: Category | null, path: string): Category {
  if (category !== null) return category;
  throw new BusinessRuleError('CATEGORY_REQUIRED', 'Choose a category first', [
    { path, message: 'Needs a category' },
  ]);
}

/** Keyed on the pair the page is ordered by, so a cursor cannot skip or repeat a row. */
function encodeCursor(row: Listing): string {
  return Buffer.from(`${row.updatedAt.toISOString()}|${row.id}`, 'utf8').toString('base64url');
}

/** A malformed cursor reads as the first page rather than a 500 — the same rule §Phase 5 applies. */
function decodeCursor(cursor: string): { updatedAt: Date; id: string } | null {
  const [at, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  if (at === undefined || id === undefined || !UUID.test(id)) return null;
  const updatedAt = new Date(at);
  return Number.isNaN(updatedAt.getTime()) ? null : { updatedAt, id };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
