import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { OwnListingDto } from '../src/modules/listings/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { ensureIslandsSeeded, islandByName } from './helpers/islands.js';
import { createDraft, ensureCategoriesSeeded, patchDraft } from './helpers/listings.js';
import { registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}

/**
 * Ledger row **P7-3**: "that a service area is what discovery actually
 * matches on".
 *
 * §Phase 7 built `ProviderServiceArea` — **account-level**, the default
 * §Phase 6a collects and §Phase 9's step 2 pre-fills from. §Phase 8 gives a
 * **listing** its own areas, and those are what a customer's island filter
 * reads. The row was opened because nothing could yet show the two apart.
 *
 * This advances it as far as this phase can: the two are separate tables, a
 * write to one does not touch the other, and the listing's set is the one
 * stored against the listing. What still needs §Phase 15 is the last clause —
 * that the island *filter* reads the listing's set and not the account's —
 * because there is no search to read either.
 */
describe.skipIf(databaseUrl === undefined)('a listing’s own service areas', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let owner: Awaited<ReturnType<typeof registerUser>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await ensureCategoriesSeeded(app.deps.prisma);
    await ensureIslandsSeeded(app.deps.prisma);
    owner = await registerUser(app, { role: 'provider' });
  });

  afterAll(async () => {
    await app.close();
  });

  it('is a different set from the account-level default, and neither write touches the other', async () => {
    const male = await islandByName(app.deps.prisma, 'K', "Male'");
    const hulhumale = await islandByName(app.deps.prisma, 'K', "Hulhumale'");
    const kulhudhuffushi = await islandByName(app.deps.prisma, 'HDh', 'Kulhudhuffushi');

    // The account-level coverage §Phase 6a collects: two islands.
    for (const island of [male, hulhumale]) {
      const res = await app.inject({
        method: 'POST',
        url: '/v1/providers/me/service-areas',
        headers: owner.headers,
        remoteAddress: freshIp(),
        payload: { islandId: island.id },
      });
      expect(res.statusCode).toBe(200);
    }

    // The listing serves somewhere else entirely.
    const draft = await createDraft(app, owner.headers, {});
    const patched = await patchDraft(app, owner.headers, draft.id, {
      serviceAreaIslandIds: [kulhudhuffushi.id],
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json<Envelope<OwnListingDto>>().data.serviceAreas.map((i) => i.id)).toEqual([
      kulhudhuffushi.id,
    ]);

    // The account default is untouched by the listing write…
    const profile = await app.deps.prisma.providerProfile.findUniqueOrThrow({
      where: { userId: owner.userId },
    });
    const accountAreas = await app.deps.prisma.providerServiceArea.findMany({
      where: { providerProfileId: profile.id, removedAt: null },
    });
    expect(new Set(accountAreas.map((a) => a.islandId))).toEqual(new Set([male.id, hulhumale.id]));

    // …and the two live in different tables, which is what makes conflating
    // them impossible rather than merely discouraged.
    const listingAreas = await app.deps.prisma.listingServiceArea.findMany({
      where: { listingId: draft.id, removedAt: null },
    });
    expect(listingAreas.map((a) => a.islandId)).toEqual([kulhudhuffushi.id]);

    // The provider's account default covers Malé; this listing does not. When
    // §Phase 15's island filter lands, THIS is the set it must read — the
    // listing is what decides.
    expect(accountAreas.map((a) => a.islandId)).toContain(male.id);
    expect(listingAreas.map((a) => a.islandId)).not.toContain(male.id);
  });

  it('is keyed on the island id, never on a name — and the ambiguous names prove why', async () => {
    // §0.0 item 12: `Meedhoo` exists in three atolls. A service area matched
    // by name would serve all three, or the wrong one.
    const dh = await islandByName(app.deps.prisma, 'Dh', 'Meedhoo');
    const r = await islandByName(app.deps.prisma, 'R', 'Meedhoo');
    const s = await islandByName(app.deps.prisma, 'S', 'Meedhoo');
    expect(new Set([dh.id, r.id, s.id]).size).toBe(3);
    expect(dh.name).toBe(r.name);

    const draft = await createDraft(app, owner.headers, {});
    const res = await patchDraft(app, owner.headers, draft.id, {
      serviceAreaIslandIds: [dh.id],
    });
    const areas = res.json<Envelope<OwnListingDto>>().data.serviceAreas;

    expect(areas.map((i) => i.id)).toEqual([dh.id]);
    // The atoll travels with it, and the display form is qualified — a screen
    // that resolved the ambiguity at pick time and then printed the bare name
    // would have fixed nothing.
    expect(areas[0]?.displayName).toBe('Dh. Meedhoo');
    expect(areas[0]?.nameAmbiguous).toBe(true);

    const stored = await app.deps.prisma.listingServiceArea.findMany({
      where: { listingId: draft.id, removedAt: null },
    });
    expect(stored.map((a) => a.islandId)).toEqual([dh.id]);
  });

  it('renders an unambiguous island bare', async () => {
    const kulhudhuffushi = await islandByName(app.deps.prisma, 'HDh', 'Kulhudhuffushi');
    const draft = await createDraft(app, owner.headers, {});
    const res = await patchDraft(app, owner.headers, draft.id, {
      serviceAreaIslandIds: [kulhudhuffushi.id],
    });
    const areas = res.json<Envelope<OwnListingDto>>().data.serviceAreas;
    expect(areas[0]?.displayName).toBe('Kulhudhuffushi');
    expect(areas[0]?.nameAmbiguous).toBe(false);
  });

  it('refuses a deactivated island', async () => {
    // The register loses islands (depopulation, consolidation) and a
    // deactivated row must not become a new service area, even though
    // existing rows pointing at it survive (invariant 8).
    // Upserted on a fixed key rather than created: the suite writes rows and
    // never deletes them (`test/setup.ts`), so a `create` would collide with
    // its own previous run on the `(atollAbbr, name)` natural key. One row,
    // reused, and `isActive: false` keeps it out of every island search.
    const island = await app.deps.prisma.island.upsert({
      where: { seedKey: 'TEST:deactivated-island' },
      create: {
        seedKey: 'TEST:deactivated-island',
        name: 'Retired',
        atollName: 'Test',
        atollAbbr: 'T',
        nameAmbiguous: false,
        searchName: 'retired',
        searchQualified: 'tretired',
        isActive: false,
      },
      update: { isActive: false },
    });
    const draft = await createDraft(app, owner.headers, {});
    const res = await patchDraft(app, owner.headers, draft.id, {
      serviceAreaIslandIds: [island.id],
    });
    expect(res.statusCode).toBe(422);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('ISLAND_NOT_FOUND');
  });

  it('clears the whole set when an empty list is sent', async () => {
    const male = await islandByName(app.deps.prisma, 'K', "Male'");
    const draft = await createDraft(app, owner.headers, {});
    await patchDraft(app, owner.headers, draft.id, { serviceAreaIslandIds: [male.id] });

    const cleared = await patchDraft(app, owner.headers, draft.id, {
      serviceAreaIslandIds: [],
    });
    const body = cleared.json<Envelope<OwnListingDto>>().data;
    expect(body.serviceAreas).toEqual([]);
    // …and it becomes a required field again, which is the honest
    // consequence: "customers browsing from islands not on your list won't
    // see this service".
    expect(body.missingRequiredFields.map((f) => f.field)).toContain('serviceAreaIslandIds');
  });
});
