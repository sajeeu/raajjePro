# Phase 17.3 — Emergency dispatch, offer collection & the reveal endpoint

Built 2026-09-28/29 against `01_Development_Plan_v5.md` revision 5.35: §Phase
17's **17.3 — Done when** (seventeen clauses), §1c's emergency rules and the
contact exception, and §1h's provider replacement.

This file records what the plan left open, the one conflict settled before the
build began, and four questions the owner decided mid-build. Two of the four
went against the build's first recommendation, and the backend was reshaped to
follow them.

---

## 1. The conflict settled before the build

**The contact reveal unlocks at `accepted` or later, not at `payment_claimed`.**
§0.3 says the opposite. §Phase 17 item 19, §1c and root `CLAUDE.md` invariant 1c
say "at `accepted` or later". §0.0's precedence rule settles it: §0.3 is the
historical record, and where it conflicts with a later section, the later
section wins. No plan edit is needed.

## 2. An emergency is a request first, and a booking only once someone is chosen

🔧 **Owner's decision, 2026-09-28 (question 1 below).** An emergency is raised
by **category and island** — `POST /v1/emergency-requests` — and never against
a listing.

- Round 23 put the emergency entry on Home and Explore and deleted the card
  marker because "dispatch never targets a provider".
- §1c computes the broadcast from "all providers whose listing is
  emergency-capable in that category, who serve that island".
- §Phase 17 item 2's listing-scoped emergency clause is pre-Round-23 residue.
  It has the same shape as the two other stale sentences this phase has already
  found: the flat 24-hour quote window, and the reveal at `payment_claimed`.

`Booking.listingId` and `providerProfileId` are NOT NULL, and a request names no
provider. So the **pre-selection half of §1c's machine lives on a new
`EmergencyRequest`**, which uses the same state names:

| `EmergencyRequest.status` | §1c's name for it | Moved by |
|---|---|---|
| `requested` | `requested` | creation; reject-all; the customer's silence; a re-dispatch |
| `emergency_offered` | `emergency_offered` | the round's first offer |
| `matched` | — | the customer selecting an offer |
| `declined` | the auto-decline | the answer window running out |
| `cancelled` | — | the customer withdrawing it before choosing |

The **booking is created at `accepted`** by the selection, against the chosen
provider's own emergency listing (`select-offer`, a creation edge). It moves on
to `awaiting_payment` in the same transaction, as every other mode does.
Nothing in §Phase 17.1 or 17.2 changed shape.

The owner weighed making the two columns nullable and rejected it. They are
denormalised precisely so the accept prompt needs no join, and every
provider-side query reads them.

**When the chosen provider falls through, their booking closes and the request
goes out again.**

- A no-show closes the booking as `cancelled` via `provider-not-arrived`, and
  its offer is marked `no_show`.
- A provider cancelling closes it through §Phase 17.1's own `provider-cancel`
  edge, with `cancelledByRole: provider` — the row §1f's cancellation rate
  counts.
- In both cases the request reopens with that provider excluded.
- The next selection is a **new** booking under the same request and the same
  fee. Each booking has exactly one provider for its whole life, so the one who
  did not come keeps their own record of it.

**`emergency_offered` is reached by no booking edge.** It stays in
`BookingStatus` (the API is additive-only), and `test/bookings-pricing.test.ts`
asserts that no booking edge reaches it.

## 3. How offers coexist without racing

🔧 **Every eligible provider may offer — owner's decision (question 4).** §1c:
the first acceptance opens a window "during which **every other eligible
provider may also accept**… At the end of it the customer is shown up to three
offers." "Up to three" caps what is *shown*, not who may bid. Capping admission
would reintroduce the race Round 15 removed, where the fastest three win rather
than the nearest or cheapest.

**Admission.** Each offer takes the request row through a conditional update
whose `WHERE` carries the open statuses and both windows. Postgres locks the
row for the first writer and re-evaluates the second writer's `WHERE` against
the committed row. So two simultaneous offers are serialised: both are
admitted, and the status moves once. No raw SQL and no explicit lock are
needed.

**One bid per provider.** A partial unique index allows one `open` offer per
provider per request. It is hand-written in the migration, because Prisma
cannot express a partial index, and it is partial because a provider released
by the customer's silence may answer the re-broadcast.

**Which three the customer sees — our ranking, because the plan names none:**

1. **Callout fee, lowest first.**
2. **The provider's own arrival estimate, soonest first** — the nearest thing to
   "nearest" that exists.
3. **The earlier offer**, so a tie is broken by something both sides can see.

The paragraph that sets the window says what it is for: the winner should be
"whoever was nearest or cheapest". Nearest cannot be computed (question 3), so
the estimate stands in for it. An offer outside the three cannot be selected,
and is released as `not_selected` when the customer chooses, like any other
unchosen offer.

**The one atomic claim** is on the offer the customer selects. Everything
selection does is one transaction: the claim, the release of every other offer,
the dispatch fee, the request moving to `matched`, the booking row and both
status events. The test forces a failure after the claim, asserts the spy was
reached (the 17.2 pattern), and then checks that no booking, no fee and no
claim survived.

## 4. The clocks

| Clock | Source | Stored as |
|---|---|---|
| Overall answer window | `Category.emergencyAcceptWindowMinutes` (30 for all four, Round 22) | `EmergencyRequest.windowEndsAt`, stamped at creation |
| Collection window | §1c flat: 90 seconds | `offerCollectionClosesAt`, set by a round's first offer |
| Customer's choice | §1c flat: 5 minutes after collection closes | derived |
| "Provider has not arrived" | the category's window, from the booking's `amountSetAt` | derived |
| Reveal expiry | §1c flat: 24 hours after the terminal state | derived |

- The per-category number is never a literal. Clause 17's test changes the
  seeded window and watches the next request's deadline move with it.
- The flat numbers live in `windows.ts`, each beside its §1c sentence.
- Both sweeps tick every **30 seconds**, because a five-minute tick could
  double the customer's five-minute choice.

🔧 **A re-dispatch after selection opens a fresh answer window — agreed with
the owner.** The Done-when's "without resetting the overall window" holds for
the two re-broadcasts **before** selection: reject-all and the customer's
silence. After selection the original window has long run out — a no-show is
only reportable once it has — so re-broadcasting into it would decline the
request on arrival.

## 5. The dispatch fee

The fee is a `PaymentSubmission` with `purpose: emergency_dispatch_fee` and
amount 20000 laari, **linked to the request**. It is created owed
(`submittedAt` null) inside the selection transaction.

- **One emergency, one fee.** A re-dispatch finds it already set and creates
  nothing.
- **Settling it.** The customer uses §Phase 8a's own proof upload and submit,
  reached from `/v1/users/me/dispatch-fees/…`. Those routes first check that
  the row really is a dispatch fee, so they cannot become a second door onto a
  subscription payment.
- **The block.** *Unsettled* means owed with no proof submitted. It is checked
  in `BookingService.bookableListing` (slot and request) and in emergency
  creation. Submitting proof lifts it while the row is still `pending`, and no
  admin is involved.
- 🔧 **An admin rejecting the proof does not re-impose the block.** The plan
  calls a fabricated receipt "a moderation matter", and never says a rejection
  blocks again.

Open, and recorded rather than decided:

- A booking auto-cancelled by the revocation cascade keeps its fee owed. §1c
  covers no-shows and says nothing about a platform-side cancellation.
- §Phase 10a part 2's admin confirm path resolves the payer to a provider and
  would refuse a customer. That is ledger **P17-6**.

## 6. The reveal

`contact-reveal.ts` is the only code in the system that reads `phoneE164` on
behalf of another user. Each condition has its own refusal:

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

**Condition 2 in this model.** An emergency booking begins at `accepted`, so a
broadcast has no booking to reveal on at all: the endpoint answers 404 to a
request id. The guard is still enforced, and the test proves it by forcing a
booking back to `requested`.

**Conditions 3 and 4 are read together.** The customer's call *is* the reveal.
A provider's call before that is provider-initiated and is refused. After it,
the provider's call is how they see the customer's number, and both calls
return both numbers.

**The kill switch** is a `KillSwitch` row keyed by a closed enum. §Phase 10b
says these are "incident controls, not a general feature-flag framework". A
missing row means the switch is not engaged. §Phase 10b adds the admin surface
and the other switches.

## 7. The revocation cascade

§Phase 17 item 21 says "below `silver`". That is Round 9's wording. The cascade
instead evaluates each in-flight emergency against **its own category's**
`emergencyMinimumTier`, through `emergencyEligibility`, as invariant 1c
requires. The owner agreed.

- At `accepted` or `awaiting_payment`, the booking auto-cancels and both parties
  are notified.
- Later than that, a system-filed Report (`provider_verification_revoked`, a new
  enum value) is raised and nothing else moves. At most one is filed per
  booking.

Nothing changes a tier yet, so this is reached from tests alone. Ledger
**P17-5** records the missing trigger; its twin is P8-3.

## 8. The broadcast, and the pass

**The broadcast rule**, computed in two halves:

- **By listing.** Only a listing query can see the island and the `isEmergency`
  flag.
- **By provider.** The candidates then go through `findVisibleProviders`, with
  the category's tier as the minimum. That helper gained one additive filter,
  `ids`, so suspension stays an input to the single shared helper (§1a).

Pages go out through §Phase 3c's `emergency_dispatch` kind at `emergency`
urgency, with the request's id as `subjectId`. Clause 5's test reads those rows
back.

🔧 **A pass is recorded and not counted — owner's decision (question 2).**
`PATCH /v1/emergency-requests/:id/pass` writes an `EmergencyPass`.

- It takes the request off that provider's list and out of any re-broadcast of
  it, and tells nobody.
- §1f's acceptance rate does not read it. That rule was written for bookings a
  provider was targeted with, and a broadcast reaches everyone eligible whether
  they wanted it or not.
- The record keeps a signal for tuning eligibility later.

## 9. The owner's four decisions, 2026-09-28

| # | Question | Decision |
|---|---|---|
| 1 | Create by listing or by category? | **By category and island**, as a request; the booking is created at selection (§2). *Overturned the build's first recommendation.* |
| 2 | Provider "Decline this request"? | **Record the pass, exclude it from acceptance rate** (§8). The artboard's acceptance-rate sentence gets a correction prompt. |
| 3 | "1.2 km" distance? | **Island-relative only.** No coordinates exist anywhere in the schema. Correction prompt. |
| 4 | "At most three" offers? | **Admit every offer, show three**, ranked (§3). *Overturned the build's first recommendation.* |

Also confirmed: the per-category tier bar in the cascade; the fresh window on a
post-selection re-dispatch; and a null rating until §Phase 11.

## 10. What this slice did not build

- **The Home and Explore entry points.** §Phase 16 and §Phase 15 place the
  emergency action. The request screen is routable now.
- **Admin confirmation of a dispatch fee** — §Phase 10a part 2 (P17-6).
- **The kill switch's admin surface** — §Phase 10b.
- **Real delivery of the new events** — §Phase 19 (P17-1, P17-7).
- **§1f's numbers.** No-shows, cancellations and passes are recorded here, and
  §Phase 11 computes the rates from them.
- **An open request in the account-deletion blocker.** A request with no chosen
  provider owes nobody a visit and closes itself within its window. It is noted
  here in case §Phase 3's deletion pipeline should wait for one anyway.

## 11. How to verify it

```
cd backend && npx vitest run test/phase17-3-done-when.test.ts
scripts/verify.sh
```

`test/phase17-3-done-when.test.ts` has one `describe` per clause, in the plan's
order. It also covers:

- each reveal condition individually;
- the pass;
- a phone-absence sweep over every endpoint this slice adds, checking both
  values and key names.

Each test uses a random island, so its broadcast recipients are its own.

## 12. The Flutter screens

Four screens and one card:

- `EmergencyRequestScreen` (`Emergency Flow`)
- `ProviderEmergencyScreen` (`Provider Emergency`)
- `RevealContactScreen` (`Reveal Contact`)
- `DispatchFeeScreen` (`Dispatch Fee`)
- `BookingEmergencyCard`, on Booking Detail

The artboard audit, and what each finding became, is
`docs/design/sessions/round-61-emergency-corrections.md`.

- **The trade's bar and window are rendered, never derived.** Both are read off
  the category on the form. Every countdown counts to a deadline the server
  gave; the screen never decides a window has closed, it re-reads.
- **The emergency accept is never queued** (§0.0 item 14). Offline, the send is
  replaced by a notice with a live retry, and the test asserts exactly one
  attempt with nothing parked.
- **No arrival preset is preselected**, and the offer cannot be sent without an
  estimate (Round 22).
- **Offers render in the server's order**, with the provider's own estimate
  labelled as theirs. There is no distance, and ratings read "No ratings yet".
- **A pass says it does not count against the provider.** The artboard's
  acceptance-rate sentence is not reproduced.
- **The reveal never calls a number "verified".** It says an admin confirmed it
  at verification and that it isn't checked live, and only at Bronze or above.
  There is no dialler yet, so the number is selectable and copyable.
- **The MVR 200 disclosure before sending is the one number the app states
  itself.** The server returns the fee only once it has been incurred, and the
  disclosure has to come before that.

**Where the entry points live.** The emergency action belongs on Home and
Explore (Round 23), which are §Phases 16 and 15. The screen is routable at
`AppRoutes.emergency`, and the provider view at `AppRoutes.providerEmergency`
for the push deep link. Those phases place the entry points.

**Not wired yet.** The slot and request creation screens show the server's
`DISPATCH_FEE_OUTSTANDING` sentence, but carry no "settle it" link; the
emergency form does.
