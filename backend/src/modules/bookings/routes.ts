import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { principalOf, requireAdmin } from '../admin-auth/guards.js';
import { requireActiveAccount, requireAuth, requireEmailVerified, userOf } from '../auth/guards.js';
import {
  amendmentParams,
  bookingParams,
  cancelBody,
  completeBody,
  completionAnswerBody,
  createSlotBookingBody,
  declineBody,
  disputeBody,
  listBookingsQuery,
  listingParams,
  proposeAmendmentBody,
  resolveDisputeBody,
  respondToAmendmentBody,
} from './schema.js';

/**
 * §Phase 17.1's route table.
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
 * `POST /v1/bookings/:id/reveal-contact`. `GET /v1/bookings/:id/contact-info`
 * does not exist here and must never be created.
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
      schema: { params: listingParams, body: createSlotBookingBody },
      preValidation: [requireAuth, requireEmailVerified, requireActiveAccount],
      config: { idempotency: { operation: 'booking.create' }, ...bookingRate },
    },
    async (request, reply) => {
      const booking = await app.bookings.createSlotBooking(
        userOf(request).id,
        request.params.id,
        request.body,
      );
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
}
