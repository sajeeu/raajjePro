import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { seedCategories } from '../src/modules/categories/seed.js';
import type { AdminCategoryDto, CategoryDto } from '../src/modules/categories/types.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';
import { createEnrolledAdmin, CSRF, PASSWORD } from './helpers/admin.js';
import { cookieFrom } from './helpers/admin.js';
import { freshIp } from './helpers/app.js';
import { registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface Err {
  error: { code: string; details?: { path: string }[] };
}

/** A name no other run has used — the suite never deletes rows. */
const freshName = () => `Test Category ${randomUUID().slice(0, 8)}`;

describe.skipIf(databaseUrl === undefined)('Phase 4 — the category endpoints', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let cookie: string;
  /** Everything this file created, so `afterAll` can take it back out of the public catalogue. */
  const createdIds: string[] = [];

  const create = async (payload: Record<string, unknown>) => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/admin/categories',
      headers: { cookie, ...CSRF, 'idempotency-key': randomUUID() },
      payload,
    });
    if (res.statusCode === 201) createdIds.push(res.json<Envelope<AdminCategoryDto>>().data.id);
    return res;
  };

  /** The minimum a create needs: everything else has a default. */
  const minimal = (over: Record<string, unknown> = {}) => ({
    name: freshName(),
    description: 'A category created by the test suite.',
    iconIdentifier: 'hammer',
    colorToken: 'yellow',
    sortOrder: 900,
    bookingMode: 'request',
    minimumLeadTimeMinutes: 120,
    reason: 'test',
    ...over,
  });

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await seedCategories(app.deps.prisma);
    ({ cookie } = await createEnrolledAdmin(app));
  });

  afterAll(async () => {
    // The suite never deletes rows, and these would otherwise sit in the
    // public catalogue for every later run. Deactivating is the soft delete
    // the product itself uses (invariant 8), so nothing is destroyed.
    for (const id of createdIds) {
      await app.deps.prisma.category.update({ where: { id }, data: { isActive: false } });
    }
    await app.close();
  });

  describe('GET /v1/categories — public', () => {
    it('answers a signed-out caller', async () => {
      const res = await app.inject({ method: 'GET', url: '/v1/categories' });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<CategoryDto[]>>().data.length).toBeGreaterThanOrEqual(12);
    });

    it('returns them in sortOrder', async () => {
      const res = await app.inject({ method: 'GET', url: '/v1/categories' });
      const orders = res.json<Envelope<CategoryDto[]>>().data.map((c) => c.sortOrder);
      expect(orders).toEqual([...orders].sort((a, b) => a - b));
    });

    it('carries the whole seeded configuration, not just name and icon', async () => {
      const res = await app.inject({ method: 'GET', url: '/v1/categories' });
      const plumbing = res.json<Envelope<CategoryDto[]>>().data.find((c) => c.name === 'Plumbing');
      expect(plumbing).toMatchObject({
        bookingMode: 'request',
        emergencyCapable: true,
        emergencyMinimumTier: 'gold',
        emergencyAcceptWindowMinutes: 30,
        emergencyEtaPresetsMinutes: [15, 30, 45, 60],
        quoteExpiryMinutes: 120,
        quoteApprovalMinutes: 240,
        callbackEligible: true,
        minimumLeadTimeMinutes: 60,
      });
    });

    it('pages, and says so in the envelope', async () => {
      const first = await app.inject({ method: 'GET', url: '/v1/categories?limit=5' });
      const body = first.json<{ data: CategoryDto[]; meta: { nextCursor: string | null } }>();
      expect(body.data).toHaveLength(5);
      expect(body.meta.nextCursor).not.toBeNull();

      const second = await app.inject({
        method: 'GET',
        url: `/v1/categories?limit=5&cursor=${encodeURIComponent(body.meta.nextCursor ?? '')}`,
      });
      const page2 = second.json<{ data: CategoryDto[] }>().data;
      expect(page2).toHaveLength(5);
      // No overlap between pages, and the order continues.
      const firstIds = new Set(body.data.map((c) => c.id));
      expect(page2.some((c) => firstIds.has(c.id))).toBe(false);
      expect(page2[0]?.sortOrder).toBeGreaterThanOrEqual(
        body.data[body.data.length - 1]?.sortOrder ?? 0,
      );
    });

    it('walks the whole catalogue when a client follows the cursor', async () => {
      const seen: string[] = [];
      let cursor: string | null = null;
      for (let guard = 0; guard < 50; guard += 1) {
        const url: string =
          cursor === null
            ? '/v1/categories?limit=5'
            : `/v1/categories?limit=5&cursor=${encodeURIComponent(cursor)}`;
        const res = await app.inject({ method: 'GET', url });
        const body = res.json<{ data: CategoryDto[]; meta: { nextCursor: string | null } }>();
        seen.push(...body.data.map((c) => c.name));
        cursor = body.meta.nextCursor;
        if (cursor === null) break;
      }
      expect(cursor).toBeNull();
      expect(new Set(seen).size).toBe(seen.length); // nothing repeated
      expect(seen).toContain('Boat Charter'); // the last of the seeded twelve
    });

    it('treats a nonsense cursor as the first page rather than failing', async () => {
      const res = await app.inject({ method: 'GET', url: '/v1/categories?cursor=not-a-cursor' });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<CategoryDto[]>>().data.length).toBeGreaterThanOrEqual(12);
    });

    it('never exposes the soft-delete flag on the public shape', async () => {
      const res = await app.inject({ method: 'GET', url: '/v1/categories' });
      for (const c of res.json<Envelope<Record<string, unknown>[]>>().data) {
        expect(c).not.toHaveProperty('isActive');
        expect(c).not.toHaveProperty('createdAt');
      }
    });
  });

  describe('the admin surface is admin-only', () => {
    const routes: [string, string, Record<string, unknown> | undefined][] = [
      ['GET', '/v1/admin/categories', undefined],
      ['POST', '/v1/admin/categories', {}],
      ['PATCH', `/v1/admin/categories/${randomUUID()}`, {}],
      ['DELETE', `/v1/admin/categories/${randomUUID()}`, {}],
    ];

    const call = (
      method: string,
      url: string,
      payload: Record<string, unknown> | undefined,
      headers: Record<string, string>,
    ) =>
      app.inject({
        method: method as 'GET',
        url,
        headers: { ...CSRF, ...headers },
        ...(payload === undefined ? {} : { payload }),
      });

    it.each(routes)('refuses an unauthenticated %s %s', async (method, url, payload) => {
      expect((await call(method, url, payload, {})).statusCode).toBe(401);
    });

    // The wrong-actor case, not just the missing-actor one: a real customer
    // session is a valid principal that is simply not an admin, and it is the
    // one an authorization bug actually lets through.
    it.each(routes)('refuses a signed-in customer on %s %s', async (method, url, payload) => {
      const customer = await registerUser(app);
      const res = await call(method, url, payload, customer.headers);
      expect(res.statusCode).toBe(401);
    });

    // An admin who has authenticated but not passed MFA on this session.
    // `requireAdmin` is what stops them; nothing else on these routes would.
    it.each(routes)(
      'refuses an admin who has not passed MFA on %s %s',
      async (method, url, payload) => {
        // Enrolled, so the block is MFA on *this session* and nothing else.
        const { email } = await createEnrolledAdmin(app);
        const login = await app.inject({
          method: 'POST',
          url: '/v1/admin/auth/login',
          headers: CSRF,
          remoteAddress: freshIp(),
          payload: { email, password: PASSWORD },
        });
        const res = await call(method, url, payload, { cookie: cookieFrom(login) });
        expect([401, 403]).toContain(res.statusCode);
        expect(res.json<Err>().error.code).toBe('MFA_REQUIRED');
      },
    );
  });

  describe('POST — create', () => {
    it('creates a category and audits it', async () => {
      const payload = minimal();
      const res = await create(payload);
      expect(res.statusCode).toBe(201);
      const created = res.json<Envelope<AdminCategoryDto>>().data;
      expect(created).toMatchObject({ name: payload.name, isActive: true });

      const entry = await app.deps.prisma.auditLogEntry.findFirst({
        where: { targetType: 'category', targetId: created.id, action: 'category.created' },
      });
      expect(entry?.reason).toBe('test');
    });

    it('accepts a category name nothing in the system has heard of', async () => {
      // The Done-when's "13th category": no validator may enumerate the catalogue.
      const res = await create(minimal({ name: `Kayak Hire ${randomUUID().slice(0, 6)}` }));
      expect(res.statusCode).toBe(201);
    });

    it('refuses a duplicate name regardless of case', async () => {
      const payload = minimal();
      expect((await create(payload)).statusCode).toBe(201);
      const cased = await create({
        ...payload,
        name: payload.name.toUpperCase(),
      });
      expect(cased.statusCode).toBe(409);
      expect(cased.json<Err>().error.code).toBe('CATEGORY_NAME_TAKEN');
    });

    it('refuses a duplicate name', async () => {
      const payload = minimal();
      expect((await create(payload)).statusCode).toBe(201);
      const second = await create({ ...payload, name: payload.name });
      expect(second.statusCode).toBe(409);
      expect(second.json<Err>().error.code).toBe('CATEGORY_NAME_TAKEN');
    });

    it('refuses an emergency-capable category with no tier bar or answer window', async () => {
      const res = await create(minimal({ emergencyCapable: true }));
      expect(res.statusCode).toBe(422);
      const body = res.json<Err>();
      expect(body.error.code).toBe('CATEGORY_CONFIG_INCOHERENT');
      expect(body.error.details?.map((d) => d.path).sort()).toEqual([
        'emergencyAcceptWindowMinutes',
        'emergencyMinimumTier',
      ]);
    });

    it('refuses a tier bar on a category that is not emergency-capable', async () => {
      const res = await create(minimal({ emergencyMinimumTier: 'silver' }));
      expect(res.statusCode).toBe(422);
    });

    it('refuses one quote window without the other', async () => {
      const res = await create(minimal({ quoteExpiryMinutes: 120 }));
      expect(res.statusCode).toBe(422);
      expect(res.json<Err>().error.details?.[0]?.path).toBe('quoteApprovalMinutes');
    });

    it('accepts a fully-specified emergency category', async () => {
      const res = await create(
        minimal({
          emergencyCapable: true,
          emergencyMinimumTier: 'gold',
          emergencyAcceptWindowMinutes: 30,
          emergencyEtaPresetsMinutes: [15, 30],
          quoteExpiryMinutes: 120,
          quoteApprovalMinutes: 240,
        }),
      );
      expect(res.statusCode).toBe(201);
    });

    it('rejects a hex value where a colour token belongs', async () => {
      const res = await create(minimal({ colorToken: '#2563EB' }));
      expect(res.statusCode).toBe(400);
    });
  });

  describe('PATCH — update', () => {
    it('changes a field and records what changed', async () => {
      const created = (await create(minimal())).json<Envelope<AdminCategoryDto>>().data;
      const res = await app.inject({
        method: 'PATCH',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: { minimumLeadTimeMinutes: 45, reason: 'faster trade' },
      });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<AdminCategoryDto>>().data.minimumLeadTimeMinutes).toBe(45);

      const entry = await app.deps.prisma.auditLogEntry.findFirst({
        where: { targetId: created.id, action: 'category.updated' },
      });
      expect(entry?.metadata).toMatchObject({ changed: 'minimumLeadTimeMinutes' });
    });

    it('checks coherence against the resulting row, not against the patch alone', async () => {
      const created = (
        await create(
          minimal({
            emergencyCapable: true,
            emergencyMinimumTier: 'silver',
            emergencyAcceptWindowMinutes: 30,
          }),
        )
      ).json<Envelope<AdminCategoryDto>>().data;

      // Clearing the tier bar is only invalid because the stored row is capable.
      const res = await app.inject({
        method: 'PATCH',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: { emergencyMinimumTier: null, reason: 'oops' },
      });
      expect(res.statusCode).toBe(422);
      expect(res.json<Err>().error.details?.[0]?.path).toBe('emergencyMinimumTier');
    });

    it('404s an unknown id', async () => {
      const res = await app.inject({
        method: 'PATCH',
        url: `/v1/admin/categories/${randomUUID()}`,
        headers: { cookie, ...CSRF },
        payload: { sortOrder: 5, reason: 'x' },
      });
      expect(res.statusCode).toBe(404);
    });

    it('rejects a patch with nothing but a reason', async () => {
      const created = (await create(minimal())).json<Envelope<AdminCategoryDto>>().data;
      const res = await app.inject({
        method: 'PATCH',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: { reason: 'nothing to say' },
      });
      expect(res.statusCode).toBe(400);
    });
  });

  describe('DELETE — soft only', () => {
    it('deactivates the row rather than removing it, and can be undone', async () => {
      const created = (await create(minimal())).json<Envelope<AdminCategoryDto>>().data;

      const res = await app.inject({
        method: 'DELETE',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: { reason: 'withdrawn' },
      });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<AdminCategoryDto>>().data.isActive).toBe(false);

      // The row is still there (invariant 8) …
      const row = await app.deps.prisma.category.findUnique({ where: { id: created.id } });
      expect(row).not.toBeNull();

      // … gone from the public list …
      const publicList = await app.inject({ method: 'GET', url: '/v1/categories' });
      expect(publicList.json<Envelope<CategoryDto[]>>().data.some((c) => c.id === created.id)).toBe(
        false,
      );

      // … still on the admin list, which is the only route back …
      const adminList = await app.inject({
        method: 'GET',
        url: '/v1/admin/categories',
        headers: { cookie, ...CSRF },
      });
      expect(
        adminList.json<Envelope<AdminCategoryDto[]>>().data.some((c) => c.id === created.id),
      ).toBe(true);

      // … and reversible.
      const restored = await app.inject({
        method: 'PATCH',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: { isActive: true, reason: 'back' },
      });
      expect(restored.json<Envelope<AdminCategoryDto>>().data.isActive).toBe(true);

      // Leave the catalogue as it was found.
      await app.inject({
        method: 'DELETE',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: { reason: 'test cleanup' },
      });
    });

    it('requires a reason', async () => {
      const created = (await create(minimal())).json<Envelope<AdminCategoryDto>>().data;
      const res = await app.inject({
        method: 'DELETE',
        url: `/v1/admin/categories/${created.id}`,
        headers: { cookie, ...CSRF },
        payload: {},
      });
      expect(res.statusCode).toBe(400);
    });
  });
});
