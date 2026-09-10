import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import { toMediaDto } from './types.js';
import {
  createListingBody,
  createListingMediaBody,
  listingMediaParams,
  listingParams,
  listingVisibilityBody,
  listOwnListingsQuery,
  updateListingBody,
} from './schema.js';

/**
 * The service-listing surface (§Phase 8).
 *
 * ## Why every route is under `/v1/providers/me/listings`
 *
 * These are the **owner's** view of their own listings, and the codebase
 * already puts an own-representation behind `/v1/<owner>/me/…`:
 * `GET /v1/providers/me`, `POST /v1/providers/me/service-areas`,
 * `PATCH /v1/users/me`. §Phase 5 left the *public* provider route to
 * §Phase 13 rather than making one response shape depend on who was asking,
 * and this phase does the same for listings: `/v1/listings/:id` is
 * deliberately unclaimed, so §Phase 12's Service Preview and §Phase 15's
 * search can define the public shape without inheriting a body full of
 * `missingRequiredFields` and gallery upload states.
 *
 * 🔧 Four Phase 5 comments predicted `POST /v1/listings` as §1a's implicit
 * profile-creation moment. The *moment* is unchanged — creating a draft
 * creates the profile — only the URL differs, and all four now say so.
 *
 * ## Authorization
 *
 * Every route is `requireAuth` plus, on the writes, `requireActiveAccount`:
 * §Phase 3 freezes an account with a deletion request pending and it "starts
 * nothing new". Ownership is not a route-level check — `ListingService`
 * resolves the caller's own profile and queries with it in the WHERE, so a
 * listing belonging to somebody else is not found rather than found and
 * rejected.
 *
 * `requireEmailVerified` is deliberately **not** here. §1c's stricter guard
 * gates booking, enquiry and messaging; §1a says dashboard access is never
 * gated, and a provider with drafts reaches their workspace normally. Phase
 * 6a is where an unverified email blocks progress.
 *
 * ## No response here carries a phone number
 *
 * Structurally: `OwnListingDto` has no field for one and nothing in this
 * module reads a `User` row (§1c — exactly one endpoint in the system may
 * return a number to another user, and it is not one of these).
 */
export function registerListingRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const base = '/v1/providers/me/listings';

  /** Generous: the wizard autosaves every step and replays a queue on reconnect (§Phase 9). */
  const wizardRate = {
    rateLimit: {
      max: 120,
      timeWindow: '1 minute',
      keyGenerator: (req: { principal?: { id: string }; ip: string }) =>
        `user:${req.principal?.id ?? req.ip}`,
    },
  };

  // Who may call: any signed-in, non-frozen user, for themselves.
  //
  // **Implicitly creates the provider profile** (§1a, §Phase 8) — starting a
  // listing is acting as a provider. Idempotency key required, as §Phase 8
  // asks: without one, a double tap on a weak connection leaves two empty
  // drafts in My Services and the wizard resumes into whichever it last saw.
  r.post(
    base,
    {
      schema: { body: createListingBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'listing.create' }, ...wizardRate },
    },
    async (request, reply) => {
      const listing = await app.listings.createDraft(userOf(request).id, request.body);
      return reply.code(201).send(ok(listing));
    },
  );

  // Who may call: the signed-in user, for their own listings. My Services
  // (§Phase 10) is the consumer. Paged, because a provider on a paid tier has
  // no fixed ceiling on drafts.
  r.get(
    base,
    { schema: { querystring: listOwnListingsQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const page = await app.listings.listOwn(userOf(request).id, request.query);
      return reply.send(ok(page.items, { nextCursor: page.nextCursor }));
    },
  );

  // Who may call: the owner. A listing that does not exist, one owned by
  // somebody else and one already deleted all answer the same not-found, so
  // this cannot be used to discover which ids are real.
  r.get(
    `${base}/:id`,
    { schema: { params: listingParams }, preValidation: requireAuth },
    async (request, reply) => {
      return reply.send(ok(await app.listings.readOwn(userOf(request).id, request.params.id)));
    },
  );

  // Who may call: the owner. One PATCH per wizard step, and a step may be
  // half-filled — invariant 2's "a draft must be saveable with zero required
  // fields filled" lives here.
  //
  // No idempotency key: a PATCH is not a creation, and a replayed partial
  // update converges on the same row. Same reasoning as
  // `PATCH /v1/providers/me`.
  r.patch(
    `${base}/:id`,
    {
      schema: { params: listingParams, body: updateListingBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: wizardRate,
    },
    async (request, reply) => {
      return reply.send(
        ok(await app.listings.updateOwn(userOf(request).id, request.params.id, request.body)),
      );
    },
  );

  // Who may call: the owner. The only door from draft to live, and the only
  // place the six required fields, the entitlement cap, the
  // pricing/booking-mode rule and §1c's emergency gate are all enforced.
  //
  // Idempotent: publishing twice is the same listing published, and a client
  // that lost the response on a flaky connection must not be told its
  // second attempt breached the cap.
  r.post(
    `${base}/:id/publish`,
    {
      schema: { params: listingParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'listing.publish' }, ...wizardRate },
    },
    async (request, reply) => {
      return reply.send(ok(await app.listings.publish(userOf(request).id, request.params.id)));
    },
  );

  // Who may call: the owner, and only for the two values §1b makes theirs —
  // `active` and `hidden_by_provider`. `hidden_over_cap` belongs to the
  // entitlement system and `hidden_by_admin` to moderation; they are absent
  // from the Zod enum, which is what makes them unreachable from here rather
  // than merely discouraged.
  r.patch(
    `${base}/:id/visibility`,
    {
      schema: { params: listingParams, body: listingVisibilityBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: wizardRate,
    },
    async (request, reply) => {
      return reply.send(
        ok(
          await app.listings.setVisibility(
            userOf(request).id,
            request.params.id,
            request.body.visibility,
          ),
        ),
      );
    },
  );

  // Who may call: the owner. Invariant 8 — stamps `deletedAt`. The row, its
  // media, its service areas and its event log all stay, so a booking or a
  // review that referenced this listing still resolves.
  r.delete(
    `${base}/:id`,
    {
      schema: { params: listingParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: wizardRate,
    },
    async (request, reply) => {
      return reply.send(ok(await app.listings.softDelete(userOf(request).id, request.params.id)));
    },
  );

  // -------------------------------------------------------------------------
  // Media — the three steps a presigned upload takes
  // -------------------------------------------------------------------------

  // Who may call: the owner. Step 1: the server chooses the object key,
  // records a pending row and hands back an expiring upload target. The key
  // is never client-supplied — that is how one provider overwrites another
  // provider's cover image.
  //
  // Idempotency key required: this is a creation POST, and a retried request
  // must return the ORIGINAL target rather than stranding an orphan row and
  // a second object in the store.
  r.post(
    `${base}/:id/media`,
    {
      schema: { params: listingParams, body: createListingMediaBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'listing.media.create' }, ...wizardRate },
    },
    async (request, reply) => {
      const created = await app.listings.createMediaUpload(
        userOf(request).id,
        request.params.id,
        request.body.contentType,
      );
      return reply.code(201).send(
        ok({
          media: toMediaDto(created.media, (key) => app.media.readUrl(key)),
          upload: {
            url: created.target.url,
            method: created.target.method,
            headers: created.target.headers,
            expiresAt: created.target.expiresAt.toISOString(),
            maxBytes: created.target.maxBytes,
          },
        }),
      );
    },
  );

  // Who may call: the owner. Step 3, and where §Phase 8's guarantee is kept:
  // the bytes are read back, their real type sniffed, their size checked and
  // their metadata stripped before the row becomes `stored`. Until it does,
  // the publish gate treats it as a missing cover.
  r.post(
    `${base}/:id/media/:mediaId/complete`,
    {
      schema: { params: listingMediaParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: wizardRate,
    },
    async (request, reply) => {
      const done = await app.listings.finaliseMedia(
        userOf(request).id,
        request.params.id,
        request.params.mediaId,
      );
      return reply.send(ok(toMediaDto(done.media, (key) => app.media.readUrl(key))));
    },
  );

  // Who may call: the owner. Invariant 8 — stamps `removedAt`; the object
  // stays in the store. Removing the cover clears `coverMediaId` and makes
  // the listing incomplete again, but does not unpublish it.
  r.delete(
    `${base}/:id/media/:mediaId`,
    {
      schema: { params: listingMediaParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: wizardRate,
    },
    async (request, reply) => {
      return reply.send(
        ok(
          await app.listings.removeMedia(
            userOf(request).id,
            request.params.id,
            request.params.mediaId,
          ),
        ),
      );
    },
  );
}
