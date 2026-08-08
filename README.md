# RaajjePro

Planning and specification for RaajjePro, a local services marketplace for the Maldives.
Flutter app (customer + provider) · TypeScript/Fastify/Prisma/PostgreSQL backend · separate React admin web app.

Nothing is built yet. This repository holds the specification the build will follow.

## Current documents — build from these

| File | What it is |
|---|---|
| `01_Development_Plan_v5.md` | **The authoritative spec**, at revision 5.4. Standalone — supersedes v1–v4 entirely. Read §0.0 first: it is a precedence rule. |
| `02_Cursor_Prompts.md` | Phase-by-phase build prompts, one per Cursor session, generated from the plan. |
| `03_Cursor_Rules_Skills_Subagents.md` | `.cursor/rules`, skills and subagent prompts. These apply **silently on every generation**, so a stale copy steers everything. |

Work top to bottom through `02`. Install `03` into the repo before pasting anything from `02`.

## Superseded — do not build from these

`01_Development_Plan_v2.md`, `_v3.md`, `_v4.md` are kept for provenance only. They conflict with v5.4 in ways that produce wrong code — v4 in particular specifies a contact-info endpoint that no longer exists, a binary verification flag, and a pinned global subscription price.

`raajjepro-design-review.md`, `-v2`, `-v3` reviewed v1–v3 and describe architecture since replaced. `raajjepro-decisions-log.md` is dated 2026-08-03 and predates rounds 7–13; the authoritative record of what is settled is **§9 Decision Log** in the plan itself.

`raajjepro-chat-history.md` is background context from early planning.

## Key architectural decisions

Full provenance for all of these is in §9 of the plan, across thirteen review rounds.

- **Payment for jobs is off-platform.** RaajjePro never moves money between customer and provider. Booking payment is a two-sided self-attestation; the UI never claims to have verified it.
- **In-app chat is the sole coordination channel** for a booking's entire life. Exactly one endpoint in the system returns a phone number to another user, for emergency bookings, under seven conditions.
- **Booking has three modes** — slot, request-with-quote, and emergency — with three distinct accept timeouts. Emergency requests broadcast to every eligible provider at once; the provider states their callout fee when accepting and the customer accepts or rejects that offer.
- **Verification is three tiers** (Bronze/Silver/Gold). Emergency capability requires Silver or above. The badge never depends on subscription state.
- **Monetization is subscription-only in v1**, priced per provider. All customer features are free indefinitely.
- **Double-booking is prevented by a provider-scoped PostgreSQL exclusion constraint**, not a unique index.
- **There is no SMS.** Email carries OTP, the push fallback and admin alerting, via **Amazon SES** — a single point of failure by design, recorded as such in §7. Bounce and complaint handling is a **Phase 0** deliverable, because SES will not leave its sandbox without it and Phase 3 is untestable until it does.

## Open questions

Recorded in §7 and §8 of the plan rather than left implicit. The largest: there is no acquisition plan for the first 50 providers, and the no-contact-information rule has not been tested with real users.
