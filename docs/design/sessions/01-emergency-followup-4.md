Two changes across both artboards. The plan changed underneath this design.

## What changed and why

Moving used to get a **120-minute** response window while the other three emergency categories got 30. The stated reason was that "a mover needs a vehicle and usually a crew" — but that describes how long a mover takes to **arrive**, not how long they may take to **answer**. One field was doing both jobs.

The cost landed on the customer: an emergency move could sit **two hours before learning nobody was coming**. It also left a 90-second collection window and a 5-minute choice window inside a two-hour outer clock.

So: **the response window is now 30 minutes on all four categories**, and **arrival time is stated per offer** by the provider who makes it.

## Change 1 — `Provider Emergency.dc.html`: arrival estimate alongside the fee

The provider now supplies **two** things in the one accept action, not one.

- Add an **arrival estimate** control beside the callout fee — `When can you get there?`
- Make it fast to answer under pressure: **one-tap presets drawn from the category**, with free entry underneath for anything they do not cover. Do not make a stressed person type a number
  - Plumbing, Electrical, AC Repair: **15 · 30 · 45 · 60** minutes
  - Moving: **60 · 90 · 120 · 180** minutes
  - Read these from the category table, never write one set into the screen. A mover offered a 15-minute option and a plumber offered a 3-hour one are both being shown noise
- **Nothing is preselected**, and the offer cannot be sent without a choice. Preselecting anchors the estimate, and the cheapest anchor to accept is the most optimistic one — a provider who taps the lowest value to win the bid and arrives at three times it is the arrival-time version of price hiking
- Both fee and arrival are required to send. The CTA reads `Send offer — MVR 350, 30 min`
- Convey: **this is your own estimate, and the customer sees it next to everyone else's.** Say plainly that arriving later than stated affects their on-time record — a provider who says 15 minutes to win the job and turns up in 90 should know that is measured
- In the `CATS` table, Moving becomes `win: 30`. All four categories now read 30

The default fee stays `MVR 350`. Arrival has **no default** — the provider picks.

## Change 2 — `Emergency Flow.dc.html`: arrival becomes the comparison dimension

**Arrival replaces distance as the primary middle column.** Distance was only ever a proxy for "how soon can they be here" — now that the real answer exists, the proxy stops being a decision axis.

Keep distance, but demote it: small, beneath the arrival time, as supporting detail. That pairing is deliberate — arrival is **claimed by the provider**, distance is **measured by the platform**, and a customer looking at `5 min` above `8.4 km` can draw their own conclusion. Never flag that mismatch yourself; just put the two numbers together and let the reader do it.

```
[IR]  Ibrahim Rasheed        ~30 min      MVR 350
      ◆ Gold · 4.6           1.2 km      Lowest fee

[HW]  Hassan Waheed          ~40 min      MVR 450
      ◆ Gold · 4.9           2.8 km

[AS]  Ahmed Shakir           ~15 min      MVR 500
      ◆ Silver · 4.4         0.8 km      Soonest
```

- Arrival renders as an estimate, never a fixed time: `~30 min`, or `arrives in ~30 min` where there is room
- **Chips become `Soonest` · `Lowest fee` · `Highest tier`.** `Closest` retires with distance's demotion — keeping four chips over three rows makes the screen busy for no gain, and `Soonest` is the question `Closest` was standing in for
- Chip rules are unchanged: computed, never hardcoded; nothing shown on a tie; nothing shown below two offers; never a chip that judges the provider
- Arrival appears in the expanded selection too, as part of what is being agreed

Offer data becomes: Ibrahim Rasheed / Gold / 4.6 / 1.2 km / **~30 min** / MVR 350 · Hassan Waheed / Gold / 4.9 / 2.8 km / **~40 min** / MVR 450 · Ahmed Shakir / Silver / 4.4 / 0.8 km / **~15 min** / MVR 500.

Note this makes the three chips split across all three providers, which is a fair test of the layout — check it still reads cleanly when one provider carries two.

## Change 3 — the 30-minute window everywhere

In `Emergency Flow.dc.html`'s `CATS` table, Moving becomes `win: 30`. Anywhere the request screen or the waiting screen states the window for Moving, it now reads 30 minutes like the rest.

## Unchanged

Everything else on both artboards. The select-then-confirm interaction, the single header clock, reject-all with its own countdown, the `MVR 200` treatment at the confirm, the live placeholder slots, tier copy, and every state. These are additive changes, not a redesign.
