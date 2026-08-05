---
name: backend-domain-module
description: Use when creating a new backend domain module or adding endpoints to an existing one. Triggers on work under backend/src/modules/, or mentions of adding an entity, route, service, or repository.
---
# New Backend Domain Module Checklist

Every module ships with: routes, service, repository, Zod schema, types, and tests. Business logic in the service layer only.

Before considering the module done, confirm each:
- Authorization on EVERY endpoint including reads, with a comment naming who is permitted.
- Ownership checked on every client-supplied ID.
- Zod validation on body, query and params.
- Idempotency middleware on money-adjacent and creation POSTs.
- Sensitive fields excluded structurally in DTO mapping — payment details, identity documents, phone numbers. Not by per-handler memory.
- Soft-delete respected in every read query.
- Money as integer laari throughout.
- Standard response envelope, with stable error codes.
- Any state transition that should happen at a time is driven by a scheduled job, not check-on-read.
- A test asserting each business rule at its boundary.
