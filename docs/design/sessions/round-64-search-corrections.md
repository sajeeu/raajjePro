# Round 64: corrections to Search and Category results

Raised while building **§Phase 15** (search and discovery) against Search
results and Category results in `Discovery.dc.html`. The items below are
things a structural check cannot see. `docs/decisions/36-phase-15-search.md`
§4 has the reasoning.

Change only what is named. Everything else on these screens was built as drawn.

---

## 1. Draw the Filters sheet

The Price, Mode and Category chips and the filters button (`allFilters`)
open nothing: each toasts. The owner approved this sheet on 2026-10-10. Draw
it as one bottom sheet, opened by all four:

- **Header**: `Filters`, and a text button `Reset` on the right.
- **CATEGORY** (on Search results only, never on a category's own results):
  `Chip kind="filter"` chips that wrap: `Any`, then the twelve categories.
- **PRICE (MVR)**: two inputs side by side, `Min` and `Max`, digits only.
  Under them in 12.5 / 600 / `#5B6B84`: "Price-on-request services are hidden
  while a price is set." If Max is below Min, the Max field shows the error
  "Max must be at least the min" and the primary button is disabled.
- **HOW YOU BOOK**: `Any`, `Pick a time`, `Request a time`.
- **Maldivian-owned business**: a toggle row with the note "Verified at
  Gold".
- **Primary button**: `Show 14 services`, a live count of what the choices
  would show, or `Show services` while counting.

A chip opens the sheet scrolled to its own section, and the filters button
opens it at the top. Nothing applies until the button is pressed, and
dismissing the sheet discards the choices. Do **not** add preset price bands
(numbers nobody decided), an emergency option or a verification-tier option.

## 2. The category empty state makes no growth claim

`resEmptyCat`'s body opens "Providers join every week". The product cannot
promise that on launch day.

**Change** the body to: "Most categories are still filling in island by
island. Try another island, or browse everything on offer today."

**Change** `catEmptyTitle`: drop the Plumbing special case. Every category
reads `No <Category> providers on <island> yet`, or `No <Category> providers
yet` when no island is chosen.

## 3. The filtered-out empty state names the filters, not the reason

The sample body explains "services on Hulhumalé currently start above MVR
300". Nothing computes that.

**Change** it to name the filters only: "‘Under MVR 300’ and ‘Hulhumalé’ are
filtering everything out. Try removing one."

---

## Built as drawn — do not "fix"

- Sort: `Distance`, `Rating`, `Price`, in that order, with Distance first.
  Distance is island-relative: listings that serve fewer islands rank first.
  Never label it in kilometres or as "nearest".
- Sponsored results lead the list and carry the `Sponsored` pill.
- "Show 12 more", the skeleton cards, "Results didn't load" with "Nothing was
  filtered out — this is a loading problem.", and the removable filter chips
  above the filtered-out empty state.
- The Island chip opens the shared island sheet. It reads `Island` until one
  is chosen, and nothing defaults to Malé.
- The query pill returns to Explore with the same words, ready to edit.
