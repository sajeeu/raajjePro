# Phase 15: Search & Discovery

Built on 2026-10-10 against `01_Development_Plan_v5.md` revision 5.37, from
§Phase 15 and its **Done when** clause. §1c "Discovery must signal booking
mode" (Rounds 23, 28 and 44), §1g (local preference), §1a (derived
visibility) and §1b (premium includes priority placement; free tier search
visibility is never paywalled) were read alongside. Design: Search results
and Category results in `Discovery.dc.html`, the card in `ServiceCard.dc.html`,
and a Filters sheet the owner approved on 2026-10-10, because the artboard
draws the chips that open it but not the sheet.

## 1. What was built

**Backend: `modules/search/`.** One endpoint answers both screens:

| Route | Who | What |
|---|---|---|
| `GET /v1/search/listings` | anyone, a guest included | `q`, `islandId`, `categoryId`, `mode`, `priceMinLaari`, `priceMaxLaari`, `maldivianOwned`, `sort` (`distance` / `rating` / `price`), `limit` (default 12), `cursor` → `{ total, items: [{ listing, provider, sponsored }] }`, `meta.nextCursor` |

The work happens in three steps, each with one job:

1. **Membership.** Prisma only. The listing must match
   `PUBLICLY_VISIBLE_LISTING`, and its provider must pass
   `ProviderVisibility.visibleWhere({ acceptingNewCustomers: true,
   maldivianOwned? })`, which is §1a's one helper. Then every filter must
   match, and every word of the query must match.
2. **Placement.** `priorityPlacementProviderIds` is billing's own entitlement
   mapping (`entitlementsFromRow`, which `getProviderEntitlements` also uses),
   read once for the providers in the set.
3. **Order.** Raw SQL, because the keys are computed. The result is a keyset
   page over `(g, k1, k2, k3, id)`: `g` is the boosted group, the `k`s are
   the sort's own keys, and `id` breaks ties.

The migration (`20261010150000_phase15_search`) adds `pg_trgm` and
`unaccent`, an IMMUTABLE fold function `rp_search_fold`, a listing
search-document function, trigram GIN indexes on that document and on the
business name, and a partial index for price. `EXPLAIN` shows both trigram
indexes used for `LIKE '%token%'`.

**Flutter: `features/search/`.** `SearchResultsScreen` at `/search` serves a
search (`{query}`) and a category (`{categoryId, categoryName}`). It has the
artboard's header, the Sort row (Distance, Rating, Price), the filter row
(the filters button, Island, Category on a search only, Price, Mode,
Maldivian-owned), the list with "Show 12 more", and four states. The Filters
sheet is `filters_sheet.dart`. Explore's search field now submits, every
category tile opens its results, and `PublicServiceCard` gained `sponsored`.

## 2. Done when — how each clause is tested

1. **"Results are correct."** `backend/test/phase15-done-when.test.ts` §1.
   - Every word must match. The fields searched are the listing's name, short
     description and tags, the category name, and the business name.
   - Accents, case and the Dhivehi apostrophe are ignored.
   - A personal name is never searched.
   - The island gate reads the *listing's* service areas by id. A provider
     whose account default covers an island their listing does not is not a
     result there (this closes ledger P7-3), and a removed area stops
     matching.
   - These are never results: a draft, a hidden listing, a deleted listing, a
     suspended provider, a provider not accepting customers.
   - A Gold provider and an unverified one are found and ordered alike.
   - A guest may call, and no response carries a phone number or bank
     detail.

   `backend/test/search-fold.test.ts` holds the TypeScript and SQL folds to
   the same output on nine awkward inputs.
2. **"Paginated."** Backend §2: seven results, walked in pages of three under
   each sort, are seen exactly once each with a stable `total`. The page
   boundary *between* the boosted and unboosted groups neither repeats nor
   skips. A malformed cursor, or one from another sort, starts from the
   beginning. Flutter: "Show 12 more" sends the server's cursor and appends
   what comes back. A failed next page says so inline, keeps what was shown,
   and retries.
3. **"Filtered."** Backend §3 covers:
   - category, mode, and §1g ownership (`false` does not narrow);
   - price: an exact price inside the bounds, a range that overlaps them,
     never a quote while a bound is set;
   - an inverted range is a 400;
   - an `emergency` parameter is ignored.

   Backend §4 asserts all three sort orders. Flutter: each chip and the sheet
   send exactly what was chosen, with price in laari, and the island goes by
   id. Dismissing the sheet changes nothing.
4. **"Priority placement never surfaces an irrelevant listing."** Backend §5
   takes one premium provider with five listings, each failing exactly one
   predicate (text, island, category, mode, price). Under all five filters,
   the only result is an unboosted listing that matches.
5. **"Every boosted result is labelled."** Backend §5: a boosted result leads
   under every sort and carries `sponsored: true`. The sponsored results form
   one leading block. A trial boosts; a `free` row does not, even with
   `tier: premium` stored. That is the billing mapping, not a copy of it.
   Flutter: `Sponsored` is drawn only where the server said so, and it is
   spoken in the card's label.
6. **"Every card states its booking mode."** Backend §6: every result carries
   `slot` or `request` with the matching second signal, and the callback
   badge appears only on a `callbackEligible` category. Flutter: "Pick a
   time" and "Request a time" render per card, and nothing on the screen or
   in the sheet says Emergency or offers a tier filter.

## 3. Decisions the plan is silent on

The control session ruled on Q1–Q6 for the owner on 2026-10-10.

1. **Q1, Distance is an island-relative proxy, not a measurement.** No
   coordinates exist (consistent with decision 30). The chosen island is the
   gate. Inside it, listings serving **fewer islands rank first** (a
   Malé-only plumber is more local than one covering thirty), then rating,
   then id. With no island chosen, the same order applies without the gate.
   Nothing prints kilometres or claims "nearest", and the chip reads
   "Distance", as the artboard does.
2. **Q2, priority placement.** Boosted listings rank ahead under every sort.
   The sort still orders each group within itself, and every boosted result
   carries `Sponsored`. The boost never touches membership. There is no cap
   on the boosted count, because a cap would be an invented number. "Boosted"
   is exactly `getProviderEntitlements(…).priorityPlacement`, so trial,
   active, paused and expired-in-grace are boosted, as billing defines them.
3. **Q3, price.** Fixed, hourly and daily listings match on `priceLaari`. A
   range matches when it overlaps the filter. A quote is excluded while a
   bound is set and sorts last under Price. **Units are not normalised**:
   MVR 300/hour and MVR 500/job compare on the number. This is knowingly
   imprecise, and the design has no unit control, so ledger **P15-1**
   records it.
4. **Q4, the fields searched** are the listing's name, short description and
   tags, the category name, and the **business name** (the public headline on
   the profile and the listing page). No personal name and no contact field
   is ever read: the query does not join `user`.
5. **Q5, Category, Mode and Island are filters** because the artboard draws
   them. There is still no emergency filter, and no tier filter or rank
   input.
6. **Q6, `acceptingNewCustomers = false` is excluded.** The toggle "hides
   every service at once". This is about availability, not verification.
7. **An empty query is allowed** and lists everything in the island and
   filters. The category empty state's "browse everything on offer" needs it.
8. **Page size 12**, from the artboard's "Show 12 more". The maximum is 50.
9. **A cursor carries its sort.** A cursor from another sort, or a malformed
   one, starts from the beginning rather than returning a 500
   (`ProviderVisibility`'s precedent).
10. **Free text is capped** at 100 characters and 8 distinct words. Each word
    is reduced to `[a-z0-9]`, so no `LIKE` wildcard can get through.
11. **The rate limit is 120 a minute** per address, matching the public reads
    beside it.
12. **A listing in a deactivated category is not filtered out.** The listing
    page (§Phase 12) does not filter it either, and the two must agree.
    Deactivation's reach is §Phase 10b's question.

## 4. Where the build departs from the artboard

1. **The Filters sheet is new.** The artboard toasts "Opens price range" and
   similar. The owner approved one sheet with Category, Price (min and max in
   MVR, never preset bands), How you book and Maldivian-owned. Each chip
   opens it at its own section, and Apply counts the results first.
   Maldivian-owned is an `AppToggle` row where the approved preview drew a
   check, because the toggle is the system's control for an on/off choice.
2. **The category empty state drops "Providers join every week".** That is a
   growth claim the product cannot promise on launch day. The artboard's
   Plumbing special case ("No plumbers on …") is generic too: "No Plumbing
   providers on Hulhumalé yet".
3. **The filtered-out empty state names the filters but not the reason.**
   The artboard explains "services on Hulhumalé currently start above MVR
   300", and the server does not compute that.
4. **The Island chip reads "Island" until one is chosen.** That is Explore
   correction #4's rule: nothing defaults to Malé.
5. **The results screen has no bottom nav.** It is pushed with a back
   control, like Saved.
6. **The query pill goes back to Explore** with the same words in the field
   and focused. That is the artboard's `editSearch`.
7. **A failed "Show 12 more" says so inline** above a "Try again". The
   artboard has no such state, and `frontend/CLAUDE.md` asks for errors where
   the user can act.

`docs/design/sessions/round-64-search-corrections.md` carries 1–3 back to
the design project.

## 5. Changed outside the phase's own files

- `ProviderVisibility.visibleWhere(filters)` takes the filters
  `findVisibleProviders` already takes. Optional and additive; every caller
  is unchanged.
- `subscriptions/entitlements.ts`: `getProviderEntitlements`' row-to-
  entitlements step became `entitlementsFromRow`, and the new batched
  `priorityPlacementProviderIds` uses it. No behaviour change, and the Phase
  8a suite is untouched.
- `ApiClient` keeps `meta` beside an *object* payload as `_meta`, as it
  already did for lists. Search is the first endpoint that pages an object.
- `PublicServiceCard.sponsored`, default false, draws the artboard's pill.
- `AppRoutes.search`. Explore's field and tiles are wired, and its error and
  empty copy regain their search clauses (`explore-corrections.md` #2 and
  #3, closed). The two tripwires in `explore_chrome_test.dart` and the copy
  assertion in `explore_screen_test.dart` were rewritten to test where the
  controls go.
- The Explore emergency entry (correction #1) is still absent: it is owed by
  §Phase 16.

## 6. Ledger

**P7-3 closed.** The island filter reads the listing's own set. **P15-1
added**: price comparisons across units.
