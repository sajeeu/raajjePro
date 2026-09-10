---
description: Build Phase 8a — Subscription & Trial
---

Build **Phase 8a — Subscription & Trial** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 8a** — the full specification for this phase, including its **Done when** criteria.
3. §1b Monetization — this phase depends on it.

4. **You fill §Phase 8's cap seam, and you open one of your own — read the 🔧 notes in §Phase 8a first.** `backend/src/modules/listings/entitlements.ts` holds `ProviderEntitlementReader` and its `FREE_TIER_ONLY` default; replace the default with `getProviderEntitlements` and change no caller. Going the other way, there is no `Booking` until §Phase 17.1, so the confirmed-booking trial trigger and the downgrade listing-protection both take an injected source — build the rules here, assert them with a fake, and do **not** create a `Booking` table.
5. **Six questions are answered in the plan — read the 🔧 notes in §Phase 8a and §1b before the schema lands.** The 7-day job **prompts and does not start** a trial, so two triggers start one and one nudges toward the second · the `acceptingNewCustomers` toggle **is** the pause, reached by one function through two doors, and its copy must say that turning it off shifts the billing anchor · the introductory-rate conversion is a **fifth** scheduled job · RaajjePro's bank details are typed config, required in production · premium's active-listing cap is **unlimited** (no section names a number; render it as `null` meaning *no limit*, never *unknown*) · and **do not build the appeal action** — ledger row **P8A-1** records why and names the mechanisms a spec round should choose between.
6. **`scripts/verify.sh` was fully green when you started** — backend typecheck, lint and tests, frontend analyze and tests, all 61 design components, navigation and locked rules. That is your bar; anything red is yours.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 8a describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
