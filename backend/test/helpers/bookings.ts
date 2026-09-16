import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';

import type { PrismaClient } from '../../src/generated/prisma/client.js';
import type { BookingDto } from '../../src/modules/bookings/types.js';
import { freshIp } from './app.js';
import { addRule, ownSlots, providerWithSlotListing } from './availability.js';
import { registerUser, type RegisteredUser } from './users.js';

interface Envelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

/**
 * A customer who can actually book.
 *
 * §1c's access-control table puts booking behind `requireEmailVerified`, so a
 * freshly-registered user cannot make one — which is the rule working, not a
 * fixture problem. Every test that needs a booking needs a verified customer,
 * and the verification is stamped directly because §Phase 3's OTP flow is
 * tested where it lives.
 */
export async function verifiedCustomer(app: FastifyInstance): Promise<RegisteredUser> {
  const user = await registerUser(app, { role: 'customer' });
  const prisma: PrismaClient = app.deps.prisma;
  await prisma.user.update({
    where: { id: user.userId },
    data: { emailVerifiedAt: new Date() },
  });
  // The principal carries `emailVerified`, and it is read from the token's
  // session on each request — so re-reading is enough and no new sign-in is
  // needed. Asserted by every test below that books successfully.
  return user;
}

/** A published slot-mode listing with a generated grid, and a verified customer for it. */
export async function bookableListing(
  app: FastifyInstance,
  options: { categoryName?: string; slotDurationMinutes?: number } = {},
): Promise<{
  provider: RegisteredUser;
  customer: RegisteredUser;
  listingId: string;
  providerProfileId: string;
  slotId: string;
  slotStartsAt: string;
}> {
  const {
    user: provider,
    listingId,
    providerProfileId,
  } = await providerWithSlotListing(app, {
    ...(options.categoryName === undefined ? {} : { categoryName: options.categoryName }),
  });
  await addRule(app, provider, listingId, {
    ...(options.slotDurationMinutes === undefined
      ? {}
      : { slotDurationMinutes: options.slotDurationMinutes }),
  });
  const slots = await ownSlots(app, provider, listingId);
  const slot = slots[0];
  if (slot === undefined) throw new Error('no slots were generated for the fixture listing');
  const customer = await verifiedCustomer(app);
  return {
    provider,
    customer,
    listingId,
    providerProfileId,
    slotId: slot.id,
    slotStartsAt: slot.startsAt,
  };
}

/**
 * A fresh idempotency key per call unless the caller names one. §Phase 17
 * item 2 requires the key on creation, so a helper that omitted it would make
 * every test assert the middleware rather than the rule it is about — and the
 * requirement itself is asserted once, on purpose, in `bookings-machine`.
 */
export async function createBooking(
  app: FastifyInstance,
  customer: RegisteredUser,
  listingId: string,
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
) {
  return app.inject({
    method: 'POST',
    url: `/v1/listings/${listingId}/bookings`,
    headers: { 'idempotency-key': randomUUID(), ...customer.headers, ...headers },
    remoteAddress: freshIp(),
    payload: body,
  });
}

/** Creates and unwraps, throwing on anything but 201 — for the many tests that start from a booking. */
export async function bookSlot(
  app: FastifyInstance,
  customer: RegisteredUser,
  listingId: string,
  slotId: string,
  extra: Record<string, unknown> = {},
): Promise<BookingDto> {
  const res = await createBooking(app, customer, listingId, { timeSlotId: slotId, ...extra });
  if (res.statusCode !== 201) throw new Error(`bookSlot: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<BookingDto>>().data;
}

export async function act(
  app: FastifyInstance,
  user: RegisteredUser,
  bookingId: string,
  action: string,
  payload?: Record<string, unknown>,
) {
  return app.inject({
    method: 'PATCH',
    url: `/v1/bookings/${bookingId}/${action}`,
    headers: user.headers,
    remoteAddress: freshIp(),
    ...(payload === undefined ? {} : { payload }),
  });
}

/** The same, unwrapped — for the happy path, where a non-200 is a test failure. */
export async function actOk(
  app: FastifyInstance,
  user: RegisteredUser,
  bookingId: string,
  action: string,
  payload?: Record<string, unknown>,
): Promise<BookingDto> {
  const res = await act(app, user, bookingId, action, payload);
  if (res.statusCode !== 200) throw new Error(`${action}: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<BookingDto>>().data;
}

export async function readBooking(
  app: FastifyInstance,
  user: RegisteredUser,
  bookingId: string,
): Promise<BookingDto> {
  const res = await app.inject({
    method: 'GET',
    url: `/v1/bookings/${bookingId}`,
    headers: user.headers,
    remoteAddress: freshIp(),
  });
  if (res.statusCode !== 200) throw new Error(`read: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<BookingDto>>().data;
}

export async function listBookings(
  app: FastifyInstance,
  user: RegisteredUser,
  query = '',
): Promise<{ bookings: BookingDto[]; nextCursor: string | null }> {
  const res = await app.inject({
    method: 'GET',
    url: `/v1/users/me/bookings${query}`,
    headers: user.headers,
    remoteAddress: freshIp(),
  });
  if (res.statusCode !== 200) throw new Error(`list: ${String(res.statusCode)} ${res.body}`);
  const body = res.json<Envelope<BookingDto[]>>();
  return { bookings: body.data, nextCursor: body.meta?.nextCursor ?? null };
}

/** Drives a booking to `awaiting_payment` — the state most of the payment tests start from. */
export async function acceptedBooking(app: FastifyInstance) {
  const fixture = await bookableListing(app);
  const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
  const accepted = await actOk(app, fixture.provider, booking.id, 'accept');
  return { ...fixture, booking: accepted };
}

export function errorCode(res: { body: string }): string {
  return (JSON.parse(res.body) as { error?: { code?: string } }).error?.code ?? '';
}
