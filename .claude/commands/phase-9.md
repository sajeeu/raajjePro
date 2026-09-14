---
description: Build Phase 9 — Create/Edit Service Wizard: Frontend
---

Build **Phase 9 — Create/Edit Service Wizard: Frontend** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 9** — the full specification for this phase, including its **Done when** criteria.
3. §1 the wizard divergences · §1c — this phase depends on it.
4. **Four things Phase 8 and 8a left you, all verified present.** The publish refusal is **two codes, not one** — `LISTING_INCOMPLETE`, whose details carry a per-row `step` (`{ field: 'categoryId', step: 'details', message: 'Category' }`) so every missing field renders its own Fix deep link, and `LISTING_CAP_REACHED`, which is the upgrade prompt. §Phase 9's "an upgrade prompt, not a generic error" is exactly this distinction, so never collapse them. The cap behind the second is **live** since §Phase 8a filled the entitlement seam, so the prompt now fires on a real premium/free difference rather than a constant. And `Category.suggestedTags` is seeded for all twelve categories and exposed on the category DTO, but the Flutter `ServiceCategory` in `lib/core/domain/category.dart` **does not read it yet** — add it beside `occasionPresets`, which is the same shape.

5. **Ledger row P6A-2 is yours to close** (`docs/deferred-verification.md`). §Phase 6a hands off to `/services/new` with nothing in arguments, and nobody has been able to assert what opens there because there was no wizard. Arrive from onboarding's confirmation sheet and assert step 1 opens a genuinely fresh draft — not the provider's most recent one — while step 2 pre-fills from the account-level `ProviderServiceArea` §Phase 7 built. Keep §P7-3's distinction: those are the *default*, and a listing's own areas are what discovery reads.

6. **Two copy corrections already landed in the prototype; do not re-litigate them.** Step 5's slot card reads "Customers pick from the times you publish, then you accept" (Round 56 — a slot booking still needs the provider to accept, §0.0 item 13). The `acceptingNewCustomers` toggle is **not yours**: §Phase 9 drops it from step 5 entirely, and its billing-consequence copy belongs to §Phase 10 and 10a (ledger row **P8A-4**).

7. **`scripts/verify.sh` was fully green when you started**, twice consecutively, against a test database that is now emptied once per run (`backend/test/global-setup.ts`). That is your bar; anything red is yours.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 9 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
