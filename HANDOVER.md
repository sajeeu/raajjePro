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
scripts/verify.sh                             # all of it; takes about three minutes
```

🔧 **If `backend lint` ever exhausts Node's heap again, read this before
raising the heap.** It happened once, on 2026-09-15, the day §Phase 9a's six
models landed. It looked like an environment problem and was not one: it was a
single rule meeting a single line.

`@typescript-eslint/no-unnecessary-type-assertion`, weighing
`value as never` against an index typed
`keyof Prisma.ListingUncheckedUpdateInput`, has to compare the assertion with
the union of every field's update-operation type. That union grew with the new
models and the comparison went superlinear — **4.4 GB and a heap abort on one
675-line file**. Either assertion alone is fine (1.7 GB, or 0.5 GB); it is the
pair that explodes. Writing the loop through a plain `Record<string, unknown>`
instead, in `backend/src/modules/listings/service.ts`, put the whole-repository
lint at **13 seconds and 1.1 GB** with every rule still on.

The lesson is the measurement order. Loading the enlarged type surface costs
almost nothing — type-aware parsing with no type-aware *rules* running is 3.4
seconds and 0.7 GB. So "the Prisma client got bigger" is never the whole answer.
Bisect the rule set with `eslint --rule '{"<rule>":"off"}'`, then bisect the
file, then bisect the line. It took eleven runs to go from "lint OOMs" to one
line, and every lever that would have been pulled instead — a bigger CI heap,
dropped `strictTypeChecked` rules, a thinner Prisma relation surface — would
have paid a permanent cost for a local cause.

The second migrate is the `_test` database. The suite writes real rows and never deletes them — it isolates by unique key rather than by truncating — so `backend/test/setup.ts` refuses to run against any database whose name does not end in `_test`. A fresh Docker volume creates it; the migration is yours to apply.

🔧 **Looking at the app in a browser — preview only, added 2026-09-10.**
`frontend/web/` exists so the app can be clicked through at any window size
without an emulator. It is **not a supported platform**: no web build in CI, no
web target in the plan, and `flutter_secure_storage` falls back to browser
storage on web, so **session and token behaviour is not faithful** — layout,
copy and anything read from the API are.

Serve it on **port 5173**, not any other port. That is the origin the backend's
CORS allows (it was reserved for the admin panel), so 5173 needs no backend
change and anything else is refused by the browser:

```bash
(cd frontend && flutter build web --dart-define=API_BASE_URL=http://localhost:3000)
python3 -m http.server 5173 --directory frontend/build/web
```

`flutter run -d chrome --web-port 5173` works too, with hot reload. Note that
`flutter create --platforms=web .` also drops a stock `test/widget_test.dart`
in; it was deleted, and should be deleted again if anyone re-runs it.

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

### Two sessions, one working tree

The VS Code session and the terminal session share a checkout, which means
they share **the index and the stash**, not only the files. Three rules, each
of which has already been broken at least once:

**Commit by pathspec, never `git add .`.** `git add` sweeps up whatever the
other session has staged, and a bare `git commit` then carries their
half-finished work under your message. Name your paths:

```bash
git commit -m "…" -- path/one path/two
```

That commits the working-tree content of exactly those paths and leaves the
rest of the index alone. Check with `git show --stat HEAD` before pushing — if
a file you did not touch is in there, you have just committed somebody's
work-in-progress.

🔧 **`git add <paths>` is not the same rule, and it is how this was broken a
second time (2026-09-15).** Staging your own paths looks like committing by
pathspec and is not: the `git commit` that follows takes **the whole index**,
including whatever the other session staged before you started. It swept up two
of their renames, which moved two files out from under eleven committed imports
and left `main` unable to compile. The `--` form is the one that matters —
`git commit` with paths uses `--only` semantics and never reads the rest of the
index. If it has already happened and you have not pushed:

```bash
git log -1 --format=%B > /tmp/msg          # keep your message
git reset --soft HEAD~1                    # index goes back exactly as it was
git commit -F /tmp/msg -- path/one path/two
```

The other session's staging survives untouched, because a soft reset restores
the index rather than rebuilding it.

🔧 **A new file has to be `git add`ed first, and the error does not say so.**
`git commit -- <paths>` uses `--only` semantics, which can only narrow to paths
git already knows. Give it a path that is untracked and you get:

```
error: pathspec 'frontend/test/helpers/a11y.dart' did not match any file(s) known to git
```

which reads like a typo or a wrong directory, and is neither — the file is
right there. Stage the new file **by name** and then commit by pathspec as
usual:

```bash
git add path/to/new-file            # this one path, never `git add .`
git commit -m "…" -- path/one path/to/new-file
```

Staging one named path does not sweep the other session's work; it is the bare
`git commit` afterwards that would. Both halves of the rule still hold.

**Read `git status` before you stage, not after.** The other session may have
landed three commits since your last look. `git pull --ff-only origin main`
first, and `git fetch` before every push.

**Never bare `git stash` / `git stash pop`.** The stack is shared with every
worktree, so `pop` can take an entry that is not yours. Prefer a throwaway WIP
commit. If you must stash, tag it — `git stash push -u -m "<tag>"` — and
recover it with `git stash apply <sha>` after finding it by tag.

A red `scripts/verify.sh` in a shared tree is usually the *other* session
mid-build. Confirm it before acting: run the individual checks rather than the
whole gate, and read the whole output rather than the tail. Attributing a
failure to the other session on a glance at the last six lines is how a
typecheck error of mine reached CI.

### Why `locked-rules.py` exists

`verify-dc.py` only ever reads `.dc.html`. Nothing read the files that tell you what to build — and they drifted. `frontend/CLAUDE.md` was still instructing Phase 1 to label slot cards `Book instantly` six rounds after Round 44 renamed it, and to render an `Emergency available` marker long after Round 23 deleted it. The style guide and the designer brief carried the same stale label, and `admin-panel-conventions` still described the three kill switches as SMS in a product with no SMS.

None of that was visible in a design review. All of it would have been implemented as written.

## What this repository is, right now

**Phases 0, 1, 2, 3, 3b, 3c, 4, 5, 6, 6a, 7, 8 and 8a are built.** Phase 0 is the repository and environment foundation: both apps boot, lint is clean, the pg_cron no-op job is observably firing, PITR is configured on the local database, CI runs lint/build/test plus dependency scanning. Phase 1 is the design system: tokens, every shared widget §Phase 1 lists (plus the verification badge, text input, toggle and avatar by decision), the three motion primitives, and a component gallery at `/gallery` that `flutter test` scrolls end to end under LTR, RTL, 200% text and reduced motion. `docs/decisions/08-phase-1-design-system.md` records the decisions and the seven prototype colours that failed AA and were corrected. **One thing is still open from Phase 1's Done-when:** the screen-reader pass with TalkBack or VoiceOver needs a device — the checklist is in that decision file. Phase 2 is the backend core: Fastify under `/v1`, the standard envelope and error hierarchy, Postgres-backed rate limiting and idempotency, a real admin identity model (TOTP MFA, sessions, force-logout, the queryable audit log), and Amazon SES with bounce/complaint handling and a suppression list honoured before every send. `docs/decisions/10-phase-2-backend-core.md` records what changed during the build and what Phase 3 must confirm. **Phase 3's backend is built**: register/login, JWT access + refresh rotation with per-device sessions, email OTP behind `requireEmailVerified`, account settings (change password/email/phone, sessions, data export), the deletion pipeline (queued, frozen, 30-day backstop) and its Node job runner. **Phase 3's Flutter half is built**: Sign In, Register (pixel-match), Verify Email (one OTP screen shared by verify-email and change-email), Session expired, `AuthGate` and the route table, Account Settings with its sessions/download/delete sub-screens, and Change password/email/phone with the phone-never-verified design-rule test. `docs/decisions/12-phase-3-identity.md` records what changed during the build on both halves, the three "Phase 3 must confirm" items resolved, the frontend's prototype divergences, and what Phase 3b/5/6/11/17 pick up. Run it with `flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000` from `frontend/` against a running backend — the OTP code lands in the newest JSON file under `backend/.mail/` (the file transport).

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

**Two seams carried the phase, because §Phase 5 is sequenced before the
tables its rules name.** There was no `Listing` until Phase 8 and no
`Booking` until Phase 17, so `PublishedListingSource` answered §1a's
published-listing count and `ProviderConductSource` returns §1f's metrics —
the `DeletionBlocker` pattern from Phase 3. Both defaults answer honestly
rather than optimistically: nobody is publicly visible before listings
exist, and conduct reports **null** rather than zero, because "0% on time"
and "never been booked" are different claims. 🔧 **Phase 8 filled the first
seam and row P5-1 is closed** — `PUBLISHED_LISTINGS` is the default now, and
the seam changed shape from a batch `Set` lookup to a SQL predicate, so the
batch-accumulating loop is gone. Rows **P5-2** to **P5-4** say what only the
real tables can prove.

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

**Phase 6a is built** — Become a Provider, backend and Flutter, against
`mockups/design-composer/Become a Provider.dc.html`. Three steps behind one
route: the intro, the grouped account details (**About you · Getting paid ·
Availability**, Round 21's grouping) and the default service areas, which embed
the multi-select Phase 7 built standalone. **No new endpoint** — §Phase 6a says
to reuse Phase 5's update endpoint, so the flow makes three kinds of call:
`PATCH /v1/providers/me`, §Phase 7's service-area writes, and — for the phone
half its own Done-when misattributes — Phase 3's `PATCH /v1/users/me/phone`.
The phone goes first, so a number already held at Bronze leaves nothing else
written.

🔧 **`isProvider` was not enough, and the role switcher's signal changed.**
Onboarding's step 2 *is* §1a's profile-creation moment, so `isProvider` flips
one step before the flow ends — and a provider who closed the app on step 3
read as a returning provider, was sent to a dashboard, and never saw the step
they had stopped on. §Phase 6a requires the opposite. So there is now one
derived answer to "has this account completed onboarding?" —
`backend/src/modules/providers/onboarding.ts`, **never stored**, the same
discipline §1a applies to visibility — exposed as
`providerOnboardingComplete` on `profile-summary` and `onboardingComplete` on
`GET /v1/providers/me`. It counts what the three steps collect plus the
verified email §Phase 5 requires to finish, and it reopens if the last service
area is removed. `isProvider` is unchanged and still answers its own question.
**Flagged**: §Phase 6's wording ("a returning provider goes straight to My
Services Dashboard") should say "a provider who has completed onboarding" —
the plan is amended by its owner, not by a phase.

**The verified-email gate is in that rule, not on an endpoint.**
`requireEmailVerified` on `PATCH /v1/providers/me` was considered and rejected:
that endpoint is also Phase 10a's billing surface, and §1a says dashboard
access is never gated. An unverified provider can fix their own bank details
and is simply *not onboarded* until the address is confirmed — which is exactly
what §Phase 6a's "unverified blocks Continue" means.

**Step 2 submits on Continue and does not autosave**, departing from
`wizard-step-pattern` for a reason specific to it: the first write creates the
provider profile, that flip is permanent (invariant 8), and autosaving would
turn a customer who typed one character into a provider. Resume is derived from
the server instead — no profile → step 1, step 2 incomplete → step 2
pre-filled, no service area → step 3 — so nothing is cached on the device and a
provider-variant registration lands on step 2 with the name Phase 3 captured.

`providerType` (`individual` / `business`) is the new column, nullable because
§1a's implicit path makes a profile before anyone has been asked. It is on the
own-read and the export and **not** on `PublicProviderDto`: §1e reads it to
decide which documents Gold review wants and §1g's Maldivian-owned attribute
hangs from it, neither of which is customer-facing.

🔧 **Four departures from the artboard, and three shared files changed** — all
flagged in `docs/decisions/20-phase-6a-become-a-provider.md`. The one that
needs a product answer: **the bank list has no "Other" and no free-text
escape**, so a provider banking outside the seven listed Maldivian banks cannot
finish step 2. The artboard's `<select>` has no escape either and the plan
names no bank register, so nothing was invented; `transferInstructions` is the
field a design round would most likely reach for. The photo control is drawn
and inert (Phase 8 owns media upload, as on Profile), the atoll chips are
absent (the island search already matches an atoll code), and "Verified" beside
the email reads **"Email verified"** — `design_rules_test.dart` bans the bare
word, and naming what was checked is more truthful next to a phone number
nothing verifies. In `shared/`: `PhoneField` and `genericErrorCopy` moved out
of `features/auth/` on their third consumer, and `AppTextField` gained
`requirement`, which draws the Required/Optional pill every delivered form uses
and appends the word to the spoken label.

🔧 **The QA contract review found nine defects and all nine are addressed** —
`docs/decisions/20-phase-6a-become-a-provider.md` §8 lists them. Two were
behavioural: resume could reach step 3 with the email still unverified, which
would have shown a provider "you're all set" while the server said otherwise
(now `_resumeStep` returns step 2, making it the single client-side home of
that rule), and tapping the step's own **Verify email** button emptied the
form, because Phase 3's screen finishes with `pushNamedAndRemoveUntil` back to
the root — the typed values now go through `FormDraftStore`, Phase 3's own
in-memory mechanism for the same class of problem.

🔧 **One consequence has no owner yet, and it is `P6A-3`.**
`providerOnboardingComplete` is **not monotonic**: five of its inputs are
legally editable, so a provider who later clears a bank field or removes their
last account-level island reads incomplete and is routed back into a flow whose
terminal CTA hands off to a *fresh* draft. Correct for someone who never
finished, wrong for someone already trading — and unanswerable here, because
`PublishedListingSource` is a seam until Phase 8. Latent today: nothing outside
this flow edits those fields. Whichever of Phase 9 or Phase 10 first ships a
surface that can must decide the rule.

Ledger rows **P6A-1** (Home's CTA, Phase 16), **P6A-2** (that the handoff opens
a genuinely fresh wizard draft, Phase 9) and **P6A-3** (above). **P6-1's
onboarding half is closed** — the switcher's first switch now lands on the real
intro screen — and it stays open for Phase 10's dashboard half.

**Phase 8 is built** — service listings, backend only.
`/v1/providers/me/listings` carries draft-save, the per-step PATCH, publish,
provider visibility, soft delete and the three-step media upload;
`/v1/listings/:id` is deliberately **unclaimed**, so §Phase 12's Service
Preview and §Phase 15's search can define the public shape rather than
inheriting one that switches on who is asking. `docs/decisions/21-phase-8-service-listings.md`
carries the full record.

**Almost every column on `Listing` is nullable, and that is the requirement**
(invariant 2): a draft saves with an empty body, and only publish enforces
the **six** required fields — name, category, short description, one island,
a pricing model with its price, and the cover image §0.2 item 4 added.
Publish returns the missing ones as a structured list carrying the wizard
step each belongs to, so §Phase 9's review screen can render a Fix link per
row and its "N required fields left to publish".

**The cap is enforced at publish and at un-hiding, never at draft creation** —
v1's bug was the reverse. `ProviderEntitlementReader.activeListingCap` is the
seam §Phase 8a fills; it returns §1b's free tier of 1, which is not a
placeholder while no `ProviderSubscription` table exists. The refusal carries
its own code so §Phase 9 can show an upgrade prompt rather than a generic
error, and `COUNTS_AGAINST_CAP` is an **alias** of `PUBLICLY_VISIBLE_LISTING`,
not a second copy — the set the cap counts and the set the public sees can
never drift apart.

**§1c's emergency rule lives in one function** called by publish, update and
the tier-drop re-evaluation. The Done-when's own case is asserted: one
`silver` provider, refused on Electrical (`gold`) and accepted on AC Repair
(`silver`) — a pair a boolean gate or a hardcoded `silver` would answer
identically.

**Media is three steps because a presigned PUT means the server never sees
the bytes.** Validation and EXIF stripping happen in a finalise step that
reads the object back, sniffs its real type, strips it and rewrites it at the
same key — identical for a local directory and for S3, so the swap is a
transport change. `MEDIA_STORAGE=file` copies §0.0 item 17's whole posture
including its production refusal, which leaves production unbootable until
the bucket lands. That is the honest signal: unlike push, nothing carries a
cover image if the store does not.

🔧 **Five answers arrived from the plan mid-build** (revision 5.25,
commit `382d2c0`), and three changed the build: no `Category.priceUnits`
(reverted after being built), `Category.suggestedTags` **is** this phase's
column and is seeded from the prototype's twelve-category `TAGS` map, and a
media row gained `hiddenByAdminAt` because `photo` is a `Report.targetType`
and §1d makes moderation reversible. The category seed **recomputes**
`suggestedTags` on every run — the island seed's pattern, safe here because
§Phase 10b's editable Category fields do not include it, and necessary
because the twelve rows already existed.

**A defect the tests caught:** the count rollup's window was
`(watermark, now]`, so an event stamped at exactly the previous run's
watermark was lost forever. It is `[watermark, now)` now, with the boundary
pinned by its own test.

Ledger row **P5-1 is closed** — the seam is implemented over the real table,
the predicate is folded into one query and the batch loop is gone. **P7-3 is
half advanced**: the two service-area tables are separate and proven not to
touch each other, and what still needs §Phase 15 is that the island *filter*
reads the listing's set. New rows **L13** (a real object store), **P8-2**
(cascade rules against real bookings, reviews and slots) and **P8-3** (the
tier-drop re-evaluation wired to Phase 10a, with its notification); **P8-1**
is the plan's own row for the unbuilt per-category `priceUnit` narrowing.

**Phase 8a is built** — subscription and trial, backend only.
`/v1/providers/me/subscription` carries the status, the trial, the pause and
the upgrade request; `/v1/providers/me/payment-submissions/:id/{proof,submit}`
carry §1b's proof upload; `/v1/providers/me/invoices` carries the PDFs; and
`/v1/admin/payment-submissions` carries the queue with confirm, reject and
reverse, all audit-logged.
`docs/decisions/22-phase-8a-subscription-and-trial.md` carries the full
record.

🔧 **Six answers arrived from the plan before the schema landed** (revision
5.28), and two changed the build. **The 7-day job prompts and does not start
a trial** — §Phase 8a's "all three call `startTrial`" is superseded, because a
trial is one per account and firing it when no booking has landed spends it
when premium is worth least. **The introductory-rate conversion is a fifth
scheduled job**, since §1b requires it and no other phase owns it. The other
four confirmed what was proposed: premium's listing cap is **unlimited**
(`null` in the DTO, meaning no limit and never unknown), the
`acceptingNewCustomers` toggle **is** the pause, RaajjePro's own bank details
are typed config required in production, and **the appeal action is not
built** (ledger row **P8A-1** says why).

**`getProviderEntitlements` is the single source of tier truth** — one live
read of two columns, never cached, and structurally unable to see
`payment_submission`, so a `pending` payment cannot grant anything. A missing
row is the free tier rather than an error, `expired` **is** §1b's grace period
and still carries premium, and `free` is the downgrade. 🔧 **It reads the
stored status and does not recompute it from the dates** — the lifecycle job
advances the state, as `backend/CLAUDE.md` requires, so there is one
implementation rather than two that could disagree.

**Downgrade and restore are one function.** `applyEntitlementVisibility`
reconciles a provider's live listings against their current cap, so §1b's
"upgrade restores exactly what downgrade hid" is a property of one code path
rather than an agreement between two. Protected listings — a committed future
job — fill the cap first and stay visible regardless of it; among the rest the
highest performer survives, ranked over §1b's 90 days and tie-broken on
`firstPublishedAt` rather than the gameable `updatedAt`.

**One pause, two doors.** §1b's "pause keys off the `acceptingNewCustomers`
toggle" is literal: `ProviderProfileService` gained a listener that §Phase 8a
registers, and the billing endpoints write the toggle *through* that service.
At the ten-day cap the clock resumes and **the toggle is left alone** —
whether a provider takes work is theirs to decide. 🔧 The counter is
`cumulativePausedMinutes` where §Phase 8a's field list says days, because a
whole-day counter lets a 23-hour pause round to zero and repeat forever; the
API still speaks in days, spent rounded up and remaining rounded down.

**The invoice PDF is written, not imported** — one page of Helvetica, no
dependency, and checked with `pdftotext` as well as by its own test, which is
what caught an em dash rendering as `?`. Non-Latin text is not representable
and degrades to `?`; Thaana is out of v1 scope. A confirmation reserves the
number and stores the bytes **before** its transaction, so a storage failure
aborts the confirmation instead of committing an invoice with no document, and
two admins confirming at once get one 200 and one 409.

Three jobs on the Phase 0 runner, all hourly: `subscription-lifecycle` (the
warning, expiry → grace, grace → downgrade, the win-back pair, the forced
resume and the over-cap reconcile, in one pass per row),
`subscription-trial-prompt` and `subscription-introductory-conversion`. Every
notification is stamped so an hourly job sends it once.

**A defect the tests caught:** the reversal derived `status` from the
rolled-back dates but left `tier` alone, so reversing a provider's only
payment left them premium for another seven days on a payment that never
arrived.

New ledger rows **P8A-2** (the booking seam: the confirmed-booking trigger and
the downgrade protection, both against `FakeBookings`), **P8A-3** (that a
provider is actually told — `BillingNotifier` logs and drops until §Phase 19,
and two events have no §Phase 19 type at all) and **P8A-4** (the pause
consequence in the toggle's own copy, which is a design round's).
**P8A-1** is the plan's own row for the unbuilt appeal.

**Phase 9 is built** — the Create/Edit Service Wizard, seven steps behind
`/services/new`, wired to `/v1/providers/me/listings`.
`docs/decisions/23-phase-9-service-wizard.md` carries the full record.

**The offline queue is built once, in `core/offline/`, and it holds data
rather than closures.** `PendingRequest` is `{method, path, body,
idempotencyKey, mergeKey}`, which serialises — so a step survives not only a
dropped connection but Android reclaiming the app, because the queue is
written to a file and picked up on the next launch. Three rules, each tested:
a refused write is recorded **before** the caller is told anything; once
anything is queued later writes queue *behind* it rather than overtaking it;
and a **server** refusal leaves the queue and surfaces where the user can see
it, because retrying it forever would never succeed. Ten offline keystrokes
merge into one PATCH on the `mergeKey`. §0.0 item 14 bounds who may use it —
this phase, §Phase 17.1's accept prompt and §Phase 18's chat sends, and the
emergency accept **never**, which the class comment says and gives the reason
for. **Publish is not queued either**: telling a provider their service is
live when the request never left the device is a lie.

🔧 **"Never blocked" and "blocked until persisted" are about different gates.**
Validation never blocks — Review is reachable from step 1 with nothing typed,
and a step still missing a field gets an amber dot, not a lock. Persistence
delays: `goTo` flushes the pending autosave first and Continue reads "Saving
this step…" while it does. Offline that wait is instant, which is why the save
pill's third state is **"Saved offline" and never "Not saved"** — an edit the
queue accepted *is* saved, and saying otherwise makes a provider retype work
that was never lost.

**A server response is adopted only when nothing newer has been typed.** One
counter, captured before the request goes out; if it has moved, only the save
pill changes and the next PATCH brings the derived fields. This also decides a
test rule worth knowing: a fake PATCH that replies with the original draft
*undoes* every edit, and the wizard faithfully adopts it — the harness's
`scriptEchoingPatch` behaves like the server instead.

**The server decides; the wizard renders.** Step 5 prints
`listing.emergency.reason` verbatim and compares no tier to any bar, and the
response window is `category.emergencyAcceptWindowMinutes` — **a null window
drops the sentence rather than printing a default**. `publish_gate.dart`
mirrors the six-field rule for the header's counter only (invariant 4); when
publish is refused, the review step renders the **server's** list. The two
refusal codes stay two screens: `LISTING_INCOMPLETE` is a Fix row per field,
`LISTING_CAP_REACHED` is the upgrade prompt, which says the draft is safe
before it says anything else.

**Step 2's pre-fill is a copy made once, at creation** — `POST` the draft,
read `GET /v1/providers/me`, `PATCH` the island **ids** onto the listing. That
is what makes it happen exactly once: a provider who clears every island does
not find them silently restored. It is client-side because §Phase 8's
`createDraft` does not do it and its Done-when does not ask it to.

🔧 **`image_picker` is a new dependency and is deliberately not deferred.**
Every other platform boundary here ships as a seam with nothing behind it
because the vendor is procured at deployment — the photo library is not a
vendor, and the cover image is one of the six required fields, so a wizard
that cannot reach a photo cannot satisfy "a service can be created
end-to-end". It sits behind `core/media/media_picker.dart`; the presigned PUT
is its own seam and deliberately does **not** go through `ApiClient`.

🔧 **Three things moved into `core/` and `shared/` on their second consumer**,
which `lib/README.md` calls the convention rather than a refactor:
`CategoryApi`/`CategoriesController` out of `features/explore/`,
`CircleBackButton` out of `features/auth/`, and a new `prefix` slot on
`AppTextField` for the price field's "MVR" chip.

**Ledger row P6A-2 is closed** — the handoff now opens a genuinely fresh
draft and step 2 pre-fills from the account-level service areas, both asserted
through the real route table. **No new rows**: every Done-when line was
testable now.

**Phase 9a is built** — availability rules, exceptions, provider time off,
the generated slot grid and reservations, backend and Flutter.
`docs/decisions/24-phase-9a-availability-and-reservations.md` carries its full
record, including the one exception to invariant 8 (§0.0 item 18) and why
double-booking is prevented by a PostgreSQL exclusion constraint scoped to the
provider rather than by a service method.

**Phase 10 is built** — My Services, the provider's workspace, plus the one
piece of backend §1b's override needed.
`docs/decisions/26-phase-10-my-services-dashboard.md` carries the full record.

**`/provider/services` is a real screen, and ledger row P6-1 closes with it.**
§Phase 6's role switcher has pointed at that route since it was built and
found an `UnbuiltScreen` there; `phase10_done_when_test.dart` now drives the
real app through the switcher and asserts both branches in one place — a
provider who completed onboarding lands on the dashboard, one mid-flow still
goes back into onboarding.

🔧 **§1b's over-cap override is a pin, not a visibility the provider writes.**
This is the phase's only backend work and the thing to know about it:
`hidden_over_cap` is set and cleared **only** by the entitlement system
(§1b, Round 17), so "make this one live instead" cannot be the two-step
hide-then-activate that `PATCH …/visibility` would allow — that writes
`hidden_by_provider` onto a listing the system hid, and silently breaks "any
confirmed payment restores everything" for the listing swapped out.
`ProviderProfile.keepVisibleListingId` is a **ranking input**:
`POST /v1/providers/me/listings/:id/keep-visible` sets it,
`applyEntitlementVisibility` reads it itself — not as a parameter, because
four callers have to honour it and a parameter is what three of them
eventually forget — and ranks it ahead of §1b's bookings → views → recency.
A stale pin holds nothing: it is promoted only if it is already in the ranked
set, so a pin on a draft, a deleted listing or one the provider hid themselves
simply does not match. `docs/decisions/25-phase-10-two-questions-answered.md`
is the verification session's reading that settled it before the build.

**"No manual refresh" is a property of the mutations.** Every context-menu
action adopts the listing the server hands back rather than re-listing: the
live toggle flips optimistically and rolls back **visibly** on the refusal
that actually happens (a second listing live on the free tier), Remove drops
the row the server will not return again, and only returning from the wizard
refreshes — silently, because a skeleton over a screen already on display
reads as a bug. The one exception is the override, which re-reads because the
server has also changed a *second* listing and which one is §1b's ranking to
decide.

🔧 **Four departures from the artboard, all recorded.** The stats tile reads
**"Live"** rather than "Published" — its number counts published-and-active
and "Published" is a filter pill directly beneath it, so one word would be
doing two jobs on one screen. The live toggle keeps a constant "Live" label
instead of flipping to "Off", because `AppToggle` already announces its state
and a flipping label makes a screen reader say "Off, off". The card carries no
star rating (no `Review` until §Phase 11, and a blank star on your own listing
reads as *nobody rated you*). And **the card is a container, not a button** —
it was built tappable first, and `Pressable` wraps its child with
`excludeSemantics: true`, so a tappable card erases the menu, the toggle and
Finish & publish from the semantics tree. The artboard's card is not tappable
either.

**Three things moved into `core/` on their second consumer**, which
`lib/README.md` calls the convention rather than a refactor: `ListingApi` and
`ServiceListing` into `core/listings/`, `customerPricePreview` into
`core/listings/listing_money.dart` — §Phase 9 shows it as *what the card will
say*, which is only a promise if one function says it — and `relativeEdit`
beside `relativeAge` in `core/format/`, whose first rung is "active now":
right about a session, wrong about an edit.

**No new ledger rows.** Every Done-when line was testable now and is tested.
**P6-1 closes**; **P8A-4 is updated rather than closed** — the dashboard
renders no `acceptingNewCustomers` toggle (the artboard draws none and
§Phase 10's bullets ask for none), so §1b's pause sentence is owed by
§Phase 10a's billing screen alone.

**Phase 10a part 1 is built** — the provider's billing surface: Billing &
subscription, Pay by bank transfer, and Invoices, plus the backend that half
of the phase needed. `docs/decisions/27-phase-10a-part-1-provider-billing.md`
carries the full record.

🔧 **Part 2, the admin panel, was not built — the owner paused it on
2026-09-15.** So **§Phase 10a is still open**, and §Phase 10b does not start
off the back of this. Four of its six Done-when clauses are Part 2's and
nothing here asserts them: an admin confirming, the CSV import's matches, the
three XSS payloads, and the aged `payment_unresolved` alert. Ledger row
**P10A-1** holds them. The two that are Part 1's are met end to end through
the real route table.

**An appeal is a re-review request, and ledger row P8A-1 closes.** §1b step 5
offers a rejected provider "resubmit immediately — no cooldown — or **appeal
for re-review**", and no section said what an appeal *changes*; the answer,
settled by the owner, is **nothing about the payment**.
`POST /v1/providers/me/payment-submissions/:id/appeal` stamps `appealedAt` and
an optional note on the **rejected** row, the status is untouched, the
entitlement is untouched, and Part 2's queue lists it as appealed. One per
submission; a reversal is appealable too; resubmit and appeal are independent.
**P8A-4 closes with it** — the pause card carries the sentence it owed: the
pause is the same switch as `acceptingNewCustomers`, the ten days do not
refill, and the billing anchor moves.

🔧 **No billing rule is evaluated in Flutter, and two fields were added to the
server to keep it that way.** Round 19 (§Phase 23) makes that a build
requirement on this phase — a web port must cost a port, not a rewrite — and
invariant 4 says it anyway. `billing.nextPeriod` (the 30-day period the next
payment would buy) and `billing.graceEndsAt` are now on the wire, because the
artboards print both and §1b's anchor is **not** a calendar month and **pause
shifts it**: a period computed in Dart would drift from the invoice the first
time anyone paused. The quote and the confirmation share one function, and a
test pays the quoted period and reads the same dates back off the invoice.

🔧 **Nothing on the pay screen is queued offline.** `Pay by Bank Transfer.dc.html`
draws a "Saved on this phone — sends on reconnect" state; §0.0 item 14 bounds
the queue to three surfaces and a payment is none of them, and the copy is a
promise about money that nothing keeps. Offline the form stays as it was with
the receipt still attached and a live retry — the test asserts the absence of
that sentence, not only the presence of the notice.

**Three artboard claims were checked against the plan and not built**, and go
back as `docs/design/sessions/round-59-billing-corrections.md` rather than
being fixed in the prototype: "Same page on the web" (a web billing page
exists only as §Phase 23's App Store contingency), "a second person looks at
it" (second-admin sign-off is out of v1 scope by name), and `MVR 150` printed
beside the introductory rate (§1b: the price is per-provider and never a
global constant). 🔧 **A fourth correction came from the plan moving
mid-build**: revision 5.35's §0.0 item 19 makes a full bank-statement match
confirm **without a human**, so the copy no longer names the reviewer —
"Pending confirmation", not "Pending admin confirmation".

New ledger rows **P10A-1** (Part 2's half of the Done-when), **P10A-2** (the
invoice PDF from a real object store, sharing L13's blocker) and **P10A-3**
(the receipt picker and the presigned PUT on a device, which is P9-2's pass in
a second place).

**Phase 17.1 is built** — the core booking machine, §1c's payment attestation
and §1h's locked agreement, backend and Flutter.
`docs/decisions/28-phase-17-1-bookings.md` carries the full record.

🔧 **It was built out of the plan's numbered order, and §4 Sequencing allows
it.** The hard prerequisites §4 names for §Phase 17 are §Phase 3c, §Phase 9a
and §Phase 4's seed, and all three are built; §Phases 11–16 are not
prerequisites for any of them. What this does mean is that the booking flow's
*entry points* belong to phases that do not exist yet — §Phase 12's Service
Preview owns the way into `BookSlotScreen`, and §Phase 16's Home the way into
the Bookings tab — so today the flow is reached from §Phase 6's Profile tiles,
which is a real route rather than a placeholder.

**One slice, and the other three refuse by name.** `POST /v1/listings/:id/
bookings` answers `BOOKING_MODE_NOT_AVAILABLE` on a request-mode listing and
`accept` answers `EMERGENCY_USES_ITS_OWN_ACCEPT` on an emergency booking —
§0.0 item 15's own correction, at the endpoint rather than in a comment. The
`BookingStatus` enum carries all fourteen values including the three no 17.1
edge reaches, so §Phases 17.2 and 17.3 add rows to `transitions.ts` rather
than a migration each.

**The machine is a table of edges, checked twice.** Once in
`assertTransition`, and again by the database: every write carries the status
the booking was read at in its own `WHERE`, so two taps from two devices
resolve to one winner with no row lock. The actor is part of the edge because
§1f depends on it — a 24-hour auto-decline and a provider saying no are the
same status and different facts, and "timeouts feed response rate, not
acceptance rate" is only computable because the machine wrote down which.

🔧 **Which clocks are constants here, and which are never.** The three the
brief forbids hardcoding are per-category and appear nowhere in this slice:
`emergencyAcceptWindowMinutes` (17.3), `quoteExpiryMinutes` and
`quoteApprovalMinutes` (17.2) — the accept-timeout job's candidate query
excludes emergency bookings outright rather than trusting a later filter.
`windows.ts` holds only the set §1c states flat for every category: 24 hours
to accept, 7 days of payment silence, 7 days to the completion prompt and 3
more of grace.

**Payment attestation is two humans, and the copy never pretends otherwise.**
Nothing writes `PaymentSubmission` — a test asserts the count is unchanged —
and seven days of provider silence reaches `payment_unresolved`, not
`confirmed`, which is asserted by the *absence* of the trial hook and the
attestation stamp rather than only by the status. Round 24's withdrawal is
allowed once, only while unanswered, files no Report and moves no conduct
metric; both transitions stay in `statusHistory`.

🔧 **§1h's agreement is written on proposal, not on acceptance.** A rejected
attempt is as load-bearing as an accepted one — §Phase 11 counts proposals —
and accepting one that moves the time calls §Phase 9a's `reschedule` **inside
the same transaction**, so the provider is never both blocked at the old time
and free at the new. This is not §Phase 17 item 16's reschedule, which is
17.4's and is a different mechanism.

**Two seams filled, neither interface changed.** §Phase 3's `DeletionBlocker`
and §Phase 8a's `SubscriptionBookingSource` now answer over the real table,
and no caller in `modules/account/` or `modules/subscriptions/` moved — the
fifth time that pattern has held. They sit on the **repository** rather than
the service, because the service needs `subscriptions.onBookingConfirmed` and
routing both through it would be a cycle. Ledger rows **P2**, **P9A-1** and
**P9A-2** close; new rows **P17-1** (nobody is told yet — §Phase 19 owns
content), **P17-2** (the accept prompt on a real device) and **P17-3** (the
offline accept surviving a cold start) open.

🔧 **Two defects the phase's own tests found.** `BookingApi.list` parsed
`data` where `ApiClient` unwraps a list payload as `_list`, so My Bookings
would have been permanently empty against a perfectly good response — the
comment in `ListingApi.listOwn` saying exactly this has now earned its place
twice. And a class named `_RoleSwitch` in a file that calls `pushNamed` tripped
`no_booking_notification_toggle_test`'s grep; the guard is right, the name was
wrong, and two chips are not a switch.

**Phase 17.2 is built** — the request-with-quote path, backend and Flutter.
`docs/decisions/29-phase-17-2-quotes.md` carries the full record.

**Nine of the twelve categories become bookable.** 17.1 refused request mode by
name; `createRequestBooking` opens it, and `bookableListing` routes by mode
instead — only `emergency` is still refused, which is §Phase 17.3's.

🔧 **A request booking is created at `awaiting_quote`, not `requested`.** §1c
says both — step 1 puts every mode on `requested`, the machine section inserts
`awaiting_quote → quote_offered → accepted` — and nothing in the plan or the
screens could move `requested → awaiting_quote`, so reading step 1 literally
leaves a status the plan puts in its own machine permanently unreachable. It is
also the state the booking is genuinely in: a provider owes a *quote* on the
category's clock, where a slot booking owes an *accept* on the flat 24 hours.

🔧 **The conflict this slice had to resolve, and the one thing 17.1 shipped
that it changes.** §1c step 4 says the request accept window is a flat 24
hours; Round 15's table says 2 hours for the six household trades, seeded as
`quoteExpiryMinutes`, and `Request a Time.dc.html` promises exactly that to the
customer — *"Ibrahim has 2 hours … if he doesn't, the request expires and you
owe nothing."* The artboard and Round 15 win (§0.0's precedence rule; step 4
was edited by Round 15 for its *approval* clause and its *quote* clause was
left behind), and otherwise a seeded, documented column would have had no
reader anywhere. `findAcceptTimeouts` now sweeps `bookingMode: 'slot'` alone —
it read `['slot','request']` while no request booking could exist to be found,
and 17.1's 24-hour Done-when clause is untouched for the only mode that could
meet it. The long-lead three are unaffected: their `quoteExpiryMinutes` is 1440.
**The plan needs the edit, not the code** — `docs/design/sessions/
round-60-quote-screen-corrections.md` §4 carries it back.

**Both quote clocks are stored, not recomputed.** `quoteDueAt` and
`quoteExpiresAt` are written from the category at the moment each promise is
made, so an admin editing §Phase 10b's config moves the *next* request's
deadline and never one a customer is already watching count down. The
provisional hold's `expiresAt` is the same instant as `quoteExpiresAt` — §1c's
"expiring with the quote's approval window" as one value written twice.

🔧 **A customer declining a quote lands on `cancelled`, never `declined`.** §1f
computes acceptance rate as "accepted ÷ (accepted + declined) — explicit
responses only", which measures the *provider*; a customer turning down a price
would otherwise count against the one who answered promptly and quoted
honestly. An unanswered approval window is `cancelled` with `cancelledByRole`
**null** — nobody cancelled, a clock ran out — and §1f counts neither.

**The hold lives and dies in the quote transaction**, the property 17.1 proved
for the firm hold, asserted both ways: an already-taken time leaves the booking
at `awaiting_quote` with no half-quote on screen, and a forced failure *after*
the hold leaves no hold. Its length is the one number the plan does not give —
`REQUEST_HOLD_MINUTES = 120`, recorded in decision 29 §3 rather than buried,
because a zero-length `tstzrange` overlaps nothing and would hold nothing.

**Round 27's chat state is derived, and the thread is §Phase 18's.** 17.2 owns
the state (`chatState`: `not_open` / `open` / `locked`, from `quoteOfferedAt`,
`amountSetAt`, the status and `completedAt`) and asserts it flips at
`quote_offered` — one whole state before `accepted`, which is the point of the
clause. New ledger row **P17-4**.

🔧 **A defect the phase found in 17.1's screen.** The provider accept prompt
guarded on `status != requested` and so showed "Already answered" for a request
booking nobody had answered; its countdown was the flat 24 hours, which would
have promised a plumber twenty-two hours they do not have. Both fixed — the
countdown now reads `quoteDueAt` for a request booking.

**Next**: `/phase-17-3` — emergency dispatch, offer collection and the reveal
endpoint. `/phase-10a` part 2 (the admin panel) is still paused by the owner,
and `/phase-11` is still unstarted.

| | |
|---|---|
| `01_Development_Plan_v5.md` | **The single source of truth**, revision 5.35. Every product decision. Read §0.0 first — it is a precedence rule |
| `CLAUDE.md` | Architectural invariants Claude must never violate. Loaded automatically |
| `docs/design/` | The design system: style guide, page briefs, session prompts, the plan for the rebuild |
| `mockups/design-composer/` | **61 working prototypes** — the current design reference |
| `mockups/*.jpg` | The seventeen originally-delivered screens. Provenance only; a prototype beats an image |
| `backend/` | TypeScript · Prisma 7 · PostgreSQL 18. Phases 0–2: Fastify under `/v1`, the envelope and error hierarchy, rate limiting, idempotency, admin identity with TOTP MFA, the audit log, and SES email with bounce handling. Phase 3: register/login, JWT sessions, email OTP, account settings, data export, the deletion pipeline and its job runner. Phase 3b: password reset. Phase 3c: `PushSender` and the transport boundary, device registration, the fallback chain, the two notification jobs and the admin message log. Phase 4: the category catalogue, its seed CLI and the admin CRUD behind `requireAdmin`. Phase 5: provider profiles, `getOrCreateProviderProfile`, §1a's `findVisibleProviders` gate and §1f's conduct read surface, both over seams Phases 8 and 11 fill. Phase 6: `profile-summary` and `PATCH /v1/users/me` on the existing account module. Phase 7: the island register and its seed, `ProviderServiceArea`, the public unpaged island search and the two provider service-area writes. Phase 6a: `providerType`, and the derived `isOnboardingComplete` that `profile-summary` and the own-provider read both answer from — no new endpoint. Phase 8: service listings under `/v1/providers/me/listings` — draft-save, the per-step PATCH, the six-field publish gate with the entitlement-cap seam, provider visibility, soft delete, per-listing service areas, the `MediaStorage` boundary with EXIF stripping, and the listing event log with its rollup job. Phase 8a: `ProviderSubscription`, the generic `PaymentSubmission` and `Invoice`; `getProviderEntitlements` filling Phase 8's cap seam, the two trial triggers and the 7-day prompt, the shared pause behind the `acceptingNewCustomers` toggle, §1b's downgrade/restore reconcile, the admin confirm/reject/reverse endpoints with their audit trail, the written PDF invoice, and three hourly lifecycle jobs. Phase 10: one column and one endpoint — `ProviderProfile.keepVisibleListingId` and `POST /v1/providers/me/listings/:id/keep-visible`, §1b's over-cap override as a ranking input that leaves `applyEntitlementVisibility` the only writer of `hidden_over_cap`. Phase 10a part 1: §1b step 5's appeal (`appealedAt`/`appealNote` and its endpoint, changing no status), and the quoted billing period and grace end on the subscription DTO so no billing arithmetic reaches Flutter. Phase 17.1: `modules/bookings/` — the `Booking`, `BookingStatusEvent`, `BookingAmendment` and §Phase 22's minimal `Report`; the edge table every transition is checked against; slot creation inside one transaction with §Phase 9a's reservation; §1c's payment attestation with Round 24's withdrawal; §1h's amendments, which move the hold with the time; disputes and the admin resolution that reaches §Phase 8a's trial hook from either door; three scheduled jobs on §1c's flat clocks; and the two seams §Phases 3 and 8a built against, filled. Phase 17.2: the request-with-quote path — request creation at `awaiting_quote` with §1c's window chips resolved server-side against the Maldives day, `quote` / `approve-quote` / `decline-quote`, the provisional hold taken and released inside the quote transaction, both quote clocks stored from the category, two more sweep jobs, and `chatState` derived for §Phase 18 |
| `frontend/` | Flutter 3.47, Android + iOS, bundle id `mv.raajjepro.app`. Phases 0–1: the design system is in `lib/core/theme/` and `lib/shared/`, the gallery at `/gallery` (linked from Home in debug builds). Phase 3: Sign In, Register, Verify Email, Session expired, Account Settings and its sub-screens. Phase 3b: Forgot password. Phase 3c: the `PushMessaging` seam in `lib/core/push/` (no vendor SDK is a dependency) and the persistent enable-notifications reminder. Phase 4: Explore, its endpoint-driven grid and the inert chrome around it. Phase 6: Profile, the role switcher, `LegalIndexScreen`, and `UnbuiltScreen` for the routes later phases owe. Phase 7: `core/location/` and `shared/location/` — the reusable island multi-select, the header picker sheet, and the session-scoped browsing island. Phase 6a: `features/onboarding/` — Become a Provider's three steps, resuming from whatever the server says was finished. Phase 9: `features/service_wizard/` — the seven-step Create/Edit Service Wizard, `core/offline/`'s queue-and-replay, `core/media/`'s picker and presigned-PUT seams, and `shared/states/no_connection_view.dart`. Phase 10: `features/my_services/` — the My Services dashboard at `/provider/services`, and `core/listings/`, where the listing API, model and price string moved on their second consumer. Phase 10a part 1: `features/billing/` — Billing & subscription, Pay by bank transfer and Invoices, with every billing rule left on the server; `core/files/` and `core/format/money.dart`, moved there on their second consumer — `frontend/lib/README.md` lists every directory. Phase 17.1: `features/bookings/` — My Bookings and its filter pills, the booking detail with §Phase 17's status timeline, the payment step and the provider's receipt answer, mark-complete, "Did this happen?", cancel, report a problem, propose an amendment, the provider accept prompt with its 24-hour countdown and its offline queue, and `BookSlotScreen`, which is the rest of `Pick a Time`. Phase 17.2: `RequestTimeScreen`, `ProposeQuoteScreen` and `QuoteReceivedScreen` — the quick-pick window chips, the provider's time and price in one action, and the customer's countdown to a deadline the server gave it |
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

## Do not judge motion on the emulator

Measured on 2026-09-14, after an hour of chasing a sheet animation that
"wasn't smooth". It was smooth. The emulator cannot paint fast enough to show
it, and every cheap way of checking that lies to you.

**The numbers**, from Flutter's own timeline on a **profile** build:

| | median | what it means |
|---|---|---|
| `Animator::BeginFrame` (UI thread) | **0.4 ms** | the app's build and layout cost nothing |
| `GPURasterizer::Draw` (raster thread) | **12.3 ms** | painting one frame, ~25–40× a real phone |
| interval between frames | **55 ms** | ≈18 fps, which is exactly what "not smooth" looks like |

So the app produced frames in 0.4 ms and the emulator took 12.3 ms to paint
each one. `-gpu host` changes nothing — the bottleneck is the emulated GL
path, not which renderer is picked.

**Two ways of measuring that do not work:**

- **`screenrecord`.** It caps at ~14 unique fps on this emulator regardless of
  what is on screen. A continuous fling — which Flutter renders at 60 fps by
  definition — measures the same ~14 fps as a janky animation, so the number
  tells you nothing. A recording is still useful for *what* is drawn (it is
  how the sheet's see-through bug was found); it is worthless for *how fast*.
- **`dumpsys gfxinfo`.** Reports `Total frames rendered: 0` for a Flutter app.
  It measures the HWUI pipeline, which Flutter bypasses entirely.

**What does work:**

```bash
# Build first, with nothing competing — an AOT build starves the emulator.
cd frontend && flutter build apk --profile --dart-define=API_BASE_URL=http://10.0.2.2:3000
# Then start the device, then attach without rebuilding:
flutter run --profile -d emulator-5554 --use-application-binary=build/app/outputs/flutter-apk/app-profile.apk
```

That prints a VM service URL. `curl "$VS/getVMTimeline"` returns the real
`Frame`, `Animator::BeginFrame` and `GPURasterizer::Draw` events with
durations. Note the ring buffer is short — capture immediately after the
interaction, and expect only a handful of frames.

**And the honest answer: use a phone.** The profile APK installs on one, and
it is the only place the question can actually be settled. Everything above is
how to avoid spending an hour finding that out again.

## One rule that overrides everything

Where anything disagrees with `01_Development_Plan_v5.md`, **the plan wins and the disagreement gets flagged, not silently resolved.** Five times a decision was reversed in the plan and survived in a copy of it. Every single time the plan was right and the copy was wrong.
