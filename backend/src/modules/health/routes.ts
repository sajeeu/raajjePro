import type { FastifyInstance } from 'fastify';

import { ok } from '../../core/envelope.js';
import { InfrastructureError } from '../../core/errors.js';
import { readHeartbeat } from '../../jobs/heartbeat.js';

/**
 * GET /v1/health — public, no auth (it is what §5 measures availability
 * against). 503 when the database is unreachable: a dead database must never
 * read as up. A silent job runner is reported, not treated as down.
 */
export function registerHealthRoutes(app: FastifyInstance): void {
  app.get('/v1/health', async (_request, reply) => {
    const { prisma, clock } = app.deps;
    let heartbeat;
    try {
      heartbeat = await readHeartbeat(prisma, clock());
    } catch {
      throw new InfrastructureError('Database unreachable');
    }
    return reply.send(
      ok({
        status: 'ok',
        database: 'reachable',
        jobRunner: heartbeat.firing ? 'firing' : 'not-firing',
        lastHeartbeatAt: heartbeat.lastFiredAt?.toISOString() ?? null,
      }),
    );
  });
}
