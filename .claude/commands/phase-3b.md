---
description: Build Phase 3b — Forgot Password Flow
---

Build **Phase 3b — Forgot Password Flow** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 3b** — the full specification for this phase, including its **Done when** criteria.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 3b describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.

## The artboard

🔧 **Superseded 2026-09-08. This section said "This screen has no mockup" and
asked for a proposal.** That stopped being true when Session 8 designed it:
§Phase 3b names **`Forgot Password.dc.html`**, which covers all three steps —
request, check your inbox, set a new password. The plan's own propose-first
marker was retired on 2026-09-06; this command kept asking for a proposal for
two days after, which is a request to invent a design that already exists and
would then compete with the committed one.

**Build against the artboard**, in `mockups/design-composer/`. Serve the
directory and read the real numbers out of it rather than estimating from a
screenshot:

```bash
cd mockups/design-composer && python3 -m http.server 8791 --bind 127.0.0.1
```

`getBoundingClientRect()` and `getComputedStyle()` at a 412-wide viewport give
the frame the app is designed to, which is also the frame
`test/helpers/pump.dart` pumps — so prototype numbers and widget-test numbers
are directly comparable.

🔧 **Where the artboard and the plan disagree, the plan wins and the
divergence is flagged, not implemented.** One is already known here: the
artboard sends a **reset link** where §Phase 3b specifies a **six-digit
code**. Build the code; `docs/design/sessions/round-54-reset-code-not-link.md`
is the correction prompt for the design project.

**Assert geometry, not only copy.** Sign In matched the prototype on every
string while carrying seven layout and colour defects — a full-bleed banner
painting 293 dp of 411, four social buttons as bare circles instead of named
pills, a field 79 dp tall where the design says 54. See
`frontend/test/features/auth/sign_in_layout_test.dart` and its siblings for
the pattern, and measure the *painted* box: `find.byType(Container)` does not
match an `AnimatedContainer`, and `AppTextField` wraps the label and helper
text as well as the input.
