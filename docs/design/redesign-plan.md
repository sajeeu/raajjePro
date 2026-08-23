# Rebuilding the whole app in Claude Design

## What this is, and what it is not

Every screen becomes a working `.dc.html` prototype in the Claude Design project, replacing a set of seventeen flat images and a handful of prototypes. **The look does not change.** Same tokens, same components, same features — this is a re-render, not a redesign.

That framing is the most important line in this document, because it decides how every session runs. The job is fidelity to what already exists, not exploration. Where a session produces something prettier than the delivered mockup, that is a bug in the session, not a win.

**What it buys.** Three things a JPEG structurally cannot give:

- **States.** Every screen gets loading, empty, error and populated, plus its own extra states. Seventeen images currently show one state each — the happy one.
- **Interaction.** Which field shows which error, when a CTA disables, how long a transition runs. `Become a Provider.dc.html` carries this; no image does.
- **One source.** Nine of the seventeen images are wrong against the plan and need a correction table read alongside them. After this, the prototype *is* the reference and the correction table retires.

## Where things stand

**71 page briefs** in `designer-brief.md`. **14 screens built**, across three artboards:

| Artboard | Screens | Status |
|---|---|---|
| `Become a Provider.dc.html` | 3 | Reviewed, corrected, committed |
| `Emergency Flow.dc.html` | 5 | Reviewed across 3 rounds, at plan revision 5.9 |
| `Provider Emergency.dc.html` | 6 | Reviewed across 2 rounds, at plan revision 5.9 |

**57 screens remain**, across thirteen sessions.

## Session 1 is Home, and it is different from the other twelve

Home is the right place to start and you named it correctly: it is where the visual language is most visible, and almost everything downstream inherits from it — the service card, the bottom nav, the header, the section rhythm, the trust content.

But Home should produce **two files, not one**:

1. **`Home.dc.html`** — the screen, with its launch-mode variant and all four states.
2. **`Components.dc.html`** — the shared vocabulary, extracted from Home while it is being built: button variants, input states, chip, service card, verification badge, status pill, bottom nav, avatar, skeleton.

The second file is what makes the following twelve sessions fast and consistent. Every later artboard imports from it (`<dc-import name="ServiceCard">`) rather than re-deriving a card from a screenshot, which is how twelve independently-built sessions drift into looking like twelve products.

**Verify in session 1** that a component built in one chat is importable from another chat in the same project. All artboards are siblings in project `065ca2ad`, so it should work — but the whole sequencing below assumes it, so confirm it before session 2 rather than discovering it in session 7.

## The sequence

Ordered so that each session inherits from ones already built, and so the screens with no mockup come while attention is freshest.

| # | Session | Screens | Mockups to attach |
|---|---|---|---|
| **1** | **Home & the shell** | Home · launch mode | `HomePage1/2` ⚠ |
| 2 | Discovery | Explore · search results · category results · saved | `Explore_services` ⚠ |
| 3 | Trust surfaces | Service preview · provider public profile | `Service-full-post` ⚠ |
| 4 | Booking — entry | Pick a time · request a time · quote received · payment step | none |
| 5 | Booking — the record | My bookings · detail & timeline · amendment · reveal contact · dispatch fee | `Bookings` ✓ |
| 6 | Booking — closing | Did this happen · rate · cancel · dispute · report · book again · recurring | none |
| 7 | Messaging | Conversations · enquiry · booking thread · block/mute/decline | none |
| 8 | Identity | Sign in · register ×2 · verify email · forgot password ×3 · session expired · no connection | `Login` ✓ `Register_*` ✓ `ForgotPassword` ✓ |
| 9 | Account | Profile · role switcher · settings · saved preferences · notifications · help · legal | `Profile_customer` ✓ |
| 10 | The wizard | Steps 1–7 | `Create_service_widget1–7` ⚠⚠⚠⚠ |
| 11 | Provider dashboard | My services · availability & time slots | `Profile_serviceProvider` ✓ |
| 12 | Provider job handling | Booking request · propose time & price · payment received · mark complete | none |
| 13 | Provider business | Performance · analytics · verification · billing · bank transfer · invoices | none |

⚠ = the attached image is wrong against the plan. Pair it with `round-16-redraws.html` and the defect warning.

**Why this order.** Sessions 1–3 build the vocabulary and the two highest-traffic surfaces, so everything after has something to inherit. Sessions 4–6 are the booking core — the most valuable and least constrained work, taken while the system is fresh but before fatigue. Messaging sits at 7 because it depends on booking states existing. Identity and account are conventional and heavily mockup-constrained, so they go late where low novelty costs least. The wizard is one session despite being seven screens, because the seven share one shell and splitting them guarantees drift. Provider work closes it out, reusing everything.

## How each session runs

The loop is the one already proven across three artboards:

1. **Paste** the session brief into a new chat in project `065ca2ad`.
2. **Attach** what the brief's *Attach* line names — plus the defect warning, whenever an image goes in.
3. **Build.** Ask explicitly for any state it skipped.
4. **Import.** I pull the `.dc.html` through the connector and audit it against the plan.
5. **Correct.** I write a follow-up prompt naming the divergences; you paste it back.
6. **Commit** the reviewed file into `mockups/design-composer/`.

**Step 4 is not optional.** Across three artboards it has caught: a missing screen, a false claim about how declining affects a provider's record, invented functionality with no endpoint behind it, an implied charge that does not exist, and bank details missing from onboarding entirely. None of those were visible in the design; all of them were visible against the plan.

## What to expect

Emergency needed four correction rounds. It was the worst case — no mockup, no precedent, the most novel interaction in the product. Sessions with a clean mockup and an established vocabulary should need one.

| Session type | Sessions | Expected rounds |
|---|---|---|
| Clean mockup, conventional | 8, 9, 11 | 1 |
| Defective mockup, corrections to apply | 2, 3, 10 | 1–2 |
| No mockup, new interaction | 4, 5, 6, 7, 12, 13 | 2–3 |
| Anchor session, produces the component sheet | 1 | 2 |

## Three things worth deciding before session 1

**The component sheet is an artboard too.** There is no way to hide a `.dc.html` from the canvas, so `Components.dc.html` will render as its own artboard. Treat that as a feature — it becomes the living component gallery — and give it a deliberate spot rather than fighting it.

**The 17 JPEGs stay in the repo.** They are the provenance record for what was originally delivered, and `mockups/README.md` maps each one. But once a screen has a reviewed prototype, the prototype wins, and that should be stated in `README.md` as each session lands.

**The real island list is still outstanding.** Sessions 2, 9 and 11 all render an island picker. Until the seed list exists they will show six placeholder islands and a note. That is fine for design, but it is the one input from your side that three sessions depend on.

## Not in this plan

The admin panel — roughly fifteen screens, React web, desktop, different visual language, its own brief. It does not belong in a Flutter component vocabulary and would corrupt the shared sheet if folded in.
