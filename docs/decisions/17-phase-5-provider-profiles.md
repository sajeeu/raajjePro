# Decision 17 — Phase 5, provider profiles

**Status: built 2026-09-09.** Backend only, as §Phase 5 states. Plan §Phase 5, §1a, §1c, §1e, §1f, §1g.

---

## What the plan settled, and what it left to this phase

§Phase 5 names the entity's fields, the two functions every later phase calls, and five Done-when lines. Most of it is transcription. What it does not settle is **where the data two of its rules depend on comes from**, because §Phase 5 is sequenced before the phases that create it — there is no `Listing` table until §Phase 8 and no `Booking` until §Phase 17, and §Phase 5's central helper is defined in terms of both.

Nine decisions were made here. Each is recorded with its reasoning.

### 1. Two seams, because the rule can be written before its data exists

`findVisibleProviders` derives visibility from `count(listings WHERE status='published' AND visibility='active') > 0` (§1a). The read surface for §1f's conduct metrics displays numbers computed from booking outcomes. Neither table exists yet.

The three ways out were: invent a minimal `Listing` (building ahead into §Phase 8's schema, which Scope Discipline forbids), defer the helper entirely (its Done-when is explicit, and the ledger rule is that a testable line is tested now), or inject the missing input.

Injected, following the precedent Phase 3 set with `DeletionBlocker` and `ExportContributors`:

- **`PublishedListingSource`** answers "which of these providers hold at least one published, active listing?" and nothing else. Suspension is not its business — the helper applies that. Phase 8 supplies the real implementation as one `groupBy` over `listing`.
- **`ProviderConductSource`** returns §1f's seven metrics plus two counts, batched. Phase 11 supplies it.

The defaults are `NO_PUBLISHED_LISTINGS` and `noConductRecorded`, and both answer honestly rather than optimistically: before listings exist nobody is publicly visible, and before bookings exist no rate is computable. That distinction matters for conduct — `noConductRecorded` reports **null**, not zero, because "0% on time" and "never been booked" are different claims and only one of them is true.

What this buys: the §1a rule is written **once, today**, in the place every consumer will call, and Phase 8 fills a hole rather than inventing a rule. What it costs is in decision 2.

### 2. Paging over a seam over-fetches, and says so

The published-listing predicate cannot be part of the SQL while the table it names does not exist, so `findVisibleProviders` scans candidates in batches of 200 and accumulates until the page is full or the candidates run out. It is correct — a caller never receives a short page and concludes there is no more data — and it is more round trips than the eventual single joined query needs.

Left as is deliberately. Folding the predicate into SQL is a one-function change **inside the helper**, invisible to every caller, and doing it now would mean guessing Phase 8's column names. The contract that must not change is the one in the doc comment: one helper, suspension as an input, no stored flag.

### 3. `suspendedAt` is a column here; the admin action stays Phase 10b's

§1a calls suspension "an input to visibility" so that one change covers search, Home and the public profile. The §Phase 5 Done-when requires `findVisibleProviders` to exclude a suspended provider. So the **column and the filter** are Phase 5's; the **admin suspend/unsuspend endpoint, its required reason and its audit entry** are §Phase 10b's, and none of them was built here.

It went on `ProviderProfile` rather than as a fourth `UserStatus`. `frozen` already means "a deletion request is pending" with its own behaviour, and widening a Phase 3 enum used across four modules to carry an unrelated meaning is the kind of repurposing the additive-only rule exists to prevent. §Phase 10b's own wording ("suspending a user") describes an effect that is entirely about provider visibility.

`frozen` and `anonymised` accounts are excluded by the same predicate, for the same reason suspension is: putting it in the helper means no consumer has to remember.

### 4. The provider sees their own conduct numbers below the public floor

§1f states two rules that meet here. "Nothing displays below a 10-completed-booking floor" — and "every metric is visible to the provider on their own dashboard before it is visible to anyone else. Nobody should learn their on-time rate from a customer."

Resolved by shape, not by suppression:

- `PublicProviderDto.conduct` is `{ jobsCompletedCount, metricsBelowFloor: true, metrics: null }` below the floor — the job count and nothing else.
- `OwnProviderDto.conduct` carries the numbers **and** `publiclyVisible: false`, so the provider sees where they stand and also sees what a customer currently sees instead.

**The flag is `metricsBelowFloor`, not `newProvider`.** It was `newProvider` on the first pass and the QA review caught what that name asserts: the floor is measured against the window (below), so a business with 47 lifetime jobs and 9 this quarter would have rendered as "New provider · 47 jobs completed" — a flag contradicting the count printed beside it. §1f's "show 'New provider' and the job count" is display copy, and Phases 12 and 13 have both numbers here to decide it from.

**The floor is measured against completed bookings in the rolling 90-day window, not the lifetime count.** §1f does not say which. A provider with forty jobs two years ago and one this quarter would otherwise clear a lifetime floor and show a 100% rate computed from a single booking — precisely what the floor exists to prevent. `jobsCompletedCount` stays lifetime, because it is the "47 jobs completed" figure and the only one that shows below the floor.

### 5. No field on any shape can hold an editorial label

§1f rejected "Prone to cancel", "Price hiking" and every euphemism for them in Round 15 — automated public accusations, computed from thin data, in a market where a wrong one is somebody's livelihood and a plausible defamation claim.

Enforced structurally rather than by intention: every conduct field is a number, a boolean or null. There is nowhere for a string to go. `providers-profile.test.ts` sets a 90% cancellation rate — the case a label would have fired on — and asserts the serialised response contains none of eight label-shaped words and that every metric value is a number or null.

### 6. Payment details and the phone are excluded by shape, not by discipline

Both Done-when lines are about absence, and absence enforced per handler is absence that eventually stops being enforced.

- **The phone number is not a column on this entity at all.** §Phase 5 stores exactly one, and Phase 3 already put it on `User`. A second copy is a second thing to protect. `schema-phase5.test.ts` asserts `provider_profile` has no `phone`, `whatsapp` or `viber` column — §0.2's dropped handles cannot be revealed by anything because they are not collected.
- **Payment details are reachable from exactly two mappers.** `toPublicProviderDto` has no field for them, so no public path can carry them at any nesting depth. `paymentDetailsForBooking(providerId)` is the booking payment step's accessor (§1c step 6) and **takes no viewer on purpose** — it is not a route and must never become one; the booking-scoped authorization is Phase 17's, because only Phase 17 can see a booking.

`GET /v1/bookings/:id/contact-info` is asserted to 404. It is not the emergency reveal and it is not coming back.

### 7. Own-data reads are the reading of "every response"

The Done-when says payment details are absent from "every response except the booking payment step". Read literally that would also exclude the provider's own read of their own bank details — which makes §Phase 6a's collection step un-editable and §Phase 10a's billing UI unbuildable.

Taken as **every response to another user**, on the precedent the phone already set: the same Done-when carves out "their own profile read" for a phone number, which is under a stricter rule. So `GET /v1/providers/me` carries them, and so does §Phase 3's data export, whose existing comment already reads "own data — so the phone is present". Everything reachable by another user carries neither.

Flagged rather than silent, because it is an interpretation of an acceptance line and not a transcription of it.

### 8. Four stored columns are absent from the update body, and the absence is the enforcement

`verificationTier` / `verificationStatus` (admin-transitioned, §1e), `maldivianOwned` (§1g: *verified* rather than self-declared), `subscriptionPriceLaari` (§1b: written once at first confirmed payment, by Phase 8a) and the suspension pair (Phase 10b's) are not keys on `updateOwnProviderBody`. An unknown key is stripped, so a request naming one leaves the stored value untouched instead of erroring — the test asserts the **row**, not the status code, and checks that a legitimate field in the same request still landed.

`subscriptionPriceLaari` is nullable with no default. §1b says it is "set at their first confirmed payment", and §1b's cohort rule — the introductory rate for the first 100 providers, the standard rate after them — is Phase 8a's to apply. Null means *not yet set*, which is a different fact from MVR 150, and the two-price-point conversion measurement §1b wants depends on nothing here pinning one.

### 9. §1g is gated in the mapper, not by a database constraint

"Below Gold the attribute is absent rather than false" (§1g). A `CHECK` tying `maldivian_owned` to the gold tier would block an admin demoting a provider until the attribute was cleared, and would force a re-promotion to re-derive something the registration document already evidenced. So the column stores what Gold review found and **both mappers return null unless the tier is currently `gold`**.

`providerType` (`individual` / `business`), which §1g's attribute hangs from, is §Phase 6a's field by that phase's own wording and was not built here.

### 10. The public read applies the gate; it does not trust its caller

`readPublic` calls `visibility.isVisible` and throws `NotFoundError` when it fails, which is §Phase 13's Done-when ("returns a proper not-found state for a drafts-only provider's id") enforced one layer below the route that will answer it.

The first pass documented the check as the *consumer's* job — and that is exactly the per-consumer-remembers pattern §1a exists to delete. Four consumers are coming (Phases 12, 13, 15, 16); one of them would eventually have skipped it, and the failure mode is a suspended provider rendering as bookable.

There is deliberately **no unchecked variant**. One was added alongside the fix, on the theory that `findVisibleProviders` would want to skip a per-row re-check — it does not, because it already holds the rows it resolved. An unchecked public mapper reachable by name is the hole this decision just closed, left open under a different name.

### 11. A read never creates the profile; a write does

The first pass called `getOrCreate` from `GET /v1/providers/me`, and the QA review found what that costs: `isProvider` on `userDto` is `providerProfile !== null`, §Phase 6's role switcher and §Phase 6a's "never sees it again" both route on it, and nothing is ever hard-deleted (invariant 8). So merely opening a screen turned a customer into a provider, permanently, including a frozen account that is supposed to start nothing new.

The read now 404s and the **write** creates. §1a names the creation moments — Phase 6a's onboarding and the first `POST /v1/listings` — and a user sending a business name and bank details is unambiguously that; opening a screen is not.

---

## Two places the plan and the build disagree

Recorded rather than resolved silently, per CLAUDE.md's Scope Discipline.

**1. §Phase 5's Done-when 5, read literally, would forbid a provider reading their own bank details.** See decision 7 — the build takes "every response" as "every response to another user", on the precedent the phone carves out in the same sentence, because the literal reading makes §Phase 6a's collection step un-editable and §Phase 10a's billing UI unbuildable. **The plan's wording is what should change**, to "absent from every response to another user except the booking payment step". It has not been changed here; the plan is amended by its owner, not by a phase.

**2. §Phase 6a's Done-when routes a phone number through this phase's endpoint, and cannot.** It requires that "completing account details persists **phone** and payment details onto the Provider Profile via the existing Phase 5 update endpoint". There is no phone field on `ProviderProfile` and no phone key on `updateOwnProviderBody`, deliberately and per §Phase 5's own single-copy rule — so the phone half of that line routes to Phase 3's `PATCH /v1/users/me/phone`, and only the payment details come through `PATCH /v1/providers/me`. §Phase 6a's builder needs to know this before they start; it is not a defect in either phase, just a line written before the single-copy rule existed.

---

## What account deletion erases, and what survives

`registerProviderAnonymisation` runs inside the anonymiser's transaction, so a failure leaves the profile intact to be retried rather than half-erased. It clears the **bank details** and the **bio** — free text a provider wrote about themselves, which routinely names them. `businessName` was already cleared by the anonymiser itself.

Left in place: `verificationTier`, `verificationStatus`, `maldivianOwned` and `subscriptionPriceLaari`. §1e requires the decision and the evidence type to persist after the images are purged, and a verification history that vanished with the account would make a re-registration indistinguishable from a first-time signup. None of the four names a person.

---

## What this phase did not build

Named here so the next reader does not go looking:

- **No public provider endpoint.** §Phase 13 builds the public profile and its own Done-when covers the not-found state for a drafts-only provider — which this phase has no listings to produce. `toPublicProviderDto` and `visibility.isVisible` are what it reuses.
- **No admin surface.** Tier transitions are §Phase 10a's identity queue; suspension is §Phase 10b's.
- **No `providerType`, no default service areas, no identity-document columns** — §Phase 6a, §Phase 7 and §Phase 10a respectively.
- **No frontend.** §Phase 5 is marked *(backend only)*.

---

## Deferred verification

Rows **P5-1** through **P5-4** in `docs/deferred-verification.md`:

- **P5-1** — a real published listing moving a provider across §1a's line (Phase 8).
- **P5-2** — §1f's numbers computed from real booking outcomes (Phase 11).
- **P5-3** — the three consumers §Phase 5's suspension line names reaching the rule through the one helper (Phases 13, 15, 16).
- **P5-4** — that the payment-step exception is actually scoped to a booking (Phase 17.1). This one was missing on the first pass: the line was asserted by calling the accessor directly, which proves the mechanism and not the scope, and invariant 6 requires a row for exactly that.

Each is held open by a table or a route a later phase creates. None could have been tested here — the QA review confirmed the seams are a legitimate reading of the sequencing and not a way around a Done-when, with the one exception it found in decision 10, which was testable today and is now tested.
