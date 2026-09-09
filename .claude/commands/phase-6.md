---
description: Build Phase 6 — Customer Profile Module
---

Build **Phase 6 — Customer Profile Module** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 6** — the full specification for this phase, including its **Done when** criteria.
3. 🔧 **The role switcher routes on `isProvider` from the auth surface.** §Phase 6's Done-when turns on telling a first switch from a later one — onboarding versus the dashboard — and `isProvider` is the signal that answers it without a request, reliable because a read no longer creates the profile (`docs/decisions/17-phase-5-provider-profiles.md`, decision 11). A 404 from `GET /v1/providers/me` is now legible too, answering `PROVIDER_PROFILE_NOT_FOUND` where a bad path answers `NOT_FOUND`, but it is the fallback rather than the route.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 6 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
