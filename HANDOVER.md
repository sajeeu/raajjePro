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

**Phases 0, 1, 2, 3, 3b, 3c, 4, 5, 6 and 7 are built.** Phase 0 is the repository and environment foundation: both apps boot, lint is clean, the pg_cron no-op job is observably firing, PITR is configured on the local database, CI runs lint/build/test plus dependency scanning. Phase 1 is the design system: tokens, every shared widget §Phase 1 lists (plus the verification badge, text input, toggle and avatar by decision), the three motion primitives, and a component gallery at `/gallery` that `flutter test` scrolls end to end under LTR, RTL, 200% text and reduced motion. `docs/decisions/08-phase-1-design-system.md` records the decisions and the seven prototype colours that failed AA and were corrected. **One thing is still open from Phase 1's Done-when:** the screen-reader pass with TalkBack or VoiceOver needs a device — the checklist is in that decision file. Phase 2 is the backend core: Fastify under `/v1`, the standard envelope and error hierarchy, Postgres-backed rate limiting and idempotency, a real admin identity model (TOTP MFA, sessions, force-logout, the queryable audit log), and Amazon SES with bounce/complaint handling and a suppression list honoured before every send. `docs/decisions/10-phase-2-backend-core.md` records what changed during the build and what Phase 3 must confirm. **Phase 3's backend is built**: register/login, JWT access + refresh rotation with per-device sessions, email OTP behind `requireEmailVerified`, account settings (change password/email/phone, sessions, data export), the deletion pipeline (queued, frozen, 30-day backstop) and its Node job runner. **Phase 3's Flutter half is built**: Sign In, Register (pixel-match), Verify Email (one OTP screen shared by verify-email and change-email), Session expired, `AuthGate` and the route table, Account Settings with its sessions/download/delete sub-screens, and Change password/email/phone with the phone-never-verified design-rule test. `docs/decisions/12-phase-3-identity.md` records what changed during the build on both halves, the three "Phase 3 must confirm" items resolved, the frontend's prototype divergences, and what Phase 3b/5/6/11/17 pick up. Run it with `flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000` from `frontend/` against a running backend — the OTP code lands in the newest JSON file under `backend/.mail/` (the file transport).

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

🔧 **A plan discrepancy found while building it — now resolved in the plan
(2026-09-09, revision 5.21).** §0.0 item 12 used to say "the seed list
**§Phase 4** calls for" when introducing `docs/data/inhabited-islands.json`,
and §Phase 4 names no island anywhere: **§Phase 7's** first bullet is the one
that asks for "Island reference data (real seed list, not five entries)", and
§Sequencing asks Phase 4 only for `bookingMode` and `emergencyCapable`. Phase 4
seeded categories only, which was the right reading. Item 12 now cites
§Phase 7, and `/phase-7` points at the data file so the list is not re-derived.

**Phase 5 is built** — provider profiles, backend only as §Phase 5 marks it.
`ProviderProfile` gains the bio, years of experience, the four payment-detail
fields, the account-level `acceptingNewCustomers` toggle, §1g's
`maldivianOwned`, the per-provider `subscriptionPriceLaari` and the
suspension pair. **Two things are deliberately not columns:** a phone number
(§Phase 5 keeps exactly one, on the user row) and any visibility flag —
`findVisibleProviders` derives it, and `information_schema` is asserted to
hold no `lifecycle_status` or synonym.

**Two seams carry the phase, because §Phase 5 is sequenced before the tables
its rules name.** There is no `Listing` until Phase 8 and no `Booking` until
Phase 17, so `PublishedListingSource` answers §1a's published-listing count
and `ProviderConductSource` returns §1f's metrics — the `DeletionBlocker`
pattern from Phase 3. Both defaults answer honestly rather than
optimistically: nobody is publicly visible before listings exist, and conduct
reports **null** rather than zero, because "0% on time" and "never been
booked" are different claims. Rows **P5-1** to **P5-4** in the
ledger say what only the real tables can prove.

`findVisibleProviders` is the one shared gate and suspension is an **input**
to it, not a filter each consumer repeats — so Phases 13, 15 and 16 must call
it rather than rebuild the rule. `readPublic` applies the gate itself and 404s for a
drafts-only or suspended provider, rather than trusting the caller to have
checked.

Conduct display follows §1f exactly: numbers only, **no field on any shape can
hold an editorial label**, rates suppressed below a ten-completed-booking
floor measured against the 90-day window, and the provider sees their own
numbers with `publiclyVisible: false` before a customer sees anything. The
suppression flag is `metricsBelowFloor`, **not** `newProvider` — the floor is
window-based, so that name would have printed "New provider · 47 jobs
completed"; §1f's copy is Phase 12/13's call and both numbers are there to
make it from. §1g's attribute is **null below Gold** — absent, not false.
Payment details reach a customer through exactly one accessor,
`paymentDetailsForBooking`, which takes no viewer on purpose because it is not
a route; changing them is audited by field name, never by value. Four columns
are absent from `PATCH /v1/providers/me` so a provider cannot self-verify,
self-declare local ownership, price themselves or un-suspend themselves. A
**read never creates the profile** — `isProvider` is `providerProfile !== null`
and Phase 6's role switcher routes on it, so opening a screen must not turn a
customer into a provider; the PATCH creates, which is §1a's implicit-creation
moment. `docs/decisions/17-phase-5-provider-profiles.md`.

🔧 **Two plan lines Phase 5 could not satisfy as written, both recorded in
that decision file rather than resolved.** §Phase 5's Done-when says payment
details are "absent from every response except the booking payment step",
which read literally forbids a provider reading their own bank details and so
makes §Phase 6a's collection step un-editable — the build takes it as "every
response **to another user**", on the precedent the phone carves out in the
same sentence, and the plan wording is what should change. And §Phase 6a's
own Done-when routes a **phone number** through `PATCH /v1/providers/me`,
which has no phone field by §Phase 5's single-copy rule: that half goes to
Phase 3's `PATCH /v1/users/me/phone`. **Phase 6a's builder needs the second
one before they start.**

**Phase 6 is built** — the customer profile module, backend and Flutter.
`GET /v1/users/me/profile-summary` is the Profile screen's one read and
`PATCH /v1/users/me` carries `fullName`; `account/dto.ts` records why the
summary has no phone number, no avatar, no island and no counts, and which
phase adds each. The screen is `Profile.dc.html` as Round 48 rewrote it: the
hero, a 2×2 block of booking tiles, the five rows and the role switcher.

**Five of its seven destinations do not exist yet, so they are routes rather
than dead controls.** A new shared `UnbuiltScreen` says what is missing and
names the phase that owes it — Saved (14), Saved preferences (17.4), Help &
support (19b), the four booking tiles (17), and the switcher's two (6a and
10) — and `owedBy` is asserted per destination, so landing one of those
screens trips a test. The four tiles keep four *distinct* placeholders, because
Round 48's finding was four labels reaching one screen and a generic
placeholder would have reintroduced it. `RoleSwitch.destinationFor` is
§Phase 6's last Done-when line as one function; the Done-when test drives the
real app and its real route table, so a row pushing an unregistered name fails
rather than passes.

🔧 **Two deliberate departures from the delivered design, both in the hero.**
The change-photo button is drawn to Round 48 §5's geometry and wired to
nothing (`InertControl`, owed by Phase 8): §Phase 6 mentions no photo, `User`
has no avatar column, and presigned media upload with EXIF stripping is
§Phase 8's bullet. And the subtitle reads `Member since Jan 2026` alone, not
`Malé, Maldives · Member since Jan 2026` — nothing stores a customer's island
and `Island` is §Phase 7's seed, so the half that can be answered is answered
and a test asserts no placeholder location is printed.

Wiring Explore's two Phase-6-owed controls — the header account disc and the
`Profile` nav tab — **broke the brand header at 200% text**, because
`Pressable`'s 48 dp floor is 12 dp wider than the 36 dp avatar. 🔧 **Fixed by
making Phase 1's `AppHeader` wordmark `Flexible`** — flagged rather than done
silently, since it is shared Phase 1 code, and needed because the 48 dp floor
and the 200%-text rule cannot both hold in that row otherwise. An
`OverflowBox` was tried first and is wrong: `RenderBox.hitTest` gates on the
box's own size, so the child laid out at 48 while only 36 was tappable. The
test written with it measured layout size and passed against the defect; it
now taps 20 dp off centre instead. **The general lesson: a geometry assertion
about a tap target has to tap.**

Phase 4's two tripwires for those controls were deleted on purpose, which is
what they were for. `SettingsRow` and `InertControl` moved into `shared/` when
Profile became their second consumer, and `core/routes.dart` now holds the
route names that cross a feature boundary.
`docs/decisions/18-phase-6-customer-profile.md` also records the three
defects the QA review found — `Pressable(excludeSemantics: true)` silently
discarding a `semanticLabel`, sign out staying on the screen, and the summary
outliving the account it described — each with the regression test that now
fails without its fix. Ledger rows **P6-1** to **P6-4**.

🔧 **Saved preferences belongs to Phase 17.4 — settled by the owner, 2026-09-10, and now written into the plan's 17.4 slice line.**
This paragraph said it did, and Phase 7 turned out not to own it: §Phase 7's
three bullets and its Done-when name it nowhere, and no section of the plan
specifies its entity shape or its endpoints, so building it would have meant
inventing a spec. Phase 7 seeded `Island` and built the picker, so the screen
is now buildable; §1h is what asks for it — labelled addresses, preferred
windows and standing instructions "reused across bookings" and "carried
forward by Book Again" — which is **Phase 17.4**'s slice, and before bookings
exist a saved preference has nothing to be used by. The route's `owedBy` and
ledger row **P6-2** now say so.

**Phase 7 is built** — service areas and the location module, backend and
Flutter. `Island` carries a UUID and **nothing anywhere keys on a name**: 16
normalised names occur in more than one atoll and `Meedhoo` exists in three, so
`ProviderServiceArea`, the DTO and every widget address an island by `id`. The
seed **reads** `docs/data/inhabited-islands.json` rather than transcribing it —
192 islands, 20 atolls — and computes the ambiguous set from the case-folded,
apostrophe-stripped name, which finds **16** groups where the raw string finds
15 and is the only way `K. Vilingili` and `GA. Vilin'gili` come out
distinguishable. 33 islands render with an atoll code, 159 bare, matching the
count `docs/data/README.md` records for the prototype array.

`npm run db:seed` now bootstraps categories **and** islands —
`src/cli/seed-categories.ts` was renamed `seed.ts` for it, because one command
has to leave a checkout with all its reference data.

**`GET /v1/islands?search=` is public and deliberately unpaginated.** §0.0
item 12 requires every match with no cap and no "show more", and the register
is closed — this phase adds no way to create an island — so the cap would be
the defect, not its absence. Matching, ranking and the `Dh. Meedhoo` display
rule are all server-side and the app rebuilds none of them: it sends what was
typed and draws what came back. Verified against a live server: `male` and
`Malé` both reach `Male'`, `Angolhitheemu` reaches `An'golhitheemu`, `gdh`
lists that atoll, `dhoo` returns 105 matches, `vilingili` returns both.

**§Phase 7 names a POST and a DELETE on `/v1/providers/me/service-areas` and no
GET**, so the read went to the endpoint that already existed:
`GET /v1/providers/me` carries `serviceAreas`, additively, and both writes
return the resulting list in full. Removing an island stamps `removedAt` and
re-adding revives the same row (invariant 8). Adding one creates the provider
profile as `PATCH /v1/providers/me` does — saying where you work is acting as a
provider — but removing one does not, because a profile made by a stray DELETE
would be permanent.

On the Flutter side the multi-select is **standalone, not screen-specific**, as
§Phase 7 asks: §Phase 6a's onboarding and §Phase 9's wizard step 2 embed the
same widget, and until then the component gallery's **Island picker** section
is its only runnable home. The header sheet on Explore pays Phase 4's island
tripwire. 🔧 **Two Phase 1 files changed and are flagged rather than done
silently:** `AppTextField` gained `autofocus` (the sheet exists to be typed
into), and the gallery's a11y sweep now pumps a `ProviderScope` with a faked
API, because the gallery gained its first data-driven specimen. That sweep also
caught a real defect — a scrollable list nested in a scrolling page swallows
the page's drag — so the island list **grows by default** and only scrolls
inside its own box when a caller caps it.
`docs/decisions/19-phase-7-service-areas.md`. Ledger rows **P7-1** to **P7-3**.

**Next**: `/phase-6a` — and its builder needs two things first. Phase 5's
second flagged line: §Phase 6a's Done-when routes a phone number through
`PATCH /v1/providers/me`, which has no phone field, so that half goes to
`PATCH /v1/users/me/phone`. And 🔧 **it is no longer propose-first** (plan
revision 5.22, 2026-09-10): the flow is drawn as
`mockups/design-composer/Become a Provider.dc.html`, whose third step is the
service-areas step Phase 7 just built the control for.

| | |
|---|---|
| `01_Development_Plan_v5.md` | **The single source of truth**, revision 5.22. Every product decision. Read §0.0 first — it is a precedence rule |
| `CLAUDE.md` | Architectural invariants Claude must never violate. Loaded automatically |
| `docs/design/` | The design system: style guide, page briefs, session prompts, the plan for the rebuild |
| `mockups/design-composer/` | **61 working prototypes** — the current design reference |
| `mockups/*.jpg` | The seventeen originally-delivered screens. Provenance only; a prototype beats an image |
| `backend/` | TypeScript · Prisma 7 · PostgreSQL 18. Phases 0–2: Fastify under `/v1`, the envelope and error hierarchy, rate limiting, idempotency, admin identity with TOTP MFA, the audit log, and SES email with bounce handling. Phase 3: register/login, JWT sessions, email OTP, account settings, data export, the deletion pipeline and its job runner. Phase 3b: password reset. Phase 3c: `PushSender` and the transport boundary, device registration, the fallback chain, the two notification jobs and the admin message log. Phase 4: the category catalogue, its seed CLI and the admin CRUD behind `requireAdmin`. Phase 5: provider profiles, `getOrCreateProviderProfile`, §1a's `findVisibleProviders` gate and §1f's conduct read surface, both over seams Phases 8 and 11 fill. Phase 6: `profile-summary` and `PATCH /v1/users/me` on the existing account module. Phase 7: the island register and its seed, `ProviderServiceArea`, the public unpaged island search and the two provider service-area writes |
| `frontend/` | Flutter 3.47, Android + iOS, bundle id `mv.raajjepro.app`. Phases 0–1: the design system is in `lib/core/theme/` and `lib/shared/`, the gallery at `/gallery` (linked from Home in debug builds). Phase 3: Sign In, Register, Verify Email, Session expired, Account Settings and its sub-screens. Phase 3b: Forgot password. Phase 3c: the `PushMessaging` seam in `lib/core/push/` (no vendor SDK is a dependency) and the persistent enable-notifications reminder. Phase 4: Explore, its endpoint-driven grid and the inert chrome around it. Phase 6: Profile, the role switcher, `LegalIndexScreen`, and `UnbuiltScreen` for the routes later phases owe. Phase 7: `core/location/` and `shared/location/` — the reusable island multi-select, the header picker sheet, and the session-scoped browsing island — `frontend/lib/README.md` lists every directory |
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

- **Saved preferences** (§Phase 3's account-settings bullet) — 🔧 **now Phase 17.4's, settled by the owner 2026-09-10 and written into §Phase 17's slice list.** Phase 7 seeded `Island` and did not take it: §Phase 7's bullets and Done-when name it nowhere and no section of the plan gives it an entity shape or endpoints, so Phase 7 declined to invent them. §1h asks for it as part of repeat use — "carried forward by Book Again" — so it sits with **Phase 17.4**, by which point a saved address has a booking to be used by. The island control it needs now exists (`IslandMultiSelect`, `IslandPickerSheet`).
- **`AnonymisationHooks` and `DeletionBlocker`** (`backend/src/modules/account/anonymise.ts`) — the two seams Phase 3's deletion pipeline built and tested against a registered hook / an injected blocker. Phase 11 registers the real review-anonymisation hook; Phase 17 supplies the real open-bookings check. Both are ledger rows in `docs/deferred-verification.md` (P1, P2).

**For the terminal session — the Phase 5 QA re-review's remaining items (2026-09-09).**
A full re-review of Phase 5 confirmed every behavioural finding fixed and
verified live: the §1a gate inside `readPublic`, the read that no longer
creates a profile, 8-of-8 concurrent `getOrCreateProviderProfile` callers
succeeding on one row, the deactivated-category lookup, the payment-detail
audit entry, redaction at depths 0–3, the malformed cursor, the tier guard,
per-principal rate limiting and the fuller export. No behavioural regression,
no authorization gap, no response shape that gained a phone number or a
payment detail. What is left is documentation and test coverage:

🔧 **Four of the five were done on 2026-09-09** in `3175a6a` and the
`NotFoundError` change that follows it; what remains is the last item.

- **Done — decision 9 and the decision count.** Decision 9 now names the two
  display mappers and states why `providerOwnExport` returns the stored value:
  §1g governs what a *customer* is shown, an export is what the platform holds
  about the subject. The count reads eleven.
- **Done — the three untested fixes now have tests**, each confirmed to fail
  before it was kept: revert the fix, watch it go red, restore it. The
  malformed cursor asserts a page across four shapes; the five payment keys are
  asserted directly, nested as a profile would arrive, because no serializer
  logs a body and the Phase 5 assertion could not see them; `tiersAtOrAbove`
  throws outside the enum, which matters because `slice(-1)` returns
  `['gold']` and §Phase 17.3 reads `emergencyMinimumTier` through it — a typo'd
  tier would broadcast an emergency to Gold alone, unlogged.
- **Done — `NotFoundError` takes an optional code.** `GET /v1/providers/me`
  answers `PROVIDER_PROFILE_NOT_FOUND`; a bad path still answers `NOT_FOUND`;
  every other caller keeps the default, so nothing else changed behaviour. The
  parameters are **message first, code second**, deliberately unlike
  `AuthorizationError` and `ConflictError`, which take the code first: eleven
  callers already pass a message positionally and both are strings, so matching
  the siblings would have turned each message into an error code with no type
  error to catch it. Do not "fix" that inconsistency by reordering.
  **Phase 6 and 6a should still route on `isProvider`** — no request, and
  reliable because a read no longer creates the profile. Both commands say so.
- **Open — two plan divergences the owner chose to record rather than amend
  (2026-09-09).** §Phase 5's Done-when 5, read literally, would forbid a
  provider reading their own bank details; §Phase 6a's Done-when routes a phone
  number through `PATCH /v1/providers/me`, which has no phone field under
  §Phase 5's single-copy rule, so that half goes to Phase 3's
  `PATCH /v1/users/me/phone`. Both are written up in the decision file, and
  `/phase-6a` now carries the second one so its builder meets it before
  starting rather than after.

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
