A product rule changed: **the callback guarantee is now offered on six categories only** (Round 28). It was previously opt-in on any listing, which let a fishing charter advertise a free return visit.

**Eligible — keeps the callback:** Plumbing · Electrical · AC Repair · Appliance Repair · Pest Control · Home Repairs
**Not eligible — callback removed entirely:** Cleaning · Beauty · Fitness · Photography · Moving · Boat Charter

The promise is *"a free return visit within 7 days if the same problem comes back."* That only means something where a thing was fixed or treated and can un-fix — a drain re-blocks, a compressor fails again, bedbugs return. A trip, a shoot, a move, a clean or a haircut either happened or did not; there is no same problem to come back.

**On an ineligible category the control does not render at all — absent, not disabled.** A disabled toggle with a reason would be noise: there is nothing the provider can do about it and nothing they need to understand.

Six artboards carry callback. Change exactly these things.

## 1. `Create Service.dc.html` — step 6

The **Callback guarantee** block (toggle, the 7-day copy, the *"this one RaajjePro holds you to"* line) renders **only when the chosen category is eligible**. Add the eligibility as a lookup beside the existing `TAGS` / `EMG` tables — do not hardcode it into the markup:

```
CALLBACK = { 'Plumbing': true, 'Electrical': true, 'AC Repair': true,
             'Appliance Repair': true, 'Pest Control': true, 'Home Repairs': true };
```

Ineligible category, or no category chosen yet → the whole block is absent. Everything else on step 6 is unchanged: what's included, the single FAQ editor, warranty and insurance as unverified `Provider states: …`.

**The cast matters here.** The wizard is cast as an **Electrical** listing, which *is* eligible — so the default view keeps the callback block exactly as it is today. Switch the category prop to Boat Charter or Cleaning and it should vanish.

## 2. `ServiceCard.dc.html`

The `Free callback · 7 days` badge must not render for an ineligible category. The component already receives both `category` and `callback` — gate the badge on the pair rather than on `callback` alone, so a caller passing `callback: true` with an ineligible category simply gets no badge. That makes the component safe by construction rather than trusting every caller.

## 3. `Discovery.dc.html` — a live violation

In `SVCS`, the entry `c1` — **Home Deep Cleaning**, Mariyam Shifa, `cat: 'Cleaning'` — carries `cb: true`. Set it to `cb: false`. Check the rest of the list too: callback may only sit on Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control or Home Repairs entries. (`p1`, `p3` are Plumbing and stay as they are.)

## 4. `Provider Profile.dc.html`

Same check in the provider's listing data — `callback: true` only on eligible categories. The cast is a plumber, so this is likely already correct; confirm rather than assume.

## 5. `Service Preview.dc.html`

The **RaajjePro callback guarantee** block renders only for eligible categories. Its copy is right and stays as written — including keeping it visually separate from any provider-stated warranty, which is a rule Round 28 does not touch.

## 6. `Mark Complete.dc.html` — the cast is now wrong

The normal-booking scenario is **Sunset Fishing Charter**, a Boat Charter, and its completed state says *"including the free callback if the same problem comes back."* Under Round 28 that job has no callback.

- **Normal booking (Boat Charter):** the 7-day chat card keeps its title and the lock explanation, but drops the callback clause. Something like: *"Long enough to settle anything about this job. After that it locks — you can still read everything, and Book Again starts the next job properly."*
- **Emergency (AC Repair — eligible):** may keep a callback mention if it reads naturally.
- The footnote *"The chat stays open for 7 days after completion — the callback window — then locks read-only"* should not call it "the callback window" on an ineligible job. Say *"stays open for 7 days after completion, then locks read-only."* The 7-day lock is universal; only the callback framing is category-dependent.

## 7. `Booking Thread.dc.html` — the locked state

The locked bar's second line reads *"Same problem within 7 days of the job? That was the callback window — a claim opens its own booking."* This thread is cast as **Home Deep Cleaning** — Cleaning, not eligible. Drop that line for the ineligible cast; keep the lock notice and **Book Again**.

If you want the callback line demonstrated somewhere, the honest way is a second scenario cast as an eligible category — optional, not required.

---

## Leave alone

- The 7-day chat lock itself (Round 27) — universal, unrelated to callback eligibility
- The callback badge's visual separation from provider warranties, and the rule that a provider warranty never uses the callback treatment or the word "guaranteed"
- Everything about quote windows, occasion chips, emergency tiers and the Round 26 categories
- All of `Booking Request`, `Propose Time and Price`, `Payment Received`, `My Services`, `Availability`, `My Calendar`
