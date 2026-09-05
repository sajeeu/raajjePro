/**
 * Backend entrypoint.
 *
 * Phase 0 boot: load configuration, reach the database, confirm the job runner
 * is alive, report, exit 0. Phase 2 replaces the exit with the Fastify server
 * and the console lines with structured logging; nothing here is meant to
 * outlive that.
 */
import { requireEnv } from './config/env.js';
import { createPrismaClient } from './db/client.js';
import { readHeartbeat } from './jobs/heartbeat.js';

const databaseUrl = requireEnv('DATABASE_URL');
const nodeEnv = process.env.NODE_ENV ?? 'development';

const prisma = createPrismaClient(databaseUrl);

try {
  const [{ now }] = await prisma.$queryRaw<[{ now: Date }]>`SELECT now()`;
  const heartbeat = await readHeartbeat(prisma, now);

  console.log(
    JSON.stringify({
      event: 'backend.booted',
      env: nodeEnv,
      database: 'reachable',
      databaseTime: now.toISOString(),
      jobRunner: heartbeat.firing ? 'firing' : 'not-firing',
      lastHeartbeatAt: heartbeat.lastFiredAt?.toISOString() ?? null,
    }),
  );
} finally {
  await prisma.$disconnect();
}
