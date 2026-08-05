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
- Trial fires on whichever of three triggers comes first: transition INTO `confirmed` (hooked on the state transition, not one endpoint), an explicit "Try Premium", or a proactive prompt 7 days after first publish. All call one no-op-if-already-run function.
- DOWNGRADE IS NON-DESTRUCTIVE. Listings over cap are hidden, never deleted. The badge is unaffected. A listing with a confirmed future booking is PROTECTED and stays visible regardless of cap. Among unprotected listings, the HIGHEST-PERFORMING survives (bookings over 90 days, then views, then recency) — not the most recently updated, which was gameable.
- Admin confirmation and reversal are explicit audit-logged endpoints, never database edits.
