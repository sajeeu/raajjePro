import type {
  ProviderConductRecord,
  ProviderConductSource,
} from '../../src/modules/providers/conduct.js';
import { NO_CONDUCT } from '../../src/modules/providers/conduct.js';
import type { PublishedListingSource } from '../../src/modules/providers/visibility.js';

/**
 * The `Listing` table stand-in. §Phase 5 is sequenced before §Phase 8, so
 * there is no listing to publish — what these tests assert is the rule §1a
 * states: a provider is visible if and only if the count of published, active
 * listings is above zero. `publish` / `unpublish` move a provider across that
 * line without a Listing schema Phase 5 has no business inventing.
 */
export class FakeListings implements PublishedListingSource {
  private readonly published = new Set<string>();
  /** Every batch this source was asked about — so a test can prove the helper batches rather than querying per provider. */
  readonly calls: string[][] = [];

  /** The provider has at least one published, active listing. */
  publish(providerId: string): void {
    this.published.add(providerId);
  }

  /** Their only listing went back to draft, or was hidden. */
  unpublish(providerId: string): void {
    this.published.delete(providerId);
  }

  providersWithPublishedListing(providerIds: string[]): Promise<Set<string>> {
    this.calls.push(providerIds);
    return Promise.resolve(new Set(providerIds.filter((id) => this.published.has(id))));
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
