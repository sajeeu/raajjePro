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
import { AvailabilityRepository } from './modules/availability/repository.js';
import { AvailabilityService } from './modules/availability/service.js';
import { SlotGenerator } from './modules/availability/generation.js';
import { ReservationService } from './modules/availability/reservations.js';
import { registerAvailabilityRoutes } from './modules/availability/routes.js';
import { BookingRepository } from './modules/bookings/repository.js';
import { registerBookingRoutes } from './modules/bookings/routes.js';
import { BookingService } from './modules/bookings/service.js';
import { loggingBookingNotifier, type BookingNotifier } from './modules/bookings/notifications.js';
import { bookingDeletionBlocker, bookingSubscriptionSource } from './modules/bookings/seams.js';
import { registerListingRoutes } from './modules/listings/routes.js';
import { ListingService } from './modules/listings/service.js';
import { PUBLISHED_LISTINGS } from './modules/listings/visibility.js';
import { registerSubscriptionAdminRoutes } from './modules/subscriptions/admin-routes.js';
import type { SubscriptionBookingSource } from './modules/subscriptions/bookings.js';
import type { BillingNotifier } from './modules/subscriptions/notifications.js';
import { registerSubscriptionRoutes } from './modules/subscriptions/routes.js';
import { SubscriptionService } from './modules/subscriptions/service.js';
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
import {
  bookingAcceptTimeoutJob,
  bookingCompletionTimeoutJob,
  bookingPaymentSilenceJob,
} from './jobs/booking-lifecycle.js';
import {
  subscriptionIntroductoryConversionJob,
  subscriptionLifecycleJob,
  subscriptionTrialPromptJob,
} from './jobs/subscription-lifecycle.js';
import { listingCountRollupJob } from './jobs/listing-count-rollup.js';
import { reservationExpiryJob, slotGenerationJob } from './jobs/slot-generation.js';
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
  /**
   * 🔧 **§Phase 17.1 filled this seam.** The default is now the real
   * non-terminal-booking check over the `booking` table, not `neverBlocks`,
   * and `AccountAnonymiser` did not change — the interface is what survived
   * (ledger rows **P1** and **P2**). A test may still inject a blocker to hold or
   * release a freeze without building a booking.
   */
  deletionBlocker?: DeletionBlocker;
  /**
   * §1a's published-listing predicate. Phase 8 supplies the real one over the
   * `listing` table; a test may substitute `FakeListings` to move a provider
   * across §1a's line without building a publishable listing.
   */
  publishedListings?: PublishedListingSource;
  /** Phase 8's object store. Defaults to the local file transport (§0.0 item 17). */
  mediaStorage?: MediaStorage;
  /**
   * 🔧 **Phase 8a filled this seam.** The default is now
   * `getProviderEntitlements` over the real `provider_subscription` table
   * rather than `FREE_TIER_ONLY`, and `ListingService` did not change — the
   * interface is what survived (§Phase 8's own note, ledger row P5-1's
   * pattern). A test may still inject a reader to put a provider on a cap
   * without building a subscription.
   */
  entitlements?: ProviderEntitlementReader;
  /**
   * 🔧 **§Phase 17.1 filled this seam.** The default is now the real pair of
   * queries over the `booking` table rather than `NO_BOOKINGS`, so §Phase 8a's
   * third trial trigger and §1b's protected-listing rule both see real rows.
   * No caller in `modules/subscriptions/` changed — which is the fourth time
   * that file's own note has been right about this pattern.
   */
  subscriptionBookings?: SubscriptionBookingSource;
  /**
   * §Phase 19 owns notification content; until then the default logs that a
   * billing event fired and that nothing delivered it.
   */
  billingNotifier?: BillingNotifier;
  /** Phase 11 supplies §1f's computed conduct metrics; until then no rate is computable. */
  providerConduct?: ProviderConductSource;
  /**
   * §Phase 19 owns notification content; until then the default logs that a
   * booking event fired and that nothing delivered it. The one exception is
   * the provider's accept prompt, which goes through §Phase 3c's dispatcher
   * directly because that phase built it a `NotificationKind` of its own.
   */
  bookingNotifier?: BookingNotifier;
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
    availability: AvailabilityService;
    reservations: ReservationService;
    subscriptions: SubscriptionService;
    bookings: BookingService;
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

  // Phase 8a. §1b's monetization: the trial, the 30-day billing anchor, the
  // shared pause, the manual `PaymentSubmission` mechanism and
  // `getProviderEntitlements` — "the single source of tier truth". It is
  // constructed **before** `ListingService` because it supplies that
  // service's entitlement reader; the dependency runs one way, and the
  // downgrade reads listing rows through the `visibility.ts` fragments rather
  // than through `ListingService`, which is what keeps it one-way.
  // Phase 17.1's repository is built here rather than beside its service,
  // because §Phase 8a's booking source is answered from it. Both questions are
  // pure reads, so they need no rules and no service — which is what keeps the
  // dependency one-way: subscriptions reads bookings, and `BookingService`
  // (constructed below) reads subscriptions for the trial hook.
  const bookingRepo = new BookingRepository(deps.prisma);

  const subscriptions = new SubscriptionService({
    prisma: deps.prisma,
    providers,
    media,
    audit,
    clock: deps.clock,
    bankDetails: config.billing.bankDetails,
    // 🔧 **§Phase 17.1 filled this seam.** `NO_BOOKINGS` was the true answer
    // while no `Booking` existed; these are the real queries and no rule in
    // `modules/subscriptions/` changed.
    bookings: deps.subscriptionBookings ?? bookingSubscriptionSource(bookingRepo, deps.clock),
    ...(deps.billingNotifier === undefined ? {} : { notifier: deps.billingNotifier }),
    log: app.log,
  });
  app.decorate('subscriptions', subscriptions);
  // 🔧 §1b's "pause keys off the provider-level `acceptingNewCustomers`
  // toggle", wired as one implementation reached through two doors: the
  // billing endpoints write the toggle through `ProviderProfileService`, and
  // `PATCH /v1/providers/me` fires this same listener.
  providers.onAcceptingNewCustomersChanged((providerProfileId, accepting) =>
    subscriptions.acceptingNewCustomersChanged(providerProfileId, accepting),
  );

  const listings = new ListingService({
    prisma: deps.prisma,
    providers,
    categories,
    media,
    clock: deps.clock,
    // 🔧 **Phase 8a's `getProviderEntitlements`, filling §Phase 8's seam.**
    // `FREE_TIER_ONLY` was the right answer while no subscription table
    // existed; now the cap is read live per provider and no caller changed.
    entitlements: deps.entitlements ?? subscriptions.entitlementReader,
  });
  app.decorate('listings', listings);

  // Phase 9a. Availability rules, the 60-day rolling slot grid, and the
  // provider-scoped reservation that is the hard guarantee against
  // double-booking.
  //
  // `ReservationService` is decorated in its own right because it is
  // **§Phase 17's seam, not an endpoint**: every method takes the caller's
  // transaction so a booking row, its state transition and its hold land
  // together or not at all (§Phase 9a: "reservations are created inside the
  // booking transaction"). Nothing in this phase exposes it over HTTP —
  // taking a time is a booking, and a booking is Phase 17.1.
  const slotGenerator = new SlotGenerator({
    prisma: deps.prisma,
    clock: deps.clock,
    repo: new AvailabilityRepository(deps.prisma),
    log: app.log,
  });
  const availability = new AvailabilityService({
    prisma: deps.prisma,
    clock: deps.clock,
    providers,
    generator: slotGenerator,
  });
  app.decorate('availability', availability);
  const reservations = new ReservationService({
    prisma: deps.prisma,
    clock: deps.clock,
    repo: availability.repo,
  });
  app.decorate('reservations', reservations);

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

  // Phase 17.1. The core booking machine, §1c's payment attestation and §1h's
  // locked agreement.
  //
  // It is constructed **after** the notification dispatcher and **before** the
  // anonymiser and the job runner, because it supplies one and is registered
  // with the other. `ReservationService` goes in as §Phase 9a built it — every
  // method taking the caller's transaction — so a booking row, its first
  // status event and its hold land together or not at all (ledger **P9A-2**).
  //
  // 🔧 `onConfirmed` is §Phase 8a's trial trigger, wired as a callback rather
  // than an endpoint call because §Phase 17 item 20 requires it to fire "on
  // the state transition into `confirmed`, not from one endpoint" — so both
  // `confirm-payment-received` and an admin resolving `payment_unresolved`
  // reach it through one place.
  const bookings = new BookingService({
    prisma: deps.prisma,
    clock: deps.clock,
    repo: bookingRepo,
    reservations,
    providers,
    notifier: deps.bookingNotifier ?? loggingBookingNotifier(app.log),
    dispatcher: notifications,
    onConfirmed: (providerProfileId) => subscriptions.onBookingConfirmed(providerProfileId),
    log: app.log,
  });
  app.decorate('bookings', bookings);

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
  // 🔧 **§Phase 3's `DeletionBlocker`, filled.** `neverBlocks` was the true
  // answer while no booking existed; now §Phase 3's "anonymisation executes
  // automatically once non-terminal bookings terminate" is enforced against
  // real rows, and the 30-day backstop inside the anonymiser is unchanged.
  jobs.register(
    anonymiseAccountsJob(
      anonymiser,
      deps.deletionBlocker ?? bookingDeletionBlocker(bookingRepo),
      app.log,
    ),
  );
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
  // Phase 8a: §1b's lifecycle on the runner rather than check-on-read — the
  // 7-day warning, expiry → grace, grace → downgrade, the win-back pair, the
  // forced resume at the pause cap, the "Try Premium" prompt and the
  // introductory-rate conversion.
  jobs.register(subscriptionLifecycleJob(subscriptions, app.log));
  jobs.register(subscriptionTrialPromptJob(subscriptions, app.log));
  jobs.register(subscriptionIntroductoryConversionJob(subscriptions, app.log));
  // Phase 9a: the incremental, per-listing slot generator with its stated
  // wall-clock budget, and the provisional-hold expiry sweep.
  jobs.register(slotGenerationJob(slotGenerator, app.log));
  jobs.register(reservationExpiryJob(app.reservations, app.log));
  // Phase 17.1: §1c's three flat clocks — the 24-hour accept window, the
  // 7-day payment silence, and the completion prompt with its 3-day grace.
  // The per-category ones belong to the slices that own them: §Phase 17.2's
  // `quoteApprovalMinutes` and §Phase 17.3's `emergencyAcceptWindowMinutes`.
  jobs.register(bookingAcceptTimeoutJob(bookings, app.log));
  jobs.register(bookingPaymentSilenceJob(bookings, app.log));
  jobs.register(bookingCompletionTimeoutJob(bookings, app.log));
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
  registerAvailabilityRoutes(app);
  registerBookingRoutes(app);
  registerSubscriptionRoutes(app);
  registerSubscriptionAdminRoutes(app);
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
