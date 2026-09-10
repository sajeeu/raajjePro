import type { PrismaClient } from '../../generated/prisma/client.js';
import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import type { SubscriptionBookingSource } from './bookings.js';
import { DAY_MS } from './period.js';

/**
 * §1b's downgrade and restore — one function, both directions.
 *
 * > **Downgrade is non-destructive and reversible.** Listings beyond the
 * > free-tier cap are hidden (`visibility: 'hidden_over_cap'`), never deleted.
 * > Analytics disable. Badge is unaffected. **Any confirmed payment restores
 * > everything.** Basic discoverability of the remaining listing is never
 * > affected.
 *
 * ## Why hiding and restoring are the same call
 *
 * §1b's requirement is that "**upgrade restores exactly what downgrade hid**",
 * and the safest way to guarantee that is to have one function decide which
 * listings a provider's current entitlement lets them keep live, and reconcile
 * to it. On premium the cap is unlimited, every candidate is kept, and every
 * `hidden_over_cap` row comes back — the restore is not a separate code path
 * that could drift from the hide.
 *
 * ## The two values this function owns, and the two it must never touch
 *
 * §1b, Round 17: "`hidden_over_cap` is set and cleared **only** by the
 * entitlement system; `hidden_by_provider` **only** by the provider,
 * `hidden_by_admin` only by moderation." Under a single `hidden` value the
 * first two are indistinguishable and a paid upgrade would silently republish
 * something the provider had deliberately withdrawn. So the candidate query
 * below matches exactly `active` and `hidden_over_cap`, and a
 * provider-hidden or admin-hidden listing is invisible to this file.
 */

/** §1b's ranking window: "confirmed bookings over the trailing 90 days". */
export const PERFORMANCE_WINDOW_DAYS = 90;

export interface EntitlementVisibilityResult {
  cap: number;
  /** Ids that stayed or became `active`. */
  keptVisible: string[];
  /** Ids newly stamped `hidden_over_cap` by this call. */
  hidden: string[];
  /** Ids brought back from `hidden_over_cap` to `active` by this call. */
  restored: string[];
  /** Ids kept only because §1b protects them — a committed future job. */
  protectedFromHiding: string[];
}

interface Candidate {
  id: string;
  visibility: 'active' | 'hidden_over_cap';
  firstPublishedAt: Date | null;
  createdAt: Date;
}

/**
 * Reconcile one provider's live listings against their entitlement cap.
 *
 * Called on downgrade, on upgrade, and by the lifecycle job — which is how
 * §Phase 8a's Done-when clause "hides it the moment that booking completes"
 * is met without a booking hook: the protection is re-asked every sweep, so a
 * listing loses it as soon as its booking reaches a terminal state.
 * §Phase 17.1 may call this directly on that transition to make "the moment"
 * exact rather than within a sweep.
 */
export async function applyEntitlementVisibility(
  prisma: PrismaClient,
  bookings: SubscriptionBookingSource,
  providerProfileId: string,
  cap: number,
  now: Date,
): Promise<EntitlementVisibilityResult> {
  const candidates = await prisma.listing.findMany({
    where: {
      providerProfileId,
      // Composed from the one definition of a publicly visible listing rather
      // than restated (§1a's argument: a rule copied per query is a rule that
      // drifts). Only `visibility` is widened, to the two values this
      // function is allowed to move between.
      status: PUBLICLY_VISIBLE_LISTING.status,
      deletedAt: PUBLICLY_VISIBLE_LISTING.deletedAt,
      visibility: { in: ['active', 'hidden_over_cap'] },
    },
    select: { id: true, visibility: true, firstPublishedAt: true, createdAt: true },
  });

  const ids = candidates.map((c) => c.id);
  const protectedIds = new Set(
    ids.length === 0 ? [] : await bookings.listingIdsWithCommittedBooking(ids),
  );

  const unprotected = candidates.filter((c) => !protectedIds.has(c.id));
  const ranked = await rankByPerformance(prisma, unprotected as Candidate[], now);

  // §1b: a protected listing "stays visible regardless of cap", so protected
  // rows are kept first and fill the cap before anything else. The slots left
  // over — never fewer than none — go to the highest-performing unprotected
  // listings. A provider whose committed jobs already exceed their cap keeps
  // all of them and nothing else, which is the only reading under which both
  // halves of §1b hold at once.
  const slotsForUnprotected = Math.max(0, cap - protectedIds.size);
  const keep = new Set<string>([
    ...protectedIds,
    ...ranked.slice(0, Number.isFinite(slotsForUnprotected) ? slotsForUnprotected : ranked.length),
  ]);

  const toHide = candidates.filter((c) => !keep.has(c.id) && c.visibility === 'active');
  const toRestore = candidates.filter((c) => keep.has(c.id) && c.visibility === 'hidden_over_cap');

  if (toHide.length > 0) {
    await prisma.listing.updateMany({
      where: { id: { in: toHide.map((c) => c.id) } },
      // Nothing else changes. `status` stays `published`, `publishedAt` and
      // `firstPublishedAt` stay, the media and service areas stay — §1b's
      // "non-destructive" is a promise about the row, not only about the
      // absence of a DELETE.
      data: { visibility: 'hidden_over_cap' },
    });
  }
  if (toRestore.length > 0) {
    await prisma.listing.updateMany({
      where: { id: { in: toRestore.map((c) => c.id) }, visibility: 'hidden_over_cap' },
      data: { visibility: 'active' },
    });
  }

  return {
    cap,
    keptVisible: [...keep],
    hidden: toHide.map((c) => c.id),
    restored: toRestore.map((c) => c.id),
    protectedFromHiding: [...protectedIds],
  };
}

/**
 * 🔧 §1b: "**among unprotected listings, keep the highest-performing one
 * visible** — ranked by confirmed bookings over the trailing 90 days, falling
 * back to listing views where booking counts tie, and only to recency where a
 * provider has neither. An earlier rule kept the *most recently updated*
 * listing, which a provider who knew the rule could game by touching their
 * preferred listing more often than the others, regardless of which actually
 * performed."
 *
 * Three deliberate readings, because the sentence leaves three things open:
 *
 *  - **Views are counted over the same 90 days as bookings.** Rolled-up
 *    lifetime counters would let a listing that was popular last year outrank
 *    one customers are looking at this week, and §1b's whole framing is
 *    performance rather than history. The event log is what makes a windowed
 *    question answerable at all (`ListingEvent`, §Phase 8).
 *  - **"Recency" is `firstPublishedAt`, not `updatedAt`.** The rule this
 *    replaced was gameable *because* it read a field a provider can touch at
 *    will, and `updatedAt` is that field. `firstPublishedAt` is written once
 *    and never cleared (§Phase 8), so it cannot be bumped by editing.
 *  - **The final tiebreak is the id.** Two listings published in the same
 *    millisecond must still produce a stable answer; an unstable one would
 *    hide a different listing on every sweep.
 *
 * The tiebreaks matter more than they look right now: with no bookings until
 * §Phase 17.1 and no view events until the discovery phases, *every* listing
 * ties at zero and zero today, so recency decides — which is exactly why it
 * must not be the gameable field.
 */
async function rankByPerformance(
  prisma: PrismaClient,
  candidates: Candidate[],
  now: Date,
): Promise<string[]> {
  if (candidates.length <= 1) return candidates.map((c) => c.id);

  const since = new Date(now.getTime() - PERFORMANCE_WINDOW_DAYS * DAY_MS);
  const counts = await prisma.listingEvent.groupBy({
    by: ['listingId', 'kind'],
    where: { listingId: { in: candidates.map((c) => c.id) }, occurredAt: { gte: since } },
    _count: { _all: true },
  });

  const bookings = new Map<string, number>();
  const views = new Map<string, number>();
  for (const row of counts) {
    const into = row.kind === 'booking' ? bookings : views;
    into.set(row.listingId, row._count._all);
  }

  return [...candidates]
    .sort((a, b) => {
      const byBookings = (bookings.get(b.id) ?? 0) - (bookings.get(a.id) ?? 0);
      if (byBookings !== 0) return byBookings;
      const byViews = (views.get(b.id) ?? 0) - (views.get(a.id) ?? 0);
      if (byViews !== 0) return byViews;
      const byRecency = published(b) - published(a);
      if (byRecency !== 0) return byRecency;
      return a.id < b.id ? -1 : 1;
    })
    .map((c) => c.id);
}

/** `createdAt` only as a floor for a row published before `firstPublishedAt` existed; no listing predates §Phase 8. */
function published(candidate: Candidate): number {
  return (candidate.firstPublishedAt ?? candidate.createdAt).getTime();
}
