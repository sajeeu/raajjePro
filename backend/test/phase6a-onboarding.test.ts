import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import {
  isOnboardingComplete,
  ONBOARDING_PROFILE_FIELDS,
} from '../src/modules/providers/onboarding.js';
import type { ProviderProfile } from '../src/generated/prisma/client.js';
import type { OwnProviderDto } from '../src/modules/providers/types.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';
import { ensureIslandsSeeded, islandByName } from './helpers/islands.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface Summary {
  isProvider: boolean;
  providerOnboardingComplete: boolean;
}

/**
 * §Phase 6a — Become a Provider, from the backend's side.
 *
 * The flow itself is the Flutter app's, and its three steps are driven in
 * `frontend/test/features/onboarding/`. What the server owes is the shape
 * underneath: the `providerType` §Phase 6a adds, and the derived
 * "has this account completed onboarding?" that §Phase 6a's first and last
 * Done-when lines both turn on.
 *
 * §Phase 6a adds **no endpoint**. Its own wording is "reuse Phase 5's existing
 * update endpoint, do not create a parallel one", and the phone half of its
 * Done-when routes to Phase 3's `PATCH /v1/users/me/phone`
 * (`docs/decisions/17-phase-5-provider-profiles.md`, disagreement 2). The last
 * test in this file is the assertion that no fourth route appeared.
 */
describe('§Phase 6a — the onboarding rule', () => {
  /** A profile with every required field filled, to subtract from. */
  const complete = {
    businessName: "Hassan's Repairs",
    providerType: 'individual',
    bankName: 'Bank of Maldives (BML)',
    bankAccountName: 'Hassan Ibrahim',
    bankAccountNumber: '7730000123456',
  } as unknown as ProviderProfile;

  it('is false with no provider profile at all — a customer has not started', () => {
    expect(isOnboardingComplete({ profile: null, serviceAreaCount: 3, emailVerified: true })).toBe(
      false,
    );
  });

  it('is true only when all three steps and the verified email are in', () => {
    expect(
      isOnboardingComplete({ profile: complete, serviceAreaCount: 1, emailVerified: true }),
    ).toBe(true);
  });

  it('is false with no default service area — step 3 has a disabled CTA, so this is unfinished', () => {
    // The case §Phase 6a's resume rule exists for: step 2 has landed (so the
    // profile exists and `isProvider` is already true) and the provider closed
    // the app on step 3. Routing on `isProvider` alone would send them to a
    // dashboard and they would never see the step they stopped on.
    expect(
      isOnboardingComplete({ profile: complete, serviceAreaCount: 0, emailVerified: true }),
    ).toBe(false);
  });

  it('is false with an unverified email — §Phase 5 requires one to finish', () => {
    // "required to complete Phase 6a's provider onboarding" (§Phase 5), and
    // "Unverified blocks Continue with its own message, since booking
    // notifications go there" (§Phase 6a). Enforced here rather than as a
    // guard on `PATCH /v1/providers/me`, which is also Phase 10a's billing
    // surface — see `providers/onboarding.ts`.
    expect(
      isOnboardingComplete({ profile: complete, serviceAreaCount: 1, emailVerified: false }),
    ).toBe(false);
  });

  it.each(ONBOARDING_PROFILE_FIELDS)('is false with %s missing', (field) => {
    // Each one individually, because a completeness check that passed with the
    // destination account missing is the expensive kind of wrong: a customer
    // would reach a payment step with nowhere to send the money.
    const missing = { ...complete, [field]: null };
    expect(
      isOnboardingComplete({ profile: missing, serviceAreaCount: 1, emailVerified: true }),
    ).toBe(false);
  });

  it('is false for a whitespace-only business name', () => {
    const blank = { ...complete, businessName: '   ' } as ProviderProfile;
    expect(isOnboardingComplete({ profile: blank, serviceAreaCount: 1, emailVerified: true })).toBe(
      false,
    );
  });

  it('does not accept a guessed provider type', () => {
    // §1e reads `providerType` to decide whether Gold review asks for personal
    // ID or a business registration, so null must mean *not yet asked* rather
    // than defaulting to either. A default here would decide which documents a
    // provider is later made to produce.
    expect(ONBOARDING_PROFILE_FIELDS).toContain('providerType');
    const unasked = { ...complete, providerType: null } as ProviderProfile;
    expect(
      isOnboardingComplete({ profile: unasked, serviceAreaCount: 1, emailVerified: true }),
    ).toBe(false);
  });
});

describe.skipIf(databaseUrl === undefined)('§Phase 6a Done-when — over HTTP', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  let male: { id: string };
  let hulhumale: { id: string };

  beforeAll(async () => {
    ctx = await buildTestApp();
    await ensureIslandsSeeded(ctx.prisma);
    male = await islandByName(ctx.prisma, 'K', "Male'");
    hulhumale = await islandByName(ctx.prisma, 'K', "Hulhumale'");
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const summary = (u: RegisteredUser) =>
    ctx.app
      .inject({ method: 'GET', url: '/v1/users/me/profile-summary', headers: u.headers })
      .then((r) => r.json<Envelope<Summary>>().data);

  const own = (u: RegisteredUser) =>
    ctx.app.inject({ method: 'GET', url: '/v1/providers/me', headers: u.headers });

  /** §Phase 6a step 2, as the app sends it: one `PATCH /v1/providers/me`. */
  const accountDetails = (u: RegisteredUser, overrides: Record<string, unknown> = {}) =>
    ctx.app.inject({
      method: 'PATCH',
      url: '/v1/providers/me',
      headers: u.headers,
      payload: {
        businessName: "Hassan's Repairs",
        providerType: 'individual',
        bio: 'AC repair and servicing in Malé for 8 years.',
        bankName: 'Bank of Maldives (BML)',
        bankAccountName: 'Hassan Ibrahim',
        bankAccountNumber: '7730000123456',
        acceptingNewCustomers: true,
        ...overrides,
      },
    });

  /** §Phase 6a step 3, as the app sends it: Phase 7's existing endpoint. */
  const addArea = (u: RegisteredUser, islandId: string) =>
    ctx.app.inject({
      method: 'POST',
      url: '/v1/providers/me/service-areas',
      headers: u.headers,
      payload: { islandId },
    });

  const verifyEmail = (u: RegisteredUser) =>
    ctx.prisma.user.update({
      where: { id: u.userId },
      data: { emailVerifiedAt: new Date() },
    });

  describe('a brand-new user lands on the intro, not the wizard', () => {
    it('reads neither a provider nor an onboarded one', async () => {
      // The Flutter side of this line is
      // `frontend/test/features/onboarding/phase6a_done_when_test.dart`; what
      // the server owes is the signal it routes on.
      const u = await registerUser(ctx.app);
      expect(await summary(u)).toMatchObject({
        isProvider: false,
        providerOnboardingComplete: false,
      });
    });

    it('a provider-variant registration is still not onboarded', async () => {
      // §Phase 3 creates a minimal profile for the provider registration
      // variant, so `isProvider` is true from the first read. It carries a
      // business name and nothing else — no type, no destination account, no
      // service area — and routing on `isProvider` alone would drop this
      // account straight into a dashboard it never set up.
      const p = await registerUser(ctx.app, { role: 'provider' });
      expect(await summary(p)).toMatchObject({
        isProvider: true,
        providerOnboardingComplete: false,
      });
    });
  });

  describe('completing account details persists the payment details', () => {
    it('persists them through the existing Phase 5 endpoint, and nothing new', async () => {
      const u = await registerUser(ctx.app);
      expect((await accountDetails(u)).statusCode).toBe(200);

      const dto = (await own(u)).json<Envelope<OwnProviderDto>>().data;
      expect(dto.providerType).toBe('individual');
      expect(dto.paymentDetails).toMatchObject({
        bankName: 'Bank of Maldives (BML)',
        bankAccountName: 'Hassan Ibrahim',
        bankAccountNumber: '7730000123456',
      });
      expect(dto.bio).toBe('AC repair and servicing in Malé for 8 years.');
      expect(dto.acceptingNewCustomers).toBe(true);
    });

    it('the phone half goes to Phase 3, and is refused here', async () => {
      // §Phase 6a's Done-when says this endpoint persists "phone and payment
      // details". It cannot: there is no phone column on `ProviderProfile`,
      // deliberately, under §Phase 5's single-copy rule. An unknown key is
      // stripped rather than erroring, so the assertion is against the row.
      const u = await registerUser(ctx.app);
      await accountDetails(u, { phone: { dialCode: '+960', number: '7771234' } });

      const changed = await ctx.app.inject({
        method: 'PATCH',
        url: '/v1/users/me/phone',
        headers: u.headers,
        payload: { dialCode: '+960', number: '9991234' },
      });
      expect(changed.statusCode).toBe(200);
      const user = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
      expect(user.phoneE164).toBe('+9609991234');

      // And the number did not land on the provider row along the way.
      const body = (await own(u)).body;
      expect(body).not.toContain('9991234');
      expect(body).not.toContain('7771234');
    });

    it('creates the profile — the write is one of §1a’s creation moments', async () => {
      const u = await registerUser(ctx.app);
      expect((await own(u)).statusCode).toBe(404);
      await accountDetails(u);
      expect((await own(u)).statusCode).toBe(200);
      expect((await summary(u)).isProvider).toBe(true);
    });

    it('refuses a provider type outside the two §Phase 6a offers', async () => {
      const u = await registerUser(ctx.app);
      const res = await accountDetails(u, { providerType: 'cooperative' });
      expect(res.statusCode).toBe(400);
    });

    it('holds the introduction to 160 characters, server-side', async () => {
      // §Phase 6a caps it and invariant 4 puts the cap on the server; the
      // client's counter is the courtesy, not the rule.
      const u = await registerUser(ctx.app);
      const res = await accountDetails(u, { bio: 'x'.repeat(161) });
      expect(res.statusCode).toBe(400);
      expect((await accountDetails(u, { bio: 'x'.repeat(160) })).statusCode).toBe(200);
    });
  });

  describe('the flow is finished by step 3, and not before', () => {
    it('stays unfinished after account details until a service area lands', async () => {
      const u = await registerUser(ctx.app);
      await verifyEmail(u);
      await accountDetails(u);

      // Step 2 done, step 3 not: this is the state §Phase 6a's resume rule
      // describes, and `isProvider` alone cannot see it.
      expect(await summary(u)).toMatchObject({
        isProvider: true,
        providerOnboardingComplete: false,
      });

      expect((await addArea(u, male.id)).statusCode).toBe(200);
      expect(await summary(u)).toMatchObject({
        isProvider: true,
        providerOnboardingComplete: true,
      });
    });

    it('an unverified email leaves it unfinished however complete the rest is', async () => {
      const u = await registerUser(ctx.app);
      await accountDetails(u);
      await addArea(u, male.id);
      await addArea(u, hulhumale.id);
      expect((await summary(u)).providerOnboardingComplete).toBe(false);

      await verifyEmail(u);
      expect((await summary(u)).providerOnboardingComplete).toBe(true);
    });

    it('removing the last service area does not un-onboard a finished provider', async () => {
      // 🔧 **Reversed by the owner's decision, 2026-09-10 (ledger P6A-3).**
      // This asserted that removing the area reopened onboarding, on §1a's
      // reasoning that a stored flag drifts from its fields. §1a derives
      // *visibility*, which is present tense and must change; §Phase 6a's
      // Done-when is past tense — "a provider who **already completed**
      // onboarding never sees it again" — and history does not un-happen. The
      // old behaviour routed a provider trading for months back into a flow
      // whose last step opens a fresh wizard draft.
      const u = await registerUser(ctx.app);
      await verifyEmail(u);
      await accountDetails(u);
      await addArea(u, male.id);
      expect((await summary(u)).providerOnboardingComplete).toBe(true);

      const removed = await ctx.app.inject({
        method: 'DELETE',
        url: `/v1/providers/me/service-areas/${male.id}`,
        headers: u.headers,
      });
      expect(removed.statusCode).toBe(200);
      expect((await summary(u)).providerOnboardingComplete).toBe(true);

      // The present-tense question is still answerable — it is simply a
      // different question, and the one a later phase asks to nudge a provider
      // whose details have gone missing.
      expect((await own(u)).json<Envelope<OwnProviderDto>>().data.serviceAreas).toHaveLength(0);
    });

    it('the two reads agree — one definition, two callers', async () => {
      // §Phase 6's role switcher reads `profile-summary`; the onboarding
      // screen reads `GET /v1/providers/me`. Two clients deriving this
      // separately would be two rules.
      const u = await registerUser(ctx.app);
      await verifyEmail(u);
      await accountDetails(u);
      expect((await own(u)).json<Envelope<OwnProviderDto>>().data.onboardingComplete).toBe(false);
      expect((await summary(u)).providerOnboardingComplete).toBe(false);

      await addArea(u, male.id);
      expect((await own(u)).json<Envelope<OwnProviderDto>>().data.onboardingComplete).toBe(true);
      expect((await summary(u)).providerOnboardingComplete).toBe(true);
    });

    it('stays complete when a bank field is cleared, and stamps only once', async () => {
      // 🔧 **The defect P6A-3 recorded, now fixed (owner, 2026-09-10).**
      // Clearing a payment field is a legal edit — `updateOwnProviderBody`
      // makes all three nullable — and it used to make the flow incomplete
      // again, sending a trading provider back into onboarding.
      const u = await registerUser(ctx.app);
      await verifyEmail(u);
      await accountDetails(u);
      await addArea(u, male.id);
      expect((await summary(u)).providerOnboardingComplete).toBe(true);

      const stampedAt = (
        await ctx.prisma.providerProfile.findFirstOrThrow({
          where: { userId: u.userId },
          select: { onboardingCompletedAt: true },
        })
      ).onboardingCompletedAt;
      expect(stampedAt).not.toBeNull();

      const cleared = await ctx.app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: u.headers,
        payload: { bankName: null },
      });
      expect(cleared.statusCode).toBe(200);
      expect(cleared.json<Envelope<OwnProviderDto>>().data.onboardingComplete).toBe(true);
      expect((await summary(u)).providerOnboardingComplete).toBe(true);

      // Written once and never rewritten: a later completing write must not
      // move the moment.
      await accountDetails(u);
      const after = (
        await ctx.prisma.providerProfile.findFirstOrThrow({
          where: { userId: u.userId },
          select: { onboardingCompletedAt: true },
        })
      ).onboardingCompletedAt;
      expect(after?.getTime()).toBe(stampedAt?.getTime());
    });

    it('stores the moment it happened, and nothing else about it', async () => {
      // 🔧 Was "stores no column that could drift from it". One column now
      // exists deliberately, and the assertion is that it is the *only* one:
      // a record of an event, not a mirror of the five requirements. A second
      // column — `onboarding_step`, `onboarding_status` — would be the copy
      // §1a's discipline actually warns about.
      const columns = await ctx.prisma.$queryRawUnsafe<{ column_name: string }[]>(
        `select column_name from information_schema.columns where table_name = 'provider_profile'`,
      );
      const names = columns.map((c) => c.column_name);
      expect(names).toContain('provider_type');
      expect(names.filter((n) => /onboard/i.test(n))).toEqual(['onboarding_completed_at']);
    });
  });

  describe('no new endpoint, and no new way to read a phone number', () => {
    it('§Phase 6a added no parallel provider-update route', async () => {
      const u = await registerUser(ctx.app);
      for (const url of [
        '/v1/providers/me/onboarding',
        '/v1/providers/me/onboarding/complete',
        '/v1/providers/me/account-details',
      ]) {
        const res = await ctx.app.inject({ method: 'POST', url, headers: u.headers });
        expect(res.statusCode).toBe(404);
      }
    });

    it('carries no phone number in either read', async () => {
      // backend/CLAUDE.md: any endpoint near a phone number is tested for its
      // ABSENCE. `providerType` was added to both shapes in this phase, so
      // both are re-checked.
      const u = await registerUser(ctx.app);
      await accountDetails(u);
      const bodies = [(await own(u)).body, JSON.stringify(await summary(u))];
      for (const body of bodies) {
        expect(body).not.toContain(u.phone);
        expect(body).not.toContain(`+960${u.phone}`);
      }
    });
  });
});
