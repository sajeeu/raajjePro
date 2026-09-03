# Round 45 — loose ends

What Rounds 43 and 44 left behind, plus three things the walk-through turned up
on the way. Nothing here is new design.

**Leave alone:** every layout, colour, component, animation and flow, and all of
Rounds 40–44. This round wires up controls, swaps two icons and rewords five
short strings.

---

## 1. Nineteen more dead controls — the same defect, a different shape

Round 43 wired up every `<button onClick="{{ noop }}">`. It missed nineteen
controls that pass `noop` to a **component's** action instead:

```html
<dc-import name="EmptyState" … action-label="Try again" on-action="{{ noop }}">
```

Eighteen of those are the error state's **Try again** — the exact control Round
43 §2a fixed on six other screens — on:

`Book Again` · `Booking Detail` · `Booking Thread` · `Cancel Booking` ·
`Did This Happen` · `Dispatch Fee` · `Enquiry Thread` · `Messages` ·
`My Bookings` · `Payment Step` · `Propose Amendment` · `Quote Received` ·
`Raise Dispute` · `Rate This Job` · `Recurring Booking` · `Report` ·
`Request a Time` · `Reveal Contact`

**Do:** give each a real `retry` that returns the screen to its normal scenario,
the way `Analytics`, `Mark Complete` and `Pick a Time` now do. Where a screen has
no scenario to return to, toast `Retrying…` as `Invoices` does.

### 1b. The nineteenth is a message button

**Screen: `Pick a Time`, the `no_times` state.**

> **No times published yet** — Mariyam hasn't put up open times right now. You can
> ask her in chat — messaging is open before you book.

`Message Mariyam` is wired to `noop`. The copy directly above it tells the
customer that chat is their way forward, and then the button doesn't go there.
Point it at `Enquiry Thread.dc.html` — this is before any booking exists, so it
is the enquiry thread, not the booking one.

---

## 2. The lightning bolt outlived the label it belonged to

**Files: `ServiceCard`, `Service Preview`.**

Round 44 renamed the slot affordance to **Pick a time**, but its icon is still
the lightning bolt — `M13 2L5 13h6l-1 9 8-11h-6l1-9z`. A bolt means *fast*, which
is precisely the promise the rename removed, so the label and the icon now say
different things.

It is worse on `Service Preview`, where **the same bolt marks the emergency
panel**. One glyph, two unrelated meanings, one screen.

**Do:** give `Pick a time` a clock — `<circle cx="12" cy="12" r="8.6"></circle>`
plus `<path d="M12 7.5V12l3 2"></path>` — matching the clock already used for the
next-open-time signal. Leave the bolt to emergency, where the urgency is real.
`Request a time`'s calendar icon is unchanged.

---

## 3. One action, three names

The customer does one thing — choose from the times a provider published — and
the app calls it three different things:

| Where | Says |
|---|---|
| The card (`ServiceCard`) | **Pick a time** |
| `Service Preview`'s primary CTA | **Book now** |
| `Book Again`'s CTA | **Choose a slot** |

`Book now` is the one that matters: it sits directly under a panel that now says
*"Mariyam confirms it, usually within the hour"*, so the screen contradicts
itself in two adjacent elements. And "slot" is internal vocabulary — a customer
picks a time, not a slot.

**Do:** make all three read **Pick a time**. The request-side pair —
`Request a time` on the card and the CTA — is already consistent; leave it.

### 3b. Two smaller carriers of the old idea

- **`Components`** still explains the modes in prose as *"instant shows the next
  open slot"*. Change `instant` to `Pick a time` so the sheet's explanation
  matches the label it just documented.
- **`Components`**'s Button examples all read **Book now**. Change them to
  **Pick a time** as well, since they are the reference for that primary button.

### 3c. The prop value, which is the one that becomes code

`ServiceCard` and `Service Preview` take `mode="instant" | "request"`. The plan's
booking modes are **`slot`**, **`request`** and **`emergency`** — `instant` is not
one of them, and it is now the last place in the prototype still carrying the
word the rename removed. A developer reading these files will name the enum after
what they see.

**Do:** rename the prop value `instant` → `slot` in `ServiceCard`,
`Service Preview` and `Components`. The rendered label is unaffected.

---

## 4. "Never shared" is one exception short of true

**Screens: `Home` (the trust grid), `Provider Profile` (footer), `Booking
Request`.**

All three state it absolutely:

> Private messaging — your contact details are never shared.
> RaajjePro never shares numbers.

There is exactly one exception, and it has its own screen: the emergency reveal —
customer-initiated, emergency bookings only, mutual and simultaneous, expiring 24
hours after the booking closes. `Reveal Contact` opens by calling itself *"the one
place in RaajjePro where numbers are shared"*, so two screens currently contradict
a third.

**Do:** say what is actually guaranteed rather than an absolute.

- `Home` and `Provider Profile`: **Private messaging — your phone number stays
  private, and you talk in the app.**
- `Booking Request`: keep the paragraph, and change *"RaajjePro never shares
  numbers"* to **"RaajjePro doesn't share numbers on bookings like this one"** —
  the line immediately after it already points at Provider Emergency as the
  different case, so this makes that sentence land instead of contradicting it.

Do not add a caveat, an asterisk or a link to the reveal. On a slot or request
booking the promise is absolute and should read that way; it is only the word
*never*, applied to the whole product, that overreaches.

---

## 5. Two small wrong things

### 5a. "View my bookings" goes to Home

**Screens: `Pick a Time`, `Request a Time`**, both in their sent state.

The primary button after sending a request reads **View my bookings** and links to
`Home.dc.html`. Point both at `My Bookings.dc.html`. This is the moment a customer
most wants to see the thing they just created.

### 5b. `Booking Request` calls an unaccepted time "Booked time"

In slot mode the detail row is labelled **Booked time**. Nothing is booked — the
provider is deciding whether to accept, and the same screen's footer says
*"Accepting locks the price, date, time and scope"*.

**Do:** label it **Requested time** in both modes. The request-mode label,
`Requested window`, is right and stays.

---

## 6. Still open from Round 43, still not an instruction

`App States` queues **Accepting a booking** for replay on reconnect, which the
plan requires. An emergency offer has a 30-minute window, so a queued acceptance
can replay after it closed — the provider sees it queued, then nothing.

Unchanged again this round. It needs a decision, not a design: either exclude
emergency accepts from the queue, or keep queueing them and say plainly that an
offer can expire while offline.

---

## Checklist

- [ ] No file passes `noop` to a component's `on-action`
- [ ] `Pick a Time`'s `Message Mariyam` reaches `Enquiry Thread.dc.html`
- [ ] The slot affordance uses a clock; the bolt is emergency-only
- [ ] Card, `Service Preview` CTA and `Book Again` CTA all read `Pick a time`
- [ ] `Components` says `Pick a time` in its prose and on its Button examples
- [ ] The `mode` prop value is `slot`, not `instant`
- [ ] No screen claims contact details are *never* shared
- [ ] Both `View my bookings` buttons reach `My Bookings.dc.html`
- [ ] `Booking Request` says `Requested time`, never `Booked time`
- [ ] Nothing from Rounds 40–44 changed
