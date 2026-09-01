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

192 entries is not a scrollable list, so search is the control rather than a filter over one. From the first character typed it matches **anywhere** in the name (`dhoo` → Kudahuvadhoo, Fonadhoo, Rasmaadhoo…), ranks prefix matches first, also matches the atoll code (`dh mee`, `dhmee` → `Dh. Meedhoo`; `gdh` alone lists that atoll), ignores case and apostrophes on both sides, and **returns every match with no cap and no "show more"** — truncating results hides the island the user came for. A native `<select>` is not an acceptable island control anywhere.

## Other data notes

- **Apostrophes are meaningful.** `An'golhitheemu`, `Kan'duhulhudhoo`, `Kon'dey` — the apostrophe transliterates a Thaana glottal. Preserve it in stored values, and make search match with **and** without it, or a customer typing "Angolhitheemu" finds nothing.
- **Trailing apostrophes**: `Male'` and `Hulhumale'` carry one. Stripping it produces a different, wrong name.
- **Source typos were cleaned.** Several entries carried a trailing full stop (`Dhihdhoo.`, `Nilandhoo.`, `Meedhoo.`, `Feydhoo.`, `Goidhoo.`); these were stripped on extraction. No other edit was made to any name.
- **No total is quoted anywhere.** This register counts 192; the Discovery prototype had said "of 187 inhabited islands", a figure predating this extraction. Rather than pick between them, the denominator was dropped — a customer looking for their island does not need the total, and it is one more number that goes stale silently. Do not reintroduce a count in UI copy.
- **Malé City.** `Male'`, `Hulhumale'` and `Vilingili` are listed under Kaafu here. Administratively they are Malé City; if that distinction matters for search or addressing, it is a product decision, not a data one.
- `Vilingili` (Kaafu) and `Vilin'gili` (Gaafu Alifu) are different islands whose names differ by one apostrophe — see the normalisation note above.

## Re-extracting

The register is a server-rendered page: the full list is in the DOM of the search page, not behind an API. Parse lines of the form `Name (CAT) - [ Traditional Atoll (Code Atoll)]`, taking the first parenthesised group that matches a known category code — some entries carry an alternate name in parentheses first (`Beenaafushi (Bibeerah) (U)`) and others carry airport/harbour codes after (`Fuvahmulah (I) (ADF,H)`).
