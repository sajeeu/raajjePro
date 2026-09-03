# Round 43 — dead ends and drift

Everything found while importing the last of Rounds 38–40. Nothing here is new
design: it is controls that go nowhere, three claims that have drifted from what
the product does, and one counter that does not count.

**Leave alone:** every layout, colour, component and animation, and all of Rounds
40, 41 and 42. This round wires up existing controls and rewords four sentences.

One conflict found in the same pass is deliberately **not** in this round — the
"Book instantly" affordance. It is a plan question, not a design correction, and
it is being settled separately. Do not touch any card's mode label.

---

## 1. "Mark all read" leaves one unread

**Screen: `Notifications`.**

The list carries four unread items — `accepted`, `payment`, `message` and the
`quote` item added in Round 38. `markAll` still sets three:

```js
markAll: () => this.setState({ read: { accepted:true, payment:true, message:true } }),
```

So tapping *Mark all read* leaves *Quote received* unread and the header stuck at
**1 unread**. A control that names an absolute — *all* — and then does not do it
is worse than one that is missing, because the user stops checking.

**Do:** derive the ids from `ITEMS` rather than listing them, so a fifth
notification cannot reintroduce this:

```js
markAll: () => this.setState({ read: Object.fromEntries(this.ITEMS.map(n => [n.id, true])) }),
```

---

## 2. Controls that go nowhere

Twenty-two of them across fifteen screens. Every one has a real label, so every
one is a promise. Group A is a single shared handler; groups B–D are individual.

### 2a. `retry` — an empty handler behind a **Try again** button

**Screens: `Analytics`, `Booking Request`, `Mark Complete`, `Payment Received`,
`Pick a Time`, `Propose Time and Price`.**

Each defines `retry: () => {}` and wires it to the error state's *Try again*.
Tapping it leaves the error on screen with no feedback at all, which reads as the
retry having failed instantly.

**Do:** in each, make `retry` return the screen to its normal scenario — the same
thing `Help & support` and `App States` already do. Where a screen has no normal
state to return to, toast `Retrying…` as `Invoices` does. Do not leave any of
them empty.

### 2b. Message buttons that do not open the chat

| Screen | Button |
|---|---|
| `Quote Received` | `Message Ibrahim` |
| `Quote Received` | `Message Ibrahim about the time or price` |
| `Quote Received` | `Ask Ibrahim again in chat` |
| `Reveal Contact` | `Message Ibrahim` |
| `Reveal Contact` | `Back to chat — arrival details live there` |
| `Propose Amendment` | `Message Mariyam` |
| `Provider Profile` | `message` (empty handler) |

All seven go to `Booking Thread.dc.html`, except `Provider Profile`'s, which
predates any booking and goes to `Enquiry Thread.dc.html`.

These matter more than the others. In-app chat is the only coordination channel
that exists between these two parties — there is no contact exchange to fall back
on — so a message button that does nothing removes the only route there is.

### 2c. The rest

| Screen | Control | Send it to |
|---|---|---|
| `Book Again` | `Change something` | `Request a Time.dc.html` in request mode, `Pick a Time.dc.html` in slot mode — the same target as the footer CTA |
| `Dispatch Fee` | `Not now` | Back to `Booking Detail.dc.html`. The fee is recorded as owed either way; dismissing the screen must not look like dismissing the debt |
| `Enquiry Thread` | `Verify my email` | `Verify Email.dc.html` |
| `Pick a Time` | `Resend link` | Keep it local: restart the countdown, as `Forgot Password` does |
| `Request a Time` | `Resend link` | Same |
| `Provider Profile` | `report` (empty handler) | `Report.dc.html` |
| `Service Preview` | `report` (empty handler) | `Report.dc.html` — this is Round 41 §4, still outstanding |

---

## 3. Two personas in the wrong role

### 3a. `Mark Complete` shows a provider as the customer

The provider is closing a job, so the counterparty is the customer. It is
currently **Mariyam Shifa**, who is the cleaner on `Home Deep Cleaning`. Four
lines name her:

> Mariyam can rate the job now, and you can rate her back.
> Mariyam has been told the trip is done.
> Mariyam is asked whether the job happened…
> Mariyam sees the same number…

**Do:** rename all four to **Aishath Naeema**, and change `her` to `them` in the
first. This is the same fix as Round 41 §1b on `Payment Received`; the two
screens drifted the same way.

### 3b. `Mute Block Decline` is one letter short

```js
'Aishath Naeem' : 'Mariyam Shifa'
```

The customer persona is **Aishath Naeema**. The role branch itself is right —
mute the provider from the customer's side, the customer from the provider's —
so change only the spelling. A name spelled almost right reads as a different
person, which is exactly the wrong effect on a screen about blocking someone.

---

## 4. Three claims that are no longer true

### 4a. `Reveal Contact` says the chat never ends

> The chat never expires — a follow-up question or a warranty claim still has its
> thread.

Round 27 replaced that. The thread stays open for the life of the booking **and
for 7 days after completion — the callback-guarantee window — then locks
read-only**. History stays readable forever, and a dispute reopens it.

**Do:** replace with:

> The chat stays open for 7 days after the job, then locks — the history stays
> readable, and a callback claim or a dispute reopens it.

Drop "warranty": the 7-day callback guarantee is the thing that exists, and
naming it as a warranty implies something longer and broader.

### 4b. `Help & support` describes a reschedule as a notification

> **Can I cancel or reschedule a booking?** Yes — open the booking and choose
> cancel or reschedule. The provider is notified straight away.

Cancelling is one-sided; rescheduling is not. Once a booking is accepted the
price, date, time and scope are locked, and changing any of them takes an
amendment the other party accepts. "The provider is notified" describes a change
that has already happened.

**Do:** replace the answer with:

> Yes. Cancelling is immediate — the provider is told straight away, and a late
> cancellation counts towards your record. Rescheduling is a request: the time
> was agreed by both of you, so the provider has to accept the new one before it
> is set.

### 4c. `Help & support` promises a screenshot that may not exist

The success copy is fixed:

> Support has your message and screenshot.

The attachment is optional, so this is wrong whenever nobody attached one.

**Do:** say "your message and screenshot" only when `attached` is true, and
"your message" otherwise.

---

## 5. One question, not an instruction

`App States` lists **Accepting a booking** among the things that queue offline
and send on reconnect, which is right — an accept tapped in airplane mode is
meant to replay rather than be lost.

But an emergency offer has a 30-minute window, and a queued accept can replay
after it has closed. The provider would see their acceptance queued, then
nothing. Nothing on the screen is wrong today; it just does not say what happens
in that one case.

Do not change it in this round. Flagging it so it is decided rather than
discovered — the honest options are to exclude emergency accepts from the queue,
or to keep queueing them and say plainly that an offer can expire while offline.

---

## Checklist

- [ ] `Notifications` marks every item read, derived from `ITEMS`
- [ ] No screen defines `retry: () => {}`
- [ ] All seven message controls reach a thread
- [ ] The seven remaining dead controls reach the screens named above
- [ ] `Mark Complete` names Aishath Naeema in all four places
- [ ] `Mute Block Decline` spells Aishath Naeema in full
- [ ] No screen claims the chat never expires
- [ ] The reschedule and screenshot answers in `Help & support` are reworded
- [ ] No card's booking-mode label changed
- [ ] Nothing from Rounds 40, 41 or 42 changed
