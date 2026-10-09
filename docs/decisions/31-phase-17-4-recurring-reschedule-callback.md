# Phase 17.4 — Recurring series, reschedule, the callback guarantee & saved preferences

Built 2026-10-09 against `01_Development_Plan_v5.md` revision 5.37: §Phase 17's
**17.4 — Done when** (four clauses), the standing no-phone-number rule over the
endpoints this slice adds, §1c "Recurring bookings", §1h (the locked agreement,
the callback guarantee, saved preferences and one-tap rebooking), and the
owner's 2026-09-10 reattribution of Saved Preferences to this slice.

This file records the four questions the plan left open and the owner answered
before the build, the judgment calls the build made, and what is deliberately
not built yet.

---

## 1. The owner's four decisions (2026-10-09)

**Reschedule splits at `accepted`.** §Phase 17 item 16 says "another open slot
(slot-based) or a new proposed time (request-based); frees the old reservation
atomically". §1h says that from `accepted` "neither party can alter them
unilaterally". Both stand:

- **Before the provider answers** — `requested` (slot) or `awaiting_quote`
  (request) — the customer moves the booking directly. A slot booking moves to
  another open slot of the same listing inside one transaction (§Phase 9a's
  `reservations.reschedule`); a request takes a new preferred window. The
  status does not change, and the provider's clock restarts from the move
  (`Booking.rescheduledAt`; `createdAt` is left alone because it is when the
  booking was made).
- **From `accepted` on**, the same endpoint files a **time amendment** through
  §Phase 17.1's machinery, which the other party must accept. On a slot booking
  the amendment carries the picked slot (`BookingAmendment.proposedTimeSlotId`),
  so acceptance lands the booking back on the provider's published grid rather
  than on a bare window. Nothing is held while the proposal waits; a slot taken
  in the meantime refuses at acceptance as `SLOT_NO_LONGER_AVAILABLE` and the
  old hold stays. The amount is not changed by a reschedule — a price change is
  its own amendment.

**A callback is a request that skips payment.** §1h: "a new booking linked to
the original, at zero cost, so it flows through the normal machinery". The
claim (`POST /v1/bookings/:id/callback`) creates a `request` booking at
`awaiting_quote`, linked by `callbackForBookingId`. The provider proposes a
return time at **zero** (`CALLBACK_IS_FREE` refuses any price); the customer
approves; a new `system` edge, `no-payment-due`, takes it from `accepted`
straight to `confirmed`, because walking a MVR 0 booking through "I've Paid" and
"Payment Received" would ask two people to attest to a transfer that cannot
happen. `AmountKind` gains `callback`, labelled "Callback — free return visit".
§Phase 17 item 20's trial hook still fires on that transition into `confirmed`.

**Three kinds of miss count toward the pause.** §1c names only the 24-hour
auto-decline. A provider's explicit decline and a week with no open slot are
misses too — to the customer each is "the provider didn't confirm this week",
and the artboard's paused copy reads that way. A week the customer skips is
neutral: it neither adds to the run nor resets it. An accepted week resets it.

**Backend and drawn screens first; undrawn pieces proposed.** See §6.

## 2. Recurring series — the shape

- `RecurringSeries` (customer, provider, listing, origin booking, status
  `active`/`paused`/`ended`, `nextOccurrenceAt`, `nextAskAt`,
  `consecutiveMisses`, the address and notes copied from the origin) and
  `RecurringOccurrence` (one row per week, unique on `(series, occursAt)`).
- **Each week is an ordinary slot booking** made through
  `BookingService.createSlotBooking`, with every rule of creation — visibility,
  the paused toggle, the dispatch-fee block, the 24-hour accept window, the
  accept prompt. The occurrence row is written **inside** that booking's
  transaction (`SlotBookingOptions.inTransaction`), so neither can exist
  without the other, and the unique key makes a second tick's ask a no-op.
- **The cadence is one week ahead**, taken from `Recurring Booking.dc.html`
  ("The ask goes out on Tue 8 Sep" for Tue 15 Sep). The first week is asked the
  moment the series is made. A week is exactly 168 hours: the Maldives keeps no
  daylight saving.
- **Outcomes are reconciled by the job, not hooked into the machine.** The
  `recurring-series` job (every five minutes) first records how each asked
  week's booking turned out — anything at or past `accepted` is accepted; a
  `declined` whose last edge is `accept-timeout` is `timed_out`, otherwise
  `declined`; a customer cancel is `skipped` — and then sends every ask that
  is due. In that order, so a third miss pauses a series before its next ask.
  The booking machine stays the only thing that moves a booking.
- **A fourth miss reason, `could_not_ask`**, covers creation's own refusals: the
  listing gone or paused, the customer blocked by an unsettled dispatch fee. It
  counts like the other three; the owner's rule is about what the customer
  experiences, and a week that could not even be asked is not confirmed.
  🔧 **Split the same day (owner, 2026-10-09)** into `provider_unavailable` and
  `customer_blocked` (`DispatchFeeOutstandingError`). One value carried two
  unrelated facts, and the paused banner read "Mariyam didn't confirm three
  weeks in a row" to a customer whose own unpaid MVR 200 had blocked all three
  — against §1c's honest framing and §1f. The count and the pause are
  unchanged; only attribution is. The series read gains `pauseCause`
  (`provider` / `customer` / `mixed`, from the last three misses): the banner
  names the provider only on `provider` (declined, timed out, no open slot,
  provider-side), says what lifts the hold on `customer` (proof submission),
  and names neither party otherwise. `could_not_ask` stays in the enum, is no
  longer written, and reads as `mixed` — rows written before the split cannot
  be told apart, so no backfill. 🔧 `no_open_slot` is counted as the
  provider's: the per-week row already names them for it.
- **One active or paused series per customer per listing**
  (`RECURRING_SERIES_EXISTS`, carrying the existing id so the app opens it).
- Offered from `confirmed` **or** `completed` slot bookings: Booking Detail
  draws "Make this recurring" on a confirmed booking, and the offer screen
  itself leads with a completed one.
- Ending withdraws any week still waiting on the provider (cancelled as the
  customer's own, which §1f never counts against the provider) and leaves
  accepted and past weeks alone.
- Series notifications (`recurring_week_missed` to both parties,
  `recurring_week_skipped`, `recurring_series_paused`, `recurring_series_ended`)
  carry the **series** id as their subject, as §Phase 17.3's pre-selection
  events carry the request's — a week with no open slot has no booking to name.

## 3. The callback guarantee — the rules around the shape

- **Snapshotted at creation** (`Booking.callbackGuaranteed`) from the listing's
  `callbackGuaranteeOffered`, on all three creation paths including emergency
  selection. A provider switching the opt-in off after the job cannot withdraw
  the promise the customer booked under. §Phase 8 already refuses the opt-in on
  a category whose `callbackEligible` is false (Round 28), so the flag is never
  read here — the listing cannot carry it on an ineligible category.
- **Seven days from `completedAt`** (`CALLBACK_WINDOW_DAYS`, flat — §1h states
  it flat; eligibility is the per-category part).
- **One claim per job**: `callbackForBookingId` is unique, and a callback
  booking is itself never guaranteed, so the chain stops at one return visit.
- **It bypasses `bookableListing`.** The guarantee was made on the job that was
  done; a provider who has since hidden the listing or paused new customers
  still owes it. Two exceptions: a **suspended** provider is refused
  (`CALLBACK_PROVIDER_UNAVAILABLE` — the platform routes nothing to them), and
  an **unsettled dispatch fee** still blocks, because §1c's rule is "all new
  bookings" and a callback is one.
- **Declining counts.** A provider's decline, letting the quote clock run out,
  or cancelling after acceptance each files a system `Report` with the new
  reason `callback_declined` (reporter null, as the day-7 escalation's is). It
  is system-filed and not among the four a person may cite in a dispute — the
  same treatment §Phase 17.3 gave `provider_verification_revoked`. §Phase 11
  reads it for conduct; ledger **P17-11**.
- `offerQuote`'s body schema widened from `min(1)` to `min(0)` so a callback can
  be quoted at zero. The service still refuses zero on every other booking
  (`QUOTE_AMOUNT_REQUIRED`), so no client sees a rule loosen.

## 4. Book Again and calendar export

- **Book Again** (`GET /v1/bookings/:id/book-again`) is a read for the
  customer of a **completed** booking. It routes by the listing's mode **now**
  and says whether that changed; it carries the address and notes from the job
  and, from Saved Preferences, the standing instructions and the first
  preferred window. The booking is then made through the ordinary creation
  route. A listing that is unpublished, hidden, deleted or whose provider is
  suspended returns `available: false` — the artboard's "no longer offered".
  A provider who merely paused new customers is still `available`; creation
  says so when the customer tries.
- **Calendar export** (`GET /v1/bookings/:id/calendar`) answers from
  `accepted` through `confirmed` — §1h locks the time at `accepted`, so from
  then on the entry names an agreed time. **A download, not a subscribe link**:
  the plan offers either, and a subscribe feed is a long-lived unauthenticated
  URL onto somebody's job list. The ICS text comes back **inside the standard
  envelope** (`{ filename, contentType, ics }`), because every response does
  (backend/CLAUDE.md) and the data export set that precedent. Times are UTC; the
  event's `SEQUENCE` counts accepted time amendments so a re-download replaces
  the entry. No phone number, ever. Validity is asserted against RFC 5545's
  structure; ledger **P17-10** carries the real-calendar-app check.

## 5. Saved preferences

- Three tables: `SavedAddress` (label, island **by id**, line), `SavedTimeWindow`
  (ISO weekdays, start and end minute of the Maldives day) and
  `SavedPreferences` (standing instructions, one row per user). All soft-delete.
- **"Weekdays" is Sunday to Thursday** — the Maldivian working week — and
  "Weekend" is Friday and Saturday. Labels are rendered by the server
  (`Weekdays · 9:00–12:00`) so every surface agrees.
- **A cap of 20 addresses and 20 windows** (`SAVED_PREFERENCE_LIMIT_REACHED`).
  🔧 Not in the plan. backend/CLAUDE.md requires an unbounded set to be paged; a
  list of saved addresses that needs paging has stopped being a shortcut, and
  the cap lets the read stay one document. Recorded here so it is a decision,
  not an accident.
- Contributes to §Phase 3's data export and is blanked by §Phase 3's
  anonymisation (text cleared, rows stamped deleted, nothing removed).
- **The island is never defaulted.** The artboard's add sheet opens on "Malé";
  §0.0 item 12 and §Phase 7's picker forbid that, so the app opens on no island
  and Save waits for one. The plan wins; the artboard is the one to correct.

## 6. Built against the artboards, and what is waiting for a design

Built: `Recurring Booking` (offer, asked, series, skipped week, paused, ended,
loading, error), `Book Again` (slot, request, no longer offered, loading,
error), `Saved Preferences` (populated, empty, loading, error, add/edit sheet),
and Booking Detail's "Make this recurring". Profile's row now reaches the real
screen. Book Slot and Request a Time accept a prefill.

**Not built, because no artboard draws them** (CLAUDE.md: propose, then build on
approval):

1. Reschedule — the entry on Booking Detail and the picker hand-off.
2. The callback claim — the badge on a guaranteed booking and the claim form.
3. Calendar export — the "Add to calendar" control and the save/share step.
4. Book Again's entry on a completed booking's detail view.
5. Saved Preferences' "add a time window" editor — the artboard's Add appends a
   sample and draws no editor. Saved windows render and can be removed.

The backend for all five is built and tested. Until the screens exist, Book
Again is reachable from no Flutter surface; that is the gap the proposals close.

## 7. Flagged, not changed

- **A slot-mode category switched to request mode cannot take a request.**
  Cleaning, Beauty and Fitness carry no quote window, so a listing in one of
  them that a provider switches to `request` (§1c: "editable per listing") is
  refused at creation with `CATEGORY_HAS_NO_QUOTE_WINDOW` — and Book Again
  would route a customer straight into that refusal. This is §Phase 17.2's
  behaviour and predates this slice; found while testing Book Again's routing.
  Either the switch should be refused at §Phase 8's listing edit for those
  categories, or the three need quote windows seeded. The plan says neither.
- **Root `CLAUDE.md`'s phase list is stale**: it still says "Phase 9a onward is
  still specification", while 9a, 10, 10a part 1 and 17.1–17.4 are built.
  `HANDOVER.md` is current.
