Redesign one screen in `Emergency Flow.dc.html`: the **offers screen** (`fOffers`), where the customer chooses between providers who have accepted.

**Change nothing else.** The request form, the waiting screen, the expired screen, the dispatched screen and the whole `Provider Emergency.dc.html` artboard stay exactly as they are.

## Why it is being redesigned

It is currently a vertical stack of three rich cards. Three cards at that richness do not fit on one screen, so choosing means scrolling — and once you scroll, comparing becomes memory work. The 90-second collection window exists to give this customer a real choice between providers; a layout that cannot show the choices together hands that back.

Everything below serves one goal: **a stressed person, possibly at 2am, compares three strangers in a few seconds without scrolling.**

## Header — one clock, not two

A single large countdown: the 5-minute window to choose. Above it, `Pick one` and nothing else competing.

**The overall-window clock leaves the header.** It moves onto the reject-all action, below, where it is actually decision-relevant.

## The three offers — all visible at once

Compact rows, roughly 110px each, so three fit above the fold without scrolling. **Column-aligned**, so the eye scans down a dimension rather than across a card — same datum at the same horizontal position in every row:

- **Left:** initials avatar, provider name, and beneath it the tier badge and rating on one line
- **Middle:** distance
- **Right:** the callout fee, with `callout fee` beneath it

```
[IR]  Ibrahim Rasheed        1.2 km      MVR 350
      ◆ Gold · 4.6           Closest    callout fee

[HW]  Hassan Waheed          2.8 km      MVR 450
      ◆ Gold · 4.9                      callout fee

[AS]  Ahmed Shakir           0.8 km      MVR 500
      ◆ Silver · 4.4                     callout fee
```

The full tier copy (`ID checked, registered trade`) moves out of the row and into the selected state. It is reference material, not a comparison dimension.

### Comparison chips

Mark the winner on each dimension with a small neutral chip: **`Closest`**, **`Lowest fee`**, **`Highest tier`**. One provider may carry two.

These state an arithmetic fact about the three offers on screen — the same kind of fact as `1.2 km`. **Never a chip that judges the provider**: no `Recommended`, no `Best value`, no `Most reliable`, no ranking number, no star or crown. If a chip could describe the person rather than the comparison, it is wrong.

*(Note: `Closest` here is Ahmed Shakir at 0.8 km, and `Lowest fee` is Ibrahim Rasheed at MVR 350 — compute them, do not hardcode which row gets which.)*

### Empty slots stay visible

With only one or two offers in, render the remaining slots as **live placeholders** — a shimmer row with `still listening`. Fewer than three must read as *in progress*, not as *this is all you get*.

## Select, then confirm

Remove the per-row `Accept` button. Tapping a **row** selects it and expands only that one, revealing the full tier copy and the costs. A single primary CTA at the bottom commits.

Accepting is irreversible and incurs a fee — a per-card button on a five-minute clock is one mis-tap away from the wrong provider, and five minutes is ample for two deliberate taps.

## Costs stated once, at the confirm

**Remove `MVR 200` from the rows.** It is identical on every offer, so inside a comparison it is noise — and sitting beside the callout fee it blurs two different payees.

State it once, in the expanded selection, next to the button:

> **MVR 350** to Ibrahim Rasheed, paid directly — the final bill may differ once parts and labour are added.
> **MVR 200** dispatch fee to RaajjePro, by bank transfer afterwards.

Two lines, two payees, visually separate. Never a single combined total — RaajjePro does not collect the callout fee.

## Reject-all carries its own clock

Secondary action, naming its cost: **`Reject all and keep looking — 21:06 left`**, reading the live overall-window value.

## States

- **Loading** — three skeleton rows
- **1–2 offers** — real rows plus live placeholder slots
- **3 offers** — full comparison, nothing selected
- **Selected** — one row expanded, costs and CTA live
- **Confirming** — CTA spinner, rows locked
- **Rejected all** — returns to the waiting screen, overall clock still running
- **Expired** — `No one accepted in time`, nothing charged

## Unchanged facts

Offer data stays exactly as it is: Ibrahim Rasheed / Gold / 4.6 / 1.2 km / MVR 350 · Hassan Waheed / Gold / 4.9 / 2.8 km / MVR 450 · Ahmed Shakir / Silver / 4.4 / 0.8 km / MVR 500. Tier copy verbatim. No phone numbers. No provider ranking or judgement of any kind.
