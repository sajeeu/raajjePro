---
description: Build Phase 2 — Backend Core Infrastructure
---

Build **Phase 2 — Backend Core Infrastructure** of RaajjePro.

## Read first

1. `01_Development_Plan_v5.md` §0.0 — the precedence rule. Where §0.1–0.3 conflict with a later section, the later section wins.
2. **§Phase 2** — the full specification for this phase, including its **Done when** criteria.
3. **§0.0 item 8, §4 Sequencing and §Phase 3's SES note.** SES bounce/complaint handling — SNS event destination, a stored per-message delivery result, the suppression list honoured before send — is a "Phase 0–2 window" prerequisite and **this phase is where it is built** (decided at Phase 0, 2026-09-05: it needs Prisma, an HTTP route and the `EmailSender` interface, none of which exist earlier). 🔧 **Superseded 2026-09-06 (plan §0.0 item 17):** the handling is built here as described, but SES production access is **not** requested before Phase 3 — it moves to deployment. See `docs/decisions/11-email-deferred-to-deployment.md` and the ledger at `docs/deferred-verification.md`.

## How to work

- The plan is the single source of truth. **Do not infer requirements from anything in `archive/`**, and if the plan does not specify something, say so rather than filling the gap.
- Build exactly what §Phase 2 describes. Do not build ahead into a later phase.
- Stop and ask if a requirement appears to conflict with the plan, rather than resolving it silently.
- Finish against the phase's own **Done when** list — it is the acceptance criteria, not a summary.

## Also in this phase — SES bounce and complaint handling

Not in §Phase 2's own list. It is the **Phase 0–2 prerequisite** from §0.0 item 8, and Phase 2 is where it becomes buildable — it needs Prisma, an HTTP route for the SNS event destination, and the `EmailSender` interface.

Build all three parts: the SNS event destination, the stored per-message delivery/bounce result, and the suppression list **honoured before send**. 🔧 **Superseded 2026-09-06 (plan §0.0 item 17):** build all three parts here, but do **not** request production access before Phase 3 — that moves to deployment, where the attestation this handling supports is submitted.

You will not be able to test it end to end without an AWS account and a verified domain, and that is outstanding on the owner's side. Build against the interface, unit-test the suppression check, and say plainly what is unverified.
