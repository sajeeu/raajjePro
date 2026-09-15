# Phase 10 — My Services Dashboard

What was decided while building §Phase 10, and why. The plan is the source of
truth; this records the choices it left open, the places the build departs
from the artboard, and the one piece of backend the phase needed.

`docs/decisions/25-phase-10-two-questions-answered.md` answered this phase's
two open questions before it started. This record cites it and supersedes it:
both answers are built exactly as it specified.

---

## 1. The screen is `My Services.dc.html`, and four things on it are not

The artboard is the design and the build follows it, with four departures.
Three are corrections and one is a deferral; every one of them is visible from
the screen itself rather than buried in a widget.

**The stats tile reads "Live", not "Published".** The artboard labels it
*Published* and computes it as *published and not hidden* — so the label was
already describing a different number from the one under it. On this screen
"Published" is also a filter pill, eight dp below, meaning the other axis
entirely (§Phase 8's `status`). One word doing both jobs on one screen is how
a provider comes to believe a listing hidden over the cap is reaching
customers. The number is the artboard's; the label names it.

**The live toggle keeps a constant label.** The artboard flips the word
between *Live* and *Off*. Visually that reads well and to a screen reader it
says "Off, off", because `AppToggle` announces its own state. The word stays
"Live" and the switch carries on / off.

**There is no rating on the card.** The artboard draws a star. `Review` does
not exist until §Phase 11 and §Phase 8's own-listing shape carries no rating,
so the star would be invented or blank — and a blank star on a provider's own
listing reads as *nobody rated you*. §Phase 11 adds the field and the star
together.

**The card is a container, not a button.** This one was built the artboard's
way after being built the other way first, and the reason is worth keeping:
`Pressable` wraps its child with `excludeSemantics: true`, so making the whole
card tappable **erases every control inside it** — the overflow menu, the live
toggle, "Finish & publish" — from the semantics tree. A screen-reader user
would have traded three controls for one summary. The artboard's card has no
tap handler either; editing is reached from the menu, which is where it
belongs.

**And one thing that was considered and left as it is:** a draft card prints
`0` views and `0` bookings, where the stats row above it says "No data yet".
`frontend/CLAUDE.md`'s rule is about `StatMiniCard` — a *metric* with no data —
and these are counts of what happened to a listing rather than a measurement
of it, so the literal is honest: a draft has had no views because it has never
been visible, which is what zero means here. Recorded because it reads like an
inconsistency and is not one.

## 2. Slot management is one row, and it resolves to a listing

§Phase 10's bullet is "slot management entry point (Phase 9a)", and §Phase
9a's screen is **per listing** — `AvailabilityScreen` requires a `listingId`,
because "a provider with a two-hour clean and a one-hour clean publishes a
different grid for each". So the row cannot simply navigate:

- **No `slot` listing → the row is absent**, not disabled. §Phase 9a's screen
  would have nothing to draw for a request-based listing.
- **Exactly one → straight in**, with the service named in the subtitle.
- **More than one → a picker sheet first.**

My Calendar is account-wide and always renders. Verification lands on
`UnbuiltScreen(owedBy: 'Phase 23')`: §1e says the evidence checklist, the
rejection-reason taxonomy and the resubmission path are Phase 23's, and
§Phase 6 deliberately left this row to "the provider workspace" rather than
putting it on the customer's Profile.

## 3. §1b's over-cap override is a pin, and it is the phase's only backend work

§1b: "**The provider can override the choice from the dashboard.**" §Phase 8a
built no endpoint for it and asked §Phase 10 to decide whether the two-step
`PATCH …/visibility` path was good enough. It is not, and decision 25 records
the argument: hiding the kept listing writes `hidden_by_provider` onto a
listing the *entitlement system* hid, which is exactly the conflation Round 17
split the two values to prevent, and it silently breaks "any confirmed payment
restores everything" for the listing swapped out.

So the override is a **ranking input**:

| Piece | Where |
|---|---|
| `ProviderProfile.keepVisibleListingId` | nullable, no relation, no cascade |
| `POST /v1/providers/me/listings/:id/keep-visible` | `listings/routes.ts`, delegating to `subscriptions.keepListingVisible` |
| The ranking | `pinnedFirst` in `subscriptions/downgrade.ts` |

Four things this shape gets right, each of which the alternative got wrong:

- **`applyEntitlementVisibility` stays the only writer of `hidden_over_cap`.**
  The provider writes a preference; the entitlement system writes visibility.
- **The pin is read inside that function, not passed to it.** Four callers
  have to honour the same override — a confirmation, a reversal, the lifecycle
  sweep and eventually §Phase 17.1's booking termination — and a parameter is
  the thing three of them eventually forget.
- **A stale pin holds nothing.** `pinnedFirst` promotes an id only if it is
  already in the ranked set, which contains just the provider's currently
  publishable, unprotected listings. A pin on a draft, a deleted listing, one
  the provider hid themselves, or one now protected by a committed booking
  simply does not match.
- **It ranks; it does not exempt.** A pinned listing still loses to §1b's
  booking protection, because that protection is about a customer who has
  already committed.

The endpoint refuses a draft (`LISTING_NOT_PUBLISHED`) — a listing that cannot
be published cannot hold the one live slot — and answers `LISTING_NOT_FOUND`
for somebody else's, so ids cannot be probed.

**This is the one mutation on the screen that re-reads**, and it re-reads for
a reason rather than for convenience: the server sets a pin and re-runs its own
reconcile, so a *second* listing has changed too, and which one is §1b's
ranking to decide. Recomputing that in Dart would be a second copy of the rule
the plan is most emphatic about keeping in one place. It is still not a manual
refresh: the provider taps once and the screen is right.

## 4. "No manual refresh" is a property of the mutations, not of a reload

§Phase 10's Done-when — "every context-menu action performs a real mutation
with no manual refresh" — pulls in two directions at once: the screen must not
re-fetch, and it must not draw a state the server did not confirm. Every
mutation therefore **adopts the listing the server hands back**:

- The live toggle flips optimistically so the tap feels immediate, then takes
  the server's row. On refusal the previous list is put back and the message is
  shown — and that refusal is the ordinary case, not the exotic one, since
  toggling a second listing live on the free tier is what the cap exists to
  stop.
- Remove drops the row locally; the server will not return it again.
- Edit is the only navigation that refreshes on return, because the wizard can
  have published, renamed or deleted the listing while it was gone. It is
  silent — no skeleton over a screen that is already on display.

## 5. What the dashboard deliberately does not carry

- **No `acceptingNewCustomers` toggle.** The artboard draws none and §Phase
  10's bullets ask for none. Ledger row **P8A-4** names "§Phase 10's dashboard
  and §Phase 10a's billing screen" as owing §1b's pause sentence; the answer
  for this half is that the toggle does not render here, so nothing is owed.
  The row is updated rather than closed — §Phase 10a still owes it.
- **No conduct metrics.** §1f's numbers are the provider's before they are
  anyone's, and `My Performance.dc.html` is where they live.
- **No suspension notice.** `suspended` is read (it is an input to §1a's
  visibility) and nothing renders it: §Phase 10b owns the suspend action and
  its copy, and writing that copy here would put words in an admin's mouth
  before the action exists.
- **No Duplicate.** Decision 25 §Q2: the plan specifies none, and it could not
  work as drawn — `ListingMedia.objectKey` is `@unique`, so a copy cannot
  share the original's cover and would land unpublishable.

## 6. Three things moved to `core/` on their second consumer

`lib/README.md` calls this the convention rather than a refactor, and Phase 9
set the precedent with `CategoryApi`:

- `ListingApi` and `ServiceListing` → `core/listings/`. The dashboard reads the
  same endpoint the wizard writes to, and no feature may import another.
- `customerPricePreview` (with `mvrFromLaari` and `laariFromMvr`) →
  `core/listings/listing_money.dart`. §Phase 9 shows it as *what the card will
  say*; that is only a promise if one function says it.
- `relativeEdit` → `core/format/relative_time.dart`, beside `relativeAge`,
  whose first rung is "active now" — right about a session, wrong about an
  edit.

Four fields were added to `ServiceListing` in the move — `viewCount`,
`bookingCount`, `publishedAt`, `updatedAt` — all already on §Phase 8's wire and
none of them previously parsed, because a wizard editing one listing has no use
for them.

## 7. Deferred verification

**No new rows.** Every Done-when line is testable now and is tested:
`frontend/test/features/my_services/phase10_done_when_test.dart` drives the
real app through §Phase 6's role switcher for all three, plus the bullet that
is a routing claim.

Two existing rows change:

- **P6-1 closes.** Its remaining half was whether the switcher's later switch
  reaches a real dashboard; `/provider/services` is now `MyServicesScreen` and
  the test asserts both branches in one place — completed → dashboard,
  mid-flow → back into onboarding.
- **P8A-4 is updated, not closed**, per §5 above.

The badge-through-lapse test sets its two axes **separately** — `silver`
verification with the entitlement degraded to a cap of one and a listing
actually hidden over it. Degrading both together would have passed while
proving nothing, which is the failure that assertion exists to catch.
