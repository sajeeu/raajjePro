import type { PrismaClient } from '../../generated/prisma/client.js';
import type { ExportContributor } from '../account/export.js';
import { LocationRepository } from './repository.js';
import { toIslandDto } from './types.js';

/**
 * The provider's own service areas, in `GET /v1/users/me/data-export`
 * (§Phase 3: "export returns complete data").
 *
 * Registered rather than written into `AccountService`, which is what
 * `ExportContributors` exists for — the export grows from each module that
 * owns data, without the account module learning about any of them.
 *
 * Only the current list. A removed island is a soft-deleted join row
 * (invariant 8) and exporting it would tell the subject about a coverage
 * choice they already reversed, which is not what they asked for.
 */
export function serviceAreaExportContributor(prisma: PrismaClient): ExportContributor {
  const repo = new LocationRepository(prisma);
  return {
    key: 'providerServiceAreas',
    async collect(userId: string) {
      const profile = await prisma.providerProfile.findUnique({
        where: { userId },
        select: { id: true },
      });
      if (profile === null) return null;
      const rows = await repo.findCurrentServiceAreas(profile.id);
      return rows.map((row) => ({
        ...toIslandDto(row.island),
        addedAt: row.addedAt.toISOString(),
      }));
    },
  };
}
