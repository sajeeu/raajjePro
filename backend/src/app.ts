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
import './core/principal.js';
import type { PrismaClient } from './generated/prisma/client.js';
import { registerAdminAuthRoutes } from './modules/admin-auth/routes.js';
import { AdminAuthService } from './modules/admin-auth/service.js';
import { registerAuditRoutes } from './modules/audit/routes.js';
import { AuditService } from './modules/audit/service.js';
import { OtpService } from './modules/auth/otp.js';
import { registerAuthRoutes } from './modules/auth/routes.js';
import { AuthService } from './modules/auth/service.js';
import { EmailService } from './modules/email/service.js';
import { registerSesEventRoutes } from './modules/email/sns/routes.js';
import type { SnsMessageValidator } from './modules/email/sns/validator.js';
import type { EmailSender, EmailTransport } from './modules/email/types.js';
import { registerHealthRoutes } from './modules/health/routes.js';
import { registerAdminSession } from './plugins/admin-session.js';
import { registerIdempotency } from './plugins/idempotency.js';
import { registerRateLimit } from './plugins/rate-limit.js';
import { registerUserAuth } from './plugins/user-auth.js';

export interface AppDeps {
  prisma: PrismaClient;
  clock: Clock;
  emailTransport: EmailTransport;
  snsValidator: SnsMessageValidator;
  /** GETs an SNS SubscribeURL to confirm a subscription. Optional so production can default to a real fetch while tests observe the call. */
  confirmSubscription?: (url: string) => Promise<void>;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
    deps: AppDeps;
    audit: AuditService;
    adminAuth: AdminAuthService;
    auth: AuthService;
    email: EmailSender;
    otp: OtpService;
  }
}

/**
 * Builds the API. Plugins register in a fixed order — logging and errors,
 * then admin session (before rate limit, so counters see the principal),
 * rate limit, idempotency — then the modules under /v1. Tests call this and
 * use inject(); main.ts calls it and listens.
 */
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

  const audit = new AuditService(deps.prisma, deps.clock);
  app.decorate('audit', audit);
  app.decorate(
    'adminAuth',
    new AdminAuthService({ prisma: deps.prisma, audit, clock: deps.clock, config }),
  );
  const email = new EmailService(
    deps.prisma,
    deps.emailTransport,
    config.email,
    deps.clock,
    app.log,
  );
  app.decorate('email', email);
  const otp = new OtpService({ prisma: deps.prisma, email, clock: deps.clock, config });
  app.decorate('otp', otp);
  app.decorate(
    'auth',
    new AuthService({ prisma: deps.prisma, audit, clock: deps.clock, config, otp }),
  );

  app.addHook('onSend', async (request, reply) => {
    void reply.header('x-request-id', request.id);
  });

  registerErrorHandling(app);
  await registerAdminSession(app); // before rate limiting: counters key on the principal
  registerUserAuth(app);
  await registerRateLimit(app);
  registerIdempotency(app);

  registerHealthRoutes(app);
  registerAdminAuthRoutes(app);
  registerAuthRoutes(app);
  registerAuditRoutes(app);
  await registerSesEventRoutes(app);

  return app;
}
