# Phase 17.1 — Core booking machine, payment attestation & the locked agreement

What was decided while building §Phase 17.1, and why. The plan is the source of
truth; this records the choices it left open, the boundaries drawn against the
three slices that follow, and the two defects the build's own tests found.

## 1. The slice boundary: what 17.1 builds and what it refuses by name

§Phase 17's slice list gives 17.1 "slot-based core: create, accept, decline,
claim-payment, withdraw-payment-claim, confirm-receipt, complete, cancel, the
24-hour and 7-day jobs", plus Round 15's **locked agreement** and **provider
replacement**. So:

| | 17.1 | Where it lives instead |
|---|---|---|
| Slot-mode creation, accept, decline | ✅ | |
| Request-mode creation and quotes | ❌ | §Phase 17.2 — "request-based and quotes" is that whole slice |
| Emergency creation, offers, dispatch fee, reveal-contact | ❌ | §Phase 17.3 |
| Recurring, reschedule, Book Again, saved preferences, callback | ❌ | §Phase 17.4 |
| Payment attestation, both sides, and the withdrawal | ✅ | |
| Disputes, `resolve-dispute`, `payment_unresolved` | ✅ | |
| §1h's amendments, and the replacement prefill | ✅ | |

**A refusal is by name, not by silence.** `POST /v1/listings/:id/bookings` on a
request-mode listing answers `BOOKING_MODE_NOT_AVAILABLE`, and `accept` on an
emergency booking answers `EMERGENCY_USES_ITS_OWN_ACCEPT` — §0.0 item 15's own
correction, stated at the endpoint rather than left to a later reader.

**The schema is built whole even where the edges are not.** `BookingStatus`
carries `awaiting_quote`, `quote_offered` and `emergency_offered`, and
`AmountKind` carries `quoted` and `callout_fee`, though no 17.1 transition
reaches any of them. One migration instead of three, and the machine reads as a
machine rather than as the part built first. `transitions.ts` is where an edge
lives; a later slice adds rows to that table and never a second table.

## 2. The machine is a table of edges, not nine handlers

§1c draws the status machine as a diagram and then states six things about it in
prose: three statuses that read terminal and are not, one edge that runs
backwards (Round 24's withdrawal), and three modes that each skip a different
part. Spread across nine endpoint handlers those rules become nine half-copies,
and the ninth is the one that lets a `completed` booking be cancelled.

So every edge is one row in `EDGES`, and an endpoint's whole transition check is
`assertTransition(name, from, actor)`. It is checked **twice** — once there, and
again by the database: every write goes through `repo.transition`, whose `WHERE`
carries the status the booking was read at. Two taps from two devices resolve to
one winner with no row lock, and the loser gets the same refusal a stale screen
gets.

The actor is part of the edge rather than a separate check, because §1f depends
on the distinction: a 24-hour auto-decline and a provider saying no are the same
*status* and different *facts*, and "timeouts feed response rate, not acceptance
rate" is only computable if the machine wrote down which it was.

## 3. Which clocks are constants here, and which are never

The brief says never to hardcode 30 minutes, 24 hours or 72 hours. Those three
are **per-category** and are read from the `Category` row —
`emergencyAcceptWindowMinutes` (§Phase 17.3), `quoteExpiryMinutes` and
`quoteApprovalMinutes` (§Phase 17.2). None of them appears anywhere in this
slice, and the accept-timeout job's candidate query excludes emergency bookings
outright rather than trusting a later filter.

What `windows.ts` holds is the set §1c states **flat for every category**: the
24-hour slot/request accept window, the 7-day payment-silence window, and the
completion prompt's 7 days plus its 3-day grace. No `Category` column holds any
of them and no section varies them, so they are constants with their citation
beside them — inventing three columns so they *could* vary would be
configuration nobody asked for.

## 4. A sub-day slot at a daily rate charges a whole day — a judgment call

Round 17's table says `daily_total` comes from "`daily` × duration", and the
plan never says what a **sub-day slot** at a day rate costs. Three readings were
available:

1. a fraction of the day rate — surprises the provider, who advertised a day;
2. whole days rounded up, minimum one — surprises nobody: the card said `/day`;
3. refuse the combination at booking time.

**(2) is what is built.** (3) was rejected for the reason ledger row **P8-1**
already records about a related narrowing: an invented restriction here would
silently block a legitimate provider at the moment a customer tries to pay them.
The reasoning sits beside the arithmetic in `pricing.ts`, and
`bookings-pricing.test.ts` asserts both the 2-hour and the 26-hour case.

## 5. An amendment that moves the time moves the reservation with it

§1h locks "the agreed price, date, time and scope" and requires an accepted
amendment to change any of them. A time change with no matching hold would leave
the provider blocked at the old time and free at the new one, so accepting one
calls §Phase 9a's `reservations.reschedule` **inside the same transaction** that
writes the new terms. The old published slot returns to `open`, the booking's
`timeSlotId` is cleared — it no longer sits on a published slot, it sits on a
time the two parties agreed — and the exclusion constraint has the last word: a
time the provider has since sold elsewhere fails as `PROVIDER_TIME_UNAVAILABLE`
rather than silently double-booking them.

This is **not** §Phase 17 item 16's reschedule, which is a different mechanism
(moving to another *open slot*) and is §Phase 17.4's.

**One open proposal at a time.** Two live counter-offers on one agreement have
no defined resolution and the plan describes none.

## 6. §1h's replacement is a prefill, never a broadcast

"A confirmed provider cancelling is the moment a customer decides the platform
is unreliable" — so the detail read attaches a `replacement` object carrying the
service, the time and the notes, and the screen offers to send it again. It is
attached only to the **customer**, and only where the **provider** cancelled.

§1h is explicit that "normal bookings do not broadcast", so nothing here
dispatches, and the copy says so: *this goes to them alone; it isn't sent out to
other providers*. A customer who expected otherwise would wait for offers that
never come. Saved preferences (§Phase 17.4) are absent rather than stubbed.

## 7. `Report` is the minimal insert §4 Sequencing asked for

§4: "build 17 first with a minimal Report insert, 22 makes the queue real." The
columns are §Phase 22's own list — reporter, targetType, targetId, reason,
status, reviewedBy, reviewedAt, resolution reason — so that phase extends this
table rather than replacing it. Round 17's **scoping of reason by target type**
is `reports.ts`'s map, because a database enum cannot express it; §Phase 17.1
files against `booking` alone.

Two rules the plan states and this honours:

- **The 7-day escalation files with a null reporter.** The system filed it;
  recording a human would be a lie about who complained.
- **A withdrawal files nothing** (§1f, Round 24: "a customer's mis-tap is
  neither"), which is asserted as an absence rather than assumed.

## 8. Notifications: one goes out, the rest are a seam

§Phase 3c built `NotificationKind.booking_accept_prompt` for exactly the prompt
this slice raises, and its `NotificationContext` is literally booking-shaped —
booking type, customer first name, island. So the accept prompt dispatches
through §Phase 3c directly.

Everything else has no §Phase 19 type, and writing copy here would put
notification content in two phases. `BookingNotifier` is the seam, in the shape
§Phase 8a's `BillingNotifier` established, and the default **logs and drops** —
honest, rather than pretending somebody was told. Ledger row **P17-1** carries
it.

## 9. Two defects the tests found, both worth recording

**The list read parsed the wrong key.** `ApiClient` unwraps the envelope and
represents a list payload as `_list` with the envelope's `meta` as `_meta`;
`BookingApi.list` read `data` and `meta`. Against a perfectly good response it
produced an empty list, so My Bookings would have been permanently empty with no
error anywhere. `ListingApi.listOwn` carries a comment saying exactly this, which
is the second time that comment has earned its place.

**A class name tripped a guard that was right.** `_RoleSwitch` in a file that
also calls `pushNamed` matches `no_booking_notification_toggle_test`'s grep for
`Switch(` near `push`. The guard exists because §Phase 3c forbids a toggle on
transactional booking notifications, and it should not be weakened for a name;
the two chips are not a switch and are now `_RoleChips`.

## 10. The two seams earlier phases built against are filled, and neither changed

§Phase 3's `DeletionBlocker` and §Phase 8a's `SubscriptionBookingSource` are now
implemented over the real `booking` table. **No caller in `modules/account/` or
`modules/subscriptions/` changed**, which is the fifth time this codebase has
built a rule one phase before its data source and had the interface survive
intact.

They are implemented on the **repository** rather than on `BookingService`,
because `SubscriptionService` needs a booking source and `BookingService` needs
`subscriptions.onBookingConfirmed` for §Phase 8a's trial trigger — through the
service that would be a cycle. Both questions are pure reads with no rules in
them, so the dependency runs one way and nothing is lazily assigned.

`NON_TERMINAL_STATUSES` deliberately **includes** `payment_unresolved` and
`disputed`: both read like endings and §1c says an admin still owes somebody an
answer on each. A deletion that completed while a dispute was open would
anonymise one side of the evidence.
