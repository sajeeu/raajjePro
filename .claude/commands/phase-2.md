---
description: Build Phase 2 — Backend Core Infrastructure
---

Build **Phase 2 — Backend Core Infrastructure** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 2** — the full specification for this phase, including its **Done when** criteria.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 2 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.

## Also in this phase — SES bounce and complaint handling

Not in §Phase 2's own list. It is the **Phase 0–2 prerequisite** from §0.0 item 8, and Phase 2 is where it becomes buildable — it needs Prisma, an HTTP route for the SNS event destination, and the `EmailSender` interface.

Build all three parts: the SNS event destination, the stored per-message delivery/bounce result, and the suppression list **honoured before send**. Then request SES production access — the attestation required to leave the sandbox is that this handling already exists, so it must be done before Phase 3 starts, not during it.

You will not be able to test it end to end without an AWS account and a verified domain, and that is outstanding on the owner's side. Build against the interface, unit-test the suppression check, and say plainly what is unverified.
