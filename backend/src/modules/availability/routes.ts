import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import {
  availabilityExceptionBody,
  availabilityRuleBody,
  exceptionParams,
  listingParams,
  publicListingParams,
  ruleParams,
  slotParams,
  slotRangeQuery,
  timeOffBody,
  timeOffParams,
  updateAvailabilityRuleBody,
} from './schema.js';

/**
 * §Phase 9a's endpoints — "generate/regenerate, block/unblock, list open slots
 * for a listing", plus the rules, exceptions and time away those three act on.
 *
 * ## Two audiences, two URL shapes
 *
 * Everything a provider does is under `/v1/providers/me/…`, the own-
 * representation shape §Phase 5 and §Phase 8 established. The **one** public
 * route is `GET /v1/listings/:id/slots`, which is the customer picker and is
 * deliberately reachable by a guest: browsing is public (§0.2) and a customer
 * must be able to see when someone is free before deciding to sign in.
 *
 * `/v1/listings/:id` itself stays unclaimed — §Phase 12's Service Preview
 * defines the public listing shape, and this adds a sub-resource under it
 * rather than pre-empting that.
 *
 * ## Authorization
 *
 * Provider routes: `requireAuth`, plus `requireActiveAccount` on the writes —
 * §Phase 3 freezes an account with a deletion request pending and it "starts
 * nothing new", and publishing new bookable time is starting something.
 * Ownership is not a route-level check: `AvailabilityService` resolves the
 * caller's own profile and queries with it, so another provider's listing is
 * *not found* rather than found and refused.
 *
 * `requireEmailVerified` is deliberately **not** here. §1c's stricter guard
 * gates booking, enquiry and messaging — the act of *taking* a time, which is
 * §Phase 17.1's endpoint. Looking at a calendar is not one of them, and §1a
 * says dashboard access is never gated.
 *
 * ## No response here carries a phone number
 *
 * Structurally — no DTO in `types.ts` has a field for one and nothing in this
 * module reads a `User` row (§1c: exactly one endpoint in the system may
 * return one, and it is not one of these).
 */
export function registerAvailabilityRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const base = '/v1/providers/me/listings/:listingId/availability';

  /** The editor saves a rule at a time and the grid refetches after each; generous, like the wizard's. */
  const providerRate = {
    rateLimit: {
      max: 120,
      timeWindow: '1 minute',
      keyGenerator: (req: { principal?: { id: string }; ip: string }) =>
        `user:${req.principal?.id ?? req.ip}`,
    },
  };

  // Who may call: the owner. The whole Availability screen in one read —
  // rules, modified hours, and how far ahead times currently reach.
  r.get(
    base,
    { schema: { params: listingParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(
        ok(
          await app.availability.readListingAvailability(
            userOf(request).id,
            request.params.listingId,
          ),
        ),
      ),
  );

  // Who may call: the owner. What the "Add rule" sheet opens with — the
  // wizard's own step-5 window, so a provider is not asked to state their
  // hours twice.
  r.get(
    `${base}/rule-defaults`,
    { schema: { params: listingParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(
        ok(await app.availability.ruleDefaults(userOf(request).id, request.params.listingId)),
      ),
  );

  // Who may call: the owner, on a listing that takes time slots.
  //
  // No idempotency key: a replayed create would add a second identical rule,
  // but `checkNoRuleClash` refuses it as an overlap — the rule that exists for
  // clarity also happens to make a double-tap safe, and a key would be a
  // second mechanism for the same outcome.
  r.post(
    base + '/rules',
    {
      schema: { params: listingParams, body: availabilityRuleBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) => {
      const rule = await app.availability.addRule(
        userOf(request).id,
        request.params.listingId,
        request.body,
      );
      return reply.code(201).send(ok(rule));
    },
  );

  // Who may call: the owner. A PUT rather than a PATCH because the editor
  // sheet opens with every field filled and replaces the rule wholesale.
  r.put(
    `${base}/rules/:ruleId`,
    {
      schema: { params: ruleParams, body: updateAvailabilityRuleBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.availability.updateRule(
            userOf(request).id,
            request.params.listingId,
            request.params.ruleId,
            request.body,
          ),
        ),
      ),
  );

  // Who may call: the owner. Soft-delete (invariant 8) — the rule stops
  // generating and stays readable, because slots it produced may hold
  // somebody's booking.
  r.delete(
    `${base}/rules/:ruleId`,
    {
      schema: { params: ruleParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) => {
      await app.availability.removeRule(
        userOf(request).id,
        request.params.listingId,
        request.params.ruleId,
      );
      return reply.code(204).send();
    },
  );

  // Who may call: the owner. "Modified hours" — a named date range that
  // changes the hours the weekly rules produce (Ramadan, and its kind).
  r.post(
    `${base}/exceptions`,
    {
      schema: { params: listingParams, body: availabilityExceptionBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) => {
      const exception = await app.availability.addException(
        userOf(request).id,
        request.params.listingId,
        request.body,
      );
      return reply.code(201).send(ok(exception));
    },
  );

  r.delete(
    `${base}/exceptions/:exceptionId`,
    {
      schema: { params: exceptionParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) => {
      await app.availability.removeException(
        userOf(request).id,
        request.params.listingId,
        request.params.exceptionId,
      );
      return reply.code(204).send();
    },
  );

  // Who may call: the owner. §Phase 9a's "generate/regenerate". Idempotent by
  // construction — re-running changes nothing — so a repeat is harmless and
  // needs no key.
  r.post(
    `/v1/providers/me/listings/:listingId/slots/regenerate`,
    {
      schema: { params: listingParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) =>
      reply.send(
        ok(await app.availability.regenerate(userOf(request).id, request.params.listingId)),
      ),
  );

  // Who may call: the owner. Their own grid, including `reserved` and
  // `blocked` — the customer's view of the same listing is the route at the
  // bottom of this file and shows neither.
  r.get(
    `/v1/providers/me/listings/:listingId/slots`,
    {
      schema: { params: listingParams, querystring: slotRangeQuery },
      preValidation: requireAuth,
    },
    async (request, reply) =>
      reply.send(
        ok(
          await app.availability.listOwnSlots(
            userOf(request).id,
            request.params.listingId,
            request.query,
          ),
        ),
      ),
  );

  // Who may call: the owner of the slot. §Phase 9a's "block/unblock" — the
  // plan's "individual override", one time at a time.
  r.post(
    `/v1/providers/me/slots/:slotId/block`,
    {
      schema: { params: slotParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) =>
      reply.send(ok(await app.availability.blockSlot(userOf(request).id, request.params.slotId))),
  );

  r.post(
    `/v1/providers/me/slots/:slotId/unblock`,
    {
      schema: { params: slotParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) =>
      reply.send(ok(await app.availability.unblockSlot(userOf(request).id, request.params.slotId))),
  );

  // Who may call: any signed-in provider, for themselves. `My Calendar`'s two
  // sections: what they are committed to, and when they are away.
  r.get(
    '/v1/providers/me/calendar',
    { schema: { querystring: slotRangeQuery }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.availability.readCalendar(userOf(request).id, request.query))),
  );

  r.get('/v1/providers/me/time-off', { preValidation: requireAuth }, async (request, reply) =>
    reply.send(ok(await app.availability.listTimeOff(userOf(request).id))),
  );

  // Who may call: any signed-in, non-frozen provider, for themselves.
  // Provider-wide by design: a trip stops every listing, not one.
  r.post(
    '/v1/providers/me/time-off',
    {
      schema: { body: timeOffBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) => {
      const away = await app.availability.addTimeOff(userOf(request).id, request.body);
      return reply.code(201).send(ok(away));
    },
  );

  r.delete(
    '/v1/providers/me/time-off/:timeOffId',
    {
      schema: { params: timeOffParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: providerRate,
    },
    async (request, reply) => {
      await app.availability.removeTimeOff(userOf(request).id, request.params.timeOffId);
      return reply.code(204).send();
    },
  );

  // Who may call: **anyone, including a guest.** The customer picker.
  //
  // It returns only times that are open, not yet past the category's lead
  // time, and not overlapping anything the provider already holds — so no
  // caller can render an unavailable time even by ignoring the response's
  // meaning (§1c). The listing must itself be publicly visible and its
  // provider must pass §1a's one shared visibility helper; a listing that
  // fails either reads as not found, exactly as §Phase 13's profile does.
  r.get(
    '/v1/listings/:id/slots',
    { schema: { params: publicListingParams, querystring: slotRangeQuery } },
    async (request, reply) =>
      reply.send(ok(await app.availability.listOpenSlots(request.params.id, request.query))),
  );
}
