# RaajjePro

Planning and specification for RaajjePro, a local services marketplace for the Maldives.
Flutter app (customer + provider) · TypeScript/Fastify/Prisma/PostgreSQL backend · separate React admin web app.

Phases 0 and 1 are built: both apps boot, lint is clean, the job runner fires, and the Flutter design system — tokens, shared widgets, motion, a component gallery — is in place. Everything from Phase 2 onward is still specification. See **Running locally** below.

## The source of truth

| File | What it is |
|---|---|
| `01_Development_Plan_v5.md` | **The authoritative spec**, at revision 5.19. Standalone. Read §0.0 first — it is a precedence rule. |

Everything else in this repo derives from that file, and nothing else restates it. Seventeen review rounds established why: every copy of a decision eventually drifts from the original, and it happened five times before the copies were removed.

## Claude Code configuration

| Path | What it does |
|---|---|
| `CLAUDE.md` | Project invariants and scope discipline. Always in context. |
| `backend/CLAUDE.md` | Backend conventions, API contract, testing. Loads when working under `backend/`. |
| `frontend/CLAUDE.md` | Flutter conventions, design system, testing. Loads when working under `frontend/`. |
| `.claude/commands/` | One slash command per phase — `/phase-0`, `/phase-3`, `/phase-17-1`. Each cites the plan rather than restating it. |
| `.claude/agents/` | Six subagents. Version-controlled, so they travel with a clone rather than being pasted into settings per machine. |
| `.claude/skills/` | Thirteen skills, auto-invoked when a task matches their description. |

## Running locally

Prerequisites: Node 22 (`.nvmrc`), Docker with Compose, Flutter 3.47 stable on your `PATH`.

```bash
npm install                          # root: commit hooks only
docker compose up -d                 # PostgreSQL 18 + pg_cron + WAL archiving, port 5435
cd backend && cp .env.example .env && npm install
npm run db:migrate                   # applies prisma/migrations, schedules the heartbeat job
npm run dev                          # boots: reaches the DB, reports the job runner, exits 0
npm run jobs:status                  # is the scheduled no-op job firing? (exit 0 = yes)
cd ../frontend && flutter pub get && flutter run
```

> **Upgrading from the Postgres 16 volume.** Dependabot moved the base image from
> 16 to 18. PostgreSQL refuses to start on a data directory written by a different
> major version, so an existing `docker compose` volume will not mount. Phase 0
> holds one heartbeat row and nothing else, so the cheap fix is to discard it:
>
> ```bash
> docker compose down -v && docker compose up -d --build
> npx prisma migrate deploy --schema backend/prisma/schema.prisma
> ```
>
> Do this deliberately — `-v` deletes the volume. From Phase 2 onward, when the
> database holds something worth keeping, a major bump needs `pg_upgrade` or a
> dump/restore instead.

`scripts/verify.sh` runs every check that does not need a running app — design rules, backend lint/typecheck/tests, `flutter analyze`/`flutter test`. `scripts/db/pitr-status.sh` reports whether WAL archiving is protecting the local database; `scripts/db/base-backup.sh` takes the base backup PITR replays onto (`scripts/db/README.md` has the restore procedure).

| | Backend | Frontend |
|---|---|---|
| Stack | TypeScript 7 · Prisma 7 · PostgreSQL 18 (Fastify arrives in Phase 2) | Flutter 3.47 · Dart 3.13 · Riverpod (§2) |
| Lint | ESLint 10 (typescript-eslint strict, type-checked) + Prettier | `flutter_lints` + strict casts/inference/raw types |
| Tests | Vitest | `flutter_test` |
| Layout | `src/modules/<domain>/`, one per domain as phases add them — see `backend/CLAUDE.md` | `lib/features/<feature>/`, one per feature as phases add them — see `frontend/lib/README.md` |

Commit hooks (husky + lint-staged) format and lint staged files per app. CI (`.github/workflows/ci.yml`) is defined to run lint, typecheck, build and tests for both apps against the same Postgres image, boot the backend, wait for the heartbeat, and scan dependencies (`npm audit`, dependency-review on PRs, Dependabot for npm, pub, Actions and Docker). Make each job a required status check in the repository's branch protection — that is a GitHub setting, not something the workflow file can do.

`backend/package.json` carries two `overrides` (`mysql2`, `deepmerge-ts`). Both are transitive through the `prisma` CLI and both were flagged high by `npm audit` on the first install; the overrides pin the fixed versions. Drop them when a Prisma release moves past the vulnerable ranges.

## Conventions every line of code follows

These four are fixed by the plan (§2 Architecture Decisions) and are restated here because §Phase 0 asks the README to carry them. The plan is authoritative if the two ever differ.

**UUID primary keys.** Every entity's `id` is a UUID — `String @id @default(uuid()) @db.Uuid` in Prisma. No serial integers anywhere, including join and infrastructure tables (`job_heartbeat` in the first migration sets the pattern). This removes the enumeration surface: an ID in a URL reveals nothing about how many of a thing exist.

**Integer laari money.** Every price, amount, fee and balance is an integer number of laari (MVR × 100): `Int` in Prisma, `number` holding an integer in TypeScript, an integer in JSON. MVR 150 is `15000`. Never a float, never a `Decimal`, never a decimal string like `"150.00"`. Use the plan's field name where it gives one (`agreedAmount`, `finalAmount`, `subscriptionPriceLaari`); where it does not, suffix `Laari` so the unit is visible at the call site. Formatting into `MVR 150.00` happens in the presentation layer and nowhere else.

**Soft delete everywhere.** Nothing is ever `DELETE`d. Every entity carries a status or visibility field, and "deleting" sets it. Every query that returns user-visible data filters on that field. Moderation actions are reversible for the same reason. Even the Phase 0 heartbeat table follows it: the job upserts one row per job rather than inserting and pruning. The one thing the plan does purge — identity-document images, 90 days after a decision (§1e) — is a file deletion with the decision, evidence type and reviewer retained.

**Idempotency keys.** Every money-adjacent and every creation `POST` requires a client-supplied idempotency key (the transport — header or body field — is fixed in Phase 2 and used identically everywhere after). The server dedupes on `(userId, operation, clientKey)` and a repeat returns the **original** result — same status, same body — rather than doing the work twice or erroring. Mobile clients retry on dropped connections; without this a retried booking is two bookings. Phase 2 builds the middleware; every later phase uses it.

## Building

Work top to bottom. Run `/phase-0` first and do not start phase N+1 until phase N's Definition of Done is met. Phase 17 is split into four slices and must not be attempted in one pass.

Where a phase says a screen has no mockup, the agent proposes a design and you approve it before implementation code is written.

## archive/ — provenance only

Superseded plan revisions (v2–v4), the design reviews that produced them, and the Cursor-era build artifacts (`02_Cursor_Prompts.md`, `03_Cursor_Rules_Skills_Subagents.md`, the subagent prompt doc).

**Never build from anything in `archive/`.** `01_Development_Plan_v4.md` in particular describes a contact-info endpoint that was deleted, SMS OTP, a binary verified badge and a pinned global subscription price — none of which exist. `CLAUDE.md` instructs against reading them.

## Key architectural decisions

Full provenance is in §9 of the plan, across seventeen review rounds.

- **Payment for jobs is off-platform.** RaajjePro never moves money between customer and provider. Booking payment is a two-sided self-attestation; the UI never claims to have verified it. "Payment hold" means a locked agreement, not escrow.
- **In-app chat is the sole coordination channel** for a booking's entire life. Exactly one endpoint returns a phone number to another user — emergency bookings only, under seven request-time conditions plus a runtime kill switch.
- **Booking has three modes** — slot, request-with-quote, and emergency. Emergency broadcasts to every eligible provider; offers collect for 90 seconds and the customer picks from up to three.
- **Verification is three tiers** (Bronze/Silver/Gold), and the bar for emergency work is per-category — Gold for Electrical and Plumbing.
- **Provider conduct is scored from booking outcomes** and displayed as objective metrics only. No editorial labels, ever.
- **Monetization is subscription-only**, priced per provider. The one customer-facing charge is the MVR 200 emergency dispatch fee.
- **Double-booking is prevented by a provider-scoped PostgreSQL exclusion constraint**, not a unique index.
- **There is no SMS.** Email carries OTP, the push fallback and admin alerting, via Amazon SES.

## Open questions

Recorded in §7 and §8 of the plan rather than left implicit. The largest: there is no acquisition plan for the first 50 providers, and launch revenue does not cover a heavily manual operation.
