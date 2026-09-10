import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { IslandDto } from '../src/modules/location/types.js';
import type { OwnProviderDto } from '../src/modules/providers/types.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';
import { ensureIslandsSeeded, islandByName } from './helpers/islands.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface Err {
  error: { code: string };
}

/**
 * `POST` / `DELETE /v1/providers/me/service-areas` — §Phase 7's second bullet.
 *
 * The join table is the provider's account-level coverage. §Phase 8 gives a
 * *listing* its own areas and those are what discovery matches on; these are
 * the default §Phase 6a collects and the wizard pre-fills from.
 */
describe.skipIf(databaseUrl === undefined)('Phase 7 — provider service areas', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let provider: RegisteredUser;
  let male: { id: string };
  let hulhumale: { id: string };
  let dhMeedhoo: { id: string };

  const add = (user: RegisteredUser, islandId: string) =>
    app.inject({
      method: 'POST',
      url: '/v1/providers/me/service-areas',
      headers: user.headers,
      payload: { islandId },
    });

  const remove = (user: RegisteredUser, islandId: string) =>
    app.inject({
      method: 'DELETE',
      url: `/v1/providers/me/service-areas/${islandId}`,
      headers: user.headers,
    });

  const areasOf = async (user: RegisteredUser) => {
    const res = await app.inject({
      method: 'GET',
      url: '/v1/providers/me',
      headers: user.headers,
    });
    expect(res.statusCode).toBe(200);
    return res.json<Envelope<OwnProviderDto>>().data.serviceAreas;
  };

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await ensureIslandsSeeded(app.deps.prisma);
    provider = await registerUser(app, { role: 'provider' });
    male = await islandByName(app.deps.prisma, 'K', "Male'");
    hulhumale = await islandByName(app.deps.prisma, 'K', "Hulhumale'");
    dhMeedhoo = await islandByName(app.deps.prisma, 'Dh', 'Meedhoo');
  });

  afterAll(async () => {
    await app.close();
  });

  it('rejects an unauthenticated write before it looks at the body', async () => {
    const anonymous = await app.inject({
      method: 'POST',
      url: '/v1/providers/me/service-areas',
      payload: { islandId: 'not-a-uuid' },
    });
    expect(anonymous.statusCode).toBe(401);
  });

  it('adds an island and returns the resulting list in full', async () => {
    const res = await add(provider, male.id);
    expect(res.statusCode).toBe(200);
    const areas = res.json<Envelope<IslandDto[]>>().data;
    expect(areas.map((i) => i.id)).toEqual([male.id]);
    expect(areas[0]?.displayName).toBe("Male'");
  });

  it('is idempotent — adding the same island twice leaves one row', async () => {
    await add(provider, hulhumale.id);
    const second = await add(provider, hulhumale.id);
    expect(second.statusCode).toBe(200);
    expect(
      second.json<Envelope<IslandDto[]>>().data.filter((i) => i.id === hulhumale.id),
    ).toHaveLength(1);

    const rows = await app.deps.prisma.providerServiceArea.findMany({
      where: { island: { id: hulhumale.id }, providerProfile: { userId: provider.userId } },
    });
    expect(rows).toHaveLength(1);
  });

  it('surfaces the current list on the provider’s own profile read', async () => {
    const areas = await areasOf(provider);
    expect(areas.map((i) => i.id).sort()).toEqual([male.id, hulhumale.id].sort());
  });

  it('carries the atoll with every island, so a caller cannot lose it', async () => {
    for (const island of await areasOf(provider)) {
      expect(island.atollAbbr).not.toBe('');
      expect(island.atollName).not.toBe('');
    }
  });

  it('soft-deletes on removal and revives the same row when re-added', async () => {
    const removed = await remove(provider, hulhumale.id);
    expect(removed.statusCode).toBe(200);
    expect(removed.json<Envelope<IslandDto[]>>().data.map((i) => i.id)).toEqual([male.id]);

    const row = await app.deps.prisma.providerServiceArea.findFirstOrThrow({
      where: { islandId: hulhumale.id, providerProfile: { userId: provider.userId } },
    });
    // Invariant 8: the row is still there, stamped rather than deleted.
    expect(row.removedAt).not.toBeNull();

    await add(provider, hulhumale.id);
    const revived = await app.deps.prisma.providerServiceArea.findUniqueOrThrow({
      where: { id: row.id },
    });
    expect(revived.removedAt).toBeNull();

    const count = await app.deps.prisma.providerServiceArea.count({
      where: { islandId: hulhumale.id, providerProfile: { userId: provider.userId } },
    });
    expect(count).toBe(1);
  });

  it('removing an island that is not a service area changes nothing and does not error', async () => {
    const before = await areasOf(provider);
    const res = await remove(provider, dhMeedhoo.id);
    expect(res.statusCode).toBe(200);
    expect(
      res
        .json<Envelope<IslandDto[]>>()
        .data.map((i) => i.id)
        .sort(),
    ).toEqual(before.map((i) => i.id).sort());
  });

  it('keeps one provider’s areas out of another’s', async () => {
    const other = await registerUser(app, { role: 'provider' });
    await add(other, dhMeedhoo.id);
    expect((await areasOf(other)).map((i) => i.id)).toEqual([dhMeedhoo.id]);
    expect((await areasOf(provider)).map((i) => i.id)).not.toContain(dhMeedhoo.id);
  });

  it('refuses an island id that does not exist, and one that is deactivated', async () => {
    const missing = await add(provider, randomUUID());
    expect(missing.statusCode).toBe(404);
    expect(missing.json<Err>().error.code).toBe('ISLAND_NOT_FOUND');

    await app.deps.prisma.island.update({
      where: { id: dhMeedhoo.id },
      data: { isActive: false },
    });
    try {
      const inactive = await add(provider, dhMeedhoo.id);
      expect(inactive.statusCode).toBe(422);
      expect(inactive.json<Err>().error.code).toBe('ISLAND_INACTIVE');
    } finally {
      await app.deps.prisma.island.update({
        where: { id: dhMeedhoo.id },
        data: { isActive: true },
      });
    }
  });

  it('names an island by id only — a name is never accepted as one', async () => {
    const byName = await app.inject({
      method: 'POST',
      url: '/v1/providers/me/service-areas',
      headers: provider.headers,
      payload: { islandId: 'Meedhoo' },
    });
    expect(byName.statusCode).toBe(400);
  });

  describe('a customer who has never been a provider', () => {
    let customer: RegisteredUser;

    beforeAll(async () => {
      customer = await registerUser(app);
    });

    it('gets a 404 from DELETE rather than a profile created behind their back', async () => {
      const res = await remove(customer, male.id);
      expect(res.statusCode).toBe(404);
      expect(res.json<Err>().error.code).toBe('PROVIDER_PROFILE_NOT_FOUND');
      expect(
        await app.deps.prisma.providerProfile.count({ where: { userId: customer.userId } }),
      ).toBe(0);
    });

    it('becomes a provider by adding one — §1a’s implicit creation, as the PATCH does', async () => {
      const res = await add(customer, male.id);
      expect(res.statusCode).toBe(200);
      expect(
        await app.deps.prisma.providerProfile.count({ where: { userId: customer.userId } }),
      ).toBe(1);
    });
  });

  it('never returns a phone number, at any depth, on any of these shapes', async () => {
    const res = await add(provider, male.id);
    expect(JSON.stringify(res.json())).not.toMatch(/\+960|phone/i);

    const profile = await app.inject({
      method: 'GET',
      url: '/v1/providers/me',
      headers: provider.headers,
    });
    const serviceAreas = profile.json<Envelope<OwnProviderDto>>().data.serviceAreas;
    expect(JSON.stringify(serviceAreas)).not.toMatch(/\+960|phone/i);
  });

  it('exports the provider’s own service areas, and only the current ones', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/v1/users/me/data-export',
      headers: provider.headers,
    });
    expect(res.statusCode).toBe(200);
    const exported = res.json<{ data: { providerServiceAreas: IslandDto[] } }>().data;
    expect(exported.providerServiceAreas.map((i) => i.id).sort()).toEqual(
      (await areasOf(provider)).map((i) => i.id).sort(),
    );
  });
});
