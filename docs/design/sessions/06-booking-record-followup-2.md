# Session 5 corrections, round 2 — one line left behind

All five corrections landed, and the two material ones landed exactly. The not-arrived flow now says what the system actually does — *"Ibrahim has been released — we're finding someone else"*, with no second dispatch fee and the no-show on his record — and the arrival/response distinction is clean in both places: **"Ibrahim estimated 45 minutes — that was 21:26"** on the card, **"Accepted · 45 min arrival estimate"** on the timeline. The unspecified admin-reads-chat sentence is gone and the rest of the dispute paragraph survived intact. Reveal contact reads for an AC call at 2pm as well as a burst pipe at midnight.

One change.

---

## Propose Amendment

### The sent state still calls every change a price change

Letting the provider use all four chips is right, and `showAdherence: isProvider && field === 'price'` gates the price-adherence card correctly. But one line below it kept the old assumption:

```js
const sentField = isProvider ? 'price' : field;
```

So a provider who moves a Tuesday job to Wednesday — the exact case that justified the change — proposes a date, taps send, and is told:

> **Sent to Aishath**
> The agreement hasn't changed — **the new price** takes effect only if Aishath accepts.
> Your proposal · on the record
> **Price: MVR 450 → Wed 26 Aug**

The proposal itself is fine; the confirmation misnames it. `sentField` no longer needs to differ from `field` at all:

```js
const sentField = field;
```

While you're in there: `sentLine` falls back to `'MVR 600'` when `propVal` is empty. That default is only reachable from the `sent` demo scenario, which is a price proposal, so it is harmless today — but if you touch that line, make the fallback come from the selected field rather than a hardcoded amount.

---

## Leave alone

Everything else. Specifically: the chip behaviour and the `fieldTouched` default that keeps the provider landing on Price without locking them there, the price-adherence gate, the not-arrived copy in both states, the arrival-estimate labels, the reveal-contact framing and its six conditions, and the whole dispatch-fee treatment. My Bookings and Dispatch Fee were checked against the project again this round and are unchanged — correct.
