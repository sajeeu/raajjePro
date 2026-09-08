---
description: Build Phase 3c — Push Notification Infrastructure
---

Build **Phase 3c — Push Notification Infrastructure** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 3c** — the full specification for this phase, including its **Done when** criteria.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 3c describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.

## The push vendor — decided 2026-09-08, read before you start

🔧 **No Firebase project and no Apple developer account exist, and none is
needed to build this phase.** Build `PushSender` behind a transport that is a
no-op without credentials — the same posture as Phase 2's `EmailSender`
(`EMAIL_TRANSPORT=file`) and Phase 3's `CrashReporter` (inert without
`SENTRY_DSN`). That is now one rule across all three external vendors, not
three separate judgements.

So:

- **Build the whole thing against a fake.** The interface, device-token
  registration, refresh and multi-device handling, the OS-permission-denied
  state on the user, and every rung of the fallback chain are all testable
  without a real FCM or APNs credential. Assert what the sender was *asked*
  to do.
- **The fallback chain is where the real work is**, and §Phase 3c is precise
  about it: email immediately when push is already known denied, email after
  30 minutes when delivery is unconfirmed, and — for emergency bookings —
  **push and email in parallel with no ladder at all**, because a 30-minute
  window leaves no room for one. An earlier revision waited for the
  acceptance window, which is 24 hours, so a fallback could arrive at hour 23
  of a booking that had already died. Do not reintroduce that.
- **Bounce handling and the suppression list already exist** (Phase 2). Wire
  to them. If anything here reads as though you are building them for the
  first time, you are not.

**What this defers, and how to record it.** A real push arriving on a real
device is the one thing a fake cannot prove, and it is §Phase 3c's own first
Done-when clause. Record that clause as met **against the fake**, in those
words — never as met outright and never as "checked later" — and add a row to
`docs/deferred-verification.md` naming what only a real device closes. The
FCM half and the APNs half are separate rows: a Firebase project is free and
quick, an Apple developer account has a fee and a lead time, so they will
almost certainly close at different moments. See rows L1–L10 for the shape,
and `CLAUDE.md` invariant 6 for the rule.

**Do not procure either vendor as part of this phase.** If the build appears
to require an account, stop and say so rather than asking the owner to create
one mid-phase.
