import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { LISTING_COUNT_ROLLUP_JOB_NAME } from '../src/jobs/listing-count-rollup.js';
import { buildTestApp, controllableClock, databaseUrl } from './helpers/app.js';
import { createDraft, ensureCategoriesSeeded } from './helpers/listings.js';
import { registerUser } from './helpers/users.js';

/**
 * §Phase 8: "view and booking counts come from an event log with periodic
 * rollup, **not per-request counter writes**".
 *
 * Time is advanced rather than waited on (backend/CLAUDE.md), and the job is
 * driven through the Phase 0 runner rather than by calling the service — the
 * bullet is about a *scheduled* rollup, so the registration is part of what
 * has to be true.
 */
describe.skipIf(databaseUrl === undefined)('listing count rollup', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  const time = controllableClock();

  beforeAll(async () => {
    ({ app } = await buildTestApp({ clock: time.clock }));
    await ensureCategoriesSeeded(app.deps.prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  async function freshListing() {
    const user = await registerUser(app, { role: 'provider' });
    return (await createDraft(app, user.headers, {})).id;
  }

  it('is registered on the Phase 0 runner, not run check-on-read', async () => {
    const ran = await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);
    expect(['ran', 'skipped']).toContain(ran);
  });

  it('folds logged events into the counters, and reading a count writes nothing', async () => {
    const listingId = await freshListing();

    for (let i = 0; i < 5; i += 1) await app.listings.events.record(listingId, 'view');
    await app.listings.events.record(listingId, 'booking');

    // Nothing has moved yet — an append is not an increment. This is the
    // whole point: `UPDATE listing SET view_count = view_count + 1` on every
    // impression serialises every reader of a popular listing behind one row
    // lock.
    const before = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listingId } });
    expect(before.viewCount).toBe(0);
    expect(before.bookingCount).toBe(0);
    expect(before.countsRolledUpAt).toBeNull();

    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);

    const after = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listingId } });
    expect(after.viewCount).toBe(5);
    expect(after.bookingCount).toBe(1);
    expect(after.countsRolledUpAt).not.toBeNull();
  });

  it('counts each event exactly once, however often the job runs', async () => {
    const listingId = await freshListing();
    await app.listings.events.record(listingId, 'view');
    await app.listings.events.record(listingId, 'view');

    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);
    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);
    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);

    // Idempotent by construction rather than by luck: the first run moved
    // the watermark past everything it counted.
    const row = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listingId } });
    expect(row.viewCount).toBe(2);
  });

  /**
   * The boundary, and the one that actually bit: an event stamped at
   * **exactly** the watermark instant.
   *
   * The clock does not advance between the first rollup and these two
   * records, so both land on the same timestamp the rollup just wrote as
   * `countsRolledUpAt`. Under an exclusive low bound (`> watermark`) they are
   * outside every window that will ever run and are lost forever — which is
   * what the first version of `rollUp` did, and what this test caught. The
   * window is `[watermark, now)` for exactly this reason.
   */
  it('counts an event stamped at exactly the previous run’s watermark', async () => {
    const listingId = await freshListing();
    await app.listings.events.record(listingId, 'view');
    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);
    const watermark = (
      await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listingId } })
    ).countsRolledUpAt;

    await app.listings.events.record(listingId, 'view');
    await app.listings.events.record(listingId, 'booking');
    const logged = await app.deps.prisma.listingEvent.findMany({
      where: { listingId },
      orderBy: { occurredAt: 'asc' },
    });
    // The premise of the test: these really are on the boundary.
    expect(logged.at(-1)?.occurredAt.getTime()).toBe(watermark?.getTime());

    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);

    const row = await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listingId } });
    expect(row.viewCount).toBe(2);
    expect(row.bookingCount).toBe(1);
  });

  it('keeps the rows, so a windowed question stays answerable', async () => {
    // §1b's downgrade rule ranks unprotected listings by "confirmed bookings
    // over the trailing 90 days, falling back to listing views". A counter
    // knows the total and nothing about when — the log is what makes
    // Phase 8a's rule computable at all, so the rollup must not consume it.
    const listingId = await freshListing();
    await app.listings.events.record(listingId, 'booking');
    time.advance(60_000);
    await app.jobs.runOnce(LISTING_COUNT_ROLLUP_JOB_NAME);

    const events = await app.deps.prisma.listingEvent.count({
      where: { listingId, kind: 'booking' },
    });
    expect(events).toBe(1);

    const since = new Date(time.clock().getTime() - 90 * 24 * 60 * 60 * 1000);
    const inWindow = await app.deps.prisma.listingEvent.count({
      where: { listingId, kind: 'booking', occurredAt: { gte: since } },
    });
    expect(inWindow).toBe(1);
  });

  it('records no viewer — the log carries an id, a kind and a time', async () => {
    // Root CLAUDE.md 1d: product/analytics event logs follow the same no-PII
    // rule as structured logging. A viewer column on an impression log is
    // easy to add now and hard to justify to anybody later, so there is not
    // one.
    const columns = await app.deps.prisma.$queryRaw<{ column_name: string }[]>`
      SELECT column_name FROM information_schema.columns WHERE table_name = 'listing_event'
    `;
    expect(columns.map((c) => c.column_name).sort()).toEqual([
      'id',
      'kind',
      'listing_id',
      'occurred_at',
    ]);
  });
});
