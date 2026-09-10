import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';

import type { SubscriptionBookingSource } from '../../src/modules/subscriptions/bookings.js';
import type {
  BillingEventInput,
  BillingNotifier,
} from '../../src/modules/subscriptions/notifications.js';
import type {
  AdminPaymentSubmissionDto,
  PaymentSubmissionDto,
  SubscriptionStatusDto,
  UpgradeRequestDto,
} from '../../src/modules/subscriptions/types.js';
import { freshIp } from './app.js';
import { jpeg, uploadPathOf } from './listings.js';

interface Envelope<T> {
  data: T;
}

/**
 * The `Booking` table stand-in (§Phase 8a's injected source, ledger row
 * **P8A-2**).
 *
 * §Phase 17.1 builds the real one. Until then no booking exists, so the
 * default answers are the true ones and these two setters are how a test
 * moves a provider or a listing across a rule's line without a table to
 * insert into — the same thing `FakeListings` did for §Phase 5's visibility
 * rule, which Phase 8 then closed.
 */
export class FakeBookings implements SubscriptionBookingSource {
  private readonly providersWithBookings = new Set<string>();
  private readonly protectedListings = new Set<string>();

  /** "A booking has landed" for this provider — what the 7-day prompt checks. */
  giveBooking(providerProfileId: string): void {
    this.providersWithBookings.add(providerProfileId);
  }

  /** §1b's protected listing: a non-terminal booking with a future `scheduledFor`. */
  commit(listingId: string): void {
    this.protectedListings.add(listingId);
  }

  /** The booking reached a terminal state — `completed`, `cancelled`, `declined`, `dispute_resolved`. */
  complete(listingId: string): void {
    this.protectedListings.delete(listingId);
  }

  hasAnyBooking(providerProfileId: string): Promise<boolean> {
    return Promise.resolve(this.providersWithBookings.has(providerProfileId));
  }

  listingIdsWithCommittedBooking(listingIds: string[]): Promise<string[]> {
    return Promise.resolve(listingIds.filter((id) => this.protectedListings.has(id)));
  }
}

/** §Phase 19's delivery, as a recorder — what fired, for whom, with what detail. */
export class RecordingBillingNotifier implements BillingNotifier {
  readonly sent: BillingEventInput[] = [];

  notify(input: BillingEventInput): Promise<void> {
    this.sent.push(input);
    return Promise.resolve();
  }

  eventsFor(providerProfileId: string): string[] {
    return this.sent.filter((e) => e.providerProfileId === providerProfileId).map((e) => e.event);
  }
}

export const SUBSCRIPTION = '/v1/providers/me/subscription';
export const ADMIN_SUBMISSIONS = '/v1/admin/payment-submissions';

export async function readStatus(
  app: FastifyInstance,
  headers: Record<string, string>,
): Promise<SubscriptionStatusDto> {
  const res = await app.inject({
    method: 'GET',
    url: SUBSCRIPTION,
    headers,
    remoteAddress: freshIp(),
  });
  if (res.statusCode !== 200) throw new Error(`status: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<SubscriptionStatusDto>>().data;
}

export function post(app: FastifyInstance, headers: Record<string, string>, path: string) {
  return app.inject({
    method: 'POST',
    url: path,
    headers: { ...headers, 'idempotency-key': randomUUID() },
    remoteAddress: freshIp(),
  });
}

/**
 * §1b's steps 1–3, as a client performs them: the intent, then the three-step
 * proof upload, then submit.
 *
 * Through the real HTTP routes rather than the service, because the whole
 * point of the presigned shape is that the client never touches an object key
 * — and because "nothing is granted on submission" is only a real assertion
 * if the submission went through the door a provider actually uses.
 */
export async function submitPayment(
  app: FastifyInstance,
  headers: Record<string, string>,
): Promise<PaymentSubmissionDto> {
  const requested = await post(app, headers, `${SUBSCRIPTION}/upgrade-request`);
  if (requested.statusCode !== 201) {
    throw new Error(`upgrade-request: ${String(requested.statusCode)} ${requested.body}`);
  }
  const { submission } = requested.json<Envelope<UpgradeRequestDto>>().data;

  const target = await app.inject({
    method: 'POST',
    url: `/v1/providers/me/payment-submissions/${submission.id}/proof`,
    headers: { ...headers, 'idempotency-key': randomUUID() },
    remoteAddress: freshIp(),
    payload: { contentType: 'image/jpeg' },
  });
  if (target.statusCode !== 201) {
    throw new Error(`proof target: ${String(target.statusCode)} ${target.body}`);
  }
  const upload =
    target.json<Envelope<{ upload: { url: string; headers: Record<string, string> } }>>().data
      .upload;

  const put = await app.inject({
    method: 'PUT',
    url: uploadPathOf(upload.url),
    headers: upload.headers,
    remoteAddress: freshIp(),
    payload: jpeg({ withExif: true }),
  });
  if (put.statusCode !== 204) throw new Error(`proof put: ${String(put.statusCode)} ${put.body}`);

  const submitted = await app.inject({
    method: 'POST',
    url: `/v1/providers/me/payment-submissions/${submission.id}/submit`,
    headers: { ...headers, 'idempotency-key': randomUUID() },
    remoteAddress: freshIp(),
  });
  if (submitted.statusCode !== 200) {
    throw new Error(`submit: ${String(submitted.statusCode)} ${submitted.body}`);
  }
  return submitted.json<Envelope<PaymentSubmissionDto>>().data;
}

/** The admin half: confirm, reject or reverse, through the guarded routes. */
export async function adminDecide(
  app: FastifyInstance,
  cookie: string,
  submissionId: string,
  action: 'confirm' | 'reject' | 'reverse',
  body?: Record<string, unknown>,
) {
  return app.inject({
    method: 'POST',
    url: `${ADMIN_SUBMISSIONS}/${submissionId}/${action}`,
    headers: {
      cookie,
      'x-requested-with': 'RaajjePro-Admin',
      'idempotency-key': randomUUID(),
    },
    remoteAddress: freshIp(),
    ...(body === undefined ? {} : { payload: body }),
  });
}

export async function confirmPayment(
  app: FastifyInstance,
  cookie: string,
  submissionId: string,
): Promise<AdminPaymentSubmissionDto> {
  const res = await adminDecide(app, cookie, submissionId, 'confirm', {});
  if (res.statusCode !== 200) throw new Error(`confirm: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<AdminPaymentSubmissionDto>>().data;
}
