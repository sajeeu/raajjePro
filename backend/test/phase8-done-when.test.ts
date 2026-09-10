import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { FREE_TIER_ACTIVE_LISTING_CAP } from '../src/modules/listings/entitlements.js';
import { PUBLICLY_VISIBLE_LISTING } from '../src/modules/listings/visibility.js';
import type { OwnListingDto } from '../src/modules/listings/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { ensureIslandsSeeded, islandByName } from './helpers/islands.js';
import {
  BASE,
  categoryByName,
  completeDraft,
  createDraft,
  ensureCategoriesSeeded,
  patchDraft,
  publish,
  uploadImage,
} from './helpers/listings.js';
import { registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface ErrorEnvelope {
  error: { code: string; message: string; details?: unknown };
}

/**
 * §Phase 8's own Done-when list, one describe per clause:
 *
 *   1. a listing saves empty
 *   2. patches per step
 *   3. publishes only when complete and within cap
 *   4. `isEmergency` is rejected on a non-emergency category, and rejected
 *      for a **silver provider on Electrical** while accepted for that same
 *      provider on **AC Repair**
 *   5. a soft-deleted listing disappears from public queries while its
 *      bookings and reviews remain intact
 *
 * Clause 5 has a half nothing can assert yet: there is no `Booking` and no
 * `Review` until §Phase 17 and §Phase 11. The public-query half is real and
 * runs here against `findVisibleProviders` and the shared predicate;
 * `docs/deferred-verification.md` row **P8-2** carries the rest.
 */
describe.skipIf(databaseUrl === undefined)('§Phase 8 Done-when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let provider: Awaited<ReturnType<typeof registerUser>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await ensureCategoriesSeeded(app.deps.prisma);
    await ensureIslandsSeeded(app.deps.prisma);
    provider = await registerUser(app, { role: 'provider' });
  });

  afterAll(async () => {
    await app.close();
  });

  // -------------------------------------------------------------------------

  describe('a listing saves empty', () => {
    it('accepts a completely empty body and stores a draft with nothing filled in', async () => {
      // Invariant 2, and the reason almost every column on `Listing` is
      // nullable: "a draft must be saveable with zero required fields
      // filled". A NOT NULL anywhere in that list would make this impossible.
      const draft = await createDraft(app, provider.headers, {});

      expect(draft.status).toBe('draft');
      expect(draft.name).toBeNull();
      expect(draft.categoryId).toBeNull();
      expect(draft.shortDescription).toBeNull();
      expect(draft.pricingModel).toBeNull();
      expect(draft.coverMedia).toBeNull();
      expect(draft.serviceAreas).toEqual([]);
      // All six are reported as outstanding, which is what §Phase 9's
      // "N required fields left to publish" counts.
      expect(draft.requiredFieldCount).toBe(6);
      expect(draft.missingRequiredFields.map((f) => f.field)).toEqual([
        'name',
        'categoryId',
        'shortDescription',
        'serviceAreaIslandIds',
        'pricingModel',
        'coverMediaId',
      ]);
    });

    it('creates the provider profile implicitly for a customer who never onboarded', async () => {
      // §1a's third creation moment: starting a listing is acting as a
      // provider. A customer account reaching the wizard without onboarding
      // must not 404.
      const customer = await registerUser(app, { role: 'customer' });
      expect(
        await app.deps.prisma.providerProfile.count({ where: { userId: customer.userId } }),
      ).toBe(0);

      await createDraft(app, customer.headers, {});

      const profiles = await app.deps.prisma.providerProfile.count({
        where: { userId: customer.userId },
      });
      expect(profiles).toBe(1);

      // And exactly one, however many drafts follow.
      await createDraft(app, customer.headers, {});
      expect(
        await app.deps.prisma.providerProfile.count({ where: { userId: customer.userId } }),
      ).toBe(1);
    });

    it('requires an idempotency key and replays rather than making a second draft', async () => {
      // §Phase 8 names the key on draft-save specifically. Without it, a
      // double tap on a weak connection leaves two empty drafts in My
      // Services and the wizard resumes into whichever it last saw.
      const noKey = await app.inject({
        method: 'POST',
        url: BASE,
        headers: provider.headers,
        remoteAddress: freshIp(),
        payload: {},
      });
      expect(noKey.statusCode).toBe(400);
      expect(noKey.json<ErrorEnvelope>().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');

      const key = randomUUID();
      const send = () =>
        app.inject({
          method: 'POST',
          url: BASE,
          headers: { ...provider.headers, 'idempotency-key': key },
          remoteAddress: freshIp(),
          payload: {},
        });
      const first = await send();
      const second = await send();
      expect(first.statusCode).toBe(201);
      expect(second.statusCode).toBe(201);
      expect(second.json<Envelope<OwnListingDto>>().data.id).toBe(
        first.json<Envelope<OwnListingDto>>().data.id,
      );
    });
  });

  // -------------------------------------------------------------------------

  describe('it patches per step', () => {
    it('takes one wizard step at a time and keeps the rest untouched', async () => {
      const cleaning = await categoryByName(app.deps.prisma, 'Cleaning');
      const male = await islandByName(app.deps.prisma, 'K', "Male'");
      const draft = await createDraft(app, provider.headers, {});

      // Step 1 — Details.
      const step1 = await patchDraft(app, provider.headers, draft.id, {
        categoryId: cleaning.id,
        name: 'Deep clean, two bedrooms',
        shortDescription: 'Kitchen, bathrooms and floors, three hours.',
        tags: ['Deep cleaning', 'Move-out'],
      });
      expect(step1.statusCode).toBe(200);
      const afterOne = step1.json<Envelope<OwnListingDto>>().data;
      expect(afterOne.name).toBe('Deep clean, two bedrooms');
      expect(afterOne.tags).toEqual(['Deep cleaning', 'Move-out']);
      // §1c: the mode is defaulted from the category seed, not asked for.
      expect(afterOne.bookingMode).toBe(cleaning.bookingMode);
      expect(afterOne.missingRequiredFields.map((f) => f.field)).toEqual([
        'serviceAreaIslandIds',
        'pricingModel',
        'coverMediaId',
      ]);

      // Step 2 — Location. The listing's own areas (ledger P7-3).
      const step2 = await patchDraft(app, provider.headers, draft.id, {
        serviceAreaIslandIds: [male.id],
      });
      expect(step2.statusCode).toBe(200);
      const afterTwo = step2.json<Envelope<OwnListingDto>>().data;
      expect(afterTwo.serviceAreas.map((i) => i.id)).toEqual([male.id]);
      // Step 1's values survived a patch that never mentioned them.
      expect(afterTwo.name).toBe('Deep clean, two bedrooms');
      expect(afterTwo.tags).toEqual(['Deep cleaning', 'Move-out']);

      // Step 3 — Pricing. Integer laari, never a float (invariant 7).
      const step3 = await patchDraft(app, provider.headers, draft.id, {
        pricingModel: 'fixed',
        priceLaari: 45_000,
        priceUnit: 'session',
      });
      expect(step3.statusCode).toBe(200);
      expect(step3.json<Envelope<OwnListingDto>>().data.priceLaari).toBe(45_000);

      // Step 6 — Extra info. §1i, and none of it gates publish.
      const step6 = await patchDraft(app, provider.headers, draft.id, {
        whatsIncluded: 'Products and equipment',
        faqs: [{ question: 'Do you supply materials?', answer: 'Yes.' }],
        warrantyOffered: true,
        warrantyTermsText: '48-hour re-clean if anything is missed',
      });
      expect(step6.statusCode).toBe(200);
      const afterSix = step6.json<Envelope<OwnListingDto>>().data;
      expect(afterSix.faqs).toEqual([{ question: 'Do you supply materials?', answer: 'Yes.' }]);
      expect(afterSix.selfDeclared.warrantyOffered).toBe(true);
      expect(afterSix.selfDeclared.warrantyTermsText).toBe(
        '48-hour re-clean if anything is missed',
      );
      // Only the cover is left — none of step 6 was ever required.
      expect(afterSix.missingRequiredFields.map((f) => f.field)).toEqual(['coverMediaId']);
    });

    it('rejects a float price rather than rounding it', async () => {
      // Invariant 7: money is integer laari end to end. A client that had
      // been doing MVR arithmetic sends 450.5, and silently truncating it
      // would store a price nobody chose.
      const draft = await createDraft(app, provider.headers, {});
      const res = await patchDraft(app, provider.headers, draft.id, { priceLaari: 450.5 });
      expect(res.statusCode).toBe(400);
      expect(res.json<ErrorEnvelope>().error.code).toBe('VALIDATION_FAILED');
    });

    it('replaces the island set, soft-deleting what is dropped and reviving what returns', async () => {
      const male = await islandByName(app.deps.prisma, 'K', "Male'");
      const hulhumale = await islandByName(app.deps.prisma, 'K', "Hulhumale'");
      const draft = await createDraft(app, provider.headers, {});

      await patchDraft(app, provider.headers, draft.id, {
        serviceAreaIslandIds: [male.id, hulhumale.id],
      });
      const narrowed = await patchDraft(app, provider.headers, draft.id, {
        serviceAreaIslandIds: [male.id],
      });
      expect(narrowed.json<Envelope<OwnListingDto>>().data.serviceAreas.map((i) => i.id)).toEqual([
        male.id,
      ]);

      // Invariant 8: the dropped island keeps its row, stamped.
      const dropped = await app.deps.prisma.listingServiceArea.findUnique({
        where: { listingId_islandId: { listingId: draft.id, islandId: hulhumale.id } },
      });
      expect(dropped?.removedAt).not.toBeNull();

      // Re-adding revives the same row rather than creating a second.
      await patchDraft(app, provider.headers, draft.id, {
        serviceAreaIslandIds: [male.id, hulhumale.id],
      });
      const revived = await app.deps.prisma.listingServiceArea.findUnique({
        where: { listingId_islandId: { listingId: draft.id, islandId: hulhumale.id } },
      });
      expect(revived?.removedAt).toBeNull();
      expect(revived?.id).toBe(dropped?.id);
    });

    it('refuses an island that is not in the register, before publish', async () => {
      // §0.0 item 12: an island is a UUID and nothing matches on a name. A
      // typo'd id must fail on the step the provider is on rather than at
      // publish, three steps later.
      const draft = await createDraft(app, provider.headers, {});
      const res = await patchDraft(app, provider.headers, draft.id, {
        serviceAreaIslandIds: [randomUUID()],
      });
      expect(res.statusCode).toBe(422);
      expect(res.json<ErrorEnvelope>().error.code).toBe('ISLAND_NOT_FOUND');
    });

    it("answers not-found for another provider's listing", async () => {
      const stranger = await registerUser(app, { role: 'provider' });
      const mine = await createDraft(app, provider.headers, {});

      const read = await app.inject({
        method: 'GET',
        url: `${BASE}/${mine.id}`,
        headers: stranger.headers,
        remoteAddress: freshIp(),
      });
      const write = await patchDraft(app, stranger.headers, mine.id, { name: 'Taken over' });

      // Not 403: "not yours" and "does not exist" answer the same thing, so
      // the endpoint cannot be used to discover which listing ids are real.
      expect(read.statusCode).toBe(404);
      expect(write.statusCode).toBe(404);
    });
  });

  // -------------------------------------------------------------------------

  describe('it publishes only when complete', () => {
    it('refuses an incomplete draft with the structured missing-field list', async () => {
      const draft = await createDraft(app, provider.headers, {});
      const res = await publish(app, provider.headers, draft.id);

      expect(res.statusCode).toBe(422);
      const body = res.json<ErrorEnvelope>().error;
      expect(body.code).toBe('LISTING_INCOMPLETE');
      // A list, not the first failure — §Phase 9's review step renders every
      // one at once with a Fix link each, and stopping at the first would
      // make publishing a six-round-trip guessing game.
      const details = body.details as { field: string; step: string }[];
      expect(details).toHaveLength(6);
      expect(details.map((d) => d.field)).toContain('coverMediaId');
      // Each one names the wizard step it belongs to, so Fix knows where to go.
      expect(new Set(details.map((d) => d.step))).toEqual(
        new Set(['details', 'location', 'pricing', 'media']),
      );
    });

    it('still refuses when only the cover image is missing', async () => {
      // 🔧 Six required fields, not five (§0.2 item 4). v4 left the cover
      // optional, which meant a listing could go live with a blank thumbnail
      // on every card and in every search result.
      const male = await islandByName(app.deps.prisma, 'K', "Male'");
      const cleaning = await categoryByName(app.deps.prisma, 'Cleaning');
      const draft = await createDraft(app, provider.headers, { categoryId: cleaning.id });
      await patchDraft(app, provider.headers, draft.id, {
        name: 'Regular home clean',
        shortDescription: 'Weekly visit, two hours.',
        serviceAreaIslandIds: [male.id],
        pricingModel: 'fixed',
        priceLaari: 30_000,
      });

      const res = await publish(app, provider.headers, draft.id);
      expect(res.statusCode).toBe(422);
      const details = res.json<ErrorEnvelope>().error.details as { field: string }[];
      expect(details.map((d) => d.field)).toEqual(['coverMediaId']);
    });

    it('does not accept an abandoned upload as a cover', async () => {
      // A media row exists from the moment a target is issued. If a pending
      // row satisfied the cover field, the one check §0.2 added to stop a
      // blank thumbnail would be satisfied by an upload that never happened.
      const cleaning = await categoryByName(app.deps.prisma, 'Cleaning');
      const male = await islandByName(app.deps.prisma, 'K', "Male'");
      const draft = await createDraft(app, provider.headers, { categoryId: cleaning.id });

      const created = await app.inject({
        method: 'POST',
        url: `${BASE}/${draft.id}/media`,
        headers: { ...provider.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { contentType: 'image/jpeg' },
      });
      const pendingId = created.json<Envelope<{ media: { id: string } }>>().data.media.id;

      // The PATCH refuses it outright — the provider learns on the media step.
      const patched = await patchDraft(app, provider.headers, draft.id, {
        name: 'Regular home clean',
        shortDescription: 'Weekly visit.',
        serviceAreaIslandIds: [male.id],
        pricingModel: 'fixed',
        priceLaari: 30_000,
        coverMediaId: pendingId,
      });
      expect(patched.statusCode).toBe(422);
      expect(patched.json<ErrorEnvelope>().error.code).toBe('MEDIA_NOT_UPLOADED');
    });

    it('publishes a complete draft, and the cover survives with its metadata gone', async () => {
      const owner = await registerUser(app, { role: 'provider' });
      const complete = await completeDraft(app, owner.headers);
      expect(complete.missingRequiredFields).toEqual([]);

      const res = await publish(app, owner.headers, complete.id);
      expect(res.statusCode).toBe(200);
      const live = res.json<Envelope<OwnListingDto>>().data;
      expect(live.status).toBe('published');
      expect(live.visibility).toBe('active');
      expect(live.publishedAt).not.toBeNull();
      expect(live.firstPublishedAt).toBe(live.publishedAt);
      expect(live.coverMedia?.status).toBe('stored');
      expect(live.coverMedia?.url).not.toBeNull();
    });

    it('refuses a slot-mode listing priced by range or on request, naming both fields', async () => {
      // §Phase 8, Round 16. Not a style preference: §1c requires
      // `agreedAmount` at `accepted`, so a slot-mode listing priced `quote`
      // is unrepresentable — the customer would be booking a fixed time at an
      // unknown price.
      // A fresh provider: the shared one already holds a live listing, and
      // the free-tier cap would answer first.
      const owner = await registerUser(app, { role: 'provider' });
      const complete = await completeDraft(app, owner.headers);
      // Cleaning is a slot category, so this listing is already slot-mode.
      expect(complete.bookingMode).toBe('slot');
      await patchDraft(app, owner.headers, complete.id, {
        pricingModel: 'quote',
        priceLaari: null,
      });

      const res = await publish(app, owner.headers, complete.id);
      expect(res.statusCode).toBe(422);
      const error = res.json<ErrorEnvelope>().error;
      expect(error.code).toBe('PRICING_MODEL_REQUIRES_REQUEST_MODE');
      const paths = (error.details as { path: string }[]).map((d) => d.path);
      expect(paths).toEqual(['pricingModel', 'bookingMode']);

      // Switching to request mode is the fix, and it publishes — `quote`
      // needs no price, so nothing else was missing.
      await patchDraft(app, owner.headers, complete.id, { bookingMode: 'request' });
      expect((await publish(app, owner.headers, complete.id)).statusCode).toBe(200);
    });

    it('lets fixed, hourly and daily take either mode', async () => {
      const owner = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, owner.headers);
      await patchDraft(app, owner.headers, draft.id, {
        pricingModel: 'hourly',
        priceLaari: 20_000,
        bookingMode: 'slot',
      });
      expect((await publish(app, owner.headers, draft.id)).statusCode).toBe(200);
    });
  });

  // -------------------------------------------------------------------------

  describe('…and within cap', () => {
    it('refuses a second live listing on the free tier and names the one already live', async () => {
      // §1b's free tier is 1 active listing, read through the seam §Phase 8a
      // fills. The message names the live listing because that is the choice
      // the provider actually has — the wizard's sheet says "Emergency
      // Plumbing & Pipe Repair is already live… or you can swap which one is
      // live".
      expect(FREE_TIER_ACTIVE_LISTING_CAP).toBe(1);
      const capped = await registerUser(app, { role: 'provider' });

      const first = await completeDraft(app, capped.headers);
      expect((await publish(app, capped.headers, first.id)).statusCode).toBe(200);

      const second = await completeDraft(app, capped.headers);
      const res = await publish(app, capped.headers, second.id);

      expect(res.statusCode).toBe(422);
      const error = res.json<ErrorEnvelope>().error;
      expect(error.code).toBe('LISTING_CAP_REACHED');
      expect(error.message).toBe('Your plan publishes one service at a time');
      const details = error.details as {
        activeListingCap: number;
        liveListings: { id: string }[];
      };
      expect(details.activeListingCap).toBe(1);
      expect(details.liveListings.map((l) => l.id)).toEqual([first.id]);
    });

    it('does not cap drafts — only what is live', async () => {
      // §Phase 8's own correction: v1 checked the cap at draft creation, "so
      // drafts made during a trial could all be published after downgrade".
      // The wizard's over-limit sheet says the opposite of a refusal —
      // "This draft is saved and isn't going anywhere".
      const capped = await registerUser(app, { role: 'provider' });
      const first = await completeDraft(app, capped.headers);
      await publish(app, capped.headers, first.id);

      for (let i = 0; i < 3; i += 1) {
        const draft = await createDraft(app, capped.headers, {});
        expect(draft.status).toBe('draft');
      }
      const drafts = await app.deps.prisma.listing.count({
        where: { providerProfile: { userId: capped.userId }, status: 'draft', deletedAt: null },
      });
      expect(drafts).toBeGreaterThanOrEqual(3);
    });

    it('frees the slot when the provider hides the live one, and re-checks on un-hiding', async () => {
      // Publish is not the only door into the visible set. A provider at the
      // cap who hid one listing and published another would otherwise un-hide
      // the first and hold two live.
      const capped = await registerUser(app, { role: 'provider' });
      const first = await completeDraft(app, capped.headers);
      await publish(app, capped.headers, first.id);

      const hide = await app.inject({
        method: 'PATCH',
        url: `${BASE}/${first.id}/visibility`,
        headers: capped.headers,
        remoteAddress: freshIp(),
        payload: { visibility: 'hidden_by_provider' },
      });
      expect(hide.statusCode).toBe(200);
      expect(hide.json<Envelope<OwnListingDto>>().data.visibility).toBe('hidden_by_provider');

      const second = await completeDraft(app, capped.headers);
      expect((await publish(app, capped.headers, second.id)).statusCode).toBe(200);

      const unhide = await app.inject({
        method: 'PATCH',
        url: `${BASE}/${first.id}/visibility`,
        headers: capped.headers,
        remoteAddress: freshIp(),
        payload: { visibility: 'active' },
      });
      expect(unhide.statusCode).toBe(422);
      expect(unhide.json<ErrorEnvelope>().error.code).toBe('LISTING_CAP_REACHED');
    });

    it('will not let a provider set the two visibility values that are not theirs', async () => {
      // §1b, Round 17: `hidden_over_cap` is the entitlement system's and
      // `hidden_by_admin` is moderation's. Under a single `hidden` value an
      // upgrade would silently republish a listing the provider had
      // deliberately withdrawn, so the distinction has to be unreachable
      // rather than merely discouraged.
      const listing = await completeDraft(app, provider.headers);
      for (const visibility of ['hidden_over_cap', 'hidden_by_admin']) {
        const res = await app.inject({
          method: 'PATCH',
          url: `${BASE}/${listing.id}/visibility`,
          headers: provider.headers,
          remoteAddress: freshIp(),
          payload: { visibility },
        });
        expect(res.statusCode).toBe(400);
      }
    });
  });

  // -------------------------------------------------------------------------

  describe('`isEmergency` is gated by §1c’s composed rule', () => {
    it('is rejected on a category that is not emergency-capable', async () => {
      const cleaning = await categoryByName(app.deps.prisma, 'Cleaning');
      expect(cleaning.emergencyCapable).toBe(false);

      const draft = await createDraft(app, provider.headers, { categoryId: cleaning.id });
      const res = await patchDraft(app, provider.headers, draft.id, { isEmergency: true });

      expect(res.statusCode).toBe(422);
      expect(res.json<ErrorEnvelope>().error.code).toBe('EMERGENCY_CATEGORY_NOT_CAPABLE');
    });

    /**
     * 🔧 §Phase 8's Done-when names this case specifically, and says why:
     * "a test that passes against a boolean gate is not a test of this rule".
     *
     * One provider, one tier, two categories, opposite answers. A `verified`
     * boolean or a hardcoded `silver` would give the same answer to both —
     * only reading each category's own `emergencyMinimumTier` separates them.
     */
    it('rejects a SILVER provider on Electrical and accepts the same provider on AC Repair', async () => {
      const silver = await registerUser(app, { role: 'provider' });
      const profile = await app.providers.getOrCreateProviderProfile(silver.userId);
      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'silver' },
      });

      const electrical = await categoryByName(app.deps.prisma, 'Electrical');
      const acRepair = await categoryByName(app.deps.prisma, 'AC Repair');
      // The bars are read from the seed, not asserted from memory — §1c:
      // `gold` for Electrical and Plumbing, `silver` for AC Repair and Moving.
      expect(electrical.emergencyMinimumTier).toBe('gold');
      expect(acRepair.emergencyMinimumTier).toBe('silver');

      const onElectrical = await createDraft(app, silver.headers, { categoryId: electrical.id });
      const refused = await patchDraft(app, silver.headers, onElectrical.id, {
        isEmergency: true,
      });
      expect(refused.statusCode).toBe(422);
      const error = refused.json<ErrorEnvelope>().error;
      expect(error.code).toBe('EMERGENCY_TIER_NOT_MET');
      // The reason names the bar and the current tier, because the provider's
      // next action depends on the gap — and §Phase 9 renders this text.
      expect(error.message).toContain('gold');
      expect(error.message).toContain('silver');

      const onAcRepair = await createDraft(app, silver.headers, { categoryId: acRepair.id });
      const accepted = await patchDraft(app, silver.headers, onAcRepair.id, { isEmergency: true });
      expect(accepted.statusCode).toBe(200);
      expect(accepted.json<Envelope<OwnListingDto>>().data.isEmergency).toBe(true);
    });

    it('is re-checked at publish, not only at update', async () => {
      // §Phase 8: "enforced on publish and update". A listing that set the
      // flag legitimately and then lost the tier must not go live with it.
      const gold = await registerUser(app, { role: 'provider' });
      const profile = await app.providers.getOrCreateProviderProfile(gold.userId);
      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'gold' },
      });
      const listing = await completeDraft(app, gold.headers, { categoryName: 'Electrical' });
      await patchDraft(app, gold.headers, listing.id, {
        isEmergency: true,
        bookingMode: 'request',
      });

      // The tier is revoked while the draft sits unpublished.
      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'silver' },
      });

      const res = await publish(app, gold.headers, listing.id);
      expect(res.statusCode).toBe(422);
      expect(res.json<ErrorEnvelope>().error.code).toBe('EMERGENCY_TIER_NOT_MET');
    });

    it('clears the flag on a published listing when the tier drops (Round 17)', async () => {
      // §1c: "Any tier drop now re-checks every published listing with
      // `isEmergency: true`, clears the flag where the category's bar is no
      // longer met" — a gold provider demoted to silver must stop advertising
      // emergency Electrical work behind a credential they no longer hold.
      const gold = await registerUser(app, { role: 'provider' });
      const profile = await app.providers.getOrCreateProviderProfile(gold.userId);
      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'gold' },
      });
      const listing = await completeDraft(app, gold.headers, { categoryName: 'Electrical' });
      await patchDraft(app, gold.headers, listing.id, {
        isEmergency: true,
        bookingMode: 'request',
      });
      expect((await publish(app, gold.headers, listing.id)).statusCode).toBe(200);

      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'silver' },
      });
      const cleared = await app.listings.reevaluateEmergencyEligibility(profile.id);

      expect(cleared.map((l) => l.id)).toEqual([listing.id]);
      const after = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listing.id } });
      expect(after.isEmergency).toBe(false);
      // The listing itself stays published — the claim was withdrawn, not the
      // service.
      expect(after.status).toBe('published');
    });

    it('leaves an AC Repair listing alone when gold drops to silver', async () => {
      // The other half of the per-category rule: the same demotion that
      // clears Electrical must not touch a category whose bar is `silver`.
      const gold = await registerUser(app, { role: 'provider' });
      const profile = await app.providers.getOrCreateProviderProfile(gold.userId);
      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'gold' },
      });
      const listing = await completeDraft(app, gold.headers, { categoryName: 'AC Repair' });
      await patchDraft(app, gold.headers, listing.id, {
        isEmergency: true,
        bookingMode: 'request',
      });
      await publish(app, gold.headers, listing.id);

      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'silver' },
      });
      const cleared = await app.listings.reevaluateEmergencyEligibility(profile.id);

      expect(cleared).toEqual([]);
      const after = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listing.id } });
      expect(after.isEmergency).toBe(true);
    });

    it('offers the callback guarantee only on an eligible category (Round 28)', async () => {
      // Not in §Phase 8's Done-when but enforced on the same write path, and
      // for a sharper reason: the callback is RaajjePro's own promise, so a
      // listing carrying it on a category where nothing can un-fix would be
      // a promise with no referent.
      const cleaning = await categoryByName(app.deps.prisma, 'Cleaning');
      const plumbing = await categoryByName(app.deps.prisma, 'Plumbing');
      expect(cleaning.callbackEligible).toBe(false);
      expect(plumbing.callbackEligible).toBe(true);

      const onCleaning = await createDraft(app, provider.headers, { categoryId: cleaning.id });
      const refused = await patchDraft(app, provider.headers, onCleaning.id, {
        callbackGuaranteeOffered: true,
      });
      expect(refused.statusCode).toBe(422);
      expect(refused.json<ErrorEnvelope>().error.code).toBe('CALLBACK_NOT_AVAILABLE_FOR_CATEGORY');
      // §Phase 9 renders no control at all — absent, not disabled — and it
      // reads this flag to decide.
      expect(onCleaning.callbackAvailable).toBe(false);

      const onPlumbing = await createDraft(app, provider.headers, { categoryId: plumbing.id });
      const accepted = await patchDraft(app, provider.headers, onPlumbing.id, {
        callbackGuaranteeOffered: true,
      });
      expect(accepted.statusCode).toBe(200);
      const body = accepted.json<Envelope<OwnListingDto>>().data;
      expect(body.callbackGuaranteeOffered).toBe(true);
      expect(body.callbackAvailable).toBe(true);
    });
  });

  // -------------------------------------------------------------------------

  describe('a soft-deleted listing disappears from public queries', () => {
    it('leaves every public query the moment it is deleted, and the row survives', async () => {
      const owner = await registerUser(app, { role: 'provider' });
      const listing = await completeDraft(app, owner.headers);
      await publish(app, owner.headers, listing.id);
      const profile = await app.providers.repo.findByUserId(owner.userId);
      const profileId = profile?.id ?? '';

      // §1a: the provider is publicly visible because this listing is.
      expect(await app.providers.visibility.isVisible(profileId)).toBe(true);
      const before = await app.deps.prisma.listing.count({
        where: { id: listing.id, ...PUBLICLY_VISIBLE_LISTING },
      });
      expect(before).toBe(1);

      const res = await app.inject({
        method: 'DELETE',
        url: `${BASE}/${listing.id}`,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(200);

      // Gone from the shared predicate every public consumer composes…
      const after = await app.deps.prisma.listing.count({
        where: { id: listing.id, ...PUBLICLY_VISIBLE_LISTING },
      });
      expect(after).toBe(0);
      // …and therefore from §1a's derived provider visibility, through the
      // one helper rather than a second copy of the rule.
      expect(await app.providers.visibility.isVisible(profileId)).toBe(false);

      // Invariant 8: nothing was deleted. The row, its service areas and its
      // media all survive, which is what lets a booking or a review that
      // referenced this listing still resolve.
      const row = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listing.id } });
      expect(row.deletedAt).not.toBeNull();
      expect(row.status).toBe('published');
      expect(
        await app.deps.prisma.listingServiceArea.count({
          where: { listingId: listing.id, removedAt: null },
        }),
      ).toBeGreaterThan(0);
      expect(
        await app.deps.prisma.listingMedia.count({
          where: { listingId: listing.id, removedAt: null },
        }),
      ).toBeGreaterThan(0);
    });

    it('is gone from the owner’s own list too, and cannot be deleted twice', async () => {
      const owner = await registerUser(app, { role: 'provider' });
      const listing = await completeDraft(app, owner.headers);
      await app.inject({
        method: 'DELETE',
        url: `${BASE}/${listing.id}`,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });

      const list = await app.inject({
        method: 'GET',
        url: BASE,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });
      const items = list.json<Envelope<OwnListingDto[]>>().data;
      expect(items.map((l) => l.id)).not.toContain(listing.id);

      const again = await app.inject({
        method: 'DELETE',
        url: `${BASE}/${listing.id}`,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });
      expect(again.statusCode).toBe(404);
    });
  });

  // -------------------------------------------------------------------------

  describe('no response carries a phone number', () => {
    it('holds for every listing shape, at every depth', async () => {
      // §1c: exactly one endpoint in the entire system may return a phone
      // number to another user, and it is not one of these. Asserted on the
      // serialized body rather than on a field list, because the risk is a
      // field added later at some nesting depth nobody re-checked.
      const owner = await registerUser(app, { role: 'provider' });
      const listing = await completeDraft(app, owner.headers);
      await publish(app, owner.headers, listing.id);
      await uploadImage(app, owner.headers, listing.id);

      const bodies = await Promise.all(
        [`${BASE}/${listing.id}`, BASE].map(
          async (url) =>
            (
              await app.inject({
                method: 'GET',
                url,
                headers: owner.headers,
                remoteAddress: freshIp(),
              })
            ).body,
        ),
      );
      for (const body of bodies) {
        expect(body).not.toContain(owner.phone);
        expect(body).not.toContain(`+960${owner.phone}`);
        for (const key of ['phone', 'phoneE164', 'whatsapp', 'viber', 'bankAccountNumber']) {
          expect(body).not.toContain(key);
        }
      }
    });
  });
});
