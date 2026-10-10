import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { SearchPageDto } from '../src/modules/search/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { ensureIslandsSeeded, islandByName } from './helpers/islands.js';
import { categoryByName, completeDraft, patchDraft, publish } from './helpers/listings.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

const SEARCH = '/v1/search/listings';

type IslandName = [string, string];
const MALE: IslandName = ['K', "Male'"];
const HULHUMALE: IslandName = ['K', "Hulhumale'"];
const VILUFUSHI: IslandName = ['Th', 'Vilufushi'];

/**
 * §Phase 15 — **Done when:** "results are correct, paginated, and filtered;
 * priority placement never surfaces an irrelevant listing; every boosted
 * result is labelled; every card states its booking mode."
 *
 * The suite runs against a database other suites share, so every test
 * scopes itself with a word nobody else uses (`marker`) in its listings'
 * names and in its query. A result from outside the test can never be
 * mistaken for one inside it.
 */
describe.skipIf(databaseUrl === undefined)('Phase 15 — Done when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await ensureIslandsSeeded(app.deps.prisma);
  });
  afterAll(async () => {
    await app.close();
  });

  /** A word no other listing in the database carries. Letters only, so the fold leaves it intact. */
  function freshMarker(): string {
    return `qx${randomUUID()
      .replace(/[^a-f]/g, '')
      .slice(0, 10)}`;
  }

  async function islandId([atoll, name]: IslandName): Promise<string> {
    return (await islandByName(app.deps.prisma, atoll, name)).id;
  }

  async function search(params: Record<string, string | number | boolean>, user?: RegisteredUser) {
    const qs = new URLSearchParams(
      Object.entries(params).map(([k, v]) => [k, String(v)]),
    ).toString();
    const res = await app.inject({
      method: 'GET',
      url: `${SEARCH}?${qs}`,
      remoteAddress: freshIp(),
      headers: user?.headers ?? {},
    });
    expect(res.statusCode, res.body).toBe(200);
    return res.json<Envelope<SearchPageDto>>();
  }

  async function ids(params: Record<string, string | number | boolean>): Promise<string[]> {
    return (await search({ limit: 50, ...params })).data.items.map((item) => item.listing.id);
  }

  async function makePremium(providerProfileId: string, status: 'active' | 'trialing' = 'active') {
    await app.deps.prisma.providerSubscription.upsert({
      where: { providerProfileId },
      create: { providerProfileId, tier: 'premium', status },
      update: { tier: 'premium', status },
    });
  }

  interface Published {
    listingId: string;
    providerProfileId: string;
    user: RegisteredUser;
  }

  /**
   * A published listing, with whatever the test sets on top of
   * `completeDraft`'s six required fields. Pass `user` to publish a second
   * listing for the same provider. The free tier allows one active listing,
   * so that provider must be premium first.
   */
  async function published(
    options: {
      name: string;
      categoryName?: string;
      islands?: IslandName[];
      patch?: Record<string, unknown>;
      user?: RegisteredUser;
      premium?: boolean;
    } = { name: 'x' },
  ): Promise<Published> {
    const user = options.user ?? (await registerUser(app, { role: 'provider' }));
    const prisma = app.deps.prisma;
    if (options.premium === true) {
      const profile = await prisma.providerProfile.findUniqueOrThrow({
        where: { userId: user.userId },
        select: { id: true },
      });
      await makePremium(profile.id);
    }
    const draft = await completeDraft(app, user.headers, {
      categoryName: options.categoryName ?? 'Cleaning',
      islandNames: options.islands ?? [MALE],
    });
    const patched = await patchDraft(app, user.headers, draft.id, {
      name: options.name,
      ...options.patch,
    });
    expect(patched.statusCode, patched.body).toBe(200);
    const res = await publish(app, user.headers, draft.id);
    expect(res.statusCode, res.body).toBe(200);
    const row = await prisma.listing.findUniqueOrThrow({
      where: { id: draft.id },
      select: { providerProfileId: true },
    });
    return { listingId: draft.id, providerProfileId: row.providerProfileId, user };
  }

  async function rate(listingId: string, reviewCount: number, ratingSum: number) {
    await app.deps.prisma.listingRatingAggregate.upsert({
      where: { listingId },
      create: { listingId, reviewCount, ratingSum },
      update: { reviewCount, ratingSum },
    });
  }

  // =========================================================================

  describe('1. results are correct', () => {
    it('matches every word against name, short description, tags, category and business name', async () => {
      const m = freshMarker();
      const byName = await published({ name: `${m} Sofa Shampoo` });
      const byDescription = await published({
        name: `${m} Service A`,
        patch: { shortDescription: 'We polish teak floors and decks.' },
      });
      const byTag = await published({ name: `${m} Service B`, patch: { tags: ['grout'] } });
      const byCategory = await published({ name: `${m} Service C`, categoryName: 'Plumbing' });
      const business = await registerUser(app, {
        role: 'provider',
        businessName: 'Zubair Kon’dey Works',
      });
      const byBusiness = await published({ name: `${m} Service D`, user: business });

      expect(await ids({ q: `${m} shampoo` })).toEqual([byName.listingId]);
      expect(await ids({ q: `teak ${m}` })).toEqual([byDescription.listingId]);
      expect(await ids({ q: `${m} grout` })).toEqual([byTag.listingId]);
      expect(await ids({ q: `${m} plumbing` })).toEqual([byCategory.listingId]);
      // Ruling Q4: the business name is the public headline, so it is found,
      // and the Dhivehi apostrophe is ignored on both sides.
      expect(await ids({ q: `${m} kondey` })).toEqual([byBusiness.listingId]);
      expect(await ids({ q: `${m} KON'DEY zubair` })).toEqual([byBusiness.listingId]);
      // Every word must match: one that matches nothing empties the set.
      expect(await ids({ q: `${m} shampoo nowhereword` })).toEqual([]);
      expect(new Set(await ids({ q: m }))).toEqual(
        new Set([byName, byDescription, byTag, byCategory, byBusiness].map((p) => p.listingId)),
      );
    });

    it('ignores accents and case, so "male" finds "Malé"', async () => {
      const m = freshMarker();
      const p = await published({ name: `${m} Malé Deep Clean` });
      expect(await ids({ q: `${m} MALE` })).toEqual([p.listingId]);
      expect(await ids({ q: `${m} malé` })).toEqual([p.listingId]);
    });

    it('never searches a personal name — registration names are not public text', async () => {
      const m = freshMarker();
      await published({ name: `${m} Service` });
      // `registerUser` names every user "Aishath Test".
      expect(await ids({ q: `${m} aishath` })).toEqual([]);
    });

    it('the island gate reads the listing’s own service areas by id, not the account default (ledger P7-3)', async () => {
      const m = freshMarker();
      const onMale = await published({ name: `${m} Service`, islands: [MALE] });
      // The provider's account-level coverage includes Vilufushi; the listing does not.
      await app.deps.prisma.providerServiceArea.create({
        data: { providerProfileId: onMale.providerProfileId, islandId: await islandId(VILUFUSHI) },
      });
      const onVilufushi = await published({ name: `${m} Service`, islands: [VILUFUSHI] });

      expect(await ids({ q: m, islandId: await islandId(MALE) })).toEqual([onMale.listingId]);
      expect(await ids({ q: m, islandId: await islandId(VILUFUSHI) })).toEqual([
        onVilufushi.listingId,
      ]);
      // No island chosen: no gate.
      expect(new Set(await ids({ q: m }))).toEqual(
        new Set([onMale.listingId, onVilufushi.listingId]),
      );
    });

    it('a removed service area stops matching', async () => {
      const m = freshMarker();
      const p = await published({ name: `${m} Service`, islands: [MALE, VILUFUSHI] });
      await app.deps.prisma.listingServiceArea.updateMany({
        where: { listingId: p.listingId, islandId: await islandId(VILUFUSHI) },
        data: { removedAt: new Date() },
      });
      expect(await ids({ q: m, islandId: await islandId(VILUFUSHI) })).toEqual([]);
      expect(await ids({ q: m, islandId: await islandId(MALE) })).toEqual([p.listingId]);
    });

    it('shows only what §1a shows: no draft, hidden, deleted, suspended or not-accepting listing', async () => {
      const m = freshMarker();
      const shown = await published({ name: `${m} Shown` });
      const hidden = await published({ name: `${m} Hidden` });
      const deleted = await published({ name: `${m} Deleted` });
      const suspended = await published({ name: `${m} Suspended` });
      const paused = await published({ name: `${m} Paused` });
      const draftOwner = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, draftOwner.headers);
      await patchDraft(app, draftOwner.headers, draft.id, { name: `${m} Draft` });

      const prisma = app.deps.prisma;
      await prisma.listing.update({
        where: { id: hidden.listingId },
        data: { visibility: 'hidden_by_provider' },
      });
      await prisma.listing.update({
        where: { id: deleted.listingId },
        data: { deletedAt: new Date() },
      });
      await prisma.providerProfile.update({
        where: { id: suspended.providerProfileId },
        data: { suspendedAt: new Date(), suspendedReason: 'test' },
      });
      // Ruling Q6: the toggle "hides every service at once".
      await prisma.providerProfile.update({
        where: { id: paused.providerProfileId },
        data: { acceptingNewCustomers: false },
      });

      expect(await ids({ q: m })).toEqual([shown.listingId]);
    });

    it('no visibility difference between verified and unverified providers', async () => {
      const m = freshMarker();
      const none = await published({ name: `${m} Service` });
      const gold = await published({ name: `${m} Service` });
      await app.deps.prisma.providerProfile.update({
        where: { id: gold.providerProfileId },
        data: { verificationTier: 'gold', verificationStatus: 'verified' },
      });

      expect(new Set(await ids({ q: m }))).toEqual(new Set([none.listingId, gold.listingId]));
      // A tier parameter is not part of the contract: it is ignored, never applied.
      expect(new Set(await ids({ q: m, verificationTier: 'gold' }))).toEqual(
        new Set([none.listingId, gold.listingId]),
      );
      // …and the tier is not a ranking input: with nothing else to tell them
      // apart, the order is the id tiebreak, whichever is verified.
      const order = await ids({ q: m });
      expect(order).toEqual([none.listingId, gold.listingId].sort());
    });

    it('is open to a guest, and no response carries a phone number', async () => {
      const m = freshMarker();
      const p = await published({ name: `${m} Service` });
      const res = await app.inject({
        method: 'GET',
        url: `${SEARCH}?q=${m}`,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(200);
      expect(res.body).not.toContain(p.user.phone);
      expect(res.body).not.toMatch(/"phone/i);
      expect(res.body).not.toMatch(/bank/i);
    });
  });

  // =========================================================================

  describe('2. results are paginated', () => {
    it('pages walk the whole set once each, with a stable total', async () => {
      const m = freshMarker();
      const all = new Set<string>();
      for (let i = 0; i < 7; i += 1)
        all.add((await published({ name: `${m} Svc ${String(i)}` })).listingId);

      for (const sort of ['distance', 'rating', 'price'] as const) {
        const seen: string[] = [];
        let cursor: string | null | undefined;
        let pages = 0;
        do {
          const body = await search({
            q: m,
            sort,
            limit: 3,
            ...(cursor == null ? {} : { cursor }),
          });
          expect(body.data.total).toBe(7);
          seen.push(...body.data.items.map((item) => item.listing.id));
          cursor = body.meta?.nextCursor;
          pages += 1;
        } while (cursor != null);
        expect(pages).toBe(3);
        expect(seen).toHaveLength(7);
        expect(new Set(seen)).toEqual(all);
      }
    });

    it('the page boundary between boosted and unboosted results neither repeats nor skips', async () => {
      const m = freshMarker();
      const boosted: string[] = [];
      for (let i = 0; i < 3; i += 1) {
        boosted.push(
          (await published({ name: `${m} Boost ${String(i)}`, premium: true })).listingId,
        );
      }
      const plain: string[] = [];
      for (let i = 0; i < 3; i += 1)
        plain.push((await published({ name: `${m} Plain ${String(i)}` })).listingId);

      const first = await search({ q: m, limit: 2 });
      const second = await search({ q: m, limit: 2, cursor: first.meta?.nextCursor ?? '' });
      const third = await search({ q: m, limit: 2, cursor: second.meta?.nextCursor ?? '' });
      const walked = [first, second, third].flatMap((page) =>
        page.data.items.map((item) => item.listing.id),
      );
      expect(third.meta?.nextCursor).toBeNull();
      expect(walked).toHaveLength(6);
      expect(new Set(walked.slice(0, 3))).toEqual(new Set(boosted));
      expect(new Set(walked.slice(3))).toEqual(new Set(plain));
    });

    it('a malformed cursor, or one from another sort, starts from the beginning instead of failing', async () => {
      const m = freshMarker();
      for (let i = 0; i < 3; i += 1) await published({ name: `${m} Svc ${String(i)}` });
      const first = await search({ q: m, limit: 2 });
      const fromStart = first.data.items.map((item) => item.listing.id);

      for (const cursor of ['garbage', Buffer.from('{"s":"distance"}').toString('base64url')]) {
        const again = await search({ q: m, limit: 2, cursor });
        expect(again.data.items.map((item) => item.listing.id)).toEqual(fromStart);
      }
      const wrongSort = await search({
        q: m,
        limit: 2,
        sort: 'price',
        cursor: first.meta?.nextCursor ?? '',
      });
      expect(wrongSort.data.items).toHaveLength(2);
    });
  });

  // =========================================================================

  describe('3. results are filtered', () => {
    it('by category, by booking mode and by §1g Maldivian ownership', async () => {
      const m = freshMarker();
      const cleaning = await published({ name: `${m} Svc`, patch: { bookingMode: 'slot' } });
      const plumbing = await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: { bookingMode: 'request' },
      });
      await app.deps.prisma.providerProfile.update({
        where: { id: plumbing.providerProfileId },
        data: { verificationTier: 'gold', maldivianOwned: true },
      });
      const plumbingId = (await categoryByName(app.deps.prisma, 'Plumbing')).id;

      expect(await ids({ q: m, categoryId: plumbingId })).toEqual([plumbing.listingId]);
      expect(await ids({ q: m, mode: 'slot' })).toEqual([cleaning.listingId]);
      expect(await ids({ q: m, mode: 'request' })).toEqual([plumbing.listingId]);
      expect(await ids({ q: m, maldivianOwned: true })).toEqual([plumbing.listingId]);
      // `false` does not narrow: customers who do not care are unaffected (§1g).
      expect(new Set(await ids({ q: m, maldivianOwned: false }))).toEqual(
        new Set([cleaning.listingId, plumbing.listingId]),
      );
    });

    it('by price range: exact prices inside the bounds, overlapping ranges, never a quote', async () => {
      const m = freshMarker();
      const cheap = await published({ name: `${m} Svc`, patch: { priceLaari: 20_000 } });
      const mid = await published({ name: `${m} Svc`, patch: { priceLaari: 40_000 } });
      const dear = await published({ name: `${m} Svc`, patch: { priceLaari: 90_000 } });
      const range = await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: {
          pricingModel: 'range',
          priceLaari: null,
          priceMinLaari: 50_000,
          priceMaxLaari: 70_000,
          priceUnit: null,
          bookingMode: 'request',
        },
      });
      const quote = await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: { pricingModel: 'quote', priceLaari: null, priceUnit: null, bookingMode: 'request' },
      });

      expect(new Set(await ids({ q: m, priceMinLaari: 30_000, priceMaxLaari: 60_000 }))).toEqual(
        new Set([mid.listingId, range.listingId]),
      );
      expect(new Set(await ids({ q: m, priceMaxLaari: 30_000 }))).toEqual(
        new Set([cheap.listingId]),
      );
      expect(new Set(await ids({ q: m, priceMinLaari: 75_000 }))).toEqual(
        new Set([dear.listingId]),
      );
      // No bound: the quote listing is a result like any other.
      expect(await ids({ q: m })).toContain(quote.listingId);
    });

    it('refuses an inverted price range', async () => {
      const res = await app.inject({
        method: 'GET',
        url: `${SEARCH}?priceMinLaari=500&priceMaxLaari=100`,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(400);
    });

    it('has no emergency filter: the parameter is ignored, never applied (Round 23)', async () => {
      const m = freshMarker();
      const p = await published({ name: `${m} Svc` });
      expect(await ids({ q: m, emergency: true })).toEqual([p.listingId]);
    });
  });

  // =========================================================================

  describe('4. sort: distance, then rating, then price', () => {
    it('distance is island-relative: fewer islands served first, then rating', async () => {
      const m = freshMarker();
      const wide = await published({ name: `${m} Svc`, islands: [MALE, HULHUMALE, VILUFUSHI] });
      const two = await published({ name: `${m} Svc`, islands: [MALE, HULHUMALE] });
      const localLow = await published({ name: `${m} Svc`, islands: [MALE] });
      const localHigh = await published({ name: `${m} Svc`, islands: [MALE] });
      await rate(localLow.listingId, 4, 12); // 3.0
      await rate(localHigh.listingId, 4, 18); // 4.5

      expect(await ids({ q: m, islandId: await islandId(MALE) })).toEqual([
        localHigh.listingId,
        localLow.listingId,
        two.listingId,
        wide.listingId,
      ]);
    });

    it('rating: highest average first, then more reviews, and unrated last', async () => {
      const m = freshMarker();
      const unrated = await published({ name: `${m} Svc` });
      const four = await published({ name: `${m} Svc` });
      const fiveFew = await published({ name: `${m} Svc` });
      const fiveMany = await published({ name: `${m} Svc` });
      await rate(four.listingId, 3, 12);
      await rate(fiveFew.listingId, 1, 5);
      await rate(fiveMany.listingId, 9, 45);

      expect(await ids({ q: m, sort: 'rating' })).toEqual([
        fiveMany.listingId,
        fiveFew.listingId,
        four.listingId,
        unrated.listingId,
      ]);
    });

    it('price: lowest headline first, a range by its "from" figure, a quote last', async () => {
      const m = freshMarker();
      const quote = await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: { pricingModel: 'quote', priceLaari: null, priceUnit: null, bookingMode: 'request' },
      });
      const dear = await published({ name: `${m} Svc`, patch: { priceLaari: 80_000 } });
      const range = await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: {
          pricingModel: 'range',
          priceLaari: null,
          priceMinLaari: 30_000,
          priceMaxLaari: 90_000,
          priceUnit: null,
          bookingMode: 'request',
        },
      });
      const cheap = await published({ name: `${m} Svc`, patch: { priceLaari: 10_000 } });

      expect(await ids({ q: m, sort: 'price' })).toEqual([
        cheap.listingId,
        range.listingId,
        dear.listingId,
        quote.listingId,
      ]);
    });
  });

  // =========================================================================

  describe('5. priority placement never surfaces an irrelevant listing; every boosted result is labelled', () => {
    it('a premium provider’s listing leads under every sort, and carries Sponsored', async () => {
      const m = freshMarker();
      const plainCheap = await published({ name: `${m} Svc`, patch: { priceLaari: 10_000 } });
      await rate(plainCheap.listingId, 5, 25);
      const boosted = await published({
        name: `${m} Svc`,
        premium: true,
        patch: { priceLaari: 90_000 },
      });

      for (const sort of ['distance', 'rating', 'price'] as const) {
        const body = await search({ q: m, sort });
        expect(body.data.items.map((item) => [item.listing.id, item.sponsored])).toEqual([
          [boosted.listingId, true],
          [plainCheap.listingId, false],
        ]);
      }
    });

    it('the chosen sort still orders the boosted group within itself', async () => {
      const m = freshMarker();
      const owner = await registerUser(app, { role: 'provider' });
      const dear = await published({
        name: `${m} Svc`,
        user: owner,
        premium: true,
        patch: { priceLaari: 70_000 },
      });
      const cheap = await published({
        name: `${m} Svc`,
        user: owner,
        patch: { priceLaari: 20_000 },
      });
      expect(await ids({ q: m, sort: 'price' })).toEqual([cheap.listingId, dear.listingId]);
    });

    it('a boosted provider’s listing that fails the query, a filter or the island gate never appears', async () => {
      const m = freshMarker();
      const owner = await registerUser(app, { role: 'provider' });
      // Five listings from one premium provider, each failing exactly one predicate.
      const offText = await published({ name: 'Unrelated words', user: owner, premium: true });
      const offIsland = await published({
        name: `${m} Svc`,
        user: owner,
        islands: [VILUFUSHI],
      });
      const offCategory = await published({
        name: `${m} Svc`,
        user: owner,
        categoryName: 'Plumbing',
      });
      const offMode = await published({
        name: `${m} Svc`,
        user: owner,
        patch: { bookingMode: 'request' },
      });
      const offPrice = await published({
        name: `${m} Svc`,
        user: owner,
        patch: { priceLaari: 99_000, bookingMode: 'slot' },
      });
      const relevantPlain = await published({
        name: `${m} Svc`,
        patch: { priceLaari: 30_000, bookingMode: 'slot' },
      });

      const cleaningId = (await categoryByName(app.deps.prisma, 'Cleaning')).id;
      const results = await search({
        q: m,
        islandId: await islandId(MALE),
        categoryId: cleaningId,
        mode: 'slot',
        priceMaxLaari: 50_000,
        limit: 50,
      });
      expect(results.data.items.map((item) => item.listing.id)).toEqual([relevantPlain.listingId]);
      expect(results.data.total).toBe(1);
      for (const irrelevant of [offText, offIsland, offCategory, offMode, offPrice]) {
        expect(results.data.items.map((item) => item.listing.id)).not.toContain(
          irrelevant.listingId,
        );
      }
    });

    it('placement follows billing’s entitlements exactly: trial boosts, a free row does not', async () => {
      const m = freshMarker();
      const trial = await published({ name: `${m} Svc` });
      await makePremium(trial.providerProfileId, 'trialing');
      const lapsed = await published({ name: `${m} Svc` });
      await app.deps.prisma.providerSubscription.create({
        data: { providerProfileId: lapsed.providerProfileId, tier: 'premium', status: 'free' },
      });
      const none = await published({ name: `${m} Svc` });

      const body = await search({ q: m });
      const sponsored = new Map(body.data.items.map((item) => [item.listing.id, item.sponsored]));
      expect(sponsored.get(trial.listingId)).toBe(true);
      expect(sponsored.get(lapsed.listingId)).toBe(false);
      expect(sponsored.get(none.listingId)).toBe(false);
      expect(body.data.items[0]?.listing.id).toBe(trial.listingId);
    });

    it('every result that ranks ahead of an unsponsored one by placement carries the label', async () => {
      const m = freshMarker();
      for (let i = 0; i < 3; i += 1) await published({ name: `${m} Svc`, premium: i % 2 === 0 });
      const items = (await search({ q: m })).data.items;
      const firstPlain = items.findIndex((item) => !item.sponsored);
      // Sponsored results form one leading block: none follows an unsponsored one.
      expect(items.slice(firstPlain).every((item) => !item.sponsored)).toBe(true);
      expect(items.slice(0, firstPlain).every((item) => item.sponsored)).toBe(true);
      expect(firstPlain).toBe(2);
    });
  });

  // =========================================================================

  describe('6. every card states its booking mode', () => {
    it('every result carries slot or request, with its mode-appropriate second signal', async () => {
      const m = freshMarker();
      await published({ name: `${m} Svc`, patch: { bookingMode: 'slot' } });
      await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: { bookingMode: 'request' },
      });

      const items = (await search({ q: m })).data.items;
      expect(items).toHaveLength(2);
      for (const item of items) {
        expect(['slot', 'request']).toContain(item.listing.bookingMode);
        expect(item.listing.secondSignal.kind).toBe(
          item.listing.bookingMode === 'slot' ? 'next_open' : 'response_time',
        );
      }
      expect(new Set(items.map((item) => item.listing.bookingMode))).toEqual(
        new Set(['slot', 'request']),
      );
    });

    it('the callback badge appears only where the category is callbackEligible (Round 28)', async () => {
      const m = freshMarker();
      const plumbing = await published({
        name: `${m} Svc`,
        categoryName: 'Plumbing',
        patch: { callbackGuaranteeOffered: true, bookingMode: 'request' },
      });
      const items = (await search({ q: m })).data.items;
      expect(
        items.find((i) => i.listing.id === plumbing.listingId)?.listing.callbackGuarantee,
      ).toBe(true);
      const cleaning = await published({ name: `${m} Other` });
      const again = (await search({ q: m })).data.items;
      expect(
        again.find((i) => i.listing.id === cleaning.listingId)?.listing.callbackGuarantee,
      ).toBe(false);
    });
  });
});
