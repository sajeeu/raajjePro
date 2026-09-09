import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { seedCategories } from '../src/modules/categories/seed.js';
import type { AdminCategoryDto, CategoryDto } from '../src/modules/categories/types.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';
import { createEnrolledAdmin, CSRF } from './helpers/admin.js';

interface Envelope<T> {
  data: T;
}

/**
 * §Phase 4's own Done-when list, one test per line. The third line — the grid
 * rendering with no rebuild — is finished on the client, in
 * `frontend/test/features/explore/explore_screen_test.dart`; what is provable
 * here is that the API half holds up.
 */
describe.skipIf(databaseUrl === undefined)('§Phase 4 Done-when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let cookie: string;
  let thirteenthId: string | undefined;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await seedCategories(app.deps.prisma);
    ({ cookie } = await createEnrolledAdmin(app));
  });

  afterAll(async () => {
    if (thirteenthId !== undefined) {
      await app.deps.prisma.category.update({
        where: { id: thirteenthId },
        data: { isActive: false },
      });
    }
    await app.close();
  });

  it('a 13th category added via the API is served to the client with no rebuild', async () => {
    const name = `Kayak Hire ${randomUUID().slice(0, 6)}`;
    const created = await app.inject({
      method: 'POST',
      url: '/v1/admin/categories',
      headers: { cookie, ...CSRF, 'idempotency-key': randomUUID() },
      payload: {
        name,
        description: 'Kayak and paddleboard hire.',
        // A token the shipped client has never seen: it must fall back to a
        // neutral accent rather than fail, which is what makes "no rebuild"
        // true rather than merely untested.
        iconIdentifier: 'kayak',
        colorToken: 'teal',
        sortOrder: 13,
        bookingMode: 'request',
        minimumLeadTimeMinutes: 240,
        reason: 'Done-when: a thirteenth category',
      },
    });
    expect(created.statusCode).toBe(201);
    thirteenthId = created.json<Envelope<AdminCategoryDto>>().data.id;

    // Nothing was redeployed between these two calls.
    const list = await app.inject({ method: 'GET', url: '/v1/categories' });
    const grid = list.json<Envelope<CategoryDto[]>>().data;
    const thirteenth = grid.find((c) => c.id === thirteenthId);
    expect(thirteenth).toBeDefined();
    expect(thirteenth?.name).toBe(name);
    // It sorts after the seeded twelve, so the grid order is the endpoint's.
    expect(grid.at(-1)?.id).toBe(thirteenthId);
  });

  it('the seeded bookingMode and emergencyCapable are readable by a downstream module', async () => {
    // Read the way Phases 8, 9a and 17 will: through the decorated service on
    // the app instance, not over HTTP and not from the seed table.
    // `listAllPublic` is the cursor-walking read a downstream module wants —
    // it never has to think about paging.
    const catalogue = await app.categories.listAllPublic();
    const byName = new Map(catalogue.map((c) => [c.name, c]));

    expect(byName.get('Cleaning')?.bookingMode).toBe('slot');
    expect(byName.get('Plumbing')?.bookingMode).toBe('request');
    expect(byName.get('Plumbing')?.emergencyCapable).toBe(true);
    expect(byName.get('Cleaning')?.emergencyCapable).toBe(false);

    // And the numbers a downstream module must never hardcode come with them.
    expect(byName.get('Electrical')?.emergencyMinimumTier).toBe('gold');
    expect(byName.get('Moving')?.emergencyAcceptWindowMinutes).toBe(30);
    expect(byName.get('Home Repairs')?.quoteExpiryMinutes).toBe(120);
  });

  it('Boat Charter appears as request-based and not emergency-capable', async () => {
    const list = await app.inject({ method: 'GET', url: '/v1/categories' });
    const boat = list.json<Envelope<CategoryDto[]>>().data.find((c) => c.name === 'Boat Charter');
    expect(boat).toBeDefined();
    expect(boat?.bookingMode).toBe('request');
    expect(boat?.emergencyCapable).toBe(false);
    expect(boat?.emergencyMinimumTier).toBeNull();
    expect(boat?.emergencyAcceptWindowMinutes).toBeNull();
    expect(boat?.emergencyEtaPresetsMinutes).toEqual([]);
    // Request-based means it quotes — on the long window, with Photography and Moving.
    expect(boat?.quoteExpiryMinutes).toBe(1440);
    expect(boat?.quoteApprovalMinutes).toBe(4320);
    // And it carries trip-type occasion chips (Round 25).
    expect(boat?.occasionPresets).toContain('Fishing trip');
    expect(boat?.occasionPresets.at(-1)).toBe('Other');
  });
});
