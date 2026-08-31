Round 2 for the provider job screens — four corrections from the audit, plus **one product change decided since the brief: Round 27, the chat now locks after completion.** The screens are otherwise right: the occasion subtitle runs through everything, the no-phone-number card explains itself instead of apologising, "Provider confirmed receipt" is worded exactly, and the withdrawn-claim state reads as a correction rather than an accusation. Change only what's below.

## 1. `Propose Time and Price` — the quote-window table is wrong five ways

`WINDOWS` currently reads:

```
{ 'Boat Charter': 72, 'Events': 48, 'Photography': 48, 'Plumbing': 4, 'Electrical': 4,
  'AC Repair': 4, 'Appliance Repair': 4, 'Pest Control': 4, 'Home Repairs': 4,
  'Cleaning': 24, 'Beauty': 24, 'Gardening': 24 }
```

- **`Events` and `Gardening` do not exist** — both are retired category names and the file fails the project gate while they're present.
- **Photography is 72, not 48.** The long group is exactly **Boat Charter, Photography, Moving — all 72** — and Moving is missing.
- **Cleaning and Beauty never quote.** They're slot categories; there is no approval window for them, and 24 is an invented number. Remove them from the table **and remove `Cleaning` from the category prop options** — this screen cannot exist for a slot category.

The table is exactly the nine request categories and nothing else:

```
{ 'Boat Charter': 72, 'Photography': 72, 'Moving': 72,
  'Plumbing': 4, 'Electrical': 4, 'AC Repair': 4,
  'Appliance Repair': 4, 'Pest Control': 4, 'Home Repairs': 4 }
```

No fallback default — every legal value of the prop is in the table.

## 2. `Propose Time and Price` — don't promise a quote composer in the chat

The sent state says *"If you agree on something different, send a fresh quote from the chat."* The chat has no quote action — that sentence advertises a mechanism that doesn't exist. Reword to what is true: the conversation happens in chat, and the quote stands as sent until Mariyam accepts it or it lapses.

## 3. `Mark Complete` — the emergency scenario is illegal for this provider

The emergency job reads **"Plumbing emergency."** Plumbing emergencies require **Gold**; Ibrahim is Silver, and he holds no plumbing listing. Make it an **AC Repair emergency** — Silver qualifies there (that's the whole point of the per-category bar), and his **AC Service & Repair** listing exists. Title, subtitle, icon and reference change; the callout fee, the required final amount, and all its copy stay exactly as built.

## 4. `My Services` — over-limit must hide every published listing but one

With Sunset Fishing Charter added there are three published listings, and the `free-over-limit` scenario still hides only one — leaving two live under a plan whose copy says **"1 live service."** In that scenario every published listing except the chosen live one shows the hidden state. "Make this one live instead" then swaps which single listing is live, hiding the rest.

## 5. `Booking Request` — one label in slot mode

In the `Slot booking` variant the detail row still says **"Requested window."** A slot customer picked a published time — label it **"Booked time"** in that mode. Request mode keeps "Requested window."

---

## 6. Round 27 — the chat locks 7 days after completion

Decided since the brief went out; the brief's "the chat stays open after completion — it's never torn down" instruction is **withdrawn**. The rule now: the thread stays open through the booking **and for 7 days after completion — the callback-guarantee window — then locks read-only.** History is never deleted. Repeat work goes through **Book Again**; a callback claim made inside the window creates its own linked zero-cost booking with its own thread; a dispute reopens the thread while it runs.

**In `Mark Complete`, replace both stays-open blocks:**

- The completed-state card titled *"The chat stays open"* becomes *"The chat stays open for 7 days"* — body to the effect of: *"Long enough to settle anything about this job, including the free callback if the same problem comes back. After that it locks — you can still read everything, and Book Again starts the next job properly."*
- The footnote *"The chat with Mariyam stays open after completion — warranty claims and follow-ups keep their thread"* becomes: *"The chat stays open for 7 days after completion — the callback window — then locks read-only."*

Never use the phrases "never torn down" or "stays open after completion" — both now fail the project gate.

**In `Booking Thread`, add one scenario: `Locked — job closed`.** The booking completed more than 7 days ago. Full history visible and readable; the composer is replaced by a quiet locked bar — not an error, not a wall — saying the job is closed, with two actions:

- **Book again** → `Book Again.dc.html`
- A secondary line, plain text: *"Same problem within 7 days of the job? That was the callback window — a claim opens its own booking."* (Past tense is correct — by the time this state renders, the window has passed.)

Nothing else in `Booking Thread` changes: the live-booking states, the block notice ("stays open until this booking ends"), and the enquiry-thread copy are all still correct — a block never severs a live booking's chat, and that rule is untouched by Round 27.

---

## Leave alone

- Every use of `StatusPill` — `pending_offline`, `payment_sent`, `receipt_confirmed` are all real keys; the offline-pending treatment on `Booking Request` is exactly right
- The countdown card and its near-expiry shift; the accept sheet restating price/date/time/scope; the decline sheet's acceptance-rate honesty
- The hold-covers-all-listings line on Propose, and "a Boat Charter quote clock"
- The whole of `Payment Received` — including the withdrawn-claim card and the decline sheet's return-the-money warning
- The emergency final-amount field, its error, and its reason copy on `Mark Complete`
- Sunset Fishing Charter's card in `My Services` and the occasion subtitle everywhere
