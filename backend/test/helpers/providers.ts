import type {
  ProviderConductRecord,
  ProviderConductSource,
} from '../../src/modules/providers/conduct.js';
import { NO_CONDUCT } from '../../src/modules/providers/conduct.js';
import type { Prisma } from '../../src/generated/prisma/client.js';
import type { PublishedListingSource } from '../../src/modules/providers/visibility.js';

/**
 * The `Listing` table stand-in, for tests about §1a's *rule* rather than
 * about listings.
 *
 * §Phase 5 was sequenced before §Phase 8, so there was nothing to publish and
 * this is how those tests move a provider across §1a's line. It survives
 * Phase 8 because it still earns its place: a test of the visibility helper
 * should not have to build a publishable listing — six required fields, a
 * category, an island and an uploaded cover — to say "this provider has one".
 *
 * 🔧 **Predicate-shaped since Phase 8 (ledger P5-1).** The seam used to hand
 * back a set and the helper scanned candidates in batches; now the rule is
 * one SQL query, so the fake supplies `id IN (…)` over the providers it was
 * told about. `test/listings-visibility.test.ts` is where the same assertions
 * run against real published rows.
 */
export class FakeListings implements PublishedListingSource {
  private readonly published = new Set<string>();

  /** The provider has at least one published, active listing. */
  publish(providerId: string): void {
    this.published.add(providerId);
  }

  /** Their only listing went back to draft, or was hidden. */
  unpublish(providerId: string): void {
    this.published.delete(providerId);
  }

  havingPublishedListing(): Prisma.ProviderProfileWhereInput {
    return { id: { in: [...this.published] } };
  }
}

/** §1f's numbers, as Phase 11 will supply them. */
export class FakeConduct implements ProviderConductSource {
  private readonly records = new Map<string, ProviderConductRecord>();

  set(providerId: string, record: Partial<ProviderConductRecord>): void {
    this.records.set(providerId, { ...NO_CONDUCT, ...record });
  }

  metricsFor(providerIds: string[]): Promise<Map<string, ProviderConductRecord>> {
    const found = new Map<string, ProviderConductRecord>();
    for (const id of providerIds) {
      const record = this.records.get(id);
      if (record !== undefined) found.set(id, record);
    }
    return Promise.resolve(found);
  }
}
