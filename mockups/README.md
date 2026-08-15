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

## Where to put them

Drop the files straight into this folder — `/home/sajeeu/Claude/mockups/` — using these names. Phase commands and `§1 Mockup Inventory` reference them by path, so keep the names stable once set.

| Expected filename | Screen | Owning phase |
|---|---|---|
| `login.png` | Sign In | 3 |
| `register-customer.png` | Create account — Find Services | 3 |
| `register-provider.png` | Create account — Offer Services | 3 |
| `forgot-password.png` | Forgot Password | 3b |
| `home.png` | Home feed (full scroll) | 16 |
| `explore.png` | Explore — category grid | 4 |
| `bookings.png` | My Bookings — Upcoming / Active / Completed | 17 |
| `profile.png` | Profile — customer | 6 |
| `my-services.png` | My Services — provider dashboard | 10 |
| `service-preview.png` | Service Preview — public listing | 12 |
| `wizard-1-details.png` | Create Service step 1 | 9 |
| `wizard-2-location.png` | Create Service step 2 | 9 |
| `wizard-3-pricing.png` | Create Service step 3 | 9 |
| `wizard-4-media.png` | Create Service step 4 | 9 |
| `wizard-5-availability.png` | Create Service step 5 | 9 |
| `wizard-6-extra-info.png` | Create Service step 6 | 9 |
| `wizard-7-review.png` | Create Service step 7 | 9 |

Seventeen files for sixteen screens — Home is two images because it scrolls; name the second `home-2.png`.

`.jpg` is fine where that is what you have. If your filenames differ, put them here anyway and they will be reconciled against this table rather than renamed blindly.
