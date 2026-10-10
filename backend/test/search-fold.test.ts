import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { MAX_TOKENS, searchTokens } from '../src/modules/search/fold.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

/**
 * The query is folded in TypeScript and the text in SQL, and a token only
 * finds what it should if both sides fold the same way. So this compares
 * them directly: for each awkward input, the query-side words must equal the
 * words `rp_search_fold` produces.
 */
const SAMPLES = [
  'Malé',
  "Kon'dey",
  'Kon’dey Works',
  'ADh. Kun’burudhoo',
  'A/C Repair — 100%',
  'Deep_Clean %wild%',
  '  Sofa   SHAMPOO  ',
  'Fuvahmulah',
  'Café crème',
];

describe('search fold — pure', () => {
  it('drops accents, apostrophes and case, and splits words on everything else', () => {
    expect(searchTokens("Kon'dey Malé")).toEqual(['kondey', 'male']);
    expect(searchTokens('A/C repair')).toEqual(['a', 'c', 'repair']);
    expect(searchTokens('%_')).toEqual([]);
    expect(searchTokens(undefined)).toEqual([]);
  });

  it('deduplicates and caps the number of words', () => {
    expect(searchTokens('sofa sofa SOFA')).toEqual(['sofa']);
    expect(searchTokens('a b c d e f g h i j k')).toHaveLength(MAX_TOKENS);
  });
});

describe.skipIf(databaseUrl === undefined)('search fold — TypeScript and SQL agree', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  beforeAll(async () => {
    ({ app } = await buildTestApp());
  });
  afterAll(async () => {
    await app.close();
  });

  it.each(SAMPLES)('%s', async (sample) => {
    const rows = await app.deps.prisma.$queryRaw<{ folded: string }[]>`
      SELECT public.rp_search_fold(${sample}) AS folded
    `;
    const sqlWords = (rows[0]?.folded ?? '').split(' ').filter((w) => w.length > 0);
    expect(searchTokens(sample)).toEqual([...new Set(sqlWords)].slice(0, MAX_TOKENS));
  });
});
