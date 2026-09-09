import type { Writable } from 'node:stream';

import Fastify, { type FastifyInstance } from 'fastify';
import {
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';

import type { Config } from './config/env.js';
import type { Clock } from './core/clock.js';
import { registerErrorHandling } from './core/error-handler.js';
import { genReqId, loggerOptions, loggerOptionsForStream } from './core/logging.js';
import './core/principal.js';
import type { PrismaClient } from './generated/prisma/client.js';
import {
  AccountAnonymiser,
  AnonymisationHooks,
  neverBlocks,
  type DeletionBlocker,
} from './modules/account/anonymise.js';
import { ExportContributors } from './modules/account/export.js';
import { registerAccountRoutes } from './modules/account/routes.js';
import { AccountService } from './modules/account/service.js';
import { registerAdminAuthRoutes } from './modules/admin-auth/routes.js';
import { AdminAuthService } from './modules/admin-auth/service.js';
import { registerAuditRoutes } from './modules/audit/routes.js';
import { registerCategoryRoutes } from './modules/categories/routes.js';
import { CategoryService } from './modules/categories/service.js';
import { AuditService } from './modules/audit/service.js';
import { OtpService } from './modules/auth/otp.js';
import { PasswordResetService } from './modules/auth/password-reset.js';
import { registerAuthRoutes } from './modules/auth/routes.js';
import { AuthService } from './modules/auth/service.js';
import { SocialAuthRegistry, stubProviders } from './modules/auth/social.js';
import { EmailMessageLog } from './modules/email/log.js';
import { registerEmailLogRoutes } from './modules/email/log-routes.js';
import { EmailService } from './modules/email/service.js';
import { registerSesEventRoutes } from './modules/email/sns/routes.js';
import type { SnsMessageValidator } from './modules/email/sns/validator.js';
import type { EmailSender, EmailTransport } from './modules/email/types.js';
import { registerHealthRoutes } from './modules/health/routes.js';
import { NotificationDispatcher } from './modules/push/dispatcher.js';
import { NotificationHealth } from './modules/push/health.js';
import { DeviceTokenRepository } from './modules/push/repository.js';
import { registerPushRoutes } from './modules/push/routes.js';
import { PushService } from './modules/push/sender.js';
import { PushRegistrationService } from './modules/push/service.js';
import { FallbackSweep } from './modules/push/sweep.js';
import type { PushTransport } from './modules/push/types.js';
import { anonymiseAccountsJob } from './jobs/anonymise-accounts.js';
import { notificationHealthJob } from './jobs/notification-health.js';
import { pushFallbackJob } from './jobs/push-fallback.js';
import { JobRunner } from './jobs/runner.js';
import { registerAdminSession } from './plugins/admin-session.js';
import { registerIdempotency } from './plugins/idempotency.js';
import { registerRateLimit } from './plugins/rate-limit.js';
import { registerUserAuth } from './plugins/user-auth.js';

export interface AppDeps {
  prisma: PrismaClient;
  clock: Clock;
  emailTransport: EmailTransport;
  /** Phase 3c's vendor boundary. A file in development; FCM/APNs when they exist. */
  pushTransport: PushTransport;
  snsValidator: SnsMessageValidator;
  /** GETs an SNS SubscribeURL to confirm a subscription. Optional so production can default to a real fetch while tests observe the call. */
  confirmSubscription?: (url: string) => Promise<void>;
  /** Phase 17 supplies the real check; until then nothing blocks anonymisation. */
  deletionBlocker?: DeletionBlocker;
  /**
   * Test seam: when present, pino writes to this stream instead of stdout, so
   * a test can capture every log line a real run produces (the §Phase 3
   * Done-when no-PII assertion needs this — there is no supported way to
   * attach a stream to an already-built Fastify logger).
   */
  logStream?: Writable;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
    deps: AppDeps;
    account: AccountService;
    audit: AuditService;
    categories: CategoryService;
    exportContributors: ExportContributors;
    adminAuth: AdminAuthService;
    auth: AuthService;
    email: EmailSender;
    emailLog: EmailMessageLog;
    push: PushService;
    pushRegistration: PushRegistrationService;
    notifications: NotificationDispatcher;
    notificationHealth: NotificationHealth;
    otp: OtpService;
    passwordReset: PasswordResetService;
    social: SocialAuthRegistry;
    anonymisation: AnonymisationHooks;
    anonymiser: AccountAnonymiser;
    jobs: JobRunner;
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
    logger:
      deps.logStream !== undefined
        ? loggerOptionsForStream(config, deps.logStream)
        : loggerOptions(config),
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
  app.decorate('emailLog', new EmailMessageLog(deps.prisma));
  const otp = new OtpService({ prisma: deps.prisma, email, clock: deps.clock, config });
  app.decorate('otp', otp);
  const authService = new AuthService({
    prisma: deps.prisma,
    audit,
    clock: deps.clock,
    config,
    otp,
  });
  app.decorate('auth', authService);
  app.decorate(
    'passwordReset',
    new PasswordResetService({
      prisma: deps.prisma,
      repo: authService.repo,
      otp,
      audit,
      clock: deps.clock,
    }),
  );
  const exportContributors = new ExportContributors();
  app.decorate('exportContributors', exportContributors);
  app.decorate(
    'account',
    new AccountService({
      prisma: deps.prisma,
      repo: authService.repo,
      otp,
      audit,
      clock: deps.clock,
      exportContributors,
    }),
  );
  app.decorate('social', new SocialAuthRegistry(stubProviders()));

  // Phase 4. The catalogue every later module reads its per-category numbers
  // from — booking mode, lead time, quote windows, the emergency tier bar.
  app.decorate('categories', new CategoryService({ prisma: deps.prisma, audit }));

  // Phase 3c. `PushService` is the one sender every later module calls;
  // `NotificationDispatcher` is the only place the fallback rungs are written.
  const devices = new DeviceTokenRepository(deps.prisma, deps.clock);
  const push = new PushService({
    prisma: deps.prisma,
    transport: deps.pushTransport,
    devices,
    clock: deps.clock,
    log: app.log,
  });
  app.decorate('push', push);
  app.decorate(
    'pushRegistration',
    new PushRegistrationService({ prisma: deps.prisma, devices, clock: deps.clock }),
  );
  const notifications = new NotificationDispatcher({
    prisma: deps.prisma,
    push,
    email,
    clock: deps.clock,
    log: app.log,
  });
  app.decorate('notifications', notifications);
  const notificationHealth = new NotificationHealth({
    prisma: deps.prisma,
    clock: deps.clock,
    log: app.log,
  });
  app.decorate('notificationHealth', notificationHealth);

  const anonymisation = new AnonymisationHooks();
  // A deleted account must stop receiving pushes. Revoking inside the
  // anonymisation transaction means a hook failure leaves the user frozen and
  // their devices intact, to be retried — never half-done.
  anonymisation.register('push-devices', async (tx, userId, now) => {
    await tx.deviceToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: now, revokedReason: 'account_anonymised' },
    });
  });
  app.decorate('anonymisation', anonymisation);
  const anonymiser = new AccountAnonymiser({
    prisma: deps.prisma,
    repo: authService.repo,
    audit,
    hooks: anonymisation,
    log: app.log,
  });
  app.decorate('anonymiser', anonymiser);
  const jobs = new JobRunner({ prisma: deps.prisma, clock: deps.clock, log: app.log });
  jobs.register(anonymiseAccountsJob(anonymiser, deps.deletionBlocker ?? neverBlocks, app.log));
  jobs.register(
    pushFallbackJob(
      new FallbackSweep({
        prisma: deps.prisma,
        dispatcher: notifications,
        clock: deps.clock,
        log: app.log,
      }),
      app.log,
    ),
  );
  jobs.register(notificationHealthJob(notificationHealth, app.log));
  app.decorate('jobs', jobs);

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
  registerAccountRoutes(app);
  registerAuditRoutes(app);
  registerCategoryRoutes(app);
  registerPushRoutes(app);
  registerEmailLogRoutes(app);
  await registerSesEventRoutes(app);

  return app;
}
