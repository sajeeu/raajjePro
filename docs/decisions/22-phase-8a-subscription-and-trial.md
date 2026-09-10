# Phase 8a — Subscription & Trial

Built 2026-09-10 against `01_Development_Plan_v5.md` §Phase 8a and §1b (plan
revision **5.28**). Backend only, as the section's own heading says. What
follows is what was decided during the build and why, in the order the
decisions were forced. The plan is the source; this file is the record of the
places it left a choice.

---

## 1. Six questions went to the owner before the schema landed, and two changed the build

The same sequence Phase 8 used. Six decisions were put to the owner at the
start, each with a recommendation, and all six came back settled **in the
plan** (revision 5.27 → 5.28) rather than in a chat. Four confirmed the
recommendation; two changed what got built.

**Changed the build.**

1. **The 7-day trigger prompts; it does not start a trial.** §Phase 8a's third
   trigger bullet ends "all three call the same `startTrial(providerId)`
   function", and the build was written that way. The plan now says otherwise
   and explains why: a trial is one per account and non-renewable, and this
   job fires *precisely when no booking has landed* — so starting it there
   spends the provider's only trial when premium is worth least, analytics
   over no data and priority placement in a market with no demand. **Two
   triggers start a trial and one nudges toward the second.** The job sends
   `trial_prompt` and leaves `trial.available` true.
2. **The introductory-rate conversion is a fifth scheduled job.** §Phase 8a's
   job list names four; §1b requires the introductory rate to be honoured for
   twelve months and then convert with thirty days' notice, and no other phase
   owns it (§Phase 10a is the billing UI, §Phase 10c only *measures* the
   conversion). It is built here, and the plan's job list now names it.

**Confirmed the recommendation.**

3. **Premium's active-listing cap is unlimited.** §1b says premium "unlocks
   multiple active listings" and names no number, so there is no number:
   `PREMIUM_ACTIVE_LISTING_CAP` is `Infinity` and the DTO renders it as
   `null`, meaning *no limit* and never *unknown*. Inventing five or ten would
   put a limit in the product that a provider would hit with no rule to point
   at.
4. **The `acceptingNewCustomers` toggle *is* the pause** — one function, two
   doors (§4 below).
5. **RaajjePro's own bank details are typed configuration**, unset in
   development and required in production (§6 below).
6. **The appeal action is not built.** Ledger row **P8A-1** is the plan's own
   record of why: §1b step 5 and §Phase 10a both offer "resubmit **or**
   appeal", and no section says what an appeal changes. Resubmit is met — a
   rejection carries no cooldown, so a fresh submission *is* the resubmit —
   and it is built and tested.

One thing needed no answer and is recorded because it was stale in the plan
itself: **the trial is 30 days, not 60.** §0.4 still said 60, which Round 12
halved; §0.0 item 5 and §1b's tier table both say 30 and §0.0's precedence
rule settles it. The plan's §0.4 now carries the correction.

## 2. `getProviderEntitlements` reads a stored status, and that is the point

§Phase 8a requires a "live DB read every call, no caching". It is one
`findUnique` on `provider_subscription` selecting two columns, and the tier
falls out of the status.

What it deliberately does **not** do is recompute the status from the dates.
That would make it check-on-read, which `backend/CLAUDE.md` rules out ("if a
transition should happen at a time, a job makes it happen at that time") — and
it would put a second implementation of the lifecycle next to the job's. The
consequence is stated plainly: if the lifecycle job stops running, a lapsed
trial keeps its premium until the job runs again. That is the same exposure
every scheduled transition in this codebase has, it is heartbeat-monitored
(§Phase 0's `job_heartbeat`), and §1b's seven-day grace period means the
window where it matters is a week wide rather than a minute.

Three properties are asserted at the function rather than through an endpoint
(`test/subscriptions-entitlements.test.ts`):

- **A missing row is the free tier**, not an error and not unknown. Nothing
  creates a row at signup, so this is the state most providers are in.
- **A pending submission grants nothing**, structurally: this function cannot
  see `payment_submission`, so there is no branch to get wrong. The test adds
  three submitted, pending payments and asserts the answer does not move.
- **`expired` carries premium.** §1b's grace is "7 days after expiry **with
  nothing changing**" — if `expired` dropped the tier there would be no grace,
  only a downgrade with a seven-day delay before the notification.

## 3. Downgrade and restore are one function

§1b's requirement is that "**upgrade restores exactly what downgrade hid**".
The safest way to guarantee that is not to have two code paths agree — it is
to have one function decide which listings the current entitlement lets a
provider keep live, and reconcile to it. On premium the cap is unlimited,
every candidate is kept, and every `hidden_over_cap` row comes back.

`applyEntitlementVisibility` is therefore called from four places — a
confirmation, a reversal, a trial start and the lifecycle sweep — and
§Phase 17.1 should call it on a booking's terminal transition. It composes
`PUBLICLY_VISIBLE_LISTING` from §Phase 8 rather than restating the clauses,
and widens exactly one field: `visibility IN ('active', 'hidden_over_cap')`,
which is the pair §1b (Round 17) makes the entitlement system's own. A
provider-hidden or admin-hidden listing is invisible to this file, and the
test asserts an upgrade does not resurrect one.

**The cap is filled by protected listings first.** §1b says a protected
listing "stays visible **regardless of cap**", so protected rows are kept
first and the slots left over — never fewer than none — go to the
highest-performing unprotected ones. A provider whose committed jobs already
exceed their cap keeps all of them and nothing else, which is the only reading
under which both halves of §1b hold at once.

**Three readings the ranking sentence left open.** §1b ranks by "confirmed
bookings over the trailing 90 days, falling back to listing views where
booking counts tie, and only to recency where a provider has neither":

- **Views are counted over the same 90 days.** Lifetime counters would let a
  listing that was popular last year outrank one customers are looking at this
  week, and the framing is performance rather than history.
- **"Recency" is `firstPublishedAt`, not `updatedAt`.** The rule this replaced
  was gameable *because* it read a field a provider can touch at will, and
  `updatedAt` is that field. This matters more than it looks right now: with
  no bookings until §Phase 17.1 and no view events until the discovery phases,
  every listing ties at zero and zero, so recency decides everything.
- **The final tiebreak is the id**, so two listings published in the same
  millisecond do not hide a different one on every sweep.

## 4. One pause, two doors

§1b: "pause keys off the provider-level `acceptingNewCustomers` toggle". The
owner confirmed that as literal, so turning the toggle off starts the pause
and turning it on resumes — and `POST …/subscription/pause|resume` reach the
*same* function rather than a second one.

The wiring runs one way. `ProviderProfileService` gained a listener
(`onAcceptingNewCustomersChanged`, registered in `app.ts`, the same shape
`ExportContributors.register` and `AnonymisationHooks.register` take), and the
billing endpoints write the toggle **through that service**. So Phase 5 never
learns what a subscription is, and there is exactly one implementation of what
happens to the clock. Two independent pause states would be the same failure
as a stored copy of a derived rule, in state form.

Three consequences worth stating:

- **The billing endpoint is where a refusal is reportable.** "You have used
  all ten days" and "there is nothing running to pause" are answers a provider
  who asked to pause *billing* needs. Setting the toggle directly is a
  different act — availability, which is always theirs — and is never refused
  for a billing reason.
- **Resume is tolerant where pause is strict**, and works for a provider with
  no subscription at all. A billing endpoint must never be able to leave
  somebody stuck at "not accepting new customers".
- **At the cap the clock resumes and the toggle is left alone.** Whether a
  provider takes work is theirs to decide; only the billing clock is capped.

**The toggle's copy is now owed.** The plan says the consequence "must be
**said** rather than discovered: turning off new customers consumes pause
allowance and shifts the billing anchor, so the toggle's own copy carries that
sentence wherever it renders". It renders today in §Phase 6a's onboarding step
2, whose copy comes from `Become a Provider.dc.html` and does not say it. This
phase is backend-only and the prototype is the source (root `CLAUDE.md`:
"never rework a design directly"), so the obligation is ledger row **P8A-4**.

## 5. 🔧 The pause counter is minutes, where §Phase 8a's field list says days

§Phase 8a names `cumulativePausedDays` and `remainingPauseAllowanceDays`. The
column is `cumulativePausedMinutes`, and the deviation is what makes the cap
real: stored as whole days, a 23-hour pause rounds to zero and can be repeated
forever. That is a hole in a limit, not a rounding nicety. There is one budget
of 14,400 minutes, spent at whatever granularity a provider pauses at.

The API still speaks in days, derived in the DTO and **rounded in opposite
directions so neither number overstates the provider's position**: what is
spent rounds up, what is left rounds down. A 23-hour pause reads as one day
used and nine left. `test/subscriptions-pause.test.ts` runs eleven 23-hour
pauses and asserts the budget stops at ten days.

## 6. RaajjePro's own bank details are configuration, and `null` beats an example

`BILLING_BANK_NAME` / `_ACCOUNT_NAME` / `_ACCOUNT_NUMBER`, unset in
development and **required in production** — the posture `EMAIL_TRANSPORT` and
`MEDIA_STORAGE` already take, and for the same reason: a seam whose absence
production tolerates is decorative. All three or none, because a
half-configured account is the worst of the three states (the screen renders
and the transfer goes nowhere).

Where they are unset, `upgrade-request` returns `bankTransfer: null` rather
than an example account. A provider who transfers money to a made-up account
number has lost it, and no default is worth that.

## 7. The submission has four states of its own, and `submittedAt` is the fourth

§1b's mechanism is four steps and the row exists from step 1 — that is what
generates the reference code the provider writes on the transfer. But
`pending` in the admin queue has to mean step 3, proof uploaded and submitted:
an intent nobody finished is not work for an admin, and §1b's 48-hour SLA is
measured from the moment there is something to review.

`submittedAt` is the difference, and it is a field §Phase 8a's own list names.
The queue filters on `submittedAt IS NOT NULL`; the test asserts an
unsubmitted intent never appears in it.

**`proofObjectKey`, not `proofUrl`.** §Phase 8a's field list says `proofUrl`,
and §Phase 8's `MediaStorage` hands out short-lived signed URLs re-issued per
read — precisely so an image stops being reachable when the thing it belongs
to does. A stored URL would be a stored credential with an expiry date in it.
The column is the key and the DTO carries the URL, exactly as `ListingMedia`
does.

The proof goes through §Phase 8's three-step upload against a new purpose
(`payment-proof`), which means the type sniffing, the size ceiling and the
EXIF stripping all apply. A payment proof is a photo of a bank-app screen
taken on a phone; it carries the same location metadata a listing photo does.

## 8. A confirmation renders the invoice before it commits

Order matters here, and there are only bad alternatives:

1. **Reserve the invoice number** from a Postgres sequence, outside the
   transaction. A sequence is non-transactional by design, so a rolled-back
   confirmation burns a number and leaves a gap. A gap in an invoice series is
   a bookkeeping curiosity; a duplicate number is a broken document, and a
   count of existing rows produces duplicates the first time two admins work
   the queue at once.
2. **Render the PDF and store the bytes**, still outside the transaction. A
   storage failure then aborts the confirmation instead of committing an
   invoice row whose document does not exist.
3. **The transaction**: move the submission `pending → confirmed`
   *conditionally* (one `updateMany` with the status in the WHERE, so two
   admins produce one confirmation and one 409), write
   `subscriptionPriceLaari` if this is the provider's first confirmed payment,
   set the anchor if there is none and extend the period, insert the invoice,
   audit.
4. **Outside again**: reconcile the listings (it asks the booking source a
   question) and fire the notification. A failure there leaves listings hidden
   until the next sweep, which reconciles them — the recoverable direction.

The concurrency case is tested with two enrolled admins confirming the same
submission in parallel: one 200, one 409, one invoice.

**A payment made during a trial does not waste the trial.** The period starts
from the later of the current period end, the trial end and now. §1b has no
rule for it, and the alternative charges a provider for time they already had.

## 9. What a reversal takes back, and why it does not grant grace

§1b: "an admin can reverse a confirmed payment (mistake, bank reversal).
Explicit endpoint with an audit-log entry, never a database edit." §Phase 8a's
Done-when adds "a reversal restores prior state and is audit-logged".

The period the payment bought is removed — `currentPeriodEnd` goes back to the
invoice's `periodStart` — and what the provider then holds is **re-derived**
rather than forced to free, because reversing one payment of three must not
cancel the other two. The test confirms two payments, reverses one, and
asserts the provider is still `active` with thirty days left.

**No grace period on a reversal.** §1b's seven days "with nothing changing"
exist for a subscription that *lapsed*: the provider paid, the period ran out,
and they are given a week. A reversal says the money never arrived, so there
is nothing to be gracious about. The provider goes to the free tier,
`downgradedAt` is stamped — which puts them in the same win-back path as any
other downgrade, since their situation is identical: listings hidden, intact,
and one confirmed payment restores them.

The submission returns to `rejected` with the reversal columns set, rather
than gaining a sixth status. The enum is §Phase 8a's three values, and what a
reversed payment has in common with a rejected one is exactly what matters
downstream: it granted nothing. The invoice is **voided**, never deleted
(invariant 8) — a document that was issued cannot be made never to have
existed.

## 10. The PDF is written rather than imported

Fourteen lines of Helvetica on one page. Writing the file is ~80 lines of a
format whose text-only subset has been stable since 1993; the alternative is a
dependency that brings a font subsetter, a stream layer and a vector graphics
API, pinned and audited in CI and eventually somebody's upgrade. That trade
goes the other way the moment an invoice needs a logo, a table or a second
page, and the boundary for that is `renderInvoicePdf` returning bytes.

Two things this decision costs, both stated in the file:

- **Non-Latin text is not representable.** The base-14 fonts a reader must
  have carry WinAnsi, so a Thaana business name degrades to `?` rather than
  producing a corrupt file. Dhivehi/Thaana localisation is explicitly out of
  v1 scope (root `CLAUDE.md`); the phase that puts it back in scope is the one
  that embeds a font here.
- **The punctuation this codebase writes needs mapping.** An em dash is
  U+2014 and WinAnsi puts it at 0x97 — without the map, "Provider
  subscription — 30 days" renders as "subscription ? 30 days". **This was
  found by checking the output with `pdftotext`**, not by reading the code:
  poppler is an independent implementation, and it also confirms the
  cross-reference offsets are real byte positions. The test asserts the xref
  offsets against the object headers for the same reason — a PDF whose xref is
  off by a byte is accepted by one reader and refused by another, which a
  "does it contain the text?" test never notices.

The invoice carries `[ placeholder — registration details pending legal
review ]` where a company registration line belongs, which is §1d's rule and
the same convention `LegalPlaceholderScreen` uses. It says "Paid by bank
transfer and confirmed by RaajjePro" and the word *verified* appears nowhere:
the admin confirming **is** the verification (§0.0 item 11).

## 11. Three jobs for five kinds of scheduled work

§Phase 8a's list is the 7-day warning, expiry → grace, grace → downgrade, the
win-back pair and — as of 2026-09-10 — the introductory conversion. They
register as three jobs on §Phase 0's runner:

- **`subscription-lifecycle`** — the first four, plus the forced resume at the
  pause cap and the over-cap reconcile, in one ordered pass per row. These are
  *sequential states of the same row* — a row that expires this hour cannot
  also be downgraded this hour — so separate sweeps would read the same rows
  five times to do at most one thing each.
- **`subscription-trial-prompt`** — the 7-day nudge. Its candidates are
  providers with **no subscription row at all**, which the lifecycle sweep
  cannot see, so folding them together would mean one job scanning two tables
  for two unrelated reasons.
- **`subscription-introductory-conversion`** — a different clock (the anchor,
  twelve months back) and a different action (a price, not a status).

**Hourly, all three.** Every deadline §1b defines is measured in days, so the
finest granularity any of them needs is a day; an hour gives each a
comfortable margin and makes "hides it the moment that booking completes" an
hour rather than a day.

**Every notification is stamped once.** `trialEndingNoticeAt`,
`periodEndingNoticeAt`, `winbackDay7At`, `winbackDay30At`,
`introductoryNoticeAt`, `trialPromptedAt` — inferring "have I already warned
them?" from the dates makes the answer depend on how punctually the job ran,
and a provider warned twice about the same expiry stops reading the warnings.

**Twelve months is 365 days**, not a calendar year: §1b is emphatic that
nothing in this model implies month boundaries, and a calendar +12 months has
to answer for 29 February. The conversion takes effect at the later of the
twelve months and the notice plus thirty days, so a job that was down for a
week cannot shorten the notice — asserted with a deliberately late notice.

## 12. Two seams open, both behind one interface

`SubscriptionBookingSource` answers the two questions this phase must ask
about bookings and cannot, because there is no `Booking` until §Phase 17.1:

- `hasAnyBooking(providerProfileId)` — the 7-day prompt's "if no booking has
  landed". Deliberately "any", not "any confirmed": the trigger exists because
  reaching `confirmed` takes days to weeks, so the question is whether there
  is any booking activity at all. Either reading converges, because
  `startTrial` is a no-op once a trial has run.
- `listingIdsWithCommittedBooking(listingIds)` — §1b's protected listings. The
  status list belongs to the implementation, not the interface: this phase has
  no booking-status enum to name and §Phase 17.1 owns it.

**One interface rather than two**, because §Phase 17.1 implements one class
over one table. The default answers "no bookings", which is the *true* answer
today rather than a stub — every rule built on it is correct as it stands.

`BillingNotifier` is the other seam: §Phase 19 owns notification content, and
five of these events are already in its type list by name. The default logs
that the event fired and that nothing delivered it — deliberately not silent,
because "the rule fired and Phase 19 is missing" and "the rule never fired"
are different bugs. **Two events have no §Phase 19 type yet** and are flagged
rather than renamed onto a neighbour: `trial_prompt` (the invitation, which
§Phase 19's list does not have — it has `trial_ending_7d`) and
`introductory_price_converting` (the list predates Round 9's introductory
pricing). A provider whose price is about to double should not hear about it
through the trial-ending template.

## 13. The booking hook takes one argument, and that is the assertion

§0.5 recorded the original defect: "hook was on one endpoint; an admin
resolving `payment_unresolved` also reaches `confirmed` and would not have
fired it". §Phase 8a therefore requires the trigger to be "hooked on the state
transition, not on one endpoint".

`onBookingConfirmed(providerProfileId)` takes a provider id and nothing about
*how* the transition happened. There is deliberately no parameter a caller
could use to distinguish the admin path, because a hook that can tell them
apart is a hook that can be wired to one and not the other. The test asserts
the arity, and asserts that two different callers reaching it produce one
trial.

## 14. Two defects the tests caught

- **The reversal kept the premium tier.** The first implementation derived
  `status` from the rolled-back dates but left `tier` at its stored value, so
  reversing a provider's only payment left them `expired`/`premium` — premium
  for another seven days on a payment that never arrived. §9 is the corrected
  rule.
- **The introductory cohort cannot be asserted against a shared database.**
  This suite's rows are never deleted (`test/setup.ts`), so the hundredth
  priced provider is somewhere in its history and every later run is past the
  cohort for good — the first version of the test asserted MVR 75 and got MVR
  150. The rule is now a pure function of `(settledPrice,
  pricedProviderCount)`, asserted at 99 and at 100, and the HTTP test asserts
  what the boundary is *for*: a provider is charged what they were quoted, the
  price is written at the first confirmed payment, and a renewal reads the
  field rather than the cohort.

A third thing the tests forced was a test-fixture decision worth recording:
this file's app is built with session, token and MFA windows wide enough to
survive the clock jumps, because §Phase 2's 15-minute admin idle timeout and
§Phase 3's 15-minute access token are measured against the same injected
clock. Both expiries are their own phases' rules and are tested there.

## What is deliberately not built

- **No `Booking` table**, and no booking-status enum. §Phase 8a's brief says
  so in as many words.
- **No appeal action.** Ledger row **P8A-1**.
- **No notification content or `Notification` entity.** §Phase 19's, and five
  of these event types are already named there.
- **No receipt analysis, no bank-statement CSV import, no
  unmatched-transaction queue.** §Phase 10a part 2, and Round 29 is explicit
  that the analysis is advisory and never gates the confirm button — which is
  why nothing here reads a proof image.
- **No provider-facing "keep this one instead" endpoint.** §1b says "the
  provider can override the choice from the dashboard" and the dashboard is
  §Phase 10's. It is reachable today through §Phase 8's existing
  `PATCH …/visibility` (hide the kept listing, activate the other), and a
  dedicated action would be inventing a surface for a screen that does not
  exist. §Phase 10 should decide whether the two-step sequence is good enough.
- **No credit wallet and no advertising.** Cut post-v1; `purpose` stays open
  so they slot back in additively, which is why the enum already carries
  `emergency_dispatch_fee`.
- **No emergency dispatch-fee flow.** §Phase 17.3's. The enum value and the
  generic payer are here so that phase adds a flow, not a table.
- **No Flutter.** §Phase 8a is backend only; §Phase 10a builds the billing UI
  against these endpoints, and Round 19 requires no billing logic in a widget.

## What Phase 9a, 10, 10a, 17.1 and 19 inherit

- **`SubscriptionBookingSource`** — §Phase 17.1 implements both methods over
  the real table and closes **P8A-2**. It should also call
  `subscriptions.onBookingConfirmed` inside the state transition, and
  `subscriptions.reconcileVisibility` on a terminal one.
- **`BillingNotifier`** — §Phase 19 registers delivery and closes **P8A-3**.
- **`getProviderEntitlements`** — the single source of tier truth. §Phase 19's
  analytics and §Phase 15/16's ranking read `analytics` and
  `priorityPlacement` from it rather than looking at a subscription row.
- **`applyEntitlementVisibility`** — the only thing that may write
  `hidden_over_cap`.
- **The endpoints §Phase 10a's three screens call**, all of them
  server-decided: `GET /v1/providers/me/subscription` carries the trial
  countdown, the next billing date, the free-tier state, the pause counters
  and the latest submission with its rejection reason;
  `POST …/subscription/upgrade-request` returns the bank details and the
  reference code; `GET /v1/providers/me/invoices` returns the list with a
  short-lived PDF URL each.
- **The toggle's copy** — ledger row **P8A-4**, and it belongs to a design
  round plus §Phase 5's profile surface, §Phase 10's dashboard and §Phase 10a's
  billing screen.

## Deferred verification

Rows **P8A-2** (the booking seam: the confirmed-booking trigger and the
downgrade protection), **P8A-3** (billing notifications actually reaching a
provider) and **P8A-4** (the pause consequence in the toggle's copy) are added
to `docs/deferred-verification.md`. **P8A-1** is the plan's own row for the
unbuilt appeal action.

Nothing in this phase is recorded as met against a vendor: the PDF is checked
by an independent reader, the payment mechanism is manual by design and has no
gateway to integrate, and the proof upload rides §Phase 8's media transport,
whose object-store row **L13** is already open.
