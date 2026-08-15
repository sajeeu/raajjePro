---
description: Build Phase 17.3 — Emergency dispatch, offer collection & the reveal endpoint
---

Build **slice 17.3** of RaajjePro's Phase 17 (Bookings Module) — *Emergency dispatch, offer collection & the reveal endpoint*.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule.
2. **§Phase 17**, specifically the 17.3 subsection, plus its **Done when** list.
3. **§1c** in full — booking modes, the status machine, the emergency rules and the contact exception.
4. **§1h Repeat use** — the locked agreement, callback guarantee and provider replacement.

## How to work

- Build **only this slice**. Phase 17 is the largest phase in the plan and is deliberately split; do not pull work forward from another slice.
- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`.**
- Every timing value is per-category from the Phase 4 seed. Never hardcode 30 minutes, 24 hours, 72 hours, or a verification tier.
- Finish against §Phase 17's **Done when** list.
