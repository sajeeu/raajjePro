---
name: verification-tiers
description: Use when working on identity verification, the verified badge, emergency eligibility, or the admin verification queue. Triggers on mentions of verification, verified, badge, bronze, silver, gold, or KYC.
---
# Verification Tiers

`verificationTier` is `none` / `bronze` / `silver` / `gold`. It is what the badge renders and what other systems gate on. It is NOT a boolean, and older documentation asserting `verificationStatus === 'verified'` is obsolete. `verificationStatus` still exists but means only the review state of a pending submission.

| Tier | Requirements | Public copy |
|---|---|---|
| Bronze | Government ID matching the account name. No trade evidence. | "ID checked by RaajjePro" |
| Silver | Bronze + photos of completed work + EITHER a customer reference RaajjePro contacts OR 5 completed on-platform bookings with no unresolved dispute | "ID checked, work verified" |
| Gold | Silver + business registration OR a recognised trade certificate | "ID checked, registered trade" |

- PHOTOS ARE NEVER SUFFICIENT ALONE AT ANY TIER — they are trivially reusable.
- THE 5-CLEAN-BOOKINGS ROUTE TO SILVER GRANTS AUTOMATICALLY, with no admin review. Implement as a triggered check, not a queue item. Only ID checks, customer references and Gold paperwork reach a human — that is what makes three tiers affordable against a single reviewer.
- EMERGENCY CAPABILITY REQUIRES SILVER OR ABOVE. Enforced on listing publish, on update, AND re-checked at booking creation.
- The badge NEVER depends on subscription state. A lapsed-but-verified provider keeps their tier.
- Tiers do NOT expire and there is no periodic recheck. A `fraud_confirmed` outcome or an accumulated dispute pattern triggers a review that may demote or revoke.
- Never render a bare "Verified" — always the tier-specific copy above.
- Documents: separate private bucket, short-lived signed URLs, every access logged, purged 90 days after decision and immediately on account deletion.
