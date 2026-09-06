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
 * Structured logging with no PII (plan §Phase 2). Redaction is by key name at
 * any depth, so a new log call cannot leak an email by accident; bodies are
 * never logged at all because no serializer includes them.
 */
export function loggerOptions(config: Config): NonNullable<FastifyServerOptions['logger']> {
  return {
    level: config.logLevel,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'res.headers["set-cookie"]',
        '*.password',
        '*.email',
        '*.phone',
        '*.code',
        '*.token',
        '*.secret',
        '*.recoveryCodes',
        '*.*.password',
        '*.*.email',
        '*.*.phone',
        '*.*.code',
        '*.*.token',
        '*.*.secret',
        '*.*.recoveryCodes',
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
