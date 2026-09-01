# The island list

`inhabited-islands.json` — **192 inhabited islands across all 20 administrative atolls.**

## Where it came from

Extracted 2026-09-01 from the Ministry of Fisheries and Agriculture's atoll register at `atollsofmaldives.gov.mv`, filtered to category **(I) Inhabited**. The same source also carries Resort (313), Uninhabited (553), Picnic, Proposed Resort, Industrial and Historical islands — 1,124 records in total — none of which RaajjePro needs. A service marketplace delivers to where people live.

This closes the input the redesign plan flagged as the one thing only the product owner could supply. It is not yet wired into anything: it is data on disk, ready for the Phase 4 / Phase 7 seed.

## The finding that changes the design

**Island names are not unique.** Fifteen names occur in more than one atoll, and **Meedhoo exists in three** — Dhaalu, Raa and Seenu. Others include Hithadhoo (Laamu, Seenu), Guraidhoo (Kaafu, Thaa) and Feydhoo (Seenu, Shaviyani).

Three consequences, all load-bearing:

1. **Never key on a name.** `Island` needs its own UUID like every other entity (invariant 8). A `serviceArea` that stores `"Meedhoo"` is ambiguous across three atolls and will silently mis-route bookings.
2. **Never render a name alone.** Every island picker, chip, address line and booking record shows the atoll with it — `Meedhoo · Seenu`, not `Meedhoo`. The current prototypes show six placeholder islands with no atoll, which was fine as a placeholder and is wrong as a pattern.
3. **Search must disambiguate rather than guess.** Typing "Meedhoo" returns three results to choose between; it must never auto-select the first.

## Other data notes

- **Apostrophes are meaningful.** `An'golhitheemu`, `Kan'duhulhudhoo`, `Kon'dey` — the apostrophe transliterates a Thaana glottal. Preserve it in stored values, and make search match with **and** without it, or a customer typing "Angolhitheemu" finds nothing.
- **Trailing apostrophes**: `Male'` and `Hulhumale'` carry one. Stripping it produces a different, wrong name.
- **Source typos were cleaned.** Several entries carried a trailing full stop (`Dhihdhoo.`, `Nilandhoo.`, `Meedhoo.`, `Feydhoo.`, `Goidhoo.`); these were stripped on extraction. No other edit was made to any name.
- **The count is 192, not 187.** The Discovery prototype's island sheet says "187 inhabited islands" — a figure that predates this extraction and does not come from this source. Before seeding, confirm which number the product should quote; census-based counts and this register may legitimately differ, and the prototype's copy needs updating to whichever is chosen.
- **Malé City.** `Male'`, `Hulhumale'` and `Vilingili` are listed under Kaafu here. Administratively they are Malé City; if that distinction matters for search or addressing, it is a product decision, not a data one.
- `Vilingili` (Kaafu) and `Vilin'gili` (Gaafu Alifu) are different islands with near-identical names — a worked example of why 2 and 3 above are not optional.

## Re-extracting

The register is a server-rendered page: the full list is in the DOM of the search page, not behind an API. Parse lines of the form `Name (CAT) - [ Traditional Atoll (Code Atoll)]`, taking the first parenthesised group that matches a known category code — some entries carry an alternate name in parentheses first (`Beenaafushi (Bibeerah) (U)`) and others carry airport/harbour codes after (`Fuvahmulah (I) (ADF,H)`).
