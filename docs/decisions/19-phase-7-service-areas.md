# Phase 7 — Service Areas & Location Module

Built 2026-09-10 against `01_Development_Plan_v5.md` §Phase 7 and §0.0 item 12.
What follows is what was decided during the build and why, in the order the
decisions were forced. The plan is the source; this file is the record of the
places it left a choice.

---

## 1. Scope: §Phase 7 only, and Saved Preferences is reattributed

`HANDOVER.md` and ledger row **P6-2** both said Saved Preferences belonged to
Phase 7. §Phase 7 does not: its three bullets are the island seed, the join
table with its two endpoints, and the two frontend controls, and its Done-when
names neither a saved address nor a preferred window. Saved Preferences is a
**§Phase 3** account-settings bullet that Phase 3 deferred because it needs
`Island`.

**Decision: build §Phase 7 as written, and correct the two repository documents
rather than the plan.** Building it here would have meant inventing the entity
shape (labelled addresses, preferred time windows, standing instructions) and
its endpoints, which no section of the plan specifies — and §Phase 7's own
instruction is to say so rather than fill the gap. After this phase the island
picker exists, so the screen is buildable by whichever phase takes it.
`HANDOVER.md` and P6-2 now say Phase 19b, alongside the other Profile rows
whose screens are still owed.

Confirmed with the product owner before starting.

---

## 2. The island register is read, not transcribed

`docs/data/inhabited-islands.json` is the ministry extract — 192 inhabited
islands, 20 atolls, verified by two independent parses. `seed-data.ts` **reads
that file** rather than holding a TypeScript copy of it.

A `seed-data.ts` array of 192 entries beside a JSON file of 192 entries is two
copies of the same list, and §Phase 7's instruction is explicitly not to
re-derive it. The path is resolved from the module's own URL, which lands on the
same repository root from `src/` and from `dist/`; `ISLAND_REGISTER_PATH`
overrides it, which is how the seed test seeds a fixture. The file is validated
with Zod on read, because a hand-edit that dropped an `abbr` would otherwise
seed 192 islands whose ambiguous names could never be qualified.

**The category seed keeps its TypeScript literal** and was not changed. Its
numbers are the plan's own decisions, argued line by line in
`categories-seed.test.ts`; the island list is an external register. The two are
different kinds of data and it is right that they load differently.

---

## 3. Ambiguity is computed twice over, and from the database

§0.0 item 12 requires the ambiguous set to be computed at seed time from the
case-folded, apostrophe-stripped name. Two refinements the plan does not spell
out, both load-bearing:

**Normalising before grouping finds 16 groups where the raw string finds 15.**
The plan says this and the data confirms it: `K. Vilingili` and
`GA. Vilin'gili` are different strings, so an exact-match grouping flags
neither, and a customer typing "Vilingili" then sees two identical-looking rows.
`islands-seed.test.ts` asserts both numbers by computing them a second way, so
the test cannot pass by agreeing with the implementation.

**The recompute runs over the whole `island` table, not over the register
file.** Search answers from the database, so what makes two names
indistinguishable is two *rows* sharing a normalised name — including a row an
earlier register carried and this one does not. Computing from the file alone
would leave such a pair rendering one qualified name and one bare one, which is
the exact failure the rule exists to prevent.

**A register spelling correction creates a second row and does not merge.**
`seedKey` is `"<atollAbbr>:<name>"`, so a corrected name is a new key. Left as
it is rather than guessed at: reconciling two spellings is an identity decision
a person makes, and the superseded row is deactivated through Phase 10b. The
seed reports it as a creation rather than doing it silently.

---

## 4. `GET /v1/islands` is deliberately unpaginated

`backend/CLAUDE.md` makes pagination mandatory on any endpoint that can return
an **unbounded** set, and the Phase 4 category list took a cursor for exactly
that reason. This endpoint does not, and the two are not in conflict:

- §0.0 item 12 states the opposite requirement as a **product rule** — every
  match, no cap, no "show more", because truncating hides the one island the
  customer came for.
- The set is closed. Islands come from a government register, and this phase
  adds no endpoint that creates one. 192 rows is the whole table.

Where the catalogue can grow by an admin action, the register cannot. The cap
would be the defect here, not the absence of one.

---

## 5. `displayName` is the server's, and the client never rebuilds it

The qualifying rule — `Dh. Meedhoo` where the name is shared, `Kulhudhuffushi`
where it is not — is applied once, in `toIslandDto`. Flutter's `Island` carries
`nameAmbiguous` but never composes the string from it.

A client-side copy would be a second implementation of a rule the plan states
once, and it would drift the first time an island's ambiguity changed under a
build that had already shipped. The same reasoning keeps **matching** on the
server: the app sends what was typed and draws what came back, and re-sorting
or trimming the response is asserted against in `island_search_list_test.dart`.

---

## 6. No `GET` on the service-areas collection

§Phase 7 names `POST` and `DELETE /v1/providers/me/service-areas`. A picker
still has to read the current set, so the read went to the endpoint that already
exists: **`GET /v1/providers/me` carries `serviceAreas`**, additively. One new
field rather than one new URL, and both writes return the resulting list in
full, so a client's view is exact after every change without a second request.

Deliberately **not** on `PublicProviderDto`. §Phase 8 gives a listing its own
service areas and those are what discovery matches on; this is the provider's
account-level default, and a customer reading it would be reading a coverage
claim no listing has to honour.

---

## 7. No idempotency key on the add

`backend/CLAUDE.md` asks for one on every creation POST so that a retry cannot
leave two rows. Here the unique `(providerProfileId, islandId)` pair gives that
guarantee **at the database**, which is stronger than replaying a stored
response: a retry converges on the one row whatever key it carries, or none.
Requiring a key would also have put friction on a control a provider taps once
per island. `service-areas.test.ts` asserts the convergence directly.

Removing an island stamps `removedAt` (invariant 8) and re-adding revives the
same row. Removing an island that is not a service area succeeds and changes
nothing — the client's view is allowed to lag, and there is nothing to protect
by turning that into an error.

---

## 8. Adding a service area creates the provider profile; removing one does not

The same split, and the same reasoning, as `PATCH /v1/providers/me` (§1a):
saying which islands you work on is unambiguously acting as a provider, so the
add calls `getOrCreateProviderProfile`. There is nothing to remove from an
account that has never been a provider, so the delete answers
`PROVIDER_PROFILE_NOT_FOUND` rather than quietly making one — `isProvider` is
`providerProfile !== null` and nothing is ever hard-deleted, so a profile
created by a stray DELETE would be permanent.

---

## 9. The island list grows; it does not nest a scroller

`IslandSearchList` has two shapes, and the **default is the growing one**: the
list renders at full height and the parent scrolls it. `maxHeight` opts into the
other, where the list scrolls inside its own cap — what the bottom sheet needs.

This is not a preference. A scrollable list nested inside a scrolling page
swallows the drag meant for the page: the component gallery stopped 200 px short
of its own last section, and the button below the island list became
unreachable. §Phase 9's wizard step 2 embeds this widget in a scrolling form, so
the default had to be the safe one. The gallery's a11y sweep is what caught it,
which is the second time that suite has paid for itself.

---

## 10. Three departures from the prototypes, each deliberate

**A visible "Search islands" label** where `Home.dc.html` and
`Create Service.dc.html` show a placeholder-only field. A placeholder
disappears the moment a customer types, and this control is reused inside a
sheet, a wizard step and a form.

**`AppTextField` gained `autofocus`** — flagged rather than done silently,
because it is shared Phase 1 code. The picker opens as a sheet whose whole
purpose is to be typed into; 192 islands is not a browsable list, so raising the
keyboard is the difference between one tap and two. Off by default, and it must
stay off anywhere a screen merely *contains* a field.

**The prototypes' "Sample list — the live app has every inhabited island"
footnote is not implemented.** It exists to explain a 19-island stand-in. There
is no stand-in here, and §0.0 item 12 forbids an island total in UI copy, so the
line has nothing left to say.

---

## 11. The browsing island is in memory, and nothing defaults it

§Phase 7's Done-when says the choice "persists for the **session**".
`BrowsingIslandController` holds it in Riverpod's root container: it survives
navigation, backgrounding and sign-in, and goes when the process does. It is
deliberately not written to secure storage or shared preferences — a browsing
island that survived a reinstall would quietly filter a customer's whole first
screen against somewhere they used to be.

**Null is a real state, not a missing one.** Nothing defaults to Malé, and the
pill names the action ("Island") rather than asserting a location. Picking an
island the customer has not mentioned is the same class of mistake as
auto-selecting a lone search match, and §0.0 item 12 forbids the second by name.

Nothing consumes the choice yet beyond the header label. §Phase 15's search and
§Phase 16's Home feed are what read it for real.

---

## 12. Phase 4's island tripwire was deleted, which is what it was for

Explore drew the island pill wrapped in `InertControl(owedBy: 'Phase 7')`, and
`explore_chrome_test.dart` asserted it did nothing. Both are gone, replaced by
`phase7_done_when_test.dart` driving the real screen: the pill opens the sheet,
a pick closes it and names the island, and the choice survives a round trip
through Profile and back.

---

## 13. What the gallery gained, and what it cost

`GalleryScreen` now has an **Island picker** section — the only place §Phase 7's
"works standalone against real API data" is exercisable by hand, because the
widget is not screen-specific and no screen owns it until Phase 6a.

Two consequences, both in Phase 1 files and both flagged:

- `gallery_a11y_test.dart` pumps a `ProviderScope` with a faked API. The gallery
  was Riverpod-free until it gained its first data-driven specimen.
- The gallery's own `ListView` is keyed. The sweep scrolls by finding one by
  type, which became ambiguous, and tree order is not something a test should
  depend on.

The island section sits **before** the bottom-sheet section, because the sweep
scrolls to the bottom and then reaches for "Open a sheet".

---

## 14. The seed CLI was renamed

`src/cli/seed-categories.ts` → `src/cli/seed.ts`, and `npm run db:seed` now
bootstraps categories **and** islands. A second script was considered and
rejected: one command has to leave a checkout with all its reference data, and a
`db:seed` that quietly did half the job would surface several phases later as an
empty island picker.

---

## What Phase 8, 9 and 6a inherit

- **`IslandMultiSelect` is built and standalone.** §Phase 9's wizard step 2 and
  §Phase 6a's third step embed it; neither needs to build a picker.
- **A listing's own service areas are §Phase 8's**, keyed on `islandId`. The
  `ProviderServiceArea` table here is account-level and is the **default** that
  pre-fills the wizard (§Phase 6a step 3), not the thing discovery matches on.
- **Nothing may key on an island name** — not a service area, not a booking
  location, not a filter. The DTO carries `id` first for that reason.
