# Session 5 corrections — the booking record

The two things I said I'd audit hardest both came out right.

**The payment mechanisms stayed distinct**, and you did it better than I asked: the dark `#0F1B2D` card gives platform payments their own visual identity, and the screen says the difference outright — *"Payments to providers are never checked by anyone — this one is."* That sentence does more work than any amount of layout.

**Reveal contact resisted being made convenient.** All seven conditions are stated before the tap, "Share numbers both ways" puts mutuality in the verb, and showing the customer their own exposed number is a good idea nobody asked for. The kill-switch state reads as a considered absence rather than a failure, which is exactly right.

Five changes. Two are material, and both are on Booking Detail.

---

## Booking Detail

### 1. The not-arrived flow promises a step that doesn't exist — material

Current: *"tell RaajjePro — it checks with him straight away"*, then *"Reported — RaajjePro is checking with Ibrahim now"* and *"You'll hear back here within minutes."*

RaajjePro does not check with him. §1c is explicit: marking not-arrived **releases the provider, records a no-show against conduct, and re-broadcasts the request excluding them** — and it says why, in the same sentence: *"No admin in the loop; an emergency cannot wait for a queue."*

The design has invented an adjudication step in the one flow the plan deliberately built without one. It also under-sells what really happens, which is better news: the customer is not waiting for RaajjePro to make a phone call, they are already being matched with someone else.

Replace the reported state with what the system does:

> **Ibrahim has been released — we're finding someone else**
> Your request has gone back out to other qualified plumbers. There's no second dispatch fee. Ibrahim's record carries the no-show.

And in the idle card, replace *"it checks with him straight away and it counts on his record"* with:

> If he isn't with you yet, release him — your request goes straight back out to other plumbers, at no extra cost, and the no-show goes on his record.

### 2. "The 45-minute response window" conflates arrival with response — material

The card reads *"Expected by 21:26 — the 45-minute window has passed"*, and the timeline carries *"Accepted — 45 min response window"*.

**The number is right and the label is wrong.** 45 minutes is one of Plumbing's arrival presets, so as an ETA it is correct. But the *response window* is a different thing — it is 30 minutes for all four emergency categories, and it governs how long a provider has to **answer**, not how long they take to **arrive**.

Round 22 exists because these two were conflated once already, and the cost was an emergency customer waiting two hours to learn nobody was coming. Do not let the label drift back.

- Card: **"Ibrahim estimated 45 minutes — that was 21:26"**
- Timeline: **"Accepted · 45 min arrival estimate"**

Ibrahim's estimate is his own, self-declared number. Never render it as a platform guarantee.

### 3. "An admin may read this chat during the dispute"

This may well be true, and disclosing it would be the honest thing to do — but it isn't in the specification, and a prototype shouldn't be the first place a data-access practice gets asserted to customers.

Drop the sentence for now. The rest of that paragraph — reviewing the timeline and both sides' messages as the record — is accurate and can stay. I'll raise the underlying question separately.

---

## Reveal Contact

### 4. The framing is written for one emergency, at night

*"Tonight can be different"* and *"the water rising"* are good writing, and they're wrong for three of the four categories this screen serves. An AC Repair emergency at 2pm, or an emergency house move, gets flooding-at-night narrative.

Keep the warmth, drop the specifics:

> **Everything normally stays in chat. This is the exception.**
> Ibrahim is on his way. If chat isn't fast enough — finding the door, getting through a locked gate, anything that needs a voice — you can choose to share phone numbers. It only ever works like this:

Everything below that line is right as it stands.

---

## Propose Amendment

### 5. The provider can only amend price

`field = isProvider ? 'price' : s.field` locks the provider to the price field. §1h lets **either party** propose a change to price, date, time or scope — a provider who needs to move a Tuesday job to Wednesday has the same right to propose it.

Let the provider use the same four chips. Keep the price-adherence card gated to `price` specifically, since that is the only field it applies to.

---

## Leave alone

- The whole dispatch-fee treatment: the dark card, the "works differently from paying a provider" callout, the separate RaajjePro account with its "never a provider's" line, the reference code, and the blocked sheet's two green "unaffected" cards.
- **"Submit proof — lifts the hold now"** and *"That happened the moment you submitted — you're not waiting on anyone."* The checkmark on that state is fine: it marks the unblocking, which really did happen, and "Admin check · Pending" sits directly below it.
- Reveal contact's conditions list, the mutual display including the customer's own number, *"confirmed by an admin when Ibrahim was verified… It isn't checked live"*, and both the expired and switched-off states.
- The withdrawal flow: gated to `payment_sent`, a confirm step, the once-per-booking used state, the status flipping back to Awaiting payment, and the withdrawal appearing on the timeline.
- The timeline's attribution format throughout — `you` versus the provider's name is the whole point of it.
- Every amendment string: *"Original — stays on record"*, *"Nothing changes unless Mariyam accepts"*, and the rejected state's *"The original terms stand"*.
- My Bookings entirely. The `EMERGENCY` marker on a booking row is **not** the thing Round 23 removed — that was a discovery card advertising a capability; this is a fact about a booking that is one.

## Note

`mockups/Bookings.jpg` never made it into the project's uploads, so My Bookings was designed without the mockup it was supposed to follow. It came out consistent with everything else, so nothing needs redoing — but attach it before any future change to that screen.
