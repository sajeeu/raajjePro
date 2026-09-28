# Phase 17.3 — Emergency dispatch, offer collection & the reveal endpoint

Built 2026-09-28 against `01_Development_Plan_v5.md` revision 5.35: §Phase 17's
**17.3 — Done when** (seventeen clauses), §1c's emergency rules and the contact
exception, and §1h's provider replacement.

This file records what the plan left open, the one conflict already settled
before the build began, and four questions raised with the verification session
where the artboards and the plan disagree.

---

## 1. The conflict settled before the build

**The contact reveal unlocks at `accepted` or later, not at `payment_claimed`.**
§0.3 says emergency bookings "no longer unlock contact at accepted — they
unlock at payment_claimed". §Phase 17 item 19, §1c and root `CLAUDE.md`
invariant 1c all say "at `accepted` or later". §0.0's precedence rule settles
it: §0.3 is the historical record, and where it conflicts with a later section
the later section wins. The owner confirmed this in the brief, and Done-when
clause 1 already assumes it. No plan edit is needed.

In the code, "accepted or later" means two things together: the booking was
accepted (`amountSetAt` is stamped at `accepted`), and it is not back at a
pre-acceptance status. The second half matters because a re-dispatch after a
no-show returns the booking to `requested` and clears `amountSetAt`, so the
next provider starts with no reveal.

## 2. The shape of the machine

An emergency starts at **`requested`**, unlike 17.2's request path, which starts
at `awaiting_quote`. §1c says request mode inserts its states "before the
diagram" but emergency inserts `emergency_offered` "between `requested` and
`awaiting_payment`". The two paths diverge at creation, and the plan gives one
sentence to each. The verification session flagged this so the 17.2 shape would
not be copied.

| Edge | From → to | Actor |
|---|---|---|
| `create-emergency` | — → `requested` | customer |
| `emergency-offer` | `requested` → `emergency_offered` | provider (first offer of a round only) |
| `select-offer`, then `amount-set` | `emergency_offered` → `accepted` → `awaiting_payment` | customer |
| `reject-all-offers` | `emergency_offered` → `requested` | customer |
| `offer-choice-timeout` | `emergency_offered` → `requested` | system |
| `emergency-window-timeout` | `requested` / `emergency_offered` → `declined` | system |
| `provider-not-arrived` | `awaiting_payment` / `payment_claimed` / `confirmed` → `requested` | customer |
| `emergency-provider-cancel` | `accepted` … `confirmed` → `requested` | provider |
| `verification-revoked` | `accepted` / `awaiting_payment` → `cancelled` | system |

Selection writes **two** events, `accepted` and then `awaiting_payment`, as every
other mode does. `accepted` is where §1h's terms lock and where both the chat
and the reveal open, so the timeline has to show that moment.

## 3. Who owns an emergency before anyone is chosen

`Booking.listingId` and `providerProfileId` are NOT NULL. §Phase 17 item 2
creates an emergency through `POST /v1/listings/:id/bookings`, which means from a
listing. Until selection, those columns name the **origin listing** and
nothing more:

- `BookingService.authorize` gives the origin provider **no side** of the
  booking. They cannot decline it, cancel it or read it as theirs.
- Their `role=provider` bookings list excludes it.
- They reach it through the emergency inbox on the same footing as every other
  eligible provider.

At selection, both columns are **re-pointed** to the chosen provider and that
provider's own emergency listing, which `EmergencyOffer.listingId` records.
Everything downstream — the payment step's bank details, the provider's own
list, completion and the 7-day jobs — then reads the provider who is actually
coming, through 17.1 code this slice did not change.

The alternative was to make both columns nullable until selection. That would
have put a null check on every 17.1 and 17.2 path, so it was rejected.

## 4. How offers coexist without racing

Each offer is admitted by **one conditional increment** of
`Booking.emergencyOfferCount`, with this `WHERE`:

- status is `requested` or `emergency_offered`,
- the count is below 3,
- the overall window is still open,
- the collection window is unset or still open.

Postgres locks the row for the first writer, then re-evaluates the second
writer's `WHERE` against the committed row. So two simultaneous offers are
serialised, not raced: both are admitted, the status moves once, and a fourth
offer is refused by the same predicate. This needs no row lock and no raw SQL.

A **partial unique index** — one `open` offer per provider per request —
stops a double tap producing two bids. It is hand-written in the migration
because Prisma cannot express it. It has to be partial: a provider released by
the customer's silence is not excluded, and may answer the next broadcast.

The one atomic claim left in the flow is on the offer the customer **selects**
(`open → selected`, conditional). The claim, the release of the other offers,
the dispatch fee, the re-pointing and both status events are one transaction.
The test forces a failure after the claim and asserts the spy was reached — the
17.2 pattern — then checks that no fee, no claim and no status change survived.

## 5. The clocks

| Clock | Source | Stored as |
|---|---|---|
| Overall answer window | `Category.emergencyAcceptWindowMinutes` (30 for all four, Round 22) | `emergencyWindowEndsAt`, stamped at creation |
| Collection window | §1c flat: 90 seconds | `offerCollectionClosesAt`, set by a round's first offer |
| Customer's choice | §1c flat: 5 minutes after the collection closes | derived from `offerCollectionClosesAt` |
| "Provider has not arrived" | the category's answer window, measured from selection (`amountSetAt`) | derived |
| Reveal expiry | §1c flat: 24 hours after the terminal state | derived from the terminal stamp |

The per-category number is never a literal. Clause 17's test changes the
seeded window and watches the deadline move with it. The flat numbers live in
`windows.ts`, each beside the sentence of §1c that sets it.

Both sweeps tick every **30 seconds**, not the five minutes the 17.1 jobs use.
A five-minute tick could double the customer's five-minute choice window.

🔧 **A re-dispatch after selection opens a fresh answer window.** The Done-when
says an unanswered set of offers re-broadcasts "without resetting the overall
window", and that holds for the two re-broadcasts **before** selection (reject-all
and the customer's silence). After selection, the original window has long run
out — a no-show can only be reported once it has — so re-broadcasting into it
would decline the request on arrival. That would dead-end exactly the customer
§1h says must never be dead-ended. The window is read from the category again
and is never a literal. This was raised with the verification session.

## 6. The dispatch fee

The fee is a `PaymentSubmission` with `purpose: emergency_dispatch_fee` and
amount 20000 laari. It is created **owed** (`submittedAt` null) inside the
selection transaction. The customer settles it through §Phase 8a's own proof
upload and submit, reached from `/v1/users/me/dispatch-fees/…`. Those routes
first check that the row really is a dispatch fee, so they cannot become a
second door onto a subscription payment.

**Unsettled** means owed with no proof submitted. The check sits in
`BookingService.bookableListing` and in emergency creation, so it covers every
creation path. Submitting proof lifts it with the row still `pending`, and no
admin is involved.

🔧 **An admin rejecting the proof afterwards does not re-impose the block.**
The plan says the admin "acts on anything false" and calls a fabricated receipt
"a moderation matter". It does not say a rejection blocks again, and the block
exists to avoid making the customer wait on the admin queue.

**One emergency, one fee.** A no-show re-dispatch and a provider-cancel
re-dispatch both find `dispatchFeeSubmissionId` already set and create nothing.

Open, and not decided here: a booking **auto-cancelled by the revocation
cascade** keeps its fee owed. §1c makes the fee non-refundable on a no-show, but
says nothing about a platform-side cancellation. The fee stays owed, and that
choice is in the queries sent to the verification session.

**§Phase 10a part 2's admin confirm does not handle this purpose.**
`SubscriptionService.confirmSubmission` resolves the payer to a provider profile
and would refuse a customer. That admin path is deferred with the rest of the
panel (ledger **P10-DEFER**), and ledger **P17-6** records what it must add.

## 7. The reveal

`contact-reveal.ts` is the only code in the system that reads `phoneE164` on
behalf of another user. It checks each condition with its own error code, so a
test can see each one refuse for the right reason:

| Condition | Refusal |
|---|---|
| (runtime) kill switch, checked first | `CONTACT_REVEAL_PAUSED` |
| 1 emergency only | `CONTACT_REVEAL_EMERGENCY_ONLY` |
| 2 accepted or later | `CONTACT_REVEAL_NOT_ACCEPTED` |
| 3 customer-initiated | `CONTACT_REVEAL_CUSTOMER_INITIATES` |
| 4 both or neither | `CONTACT_REVEAL_UNAVAILABLE` |
| 5 counterparty notified | `contact_revealed`, once, on the first customer call |
| 6 24 hours after terminal | `CONTACT_REVEAL_EXPIRED` |
| 7 logged | a `ContactRevealEvent` row, IDs only |

Conditions 3 and 4 have to be read together. The customer's call **is** the
reveal. The provider's call is how the provider sees the customer's number
afterwards: it is refused while no customer reveal exists, because that would be
provider-initiated, and answered once one does. Both calls return both numbers.

**The kill switch is a `KillSwitch` row keyed by a closed enum**, because
§Phase 10b calls these "incident controls, not a general feature-flag
framework". No row means not engaged. Only the one switch this slice checks is
defined; §Phase 10b adds the rest and the admin screen. A check against a flag
with no admin surface is the intended state (§0.0 item 20).

## 8. The revocation cascade

§Phase 17 item 21 says "drops below `silver`". That is Round 9's wording, and
Round 15 made the emergency gate per-category. The cascade therefore evaluates
each in-flight emergency against **its own category's**
`emergencyMinimumTier`, through `emergencyEligibility`, the one place the
composed rule is written. The effect: a gold electrician demoted to silver loses
Electrical work and keeps AC Repair work.

- At `accepted` or `awaiting_payment`, the booking auto-cancels and both parties
  are notified.
- Later than that, a system-filed Report (`provider_verification_revoked`, a new
  enum value) routes it to admin, the booking is left untouched, and at most one
  Report is filed per booking.

Nothing in the codebase changes a tier yet, because that is §Phase 10a part 2's
verification queue. So `onProviderTierChanged` is reached only from tests, the
same position as `ListingService.reevaluateEmergencyEligibility` (ledger P8-3).
Ledger **P17-5** records the wiring.

## 9. The broadcast

The rule is: an emergency-capable category, a published and active emergency
listing with a live service area on the job's island, the category's tier,
`acceptingNewCustomers`, not suspended, not excluded, and not the customer.

It is computed in two halves:

- **By listing.** Only a query over listings can see the island and the
  `isEmergency` flag.
- **By provider.** The candidates go through `findVisibleProviders`, with the
  category's tier as the minimum. That helper gained one additive filter, `ids`,
  so suspension stays an input to the single shared helper (§1a) instead of a
  second copy inside the dispatcher.

The broadcast goes out through §Phase 3c's `emergency_dispatch` kind at
`emergency` urgency, which sends push and email together. Every send is a
`PushDispatch` row, and the clause 5 test reads those rows back.

## 10. Questions raised with the verification session

Each question has a recommended option and was sent on 2026-09-28. The build
follows the recommendation. Every one can be reversed without touching the
machine.

1. **Emergency Flow picks a category, not a listing.** The plan creates
   emergencies from a listing, and clause 3's "by an unverified provider" only
   makes sense with a listing. *Built:* the listing-scoped endpoint only. The
   screen opens with the listing's category fixed. Round 23's Home/Explore entry
   arrives with §Phase 16 and needs its own plan line.
2. **Provider Emergency's "Decline this request"** says a pass "is counted in
   your acceptance rate". The plan has no broadcast decline, and §1f does not
   say whether a pass counts. *Built:* no server-side decline. The pass hides the
   request on the device, and the acceptance-rate sentence goes in a correction
   prompt.
3. **Offer cards show "1.2 km"**, and §1c lists distance too, but the system
   knows islands and has no coordinates. *Built:* distance is omitted, and the
   card shows the island.
4. **"At most three."** A fourth offer is refused (`EMERGENCY_OFFERS_FULL`) so
   that provider is released at once, and the window still closes at 90 seconds.

Also decided without asking:

- **Rating is null until §Phase 11.** A number there would be invented.
- **Emergency jobs need both the description and the island.** The island is
  what the broadcast matches on, and the description is all a provider has to
  price a callout from.
- **The emergency accept is not in the offline queue** (§0.0 item 14). Offline,
  the control is replaced by a notice with a live retry.

## 11. What this slice did not build

- **The Home/Explore emergency entry** — §Phase 16, per question 1.
- **Admin confirmation of a dispatch fee** — §Phase 10a part 2 (P17-6).
- **The kill switch's admin surface** — §Phase 10b.
- **Real delivery of the new notification events** — §Phase 19. The seam fires
  them, as it does 17.1's (P17-1). `contact_revealed` has no push kind yet.
- **§1f's conduct numbers.** `EmergencyOffer.state = no_show` and the status
  events are what §Phase 11 will read. This slice records them and computes
  nothing.

## 12. How to verify it

```
cd backend && npx vitest run test/phase17-3-done-when.test.ts
scripts/verify.sh
```

`test/phase17-3-done-when.test.ts` has one `describe` per clause, numbered in the
plan's order. It also checks each reveal condition individually, and runs a
phone-absence sweep over every endpoint this slice adds, checking both values
and keys. Each broadcast test uses a random island, so its recipients are its
own even inside one run.
