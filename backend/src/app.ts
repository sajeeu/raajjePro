import Fastify, { type FastifyInstance } from 'fastify';
import {
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';

import type { Config } from './config/env.js';
import type { Clock } from './core/clock.js';
import { registerErrorHandling } from './core/error-handler.js';
import { genReqId, loggerOptions } from './core/logging.js';
import type { PrismaClient } from './generated/prisma/client.js';

export interface AppDeps {
  prisma: PrismaClient;
  clock: Clock;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
    deps: AppDeps;
  }
}

/**
 * Builds the API. Plugins register in a fixed order — logging and errors, then
 * (later tasks) admin session, rate limit, idempotency — then the modules under
 * /v1. Tests call this and use inject(); main.ts calls it and listens.
 */
// eslint-disable-next-line @typescript-eslint/require-await -- stays async: later tasks add awaited plugin registration (rate limit, cookie, cors) here
export async function buildApp(config: Config, deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({
    logger: loggerOptions(config),
    genReqId,
    requestIdHeader: false,
    trustProxy: config.trustProxy,
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);
  app.decorate('config', config);
  app.decorate('deps', deps);

  app.addHook('onSend', async (request, reply) => {
    void reply.header('x-request-id', request.id);
  });

  registerErrorHandling(app);

  return app;
}
