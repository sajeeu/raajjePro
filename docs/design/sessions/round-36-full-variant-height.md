# Round 36 — the full variant's number, and one word

Round 35 fixed the horizontal card properly. It is `250 × 330`, the photo is `flex:none`, the body is `flex:1;min-height:0`, the title is clamped to two lines **and reserves both**, the price row is pinned with `margin-top:auto`, and the chip row is `nowrap` with the signal truncating. Moving the callback badge onto the photo beside `Sponsored` was the right call — it is what freed the row, and it reads better.

By arithmetic that card fits with about 7px to spare, and because every piece is reserved, a full-data card and a sparse one now produce the same internal layout rather than merely the same frame. **I could not render it to confirm** — the design tool's runtime is not in the repo and the headless browser here cannot return a screenshot — so please eyeball the horizontal pair once. Everything below is what the numbers say.

Three changes.

## 1. `full` is set to a height it does not fit in

The same round set two different heights for the same variant:

- `ServiceCard.dc.html` — `height:150px` on the full card
- `Components.dc.html` — `hint-size="100%,172px"` on the full card
- `Discovery` and `Provider Profile` — still `hint-size="100%,150px"`

Something measured 172px. Working it through agrees: inside a 150px box there are 120px of content space after the 14px padding and the border. The right column needs the header row (39px reserved title + 3px gap + ~15px provider line = ~57), the rating/island/category row (~16), the pinned price row (1px border + 9px padding + a 23px mode chip = 33), and the footer row (`min-height:25px`) — **about 131px, plus 21px of gaps, against 120px available.** It overflows by roughly 30px, and the full variant has no `overflow:hidden`, so it spills past the rounded corner instead of clipping inside it.

**Set the full variant to the height it actually needs** — take the measured value rather than mine, and then make all four agree: the `height` in `ServiceCard`, and the `hint-size` in `Components`, `Discovery` and `Provider Profile`. One variant, one number, in every place it is written down.

## 2. Both variants get `overflow:hidden`

The horizontal card already has it — that is why its 7px margin is safe. The full card does not.

Add `overflow:hidden` to the full variant's outer div. A fixed height without it means any future content change spills outside the border and looks broken; with it, the same mistake clips *inside* the card, which is recoverable and obvious. This is the guard that makes a hard-coded height a reasonable thing to have.

## 3. The `full` rating row can still wrap

`<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">` holds rating, island and category. On a 372px card the right column is about 234px wide, and `4.6 (31)` + `Th. Guraidhoo` + `PLUMBING` is close to that. If it wraps, the card gains a line and the height stability this round exists to create is gone.

Give it `flex-wrap:nowrap;min-width:0` and let the island span truncate with `overflow:hidden;text-overflow:ellipsis;white-space:nowrap`, exactly as the horizontal chip row now does. The category label is the least important of the three, so let that one drop off the end first if something has to.

## 4. The sparse demo card is called `Gardening`

The new second horizontal card in `Components` — the sparse one that makes the pair work — is titled **`Gardening`**. Round 25 retired Gardening and replaced it with Pest Control. The card's `category` is `Home Repairs`, which is correct; only the title is wrong.

`verify-dc.py` fails on it, which is why **the `Components` import is the one file being held back** — the rest of Round 35 is committed and the gate is green without it.

**Rename it.** `Tiling`, `Tile replacement` or `Wall painting` all work — short, plainly a Home Repairs job, and none of them is a retired category name. Everything else about that card is right: no tier, no callback, no photo, no reply time, a bare price. That is exactly the sparse case the pair needs.

---

## Leave alone

- The whole horizontal variant as Round 35 built it — the 330px frame, `flex:none` photo, `flex:1;min-height:0` body, two-line clamped and reserved title, `margin-top:auto` price row, `nowrap` chip row with a truncating signal
- The callback badge on the photo at bottom-right, its `Free callback` wording at that size, and the longer `Free callback · 7 days` in the full variant's footer where there is room
- `hasFoot: true` — making the footer unconditional is part of what keeps the height stable
- The `island` prop's new description documenting the atoll convention
- The `Components` pair itself and its `Same frame, any amount of data` label
- `SkeletonCard` — still out of scope. Its `100%,124px` full hint no longer matches the card and its horizontal variant may not match 330px either. Worth a look, deliberately, on its own.
