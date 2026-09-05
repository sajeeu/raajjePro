# Round 53 — seven colours that fail the contrast bar

Phase 1 built the Flutter design system from the measured tokens and ran every
text-on-surface pair through the WCAG AA check the plan makes non-negotiable
(§Phase 1: "WCAG AA contrast verified for all text and status colours —
amber-on-white in particular"). Seven measured values fail it. The app now uses
corrected values; this round brings the prototypes into line so the two agree.

**Leave alone:** every layout, radius, spacing, weight, size, animation and every
piece of copy. This round changes colour values only, and only the ones listed.
Every replacement is the next step on the same Tailwind scale the original was
drawn from, so nothing reads as a different hue.

---

## Why these seven

WCAG AA asks 4.5:1 for text and 3:1 for a graphic the user needs to read. The
numbers below are computed, not judged. `docs/decisions/08-phase-1-design-system.md`
has the full table and the reasoning; this is the change list.

---

## 1. Placeholder text — `#9AA9C0` → `#627187`

2.38:1 on white. Every input's placeholder, everywhere: `Components`, `Sign In`,
`Register`, `Become a Provider`, `Create Service`, `Home` search, the island
search sheets. The new grey is 4.96:1 on white and stays visibly lighter than the
`#5B6B84` secondary text, so a typed value still reads as different from a hint.

Icons that sit *inside* an input as decoration (the search magnifier on `Home`)
may keep `#9AA9C0`; they are not text and the field is labelled.

## 2. Warning as **text** — `#D97706` → `#A15C00`

3.19:1 on white. `StatusPill` already uses `#A15C00` for its amber label; this
round makes every other amber *word* match it — the "Still offline" line on
`App States`, any amber helper or caption. **`#D97706` stays** for the amber dot,
icon and star glyph, which are graphics and clear 3:1.

## 3. Success as **text** — `#16A34A` → `#166534`

3.30:1 on white. Same shape as §2: `StatusPill` already uses `#166534` for its
green label. Any other green *word* — a "Live — visible to customers" line, a
green caption — takes it. **`#16A34A` stays** for dots, ticks and icons.

## 4. Inactive bottom-nav label — `#8296B3` → `#5B6B84`

`BottomNav.dc.html`: the four inactive tabs' icon and 10.5 px label are
`#8296B3`, 3.02:1 on white. An inactive tab is a live control, not a disabled
one, so it is held to the text bar. `#5B6B84` is 5.41:1. The active `#1D4ED8`
and the `#E8F0FE` pill are unchanged.

`#8296B3` is otherwise kept — but **only on disabled controls** (the disabled
button text, the disabled input value). Anywhere it labels something live —
the 11.5 px helper under the `My Services` title, the uppercase captions on the
`Components` sheet — move to `#5B6B84`.

## 5. Rating stars — `Rate This Job.dc.html`

- Filled star stroke `#D99A1E` → **`#B45309`** (2.44:1 → 5.02:1). The fill
  `#F3B23E` is unchanged.
- Empty star stroke `#C6D4EA` → **`#8296B3`** (1.60:1 → 3.02:1).

The stroke is what tells a filled star from an empty one at a glance; at 2.4:1
and 1.6:1 it did not.

## 6. Home Repairs category icon — `#CA8A04` → `#A16207`

The only one of the twelve category glyphs under 3:1 on its own tint
(`#CA8A04` on `#FEFCE8` is 2.84:1). Yellow-700 `#A16207` is 4.76:1. The tint is
unchanged. `ServiceCard` `CATS['Home Repairs'].fg`, `Discovery`'s grid, and
`Create Service` step 1 all carry this value.

## 7. Category names set in the category colour — one step darker

`ServiceCard` (full variant) and anywhere else a category *name* is typed in
its accent hue. Two of the twelve fail as text on white — Electrical `#D97706`
(3.19:1) and Home Repairs `#CA8A04` (2.94:1) — and several more sit under 4:1.
Use the 700/800 of the same scale for the **word**; keep the 600 for the icon:

| Category | Icon (unchanged) | Label text |
|---|---|---|
| Cleaning | `#4F46E5` | `#4338CA` |
| Plumbing | `#059669` | `#047857` |
| Electrical | `#D97706` | `#92400E` |
| AC Repair | `#2563EB` | `#1D4ED8` |
| Beauty | `#DB2777` | `#BE185D` |
| Photography | `#EA580C` | `#C2410C` |
| Pest Control | `#16A34A` | `#15803D` |
| Appliance Repair | `#0284C7` | `#0369A1` |
| Moving | `#C2410C` | `#9A3412` |
| Fitness | `#7C3AED` | `#6D28D9` |
| Home Repairs | `#A16207` (§6) | `#854D0E` |
| Boat Charter | `#0891B2` | `#0E7490` |

The `Sponsored` and category pills on the horizontal card sit on 95% white and
use the same table.

---

## One more, for the record — the CTA gradient

`linear-gradient(135deg, #5B8DF6, #2563EB 60%, #1D4ED8)`: at the label's leading
edge white text sits on roughly 4.1:1. The app moved the middle stop to **40%**
so every point a centred label reaches is ≥ 4.5:1. The three colours are
unchanged and the difference is not visible side by side. Apply the same stop in
`motion.css`'s consumers and the button specimens on `Components` so the two
stay identical.

---

## Check before you finish

- `Components.dc.html` Text input placeholder is `#627187`; the Button and
  Status pill specimens are otherwise untouched
- `BottomNav.dc.html` inactive `fg` is `#5B6B84`
- `Rate This Job.dc.html` star strokes are `#B45309` / `#8296B3`
- `ServiceCard.dc.html` `CATS` carries a `text` colour per category and uses
  it for the category label; `Home Repairs.fg` is `#A16207`
- No `#8296B3` labels anything that is not disabled
- Nothing else changed: `python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html` still passes
