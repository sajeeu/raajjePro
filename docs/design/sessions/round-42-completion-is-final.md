# Round 42 — completion is final

One rule, on two screens.

**Completing a booking closes it.** Nothing about the agreement can change afterwards,
and nothing half-finished may be left behind at the moment it completes.

**Leave alone:** every layout, colour, component and animation, and all of Round 41.
This round adds two blocked states and changes no copy outside them.

---

## Why this needs saying

At `accepted` the price, date, time and scope lock, and changing any of them takes an
amendment the other party accepts. `completed` is a terminal state. But nothing
currently enforces the join between those two facts:

- `Mark Complete` performs no checks at all. A provider can complete a job while an
  amendment is still sitting unanswered, or while the customer's "I've paid" is still
  waiting on their reply. Both then have nowhere to go — the booking is terminal and
  the question stays open forever.
- `Propose Amendment` has no terminal check. Reached on a completed booking it would
  compose one as if the job were still live.

`Mark Complete` already knows how to refuse: an emergency job cannot complete without
a final amount. This is the same shape, applied to two more conditions.

---

## 1. `Mark Complete` refuses while something is outstanding

**Screen: `Mark Complete`.**

Add a blocked state, shown instead of the complete action, when either of these is true:

1. **An amendment is open** — proposed by either side and not yet accepted or rejected.
2. **A payment claim is unanswered** — the customer has marked "I've paid" and this
   provider has not yet said whether it arrived. (Booking state `payment_sent`.)

Each blocker renders as its own row, with a route to resolve it:

| Blocker | Row copy | Action |
|---|---|---|
| Open amendment | **An amendment is waiting** — you both agreed a price, and a change to it hasn't been settled. Decide it before you close the job. | `Decide it now` → `Propose Amendment.dc.html` |
| Unanswered payment claim | **Aishath says she's paid** — you haven't answered yet. Say whether it arrived before you close the job. | `Answer now` → `Payment Received.dc.html` |

Above the rows:

> **Settle these first**
>
> Completing closes the booking for good — the price, date, time and scope stop being
> changeable. Anything still open would be stuck there.

Show every blocker that applies, not just the first. When none apply, the screen behaves
exactly as it does today.

### What must **not** block

- **`awaiting_payment`** — the customer simply hasn't paid yet. Paying after the work is
  normal here, and the provider must be able to close out a job they have finished.
- **`payment_unresolved`** — already escalated to RaajjePro at day 7 and only an admin
  can clear it. Blocking on it would leave a provider who did the work unable to close
  it on someone else's queue. The job completes and the payment dispute carries on
  separately. This is deliberate: an admin backstop must never become a customer- or
  provider-facing dead end.
- **The MVR 200 emergency dispatch fee** — owed to RaajjePro, not part of this
  agreement. It blocks new bookings, never the closing of this one.

### Add a Scenario option

Add `Blocked — amendment open` and `Blocked — payment unanswered` to the existing
Scenario enum, so both are inspectable.

---

## 2. `Propose Amendment` refuses on a completed booking

**Screen: `Propose Amendment`.**

Add a `closed` scenario to the enum. When the booking is completed, replace the compose
form with:

> **This booking is closed**
>
> It completed on Wed 2 Sep, so the price, date, time and scope are final. Amendments
> only exist while a job is live.
>
> If the work wasn't right, report a problem — that reopens the booking for review.
> If you want more work done, Book Again.

Two routes out, side by side: `Report a problem` → `Raise Dispute.dc.html`, and
`Book Again` → `Book Again.dc.html`.

Keep every other scenario exactly as it is.

---

## 3. What stays available after completion — do not remove these

`Booking Detail` is already correct on this and needs no change: on a completed booking
its only text action is **Report a problem**, and its footer offers chat and rating. It
offers no amendment route. Leave it alone.

These three remain live after completion, and none of them is a change to the agreement:

- **Rating** — becomes postable once completed. One per booking.
- **Reporting a problem** — reopens the booking for review and reopens the chat for the
  duration. This is the customer's only recourse for bad work; it must never be removed.
- **The callback claim** — for 7 days after completion, on the six categories that carry
  the guarantee. It creates its own linked booking rather than editing this one.

The chat also stays open for those 7 days and then locks read-only, as it does now.

---

## Checklist

- [ ] `Mark Complete` blocks on an open amendment and on an unanswered payment claim
- [ ] It shows every applicable blocker, each with a working route
- [ ] It does **not** block on `awaiting_payment`, `payment_unresolved`, or a dispatch fee
- [ ] Both blocked scenarios are selectable in the Scenario enum
- [ ] `Propose Amendment` has a `closed` scenario offering Report a problem and Book Again
- [ ] `Booking Detail` is unchanged
- [ ] Rating, reporting and the callback claim still work on a completed booking
- [ ] Emergency completion still requires a final amount
