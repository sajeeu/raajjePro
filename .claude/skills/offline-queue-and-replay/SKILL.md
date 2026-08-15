---
name: offline-queue-and-replay
description: Use when implementing any action that must survive a dropped connection — the service wizard, the provider accept prompt, or chat sends. Triggers on mentions of offline, queue, replay, retry, or connectivity.
---
# Offline Queue and Replay

The plan names weak atoll connectivity as a platform-wide risk. Three surfaces are offline-resilient and MUST share one implementation, not three:

1. The Create/Edit Service Wizard's per-step autosave (Phase 9) — the highest-value conversion flow.
2. The provider accept prompt (Phase 17.1) — a lost tap costs the provider the job, and leaves them unsure whether it registered.
3. Chat message sends (Phase 18) — chat is the sole coordination channel, so a silently-failed message is a coordination failure, not a cosmetic one.

The pattern:
- Record the action locally BEFORE the network call.
- Show a visible pending state on the affected item — not a global spinner.
- Replay on reconnect, in order, idempotently. Server-side idempotency keys make a double-replay safe.
- On permanent failure, surface it where the user can act, and never discard their input.
- Never block the UI waiting for a network round trip on these three surfaces.

Build it once in `lib/core/`. If you find yourself writing a second implementation, stop.
