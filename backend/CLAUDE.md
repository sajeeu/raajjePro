# Backend — RaajjePro

Applies to everything under `backend/`. The root `CLAUDE.md` and `01_Development_Plan_v5.md` still govern; this file adds the conventions specific to this app.

- Domain-module structure: `backend/src/modules/<domain>/` containing routes, service, repository, schema (Zod), and types. Business logic lives in the service layer, never in a route handler.
- Prisma is the only database access path. No raw SQL except where a feature genuinely requires it — the gist exclusion constraint and its supporting migration are the expected exception.
- Every mutating endpoint has an explicit authorization check as its first act, stated in a comment naming who is allowed. Authorization on READS too — an unauthorized read of a booking or a payment detail is a real leak.
- Zod schemas validate every request body, query and param. Never trust a client-supplied ID without checking ownership.
- Money is integer laari end to end — in the database, in the DTO, in the JSON. Never convert to float anywhere in the path.
- Idempotency middleware on every money-adjacent and creation POST, keyed on `(userId, operation, clientKey)`, returning the ORIGINAL result on repeat.
- Scheduled work runs on the job runner from Phase 0, never as check-on-read. If a transition should happen at a time, a job makes it happen at that time.
- Sensitive fields (payment details, identity documents, phone numbers) are excluded structurally in the DTO mapping layer, not by remembering to omit them per handler.
- Soft-delete only. Every query that returns user-visible data filters on the visibility/status field.

---

# API Contract

- Every response — success and failure — uses the standard envelope. Errors carry a stable machine-readable `code`, a human-readable `message`, and optional `details`. Never return a bare string; the frontend routes on codes.
- Error codes are stable identifiers, not prose. Renaming one is a breaking change.
- ADDITIVE-ONLY EVOLUTION WITHIN /v1. Never remove a field, never repurpose a field's meaning, never tighten a type. Mobile clients cannot be force-updated, so a breaking change strands every installed app version. If a change cannot be made additively, stop and flag it.
- Pagination is server-side and mandatory on any endpoint that can return an unbounded set.
- Rate-limit tiers are declared per endpoint, not applied globally by default. Auth, OTP, payment, emergency-booking and MESSAGING endpoints carry stricter tiers.
- No endpoint outside `POST /v1/bookings/:id/reveal-contact` may include a phone number in any response shape, at any nesting depth, under any status. When adding a field to a shared DTO, check what else consumes it.

---

# Testing

- Every business rule gets a test asserting the rule, not the implementation. A test that would pass against a wrong implementation is not a test.
- Concurrency is tested explicitly wherever the plan names it: simultaneous slot booking, cross-listing overlap on one provider, 1,000 concurrent attempts asserting zero double-books, simultaneous admin confirmation, repeated idempotent POSTs.
- State machines are tested at their boundaries — the transition that should be rejected matters more than the one that should succeed.
- Scheduled jobs are tested by advancing time, not by waiting.
- Authorization tests cover reads as well as writes, and cover the wrong-user case, not just the unauthenticated one.
- Any endpoint touching a phone number is tested for its ABSENCE in the response, not only for the presence of what it should return.
- Registration is tested against both a duplicate email and a duplicate phone, asserting each is blocked with a message naming the specific field.
