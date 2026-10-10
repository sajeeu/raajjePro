# Phase 13: Provider Public Profile

Built on 2026-10-10 against `01_Development_Plan_v5.md` revision 5.37, from
§Phase 13 and its **Done when** clause. §1a (derived visibility), §1e (the
three-tier badge), §1f (conduct is numbers) and §1g (Maldivian-owned) were read
alongside. Design: `Provider Profile.dc.html`, plus the `full` variant of
`ServiceCard.dc.html`.

## 1. What was built

**Backend.** One open route was added to `modules/public-listings/`:

- `GET /v1/providers/:id/public` returns `PublicProviderProfileDto`, which
  carries:
  - `provider` (`PublicProviderDto`, unchanged)
  - the rating across every service
  - the tags three different customers applied
  - every published listing as a `PublicListingCardDto`

The gate is Phase 12's: `ProviderProfileService.readPublic`, which runs §1a's
`findVisibleProviders` rule (`isVisible`). As a result, these all return the
**same 404 with the same body**:

- a drafts-only provider
- a provider whose only listing is hidden
- a suspended provider
- an id that never existed

The owner gets the 404 too. The page is the public one, not a preview of it.

The response is **identical for every viewer**, because nothing in it reads who
is asking. The test compares a guest's read with the owner's, with signed media
URLs masked.

The card is a strict subset of the listing page's DTO and carries no provider
block. Every card on the profile belongs to the page's provider, so the client
takes the name and tier from there. The second signal now comes from one
private method, `secondSignal`, which the listing page and every card both call.
Before this, the listing page computed it inline.

The listings grid is unpaged. §1b's entitlement cap bounds how many listings a
provider can hold published, and the profile's job is to show all of them.

**Frontend.** The new `features/provider_profile/` holds the API, the
controller, `profile_copy.dart` and the screen. Route
`/provider-profile` is `AppRoutes.providerProfile`. The Service Preview's
provider card now opens it, which closes ledger **P12-4**.

`shared/cards/public_service_card.dart` is the customer-facing card in its
`full` variant. Phase 13 is its first consumer and §Phases 15–16 are its next,
so it lives in `shared/`.

## 2. How "no contact data regardless of viewer" is held

This works the way Phase 12's guarantee does, by structure rather than by a
check per handler:

- The profile DTO is built from `PublicProviderDto`, which has no phone,
  payment or person-name field.
- The card DTO reads no `User` row.
- The Flutter models parse fields by name.

`backend/test/phase13-done-when.test.ts` scans the raw body for four viewers
(guest, customer, a stranger provider, the owner) on a slot provider and an
emergency-capable Gold one. It looks for:

- the provider's phone in both forms
- the provider's email
- all four bank fields
- the customer's phone and email

It also checks for any key that could hold one of these, `fullName` and
`userId` included. The Flutter test plants a phone, an email, a full name and an
account number in the JSON and finds none of them on screen.

## 3. Decisions the plan left open

**The headline is the business name, and no personal name or photo appears.**
The artboard draws a person's name over the business name and an avatar photo.
The plan does not say which name a public page shows:

- `PublicProviderDto` has never carried a person's name.
- Phase 12 already prints the business name for the same provider.
- Only the parties to a booking see `businessName ?? fullName`.
- No provider photo column exists.

The question went to the control session, which decided on the owner's behalf:
headline = `businessName`, an initials avatar, and the button reads "Message
provider". It also ruled that a photo needs its own plan decision before any
column is added. To reverse this, add one field to `PublicProviderDto` and one
header line. No migration is needed.

**Which §1f metrics the grid shows.** The grid has six cells, as the artboard
draws them: completed, cancelled, no-show, on time, price honoured, and jobs
completed. The response time sits beneath them. Acceptance rate is computed
but not shown, and §1f's own example line does not use it either. A rate that
is null above the floor (for example, on-time with no arrival marks) reads "No
data yet", never 0%.

**When "New provider" is said.** Whether the rates show is decided by the
server (`metricsBelowFloor`, measured over the 90-day window). Whether "New
provider" is *true* is a separate question, because the job count is lifetime.
`jobsLine` (now in `core/public/public_copy.dart`) says "New provider" only when
the lifetime count is itself under ten. Otherwise the count stands alone, and
the rates stay hidden either way. Phase 12's ProviderCard uses the same
function. Its own test case (4 jobs) is unaffected.

**The below-floor body says "in the last 90 days".** The artboard says
"…completed ten bookings", which is false for a provider who has completed 47.

**The name is set in `sectionHeading` at weight 800**, which is 17 px. The
artboard's 20/800 matches no type role, and `frontend/CLAUDE.md` says to use a
role rather than a size.

## 4. Changed, though the task did not name it

1. **Phase 11's provider tag counts now merge by tag key across categories.**
   Each category seeds its own copy of the same eight tags. Provider counts were
   kept per tag id, so a provider working in two categories would have shown
   "On time" twice, with §1f's three-customer threshold judged per category.
   - `ReviewAggregates.refreshProviderTags` now writes each row's
     `customerCount` as the distinct authors across every row that shares the
     key. Distinct authors do not sum: one customer tagging "Arrived late" in
     two categories is one customer.
   - The read (`toSummary` → `mergeByKey`) sums `applicationCount` per key.
   - Listings have one category, so nothing changes for them.
   - Asserted in `phase13-done-when.test.ts`: two customers plus the same
     customer again in a second category shows nothing, and a third customer
     makes "On time (4)" appear once.
   - Rows written before this change keep their per-category `customerCount`
     until the next review write for that provider recomputes them. No
     production data exists.
2. **Phase 12's public models and shared copy moved to `core/public/`.** This
   was required because this second consumer is another feature (`lib/README.md`:
   no feature imports another). The moved items are:
   - the models: provider, conduct, category, pricing, second signal, tag count
   - the copy: booking CTA, response time, next-open time, job count, headline
     price
   Phase 12's two files re-export them, so its imports are unchanged.
   `PublicConduct` gained the five rates the grid prints.
3. **`priceCopy` gets its figure and unit from the new `priceHeadline`.** The
   card and the listing page therefore cannot print one price two ways. No
   output changed, and Phase 12's `priceCopy` tests pass unmodified.
4. **Two geometry defects were caught and fixed by the geometry tests.**
   - The avatar ring painted over the avatar's edge, so the disc measured
     68 dp instead of the drawn 76.
   - At 200% text, two pills overflowed (the Maldivian-owned pill and the
     callback badge). Their text now wraps.

## 5. Deliberately not built

- **Message**: §Phase 18's enquiry thread. Gated on a verified email, then
  lands on `UnbuiltScreen`. Ledger **P13-1**.
- **Report this provider**: §Phase 22. Ledger **P13-2**.
- **Saving the provider, and the hearts on the cards**: §Phase 14. Ledger
  **P13-3**.
- **A photo**: needs its own plan decision (§3).
- **A paged review list on the profile.** Neither the artboard nor §Phase 13
  draws one, and `GET /v1/providers/:id/reviews` already exists for later use.

## 6. Artboard follow-up

`docs/design/sessions/round-62-provider-profile-corrections.md` covers three
items. The `.dc.html` files themselves were not edited (the design project is
the source):

- the business-name headline
- the "New provider" rule
- the card's hardcoded callback-eligible category map

## 7. Verification

- `backend/test/phase13-done-when.test.ts`: 11 tests.
- `frontend/test/features/provider_profile/phase13_done_when_test.dart`: 29
  tests.

Both files have one group per Done-when clause, plus §1f's rules and the
geometry checks. Geometry is measured on the painted boxes at 412 dp:

- 20 dp gutters
- the radius-24 header card
- the 76 dp banner and avatar, lifted 32 dp
- 16 dp between sections
- the card's 14 dp padding and 96 dp thumbnail
- three metrics across at 100% text, fewer at 200%
- the 54 dp CTA

`scripts/verify.sh` is green.
