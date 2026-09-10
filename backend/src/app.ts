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
import { serviceAreaExportContributor } from './modules/location/export.js';
import { ListingEvents } from './modules/listings/events.js';
import type { ProviderEntitlementReader } from './modules/listings/entitlements.js';
import { registerListingRoutes } from './modules/listings/routes.js';
import { ListingService } from './modules/listings/service.js';
import { PUBLISHED_LISTINGS } from './modules/listings/visibility.js';
import { registerLocationRoutes } from './modules/location/routes.js';
import { LocationService } from './modules/location/service.js';
import { registerMediaRoutes } from './modules/media/routes.js';
import { MediaService } from './modules/media/service.js';
import { createMediaStorage } from './modules/media/transports/file.js';
import type { MediaStorage } from './modules/media/types.js';
import { registerProviderAnonymisation } from './modules/providers/anonymise.js';
import type { ProviderConductSource } from './modules/providers/conduct.js';
import { registerProviderRoutes } from './modules/providers/routes.js';
import { ProviderProfileService } from './modules/providers/service.js';
import type { PublishedListingSource } from './modules/providers/visibility.js';
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
import { listingCountRollupJob } from './jobs/listing-count-rollup.js';
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
   * §1a's published-listing predicate. Phase 8 supplies the real one over the
   * `listing` table; a test may substitute `FakeListings` to move a provider
   * across §1a's line without building a publishable listing.
   */
  publishedListings?: PublishedListingSource;
  /** Phase 8's object store. Defaults to the local file transport (§0.0 item 17). */
  mediaStorage?: MediaStorage;
  /** Phase 8a replaces this with `getProviderEntitlements`; until then every provider is on §1b's free tier. */
  entitlements?: ProviderEntitlementReader;
  /** Phase 11 supplies §1f's computed conduct metrics; until then no rate is computable. */
  providerConduct?: ProviderConductSource;
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
    providers: ProviderProfileService;
    location: LocationService;
    listings: ListingService;
    media: MediaService;
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
  // Phase 4. The catalogue every later module reads its per-category numbers
  // from — booking mode, lead time, quote windows, the emergency tier bar.
  const categories = new CategoryService({ prisma: deps.prisma, audit });
  app.decorate('categories', categories);

  // Phase 5. The provider half of an account, and §1a's single visibility
  // gate. 🔧 **Phase 8 filled the published-listing seam** — the default is
  // now the real predicate over the `listing` table, not the empty one, so a
  // provider becomes publicly visible the moment they publish (ledger P5-1).
  // Phase 11's conduct seam is still open: until bookings exist no rate is
  // computable, which is the honest answer rather than a placeholder.
  const providers = new ProviderProfileService({
    prisma: deps.prisma,
    categories,
    audit,
    listings: deps.publishedListings ?? PUBLISHED_LISTINGS,
    ...(deps.providerConduct === undefined ? {} : { conduct: deps.providerConduct }),
  });
  app.decorate('providers', providers);

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
      // 🔧 **Phases 4 and 5 moved above this line in Phase 6a**, which is the
      // only reason the order changed: `GET /v1/users/me/profile-summary` now
      // answers §Phase 6a's "has this account completed onboarding?", and the
      // one definition of that lives in the provider service. Neither Phase 4
      // nor Phase 5 depends on anything constructed between here and there,
      // and `account` is decorated in the same place it always was.
      providerOnboarding: providers,
    }),
  );
  app.decorate('social', new SocialAuthRegistry(stubProviders()));

  // Phase 7. The island register and the provider service areas over it.
  // Depends on `providers` for §1a's implicit profile creation — declaring
  // where you work is acting as a provider — and the dependency runs one way:
  // the provider profile reads the join table through `LocationRepository`,
  // never through this service.
  app.decorate(
    'location',
    new LocationService({ prisma: deps.prisma, providers, clock: deps.clock }),
  );
  exportContributors.register(serviceAreaExportContributor(deps.prisma));

  // Phase 8. `MediaService` is the one upload path every module uses; the
  // storage behind it is a transport, defaulting to the local directory
  // because the object store is procured at deployment (§0.0 item 17).
  const media = new MediaService({
    storage: deps.mediaStorage ?? createMediaStorage(config.media),
    clock: deps.clock,
  });
  app.decorate('media', media);
  const listings = new ListingService({
    prisma: deps.prisma,
    providers,
    categories,
    media,
    clock: deps.clock,
    // Phase 8a replaces this with the live `getProviderEntitlements` read.
    // Until then every provider is on §1b's free tier, which is not a
    // placeholder — with no `ProviderSubscription` table, they are.
    ...(deps.entitlements === undefined ? {} : { entitlements: deps.entitlements }),
  });
  app.decorate('listings', listings);

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
  // Phase 5. The bank details and the self-written bio go with the account;
  // the verification decision and the billing price stay (see the hook).
  registerProviderAnonymisation(anonymisation);
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
  // Phase 8: the counters are rolled up from the event log on a schedule,
  // never incremented per request.
  jobs.register(listingCountRollupJob(new ListingEvents(deps.prisma, deps.clock), app.log));
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
  registerProviderRoutes(app);
  registerLocationRoutes(app);
  registerListingRoutes(app);
  // The two routes the LOCAL media transport needs — this process playing the
  // object store. There is one transport today, so they register
  // unconditionally, the same shape `createPushTransport` takes for the same
  // reason: a branch on a one-member union is a branch the compiler knows is
  // always taken. **When `s3` lands, `MediaConfig` becomes a union and this
  // becomes a real switch** — with a real store the client uploads to the
  // store and reads from it, and these URLs must not exist at all.
  registerMediaRoutes(app);
  registerPushRoutes(app);
  registerEmailLogRoutes(app);
  await registerSesEventRoutes(app);

  return app;
}
