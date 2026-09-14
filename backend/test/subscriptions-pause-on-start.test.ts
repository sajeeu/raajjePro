import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { PAUSE_ALLOWANCE_MINUTES } from '../src/modules/subscriptions/period.js';
import { buildTestApp, controllableClock, freshIp } from './helpers/app.js';
import { SUBSCRIPTION, post, readStatus } from './helpers/subscriptions.js';
import { registerUser } from './helpers/users.js';

/**
 * §1b: "**pause keys off the provider-level `acceptingNewCustomers` toggle**".
 *
 * `SubscriptionService.acceptingNewCustomersChanged` answers that for a
 * provider who reaches for the toggle — a *transition*. This file covers the
 * case a transition cannot see, and it is reachable today rather than
 * hypothetical: the toggle renders in §Phase 6a's onboarding step 2, where
 * turning it off correctly does nothing because there is no clock to stop.
 * When a clock later starts, no transition happens.
 *
 * Without the reconcile at clock start, the provider ends up `trialing`, not
 * accepting customers and **not paused** — burning trial days while taking no
 * work, which is the one thing §1b's pause exists to prevent. Every test here
 * fails against that.
 */

const time = controllableClock(new Date('2026-09-14T08:00:00.000Z'));
let app: Awaited<ReturnType<typeof buildApp>>;

async function setAccepting(
  headers: Record<string, string>,
  acceptingNewCustomers: boolean,
): Promise<void> {
  const res = await app.inject({
    method: 'PATCH',
    url: '/v1/providers/me',
    headers,
    remoteAddress: freshIp(),
    payload: { acceptingNewCustomers },
  });
  if (res.statusCode !== 200) throw new Error(`toggle: ${String(res.statusCode)} ${res.body}`);
}

beforeAll(async () => {
  ({ app } = await buildTestApp({ clock: time.clock }));
});

afterAll(async () => {
  await app.close();
});

describe('a clock starts in the state the toggle already describes', () => {
  it('starts a trial paused for a provider who is not accepting customers', async () => {
    const provider = await registerUser(app, { role: 'provider' });
    // Turned off while free-tier — the §Phase 6a onboarding case. Nothing
    // happens to billing here, correctly: there is no clock.
    await setAccepting(provider.headers, false);
    expect((await readStatus(app, provider.headers)).status).toBe('free');

    const started = await post(app, provider.headers, `${SUBSCRIPTION}/start-trial`);
    expect(started.statusCode).toBe(200);

    const status = await readStatus(app, provider.headers);
    // The trial exists — it is not refused — and its clock is stopped.
    expect(status.status).toBe('paused');
    expect(status.tier).toBe('premium');
    expect(status.trial.startedAt).not.toBeNull();
    // And the trial is intact rather than spent: its clock has not started running.
    expect(status.trial.available).toBe(false);
  });

  it('leaves a provider who is accepting customers running', async () => {
    // The other half, without which the test above passes against a service
    // that simply pauses every trial it starts.
    const provider = await registerUser(app, { role: 'provider' });
    expect((await readStatus(app, provider.headers)).status).toBe('free');

    expect((await post(app, provider.headers, `${SUBSCRIPTION}/start-trial`)).statusCode).toBe(200);

    const status = await readStatus(app, provider.headers);
    expect(status.status).toBe('trialing');
    expect(status.tier).toBe('premium');
  });

  it('turning the toggle back on resumes the clock it stopped', async () => {
    const provider = await registerUser(app, { role: 'provider' });
    await setAccepting(provider.headers, false);
    await post(app, provider.headers, `${SUBSCRIPTION}/start-trial`);
    expect((await readStatus(app, provider.headers)).status).toBe('paused');

    // Through §Phase 5's door rather than the billing one, because the two
    // reach the same function and this is the door the provider found first.
    await setAccepting(provider.headers, true);
    expect((await readStatus(app, provider.headers)).status).toBe('trialing');
  });

  it('starts the trial unpaused rather than refusing it when the allowance is gone', async () => {
    // `pause` throws PAUSE_ALLOWANCE_EXHAUSTED so §Phase 10a can tell a
    // provider why their deliberate pause was refused. Nobody asked for a
    // pause here, so failing the trial start over it would be absurd — the
    // provider runs unpaused, which is the only remaining option.
    const provider = await registerUser(app, { role: 'provider' });
    const profile = await app.providers.getOrCreateProviderProfile(provider.userId);
    await app.deps.prisma.providerProfile.update({
      where: { id: profile.id },
      data: { acceptingNewCustomers: false },
    });
    await app.deps.prisma.providerSubscription.create({
      data: { providerProfileId: profile.id, cumulativePausedMinutes: PAUSE_ALLOWANCE_MINUTES },
    });

    const started = await post(app, provider.headers, `${SUBSCRIPTION}/start-trial`);
    expect(started.statusCode).toBe(200);
    expect((await readStatus(app, provider.headers)).status).toBe('trialing');
  });
});
