# The island list

`inhabited-islands.json` — **192 inhabited islands across all 20 administrative atolls.**

## Where it came from

Extracted 2026-09-01 from the Ministry of Fisheries and Agriculture's atoll register at `atollsofmaldives.gov.mv`, filtered to category **(I) Inhabited**. The same source also carries Resort (313), Uninhabited (553), Picnic, Proposed Resort, Industrial and Historical islands — 1,124 records in total — none of which RaajjePro needs. A service marketplace delivers to where people live.

This closes the input the redesign plan flagged as the one thing only the product owner could supply. It is not yet wired into anything: it is data on disk, ready for the Phase 4 / Phase 7 seed.

## The finding that changes the design

**Island names are not unique.** Fifteen names occur in more than one atoll, and **Meedhoo exists in three** — Dhaalu, Raa and Seenu. Others include Hithadhoo (Laamu, Seenu), Guraidhoo (Kaafu, Thaa) and Feydhoo (Seenu, Shaviyani).

### The display rule

**Qualify an ambiguous name with its atoll code, in the Maldivian convention: `Dh. Meedhoo`, `R. Meedhoo`, `S. Meedhoo`.** Each atoll carries its standard code in `abbr` — `HA`, `HDh`, `Sh`, `N`, `R`, `B`, `Lh`, `K`, `AA`, `ADh`, `V`, `M`, `F`, `Dh`, `Th`, `L`, `GA`, `GDh`, `Gn`, `S`. This is how Maldivians already write an address, so it reads as normal rather than as a disambiguation artefact.

An unambiguous name stands alone: `Kulhudhuffushi`, not `HDh. Kulhudhuffushi`. Prefixing all 192 was considered and rejected — it adds a code to 177 names that never needed one.

**Derive the ambiguous set from the data, never from a hardcoded list.** At seed time, group islands by their **case-folded, apostrophe-stripped** name and qualify every name whose group has more than one row. `duplicateNames` below records today's fifteen exact-name collisions for reference and as a test fixture; it is not the mechanism. If the register gains or loses an island the rule must follow it on its own — that is the conditional rule's one real risk, and computing it removes it.

**Normalise before grouping, or you miss one.** On the raw strings there are 15 collisions. On the normalised form there are **16**: `K. Vilingili` and `GA. Vilin'gili` are different names, so neither is flagged by an exact-match grouping — but search is apostrophe-insensitive by the rule below, so a customer typing "Vilingili" sees both and cannot tell them apart. Grouping on the raw name would leave that one pair broken in exactly the way the rule exists to prevent.

### The rest of the consequence

1. **Never key on a name.** `Island` needs its own UUID like every other entity (invariant 8). A `serviceArea` storing `"Meedhoo"` is ambiguous across three atolls and will silently mis-route bookings.
2. **The atoll travels with the island everywhere** — picker, chip, address line, booking record, provider service area. A screen that resolves the ambiguity at selection time and then stores or displays the bare name has not fixed anything.
3. **Search must disambiguate rather than guess.** Typing "Meedhoo" returns all three to choose between; it never auto-selects, even when exactly one island matches.

### Search behaviour

192 entries is not a scrollable list, so search is the control rather than a filter over one. From the first character typed it matches **anywhere** in the name (`dhoo` → Kudahuvadhoo, Fonadhoo, Rasmaadhoo…), ranks prefix matches first, also matches the atoll code (`dh mee`, `dhmee` → `Dh. Meedhoo`; `gdh` alone lists that atoll), ignores case, **accents** (`male` must find `Malé`) and apostrophes on both sides, and **returns every match with no cap and no "show more"** — truncating results hides the island the user came for. A native `<select>` is not an acceptable island control anywhere.

## Other data notes

- **Apostrophes are meaningful.** `An'golhitheemu`, `Kan'duhulhudhoo`, `Kon'dey` — the apostrophe transliterates a Thaana glottal. Preserve it in stored values, and make search match with **and** without it, or a customer typing "Angolhitheemu" finds nothing.
- **Trailing apostrophes**: `Male'` and `Hulhumale'` carry one. Stripping it produces a different, wrong name.
- **Source typos were cleaned.** Several entries carried a trailing full stop (`Dhihdhoo.`, `Nilandhoo.`, `Meedhoo.`, `Feydhoo.`, `Goidhoo.`); these were stripped on extraction. No other edit was made to any name.
- **No total is quoted anywhere.** This register counts 192; the Discovery prototype had said "of 187 inhabited islands", a figure predating this extraction. Rather than pick between them, the denominator was dropped — a customer looking for their island does not need the total, and it is one more number that goes stale silently. Do not reintroduce a count in UI copy.
- **Malé City.** `Male'`, `Hulhumale'` and `Vilingili` are listed under Kaafu here. Administratively they are Malé City; if that distinction matters for search or addressing, it is a product decision, not a data one.
- `Vilingili` (Kaafu) and `Vilin'gili` (Gaafu Alifu) are different islands whose names differ by one apostrophe — see the normalisation note above.

## Verification (2026-09-01)

The list was re-derived a second time by a different method — parsing the register's own `/atolls/<atoll>/<island-(CAT)>/<id>` link structure rather than the page text — and produced **the identical 192 across the identical 20 atolls**. Two independent parses agreeing rules out an extraction error.

Three things that turned up in the process:

- **25 records carry no category code at all** (mostly Gaafu Dhaalu reefs — `Hakandhoo`, `Kaafarataa`, `Dhimmanaa`…). None is an inhabited island, so none affects this list.
- **41 IDs are absent from the register's own sequence** (max ID 1163, 1122 records present). These are gaps on the source side, not dropped rows.
- **`Male'` is recorded as `Male'(I)[H]`** — square brackets instead of parentheses. It parsed correctly, but it is the sort of one-off that a stricter parser would silently drop.

**Per-atoll counts were cross-checked against a second source** for five atolls. Four match exactly: Haa Dhaalu 14, Shaviyani 14, Meemu 8, Gaafu Dhaalu 9 (Faresmaathodaa present in both).

**One unresolved discrepancy: Raa.** The register lists 15 inhabited islands; the second source lists 16, the extra being **R. Maamin'gili**, which the register classifies as `(R)` — a resort. One of the two is wrong and it has not been settled. Everything else agrees.

### Islands that are correctly absent

Several islands that were inhabited within living memory are not on this list, and that is right rather than a gap:

- **HDh. Faridhoo, HDh. Maavaidhoo, Sh. Maakan'doodhoo, Sh. Firunbaidhoo** — depopulated under the population-consolidation programme. Maakan'doodhoo and Firunbaidhoo were merged into **Sh. Milandhoo**, which is on the list.
- **R. Kadholhudhoo** — destroyed in the 2004 tsunami; the population moved to **R. Dhuvaafaru**, which is on the list.
- **L. Gaadhoo** — depopulated.
- **M. Madifushi** is a resort. The inhabited Madifushi is **Th. Madifushi**, which is on the list.

Anyone auditing this list against memory will reach for these first. They were each checked.

## Names the register does not carry

`islands-prototype-array.js` is generated from the JSON and holds the same 192 in the display form the prototypes use — 33 prefixed, 159 bare. Regenerate it if the seed changes; never edit it by hand.

**One known alias gap.** The register calls Kaafu's island `Vilingili`; locally it is **Villimalé** (Villingili). Search on the register name alone means someone typing "Villimalé" finds nothing. The same will be true of any island with a common alternate name. Aliases are not modelled here and are worth a decision before the seed lands — the register name is authoritative for identity, but it is not always what a customer types.

## Re-extracting

The register is a server-rendered page: the full list is in the DOM of the search page, not behind an API. Parse lines of the form `Name (CAT) - [ Traditional Atoll (Code Atoll)]`, taking the first parenthesised group that matches a known category code — some entries carry an alternate name in parentheses first (`Beenaafushi (Bibeerah) (U)`) and others carry airport/harbour codes after (`Fuvahmulah (I) (ADF,H)`).
