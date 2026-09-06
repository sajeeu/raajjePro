import { createHash } from 'node:crypto';

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

import { canonicalJson } from '../core/canonical-json.js';
import { AppError, BusinessRuleError, ConflictError } from '../core/errors.js';
import { Prisma } from '../generated/prisma/client.js';

declare module 'fastify' {
  interface FastifyContextConfig {
    idempotency?: { operation: string };
  }
  interface FastifyRequest {
    idempotencyRecordId?: string;
  }
}

const HEADER = 'idempotency-key';

// A record left `in_progress` by a hard crash (the process died before the
// onSend hook ever ran, so nothing moved it to `abandoned`) would otherwise
// answer 409 forever — no other path ever revisits an in_progress record.
// Every handler behind this middleware in this codebase completes in well
// under a second, so anything still `in_progress` a full minute later is
// certainly dead, not merely slow. This is a fact about this codebase's
// handlers, not an operational tradeoff, so it is a fixed constant rather
// than a config value — there is nothing for an operator to legitimately
// tune it against.
const IN_PROGRESS_STALE_MS = 60_000;

function inProgress(): ConflictError {
  return new ConflictError('IDEMPOTENT_REQUEST_IN_PROGRESS', 'The same request is being processed');
}

/** The same hash the preHandler computes, exported so tests can seed a record the middleware will recognise as matching a given request. */
export function requestHashFor(method: string, path: string, body: unknown): string {
  return createHash('sha256')
    .update(`${method} ${path}\n${canonicalJson(body ?? null)}`)
    .digest('hex');
}

function sendReplay(
  reply: FastifyReply,
  record: {
    responseStatus: number | null;
    responseHeaders: Prisma.JsonValue;
    responseBody: Prisma.JsonValue;
  },
) {
  const headers = (record.responseHeaders ?? {}) as Record<string, string>;
  void reply.code(record.responseStatus ?? 200);
  for (const [name, value] of Object.entries(headers)) void reply.header(name, value);
  void reply.header('idempotent-replayed', 'true');
  return reply.send(record.responseBody);
}

/**
 * Idempotency (plan §2, §Phase 2): keyed on (subject, operation, clientKey).
 * The first request with a key runs; a repeat with the same body replays the
 * stored response; the same key with a different body is refused. Records are
 * kept forever. The subject is the principal; before Phase 3 defines user
 * registration, an anonymous request falls back to its IP.
 */
export function registerIdempotency(app: FastifyInstance): void {
  const { prisma } = app.deps;

  app.addHook('preHandler', async (request: FastifyRequest, reply: FastifyReply) => {
    const opts = request.routeOptions.config.idempotency;
    if (opts === undefined) return;

    const header = request.headers[HEADER];
    const clientKey = Array.isArray(header) ? header[0] : header;
    if (clientKey === undefined || clientKey.length === 0 || clientKey.length > 128) {
      throw new AppError(400, 'IDEMPOTENCY_KEY_REQUIRED', 'Idempotency-Key header required', [
        { path: 'Idempotency-Key', message: 'header required, 1–128 characters' },
      ]);
    }

    const subject = request.principal ? request.principal.id : `anon:${request.ip}`;
    const requestHash = requestHashFor(
      request.method,
      request.url.split('?')[0] ?? '',
      request.body ?? null,
    );

    const inserted = await prisma.$queryRaw<{ id: string }[]>`
      INSERT INTO idempotency_record (id, subject, operation, client_key, request_hash, status, created_at)
      VALUES (gen_random_uuid(), ${subject}, ${opts.operation}, ${clientKey}, ${requestHash}, 'in_progress', now())
      ON CONFLICT (subject, operation, client_key) DO NOTHING
      RETURNING id`;
    const winner = inserted[0];
    if (winner !== undefined) {
      request.idempotencyRecordId = winner.id;
      return;
    }

    const existing = await prisma.idempotencyRecord.findUnique({
      where: { subject_operation_clientKey: { subject, operation: opts.operation, clientKey } },
    });
    if (existing === null) {
      throw inProgress();
    }
    if (existing.requestHash !== requestHash) {
      throw new BusinessRuleError(
        'IDEMPOTENCY_KEY_REUSED',
        'This Idempotency-Key was already used with a different request',
      );
    }
    if (existing.status === 'completed') {
      return sendReplay(reply, existing);
    }
    if (existing.status === 'in_progress') {
      // Same conditional-takeover shape as the abandoned case below — a
      // plain read-then-update would let several concurrent stale-record
      // retries all see `in_progress` + old `created_at` and all proceed.
      // Raw SQL because Prisma has no "conditional update, return the row
      // only if the WHERE matched" primitive; the WHERE clause is the whole
      // race guard, so it has to be one statement.
      const staleTakeover = await prisma.$queryRaw<{ id: string }[]>`
        UPDATE idempotency_record
        SET status = 'in_progress', created_at = now(), response_status = NULL, response_headers = NULL, response_body = NULL, completed_at = NULL
        WHERE id = ${existing.id} AND status = 'in_progress'
          AND created_at < now() - make_interval(secs => ${IN_PROGRESS_STALE_MS / 1000})
        RETURNING id`;
      const staleWinner = staleTakeover[0];
      if (staleWinner !== undefined) {
        request.idempotencyRecordId = staleWinner.id;
        return;
      }
      throw inProgress();
    }

    // existing.status === 'abandoned': the earlier attempt failed on our
    // side. The takeover itself must be one atomic, conditional statement —
    // a plain read-then-update here would reopen exactly the race the INSERT
    // above already guards against for a brand-new key: several concurrent
    // requests could all read `abandoned` and all proceed to run the handler.
    const takeover = await prisma.$queryRaw<{ id: string }[]>`
      UPDATE idempotency_record
      SET status = 'in_progress', response_status = NULL, response_headers = NULL, response_body = NULL, completed_at = NULL
      WHERE id = ${existing.id} AND status = 'abandoned'
      RETURNING id`;
    const takeoverWinner = takeover[0];
    if (takeoverWinner !== undefined) {
      request.idempotencyRecordId = takeoverWinner.id;
      return;
    }

    // Lost the takeover race — another request already claimed (or, by now,
    // completed) this record. Re-read and respond from its current state.
    const after = await prisma.idempotencyRecord.findUnique({ where: { id: existing.id } });
    if (after !== null && after.status === 'completed' && after.requestHash === requestHash) {
      return sendReplay(reply, after);
    }
    throw inProgress();
  });

  app.addHook('onSend', async (request, reply, payload: unknown) => {
    const id = request.idempotencyRecordId;
    if (id === undefined) return payload;
    const status = reply.statusCode;
    const transient = status >= 500 || status === 429;
    const contentType = reply.getHeader('content-type');
    // The response body is stored as the raw serialized string, not parsed
    // back into an object — Postgres's jsonb reorders object keys by length
    // then alphabetically, which would make a replayed body byte-different
    // from the original even though the content is equivalent. Storing (and
    // later replaying) the exact string sidesteps that.
    await prisma.idempotencyRecord.update({
      where: { id },
      data: transient
        ? { status: 'abandoned', completedAt: new Date() }
        : {
            status: 'completed',
            responseStatus: status,
            responseHeaders: typeof contentType === 'string' ? { 'content-type': contentType } : {},
            responseBody: typeof payload === 'string' ? payload : Prisma.JsonNull,
            completedAt: new Date(),
          },
    });
    return payload;
  });
}
