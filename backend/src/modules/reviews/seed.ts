import type { PrismaClient } from '../../generated/prisma/client.js';
import type { ReviewTagSentiment } from '../../generated/prisma/enums.js';

interface TagSeed {
  key: string;
  label: string;
  sentiment: ReviewTagSentiment;
}

/**
 * §1f's tag set, verbatim and in the plan's order: "*On time · Fair price ·
 * Quality materials · Good communication · Left a mess · Arrived late · Poor
 * communication · Price changed on site.*"
 *
 * 🔧 **Every category gets these eight** (owner's decision, 2026-10-09,
 * decision 32). The plan specifies "six to eight fixed tags per category" but
 * names only this one set, and the design brief calls it Cleaning's; nothing
 * defines the other eleven. Seeding it as per-category rows means a category
 * can diverge later through data, without a schema change and without
 * touching a review already counted.
 */
export const REVIEW_TAG_SEED: readonly TagSeed[] = [
  { key: 'on_time', label: 'On time', sentiment: 'positive' },
  { key: 'fair_price', label: 'Fair price', sentiment: 'positive' },
  { key: 'quality_materials', label: 'Quality materials', sentiment: 'positive' },
  { key: 'good_communication', label: 'Good communication', sentiment: 'positive' },
  { key: 'left_a_mess', label: 'Left a mess', sentiment: 'negative' },
  { key: 'arrived_late', label: 'Arrived late', sentiment: 'negative' },
  { key: 'poor_communication', label: 'Poor communication', sentiment: 'negative' },
  { key: 'price_changed_on_site', label: 'Price changed on site', sentiment: 'negative' },
];

/**
 * Seeds the tag set onto every category (§Phase 11: "`ReviewTag` seeded per
 * category").
 *
 * **Create-if-absent, keyed on `(categoryId, key)`** — the categories seed's
 * pattern. A tag already present is left exactly as it is, so a later
 * per-category rewording or retirement is never reverted by a deploy.
 * Idempotent: safe to run on every deploy. Run after `seedCategories`.
 */
export async function seedReviewTags(prisma: PrismaClient): Promise<{ created: number }> {
  const categories = await prisma.category.findMany({ select: { id: true } });
  const { count } = await prisma.reviewTag.createMany({
    data: categories.flatMap((category) =>
      REVIEW_TAG_SEED.map((tag, i) => ({ categoryId: category.id, ...tag, sortOrder: i })),
    ),
    skipDuplicates: true,
  });
  return { created: count };
}
