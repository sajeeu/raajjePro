import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { IslandDto } from '../src/modules/location/types.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';
import { ensureIslandsSeeded } from './helpers/islands.js';

interface Envelope<T> {
  data: T;
}

/**
 * `GET /v1/islands?search=` — §Phase 7's second bullet, against the rules
 * §0.0 item 12 states for it.
 *
 * Every assertion here is one clause of that item. They are written against
 * the *behaviour* a customer sees — which islands come back and in what order
 * — rather than against the normalisation function, which is separately
 * unit-tested: a search that normalised perfectly and then filtered on the
 * wrong column would pass the unit test and fail every line below.
 */
describe.skipIf(databaseUrl === undefined)('Phase 7 — island search', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  const search = async (term?: string) => {
    const url =
      term === undefined ? '/v1/islands' : `/v1/islands?search=${encodeURIComponent(term)}`;
    const res = await app.inject({ method: 'GET', url });
    expect(res.statusCode).toBe(200);
    return res.json<Envelope<IslandDto[]>>().data;
  };

  const names = async (term?: string) => (await search(term)).map((i) => i.displayName);

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    await ensureIslandsSeeded(app.deps.prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  it('is public — the picker is in the header of the first screen a guest sees', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/islands?search=kulhudhuffushi' });
    expect(res.statusCode).toBe(200);
  });

  it('matches anywhere in the name, not just at the start', async () => {
    const found = await names('dhoo');
    expect(found).toContain('Kudahuvadhoo');
    expect(found).toContain('Fonadhoo');
    expect(found).toContain('Rasmaadhoo');
    // "anywhere" means the match is genuinely internal, not a prefix.
    expect(found.every((n) => n.toLowerCase().startsWith('dhoo'))).toBe(false);
  });

  it('matches from the very first character typed', async () => {
    expect((await search('k')).length).toBeGreaterThan(1);
  });

  it('ranks prefix matches ahead of internal ones', async () => {
    const found = await names('mee');
    const firstInternal = found.findIndex((n) => !bare(n).toLowerCase().startsWith('mee'));
    const lastPrefix = found.map((n) => bare(n).toLowerCase().startsWith('mee')).lastIndexOf(true);
    expect(firstInternal).toBeGreaterThan(-1);
    expect(lastPrefix).toBeLessThan(firstInternal);
  });

  it('matches the atoll code too — with a space, without one, and alone', async () => {
    expect(await names('dh mee')).toContain('Dh. Meedhoo');
    expect(await names('dhmee')).toContain('Dh. Meedhoo');

    const gdh = await search('gdh');
    expect(gdh.length).toBeGreaterThan(1);
    expect(gdh.every((i) => i.atollAbbr === 'GDh')).toBe(true);
  });

  it('ignores case', async () => {
    expect(await names('KULHUDHUFFUSHI')).toEqual(await names('kulhudhuffushi'));
  });

  it('ignores accents — `male` finds the register’s `Male’`, and so does `Malé`', async () => {
    const plain = await search('male');
    const accented = await search('Malé');
    expect(plain.map((i) => i.id)).toEqual(accented.map((i) => i.id));
    expect(plain.some((i) => i.name === "Male'")).toBe(true);
  });

  it('ignores the Dhivehi apostrophe on BOTH sides', async () => {
    const without = await search('Angolhitheemu');
    const with_ = await search("An'golhitheemu");
    expect(without.map((i) => i.name)).toContain("An'golhitheemu");
    expect(with_.map((i) => i.id)).toEqual(without.map((i) => i.id));
  });

  it('returns every match with no cap and no page cursor', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/islands?search=dhoo' });
    const body = res.json<{ data: IslandDto[]; meta?: Record<string, unknown> }>();
    expect(body.data.length).toBeGreaterThan(20);
    // Truncating hides the one island the customer came for, so there is
    // nothing here that could carry a "show more".
    expect(body.meta?.nextCursor).toBeUndefined();

    // An empty search is the whole register, also uncapped.
    expect((await search()).length).toBeGreaterThanOrEqual(192);
    expect((await search('')).length).toBeGreaterThanOrEqual(192);
  });

  it('returns a lone match as a list of one — it never auto-selects', async () => {
    const found = await search('kulhudhuffushi');
    expect(found).toHaveLength(1);
    // No field on the shape can say "this one is chosen": choosing is the
    // customer's act, and a picker that resolved it for them could not be
    // corrected when it guessed the wrong Meedhoo.
    expect(Object.keys(found[0] ?? {}).sort()).toEqual([
      'atollAbbr',
      'atollName',
      'displayName',
      'id',
      'name',
      'nameAmbiguous',
    ]);
  });

  it('qualifies an ambiguous name with its atoll code and leaves a unique one bare', async () => {
    const found = await search('meedhoo');
    // The three exact Meedhoos rank first; `Hangnaameedhoo` is a genuine
    // internal match and follows them rather than being filtered out.
    expect(found.slice(0, 3).map((i) => i.displayName)).toEqual([
      'Dh. Meedhoo',
      'R. Meedhoo',
      'S. Meedhoo',
    ]);
    expect(found.map((i) => i.displayName)).toContain('Hangnaameedhoo');

    const meedhoo = found.filter((i) => i.name === 'Meedhoo');
    expect(meedhoo.every((i) => i.nameAmbiguous)).toBe(true);
    // Every one of them still carries its own atoll, so a screen that stores
    // the pick cannot lose it.
    expect(meedhoo.map((i) => i.atollName).sort()).toEqual(['Dhaalu', 'Raa', 'Seenu']);

    const [kulhudhuffushi] = await search('kulhudhuffushi');
    expect(kulhudhuffushi?.displayName).toBe('Kulhudhuffushi');
    expect(kulhudhuffushi?.nameAmbiguous).toBe(false);
  });

  it('distinguishes Vilingili from Vilin’gili, which differ only by an apostrophe', async () => {
    const found = await search('vilingili');
    expect(found.map((i) => i.displayName).sort()).toEqual(["GA. Vilin'gili", 'K. Vilingili']);
  });

  it('returns nothing for a term no island matches, rather than a nearest guess', async () => {
    expect(await search('zzzznotanisland')).toEqual([]);
  });

  it('treats a LIKE wildcard as text, not as a pattern', async () => {
    // Under LIKE semantics `kulhu%ffushi` matches `Kulhudhuffushi`. It must
    // not: the query is normalised to `[a-z0-9]` before it reaches the
    // database, so the wildcard is dropped and `kulhuffushi` matches nothing.
    expect(await search('kulhu%ffushi')).toEqual([]);
    // And `kulhud_uffushi`, where LIKE's single-character `_` would match the `h`.
    expect(await search('kulhud_uffushi')).toEqual([]);
  });

  it('treats a term of only ignorable characters as no term at all', async () => {
    // Someone who has typed a space, a full stop or an apostrophe and nothing
    // else has not narrowed anything, and "No island matches" would be a lie.
    for (const noise of ['%', ' ', "'", '.']) {
      expect((await search(noise)).length).toBeGreaterThanOrEqual(192);
    }
  });

  it('excludes a deactivated island from search', async () => {
    const [target] = await search('kulhudhuffushi');
    if (target === undefined) throw new Error('expected Kulhudhuffushi');
    await app.deps.prisma.island.update({ where: { id: target.id }, data: { isActive: false } });
    try {
      expect(await search('kulhudhuffushi')).toEqual([]);
    } finally {
      await app.deps.prisma.island.update({ where: { id: target.id }, data: { isActive: true } });
    }
  });
});

/** Strips the `Dh. ` qualifier so a rank assertion reads the name the customer typed. */
function bare(displayName: string): string {
  return displayName.replace(/^[A-Za-z]+\.\s*/, '');
}
