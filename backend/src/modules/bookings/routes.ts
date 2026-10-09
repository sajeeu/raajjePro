import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { principalOf, requireAdmin } from '../admin-auth/guards.js';
import { requireActiveAccount, requireAuth, requireEmailVerified, userOf } from '../auth/guards.js';
import { paymentProofBody } from '../subscriptions/schema.js';
import {
  amendmentParams,
  bookingParams,
  cancelBody,
  claimCallbackBody,
  completeBody,
  createRecurringSeriesBody,
  completionAnswerBody,
  createBookingBody,
  declineBody,
  createEmergencyRequestBody,
  declineQuoteBody,
  dispatchFeeParams,
  disputeBody,
  emergencyAcceptBody,
  emergencyOfferResponseBody,
  listBookingsQuery,
  listRecurringSeriesQuery,
  recurringSeriesParams,
  rescheduleBody,
  skipOccurrenceBody,
  emergencyRequestParams,
  listingParams,
  offerQuoteBody,
  proposeAmendmentBody,
  resolveDisputeBody,
  respondToAmendmentBody,
} from './schema.js';

/**
 * §Phases 17.1 and 17.2's route table.
 *
 * 🔧 §Phase 17.2 adds three routes — `quote`, `approve-quote`,
 * `decline-quote` — and widens the creation body to the two shapes a listing
 * can take. Every rule below is unchanged and applies to them, including the
 * last one: **none of the three new responses carries a phone number**, which
 * `test/phase17-2-done-when.test.ts` re-checks over them the way §Phase
 * 17.1's test does over its own.
 *
 * ## Authorization, and the guard that is stricter than the usual one
 *
 * Creation carries **`requireEmailVerified`** — §1c's access-control table
 * puts "Book, enquire, message within a booking" behind it, and it is
 * enforced server-side on every relevant endpoint precisely because hiding a
 * button is not enforcement. It also carries `requireActiveAccount`: §Phase 3
 * freezes an account with a deletion request pending and says it "starts
 * nothing new", and a booking is the clearest case of starting something.
 *
 * Every other endpoint here **acts on a booking that already exists** and so
 * carries `requireAuth` alone. A customer who has asked to delete their
 * account must still be able to pay for, confirm and complete the job they
 * booked before they asked — §Phase 3's own rule is that anonymisation waits
 * for non-terminal bookings to terminate, and freezing them out of the actions
 * that terminate them would deadlock their own deletion.
 *
 * Ownership is never a route-level check: `BookingService.authorize` resolves
 * the caller's side of the booking and a stranger gets **not found**, not
 * forbidden — the existence of somebody else's booking is not theirs to learn.
 *
 * ## No response from any route below carries a phone number
 *
 * Structurally (see `types.ts` and `repository.ts`), and asserted over this
 * route table by `test/phase17-1-done-when.test.ts`. §1c allows exactly one
 * endpoint in the system to return one and it is §Phase 17.3's
 * `POST /v1/bookings/:id/reveal-contact`, **below, and the only exception**.
 * `GET /v1/bookings/:id/contact-info` does not exist here and must never be
 * created.
 */
export function registerBookingRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  /**
   * Booking actions are taps on a screen somebody is looking at, and the
   * accept prompt is one a provider may hit the moment a push lands. Generous
   * per user, and keyed on the principal rather than the IP — a provider and
   * a customer behind one island's NAT are not one caller.
   */
  const bookingRate = {
    rateLimit: {
      max: 120,
      timeWindow: '1 minute',
      keyGenerator: (req: { principal?: { id: string }; ip: string }) =>
        `user:${req.principal?.id ?? req.ip}`,
    },
  };

  // -- Creation -------------------------------------------------------------

  // Who may call: any email-verified, non-frozen signed-in user who is not the
  // provider. §Phase 17 item 2: "`requireEmailVerified` (Round 11);
  // idempotency key required" — a booking is the definitive creation POST, and
  // a replayed tap on a weak atoll connection must not take two slots.
  r.post(
    '/v1/listings/:id/bookings',
    {
      schema: { params: listingParams, body: createBookingBody },
      preValidation: [requireAuth, requireEmailVerified, requireActiveAccount],
      config: { idempotency: { operation: 'booking.create' }, ...bookingRate },
    },
    async (request, reply) => {
      const body = request.body;
      // One route, two shapes, and the **listing** decides which is valid —
      // the service refuses a mismatch by name (`BOOKING_MODE_NOT_AVAILABLE`).
      // Reading `timeSlotId` here only routes the call; it grants nothing.
      const booking =
        'timeSlotId' in body
          ? await app.bookings.createSlotBooking(userOf(request).id, request.params.id, body)
          : await app.bookings.createRequestBooking(userOf(request).id, request.params.id, body);
      return reply.code(201).send(ok(booking));
    },
  );

  // -- Reads ----------------------------------------------------------------

  // Who may call: the signed-in user, for their own bookings on either side.
  // The query *is* the authorization — no shape of it reaches somebody else's.
  r.get(
    '/v1/users/me/bookings',
    { schema: { querystring: listBookingsQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const { bookings, nextCursor } = await app.bookings.list(userOf(request).id, {
        role: request.query.role,
        statuses: request.query.status ?? null,
        limit: request.query.limit,
        cursor: request.query.cursor ?? null,
      });
      return reply.send(ok(bookings, { nextCursor }));
    },
  );

  // Who may call: either party to this booking. Anyone else gets 404.
  r.get(
    '/v1/bookings/:id',
    { schema: { params: bookingParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.bookings.read(userOf(request).id, request.params.id))),
  );

  // -- The provider answers the accept prompt -------------------------------

  // Who may call: the provider on this booking.
  //
  // No idempotency key, and deliberately: the transition itself is idempotent
  // in the way that matters — `repo.transition` carries the status in its
  // `WHERE`, so the second of two taps changes nothing and is told the booking
  // moved. §Phase 17's offline queue replays this endpoint, and what it needs
  // is exactly that: a replay that cannot double-accept.
  r.patch(
    '/v1/bookings/:id/accept',
    { schema: { params: bookingParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.bookings.accept(userOf(request).id, request.params.id))),
  );

  // Who may call: the provider on this booking. Distinct from dispute (§1c).
  r.patch(
    '/v1/bookings/:id/decline',
    {
      schema: { params: bookingParams, body: declineBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(await app.bookings.decline(userOf(request).id, request.params.id, request.body.reason)),
      ),
  );

  // -- §Phase 17.2, the request-with-quote path ------------------------------

  // Who may call: the provider on this booking, on a `request` booking at
  // `awaiting_quote` (a first quote) or `quote_offered` (a revision after
  // negotiating in chat). §1c: the quote creates the provisional reservation.
  //
  // An idempotency key, unlike `accept`: this call carries a **price and a
  // time**, so a replay is not self-evidently the same intention as the
  // original — and a revision is a legitimate second call to the same path
  // with a different body. The key is what tells the two apart.
  r.patch(
    '/v1/bookings/:id/quote',
    {
      schema: { params: bookingParams, body: offerQuoteBody },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'booking.quote' }, ...bookingRate },
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.offerQuote(userOf(request).id, request.params.id, {
            scheduledFor: new Date(request.body.scheduledFor),
            amountLaari: request.body.amountLaari,
            ...(request.body.note === undefined ? {} : { note: request.body.note }),
          }),
        ),
      ),
  );

  // Who may call: the customer on this booking, while the quote is live.
  // Converts the provisional hold to firm and lands on `awaiting_payment`.
  r.patch(
    '/v1/bookings/:id/approve-quote',
    { schema: { params: bookingParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.bookings.approveQuote(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer on this booking. `Quote Received.dc.html`'s
  // "Decline this quote" — `cancelled`, never `declined` (§1f).
  r.patch(
    '/v1/bookings/:id/decline-quote',
    {
      schema: { params: bookingParams, body: declineQuoteBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.declineQuote(
            userOf(request).id,
            request.params.id,
            request.body.reason,
          ),
        ),
      ),
  );

  // -- §Phase 17.3, emergency dispatch ----------------------------------------
  //
  // 🔧 An emergency is a **request**, raised by category and island, until the
  // customer chooses an offer — owner's decision 2026-09-28, following Round
  // 23's "dispatch never targets a provider". §Phase 17 item 2's
  // listing-scoped emergency clause is pre-Round-23 residue; the verbs below
  // keep the plan's names (`emergency-accept`, `emergency-offer-response`).

  // Who may call: an email-verified, non-frozen customer — the same guards as
  // every booking creation, for the same reasons (§1c's access table; §Phase
  // 3's freeze). Idempotency key required: a double tap on a weak connection
  // must not page every plumber on the island twice or spend two of three
  // requests a day.
  r.post(
    '/v1/emergency-requests',
    {
      schema: { body: createEmergencyRequestBody },
      preValidation: [requireAuth, requireEmailVerified, requireActiveAccount],
      config: { idempotency: { operation: 'emergency.create' }, ...bookingRate },
    },
    async (request, reply) =>
      reply.code(201).send(ok(await app.emergency.create(userOf(request).id, request.body))),
  );

  // Who may call: the customer who raised it. Anyone else gets 404.
  r.get(
    '/v1/emergency-requests/:id',
    { schema: { params: emergencyRequestParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.emergency.readForCustomer(userOf(request).id, request.params.id))),
  );

  // Who may call: the signed-in user, for their own requests.
  r.get(
    '/v1/users/me/emergency-requests',
    { preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.emergency.listForCustomer(userOf(request).id))),
  );

  // Who may call: a provider the broadcast reaches — capable category, the
  // category's own tier bar, a live emergency listing on the job's island,
  // taking new customers, not excluded. Everyone else gets 404, or the tier
  // refusal by name where they have a listing here but not the tier.
  //
  // An idempotency key, like `quote`: the call carries a price and an arrival
  // promise. And **not** in the offline queue (§0.0 item 14) — a replayed offer
  // would commit a provider to numbers worked out somewhere else.
  r.patch(
    '/v1/emergency-requests/:id/emergency-accept',
    {
      schema: { params: emergencyRequestParams, body: emergencyAcceptBody },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'emergency.accept' }, ...bookingRate },
    },
    async (request, reply) =>
      reply.send(
        ok(await app.emergency.offer(userOf(request).id, request.params.id, request.body)),
      ),
  );

  // Who may call: a provider the broadcast reaches. Recorded, never counted
  // in the acceptance rate, and nobody is told (owner, 2026-09-28).
  r.patch(
    '/v1/emergency-requests/:id/pass',
    { schema: { params: emergencyRequestParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.emergency.pass(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer, once the collection window has closed and
  // inside their five minutes. Selecting creates the booking and incurs the
  // dispatch fee.
  r.patch(
    '/v1/emergency-requests/:id/emergency-offer-response',
    {
      schema: { params: emergencyRequestParams, body: emergencyOfferResponseBody },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'emergency.offer-response' }, ...bookingRate },
    },
    async (request, reply) =>
      reply.send(
        ok(await app.emergency.respond(userOf(request).id, request.params.id, request.body)),
      ),
  );

  // Who may call: the customer, before anyone is chosen. Nothing is charged.
  r.patch(
    '/v1/emergency-requests/:id/cancel',
    { schema: { params: emergencyRequestParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.emergency.cancel(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer on an emergency booking, once the category's
  // answer window has passed since they chose. No admin in the loop (Round 15).
  // Answers with the request, which has gone out again.
  r.patch(
    '/v1/bookings/:id/provider-not-arrived',
    { schema: { params: bookingParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.emergency.markNotArrived(userOf(request).id, request.params.id))),
  );

  // Who may call: a provider, for the open emergencies they may answer now.
  r.get(
    '/v1/providers/me/emergency-requests',
    { preValidation: requireAuth, config: bookingRate },
    async (request, reply) => reply.send(ok(await app.emergency.inbox(userOf(request).id))),
  );

  // Who may call: a provider the request reaches, or one who already offered
  // on it — so a provider who was not chosen can see that they were released.
  r.get(
    '/v1/providers/me/emergency-requests/:id',
    { schema: { params: emergencyRequestParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.emergency.readForProvider(userOf(request).id, request.params.id))),
  );

  // 🔧 **THE ONE ROUTE IN THIS SYSTEM THAT RETURNS A PHONE NUMBER** (§1c).
  //
  // Who may call: the customer on an emergency booking at `accepted` or
  // later, to start it; the provider on it, only after the customer has.
  // Every one of the seven conditions is checked in `contact-reveal.ts`, and
  // the runtime kill switch before them. A tighter rate than the rest of the
  // module: a legitimate caller needs this once or twice per job, and each
  // call is logged as a moderation signal.
  r.post(
    '/v1/bookings/:id/reveal-contact',
    {
      schema: { params: bookingParams },
      preValidation: requireAuth,
      config: {
        rateLimit: {
          max: 10,
          timeWindow: '1 minute',
          keyGenerator: (req: { principal?: { id: string }; ip: string }) =>
            `user:${req.principal?.id ?? req.ip}`,
        },
      },
    },
    async (request, reply) =>
      reply.send(ok(await app.contactReveal.reveal(userOf(request).id, request.params.id))),
  );

  // -- §1c's dispatch fee, settled by the customer ---------------------------

  // Who may call: the signed-in user, for their own dispatch fees — and the
  // RaajjePro bank account to pay them into.
  r.get(
    '/v1/users/me/dispatch-fees',
    { preValidation: requireAuth, config: bookingRate },
    async (request, reply) => reply.send(ok(await app.dispatchFees.listOwn(userOf(request).id))),
  );

  // Who may call: the customer whose current fee was rejected. §0.0 item 24:
  // a rejection re-blocks, and this is the way out — a fresh transfer against
  // a fresh reference. Idempotency key required: a double tap must not issue
  // two references for one fee.
  r.post(
    '/v1/users/me/dispatch-fees/:id/retry',
    {
      schema: { params: dispatchFeeParams },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'dispatch-fee.retry' }, ...bookingRate },
    },
    async (request, reply) =>
      reply.code(201).send(ok(await app.dispatchFees.retry(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer who owes it. Step 1 of §Phase 8a's upload.
  // Not `requireActiveAccount`: a customer mid-deletion may still settle a
  // debt, and refusing would leave it owed forever.
  r.post(
    '/v1/users/me/dispatch-fees/:id/proof',
    {
      schema: { params: dispatchFeeParams, body: paymentProofBody },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'dispatch-fee.proof' }, ...bookingRate },
    },
    async (request, reply) => {
      const created = await app.dispatchFees.createProofUpload(
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

  // Who may call: the customer who owes it. §1c: submitting **is** what lifts
  // the new-booking block — "not when an admin confirms it".
  r.post(
    '/v1/users/me/dispatch-fees/:id/submit',
    {
      schema: { params: dispatchFeeParams },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'dispatch-fee.submit' }, ...bookingRate },
    },
    async (request, reply) =>
      reply.send(ok(await app.dispatchFees.submitProof(userOf(request).id, request.params.id))),
  );

  // -- Payment attestation --------------------------------------------------

  // Who may call: the customer on this booking. Self-attestation, no proof.
  r.patch(
    '/v1/bookings/:id/claim-payment',
    { schema: { params: bookingParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.bookings.claimPayment(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer on this booking, once, while the claim is
  // unanswered (Round 24).
  r.patch(
    '/v1/bookings/:id/withdraw-payment-claim',
    { schema: { params: bookingParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(
        ok(await app.bookings.withdrawPaymentClaim(userOf(request).id, request.params.id)),
      ),
  );

  // Who may call: the provider on this booking. "Provider confirmed receipt",
  // never "payment verified" — nothing here can see a bank transfer.
  r.patch(
    '/v1/bookings/:id/confirm-payment-received',
    { schema: { params: bookingParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(
        ok(await app.bookings.confirmPaymentReceived(userOf(request).id, request.params.id)),
      ),
  );

  // -- Completion -----------------------------------------------------------

  // Who may call: the provider on this booking. An emergency booking is
  // refused without a final amount (§Phase 17 item 13).
  r.patch(
    '/v1/bookings/:id/complete',
    {
      schema: { params: bookingParams, body: completeBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.complete(
            userOf(request).id,
            request.params.id,
            request.body.finalAmountLaari,
          ),
        ),
      ),
  );

  // Who may call: the customer on this booking, answering §1c step 10's
  // "Did [Provider] complete this job?". "No" files a Report and disputes.
  r.patch(
    '/v1/bookings/:id/completion-answer',
    {
      schema: { params: bookingParams, body: completionAnswerBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.answerCompletionPrompt(
            userOf(request).id,
            request.params.id,
            request.body.happened,
          ),
        ),
      ),
  );

  // -- Cancellation ---------------------------------------------------------

  // Who may call: either party. Which edge it takes depends on which one —
  // §1f counts a provider's cancellation and never a customer's.
  r.patch(
    '/v1/bookings/:id/cancel',
    {
      schema: { params: bookingParams, body: cancelBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(await app.bookings.cancel(userOf(request).id, request.params.id, request.body.reason)),
      ),
  );

  // -- §1h, the locked agreement --------------------------------------------

  // Who may call: either party, while a locked agreement exists. Every
  // attempt is recorded whether it is accepted or not.
  r.post(
    '/v1/bookings/:id/amendments',
    {
      schema: { params: bookingParams, body: proposeAmendmentBody },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'booking.amendment.create' }, ...bookingRate },
    },
    async (request, reply) => {
      const body = request.body;
      const booking = await app.bookings.proposeAmendment(userOf(request).id, request.params.id, {
        ...(body.amountLaari === undefined ? {} : { amountLaari: body.amountLaari }),
        ...(body.scheduledFor === undefined ? {} : { scheduledFor: new Date(body.scheduledFor) }),
        ...(body.scopeNote === undefined ? {} : { scopeNote: body.scopeNote }),
        ...(body.reason === undefined ? {} : { reason: body.reason }),
      });
      return reply.code(201).send(ok(booking));
    },
  );

  // Who may call: the **counterparty** — the party who did not propose it.
  r.patch(
    '/v1/bookings/:id/amendments/:amendmentId',
    {
      schema: { params: amendmentParams, body: respondToAmendmentBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.respondToAmendment(
            userOf(request).id,
            request.params.id,
            request.params.amendmentId,
            request.body.accept,
          ),
        ),
      ),
  );

  // Who may call: the party who proposed it. The row stays either way.
  r.delete(
    '/v1/bookings/:id/amendments/:amendmentId',
    { schema: { params: amendmentParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.withdrawAmendment(
            userOf(request).id,
            request.params.id,
            request.params.amendmentId,
          ),
        ),
      ),
  );

  // -- Disputes -------------------------------------------------------------

  // Who may call: either party. A late dispute on a completed booking is
  // accepted and queues separately without moving the booking (§1c).
  r.patch(
    '/v1/bookings/:id/dispute',
    {
      schema: { params: bookingParams, body: disputeBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.bookings.dispute(
            userOf(request).id,
            request.params.id,
            request.body.reason,
            request.body.note ?? null,
          ),
        ),
      ),
  );

  // Who may call: an admin. §Phase 10b builds the surface that calls this;
  // the endpoint is this phase's and is testable without it.
  r.patch(
    '/v1/admin/bookings/:id/resolve-dispute',
    {
      schema: { params: bookingParams, body: resolveDisputeBody },
      preValidation: requireAdmin,
    },
    async (request, reply) => {
      return reply.send(
        ok(
          await app.bookings.resolveDispute(
            principalOf(request).id,
            request.params.id,
            request.body.outcome,
            {
              ...(request.body.unresolvedTo === undefined
                ? {}
                : { unresolvedTo: request.body.unresolvedTo }),
              ...(request.body.note === undefined ? {} : { note: request.body.note }),
            },
          ),
        ),
      );
    },
  );

  // -- §Phase 17.4 ------------------------------------------------------------
  //
  // None of these responses carries a phone number: every booking shape is
  // `BookingDto`, the series and Book Again shapes have no slot for one, and
  // the calendar entry is built from the same projection.
  // `test/phase17-4-done-when.test.ts` re-checks all of them.

  // Who may call: the customer before the provider has answered (a direct
  // move); either party from `accepted` on (a time amendment the other side
  // must accept, §1h). Idempotency, because the pre-accept move takes a slot.
  r.patch(
    '/v1/bookings/:id/reschedule',
    {
      schema: { params: bookingParams, body: rescheduleBody },
      preValidation: requireAuth,
      config: { idempotency: { operation: 'booking.reschedule' }, ...bookingRate },
    },
    async (request, reply) => {
      const body = request.body;
      return reply.send(
        ok(
          await app.bookings.reschedule(userOf(request).id, request.params.id, {
            timeSlotId: body.timeSlotId,
            scheduledFor: body.scheduledFor === undefined ? undefined : new Date(body.scheduledFor),
            preferredWindowChip: body.preferredWindowChip,
            preferredWindowText: body.preferredWindowText,
            reason: body.reason,
          }),
        ),
      );
    },
  );

  // Who may call: the customer of a completed booking. A read — the booking
  // itself is then made through the ordinary creation route.
  r.get(
    '/v1/bookings/:id/book-again',
    { schema: { params: bookingParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.bookings.bookAgain(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer of a completed, guaranteed booking, inside its
  // 7-day window. A creation POST like booking itself: email-verified,
  // not frozen, idempotent.
  r.post(
    '/v1/bookings/:id/callback',
    {
      schema: { params: bookingParams, body: claimCallbackBody },
      preValidation: [requireAuth, requireEmailVerified, requireActiveAccount],
      config: { idempotency: { operation: 'booking.callback' }, ...bookingRate },
    },
    async (request, reply) =>
      reply
        .code(201)
        .send(
          ok(await app.bookings.claimCallback(userOf(request).id, request.params.id, request.body)),
        ),
  );

  // Who may call: either party, once the time is agreed.
  r.get(
    '/v1/bookings/:id/calendar',
    { schema: { params: bookingParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.bookings.calendarExport(userOf(request).id, request.params.id))),
  );

  // Who may call: the customer of a confirmed or completed slot booking. It
  // makes the first week's booking, so it carries creation's guards.
  r.post(
    '/v1/recurring-series',
    {
      schema: { body: createRecurringSeriesBody },
      preValidation: [requireAuth, requireEmailVerified, requireActiveAccount],
      config: { idempotency: { operation: 'recurring.create' }, ...bookingRate },
    },
    async (request, reply) =>
      reply
        .code(201)
        .send(ok(await app.recurringSeries.create(userOf(request).id, request.body.bookingId))),
  );

  // Who may call: the signed-in user, for their own series on either side.
  r.get(
    '/v1/users/me/recurring-series',
    { schema: { querystring: listRecurringSeriesQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const { series, nextCursor } = await app.recurringSeries.list(userOf(request).id, {
        role: request.query.role,
        limit: request.query.limit,
        cursor: request.query.cursor ?? null,
      });
      return reply.send(ok(series, { nextCursor }));
    },
  );

  // Who may call: either party to the series. Anyone else gets 404.
  r.get(
    '/v1/recurring-series/:id',
    { schema: { params: recurringSeriesParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.recurringSeries.read(userOf(request).id, request.params.id))),
  );

  // Who may call: the series' customer.
  r.patch(
    '/v1/recurring-series/:id/skip',
    {
      schema: { params: recurringSeriesParams, body: skipOccurrenceBody },
      preValidation: requireAuth,
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.recurringSeries.skip(
            userOf(request).id,
            request.params.id,
            new Date(request.body.occursAt),
          ),
        ),
      ),
  );

  // Who may call: the series' customer.
  r.patch(
    '/v1/recurring-series/:id/end',
    { schema: { params: recurringSeriesParams }, preValidation: requireAuth, config: bookingRate },
    async (request, reply) =>
      reply.send(ok(await app.recurringSeries.end(userOf(request).id, request.params.id))),
  );

  // Who may call: the series' customer. It asks for the next week, so it
  // carries creation's guards.
  r.patch(
    '/v1/recurring-series/:id/resume',
    {
      schema: { params: recurringSeriesParams },
      preValidation: [requireAuth, requireEmailVerified, requireActiveAccount],
      config: bookingRate,
    },
    async (request, reply) =>
      reply.send(ok(await app.recurringSeries.resume(userOf(request).id, request.params.id))),
  );
}
