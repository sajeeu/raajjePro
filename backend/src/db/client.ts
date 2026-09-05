import { PrismaPg } from '@prisma/adapter-pg';

import { PrismaClient } from '../generated/prisma/client.js';

/**
 * The single Prisma client for the process.
 *
 * Prisma is the only database access path (backend/CLAUDE.md). Raw SQL is
 * reserved for what Prisma cannot express — the pg_cron tables and, later, the
 * gist exclusion constraint.
 */
export function createPrismaClient(databaseUrl: string): PrismaClient {
  const adapter = new PrismaPg({ connectionString: databaseUrl });
  return new PrismaClient({ adapter });
}
