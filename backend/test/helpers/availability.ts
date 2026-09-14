import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';

import type { PrismaClient } from '../../src/generated/prisma/client.js';
import type {
  AvailabilityRuleDto,
  ListingAvailabilityDto,
  OpenSlotsDto,
  ProviderSlotDto,
  TimeOffDto,
} from '../../src/modules/availability/types.js';
import { freshIp } from './app.js';
import { completeDraft, publish } from './listings.js';
import { registerUser, type RegisteredUser } from './users.js';

interface Envelope<T> {
  data: T;
}

export const MON_TO_THU = [1, 2, 3, 4];

/** A published, slot-mode listing owned by a fresh provider — the state every test below starts from. */
export async function providerWithSlotListing(
  app: FastifyInstance,
  options: { categoryName?: string } = {},
): Promise<{ user: RegisteredUser; listingId: string; providerProfileId: string }> {
  const user = await registerUser(app, { role: 'provider' });
  const draft = await completeDraft(app, user.headers, {
    categoryName: options.categoryName ?? 'Cleaning',
  });
  const published = await publish(app, user.headers, draft.id);
  if (published.statusCode !== 200) {
    throw new Error(`publish: ${String(published.statusCode)} ${published.body}`);
  }
  const prisma: PrismaClient = app.deps.prisma;
  const listing = await prisma.listing.findUniqueOrThrow({
    where: { id: draft.id },
    select: { providerProfileId: true },
  });
  return { user, listingId: draft.id, providerProfileId: listing.providerProfileId };
}

export function availabilityBase(listingId: string): string {
  return `/v1/providers/me/listings/${listingId}/availability`;
}

export async function addRule(
  app: FastifyInstance,
  user: RegisteredUser,
  listingId: string,
  body: {
    weekdays?: number[];
    startTime?: string;
    endTime?: string;
    slotDurationMinutes?: number;
  } = {},
): Promise<AvailabilityRuleDto> {
  const res = await app.inject({
    method: 'POST',
    url: `${availabilityBase(listingId)}/rules`,
    headers: user.headers,
    remoteAddress: freshIp(),
    payload: {
      weekdays: body.weekdays ?? MON_TO_THU,
      startTime: body.startTime ?? '09:00',
      endTime: body.endTime ?? '17:00',
      slotDurationMinutes: body.slotDurationMinutes ?? 120,
    },
  });
  if (res.statusCode !== 201) throw new Error(`addRule: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<AvailabilityRuleDto>>().data;
}

export async function readAvailability(
  app: FastifyInstance,
  user: RegisteredUser,
  listingId: string,
): Promise<ListingAvailabilityDto> {
  const res = await app.inject({
    method: 'GET',
    url: availabilityBase(listingId),
    headers: user.headers,
    remoteAddress: freshIp(),
  });
  return res.json<Envelope<ListingAvailabilityDto>>().data;
}

export async function ownSlots(
  app: FastifyInstance,
  user: RegisteredUser,
  listingId: string,
  query = '',
): Promise<ProviderSlotDto[]> {
  const res = await app.inject({
    method: 'GET',
    url: `/v1/providers/me/listings/${listingId}/slots${query}`,
    headers: user.headers,
    remoteAddress: freshIp(),
  });
  if (res.statusCode !== 200) throw new Error(`ownSlots: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<ProviderSlotDto[]>>().data;
}

/** The customer picker, as a guest — no headers at all. */
export async function openSlots(
  app: FastifyInstance,
  listingId: string,
  query = '',
): Promise<OpenSlotsDto> {
  const res = await app.inject({
    method: 'GET',
    url: `/v1/listings/${listingId}/slots${query}`,
    remoteAddress: freshIp(),
  });
  if (res.statusCode !== 200) throw new Error(`openSlots: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<OpenSlotsDto>>().data;
}

export async function addTimeOff(
  app: FastifyInstance,
  user: RegisteredUser,
  body: { name?: string; startDate: string; endDate: string },
): Promise<TimeOffDto> {
  const res = await app.inject({
    method: 'POST',
    url: '/v1/providers/me/time-off',
    headers: user.headers,
    remoteAddress: freshIp(),
    payload: {
      name: body.name ?? 'Trip to Colombo',
      startDate: body.startDate,
      endDate: body.endDate,
    },
  });
  if (res.statusCode !== 201) throw new Error(`addTimeOff: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<TimeOffDto>>().data;
}

export function idempotent(): { 'idempotency-key': string } {
  return { 'idempotency-key': randomUUID() };
}

/**
 * The first item, or a failure naming what was missing.
 *
 * The suite forbids `!` (`@typescript-eslint/no-non-null-assertion`), and for
 * good reason in a test: a non-null assertion on an empty array fails later,
 * somewhere else, with `Cannot read properties of undefined` — which reads as
 * a bug in the code under test rather than a fixture that produced nothing.
 */
export function firstOf<T>(items: readonly T[], what: string): T {
  const [item] = items;
  if (item === undefined) throw new Error(`expected at least one ${what}`);
  return item;
}

/** The last item, same contract. */
export function lastOf<T>(items: readonly T[], what: string): T {
  const item = items.at(-1);
  if (item === undefined) throw new Error(`expected at least one ${what}`);
  return item;
}

/** The item matching, or a failure naming what was looked for. */
export function pickOne<T>(items: readonly T[], predicate: (item: T) => boolean, what: string): T {
  const found = items.find(predicate);
  if (found === undefined) throw new Error(`expected ${what}`);
  return found;
}
