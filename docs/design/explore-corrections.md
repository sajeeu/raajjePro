# Explore — divergences from the prototype, and what closes each

**For whoever next holds `frontend/lib/features/explore/`, and for the design
project's next session on `Discovery.dc.html`.**

Written 2026-09-09 as Phase 4 built the screen. Every number is measured from
`mockups/design-composer/Discovery.dc.html` → Explore, in the prototype's own
412 dp frame. `test/features/explore/explore_geometry_test.dart` holds the
geometry that *does* match; this file is the list of what does not, and why.
Eight entries, not the seven an earlier draft carried.

Nothing below is a defect left lying. Each is a deliberate call with the
reason attached, and each names the thing that closes it.

---

## Divergences that close when a later phase lands

### 1 · The emergency entry is absent, not inert

**Prototype:** a full-width row under the search field — a 26 dp red-tinted
bolt chip, "Something urgent? **Get help now**" at 12.5/700, chevron.

**As built:** not rendered.

Round 23 removed the per-card "Emergency available" marker because it
advertised an action that does not exist — dispatch broadcasts and never
targets a provider. A tappable emergency affordance that goes nowhere is the
same error with a person on the other end of it: someone with water spreading
taps it and learns nothing happens.

**Closed by:** §Phase 16, which owes "Home and Explore each carry an action
that goes straight to the ASAP request"; Phase 17.3 builds the dispatch
behind it. Restore the prototype's row verbatim at that point —
`explore_chrome_test.dart` has a test asserting it is *absent* that must be
deleted then, on purpose.

### 2 · The error card does not say "Search still works"

**Prototype:** *"Your connection dropped while loading. Search still works."*

**As built:** *"Your connection dropped while loading."* — and, where the
failure was not a dropped connection, *"We couldn't reach RaajjePro just
then."* (the prototype has one error state; a server error and an offline
device are different facts and the copy says which).

Search does not work in this build. The field above the grid is inert until
Phase 15. A recovery instruction that does not recover is worse than no
instruction: it spends the reader's next action on a dead end at the exact
moment they are already stuck.

**Closed by:** Phase 15. Restore the second sentence when the field submits.
`explore_screen_test.dart` asserts the sentence is absent; delete that test
with the change.

### 3 · The empty state does not point at search either

**Prototype:** *"Categories are still loading for your region. Check back
shortly, or search directly for what you need."*

**As built:** *"No service categories are available right now. This is
usually temporary — try again in a moment."*

Two problems with the prototype's copy, only one of which is about this
build. The second clause points at the same inert field as #2. The first
clause — "still loading for your region" — is wrong on its own terms: this
state is reached when the endpoint returned an **empty list**, not while it is
loading (that is the skeleton), and categories are not scoped by region
anywhere in the plan.

**Closed by:** Phase 15 for the search clause. The "for your region" clause
should be dropped from the prototype outright — it describes behaviour the
product does not have.

### 4 · The island pill reads "Island", not "Malé"

**Prototype:** the pill shows a selected island, `Malé`.

**As built:** it names the action instead.

Phase 7 owns island selection and nothing has been selected. Showing `Malé`
would assert a location the app neither knows nor stored, and invariant 15 is
emphatic that an island is never keyed or defaulted casually.

**Closed by:** Phase 7, which wires the pill to the island search sheet and
gives it a real selection to show.

### 5 · Category tiles, the Saved heart, the search field and the bell do nothing

All four are drawn to the prototype and wired to nothing, each wrapped in
`InertControl` naming its owner: tiles and search → Phase 15, heart →
Phase 14, bell → Phase 19, account disc → Phase 6. `explore_chrome_test.dart` fails when any of them
is wired, which is how the owning phase learns the test exists.

---

### 6 · The header avatar is a generic disc for a guest, not initials

**Prototype:** a 36 dp accent-tinted disc reading `AN`.

**As built:** initials when someone is signed in; a person glyph on the same
36 dp disc when nobody is. Explore is browsable by a guest (§0.2) and there is
no name to take initials from.

**Closed by:** nothing — this is correct behaviour, and the prototype simply
draws its signed-in state. Noted so the difference is not read as a defect.
The disc is inert either way; **Phase 6** owes it the Profile destination.

---

## Divergences that are permanent, and belong to the design project

### 7 · The twelve category glyphs are Material icons, not the prototype's SVG paths

**Prototype:** a bespoke `<path>` per tile — a sparkle for Cleaning, a droplet
for Plumbing, a stylised AC unit, a sailboat.

**As built:** the closest Material glyph, resolved from the seeded
`iconIdentifier` through `lib/core/theme/category_icons.dart`.

The app has no SVG renderer, and Phase 1 built the whole design system on
`IconData` — `AppHeader`, `EmptyState` and `AnimatedBottomNav` all take one.
Adding a vector dependency for twelve glyphs, plus the asset pipeline it
implies, was judged the worse trade against a shape difference of a few
degrees at 22 dp.

Hue, tile geometry, chip size and label are unchanged. What differs is stroke
weight and outline shape, most visibly on **AC Repair** (Material's `air` is
three airflow lines where the prototype draws a unit) and **Home Repairs**
(`handyman` is crossed tools where the prototype draws a plane).

**For the design project:** if these should match exactly, the ask is a
Material-icon-compatible redraw of the twelve, not an SVG export — a
redrawn set can be swapped in behind the same identifiers with no code change.

### 8 · The header action disc is 40 dp, and the prototype's is 44

**Prototype:** `width:44px;height:44px` on the bell and the back control.
**As built:** `AppHeader`'s `_RoundAction` draws 40, with `Pressable`
supplying the 48 dp hit area around it.

**This is not Explore's number.** It is `AppHeader`'s, on every screen that
uses it, and it predates this phase — Phase 1 shipped it. Recorded here
because Explore is where it was measured, not because Explore should fix it.

**For whoever picks it up:** it is a one-line change in
`lib/shared/headers/app_header.dart` plus whatever layout tests measure the
header, and it should be made once for every screen rather than patched on
one. Flagged, not done — invariant 5.

---

## Two additive changes made to `AppHeader` by this phase

Not divergences, but the same reader needs to know.

- **`AppHeaderAction.onTap` is nullable.** An inert action renders identically
  and reports itself disabled. Never use it to grey a live control.
- **`AppHeader.brand` has a `trailingSlot`**, for the account avatar that sits
  after the actions on Home and Explore and is not a bordered icon disc.
