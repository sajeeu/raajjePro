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

## The files

All seventeen screens are here, committed 2026-08-13. Filenames are **as delivered** — reconciled against the inventory rather than renamed, except one typo fix noted below.

| File | Screen | Owning phase |
|---|---|---|
| `Login.jpg` | Sign In | 3 |
| `Register_customer.jpg` | Create account — Find Services | 3 |
| `Register_serviceProvider.jpg` | Create account — Offer Services | 3 |
| `ForgotPassword.jpg` | Forgot Password | 3b |
| `HomePage1.jpg` · `HomePage2.jpg` | Home feed — one screen, two captures | 16 |
| `Explore_services.jpg` | Explore — category grid | 4 |
| `Bookings.jpg` | My Bookings — Upcoming / Active / Completed | 17 |
| `Profile_customer.jpg` | Profile — customer | 6 |
| `Profile_serviceProvider.jpg` | **My Services dashboard** — not a provider profile, despite the name | 10 |
| `Service-full-post.jpg` | Service Preview — public listing | 12 |
| `Create_service_widget1.jpg` | Wizard step 1 — Details | 9 |
| `Create_service_widget2.jpg` | Wizard step 2 — Location | 9 |
| `Create_service_widget3.jpg` | Wizard step 3 — Pricing | 9 |
| `Create_service_widget4.jpg` | Wizard step 4 — Media | 9 |
| `Create_service_widget5.jpg` | Wizard step 5 — Availability | 9 |
| `Create_service_widget6.jpg` | Wizard step 6 — Extra Info | 9 |
| `Create_service_widget7.jpg` | Wizard step 7 — Review & Publish | 9 |

**Two names worth knowing about.** `Profile_serviceProvider.jpg` is the My Services dashboard, verified by opening it — a phase command that took the name at face value would attach the wrong screen. And `Explore seervices.jpg` was renamed to `Explore_services.jpg`: a space in a filename referenced from phase commands causes real friction, and the original also misspelled "services".

## These files are not correct as drawn

Seven divergences from the plan were found in Round 16 and confirmed in Round 18. **`round-16-redraws.html` is authoritative where the two disagree** — open it in a browser. Do not implement `Create_service_widget5.jpg` or `Explore_services.jpg` as delivered.

| Screen | Correction |
|---|---|
| `Explore_services.jpg` · `Create_service_widget1.jpg` | Boat Charter replaces **Tuition** in both category grids |
| `HomePage1.jpg` | Featured card is a Tuition listing — replace |
| `HomePage2.jpg` | Trust card claims "encrypted" messaging — false, chat is admin-readable in a dispute |
| `Create_service_widget1.jpg` | Tags become category-scoped chips, not free text |
| `Create_service_widget3.jpg` | Price field renders twice; add `priceUnit`; remove Service Packages |
| `Create_service_widget5.jpg` | "Accepting New Customers" removed entirely; Emergency Service tier-gated with a reason |
| `Create_service_widget6.jpg` | FAQs accordion appears twice |
| `Service-full-post.jpg` | Single "Verified Provider" badge becomes three tiers; description describes AC repair under a Cleaning listing |

`Login.jpg` needed no correction — **Apple sign-in was right** and the plan was amended, since App Store review requires it wherever third-party sign-in exists.
