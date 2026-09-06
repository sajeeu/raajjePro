import type { FastifyError, FastifyInstance } from 'fastify';
import { hasZodFastifySchemaValidationErrors } from 'fastify-type-provider-zod';

import { fail } from './envelope.js';
import { AppError, RateLimitedError } from './errors.js';

/**
 * Global error handling (plan §Phase 2): every failure — ours, Fastify's own
 * 404 and body-parse errors, Zod validation — leaves as the standard envelope.
 * Unexpected errors are logged with the request id and replaced by a fixed
 * message; internals never reach a client.
 */
export function registerErrorHandling(app: FastifyInstance): void {
  app.setNotFoundHandler(async (request, reply) => {
    return reply.code(404).send(fail('NOT_FOUND', 'No such route', request.id));
  });

  app.setErrorHandler(async (error: FastifyError | AppError, request, reply) => {
    if (error instanceof AppError) {
      if (error instanceof RateLimitedError) {
        void reply.header('retry-after', String(error.retryAfterSeconds));
      }
      return reply
        .code(error.status)
        .send(fail(error.code, error.message, request.id, error.details));
    }

    if (hasZodFastifySchemaValidationErrors(error)) {
      const details = error.validation.map((v) => ({
        path: v.instancePath.replace(/^\//, '').replaceAll('/', '.'),
        message: v.message ?? 'Invalid value',
      }));
      return reply
        .code(400)
        .send(fail('VALIDATION_FAILED', 'Request failed validation', request.id, details));
    }

    const code = 'code' in error ? error.code : undefined;
    if (typeof code === 'string' && code.startsWith('FST_ERR_CTP_')) {
      return reply
        .code(400)
        .send(fail('MALFORMED_BODY', 'The request body could not be parsed', request.id));
    }

    request.log.error({ err: error }, 'unhandled error');
    return reply.code(500).send(fail('INTERNAL_ERROR', 'Something went wrong', request.id));
  });
}
