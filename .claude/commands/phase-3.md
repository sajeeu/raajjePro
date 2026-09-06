---
description: Build Phase 3 — Identity & Authentication
---

Build **Phase 3 — Identity & Authentication** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 3** — the full specification for this phase, including its **Done when** criteria.
3. §1e Identity Verification — this phase depends on it.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 3 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.

## Email in this phase — read before you start

**No AWS account exists and none is needed.** The owner deferred SES to
deployment on 2026-09-06; the plan records it as **§0.0 item 17** and
`docs/decisions/11-email-deferred-to-deployment.md` carries the detail. The
§Phase 3 bullet that used to say SES must be out of its sandbox first is
struck through there — the constraint returns at deployment, not now.

So:

- Build against **`EMAIL_TRANSPORT=file`** (Phase 2 ships it). Every message
  is written as JSON into `backend/.mail/`. A test reads the OTP out of the
  written file exactly as it would read a mailbox, so the full
  register → verify → login cycle and both OTP rate limits are genuinely
  testable here.
- Send through the **`EmailSender` interface**, never by calling SES from a
  domain module (root `CLAUDE.md` invariant 10). The suppression list is
  already checked before the transport is contacted — do not re-implement it.
- **Bounce and complaint handling already exists** (Phase 2). Wire to it.
  If anything here reads as though you are building it for the first time,
  you are not.

**How to report a Done-when line that needs a real mailbox.** Record it as
met **against the file transport**, in those words — never as met outright,
and never as "will be checked later". Then add a row to
`docs/deferred-verification.md` saying what only a real send can prove and how
it will be proved. That ledger is general — it takes every deferred check in
the project, not only email — and it is what gets worked through at the end.
A line that never reaches it never gets checked.
