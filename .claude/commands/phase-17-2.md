---
description: Build Phase 17.2 — Request-with-quote path
---

Build **slice 17.2** of RaajjePro's Phase 17 (Bookings Module) — *Request-with-quote path*.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule.
2. **§Phase 17**, specifically the 17.2 subsection, and **§Phase 17's `17.2 — Done when` list, which is yours. The other three slices have their own and you finish against none of them.**
3. **§1c** in full — booking modes, the status machine, the emergency rules and the contact exception.
4. **§1h Repeat use** — the locked agreement, callback guarantee and provider replacement.

## How to work

- Build **only this slice**. Phase 17 is the largest phase in the plan and is deliberately split; do not pull work forward from another slice.
- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`.**
- Every timing value is per-category from the Phase 4 seed. Never hardcode 30 minutes, 24 hours, 72 hours, or a verification tier.
- Finish against **`17.2 — Done when`**, plus the standing rule above it that no endpoint in the module returns a phone number — that one applies to every slice, over the endpoints this one adds.
- The phase-level **Done when** is the sum of all four slices. It is not a target for this one.
