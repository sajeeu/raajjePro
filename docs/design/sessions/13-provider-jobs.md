Build the provider's job handling: **Booking request**, **Propose a time and price**, **Payment received?**, and **Mark the job complete**. Four artboards.

**Attach:** nothing — no mockup exists for any of these. Propose the design, inheriting the vocabulary already built. The nearest relatives are `Provider Emergency` (the same accept-under-a-clock shape) and `Booking Detail` (the same record).

**Import the components**: `StatusPill` (booking statuses — this is what it is for) · `Chip` · `VerificationBadge` where the customer is shown · `EmptyState` · `SkeletonCard`. Cast: Ibrahim Rasheed is the provider, Mariyam Shifa the customer.

**Emergency accept is already built** — `Provider Emergency.dc.html` covers the callout fee, the competitive-bid framing and the 30-minute window. Do not rebuild it, and do not duplicate its copy. Link to it where a provider would cross over.

---

## Cast this session as Boat Charter — this is the point of it

Every booking prototype in the project is cast as Cleaning or Plumbing. That means three things the plan specifies have never appeared on any screen: the **occasion** subtitle, the **long quote window**, and a **long lead time**. This session fixes that.

The job: **Sunset Fishing Charter**, booked by Mariyam Shifa, occasion **Fishing trip**, MVR 3,200, Wed 2 Sep 06:30 — the same booking `My Calendar` already shows as `#4833`.

**A fix that comes with it.** `My Services.dc.html` lists three services — Home Deep Cleaning, AC Service & Repair, and the Wiring & Fault Repair draft. `My Calendar` shows a commitment against **Sunset Fishing Charter**, which is not one of them: the provider's calendar references a listing their own dashboard doesn't have. Add **Sunset Fishing Charter** to `My Services` as a fourth, published, Boat Charter listing (`MVR 3,200`, `/trip`, request-based, its own photo or the hatched placeholder). That makes the dashboard, the calendar and this session's job describe one provider.

## Booking request — the highest-stakes screen in the provider app

A lost tap is a lost job. Everything else on this screen serves the decision.

- **What the job is:** service, the customer's **first name only**, the requested window, address, island, job notes, photos. For this cast, the **occasion reads as the subtitle** — `Fishing trip — Wed 2 Sep`
- **No contact details of any kind appear here, and there is no chat yet.** Say so — a provider looking for a phone number needs to know why there isn't one rather than assuming the screen is broken
- The amount they would be agreeing to
- **A countdown matching the real window: 24 hours** for a slot or request-based booking, after which it auto-declines and the customer is told to look elsewhere. (30 minutes is emergency only, and that screen exists.)
- **Three actions:** accept · decline · **propose a time and price** — the third appears on request-based bookings only
- **Accepting locks the price, date, time and scope.** Changing any of them afterwards needs the customer to accept an amendment. State it at the point of accepting, not in help text
- **Accepting opens the chat immediately** — that is the sole channel from then on, for arrival details, the exact address, access instructions
- **Offline behaviour belongs on this screen.** A tap with no connection is recorded, shows as pending, and sends on reconnect. The provider is never left unsure whether it registered — this is the screen where that uncertainty costs a job
- **Timed-out state:** the window passed and the booking is gone, stated plainly, with no implication the provider can still act

## Propose a time and price

The provider's answer to a request-based booking.

- The customer's preferred window, restated — they are answering it, not composing from scratch
- A concrete date and time, a price, an optional note, a send action
- **Sending this holds that time.** For as long as the customer has to accept, nobody else can take it — including a booking on any of the provider's other listings
- **Sending opens the chat immediately**, so the provider lands in a conversation rather than back on a list. This is where the customer says *"could we do 3pm instead"*
- **The customer's clock is per-category and starts when the quote is offered, not when the booking was created.** On Boat Charter it is **72 hours**; on Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control and Home Repairs it is **4 hours**. State the real number for the category being quoted — read it from the category, never hardcode one
- A quote that expires releases the held time and closes the booking

## Payment received?

The customer says they have paid. The provider says whether that is true.

- The amount, the customer, the booking
- **Three visually distinct actions:** `Payment received` · `Payment not received` · `Decline booking`
- **`Payment received` is the provider's own statement, not a check RaajjePro performed.** Nothing on this screen may read as verification — no shield, no "verified", no certainty tick
- **No answer within 7 days sends this to RaajjePro to look at, and nothing is unlocked by it.** It is not a confirmation and must never be drawn as one
- **A withdrawn-claim state:** the customer may take back an unanswered "I've paid" — once per booking, only while the provider has neither confirmed nor disputed. The provider is notified and the booking returns to awaiting payment. Word it as a correction to the record, **not** as a dispute and not as an accusation — a mis-tap on the way to a banking app is the ordinary cause

## Mark the job complete

- The booking, and a confirm action
- **Emergency bookings additionally require a final amount** — what the job actually came to once parts and labour were added to the callout fee. **The job cannot be marked complete without it.** Convey why: it is the number a price dispute needs, and it is required precisely because a provider has no incentive to volunteer one that reflects badly on them
- **Not marking a job complete does not bury it.** After 7 days the customer is asked whether it happened; if they don't answer either, a further 3-day grace auto-closes it. Reviews open either way — silence is not a way to block them
- **The chat stays open after completion.** A warranty claim or a follow-up question about the same job still has its thread; it is never torn down

## States

Each screen: populated, loading, error. Plus the ones that carry meaning:

- Booking request: live countdown · near-expiry · timed out · offline-pending · slot-mode (no propose action) vs request-mode (with it)
- Propose: composing · sent-and-holding · expired
- Payment: awaiting · claim withdrawn · answered
- Complete: normal vs emergency-with-final-amount, and the required-field block on the latter

## Guardrails

- **No phone numbers, on any screen, in any state** — and no WhatsApp or Viber, which this system does not collect at all. The one reveal endpoint is emergency-only and lives on `Reveal Contact`
- Customer identified by **first name only** until a booking is accepted
- No "Payment Verified" or equivalent; no editorial labels about the customer; no encryption claims about chat
- Money as MVR, integer amounts. Categories are the Round 26 twelve — Home Repairs, never Events
- `StatusPill` carries the booking statuses; don't restate its labels inline
- Don't build the emergency accept screen, provider performance metrics, or billing — those are `Provider Emergency` and session 13
