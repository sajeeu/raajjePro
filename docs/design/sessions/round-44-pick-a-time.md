# Round 44 — "Pick a time", not "Book instantly"

A rename, and the two sentences that had believed the old name.

**Leave alone:** every layout, colour, component, animation and flow. No screen
gains or loses a step. Nothing about how a slot booking works changes — only what
the app says about it. Round 43's fixes stand; this round touches nothing they
touch.

---

## Why

Picking a published slot does not confirm a booking. It creates a `requested`
booking that the provider still has to accept, on the same 24-hour auto-decline
clock a request-based booking runs on. The provider accepting is what confirms
it, in every mode.

So "Book instantly" named an immediacy the product does not produce, and two
screens then repeated the label as if it were a fact — which is how it was
caught. The plan has been amended: **§0.0 item 13, §1c and Phase 7, revision
5.17.**

`Book Again` already gets this right and is the model for the wording:

> Mariyam still has to accept — picking a slot sends her the request.

Leave that screen exactly as it is.

---

## 1. The card affordance

**Files: `ServiceCard`, `Home`, `Components`, `Service Preview`, `session.js`.**

Replace the slot-mode label **"Book instantly"** with **"Pick a time"** everywhere
it renders. `"Request a time"` is unchanged.

The affordance still does its Round 23 job, because the distinction between the
modes survives the rename and is in fact clearer for it:

- **`slot` → "Pick a time"** — the customer chooses from times the provider has
  already published.
- **`request` → "Request a time"** — the customer asks, and the provider comes
  back with a time and a price.

Pick versus request is the real difference. Neither label now implies the booking
is settled on tapping, because in neither mode is it.

The second signal is unchanged: `slot` still shows the next open time
(`Next: today 14:00`), `request` still shows median reply time or `New provider`.
The next open time answers *how soon can someone come*, which is a real question
and still worth showing.

Also in scope:

- `Home`'s quick-filter row: the chip currently reading `Book instantly` becomes
  `Pick a time`. (`Near me` and `Available today` are unchanged. The row is three
  chips — Round 41 removed the Emergency chip.)
- `session.js`: the comment `// slot ("Book instantly") only for Cleaning,
  Beauty, Fitness` becomes `// slot ("Pick a time") only for …`. The seed data
  itself does not change.

---

## 2. `Service Preview` says the booking is confirmed. It is not.

Currently:

```js
modeTitle: instant ? 'Book instantly' : 'Request a time',
modeSub: instant ? "Pick one of " + L.first + "'s published times — confirmed straight away." : L.requestSub,
```

**Do:**

```js
modeTitle: instant ? 'Pick a time' : 'Request a time',
modeSub: instant ? "Pick one of " + L.first + "'s published times — " + L.first + " confirms it, usually within the hour." : L.requestSub,
```

"Usually within the hour" is the honest shape of the claim: it says what normally
happens without promising it, and the 24-hour auto-decline is the backstop if it
does not. Do not write a number the product cannot keep — no "instantly", no
"immediately", no checkmark.

---

## 3. `Help & support` — the booking FAQ

The first answer currently reads:

> Find a service on Explore, pick a time, and confirm. Your saved address and
> instructions pre-fill the booking — you can edit them right there.

"and confirm" reads as the customer confirming, which is not what happens.
Replace with:

> Find a service on Explore and pick a time, or send a request if the provider
> quotes per job. Your saved address and instructions pre-fill it — you can edit
> them right there. The provider confirms, and you're notified as soon as they do.

This answer sits next to the reschedule answer Round 43 rewrites. Both end up
saying the same thing about the same rule, which is the point: the time is agreed
by two people, so one person cannot set it alone.

---

## 4. What must not change

- **`Book Again`** — already correct, both modes. Do not touch it.
- **The flow itself.** No screen gains a confirmation step, loses one, or
  reorders. A slot booking has always worked this way; only the words were wrong.
- **`Request a time`, `Pick a Time`, `Quote Received`** — the request-side
  wording is unaffected.
- **The second card signal**, the callback badge, and the emergency entry.
- **Round 43.** If it has not been applied yet, apply it first; this round
  assumes its dead ends and its three reworded claims are already in.

---

## Checklist

- [ ] No file contains the string `Book instantly`
- [ ] Slot cards read `Pick a time`; request cards still read `Request a time`
- [ ] `Home`'s chip row reads `Near me · Available today · Pick a time`
- [ ] `Service Preview` no longer says a slot booking is confirmed straight away
- [ ] `Help & support`'s booking answer says the provider confirms
- [ ] `Book Again` is unchanged
- [ ] The next-open-time and reply-time signals are unchanged
- [ ] Nothing from Rounds 40–43 changed
