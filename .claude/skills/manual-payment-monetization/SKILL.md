---
name: manual-payment-monetization
description: Use when working on subscriptions, trials, entitlements, payment submissions, or billing UI. Triggers on mentions of subscription, trial, entitlement, PaymentSubmission, billing, or invoice.
---
# Manual Payment & Monetization Pattern

- RaajjePro collects ONLY provider subscription fees, via manual bank transfer + admin confirmation. No payment gateway. Never scaffold one.
- `PaymentSubmission` is one generic entity with an open `purpose` enum — `'subscription'` today.
- NOTHING IS GRANTED ON SUBMISSION. A `pending` submission produces entitlements identical to no payment at all. `getProviderEntitlements` reads LIVE database state on every call and never caches.
- PRICE IS PER-PROVIDER: read `providerProfile.subscriptionPriceLaari`. Never a global constant.
- Billing is on a 30-day ANCHOR, never a calendar month. Pausing SHIFTS the anchor by the paused duration. Never imply month boundaries in data or copy.
- Pause is capped at 10 cumulative days, keyed off the provider-level `acceptingNewCustomers` toggle, with ONE shared implementation for `trialing` and `active`.
- TWO triggers START a trial and one NUDGES: the transition INTO `confirmed` (hooked on the state transition, never one endpoint) and an explicit "Try Premium" both call one no-op-if-already-run `startTrial`. The 7-day-after-first-publish job PROMPTS ONLY — it never starts one (2026-09-10), because a trial is one per account and firing it when no booking has landed spends it when premium is worth least. 30 days, not 60.
- PREMIUM'S LISTING CAP IS UNLIMITED — §1b names no number, so there is none. `Infinity` internally, `null` in the DTO meaning *no limit*, never *unknown*. Free is 1.
- `expired` IS THE GRACE PERIOD AND STILL CARRIES PREMIUM — §1b's 7 days "with nothing changing". `free` is the downgrade.
- THE `acceptingNewCustomers` TOGGLE IS THE PAUSE: one function, two doors (the toggle and the billing endpoints). At the 10-day cap the clock resumes and the TOGGLE IS LEFT ALONE.
- TWO PRICE POINTS COEXIST: MVR 75 = 7500 laari for the first 100 providers, MVR 150 = 15000 after, honoured 12 months from the anchor then converted with 30 days' notice. The cohort is decided by how many providers already have a price WRITTEN.
- THERE IS NO APPEAL ACTION and none may be invented — no section says what an appeal changes (ledger row P8A-1). A rejection has no cooldown, so a fresh submission IS the resubmit.
- DOWNGRADE IS NON-DESTRUCTIVE. Listings over cap are hidden, never deleted. The badge is unaffected. A listing with a confirmed future booking is PROTECTED and stays visible regardless of cap. Among unprotected listings, the HIGHEST-PERFORMING survives (bookings over 90 days, then views, then recency) — not the most recently updated, which was gameable.
- Admin confirmation and reversal are explicit audit-logged endpoints, never database edits.
