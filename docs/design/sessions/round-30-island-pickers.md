# Round 30 — the real island list, and why a bare island name is now a defect

The island list the prototypes have been standing in for finally exists: **192 inhabited islands across 20 atolls**, from the government atoll register. It carries one fact the six placeholders hid completely, and it makes a bare island name wrong everywhere it appears.

**Island names are not unique.** Fifteen names occur in more than one atoll, and **`Meedhoo` exists in three** — Dhaalu, Raa and Seenu.

Two of the placeholders already in these files are among the fifteen, which is how invisible this was:

- `Discovery` offers **Hithadhoo** — that is Laamu *and* Seenu.
- `Become a Provider` offers **Guraidhoo** — that is Kaafu *and* Thaa.

A provider setting their service area to "Guraidhoo" today has selected nothing determinate, and the booking goes to whichever one the code happened to pick.

---

## 1. The display rule

**Qualify an ambiguous name with its atoll code, in the ordinary Maldivian form. Leave an unambiguous name bare.**

```
Dh. Meedhoo          R. Meedhoo          S. Meedhoo
K. Guraidhoo         Th. Guraidhoo
L. Hithadhoo         S. Hithadhoo
Kulhudhuffushi       Maafushi            Thulusdhoo        Fuvahmulah
```

This is how a Maldivian address is already written, so it should read as normal, not as a warning. **Do not prefix every island** — 177 of the 192 need no code and adding one makes the list noisier for no gain.

The twenty atoll codes: `HA` `HDh` `Sh` `N` `R` `B` `Lh` `K` `AA` `ADh` `V` `M` `F` `Dh` `Th` `L` `GA` `GDh` `Gn` `S`.

**The prefix is part of the label, not a separate badge or chip.** One string, one weight, same colour as the rest of the name. It is not metadata to be styled — a customer reads "Dh. Meedhoo" as the island's name.

## 2. The sample list every picker should use

Replace the placeholder arrays with this set. It is deliberately built so the rule is visible on screen rather than described in a comment — three same-named islands, two ambiguous pairs, and unambiguous names alongside them:

```
Malé
Hulhumalé
Maafushi
Thulusdhoo
K. Guraidhoo
Th. Guraidhoo
Dh. Meedhoo
R. Meedhoo
S. Meedhoo
L. Hithadhoo
S. Hithadhoo
Kulhudhuffushi
Fuvahmulah
Kudahuvadhoo
```

Applies to the island lists in **`Discovery`**, **`Home`**, **`Create Service`**, **`Become a Provider`**, **`Saved Preferences`** and **`Emergency Flow`**. Keep each screen's selection model as it is — multi-select where it is multi-select, single where it is single. The data, the label and the search behaviour in §3 are what change.

## 3. Search behaviour — every picker, spelled out

The list is 192 long. Scrolling is not a way to find an island, so **search is the primary interaction and the list is the fallback**, not the other way round.

**From the first character typed, show every match. All of them.**

- **Match anywhere in the name, not just the start.** Typing `dhoo` returns Kudahuvadhoo, Rasmaadhoo, Fonadhoo and the rest — someone who remembers the end of a name deserves the same help as someone who remembers the start.
- **Rank names that start with the query first**, then the rest alphabetically. `mee` puts the three Meedhoos at the top, Hangnaameedhoo below them.
- **No cap and no "show more".** If a single character matches sixty islands, the sheet renders sixty and scrolls. Truncating a search result silently hides the island someone is looking for, which is the one thing this control must never do.
- **Ignore apostrophes on both sides.** `angolhi` finds **An'golhitheemu**; `an'golhi` finds it too. Ignore case and leading/trailing spaces the same way.
- **Match the atoll code as well as the name.** `dh. mee`, `dh mee` and `dhmee` all find **Dh. Meedhoo**. Typing an atoll code alone — `gdh` — lists that atoll's islands.
- **Never auto-select and never pre-highlight a single result.** Even when exactly one island matches, the customer taps it. Three islands are called Meedhoo; a picker that guesses is worse than one that asks.
- **Empty query shows the full list**, scrollable, unchanged from how each screen shows it today.
- **No match** gets a plain line — `No island matches "{query}"` — and nothing else. No suggestion, no "did you mean".

Show the search field **focused and with a query typed** in at least `Discovery` and `Create Service`, with the filtered result visible beneath it. A picker screenshotted at rest does not demonstrate any of the above.

## 4. `Saved Preferences` and `Emergency Flow` — the native `<select>` has to go

Both currently render the island list inside a native `<select>`:

- `Saved Preferences` — the **Island** field on the saved-address form
- `Emergency Flow` — the **Island** field under the street address

With four placeholder options that was reasonable. With 192 it is a scroll-hunt with no search at all, and in `Emergency Flow` it sits on the one screen where someone is dealing with a burst pipe. It is the worst control on the most time-critical path in the product.

**Replace both with the searchable island picker the other screens already use** — the tap-to-open sheet with the search field at the top, single-select, closing on choice, showing the chosen island in the field. Match `Discovery`'s sheet, which is the closest existing pattern.

`Emergency Flow` keeps everything else about that step exactly as it is: same position under the address, same validation, same error treatment, same one-screen flow. Only the control changes.

## 5. Delete both "placeholder list" notices

They were honest while the list was pending and are now false:

- `Create Service` — the amber note reading *"This is a placeholder list — the full island directory is still being added."*
- `Saved Preferences` — the amber note reading *"Placeholder islands — the real island list is pending."*

Remove the notes and their containers entirely. Nothing replaces them.

## 6. `Discovery` — drop the island total

The sheet footer currently reads:

> Showing {{ islandShown }} of 187 inhabited islands — keep typing to narrow

The register counts 192, not 187, and rather than swap one number for another **the denominator goes away**. Make it:

> Showing {{ islandShown }} — keep typing to narrow

A customer looking for their own island does not need the total, and a hardcoded count in UI copy goes stale silently. Do not reintroduce an island count anywhere.

## 7. Pick one spelling of Malé and use it everywhere

The files currently contain **three** forms across six screens: `Hulhumalé`, `Hulhumalé'` and `Malé`. `Hulhumalé'` is a hybrid — the `é` and the trailing apostrophe are two romanisations of the same final vowel, so writing both double-marks it.

**Use `Malé` and `Hulhumalé`** — accented, no trailing apostrophe — in every screen, card, chip and address line. (The seed data stores the register's `Male'` / `Hulhumale'`; the display form is a presentation choice and this fixes it to one.)

Note that the Dhivehi apostrophe *inside* a name is different and always stays: `An'golhitheemu`, `Kon'dey`, `Vilin'gili`.

## 8. Wherever a single island is shown

`ServiceCard`, `Service Preview`, `Provider Profile`, `Booking Request`, `Pick a Time`, `Request a Time` and `Components` each render one island name next to a pin icon. Those follow the same rule — if the name is ambiguous it carries its atoll code, if not it stands bare. Use a qualified example in at least one of them (`Th. Guraidhoo` on a card) so the pattern is demonstrated at card scale and not only inside the pickers.

---

## Leave alone

- Every picker's existing **selection** model — multi-select chips, the selected-count line, sheet open/close behaviour, empty states. §3 changes what the search *returns*, not how selection works
- `Discovery`'s sort order and filters, `Home`'s location bottom sheet, `Create Service`'s step-2 layout and its required-field framing
- `Become a Provider`'s three-step flow and the account-level default-service-area framing
- `Saved Preferences`' single-island model — it stays one island, not many; only the control changes
- `Emergency Flow`'s step order, validation, timing copy and everything below the address block
- All wording outside the six items above
