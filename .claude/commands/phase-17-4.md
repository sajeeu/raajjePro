---
description: Build Phase 17.4 — Recurring series, reschedule & the callback guarantee
---

Build **slice 17.4** of RaajjePro's Phase 17 (Bookings Module) — *Recurring series, reschedule & the callback guarantee*.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule.
2. **§Phase 17**, specifically the 17.4 subsection, plus its **Done when** list.
3. **§1c** in full — booking modes, the status machine, the emergency rules and the contact exception.
4. **§1h Repeat use** — the locked agreement, callback guarantee and provider replacement.
5. 🔧 **This slice also owns Saved Preferences** (owner's decision, 2026-09-10). §Phase 3 collected it and deferred it for `Island`; §Phase 7 seeded `Island` and correctly declined it, since no section gave it an entity shape. §1h is what asks for it — saved addresses, preferred time windows and standing instructions, "carried forward by **Book Again**", which is this slice. The design exists: `mockups/design-composer/Saved Preferences.dc.html`. Profile's row currently reaches an `UnbuiltScreen` naming Phase 17.4; wiring it is part of finishing here.

## How to work

- Build **only this slice**. Phase 17 is the largest phase in the plan and is deliberately split; do not pull work forward from another slice.
- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`.**
- Every timing value is per-category from the Phase 4 seed. Never hardcode 30 minutes, 24 hours, 72 hours, or a verification tier.
- Finish against §Phase 17's **Done when** list.
