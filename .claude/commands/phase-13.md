---
description: Build Phase 13 — Provider Public Profile
---

Build **Phase 13 — Provider Public Profile** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 13** — the full specification for this phase, including its **Done when** criteria.
3. §1e · §1f — this phase depends on it.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 13 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.

## The artboard

🔧 **Superseded 2026-09-08. This section said "This screen has no mockup" and
asked for a proposal.** Session 3 designed it and reviewed it across two
rounds: §Phase 13 names **`Provider Profile.dc.html`**. The plan's
propose-first marker was retired on 2026-09-06 and this command was not, so
it was still asking for a design that already exists — one that would then
compete with the committed artboard.

**Build against the artboard**, in `mockups/design-composer/`. Serve the
directory and read its real numbers rather than estimating from a screenshot:

```bash
cd mockups/design-composer && python3 -m http.server 8791 --bind 127.0.0.1
```

`getBoundingClientRect()` and `getComputedStyle()` at a 412-wide viewport give
the frame the app is designed to, which is the frame
`frontend/test/helpers/pump.dart` pumps — so prototype numbers and
widget-test numbers compare directly.

🔧 **Where the artboard and the plan disagree, the plan wins and the
divergence is flagged, not implemented.** This screen is where that bites
hardest: the badge renders `verificationTier`, conduct is numbers only, and a
warranty or insurance claim is attributed to the provider and never shown as
verified. Verification is three tiers, so an artboard drawing a bare
"Verified Provider" badge is wrong — NEVER render one; the badge carries its
tier's own words. The same goes for an editorial conduct label or a check
mark beside a phone number, against §1f and §1i. Flag any of them rather
than building them.

**Assert geometry, not only copy.** Sign In matched its prototype on every
string while carrying seven layout and colour defects. See
`frontend/test/features/auth/sign_in_layout_test.dart` and its siblings, and
measure the *painted* box: `find.byType(Container)` does not match an
`AnimatedContainer`, and a field wrapper may include its label and helper
text as well as the input.
