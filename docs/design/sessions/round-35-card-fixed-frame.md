# Round 35 — the card is a fixed frame

Round 34 landed correctly: both of `Home`'s runs mount `ServiceCard`, `mkCard` is down to three lines, every row carries its mode-appropriate signal, `SkeletonCard` is in the loading state, and the three cards claiming the wrong booking mode are fixed.

It also made a latent problem visible. **`ServiceCard` has no fixed height, so cards with more data are taller than cards with less** — and in a horizontal scroll run, ragged card bottoms read as breakage rather than as variation.

This is not a Round 34 regression. Home's old hand-written cards had the same flaw and it was hidden because their data was uniform: no signal, no callback badge, on any card. Giving the cards real data exposed it.

**The rule: the frame is constant, the content flexes inside it. Never the reverse.**

## Where the height actually varies

Four independent causes, all in `ServiceCard`:

1. **The outer card has no `height`.** It grows to fit whatever is inside.
2. **The title has no line clamp.** `Home Deep Cleaning` is one line, `Emergency Plumbing & Pipe Repair` is two. That alone is a ~20px difference, and it pushes every row below it down.
3. **The chip row is `flex-wrap:wrap` with three possible children.** At 250px minus 28px padding there are 222px to work with — a `Request a time` chip plus `Usually replies in 12 min` plus the callback badge wraps to two or three lines, while a slot card with a short `Next:` wraps to one. This is the largest source of variation.
4. **Nothing pins the footer.** The price row and chips sit wherever the content above leaves them, so they land at a different height on every card.

## 1. `horizontal` — fixed 250 × 330

**Outer:** add `height:330px;display:flex;flex-direction:column` to the existing `width:250px…` div. The card already declares `hint-size="250px,330px"` everywhere it is mounted, so this makes a claim that is currently false into a fact.

**Photo block:** add `flex:none` to the `height:126px` div.

**Body:** add `flex:1;min-height:0` to the `padding:13px 14px 14px;…gap:9px` div.

**Title — clamp to two lines, and reserve two lines even when it only needs one:**

```
display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;
min-height:39px
```

39px is two lines at 15px × 1.3. Reserving it matters as much as clamping: without the `min-height`, a one-line title lifts the provider and rating rows and they stop aligning across neighbouring cards.

**Move the callback badge onto the photo.** This is what frees the chip row. The photo already hosts three overlays — `Sponsored` top-left, the heart top-right, the category chip bottom-left. **Bottom-right is empty; put the callback badge there**, styled like the others: `rgba(255,255,255,.95)` pill, green text and shield icon, `padding:4px 10px`, `font-size:10.5px;font-weight:800`. Shorten the label to **`Free callback`** at this size — the `· 7 days` detail is on the listing page and does not survive a photo overlay legibly.

It is also the more honest placement. The callback guarantee is RaajjePro's, not the provider's, and sitting alongside `Sponsored` — the other platform-level marker — says so better than sitting in a row of provider facts.

**Footer — pin it and stop it wrapping.** The price row (`border-top:1px solid #EEF3FA;padding-top:10px`) gets `margin-top:auto`. The chip row loses `flex-wrap:wrap` and becomes `flex-wrap:nowrap;min-width:0`, with the signal span given `overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0` so a long reply time truncates instead of wrapping. With the callback badge gone the row is exactly two children and will not need to.

Result: every card is 330px, titles occupy the same block, and the price line sits at the same height on all of them.

## 2. `full` — fixed height, same treatment

**Outer:** add `height:150px` to the `background:#fff;border:1px solid #E9EFF7;border-radius:20px;padding:14px;display:flex;gap:13px…` div.

**Title:** same two-line clamp and `min-height:39px`.

The footer already has `margin-top:auto`, and at full width the signal and callback badge sit on one line with a spacer between them, so **the callback badge stays where it is in this variant.** Do not move it onto the 96px thumbnail — there is no room.

Check the `hasFoot` case: `hasSignal` is true for every card that has a mode, so the footer row is effectively always present. If it can ever be absent, give the row a `min-height` rather than letting the card shrink.

## 3. One component, one declared height

`full` is currently mounted at **two different heights**: `hint-size="100%,124px"` in `Components`, and `hint-size="100%,150px"` in `Discovery` and `Provider Profile`. The component sheet documents the card as shorter than every screen that uses it.

**Set `Components`' full-variant mount to `hint-size="100%,150px"`** so all four agree, and keep `250px,330px` for horizontal.

## 4. Show it working

In `Components`, the two `ServiceCard` examples currently differ in nearly every input, which is exactly the wrong demonstration for this change. Add a **third horizontal card next to the existing one** with deliberately minimal data — no tier, no callback, no photo, a one-word title, a short price — so the sheet shows a full card and a sparse card **side by side at identical height**. Label the pair `Same frame, any amount of data`.

That pair is the regression test. If a later change breaks height stability, it will be visible on the component sheet before it reaches a screen.

---

## Leave alone

- Everything Round 34 did — the `ServiceCard` mounts in both of Home's runs, the trimmed `mkCard`, the signal data, `SkeletonCard`, the corrected booking modes
- The photo height (126px horizontal, 96px full), the border radius, the shadow, the palette, every font size
- `Sponsored`, the heart and the category chip — their positions and styling do not change
- The `full` variant's layout: 96px thumbnail left, content right, price and mode chip on the footer line
- Card **width** — 250px horizontal, full-width for `full`. Only height and internal layout change.
- `SkeletonCard`'s own dimensions. If its horizontal variant no longer matches a 330px card, say so and leave it — that is a separate change and it should be made deliberately, not folded in here.
