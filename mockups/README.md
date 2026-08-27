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

## design-composer/ — the highest-fidelity reference here

`design-composer/Become a Provider.dc.html` is a **working prototype** of the Phase 6a onboarding flow, not a picture. Open it in a browser and it runs: real validation, real error text, real loading and disabled states.

**Prefer it over any image for the screens it covers.** It carries what a flat mockup structurally cannot — which field shows which message, when a CTA disables, exactly how long a transition runs. `frontend/CLAUDE.md` has its tokens extracted for Phase 1.

**It is never shipped.** It is React and HTML in Design Composer's `.dc.html` format; the app is Flutter. Match its values; do not transliterate `100dvh`, CSS gradients or `overflow-y:auto` into Flutter, or you get something that feels like a website in an app.

It was reviewed against the plan and corrected on 2026-08-15: bank transfer details, verified email, the account-level `acceptingNewCustomers` toggle, phone as confirm-rather-than-retype, and international phone validation were all added after the first pass omitted them.

## These files are not correct as drawn

Seven divergences from the plan were found in Round 16 and confirmed in Round 18. **`round-16-redraws.html` is authoritative where the two disagree** — open it in a browser. Do not implement `Create_service_widget5.jpg` or `Explore_services.jpg` as delivered.

🔧 **The five `Create_service_widget*` rows below are now historical.** Session 10 built `design-composer/Create Service.dc.html`, which applies every one of them; it is the wizard reference and these images are provenance. The rows stay so the record of what was wrong survives.

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

## The prototypes are becoming the reference

`design-composer/` holds working Design Composer prototypes reviewed against the plan. **Where a prototype and a JPEG cover the same screen, the prototype wins** — it carries every state, the real interaction detail, and the corrections the images never got.

| Prototype | Screens | Supersedes |
|---|---|---|
| `Home.dc.html` | Home + launch mode | `HomePage1.jpg` · `HomePage2.jpg` |
| `Components.dc.html` | the component gallery — mounts the seven below | — |
| `ServiceCard.dc.html` | the card, horizontal and full-width | — |
| `VerificationBadge.dc.html` | Bronze / Silver / Gold, and nothing at all | — |
| `Chip.dc.html` | filter · input · static | — |
| `StatusPill.dc.html` | the twelve booking statuses | — |
| `BottomNav.dc.html` | the five tabs | — |
| `SkeletonCard.dc.html` | loading, per card variant | — |
| `EmptyState.dc.html` | icon, title, body, action | — |
| `Discovery.dc.html` | Explore · search · category results · saved | `Explore_services.jpg` |
| `Emergency Flow.dc.html` | emergency booking, customer side | — |
| `Provider Emergency.dc.html` | emergency offer, provider side | — |
| `Become a Provider.dc.html` | Phase 6a onboarding | — |
| `Create Service.dc.html` | the Create/Edit Service wizard, all seven steps in one shell | `Create_service_widget1–7.jpg` |

The JPEGs stay as the provenance record of what was originally delivered. This table grows as each session in `docs/design/redesign-plan.md` lands.

⚠ **This table lags the sessions.** Sessions 3–9 (trust surfaces, booking entry, the booking record, closing, messaging, identity, account) landed reviewed prototypes that are not listed above. Backfilling it is worth doing; it has not been done.

### Components are files, not sections

`<dc-import>` mounts a **sibling `.dc.html`**. The seven components above are the unit of reuse — a screen imports them and never copies their markup. Two mappings live inside them deliberately and must not be duplicated into a screen: the tier copy in `VerificationBadge`, the twelve status labels in `StatusPill`.

`Home.dc.html` still carries inline copies from before the split. Migrating it is worth doing; it was deliberately kept out of the extraction so a pixel-identical refactor stayed pixel-identical.

Check any file with `python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html`.

### Photos live in the design project, not here

A prototype that shows real imagery references it as `uploads/<name>.jpeg` — those files are uploaded to the Claude Design project and are **not** in this repository. An exported `.dc.html` therefore shows its category-icon fallback locally, which is correct behaviour rather than a defect. Never replace them with hotlinked URLs: an external image is blocked wherever the page is published, and it rots.
