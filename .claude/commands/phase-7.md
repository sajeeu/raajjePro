---
description: Build Phase 7 — Service Areas & Location Module
---

Build **Phase 7 — Service Areas & Location Module** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 7** — the full specification for this phase, including its **Done when** criteria.
3. **§0.0 item 12 — the island list, and the rules that come with it.** The seed this phase asks for already exists at `docs/data/inhabited-islands.json`: **192 inhabited islands across 20 atolls**, extracted from the ministry register. Do not re-derive it, do not shorten it, and read item 12 before writing the search — island names are not unique, the ambiguous set is computed at seed time rather than hardcoded, search must never auto-select, and no island total appears in UI copy. `docs/data/README.md` carries the data notes.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 7 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.
