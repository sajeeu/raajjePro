# Rebuilding the whole app in Claude Design

## What this is, and what it is not

Every screen becomes a working `.dc.html` prototype in the Claude Design project, replacing a set of seventeen flat images and a handful of prototypes. **The look does not change.** Same tokens, same components, same features — this is a re-render, not a redesign.

That framing is the most important line in this document, because it decides how every session runs. The job is fidelity to what already exists, not exploration. Where a session produces something prettier than the delivered mockup, that is a bug in the session, not a win.

**What it buys.** Three things a JPEG structurally cannot give:

- **States.** Every screen gets loading, empty, error and populated, plus its own extra states. Seventeen images currently show one state each — the happy one.
- **Interaction.** Which field shows which error, when a CTA disables, how long a transition runs. `Become a Provider.dc.html` carries this; no image does.
- **One source.** Nine of the seventeen images are wrong against the plan and need a correction table read alongside them. After this, the prototype *is* the reference and the correction table retires.

## Where things stand

**71 page briefs** in `designer-brief.md`. **Eleven of the thirteen sessions are done.**

| Artboard | Session | Status |
|---|---|---|
| `Become a Provider.dc.html` | pre-sequence | Reviewed, corrected, committed |
| `Emergency Flow.dc.html` | pre-sequence | Reviewed across 3 rounds, at plan revision 5.9 |
| `Provider Emergency.dc.html` | pre-sequence | Reviewed across 2 rounds, at plan revision 5.9 |
| `Home.dc.html` | 1 | Reviewed, corrected; two false trust claims removed |
| Seven components + `Components.dc.html` | 2b | Split to one file per component; cross-chat import confirmed |
| `Discovery.dc.html` | 2 | Reviewed, corrected; Round 23 card signals applied |
| `Service Preview.dc.html` | 3 | Reviewed across 3 rounds |
| `Provider Profile.dc.html` | 3 | Reviewed across 2 rounds |
| `Pick a Time` · `Request a Time` · `Quote Received` · `Payment Step` | 4 | Reviewed across 2 rounds |
| `My Bookings` · `Booking Detail` · `Propose Amendment` · `Reveal Contact` · `Dispatch Fee` | 5 | Reviewed across 3 rounds |
| `Did This Happen` · `Rate This Job` · `Cancel Booking` · `Raise Dispute` · `Report` · `Book Again` · `Recurring Booking` | 6 | Reviewed across 2 rounds |
| `Messages` · `Enquiry Thread` · `Booking Thread` · `Mute Block Decline` | 7 | Reviewed across 1 round |
| `Sign In` · `Register` · `Verify Email` · `Forgot Password` · `App States` | 8 | Reviewed across 1 round |
| `Profile` · `Account Settings` · `Saved Preferences` · `Notifications` · `Help Support` · `Legal` | 9 | Reviewed across 1 round |
| `Create Service.dc.html` — all seven wizard steps in one shell | 10 | Reviewed across 2 rounds |
| `My Services` · `Availability` · `My Calendar` | 11 | Reviewed across 3 rounds |

**Sessions 12–13 remain.** `verify-dc.py` passes on all fifty files.

### What auditing has caught that design review would not

Every prototype so far has had at least one defect that looked completely fine on
screen and was only visible against the plan: invented endpoints, a claim the
product cannot keep, a fee named as the wrong fee, numbers contradicting a
category's configuration. Budget a correction round per session; two is normal.

🔧 **Check reachable prop combinations, not just prop content — added after session 3.**
A screen with two or more scenario props can render a listing that cannot exist:
Service Preview allowed a `range` price with `instant` booking, which advertises a
starting price as bookable. Each prop was individually correct. For every screen
with multiple scenario props, enumerate the combinations and confirm each one is
legal — the verifier reads markup and cannot do this.

🔧 **Ask who a screen is *not* for — added after session 11.**
`Availability` was built correctly and served three of the twelve categories: slot
booking is Cleaning, Beauty and Fitness, while the other nine are request-based and
publish no times at all. Nothing in the artboard was wrong; the gap was that most
providers had no screen. Before building any provider surface, enumerate which
categories reach it and confirm the rest have somewhere to go — `My Calendar` exists
because that question was asked late.

🔧 **A brief that says "import the components" is not enough — added after session 10.**
The wizard hand-rolled its own tag and island chips despite `Chip.dc.html` supporting
both cases exactly. Nothing looked wrong; it was a silent fork of a component that
exists. Grep every imported artboard for `<dc-import` and check the count against what
the screen actually renders — a screen with chips, badges, pills, skeletons or empty
states and zero imports has copied something.

## Session 1 is Home, and it is different from the other twelve

Home is the right place to start and you named it correctly: it is where the visual language is most visible, and almost everything downstream inherits from it — the service card, the bottom nav, the header, the section rhythm, the trust content.

But Home should produce **two files, not one**:

1. **`Home.dc.html`** — the screen, with its launch-mode variant and all four states.
2. **A component per file** — `ServiceCard.dc.html`, `VerificationBadge.dc.html`, `Chip.dc.html`, `StatusPill.dc.html`, `BottomNav.dc.html`, `SkeletonCard.dc.html`, `EmptyState.dc.html` — plus `Components.dc.html` as the gallery that mounts them.

🔧 **One file per component, not one sheet.** `<dc-import>` mounts a **sibling `.dc.html` file**, so a single gallery cannot be imported from. Session 1 delivered the sheet as one file and it had to be split before session 2 could use it — the fix is `sessions/02b-components.md`. A gallery is a display of the components; the components are the files.

That split is what makes the following twelve sessions fast and consistent. Every later artboard imports the real component rather than re-deriving a card from a screenshot, which is how twelve independently-built sessions drift into looking like twelve products.

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
| 11 | Provider dashboard | My services · availability & time slots · **my calendar** | `Profile_serviceProvider` ✓ |
| 12 | Provider job handling | Booking request · propose time & price · payment received · mark complete | none — **cast as Boat Charter**, decided in session 11 (originally “Boat Charter or Events”; Round 26 removed Events): it must exercise the Round 25 occasion subtitle, the 1440/4320 quote windows and the long lead times, since every existing booking artboard is cast Cleaning or Plumbing and none of the long-window behaviour is demonstrated anywhere |
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
6. **Export** the artboard from Claude Design into `mockups/design-composer/`, keeping the filename Claude Design gave it.
7. **Check** it: `python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html`. Structure plus the plan's locked rules — a bare "Verified", a Tuition category, an encryption claim, an editorial provider label, a payment claimed as verified, a phone rendered as verified, a 120-minute Moving window, the deleted contact-info endpoint. Exit 0 or it does not get committed.
8. **Commit** the reviewed file.

**Why the export step is yours.** The connector hands file contents into my context rather than onto disk, and below roughly 40 KB nothing is written out — so for smaller artboards I have to reconstruct the file rather than copy it. That has validated clean every time, but an export is a copy and a reconstruction is not. Step 7 is what makes it not matter either way.

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

## Two rules the sessions keep re-learning

**Images must be uploaded, never hotlinked.** A published page blocks every external host except Google Fonts, so a remote image URL renders as nothing outside the editor — and it is a dependency on someone else's server inside a file meant to be the durable reference. Upload the photo and reference it by filename.

**A screen's most urgent action cannot live below the fold.** Session 2 moved the emergency entry off the cards for the right reason — someone in an emergency is not browsing — and then placed the replacement under twelve category tiles. Whatever a screen exists to make possible in a hurry has to be visible when it opens.

**Visible is not the same as loud.** The fix for that was a red banner card, and on both Home and Explore it took over the page — a browsing surface that reads like an incident. Session 4 replaced it with a compact single-line row, small red bolt, `Something urgent? Get help now`, still above the fold on both screens, and moved the explanation of how dispatch works into the emergency flow itself. Ordinary features are what these pages are for; emergency has to be findable, not dominant. Do not reintroduce the banner.

## Not in this plan

The admin panel — roughly fifteen screens, React web, desktop, different visual language, its own brief. It does not belong in a Flutter component vocabulary and would corrupt the shared sheet if folded in.
