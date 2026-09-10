import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import { invoiceListQuery, paymentProofBody, paymentSubmissionParams } from './schema.js';

/**
 * The provider's billing surface (§Phase 8a: "endpoints: upgrade-request,
 * subscription status, pause/resume, start-trial").
 *
 * ## Why these are the endpoints §Phase 10a's Flutter screens call
 *
 * Round 19 (§Phase 23): "**keep the provider billing UI behind a thin
 * boundary** … put **no billing logic in Flutter widgets**, and drive
 * everything through the same endpoints the admin panel uses. A rejection
 * must cost a port, not a rewrite." So every decision below happens
 * server-side and the app renders what it is told — which is also invariant
 * 4, and the reason the status response carries a computed
 * `nextPaymentAmountLaari` and `daysRemaining` rather than the raw dates for
 * a widget to do arithmetic on.
 *
 * ## Authorization
 *
 * `requireAuth` everywhere, plus `requireActiveAccount` on the writes:
 * §Phase 3 freezes an account with a deletion request pending and it "starts
 * nothing new", which a trial and a payment plainly are. Ownership is never a
 * route-level check — the service resolves the caller's own provider profile
 * and queries with it, so somebody else's submission is *not found*.
 *
 * `requireEmailVerified` is deliberately **not** here. §1c's stricter guard
 * gates booking, enquiry and messaging; §1a says dashboard access is never
 * gated. In practice a provider reaching billing has a verified email
 * anyway, because §Phase 6a's onboarding will not complete without one.
 *
 * ## No response here carries a phone number or a provider's bank details
 *
 * Structurally — see the note at the top of `types.ts`. The bank details that
 * do appear are **RaajjePro's own**, from configuration.
 */
export function registerSubscriptionRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const base = '/v1/providers/me/subscription';

  /** Generous enough for a billing screen that refreshes, tight enough that money-adjacent calls are not loopable. */
  const billingRate = {
    rateLimit: {
      max: 60,
      timeWindow: '1 minute',
      keyGenerator: (req: { principal?: { id: string }; ip: string }) =>
        `user:${req.principal?.id ?? req.ip}`,
    },
  };

  // Who may call: any signed-in user, for their own subscription. A provider
  // who has never trialled or paid has no row, and gets §1b's free tier
  // rather than a 404 — the absence *is* the answer.
  r.get(base, { preValidation: requireAuth, config: billingRate }, async (request, reply) => {
    return reply.send(ok(await app.subscriptions.readOwnStatus(userOf(request).id)));
  });

  // Who may call: the signed-in, non-frozen user, for themselves — §Phase
  // 8a's explicit "Try Premium".
  //
  // Idempotency key required: it is money-adjacent (it grants premium) and a
  // creation POST, and §1b allows exactly one trial per account forever — a
  // double tap on a weak connection must not be able to turn "started" into
  // an error the second time.
  r.post(
    `${base}/start-trial`,
    {
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'subscription.start-trial' }, ...billingRate },
    },
    async (request, reply) => {
      return reply.send(
        ok(await app.subscriptions.startTrialForOwner(userOf(request).id, requestMeta(request))),
      );
    },
  );

  // Who may call: the signed-in, non-frozen user, for themselves.
  //
  // 🔧 **One of two doors onto one pause** (§1b, confirmed 2026-09-10): this
  // sets `acceptingNewCustomers`, and setting that through
  // `PATCH /v1/providers/me` runs the same code. What is different here is
  // that a refusal is reportable — "you have used all ten days", "there is no
  // subscription to pause" — because here the provider asked to pause
  // billing, where there they asked to stop taking work.
  //
  // No idempotency key: pausing twice is paused, and the pause function is a
  // no-op on an already-paused subscription.
  r.post(
    `${base}/pause`,
    { preValidation: [requireAuth, requireActiveAccount], config: billingRate },
    async (request, reply) => {
      return reply.send(
        ok(await app.subscriptions.pauseForOwner(userOf(request).id, requestMeta(request))),
      );
    },
  );

  r.post(
    `${base}/resume`,
    { preValidation: [requireAuth, requireActiveAccount], config: billingRate },
    async (request, reply) => {
      return reply.send(
        ok(await app.subscriptions.resumeForOwner(userOf(request).id, requestMeta(request))),
      );
    },
  );

  // Who may call: the signed-in, non-frozen user, for themselves. §1b steps
  // 1–2: the intent, and the bank details plus reference code the app shows.
  //
  // **This grants nothing and queues nothing.** `submittedAt` stays null
  // until the proof is submitted, so an intent nobody finished never reaches
  // an admin — and §1b's "nothing is granted on submission" is stricter than
  // that anyway: even a submitted, pending payment produces entitlements
  // identical to no payment at all.
  //
  // Idempotency key required (§Phase 8a: "on every submission-creating
  // call"). Without one a double tap issues two reference codes and the
  // provider writes the wrong one on their transfer.
  r.post(
    `${base}/upgrade-request`,
    {
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'subscription.upgrade-request' }, ...billingRate },
    },
    async (request, reply) => {
      const created = await app.subscriptions.requestUpgrade(userOf(request).id);
      return reply.code(201).send(ok(created));
    },
  );

  // Who may call: the owner of the submission. Step 1 of the three-step
  // upload — the server chooses the object key and hands back an expiring
  // target. Idempotency key required: a retried request must return the
  // original target rather than orphaning an object in the store.
  r.post(
    '/v1/providers/me/payment-submissions/:id/proof',
    {
      schema: { params: paymentSubmissionParams, body: paymentProofBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'payment-submission.proof' }, ...billingRate },
    },
    async (request, reply) => {
      const created = await app.subscriptions.createProofUpload(
        userOf(request).id,
        request.params.id,
        request.body.contentType,
      );
      return reply.code(201).send(
        ok({
          submission: created.submission,
          upload: {
            url: created.upload.url,
            method: created.upload.method,
            headers: created.upload.headers,
            expiresAt: created.upload.expiresAt.toISOString(),
            maxBytes: created.upload.maxBytes,
          },
        }),
      );
    },
  );

  // Who may call: the owner. §1b step 3 — "provider uploads proof and
  // submits. Status `pending`." This is also where the proof's real type is
  // sniffed, its size checked and its EXIF stripped: a photo of a bank-app
  // screen carries the same location metadata a listing photo does.
  r.post(
    '/v1/providers/me/payment-submissions/:id/submit',
    {
      schema: { params: paymentSubmissionParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'payment-submission.submit' }, ...billingRate },
    },
    async (request, reply) => {
      return reply.send(
        ok(await app.subscriptions.submitProof(userOf(request).id, request.params.id)),
      );
    },
  );

  // Who may call: the signed-in user, for their own invoices (§Phase 10a's
  // invoice list with a PDF download per confirmed payment). Paged, because a
  // provider renewing monthly accumulates them without limit. A voided
  // invoice stays in the list — invariant 8, and a document that was issued
  // cannot be made never to have existed.
  r.get(
    '/v1/providers/me/invoices',
    { schema: { querystring: invoiceListQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const page = await app.subscriptions.listOwnInvoices(userOf(request).id, {
        limit: request.query.limit,
        ...(request.query.cursor === undefined ? {} : { cursor: request.query.cursor }),
      });
      return reply.send(ok(page.items, { nextCursor: page.nextCursor }));
    },
  );
}
