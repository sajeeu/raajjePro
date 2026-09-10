import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { principalOf, requireAdmin } from '../admin-auth/guards.js';
import { requestMeta } from '../admin-auth/routes.js';
import {
  adminSubmissionListQuery,
  confirmSubmissionBody,
  paymentSubmissionParams,
  rejectSubmissionBody,
  reverseSubmissionBody,
} from './schema.js';

/**
 * §Phase 8a: "Admin: confirm / reject / **reverse** a submission, plus the
 * pending list. All audit-logged."
 *
 * The endpoints are here; §Phase 10a builds the React panel on top of them,
 * and §Phase 10a's own additions — the receipt analysis rendered beside the
 * image, the bank-statement CSV import, the unmatched-transaction queue — are
 * that phase's, not this one's. What this phase owns is the decision itself
 * and its audit trail.
 *
 * ## The admin confirming *is* the verification
 *
 * §0.0 item 11 and §1b: nothing automated approves a payment. There is no
 * endpoint here that confirms in bulk, none that auto-confirms on a match,
 * and §Phase 10a's analysis "never gates the confirm button". The whole
 * mechanism rests on a person looking at a receipt and a bank statement.
 *
 * ## Every route behind real admin auth
 *
 * `requireAdmin` — an enrolled, MFA-verified admin (§Phase 2). The read is
 * guarded too: the queue names payers and amounts, and an unauthorized read
 * of a payment detail is a real leak (backend/CLAUDE.md).
 */
export function registerSubscriptionAdminRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const base = '/v1/admin/payment-submissions';

  // Who may call: an enrolled, MFA-verified admin. Oldest first — §1b's
  // 48-hour confirm-or-reject SLA runs from `submittedAt`, so the queue is
  // ordered by the thing the SLA is measured on.
  //
  // Unsubmitted intents are excluded by the repository: a provider who
  // tapped Upgrade and never transferred is not work for an admin.
  r.get(
    base,
    { schema: { querystring: adminSubmissionListQuery }, preHandler: requireAdmin },
    async (request, reply) => {
      const page = await app.subscriptions.listSubmissionsForAdmin({
        status: request.query.status,
        ...(request.query.purpose === undefined ? {} : { purpose: request.query.purpose }),
        limit: request.query.limit,
        ...(request.query.cursor === undefined ? {} : { cursor: request.query.cursor }),
      });
      return reply.send(ok(page.items, { nextCursor: page.nextCursor }));
    },
  );

  // Who may call: an enrolled, MFA-verified admin. §1b step 4 — grants the
  // entitlement, sets the provider's price if this is their first confirmed
  // payment, extends the 30-day period from the billing anchor, generates the
  // PDF invoice and restores anything the free-tier cap had hidden.
  //
  // Idempotency key required: this is money-adjacent and grants a period. A
  // replayed request must return the original result rather than extending
  // the subscription twice — and two admins racing each other are refused
  // with a conflict by the conditional status transition, which is the
  // guarantee that does not depend on the client sending a key at all.
  r.post(
    `${base}/:id/confirm`,
    {
      schema: { params: paymentSubmissionParams, body: confirmSubmissionBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'payment-submission.confirm' } },
    },
    async (request, reply) => {
      return reply.send(
        ok(
          await app.subscriptions.confirmSubmission(request.params.id, principalOf(request).id, {
            ...(request.body?.note === undefined ? {} : { note: request.body.note }),
            meta: requestMeta(request),
          }),
        ),
      );
    },
  );

  // Who may call: an enrolled, MFA-verified admin. §1b step 4–5: reason
  // required, and the provider sees it and may resubmit immediately — no
  // cooldown, and no appeal action (ledger row **P8A-1**: no section of the
  // plan says what an appeal changes, so nothing here invents one).
  r.post(
    `${base}/:id/reject`,
    {
      schema: { params: paymentSubmissionParams, body: rejectSubmissionBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'payment-submission.reject' } },
    },
    async (request, reply) => {
      return reply.send(
        ok(
          await app.subscriptions.rejectSubmission(
            request.params.id,
            principalOf(request).id,
            request.body.reason,
            requestMeta(request),
          ),
        ),
      );
    },
  );

  // Who may call: an enrolled, MFA-verified admin. §1b's reversal — "mistake,
  // bank reversal. **Explicit endpoint with an audit-log entry, never a
  // database edit.**" It takes back the period the payment bought, voids the
  // invoice rather than deleting it, and re-hides the listings the upgrade
  // had restored.
  r.post(
    `${base}/:id/reverse`,
    {
      schema: { params: paymentSubmissionParams, body: reverseSubmissionBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'payment-submission.reverse' } },
    },
    async (request, reply) => {
      return reply.send(
        ok(
          await app.subscriptions.reverseSubmission(
            request.params.id,
            principalOf(request).id,
            request.body.reason,
            requestMeta(request),
          ),
        ),
      );
    },
  );
}
