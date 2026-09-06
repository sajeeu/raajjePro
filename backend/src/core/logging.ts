import { randomUUID } from 'node:crypto';
import type { IncomingMessage } from 'node:http';

import type { FastifyServerOptions } from 'fastify';

import type { Config } from '../config/env.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Correlation id: a client-supplied X-Request-Id is honoured only when it is a
 * UUID — anything else is replaced, so a header cannot inject into the log.
 */
export function genReqId(req: IncomingMessage): string {
  const given = req.headers['x-request-id'];
  const value = Array.isArray(given) ? given[0] : given;
  return value !== undefined && UUID.test(value) ? value.toLowerCase() : randomUUID();
}

/**
 * Keys that must never reach a log line unredacted. fast-redact wildcards
 * match an exact depth — `*.email` catches `{ user: { email } }` but not a
 * top-level `{ email }` — so each key is repeated at every depth we redact.
 */
const SENSITIVE_KEYS = ['password', 'email', 'phone', 'code', 'token', 'secret', 'recoveryCodes'];

/** Depths 0 (bare key) through 3 (three levels of nesting). */
const REDACTED_DEPTH = 3;

function sensitiveKeyPaths(): string[] {
  const paths: string[] = [];
  for (let depth = 0; depth <= REDACTED_DEPTH; depth += 1) {
    const prefix = '*.'.repeat(depth);
    for (const key of SENSITIVE_KEYS) {
      paths.push(`${prefix}${key}`);
    }
  }
  return paths;
}

/**
 * Structured logging with no PII (plan §Phase 2). Redaction is by key name at
 * the top level and up to three levels of nesting — anything logged deeper
 * than that must not carry sensitive data in the first place, since no
 * wildcard depth covers it. Bodies are never logged at all because no
 * serializer includes them.
 */
export function loggerOptions(config: Config): NonNullable<FastifyServerOptions['logger']> {
  return {
    level: config.logLevel,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'res.headers["set-cookie"]',
        ...sensitiveKeyPaths(),
      ],
      censor: '[redacted]',
    },
    serializers: {
      req(req) {
        return {
          method: req.method,
          // Path only: a query string may carry an email or a reference code.
          path: req.url.split('?')[0],
          ip: req.ip,
        };
      },
      res(res) {
        return { statusCode: res.statusCode };
      },
    },
  };
}
