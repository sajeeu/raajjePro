# Mockups

## What is here

`round-16-redraws.html` — the six screens Round 16 found diverging from the plan, corrected and rendered at phone width. **Reviewed and confirmed correct on 2026-08-13.** Open it in a browser.

These are the authoritative reference for the affected screens. Where they disagree with an original image file, these win — they were derived from the plan at revision 5.7, and §1 of the plan carries the divergence table that produced them.

| Screen | Correction |
|---|---|
| Explore | Boat Charter replaces Tuition |
| Wizard step 1 | Category grid corrected; tags become category-scoped chips |
| Wizard step 3 | Duplicate Price field removed; `priceUnit` added; Service Packages removed |
| Wizard step 5 | "Accepting New Customers" removed; Emergency Service tier-gated with reason |
| Wizard step 6 | Duplicate FAQs accordion removed |
| Service Preview | Three-tier badge; description matched to the listing |
| Home — trust card | "encrypted" claim replaced with what the system actually delivers |

Login needed no correction: **Apple sign-in was right** and the plan was amended instead, since App Store review requires it wherever third-party sign-in exists.

## What is missing

**The original image files are not in this repository.** The design set — Login, Register (customer and provider), Home, Explore, Profile, My Services, Service Preview, Bookings, Forgot Password, and the seven wizard steps — was reviewed from images pasted into a chat session and never landed on disk.

Phases 1, 9, 10, 12 and 16 are specified as pixel-match against these files. **Put them here before starting Phase 1**, keeping the filenames stable — phase commands reference them by path, and those references should not move.

Sixteen screens are expected. `§1 Mockup Inventory` in the plan lists them with their owning phases.
