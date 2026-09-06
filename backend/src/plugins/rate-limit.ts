import rateLimit, {
  type FastifyRateLimitStore,
  type FastifyRateLimitStoreCtor,
} from '@fastify/rate-limit';
import type { FastifyBaseLogger, FastifyInstance, FastifyRequest, RouteOptions } from 'fastify';

import { RateLimitedError } from '../core/errors.js';
import type { PrismaClient } from '../generated/prisma/client.js';

interface CounterRow {
  count: number;
  window_started_at: Date;
  // Computed by the same statement, in Postgres's own clock — see the note on
  // `incr()`. Prisma may hand this back as a string (or a Decimal-shaped
  // value) rather than a plain number, so it is coerced with `Number()`.
  ttl_ms: number | string;
}

/**
 * Rate-limit counters in PostgreSQL (decision: no Redis, no per-process
 * memory). One atomic upsert per counted request; the row for a (scope,
 * subject) is reused across windows and never deleted. See the UNLOGGED note
 * on the model.
 */
function createPostgresStore(
  prisma: PrismaClient,
  scope: string,
  log: FastifyBaseLogger,
): FastifyRateLimitStoreCtor {
  return class PostgresRateLimitStore implements FastifyRateLimitStore {
    // No explicit constructor: the plugin passes its global params object into
    // every store constructor, including per-route children created via
    // `child()` below, but we key entirely on `scope` (set from the factory's
    // closure) so there is nothing in it we need — the default constructor
    // (which ignores the argument) is sufficient.
    incr(
      key: string,
      callback: (error: Error | null, result?: { current: number; ttl: number }) => void,
      timeWindow: number,
    ): void {
      const fullKey = `${scope}|${key}`;
      const windowSeconds = timeWindow / 1000;
      prisma.$queryRaw<CounterRow[]>`
          INSERT INTO rate_limit_counter (key, count, window_started_at)
          VALUES (${fullKey}, 1, now())
          ON CONFLICT (key) DO UPDATE SET
            count = CASE
              WHEN rate_limit_counter.window_started_at + make_interval(secs => ${windowSeconds}) <= now() THEN 1
              ELSE rate_limit_counter.count + 1 END,
            window_started_at = CASE
              WHEN rate_limit_counter.window_started_at + make_interval(secs => ${windowSeconds}) <= now() THEN now()
              ELSE rate_limit_counter.window_started_at END
          -- ttl_ms is computed here, in the same statement, so only Postgres's
          -- clock is ever consulted for it. Node's Date.now() must never be
          -- mixed with window_started_at (a DB now()) to derive a remaining
          -- window — under clock drift that produces a wrong retryAfterSeconds
          -- in either direction. RETURNING sees the post-update row, so
          -- window_started_at here is already the current window's start.
          RETURNING count, window_started_at,
            GREATEST(EXTRACT(EPOCH FROM (rate_limit_counter.window_started_at + make_interval(secs => ${windowSeconds}) - now())) * 1000, 0) AS ttl_ms`
        .then((rows) => {
          const row = rows[0];
          if (row === undefined) {
            callback(new Error('rate limit upsert returned no row'));
            return;
          }
          callback(null, { current: row.count, ttl: Math.max(Math.ceil(Number(row.ttl_ms)), 1) });
        })
        .catch((error: unknown) => {
          // skipOnError: true (below) means the plugin lets the request
          // through on a store failure rather than 503-ing the whole API —
          // but that must not be silent, or an outage of this table quietly
          // disables rate limiting with nothing in the logs to show it.
          log.warn({ err: error }, 'rate-limit store unavailable; failing open');
          callback(error instanceof Error ? error : new Error(String(error)));
        });
    }

    // The package's .d.ts types this parameter as `RouteOptions & { path;
    // prefix }`, matching the plugin's *global* (no-route) child() call. On a
    // route carrying `config.rateLimit`, though, the plugin (index.js) builds
    // the merged params as `mergeParams(globalParams, routeOptions.config.rateLimit,
    // { routeInfo: routeOptions })` and calls `store.child(mergedRateLimitParams)`
    // — so at runtime this argument is the *merged rate-limit params object*,
    // and the actual route sits at `.routeInfo` (method/url/prefix/path), not
    // at the top level. We type the parameter as the d.ts demands to satisfy
    // the compiler, then read `routeInfo` off it via a narrow cast to the
    // shape the plugin actually sends.
    child(params: RouteOptions & { path: string; prefix: string }): FastifyRateLimitStore {
      const info = (
        params as unknown as {
          routeInfo?: { method?: string | string[]; url?: string; path?: string; prefix?: string };
        }
      ).routeInfo;
      const childScope =
        info === undefined
          ? `${scope}:child`
          : `${String(info.method ?? '*')} ${info.prefix ?? ''}${info.url ?? info.path ?? ''}`;
      return new (createPostgresStore(prisma, childScope, log))({});
    }
  };
}

function subjectKey(request: FastifyRequest): string {
  return request.principal ? `u:${request.principal.id}` : `ip:${request.ip}`;
}

/**
 * Global tiers (plan §Phase 2): anonymous per IP, authenticated per principal.
 * A route's `config.rateLimit` replaces the global tier for that route — that
 * is the per-endpoint override mechanism the plan asks for.
 */
export async function registerRateLimit(app: FastifyInstance): Promise<void> {
  const { anonPerMinute, authPerMinute } = app.config.rateLimit;
  await app.register(rateLimit, {
    global: true,
    store: createPostgresStore(app.deps.prisma, 'global', app.log),
    keyGenerator: subjectKey,
    max: (request: FastifyRequest) => (request.principal ? authPerMinute : anonPerMinute),
    timeWindow: '1 minute',
    // A store failure must not take the API down with it, so it fails open —
    // the request is let through uncounted. The store itself logs a warning
    // when this happens (see the `.catch()` in createPostgresStore's incr());
    // @fastify/rate-limit does not log anything on its own here.
    skipOnError: true,
    addHeadersOnExceeding: {
      'x-ratelimit-limit': true,
      'x-ratelimit-remaining': true,
      'x-ratelimit-reset': true,
    },
    addHeaders: {
      'x-ratelimit-limit': true,
      'x-ratelimit-remaining': true,
      'x-ratelimit-reset': true,
      'retry-after': true,
    },
    errorResponseBuilder: (_request, context) =>
      new RateLimitedError(Math.max(Math.ceil(context.ttl / 1000), 1)),
  });
}
