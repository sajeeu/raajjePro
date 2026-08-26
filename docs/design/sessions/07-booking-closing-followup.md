# Session 6 corrections — four claims the product can't keep, and two labels

Seven screens, and the hard part landed. Cancel, dispute and report are unmistakably three different severities — navy, red, and grey-blue, with the dispute screen's own header colour doing most of that work. The rate screen really is two taps. The recurring series never once reads as a subscription that runs itself, which was the whole risk on that screen. The `wasSentByMe` line is gone from Propose Amendment.

Four things claim something the system doesn't do, and two labels drifted off their fixed sets.

---

## 1. Book Again — the slot note says the customer is confirmed

Bottom of the slot scenario, under the CTA:

```js
ctaNote: 'Mariyam books by open slots — pick one and you’re confirmed.'
```

Picking a slot does not confirm anything. It creates a booking at `requested`, and Mariyam then has **24 hours** to accept or decline — the same accept step every booking in the product goes through. Session 4 built Pick a Time around exactly this sentence and the brief for it said the screen fails regardless of how it looks if a customer walks away believing they have a cleaner confirmed. Book Again feeds *into* Pick a Time, so it must not promise what the next screen then walks back.

```js
ctaNote: 'Mariyam still has to accept — picking a slot sends her the request.'
```

The request-mode note is fine as it stands.

## 2. Cancel Booking — the emergency re-send describes first-acceptance-wins

In `provider_cancelled_emergency`:

> You'll be notified the moment a plumber accepts, exactly like the first time.

Acceptances don't race. The first acceptance opens a **90-second collection window** during which other eligible plumbers can also accept, and at the end the customer picks from **up to three offers** side by side — each with that provider's callout fee and arrival estimate. "The moment a plumber accepts" describes the one-provider-at-a-time model that was replaced, and "exactly like the first time" is the only thing currently carrying the real behaviour.

Say what actually happens:

> As plumbers accept you'll get their offers together — callout fee and arrival estimate — and you choose, exactly like the first time.

Everything else in that card is right and should not move: the re-broadcast excluding Ibrahim, the no-second-dispatch-fee panel, and the fact that there is nothing for the customer to redo.

## 3. Raise a dispute — "both of you see the same record"

In the "What RaajjePro holds — and acts on" card:

> An admin reviews exactly that — **both of you see the same record** — and patterns across bookings count against a provider.

The record goes to the **admin** with both parties' history shown together. There is no shared evidence view where the customer and provider both read the same dispute file, and nothing in the plan builds one. This is the same class of defect as session 5's invented adjudication step: a reassurance that sounds procedural and isn't backed by anything.

Cut the middle clause. The sentence is stronger without it:

> An admin reviews exactly that, and patterns across bookings count against a provider.

The line below it — that the payment moved outside RaajjePro and can't be refunded or reversed from here — is exactly right and stays.

## 4. Did this happen — the "No" answer is pilled as a payment problem

The `no` state renders `<dc-import name="StatusPill" status="unresolved">`, which prints **"Unresolved"** in red. In `StatusPill` that label belongs to `payment_unresolved` — the day-7 escalation when a provider never answers a payment claim. The customer has just said a provider didn't turn up; telling them their *payment* is unresolved names the wrong problem.

The plan routes a "No" the **same path as a dispute**, so use the pill that says so:

```html
<dc-import name="StatusPill" status="disputed" hint-size="100px,28px"></dc-import>
```

Dropping the pill entirely is also acceptable — the card copy already carries the state. What it must not say is "Unresolved".

## 5. Report — two message reasons drifted off the fixed set

The message reason set is fixed: `harassment` · `contact_solicitation` · `spam` · `abusive_content`. The artboard renders the second as **"Asking to deal off-platform"**, and the sample message underneath it is *"Let's arrange this outside the app — cheaper for you."*

Those are a different thing. `contact_solicitation` is someone asking for your phone number or pushing you onto WhatsApp — which matters here because in-app chat is the only channel the product has, and a customer who wants to report being asked for their number currently finds no reason that fits. Off-platform dealing is a business problem; contact solicitation is the safety one.

- Label: **"Asking for contact details"**
- Sample message: something like *"Just WhatsApp me on my number and we'll sort it faster."*

The other four reason sets match their fixed sets exactly and stay as they are.

## 6. Recurring — the series header prices it by the week

> Home Deep Cleaning · Mariyam Shifa · **MVR 450 a week**

Every other line on that screen works to stop this reading as a standing arrangement, and the header undoes it: "a week" is subscription language, and it isn't even accurate — a week Mariyam doesn't confirm costs nothing, and the customer pays her per job, off-platform, each time.

> Home Deep Cleaning · Mariyam Shifa · MVR 450 a visit

Leave the rest of the recurring screen alone entirely — the skipped-week sentence, the three-miss pause, Skip versus End the series, and the "weekly ask, not a standing booking" note are all correct.

---

## Leave alone

Everything not named above. Specifically worth protecting because it is right and easy to disturb: the three severities' visual separation; the two-tap rate flow and the three-customers-before-a-tag-shows line; the eight Cleaning tags; the dispute screen's four fixed reasons and its photo slots; Report's per-target context card and the hidden-never-deleted-with-appeal copy; Book Again's carried-over details and its delisted state; Did this happen's silence line and its 3-day date arithmetic, which checks out against the 18 Aug booking.

No phone number appears on any of the seven screens, no payment is described as verified, no editorial provider label is generated anywhere, and every component prop used — including `StatusPill status="unresolved"`, `Chip kind="static"` and `VerificationBadge tier="Silver"` — is a declared value rather than an invention. Those were checked against the component files, not assumed.
