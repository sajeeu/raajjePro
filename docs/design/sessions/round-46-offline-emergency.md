# Round 46 — the emergency accept needs a live connection

One rule, on two screens. It closes the item Rounds 43 and 45 both flagged and
neither instructed.

**Leave alone:** every layout, colour, component, animation and flow, and all of
Rounds 40–45. This round adds one offline state and edits one list item.

---

## Why

Three things queue offline and replay on reconnect: a wizard step, an accept, and
a chat message. That is right for two of them and wrong for the third.

The emergency accept is a different endpoint doing a different thing. Since Round
22 the provider supplies their **callout fee and their own arrival estimate** in
the same action, and on-time rate is measured against that estimate. So a queued
emergency accept is a queued price and a queued promise — replayed from where the
provider was and what they could offer at the moment they tapped, not now. If it
lands inside a still-open window they are committed to an arrival time they would
never give again, and scored against it.

The collection window is 90 seconds, so in most cases it is moot anyway: a
reconnect two minutes later has missed the window with 28 of the 30 minutes still
on the clock.

The plan is amended to match — **§0.0 item 14, §Phase 17 item 12, revision
5.18**. The queue keeps exactly the three surfaces it was built for; emergency is
not one of them.

---

## 1. `App States` — the offline list is one item too broad

**Screen: `App States`, the `no_connection` state.**

The "These keep working offline" list currently reads:

- Saving a step of the service wizard
- **Accepting a booking**
- Sending a message

The middle one is true for slot and request bookings and false for emergency.

**Do:** change that row's label to **Accepting a booking — not emergencies**, and
keep its `pending_offline` pill exactly as it is.

Then add a fourth row **below** the divider, visually distinct from the three
above it — no `pending_offline` pill, a muted treatment rather than the queued
one:

| | |
|---|---|
| Icon | The same lightning bolt used for emergency elsewhere |
| Label | **Emergency offers need a live connection** |
| Sub | Your callout fee and arrival estimate have to be current, and offers are collected in 90 seconds. |

Keep the closing line as it is — *"They send when the connection returns. Nothing
is confirmed — and no payment is recorded — until it sends."* — and make sure it
reads as applying to the three queued rows, not the fourth.

---

## 2. `Provider Emergency` — the accept control, offline

**Screen: `Provider Emergency`.**

Add an `offline` scenario to the existing Scenario enum. In it, the accept action
— the control where the provider enters their callout fee and picks an arrival
estimate — is **replaced**, not disabled and not left tappable:

> **You're offline**
>
> Emergency jobs need a live connection — your fee and arrival estimate have to be
> current, and offers are collected in 90 seconds.
>
> `Retry connection`

`Retry connection` returns the screen to its normal scenario, the way `Analytics`
and `Mark Complete` now do.

Two things this state must **not** do:

- **No pending pill, and no queued state of any kind.** The whole point is that
  the provider does not walk away believing they have bid.
- **Do not hide the job.** The request, its category, its window and the customer's
  description all stay readable. A provider who reconnects in forty seconds should
  already know whether they want it.

Keep the countdown running and visible. It is the honest thing on the screen: the
clock does not stop because the connection dropped.

---

## 3. What must not change

- The queue itself, on the wizard, the slot/request accept and chat. Round 43 and
  the plan both keep those, and this round narrows nothing else.
- `Booking Request`'s offline handling — that screen is the slot/request accept,
  which **does** queue. Its `Offline — accept pending` scenario and its
  "Sends on reconnect — nothing more to do" footer are correct and stay.
- The 30-minute window, the 90-second collection window, the three-offer cap, the
  fee and the arrival estimate.

---

## Checklist

- [ ] `App States` says "Accepting a booking — not emergencies"
- [ ] A fourth row states that emergency offers need a live connection, with no pending pill
- [ ] `Provider Emergency` has an `offline` scenario in its Scenario enum
- [ ] In it the accept control is replaced by an offline notice with a working retry
- [ ] Nothing on that screen shows a pending or queued state
- [ ] The job details and the countdown stay visible while offline
- [ ] `Booking Request`'s offline-accept-pending state is unchanged
- [ ] Nothing from Rounds 40–45 changed
