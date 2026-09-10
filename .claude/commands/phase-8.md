---
description: Build Phase 8 — Service Listings: Backend Domain
---

Build **Phase 8 — Service Listings: Backend Domain** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 8** — the full specification for this phase, including its **Done when** criteria.
3. §1c · §1d · §1b entitlements — this phase depends on it.
4. **The entitlement cap is a seam in this phase.** §Phase 8's publish bullet enforces the cap; §Phase 8a owns `getProviderEntitlements`, the single source of tier truth, and it does not exist yet. Read the 🔧 note under that bullet: define the narrow reader you need, return §1b's free-tier cap of **1 active listing**, and build none of 8a's subscription, trial or pause machinery.
5. **Two open ledger rows in `docs/deferred-verification.md` are yours to close or advance.** **P5-1** waits on a real `Listing` table so §1a's derived visibility can be re-run against published rows through `findVisibleProviders` — the same helper, not a second copy of the query. **P7-3** turns on this phase giving a listing its own service areas keyed on `islandId`: the account-level `ProviderServiceArea` from §Phase 7 is the wizard's *default* and nothing more, the two must never be conflated, and nothing may match on a name (§0.0 item 12).

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 8 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
