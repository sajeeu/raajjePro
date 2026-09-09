# Picking this up on another machine

Everything needed to continue is in this repository. Nothing lives only in a chat session.

## Set up

```bash
git clone git@github.com:sajeeu/raajjePro.git
cd raajjePro
code .
```

VS Code will offer the recommended extensions from `.vscode/extensions.json` — the important one is **Claude Code**. Accept them.

Then open Claude Code in the workspace. It reads `CLAUDE.md` at the root automatically, which carries every architectural invariant, so it starts with the same constraints it has here. **You do not need to re-explain the project.** `backend/CLAUDE.md` and `frontend/CLAUDE.md` scope themselves to their own trees and load on top of it.

Then the toolchain. Phase 0 is built, so a checkout needs Node 22, Docker with Compose, and Flutter 3.47 stable on your `PATH` (`export PATH="$HOME/flutter/bin:$PATH"` in your shell rc — the pre-commit hook runs `dart format` and `scripts/verify.sh` runs `flutter analyze`, and both need it).

🔧 **One Android SDK quirk, if the app will not build locally.** `frontend/android/app/build.gradle.kts` pins `compileSdk = 37`, which `flutter_secure_storage` 11 requires. The SDK publishes that platform as **`platforms;android-37.0`** — minor API levels are a 2025 change — but AGP 9.1 looks for a directory named `android-37`. On this machine the two are bridged by copying the installed `android-37.0` directory to `android-37`; the copy says so in its own `source.properties`. **CI needs none of this** — a fresh runner resolves the platform on its own, verified on the Phase 3 merge, which built `app-debug.apk` in 220 seconds. So this is a local-machine fix, not a project dependency:

🔧 **The Android SDK is at `$HOME/Android`, not `$HOME/Android/Sdk`.** Worth
saying because a session looked for the conventional path, concluded the
machine had no `adb` and no emulator, and handed the whole device-verification
pass on to someone else — on the same machine that has both. `adb` is
`$HOME/Android/platform-tools/adb` and the emulator `$HOME/Android/emulator/emulator`;
neither is on `PATH` and `ANDROID_HOME` is unset, so export both before
building or launching:

```bash
export ANDROID_HOME="$HOME/Android"
export PATH="$HOME/flutter/bin:$HOME/Android/platform-tools:$HOME/Android/emulator:$PATH"
```

Anything a Claude session starts dies with the session — the emulator, a
`npm run dev`, a `flutter run`. `setsid nohup <cmd> &` survives a turn, but for
a long session start the emulator and the API from your own terminal.

```bash
sdkmanager "platforms;android-37.0"
cp -r "$ANDROID_HOME/platforms/android-37.0" "$ANDROID_HOME/platforms/android-37"
```

Note that `scripts/verify.sh` runs `flutter analyze` and `flutter test` but **does not build the APK**, so a broken Android build passes local verification and fails only in CI.

```bash
npm install                                   # commit hooks
docker compose up -d                          # Postgres 18 + pg_cron + WAL archiving on :5435
(cd backend && cp .env.example .env && npm install && npm run db:migrate)
(cd backend && DATABASE_URL="postgresql://raajjepro:raajjepro@localhost:5435/raajjepro_test?schema=public" npm run db:deploy)
(cd frontend && flutter pub get)
scripts/verify.sh                             # everything should be green
```

The second migrate is the `_test` database. The suite writes real rows and never deletes them — it isolates by unique key rather than by truncating — so `backend/test/setup.ts` refuses to run against any database whose name does not end in `_test`. A fresh Docker volume creates it; the migration is yours to apply.

`README.md` has the day-to-day commands and the four conventions every line of code follows.

## Write in the editor, verify in the terminal

The split that works: **code in VS Code with the Claude extension, check with one command.**

**The division is firm.** Phases are built in VS Code — every one of them, including
the ones a terminal session could technically write. The terminal session does
follow-up, verification and bug fixes: running `scripts/verify.sh`, exercising a
phase's Done-when criteria against a live server, auditing an imported design
against the plan, and fixing defects that verification turns up. It does not
build a phase, and it does not start one because the moment seems right.

```bash
scripts/verify.sh
```

It runs everything that can be checked without starting the app, and exits non-zero if anything fails:

| Check | What it catches |
|---|---|
| `verify-dc.py` | Prototype structure, plus every locked product rule — a stale category, a claim the product cannot keep, a dead control |
| `checks/journeys.py` | The six acceptance journeys from Round 38 §6, plus broken links and orphan screens |
| `checks/locked-rules.py` | Instruction files stating a rule the plan has already reversed |
| `db/image-matches-repo.sh` | A running database container older than the image the repo specifies — how the Postgres 18 bump stayed broken for ten commits while every local check passed |

The backend block (typecheck, lint, tests) and the frontend block (`flutter analyze`, `flutter test`) run as well. The backend tests need the Docker database up and migrated. With no database configured at all they skip rather than fail; with one configured whose name does not end in `_test` they refuse to run, because they write rows and never delete them.

The same three are VS Code tasks. **Ctrl/Cmd-Shift-P → Run Test Task** runs the lot; the individual ones are under **Run Task**.

### Why `locked-rules.py` exists

`verify-dc.py` only ever reads `.dc.html`. Nothing read the files that tell you what to build — and they drifted. `frontend/CLAUDE.md` was still instructing Phase 1 to label slot cards `Book instantly` six rounds after Round 44 renamed it, and to render an `Emergency available` marker long after Round 23 deleted it. The style guide and the designer brief carried the same stale label, and `admin-panel-conventions` still described the three kill switches as SMS in a product with no SMS.

None of that was visible in a design review. All of it would have been implemented as written.

## What this repository is, right now

**Phases 0, 1, 2, 3, 3b, 3c and 4 are built.** Phase 0 is the repository and environment foundation: both apps boot, lint is clean, the pg_cron no-op job is observably firing, PITR is configured on the local database, CI runs lint/build/test plus dependency scanning. Phase 1 is the design system: tokens, every shared widget §Phase 1 lists (plus the verification badge, text input, toggle and avatar by decision), the three motion primitives, and a component gallery at `/gallery` that `flutter test` scrolls end to end under LTR, RTL, 200% text and reduced motion. `docs/decisions/08-phase-1-design-system.md` records the decisions and the seven prototype colours that failed AA and were corrected. **One thing is still open from Phase 1's Done-when:** the screen-reader pass with TalkBack or VoiceOver needs a device — the checklist is in that decision file. Phase 2 is the backend core: Fastify under `/v1`, the standard envelope and error hierarchy, Postgres-backed rate limiting and idempotency, a real admin identity model (TOTP MFA, sessions, force-logout, the queryable audit log), and Amazon SES with bounce/complaint handling and a suppression list honoured before every send. `docs/decisions/10-phase-2-backend-core.md` records what changed during the build and what Phase 3 must confirm. **Phase 3's backend is built**: register/login, JWT access + refresh rotation with per-device sessions, email OTP behind `requireEmailVerified`, account settings (change password/email/phone, sessions, data export), the deletion pipeline (queued, frozen, 30-day backstop) and its Node job runner. **Phase 3's Flutter half is built**: Sign In, Register (pixel-match), Verify Email (one OTP screen shared by verify-email and change-email), Session expired, `AuthGate` and the route table, Account Settings with its sessions/download/delete sub-screens, and Change password/email/phone with the phone-never-verified design-rule test. `docs/decisions/12-phase-3-identity.md` records what changed during the build on both halves, the three "Phase 3 must confirm" items resolved, the frontend's prototype divergences, and what Phase 3b/5/6/11/17 pick up. Run it with `flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000` from `frontend/` against a running backend — the OTP code lands in the newest JSON file under `backend/.mail/` (the file transport).

**Phase 3b is built**: reset-token issuance, expiry and consumption, every refresh token invalidated on success, and the three screens — request email, check-your-inbox, set new password. It sends a six-digit **code**, not a link. `docs/decisions/13-phase-3b-forgot-password.md`.

**Phase 3c is built** — push notification infrastructure, against a fake vendor by decision. `PushSender` is the one send interface Phases 17 and 19 call; `NotificationDispatcher` is the only place the fallback chain is written; device registration keys on a stable installation id so a token refresh updates the row rather than adding one, with a partial unique index stopping a handed-on phone from delivering the previous owner's notifications. The rungs are: emergency sends push and email in parallel with no ladder; a known OS denial (or no live registration at all) emails immediately; anything else emails at **30 minutes** if no device has acked. A vendor accepting a push is not delivery — only the app's ack is. Two jobs run on the Phase 0 runner: the fallback sweep every minute and the rolling-day health check every five. `GET /v1/admin/message-log` is the "did this provider actually receive it?" lookup Phase 10b puts a screen on. **No Firebase project and no Apple developer account exist and none was procured** — `PUSH_TRANSPORT=fcm_apns` is refused at config load, pushes are written as JSON into `backend/.push/`, and a real push on a real device is ledger rows **L11** (FCM) and **L12** (APNs). `docs/decisions/15-phase-3c-push.md`.

**Phase 4 is built** — the category catalogue. `Category` carries every
per-category number the plan seeds (booking mode, lead time, the emergency
tier bar and answer window, the arrival presets, both quote windows, the
callback flag and the occasion chips) and **nothing anywhere enumerates a
category name**: `GET /v1/categories` is public and is the grid's only
source, so a thirteenth added through the admin API reaches Explore with no
rebuild. `npm run db:seed` bootstraps the twelve — create-if-absent, so it
never reverts an admin's Phase 10b edit. `DELETE` clears `isActive`; the
admin list returns inactive rows, which is the only way back. Two coherence
rules are enforced server-side (an emergency-capable category must carry a
tier bar and an answer window; the two quote windows move together) — both
derived from §1c rather than stated in §Phase 4, and both recorded in the
decision file. The Explore screen renders the grid with all four states and
the surrounding chrome **inert**, each control wrapped in `InertControl`
naming the phase that owes it a destination, with a test per control that
fails when it is wired. The emergency entry is **absent rather than dead** —
§Phase 16 owes it. `docs/decisions/16-phase-4-categories.md` and
`docs/design/explore-corrections.md`.

🔧 **A plan discrepancy found while building it, flagged not resolved.**
§0.0 item 12 says "the seed list **§Phase 4** calls for" when it introduces
`docs/data/inhabited-islands.json`. §Phase 4's text names no island, and its
Done-when has no island line; **§Phase 7's** first bullet is the one that says
"Island reference data (real seed list, not five entries)". Phase 4 therefore
seeded categories only. If islands were meant to land here, §Phase 4 needs the
bullet §0.0 assumes it has.

**Next**: `/phase-5`.

| | |
|---|---|
| `01_Development_Plan_v5.md` | **The single source of truth**, revision 5.20. Every product decision. Read §0.0 first — it is a precedence rule |
| `CLAUDE.md` | Architectural invariants Claude must never violate. Loaded automatically |
| `docs/design/` | The design system: style guide, page briefs, session prompts, the plan for the rebuild |
| `mockups/design-composer/` | **61 working prototypes** — the current design reference |
| `mockups/*.jpg` | The seventeen originally-delivered screens. Provenance only; a prototype beats an image |
| `backend/` | TypeScript · Prisma 7 · PostgreSQL 18. Phases 0–2: Fastify under `/v1`, the envelope and error hierarchy, rate limiting, idempotency, admin identity with TOTP MFA, the audit log, and SES email with bounce handling. Phase 3: register/login, JWT sessions, email OTP, account settings, data export, the deletion pipeline and its job runner. Phase 3b: password reset. Phase 3c: `PushSender` and the transport boundary, device registration, the fallback chain, the two notification jobs and the admin message log. Phase 4: the category catalogue, its seed CLI and the admin CRUD behind `requireAdmin` |
| `frontend/` | Flutter 3.47, Android + iOS, bundle id `mv.raajjepro.app`. Phases 0–1: the design system is in `lib/core/theme/` and `lib/shared/`, the gallery at `/gallery` (linked from Home in debug builds). Phase 3: Sign In, Register, Verify Email, Session expired, Account Settings and its sub-screens. Phase 3b: Forgot password. Phase 3c: the `PushMessaging` seam in `lib/core/push/` (no vendor SDK is a dependency) and the persistent enable-notifications reminder. Phase 4: Explore, its endpoint-driven grid and the inert chrome around it — `frontend/lib/README.md` lists every directory |
| `docker-compose.yml` · `infra/postgres/` | The local database image: pg_cron preloaded, WAL archived every 5 min |
| `scripts/db/` | `base-backup.sh`, `pitr-status.sh`, and the restore procedure |
| `.github/` | CI workflow and Dependabot |
| `.claude/commands/` | 38 phase commands — `/phase-0`, `/phase-17-1`, … |
| `.claude/skills/` | 13 skills that trigger on relevant work |
| `docs/design/checks/` | The verification scripts `scripts/verify.sh` runs |
| `archive/` | Superseded. **Never read as current** |

## The design work is done

**61 prototypes, every session imported, Rounds 40–52 applied.** `scripts/verify.sh` passes clean: no warnings, all six acceptance journeys run start to finish, zero broken links, zero orphan screens.

The loop below is kept because it is how a correction round runs, and there will be more.

Read `docs/design/redesign-plan.md` — it has the full sequence, what each session covers, and which mockups to attach.

**The Claude Design project is "Mobile app design project", id `065ca2ad-ff8f-4eac-a8f8-e860a77561ff`.** Its `CLAUDE.md` should carry `docs/design/style-guide.md`; set that once per machine if the project is recreated.

### The loop, per session

1. Paste the session brief from `docs/design/sessions/` into a new chat in that project
2. Attach whatever the brief's *Attach* line names
3. Let it build; ask explicitly for any state it skipped
4. Tell Claude Code **"import and analyse"** — it pulls the file through the connector and audits it against the plan
5. Claude Code writes a correction prompt; paste it back
6. **Export** the corrected artboards into `mockups/design-composer/`
7. `python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html`
8. Commit

Step 4 is the one that earns its keep. Across five prototypes it has caught a missing screen, a false claim about how declining affects a provider's record, invented functionality with no endpoint behind it, an implied charge that does not exist, two claims the product cannot keep printed on Home, and bank details missing from provider onboarding entirely. None of those were visible in the design. All were visible against the plan.

### Components are files, not sections

`<dc-import>` mounts a **sibling `.dc.html`**. Seven components exist as their own files — `ServiceCard`, `VerificationBadge`, `Chip`, `StatusPill`, `BottomNav`, `SkeletonCard`, `EmptyState` — and `Components.dc.html` is the gallery that mounts them. **Import them; never copy their markup.** A second copy is how twelve sessions drift into twelve products.

Two mappings live inside components deliberately: the tier copy in `VerificationBadge`, the twelve status labels in `StatusPill`. They must never be duplicated into a screen.

## End of day

```bash
scripts/eod-push.sh
```

Verifies every prototype, checks `origin` really is raajjePro, commits and pushes. Refuses to commit if a prototype fails its check. `--dry-run` to see what would happen. A clean tree is a normal outcome, not an error.

### The 16:30 backstop

A crontab entry runs it at **16:30 Maldives time** daily. Set it up once per machine:

```bash
( crontab -l 2>/dev/null | grep -v eod-push.sh
  echo "30 16 * * * /usr/bin/env bash $(pwd)/scripts/eod-push.sh >> $(pwd)/.eod-push.log 2>&1" ) | crontab -
```

Two things it depends on, worth checking on a new machine:

- **cron has no ssh-agent.** If your GitHub key has a passphrase the push will fail silently into the log. Test with
  `env -i HOME=$HOME PATH=/usr/bin:/bin ssh -o BatchMode=yes -T git@github.com` — it should greet you by name.
- **The machine has to be awake at 16:30.** A laptop asleep at that minute simply misses it; there is no catch-up.

Read `.eod-push.log` if a day looks missing. It is gitignored.

It is a safety net for a forgotten push, not a substitute for committing as you go — a day's work in one commit is a day's work you cannot bisect.

## What is outstanding, and who owns it

**Yours — none of this can be done from a keyboard here:**

- **SES and real email — deferred to deployment** (your decision, 2026-09-06; plan §0.0 item 17). No AWS account is needed to build anything. Every phase that sends email is built and verified against `EMAIL_TRANSPORT=file`, which writes each message as JSON into `backend/.mail/`. `docs/deferred-verification.md` is the ledger of what that leaves unverified and how each line is closed — it is general, not email-specific, and every phase appends to it; `docs/ops/ses-production-access.md` is the runbook to work through **early in the deployment phase, not at the end of it** — AWS can come back for more information and it is the last external dependency left
- **Legal counsel on liability** (§1i) — whether a platform that verifies identity, gates emergency work by tier and dispatches providers is still "just a marketplace" under Maldivian law
- **App Store submission outcome.** Phase 10a ships in-app bank-transfer billing as a deliberate test of guideline 3.1.1; rejection is likely and the fallback is mapped
- **Admin load costing** at 50, 200 and 500 providers. Plan §4 Sequencing places this *before Phase 0*; Phase 0 has been built without it, so it is overdue rather than backlog

**Left open by design, for a named later phase — not a gap, a seam:**

- **Saved preferences** (§Phase 3's account-settings bullet) — deferred past Phase 4, because a saved address needs `Island`, which **Phase 7** seeds and never keys by name (§Phase 7's first bullet; §0.0 item 12 attributes the seed to Phase 4, which its text does not ask for). Phase 6 or 7 builds it.
- **`AnonymisationHooks` and `DeletionBlocker`** (`backend/src/modules/account/anonymise.ts`) — the two seams Phase 3's deletion pipeline built and tested against a registered hook / an injected blocker. Phase 11 registers the real review-anonymisation hook; Phase 17 supplies the real open-bookings check. Both are ledger rows in `docs/deferred-verification.md` (P1, P2).

**Built in VS Code:** every phase, Phase 3 onward.

**Mine, on request:** verification against a phase's Done-when list, design-import audits against the plan, and the bugs those turn up — not the phases themselves.

**Yours, with sound on:** finishing the Phase 1 screen-reader pass. Steps 1–5 were run on 2026-09-07; **step 1 fails** (section headings are not announced as headings) and 2–5 pass. Steps 6–13 remain. No device is needed any more — an Android 15 Play Store emulator is installed with TalkBack enabled and the app on it:

```bash
export ANDROID_HOME=$HOME/Android
$HOME/Android/emulator/emulator -avd raajjepro_a11y -no-boot-anim &
```

Start it from your own terminal, not from a Claude session — one started by a session dies with it. The checklist, the result so far and the step 1 defect are in `docs/decisions/08-phase-1-design-system.md`. The gallery has its own RTL, 200% text and reduced-motion toggles, so step 13 needs no OS settings.

## One rule that overrides everything

Where anything disagrees with `01_Development_Plan_v5.md`, **the plan wins and the disagreement gets flagged, not silently resolved.** Five times a decision was reversed in the plan and survived in a copy of it. Every single time the plan was right and the copy was wrong.
