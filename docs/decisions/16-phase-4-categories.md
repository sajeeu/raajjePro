# Decision 16 — Phase 4, the categories module

**Status: built 2026-09-09.** Backend catalogue, seed and admin surface; the Explore screen against it. Plan §Phase 4, §1c, §1d.

---

## What the plan settled, and what it left to this phase

§Phase 4 names the columns, the twelve rows and every number on them. Almost nothing here is a judgement call — the table in `backend/src/modules/categories/seed-data.ts` is a transcription, and `backend/test/categories-seed.test.ts` asserts it line by line against the plan rather than against itself.

Nine things the plan does not state were decided here. Each is recorded with its reasoning so the next reader does not have to reconstruct it.

### 1. The catalogue is keyed by UUID; `name` is unique but is not an identifier

Invariant 8 gives every entity a UUID and nothing references a category by name — listings, service areas and filters all take the id. `name` carries a unique constraint because two categories called "Plumbing" is a data defect, but that constraint is a guard, not an identity: the name is admin-editable and the bootstrap keys on `seedKey` instead (below).

This is not the island rule (invariant 15) in reverse. Island names genuinely repeat — fifteen of them across twenty atolls — so a name there is not even a candidate for a guard, let alone a key.

### 2. The seed keys on `seedKey`, and overwrites nothing

Two separate rules, and the first one was got wrong on the first pass — the QA review caught it.

**Create-if-absent, never overwrite.** Every number on a category is admin-editable from Phase 10b. A seed that upserted would quietly revert an admin's change on the next deploy, and the revert would be invisible — no audit entry, no notification, just a lead time back at 180. The test creates the situation directly: change Cleaning's lead time, re-run the seed, assert the change survived.

**Keyed on `seedKey`, not on `name`.** The first version recognised its own rows by name, which is wrong for exactly the reason Round 25 exists: a category's name is admin-editable and Computer really was renamed to Appliance Repair. Rename a seeded category in Phase 10b, deploy, and a name-keyed seed re-creates it under the old name — two active rows, two tiles in Explore, no error anywhere. `Category.seedKey` is written once by the bootstrap and never updated; it is null on anything an admin created, which the seed never touches.

The migration adds the column with **no backfill**. `seedCategories` instead adopts a row whose name matches a seed key and whose own key is still null, stamping it on the way past. That keeps the twelve names out of a migration file, where they would be a second copy of the seed table with its own way to drift.

Both are tested: rename Boat Charter, re-seed, assert one row survives under the new name and nothing was created; clear a seed key, re-seed, assert adoption stamps it and changes nothing else.

### 3. `DELETE` is a deactivation, and there is an admin list to undo it from

§Phase 4 asks for admin POST/PATCH/DELETE and does not mention a read. Invariant 8 makes DELETE a soft delete — it clears `isActive` — and invariant 1d requires moderation actions to be reversible. Without an admin read, a deactivated category is in the database and reachable from no endpoint, which makes the soft delete irreversible in practice and so no better than the hard one.

`GET /v1/admin/categories` therefore exists, returning inactive rows alongside active ones. It is the smallest addition that makes DELETE honest, and it is the read Phase 10b's config screen needs anyway.

### 4. Duplicate names are refused case-insensitively, in the service only

`Plumbing` and `plumbing` would render as two tiles. Postgres's unique index is exact-match, so the check lives in `findByName`, which compares case-insensitively.

That leaves a race: two admins creating differently-cased duplicates in the same instant would both pass the check. It is left open knowingly. A functional unique index on `LOWER(name)` would close it, but Prisma has no way to declare one, so it would show as schema drift on every subsequent `migrate dev` — a permanent false alarm on the migration tooling, traded against a race that needs two simultaneous operators on a surface that has one, and whose worst outcome is a cosmetic duplicate an admin fixes by renaming.

### 5. Two coherence rules, enforced in the service

Neither is in §Phase 4's field list; both come out of §1c and invariant 13, and both exist because a downstream module would otherwise read a null it has no defined behaviour for.

- **An emergency-capable category must carry `emergencyMinimumTier` and `emergencyAcceptWindowMinutes`, and a non-capable one must carry neither.** §1c's composed rule gates on the tier and dispatch runs on the window. A capable category missing either has no bar and no clock.
- **The two quote windows move together.** A quote that expires but can never be approved is not a configuration anyone meant.

Neither rule constrains *which* tier or *how many* minutes — those stay admin-editable, which is what §Phase 4 actually requires. On a PATCH the rules are checked against the row that *would* result, not against the patch: clearing `emergencyMinimumTier` is only invalid because the stored `emergencyCapable` is true, and the patch alone cannot say that.

### 6. Scalar lists where the plan says null

`emergencyEtaPresetsMinutes` and `occasionPresets` are Postgres arrays, and a Prisma scalar list cannot be null. The plan's "null elsewhere" is an empty array. No translation layer converts one to the other — a consumer checks `isEmpty`, and the two states the plan distinguishes ("no presets" and "presets not applicable") were never actually different.

### 7. Icon identifiers resolve to Material glyphs, not to the prototype's SVG paths

`Discovery.dc.html` draws each tile from a bespoke SVG path. This app has no SVG renderer, and Phase 1 built the entire design system on `IconData`. Twelve identifiers (`sparkle`, `droplet`, `bolt`, …) resolve through `CategoryIcons` to the closest Material glyph, with `Icons.category_outlined` for one this build has never seen — the same shape, and the same fallback discipline, as Phase 1's `CategoryAccents`.

Adding an SVG dependency for twelve glyphs was judged the worse trade. It is a real fidelity loss and is logged in `docs/design/explore-corrections.md` for the design project rather than settled silently.

---

### 8. The public list is paged, even though twelve fit in one page

`backend/CLAUDE.md` makes pagination mandatory on any endpoint that can return an unbounded set, and §Phase 4 says the catalogue is explicitly unlimited — so the rule applies however small the catalogue happens to be today. `GET /v1/categories` takes `limit` and `cursor` and returns `meta.nextCursor`, ordered by `(sortOrder, id)`: the cursor cannot key on the name, because a name can be renamed underneath a paging client.

The client follows the cursor to the end rather than reading page one and stopping, so a hundredth category does not silently vanish off the bottom of the grid. `CategoryApi.list()` bounds the loop at twenty pages — a server bug returning the same cursor forever would otherwise leave Explore on its loading state with nothing to show. `CategoryService.listAllPublic()` is the same walk for a downstream module, so Phases 8, 9a and 17 never have to think about paging.

A malformed cursor reads as "start from the beginning" rather than 500ing: it is an opaque client-supplied string and the page it names is public either way.

### 9. Audit actions are past tense

`category.created` / `category.updated` / `category.deactivated`, matching `admin.created` and `user.password.changed`. Phase 10b will filter the audit log on these strings, so the convention is cheap to hold now and a breaking change later.

---

## What makes "no rebuild" true rather than merely claimed

§Phase 4's first Done-when line is that a thirteenth category added through the API reaches Explore without a rebuild. Three things had to hold, and each has a test that fails if it stops holding:

- **Nothing validates a category name against a list.** `backend/test/categories-routes.test.ts` creates "Kayak Hire" and expects 201.
- **The client holds no fallback catalogue.** `CategoriesController` has no hardcoded twelve; `explore_screen_test.dart` feeds the screen two invented categories and asserts Plumbing is *absent*, which a screen with a compiled-in list could not pass.
- **An unknown colour token and an unknown icon identifier both resolve.** The thirteenth in the test carries `teal` and `kayak`, neither of which exists in this build, and the tile still draws.

The wire shape was checked against the running server rather than only against the fake: `GET /v1/categories` on a live instance returns exactly the sixteen keys `ServiceCategory.fromJson` reads, with the seeded values.

---

## The chrome around the grid

§Phase 4 asks for the Explore screen pixel-matched, and the prototype's Explore carries six controls whose destinations belong to later phases. The decision, taken with the product owner:

**Render the chrome, inert — except the emergency entry, which is absent.**

The island pill, search field, Saved heart and notification bell are drawn exactly as the prototype draws them and do nothing. Each is wrapped in an `InertControl` naming the phase that owes it a destination, and `test/features/explore/explore_chrome_test.dart` asserts each one is present *and* has no callback. That test is a tripwire, not documentation: when Phase 15 attaches search, it fails and has to be deleted deliberately.

**The "Something urgent? Get help now" entry is not rendered at all.** Round 23 removed the per-card emergency marker because it advertised an action that did not exist; a tappable emergency affordance that goes nowhere is the same error with a person on the other end of it. §Phase 16 owes the entry and Phase 17.3 the dispatch behind it, so omitting it now loses nothing that is not already owed.

The bottom nav is Phase 1's own component and is real, so its taps are real: a tab whose screen does not exist yet reaches `TabPlaceholderScreen`, which says so. Phase 16 replaces it with the tab shell. **This is the largest step outside §Phase 4's brief** — it ships four user-visible "not built yet" screens ahead of the phase that owns them — and it was a product decision taken deliberately, on the grounds that a nav tab which absorbs a tap silently is indistinguishable from a broken app.

The account avatar reads the signed-in account and shows a generic disc for a guest. It renders no tier overlay: wherever the overlay appears, the full `VerificationBadge` with its words has to be reachable on the same screen (Phase 1's rule), and Explore has nowhere to put them.

`test/features/explore/explore_geometry_test.dart` measures the chrome against the prototype **now**, while this session still holds the screen's context. Phases 7, 15 and 19 each replace one control here in a session that will not, and Sign In's seven layout defects — invisible to both a copy comparison and `flutter analyze` — are what that file exists to prevent happening twice.

---

## Two additive changes to Phase 1's `AppHeader`

Flagged rather than made silently (invariant 5). Neither changes existing behaviour and both are covered by the Explore tests.

- **`AppHeaderAction.onTap` is now nullable.** The disc renders exactly as it always did, inert, and reports itself disabled to a screen reader. It is not a "disabled" visual state and must never be used to grey a live control.
- **`AppHeader.brand` gained `trailingSlot`.** The account avatar sits after the actions on Home and Explore and is not a bordered icon disc, so it could not be an `AppHeaderAction`.

---

## One rule the plan states that this phase cannot enforce

§Sequencing's Round 15 follow-ups say the admin panel "refuses to change a category's mode once it has published slots or live bookings". `PATCH` accepts a `bookingMode` change unconditionally, because there is no `Listing` and no `Booking` for the check to read. Invariant 4 means the refusal has to be server-side when it lands, not an admin-UI control — so it is **ledger row P4** in `docs/deferred-verification.md`, closed by whichever of Phase 9a and Phase 17 lands second. The same question applies to deactivating a category that still carries live listings, and P4 names it.

---

## Deferred verification

**One row: P4 above.** Phase 4 touches no vendor and no external dependency; every Done-when line was testable in this phase and was tested. The one thing not exercised here is the Flutter app fetching from a live server on a device — the tooling for that is not on this machine, and it is verification work rather than a missing dependency.
