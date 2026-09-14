---
description: Build Phase 9a — Availability, Time Slots & Reservations
---

Build **Phase 9a — Availability, Time Slots & Reservations** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 9a** — the full specification for this phase, including its **Done when** criteria.
3. §1c Slot-based and Request-based flows — this phase depends on it.
4. **The sweep you are about to write has a known failure mode in this repository — read it before designing the job.** §Phase 9a's generation is explicitly "incremental and per-provider, not a global nightly sweep", with "a stated wall-clock budget and a §Phase 21 alert on overrun". That warning has already come true once, in §Phase 8a: `runLifecycle` selected every subscription row and then did a `findUnique` per candidate, and it crossed five seconds on a laptop at a thousand rows — found only because a test began timing out four days after it was written. It was fixed on 2026-09-14 by moving the job's own conditions into the WHERE and reading the related row lazily (`subscriptions/repository.ts`, `findLifecycleCandidates`). Slot generation is the bigger version of the same shape: 60 days rolling, per provider, per listing. Write it narrow from the start and state its budget.

5. **Two inputs are thinner than they look.** §Phase 9's step 5 collects only `workingDays` / `workingHoursFrom` / `workingHoursTo` — a simple window, which its own helper says and §1's mockup table warns "will mislead if treated as the pattern". The real availability rules are yours. And `Category.minimumLeadTimeMinutes` is seeded and admin-editable (§Phase 10b), so read it per category and never hardcode a lead time.

6. **Ledger rows you touch.** **P8-2** (§Phase 8's cascade rules against a real reserved slot) becomes assertable the moment `TimeSlot` exists — the rules it must obey are written out in `docs/decisions/21-phase-8-service-listings.md`. **P8A-2**'s booking source stays §Phase 17.1's, not yours: a reservation is not a booking.

7. **The frontend half inherits three rules landed on 2026-09-14** — `frontend/CLAUDE.md` has them with the reasoning. No arithmetic on a spacing token (the scale names every 2 dp step from 8 to 26, and a test ratchets the count). Content enters with `FadeUp` rather than appearing, staggered inside a list — and a geometry assertion must `pumpAndSettle` first. Consequential taps carry a haptic: `selection` when a choice changes, `commit` when something lands that cannot be quietly undone, `refused` when the app says no. A slot picker is the clearest `selection` surface in the app so far.

8. **`scripts/verify.sh` was green when you started**, and CI has been green since the boot step was fixed. That is your bar.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 9a describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
