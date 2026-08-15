# RaajjePro

Planning and specification for RaajjePro, a local services marketplace for the Maldives.
Flutter app (customer + provider) · TypeScript/Fastify/Prisma/PostgreSQL backend · separate React admin web app.

Nothing is built yet. This repository holds the specification the build will follow, and the Claude Code configuration that builds it.

## The source of truth

| File | What it is |
|---|---|
| `01_Development_Plan_v5.md` | **The authoritative spec**, at revision 5.7. Standalone. Read §0.0 first — it is a precedence rule. |

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
