# Decision 18 — Phase 6, the customer profile module

**Status: built 2026-09-09.** Plan §Phase 6, plus §Phase 5's `isProvider`
signal and §Phase 3's account surface. Backend and Flutter both.

---

## What the plan settled, and what it left to this phase

§Phase 6 is four bullets and three Done-when clauses. It names two endpoints
and **no fields on either**, names the Profile screen as a pixel-match with
"five rows navigating to sub-screens", and states the rule the role switcher
turns on: a first switch reaches §Phase 6a's onboarding, every later one
§Phase 10's dashboard.

What it does not settle is what those two endpoints carry, and — more
awkwardly — that **five of the seven destinations this screen navigates to do
not exist yet.** Account settings is Phase 3's and Legal is Phase 3's
placeholder; Saved is Phase 14's, Saved preferences Phase 7's, Help & support
Phase 19b's, My Bookings Phase 17's, and the switcher's two are Phase 6a's and
Phase 10's. A phase whose acceptance criterion is *every row navigates*, built
before most of the rows have anywhere to go, is the shape of this one.

`Profile.dc.html` is the design source and Round 48 rewrote the screen; both
were built against, and `Profile_customer.jpg` is provenance
(root CLAUDE.md: a prototype beats an image). Nine decisions follow.

### 1. Two of the plan's Done-when destinations are placeholders, not inert controls

Phase 4 established `InertControl`: a control drawn to the prototype and wired
to nothing, marked in the tree so a test fails when someone wires it. That is
right for a search field or an island pill — the control is *part of the
layout* and removing it would change the screen.

It is wrong for a row. A row's entire purpose is to navigate, and §Phase 6's
Done-when says so in those words. So the five rows, the four booking tiles and
the switcher's two destinations are **real named routes** that land on a new
shared `UnbuiltScreen`, which says what is missing and names the phase that
owes it. `owedBy` is asserted per destination, so a phase landing its screen
finds the tripwire.

The third possibility — a row that silently does nothing — was rejected for
the reason Phase 4 gave for `TabPlaceholderScreen`: the user cannot tell a
dead control from a slow one.

**Where the tile placeholders differ from the naive version:** Round 48 §2's
whole finding was that four tiles reached one screen, so four placeholders
reading "Bookings is not built yet" would have reintroduced the defect through
the fix. Each tile lands on a placeholder titled with **its own tab** —
`Upcoming bookings`, `Completed bookings` — and the test asserts all four are
distinct. Ledger row **P6-3**.

### 2. The change-photo control is drawn and wired to nothing; the photo is not built

`Profile.dc.html` has a working photo picker and Round 48 §5 explicitly made
it a real button with a real handler. It is the one place this phase departs
from the delivered design, and it is deliberate:

- §Phase 6 does not mention a photo.
- `User` has no avatar column, and none was added.
- **Media upload via presigned URL — server-side content-type and size
  validation, EXIF stripping on every image — is §Phase 8's bullet.** Building
  storage here would mean inventing a bucket and a retention policy the plan
  does not specify, for an entity the plan does not mention.

So the avatar renders initials through Phase 1's `AppAvatar`, and the camera
disc is drawn to the prototype's geometry — 30 dp of paint inside Round 48's
48 dp target — inside `InertControl(owedBy: 'Phase 8')`. The alternative
considered was leaving it out entirely, on Round 23's precedent for the
emergency entry. That precedent turns on a dead control *advertising an action
with a person on the other end of it*; nobody is waiting at the other end of a
camera button on your own profile, and Round 48 §8 lists the hero among the
things that must not change. Owner chose "render it, wire nothing".

**§Phase 6a also needs this.** Its account-details step collects "photo or
logo (optional)", and it is sequenced before Phase 8. Whichever of the two
lands first owns the upload path; the `owedBy` reads `Phase 8` because that is
where the plan puts the mechanism.

### 3. `PATCH /v1/users/me` carries `fullName`, and no screen calls it

`fullName` is the one user-owned field on `User` without its own Phase 3
endpoint — password, email and phone each carry a credential check or a
re-verification step and keep theirs. Bounds match `registerBody.fullName`
exactly, because it is the same field.

**Nothing calls it.** Neither `Profile_customer.jpg` nor `Profile.dc.html`
carries a name-edit control, and adding one would be Phase 6 designing a
screen element on its own. Recorded as met **for the mechanism** with ledger
row **P6-4**, which closes when a design round adds the affordance.

Unknown keys are stripped rather than rejected, matching
`updateOwnProviderBody` (decision 8 of `17-phase-5-provider-profiles.md`).
What matters is that naming `email`, `phoneE164`, `status`, `emailVerifiedAt`
or `passwordHash` cannot change any of them — asserted against the **row**,
not the status code, with a legitimate field in the same request checked to
have landed.

`requireActiveAccount` as well as `requireAuth`, for the reason
`PATCH /v1/providers/me` carries it: a frozen account has a queued
anonymisation that replaces this exact field with a placeholder, and §Phase 3's
freeze means it starts nothing new.

### 4. `profile-summary` carries four fields, and every absence is reasoned

§Phase 6 calls it "one call for the Profile screen" and names no fields, so
the shape is what the screen renders and nothing else: `id`, `fullName`,
`memberSince`, `isProvider`. Each obvious candidate is absent on purpose, and
`backend/src/modules/account/dto.ts` says so at the point of definition:

- **No phone number.** backend/CLAUDE.md excludes phone numbers structurally
  in the mapping layer rather than per handler, and this screen displays none.
  An own-read is permitted to carry one — `userDto` does — but a field nothing
  renders is a field with nothing protecting it. Asserted by scanning the
  serialised body for the user's actual number, not by checking a field list.
- **No avatar** — decision 2.
- **No island or location** — decision 5.
- **No saved or booking counts.** Phase 14's Done-when ("Profile's count
  updates") and Phase 17's tabs are what put numbers here. Neither `Favorite`
  nor `Booking` exists, so a count today could only be a zero meaning "not
  built" — the same distinction §1f's `noConductRecorded` draws. This call is
  the point they extend, additively.

It is deliberately **not** the same shape as `GET /v1/auth/me`. That is the
auth surface every screen restores from; this one is the Profile screen's, and
the two will diverge the moment Phase 14 lands.

Built onto the existing `account` module rather than a new `users` one — the
`/v1/users/me` prefix and `AccountService` are already there, and invariant 5
is additive-and-modular, not one-module-per-endpoint.

### 5. The hero states no location, because nothing stores one

The prototype's hero reads `Malé, Maldives · Member since Jan 2026`, and Round
48 §8 lists that line among the things that must not change.

There is **no customer island field anywhere in this schema**, and `Island`
itself is §Phase 7's seed. The options were to print a placeholder location,
to invent the field, or to render the half that can be answered. The third:
the subtitle reads `Member since Jan 2026`, and a test asserts neither `Malé`
nor `Maldives` appears — so when Phase 7 puts a real island on the account,
that test is what makes someone decide about this line rather than leaving the
placeholder in place forever.

`monthAndYear` was added beside `shortDate` for it. Month and year only: the
exact day a customer signed up is not something the screen has reason to state.

### 6. The provider-mode `Verification` row is not on this screen

`Profile.dc.html` prepends a `Verification` row when the session role is
provider. §Phase 6 says **five rows**, the five it renders are the five Round
48 §4 settled, verification review is §Phase 10a's identity queue and §1e's
tiers, and §Phase 10 owns the provider workspace this screen hands off to.
Asserted absent, so it arrives with the phase that owns what it opens.

### 7. Three things moved into `shared/` and `core/`, and one accessibility problem came with them

`lib/README.md`: a widget a second feature needs moves to `shared/`, it is not
copied, and no feature may import another feature — they meet in `core/`.
Three things moved.

- **`SettingsRow`** was Phase 3's, in `features/account/`. Profile's rows are
  the same component minus the subtitle (Round 48 §4: "keep the rows
  subtitle-free"), and no feature may import another feature. Now
  `shared/navigation/settings_row.dart` with `subtitle` nullable.
- **`InertControl`** was declared inside Phase 4's `explore_screen.dart`. Now
  `shared/states/inert_control.dart`, with the note that not every unbuilt
  control belongs in one.
- **Route names that cross a boundary** are now in `core/routes.dart`. Wiring
  Explore's avatar and nav tab meant Explore reaching Profile and Sign in, and
  the first pass did it by importing both features — breaking the same rule
  this decision cites for `SettingsRow`, in the same commit. Each screen still
  declares its own `routeName`; where a name is needed across a boundary it is
  defined once in `core/` and referenced from both sides.

**Wiring Explore's two Phase-6-owed controls broke the header at 200% text,
and 🔧 the first fix for it was wrong.** Explore's account disc was an
`InertControl(owedBy: 'Phase 6')`; making it a control put it inside a
`Pressable`, whose 48 dp hit floor is 12 dp wider than the 36 dp avatar — and
the brand row overflowed by 5.5 px at 200% text.

The first attempt wrapped the control in an `OverflowBox`, on the theory that
the slot could lay out at 36 while the child hit-tests at 48. **It does not.**
`RenderBox.hitTest` gates on the box's own `size` before it ever reaches
`hitTestChildren`, so the child laid out at 48 and only the parent's 36 was
tappable — the extra 12 dp was paint. Measured with a throwaway probe: a tap
21 dp off centre did not register, while `getSize` on the child returned
48 × 48. The test written alongside it asserted the *layout* size and so
passed against the defect, and both this file and `HANDOVER.md` stated the
false claim before the review caught it. Recorded because the failure mode
generalises: a geometry assertion about a **tap target** has to tap.

The real fix is one line in Phase 1's `AppHeader` — the brand wordmark is now
`Flexible` with ellipsis. Every other child of that row is either fixed width
or already flexible, so the wordmark was the one thing that could not give;
it keeps its natural width at ordinary text scales and truncates only where
the alternative is a layout error. **Flagged rather than done silently**
(invariant 5): it is a change to a shared Phase 1 widget, made because
frontend/CLAUDE.md's 48 dp floor and the plan's 200%-text rule cannot both
hold in that row without it. `explore_chrome_test.dart` now asserts the target
by tapping 20 dp off centre, and asserts the brand row survives 200% text with
the control wired.

Phase 4's two Account/Profile tripwires were **deleted on purpose** — which is
what they existed to force — and replaced by tests of where the two controls
now go. The island pill, search field, Saved heart, bell and category tiles are
still inert and still asserted.

### 8. Three defects the QA review found, and what each one cost

Recorded because none of the three was visible in the source and each had a
test passing beside it.

- **`Pressable(excludeSemantics: true)` discards `semanticLabel`.** It returns
  the child *unwrapped* — it means "the child carries its own complete
  semantics", which is true of Explore's search field and false of both
  controls Phase 6 added. The header account disc announced as `label=""` and
  the change-photo button produced no semantics node at all, directly
  contradicting its own comment. Removed from both; asserted with
  `find.bySemanticsLabel`.
- **Sign out cleared the session and stayed on the screen.** `AuthGate` swaps
  to the guest home underneath, and `app.dart`'s listener pops only for a
  session *expiry* — so Profile sat on top still showing the name of the
  account that had just signed out. It now pops to the first route after
  `signOut()` completes.
- **The summary outlived the account it described.** A plain
  `AsyncNotifierProvider` lives as long as the `ProviderScope`, so signing out
  and back in as someone else showed the previous person's name and routed the
  role switcher on *their* `isProvider`. Now `isAutoDispose: true`. The
  Done-when test could not have caught it, because it rebuilds the scope on
  every boot; the regression test signs out and back in inside one app
  instance, and fails without the flag.

Two lower-severity findings from the same review are also fixed: a dead
`bookingsRoute` constant is gone, and `core/routes.dart` now holds the route
names that cross a feature boundary, so Explore no longer imports two sibling
features to reach them — the rule this phase cites as its reason for moving
`SettingsRow` into `shared/`.

### 9. The screen has three states, not four, and says why

frontend/CLAUDE.md requires loading, empty, error and populated on every
screen. Profile has no empty state: it renders the signed-in account, and an
account always has a name and a join date. "Empty" here would mean "you do not
exist". A failed read is the error state, and `EmptyState` appearing on the
populated screen is asserted to be a defect.

The skeleton is the populated layout's shape — a hero-sized circular disc, four
tile bones, three row bones — asserted by shape rather than by a raw count, so
it stays a meaningful assertion when the row count changes.

---

## One place the design and the build differ, beyond decisions 2 and 5

`Profile.dc.html`'s sheet links its Provider card straight at
`Become a Provider.dc.html`, because an artboard has no session. The build
resolves it through `RoleSwitch.destinationFor(isProvider:)`, which §Phase 6's
Done-when requires. Not a design defect — the prototype could not express it —
and the sheet's explanatory copy is the prototype's verbatim, because it
describes the rule rather than asserting which branch the reader is on.

---

## What this phase did not build

- **Saved preferences.** Phase 3 deferred it to "Phase 6 or Phase 7"
  (`12-phase-3-identity.md`, decision 2); it needs `Island`, which Phase 7
  seeds, and §0.0 item 12 governs the island control in detail — search from
  the first character, no cap, never a native `<select>`, never keyed by name.
  Phase 7 builds it whole. Owner's call; ledger row **P6-2**.
- **A name-edit affordance** — decision 3.
- **Photo upload** — decision 2.
- **Any count on the Profile screen** — decision 4.
- **The provider-mode IA.** §Phase 6's bullet says the switcher's placement
  *and* the provider-mode IA are in `Profile.dc.html`. The placement is built;
  the IA behind it is the dashboard §Phase 10 owns, and this phase stops at the
  route that reaches it.

---

## Deferred verification

Rows **P6-1** to **P6-4** in `docs/deferred-verification.md`. The first three
are held open by screens later phases build; the fourth by a design decision
nobody has made yet. None could have been closed here, and everything that
could be tested was: the routing decision both ways, all five rows tapped
through the real route table, all four tiles distinct, and the `isProvider`
signal asserted not to flip when the screen is merely opened.
