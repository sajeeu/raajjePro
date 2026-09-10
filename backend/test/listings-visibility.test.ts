import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { PUBLICLY_VISIBLE_LISTING } from '../src/modules/listings/visibility.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { BASE, completeDraft, ensureCategoriesSeeded, publish } from './helpers/listings.js';
import { registerUser } from './helpers/users.js';

/**
 * Ledger row **P5-1**, closed here.
 *
 * §Phase 5 built §1a's derived visibility — draft-only excluded, published
 * included, unpublished excluded again, a suspended provider excluded from
 * all three consumer shapes — but every one of those ran against the
 * `PublishedListingSource` seam (`FakeListings`), because there was no
 * `Listing` table to publish. What P5-1 was open for is exactly this: the
 * same helper, the same rule, run against **real published rows**.
 *
 * `PUBLISHED_LISTINGS` is wired as the default in `app.ts`, so nothing is
 * injected here — the app under test is the one that ships.
 */
describe.skipIf(databaseUrl === undefined)('§1a visibility over real listings', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await ensureCategoriesSeeded(app.deps.prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  /**
   * Whether this provider appears anywhere in `findVisibleProviders`, walking
   * the cursor rather than reading page one.
   *
   * The suite writes rows and never deletes them, so by the time this file
   * runs there are more visible providers than fit in a page — and a
   * one-page check would make the negative assertions pass for the wrong
   * reason, which is worse than the positive one failing.
   */
  async function appearsInVisibleProviders(profileId: string): Promise<boolean> {
    let cursor: string | undefined;
    do {
      const page = await app.providers.findVisibleProviders(
        {},
        cursor === undefined ? {} : { cursor },
      );
      if (page.items.some((p) => p.id === profileId)) return true;
      cursor = page.nextCursor ?? undefined;
    } while (cursor !== undefined);
    return false;
  }

  async function providerWithListing() {
    const user = await registerUser(app, { role: 'provider' });
    const listing = await completeDraft(app, user.headers);
    const profile = await app.providers.repo.findByUserId(user.userId);
    if (profile === null) throw new Error('no profile');
    return { user, listing, profileId: profile.id };
  }

  it('includes a provider the moment a real listing is published, and drops them when it is hidden', async () => {
    const { user, listing, profileId } = await providerWithListing();

    // A draft is not a published listing. §1a's count is zero.
    expect(await app.providers.visibility.isVisible(profileId)).toBe(false);
    expect(await appearsInVisibleProviders(profileId)).toBe(false);

    expect((await publish(app, user.headers, listing.id)).statusCode).toBe(200);

    // Nothing about the provider row changed — the answer is derived.
    expect(await app.providers.visibility.isVisible(profileId)).toBe(true);
    expect(await appearsInVisibleProviders(profileId)).toBe(true);

    // Hidden by the provider: still published, no longer visible.
    await app.inject({
      method: 'PATCH',
      url: `${BASE}/${listing.id}/visibility`,
      headers: user.headers,
      remoteAddress: freshIp(),
      payload: { visibility: 'hidden_by_provider' },
    });
    expect(await app.providers.visibility.isVisible(profileId)).toBe(false);

    // And back again. This is the transition v1's stored flag could not
    // represent: it flipped one-way on first publish and never came back.
    await app.inject({
      method: 'PATCH',
      url: `${BASE}/${listing.id}/visibility`,
      headers: user.headers,
      remoteAddress: freshIp(),
      payload: { visibility: 'active' },
    });
    expect(await app.providers.visibility.isVisible(profileId)).toBe(true);
  });

  it('still stores no visibility column on either table', async () => {
    // §1a: "There is no stored lifecycleStatus field." §Phase 5 asserted this
    // for `provider_profile`; now that a `listing` table exists, the same
    // question has to be asked of the place a cached answer would most
    // naturally be written — a `provider_is_visible` denormalisation on the
    // listing, or a count on the profile.
    const columns = await app.deps.prisma.$queryRaw<{ table_name: string; column_name: string }[]>`
      SELECT table_name, column_name FROM information_schema.columns
      WHERE table_name IN ('provider_profile', 'listing')
    `;
    const profileColumns = columns
      .filter((c) => c.table_name === 'provider_profile')
      .map((c) => c.column_name);
    for (const forbidden of [
      'lifecycle_status',
      'is_visible',
      'visibility',
      'is_public',
      'published',
      'is_published',
      'published_listing_count',
      'status',
    ]) {
      expect(profileColumns).not.toContain(forbidden);
    }
    // The listing's own `visibility` and `status` are the INPUTS to the
    // derivation, not a cache of its result — which is why they are expected
    // here and forbidden above.
    const listingColumns = columns
      .filter((c) => c.table_name === 'listing')
      .map((c) => c.column_name);
    expect(listingColumns).toContain('visibility');
    expect(listingColumns).toContain('status');
    expect(listingColumns).not.toContain('provider_is_visible');
  });

  it('excludes a suspended provider even with a published listing', async () => {
    // §1a: suspension is an INPUT to the helper, not a second filter. With a
    // real listing behind it, the composed query has to still exclude them.
    const { user, listing, profileId } = await providerWithListing();
    await publish(app, user.headers, listing.id);
    expect(await app.providers.visibility.isVisible(profileId)).toBe(true);

    await app.deps.prisma.providerProfile.update({
      where: { id: profileId },
      data: { suspendedAt: new Date(), suspendedReason: 'under review' },
    });

    expect(await app.providers.visibility.isVisible(profileId)).toBe(false);
    expect(await appearsInVisibleProviders(profileId)).toBe(false);
    await expect(app.providers.readPublic(profileId)).rejects.toThrow(/No such provider/);
  });

  it('drops a provider whose only listing is soft-deleted', async () => {
    const { user, listing, profileId } = await providerWithListing();
    await publish(app, user.headers, listing.id);
    expect(await app.providers.visibility.isVisible(profileId)).toBe(true);

    await app.inject({
      method: 'DELETE',
      url: `${BASE}/${listing.id}`,
      headers: user.headers,
      remoteAddress: freshIp(),
    });

    expect(await app.providers.visibility.isVisible(profileId)).toBe(false);
  });

  it('keeps a provider visible while any one listing qualifies', async () => {
    // The rule is a count above zero, not "the listing". A provider with one
    // live and one hidden is visible; hiding the live one takes them out.
    const { user, listing, profileId } = await providerWithListing();
    await publish(app, user.headers, listing.id);
    const second = await completeDraft(app, user.headers);

    // The second stays a draft — the free-tier cap would refuse it live, and
    // a draft was never going to count anyway.
    expect(await app.providers.visibility.isVisible(profileId)).toBe(true);
    expect(second.status).toBe('draft');

    await app.inject({
      method: 'PATCH',
      url: `${BASE}/${listing.id}/visibility`,
      headers: user.headers,
      remoteAddress: freshIp(),
      payload: { visibility: 'hidden_by_provider' },
    });
    expect(await app.providers.visibility.isVisible(profileId)).toBe(false);
  });

  it('is the same predicate the entitlement cap counts', async () => {
    // `COUNTS_AGAINST_CAP` is an alias of `PUBLICLY_VISIBLE_LISTING`, not a
    // second copy. If the two diverged a provider could be over their cap
    // with nothing visible, or under it with two listings live — so the
    // aliasing is asserted rather than assumed.
    const { user, listing, profileId } = await providerWithListing();
    await publish(app, user.headers, listing.id);

    const visibleCount = await app.deps.prisma.listing.count({
      where: { providerProfileId: profileId, ...PUBLICLY_VISIBLE_LISTING },
    });
    const capCount = await app.listings.repo.countActive(profileId);
    expect(capCount).toBe(visibleCount);
    expect(capCount).toBe(1);
    expect(listing.id).toBeDefined();
  });
});
