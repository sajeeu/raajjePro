---
description: Build Phase 6a — Become a Provider: Onboarding Flow
---

Build **Phase 6a — Become a Provider: Onboarding Flow** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 6a** — the full specification for this phase, including its **Done when** criteria.
3. §1a Provider Lifecycle · §1e — this phase depends on it.
3a. 🔧 **The design exists: `mockups/design-composer/Become a Provider.dc.html`.** Build against the artboard, not a fresh proposal — §Phase 6a said "No mockup exists" until 2026-09-10 and was wrong. Its third step collects default service areas, which needs Phase 7's `Island` and its reusable island multi-select, so that step cannot be finished before Phase 7.
4. **`docs/decisions/17-phase-5-provider-profiles.md` — two things Phase 5 settled that this phase inherits.**
   - 🔧 **The phone does not go through `PATCH /v1/providers/me`.** §Phase 6a's Done-when says account details persist "**phone** and payment details onto the Provider Profile via the existing Phase 5 update endpoint". There is no phone field on `ProviderProfile` and none on `updateOwnProviderBody` — deliberately, under §Phase 5's single-copy rule. **The phone half routes to Phase 3's `PATCH /v1/users/me/phone`; only the payment details go through `PATCH /v1/providers/me`.** Recorded as a divergence rather than a plan amendment, so build to this and do not add a phone field.
   - 🔧 **Route on `isProvider` from the auth surface.** It costs no request and is reliable because a read no longer creates the profile. A 404 from `GET /v1/providers/me` is now legible if you reach one anyway — it answers `PROVIDER_PROFILE_NOT_FOUND` where a bad path answers `NOT_FOUND` — but that is for handling a 404, not a reason to probe for one.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 6a describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
