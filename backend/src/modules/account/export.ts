export interface ExportContributor {
  /** The top-level key the section appears under. Stable — the export is a client-visible document. */
  key: string;
  collect(userId: string): Promise<unknown>;
}

/** The keys `AccountService.exportData` writes directly — a contributor spread after them must never be able to overwrite one. */
export const RESERVED_EXPORT_KEYS = ['exportedAt', 'account', 'providerProfile', 'sessions'];

/**
 * `GET /v1/users/me/data-export` (plan §Phase 3) grows by registration:
 * Phase 11 adds reviews, 17 bookings, 18 messages, each from its own module,
 * so the export is complete without this module knowing about them.
 */
export class ExportContributors {
  private readonly contributors = new Map<string, ExportContributor>();

  register(contributor: ExportContributor): void {
    if (RESERVED_EXPORT_KEYS.includes(contributor.key)) {
      throw new Error(`export section key is reserved for a core section: ${contributor.key}`);
    }
    if (this.contributors.has(contributor.key))
      throw new Error(`export section already registered: ${contributor.key}`);
    this.contributors.set(contributor.key, contributor);
  }

  async collectAll(userId: string): Promise<Record<string, unknown>> {
    const sections: Record<string, unknown> = {};
    for (const [key, contributor] of this.contributors)
      sections[key] = await contributor.collect(userId);
    return sections;
  }
}
