# Round 30 — the island list is real, and island names are not unique

**Status: adopted as Round 30 (2026-09-01). Plan revision 5.16.**

## What arrived

`docs/data/inhabited-islands.json` — **192 inhabited islands across 20 atolls**, extracted from the Ministry of Fisheries and Agriculture's atoll register and filtered to category (I). This is the seed input §Phase 4 calls for and the redesign plan had flagged as the one thing only the product owner could supply. It replaces six placeholder islands in five prototypes.

## What it changed

**Names are not identifiers.** Fifteen island names occur in more than one atoll; `Meedhoo` exists in three. The placeholder lists hid this completely — they were six distinct names, so a bare name looked sufficient.

Two of the placeholders were themselves ambiguous and nobody noticed: `Discovery` offers `Hithadhoo` (Laamu **and** Seenu) and `Become a Provider` offers `Guraidhoo` (Kaafu **and** Thaa). A provider selecting one of those today is selecting nothing determinate.

## The display rule

**Qualify an ambiguous name with its atoll code in the Maldivian convention — `Dh. Meedhoo`. Leave an unambiguous one bare — `Kulhudhuffushi`.**

Qualifying *all* 192 was the alternative, and it is the more defensible engineering answer: one rule, no conditional. It was declined because it puts a code on 177 names that never needed one, and because the prefix form is how a Maldivian address is already written — `K. Malé`, `HDh. Kulhudhuffushi` — so it reads as ordinary rather than as a disambiguation artefact. Applying it only where it does work keeps that.

**The conditional's risk is real and is handled by computing it.** A hardcoded list of fifteen goes stale the moment the register changes, silently, in the direction of ambiguity. So the set is derived at seed time by grouping on the name and qualifying any group with more than one row.

**Group on the normalised name, not the raw one.** Case-folded and apostrophe-stripped, there are **16** groups, not 15. The extra one is `K. Vilingili` / `GA. Vilin'gili` — two different islands whose names differ by a single apostrophe. Exact-match grouping flags neither, but search is apostrophe-insensitive by the rule below, so a customer typing "Vilingili" gets both with nothing to tell them apart. Grouping on the raw string leaves that pair broken in precisely the way the rule exists to prevent.

## The rest of it

- **`Island` carries a UUID** like every other entity (invariant 8). No `ProviderServiceArea` row, booking location or search filter stores or matches on a name.
- **The atoll travels with the island everywhere** it is shown — picker, chip, card, address line, booking record. Resolving the ambiguity at selection time and then displaying the bare name fixes nothing.
- **Search is the control, not a filter on it.** 192 entries cannot be scrolled. From the first character, search matches anywhere in the name, ranks prefix matches first, also matches the atoll code (`dh mee` → `Dh. Meedhoo`), and returns **every** match with no cap — a truncated result list hides the island the user came for. It never auto-selects, even on a single match, because three islands are called Meedhoo. A native `<select>` is not an acceptable island control anywhere; the two screens still using one (`Saved Preferences`, `Emergency Flow`) change to the searchable sheet, the emergency one most urgently.
- **Search matches with and without the Dhivehi apostrophe.** `An'golhitheemu` ≡ `Angolhitheemu`, `Kon'dey` ≡ `Kondey`. Without this a customer typing the name as they would say it finds nothing. Trailing apostrophes (`Male'`, `Hulhumale'`) are part of the name and are not stripped from stored values.
- **No island total in UI copy.** `Discovery` had said "of 187 inhabited islands"; this register counts 192. Rather than adjudicate between a census figure and an administrative register, the denominator goes away — it is trivia to someone searching for their own island, and a number that goes stale silently is worse than no number.

## Not decided here

`Male'`, `Hulhumale'` and `Vilingili` sit under Kaafu in the register but are administratively Malé City. Whether search and addressing should reflect that is a product question, not a data one, and is left open.
