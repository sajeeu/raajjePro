Discovery is right and the imports resolve — keep all of it. The four screens, the sort actually reordering the list, sponsored-first placement, the searchable island sheet, the optimistic unsave with its rollback, and the empty states that name the specific reason: all correct, do not rework them.

**One product decision changed underneath the design**, and it touches `ServiceCard.dc.html` as well as `Discovery.dc.html`.

## What changed and why

The **"Emergency available"** marker is gone from cards and from search filters.

It could never work. Emergency dispatch **broadcasts to every eligible provider at once** — the customer submits an ASAP request, everyone eligible is asked, up to three bid, and the customer picks from the offers. There is no path anywhere in the product that sends an emergency to one named provider.

So a marker on Ibrahim Rasheed's card advertised an action that does not exist. Worse, it did so at the moment it mattered most: someone with water spreading who browses to that card *because* of the marker, taps through, and finds the request goes to everyone has spent their scarcest resource believing they were summoning a particular person.

Your own design surfaced the cost. The search empty state has to explain that *"'Under MVR 300' and 'Emergency available' are filtering everything out"* — a dead end produced by a filter that could not have helped even when it returned results.

## 1 — `ServiceCard.dc.html`: drop `emergency`, add two things

**Remove the `emergency` prop and the `Emergency available` chip entirely**, from both variants.

**Add `callback` (boolean).** Where true, render a badge for the **callback guarantee**: a free return visit within 7 days if the same problem comes back. This is RaajjePro's own promise and it is enforceable — it must not share a visual treatment with anything the provider merely claims about themselves. Suggested label: `Free callback · 7 days`.

**Add a second signal matched to the mode**, replacing the space the emergency chip used:

- `mode="instant"` → **`nextSlot`** — the next open time, e.g. `Next: today 14:00`. `Book instantly` promises immediacy; this is the evidence for it
- `mode="request"` → **`replyTime`** — the provider's typical reply time, e.g. `Usually replies in 12 min`

**Below ten completed bookings `replyTime` reads `New provider`** and nothing else — the same floor that governs every other conduct number. A provider with no data shows no number rather than a flattering blank.

Both are measured values, never labels. Nothing here may become a judgement: no `Fast responder`, no `Highly rated`, no `Top choice`.

## 2 — `Discovery.dc.html`: drop the filter, add the entry

- Remove **`Emergency available`** from the filter chip row
- Rewrite the search empty state so it no longer depends on that filter. Keep the shape — naming *which* filters conflict is the good part — using two that can genuinely collide, e.g. `Under MVR 300` and `Hulhumalé`
- Add an **emergency entry on Explore**, near the search field: a distinct action, visually separate from the category grid, that goes straight to the ASAP request. Word it so the broadcast is obvious rather than a surprise — something like `Something urgent? Get help now` with a line stating the request goes to every qualified provider nearby
- Update the sample data: `emergency` disappears; give two or three listings a `callback` guarantee, and give every listing a `nextSlot` or `replyTime` according to its mode

## Unchanged

Everything else on both files. The layout, the sort, the sponsored ordering, the island sheet, the states, the rollback behaviour, the component boundaries. This is one prop out, three in, and one entry point added.
