# Phase 14: Favorites (Saved Services and Providers)

Built on 2026-10-10 against `01_Development_Plan_v5.md` revision 5.37, from
§Phase 14 and its **Done when** clause. §1c's access table (saving is
*Registered*), §1a (derived visibility) and §1h (Round 15: favourites extend
to providers) were read alongside. Design: the Saved screen in
`Discovery.dc.html`, the hearts in `ServiceCard.dc.html`,
`Service Preview.dc.html` and `Provider Profile.dc.html`, and Profile's Saved
row in `Profile.dc.html`.

## 1. What was built

**Backend — `modules/favorites/`.** Two tables, `favorite_listing` and
`favorite_provider`, one row per (user, thing) ever. Under
`/v1/users/me/favorites`:

| Route | Who | What |
|---|---|---|
| `PUT /listings/:listingId` · `PUT /providers/:providerId` | signed in, not frozen | save; 404 unless the public can see it |
| `DELETE` on the same paths | signed in, not frozen | unsave — a stamp, never a delete |
| `GET /status?listingIds=…&providerIds=…` | signed in | which of ≤100 ids per kind the caller saved |
| `GET /listings` · `GET /providers` | signed in | the Saved screen's lists, newest saved first, cursor-paged |

`GET /v1/users/me/profile-summary` gained `saved: { services, providers }`,
additively. Favourites are in the data export and are stamped by the
anonymiser.

**Flutter.** `core/favorites/` holds the API, the app's **one** saved state
(`favoritesProvider`) and `setSaved`, the one thing every heart does.
`shared/toggles/listing_save_heart.dart` is the heart wired to it.
`features/saved/` is the Saved screen at `/saved`. Wired: every
`PublicServiceCard` heart, the Service Preview's hero heart, the provider
page's header heart, Explore's heart (now navigation to Saved), and Profile's
Saved row and its count.

## 2. Done when — how each clause is tested

1. **"Tapping the heart anywhere persists via API."**
   `backend/test/phase14-done-when.test.ts` §1 — save and unsave persist for a
   listing and a provider; both are idempotent, five concurrent saves leave one
   row; an unsave stamps and a re-save revives the same row. Flutter
   `test/features/saved/phase14_done_when_test.dart` §1 taps the card heart,
   the hero heart and the provider header heart and asserts the exact `PUT` /
   `DELETE` each sends.
2. **"The Saved Services screen reflects it immediately."** Backend §2 — the
   lists return exactly what was saved, newest first, and drop an unsaved item
   on the next read. Flutter §2 — an unsave on the Saved screen, from either a
   provider row or a card heart, removes it in the same frame. A refused one
   puts it back with the artboard's sentence. All four screen states are
   covered.
3. **"Profile's count updates."** Backend §3 — `profile-summary.saved` moves
   with every save and unsave and never double-counts. Flutter §3 — the Saved
   row shows the count, and a save accepted anywhere re-reads the summary
   while Profile stays mounted.

The rollback and the count refresh were each mutation-checked: removing the
rollback turns both rollback tests red, and removing the refresh turns the
count test red.

## 3. Decisions the plan is silent on

1. **A favourite that stops being public is kept, not stamped.** Examples are
   a hidden listing, an unpublished one or a suspended provider. It is absent
   from the lists and the count while §1a and `PUBLICLY_VISIBLE_LISTING` hide
   it, and it comes back when they show it again. The customer did not unsave
   it. Tested both ways.
2. **Only what the public can see can be saved.** Saving a draft, a hidden
   listing, a drafts-only provider or a suspended one is the same 404 the
   public read gives, so the endpoint never confirms a hidden thing exists.
3. **The count is "what the Saved screen would show".** The lists and the
   count share one predicate (`shownListings` / `shownProviders`), so Profile's
   number cannot disagree with the screen it opens.
4. **Saved state is a lookup, not a field on the public reads.** §Phase 13's
   profile is deliberately identical for every viewer. A `viewerSaved` field
   would have ended that. Instead each heart asks `GET …/status` as it
   appears, and the asks made in one frame go out as one call.
5. **No cap on how many things a customer can save.** Saved Preferences capped
   at 20 to stay one unpaged read. Here the lists are cursor-paged, as
   backend/CLAUDE.md requires, and the client pages to the end, as My Bookings
   does. A product limit would have been an invention.
6. **Save is `PUT`, unsave is `DELETE`, with no `Idempotency-Key`.** Each verb
   is idempotent on its own, and the heart's retry must land on the asked-for
   state rather than toggle it back. `ON CONFLICT DO NOTHING` makes two racing
   saves both succeed.
7. **Writes carry `requireActiveAccount`**, as Saved Preferences' do. A frozen
   account starts nothing new.
8. **A rate limit of 60 a minute per principal** on the four writes. It bounds
   a script, not a person.
9. **Profile's count is services plus providers**, one number on the row.
   Nothing draws two.

## 4. Where the build departs from the artboard

1. **A saved provider's headline is the business name**, with its initials,
   the chip badge and what they offer beneath. The artboard heads the row with
   a person's name ("Ibrahim Rasheed") and puts the business under it. This is
   decision 34's ruling, applied to the same provider on another surface.
2. **Tapping a saved provider's name and avatar opens their profile.** The
   artboard gives the row no destination. A saved person you cannot look at
   again is a dead end. The row stays a container (`frontend/CLAUDE.md`): the
   identity half is its own target, and Message and the heart are their own.
3. **Profile's Saved row shows the count before its chevron.** `Profile.dc.html`
   draws no count, and Round 48 §4 keeps the rows subtitle-free. A trailing
   number is the least that satisfies "Profile's count updates" without a
   subtitle. Nothing saved draws no number, never a zero.
4. **Explore's heart is navigation, not a toggle.** It was built in Phase 4 as
   an inert `SaveHeartToggle`, which would announce "Save, off" for a button
   that opens a screen. It is now a button labelled "Saved". A guest is sent to
   sign in, as the account disc does.
5. **The Saved screen has no bottom nav.** It is a pushed screen with a back
   control, like Saved Preferences.
6. **Only the rollback says anything.** The artboard toasts "Saved" on every
   tap. Here a heart's own fill is the confirmation. A snack bar appears only
   on a refusal, where there is no field to put the error under, and for
   "Removed from saved", because the row the customer tapped disappears.

`docs/design/sessions/round-63-saved-corrections.md` carries items 1–3 back to
the design project.

## 5. Changed outside the phase's own files

- **`PublicListingService`'s card building is one private method,
  `toCards`.** The profile grid and the new `cardsByIds` (the Saved list,
  whose services belong to many providers) both call it.
- **`ProviderVisibility.visibleWhere()`** hands out §1a's rule as a Prisma
  predicate. The favourites lists page and count through a relation. Built
  from the same two halves `isVisible` uses, not a copy, so suspension is
  still an input to one helper.
- **`AppHeaderAction` gained `toggled` and `iconColor`**, for the provider
  page's heart. **`SettingsRow` gained `count`**, for Profile.
- **`displayName` moved to `core/public/public_copy.dart`**, and the provider
  profile's copy file re-exports it. **The email gate moved to
  `core/auth/email_gate.dart`.** In both cases the Saved screen is the second
  consumer.
- **Tripwires rewritten, as they exist to be.** Explore's inert Saved heart,
  Profile's "Saved owes Phase 14", and Phase 13's two "Save is inert" tests are
  now tests of what each control does. Phase 6's exact-key test on
  `profile-summary` now names `saved`.

## 6. Ledger

- **Closed:** P12-3 (the hero heart) and P13-3 (the provider and card hearts).
  P6-2's Saved half is closed; the row stays open for Help & support.
- **Added:** P14-1 — the Saved providers row's Message button lands on
  §Phase 18's placeholder.
