# Round 37 — `SkeletonCard` catches up with the card, but not in one size

`ServiceCard` is now a fixed frame: **250 × 330** horizontal, **100% × 188** full. `SkeletonCard` was deliberately left out of Rounds 35 and 36 and is still on the old geometry, so the loading state is materially shorter than the thing it stands in for:

| | Skeleton renders | Real card | Short by |
|---|---|---|---|
| horizontal | ~250px | 330px | **80px** |
| full | ~126px | 188px | **62px** |

A skeleton exists so that **nothing moves when the data arrives.** At 80px short it guarantees the opposite — the page settles downward as each card loads, which is the specific jolt the shimmer was supposed to prevent.

## First, the thing that makes this not a resize

**`variant="full"` is doing two different jobs**, and one height cannot serve both. Of its 29 mounts:

- **5 stand in for a real `ServiceCard`** — `Discovery` ×2, `Provider Profile` ×2, `Components` ×1. These must become 188px.
- **24 stand in for something else entirely** — `Analytics`, `Availability`, `Booking Request`, `Invoices`, `Mark Complete`, `My Bookings`, `My Calendar`, `My Performance`, `My Services`, `Payment Received`, `Propose Time and Price`. **None of those screens mounts a `ServiceCard` at all.** They are using it as a generic card-shaped shimmer for booking rows, invoice rows, metric tiles and availability rows.

Making all 29 into 188px would fix five loading states and damage twenty-four. So:

## 1. Three variants, each named for what it mirrors

- **`horizontal`** — mirrors `ServiceCard variant="horizontal"`. Fixed **250 × 330**.
- **`full`** — mirrors `ServiceCard variant="full"`. Fixed **100% × 188**.
- **`row`** — a generic card-shaped list row. **This is exactly what `full` renders today** — keep its markup as it is, unchanged, under the new name.

`horizontal` and `full` carry a hard height because each mirrors one known component. **`row` stays deliberately unsized** — it stands in for a dozen different real rows, so a fixed height would be wrong for most of them. Say that in a comment so nobody "fixes" it later.

## 2. `horizontal` — mirror the card's rows, not just its height

Height alone is not enough. The bars have to sit where the real rows will sit, or the content still jumps sideways and vertically inside a card of the right size.

```
outer   width:250px; height:330px; display:flex; flex-direction:column; overflow:hidden
        (keep the existing border, radius, shadow, and aria-hidden)
photo   flex:none; height:126px                                    ← matches the card
body    flex:1; min-height:0; padding:13px 14px 14px;
        display:flex; flex-direction:column; gap:9px               ← card gap is 9, not 10
```

Then, in order, mirroring the card row for row:

1. **Title block** — `height:39px`, two 15px bars with `justify-content:space-between` (100% and ~68% width). 39px is the card's reserved two-line title; the 9px between the bars falls out of it exactly.
2. **Provider row** — `gap:7px`: a **22px circle** then a 12px bar ~45% wide. The circle matters — it is the avatar, and it is the widest thing in that row.
3. **Rating row** — `gap:5px`: a 12px bar ~54px, a `flex:1` spacer, a 12px bar ~70px. Rating left, island right, as on the card.
4. **Price row** — `border-top:1px solid #EEF3FA; padding-top:10px; margin-top:auto`, holding a 19px bar ~96px wide. **The `margin-top:auto` is the important part** — it pins the footer exactly where the card pins it.
5. **Chip row** — `gap:6px`: a 25px pill ~112px (radius 9) and a 25px pill ~92px. Mode chip and signal.

That comes to about 317px of the 328px available, so it fits with roughly the same slack the real card has.

## 3. `full` — same treatment at 188px

```
outer   height:188px; overflow:hidden; padding:14px; display:flex; gap:14px
thumb   width:96px; flex:none; align-self:stretch; min-height:112px; border-radius:14px
right   flex:1; display:flex; flex-direction:column; gap:7px; min-width:0
```

- **Header row** — `align-items:flex-start; gap:8px`. Left, a `flex:1` column: the same 39px two-bar title block, then a 3px gap, then a 12px provider bar ~40% wide. Right, a **28px circle** for the heart.
- **Rating row** — three 12px bars (~54px, ~78px, ~62px), `flex-wrap:nowrap`.
- **Price footer** — `border-top:1px solid #EEF3FA; margin-top:auto; padding-top:9px`, with an 18px bar ~84px, a spacer, and a 23px pill ~104px.
- **Foot row** — `min-height:25px`: a 12px bar ~120px, a spacer, a 21px pill ~96px.

**Drop `justify-content:center` from the right column.** That is what currently centres three bars in the middle of the card, while the real card is top-aligned with a pinned footer. Centring is why the shimmer and the content do not line up even when the heights match.

## 4. Update every mount — this is part of the change, not a follow-up

Rounds 35 and 36 both went wrong by taking a number from a stale `hint-size`. The hints are assertions about runtime and they move with the component:

- **3 `horizontal` mounts** — `Home` ×2, `Components` ×1 → `hint-size="250px,330px"`
- **5 `full` mounts** — `Discovery` ×2, `Provider Profile` ×2, `Components` ×1 → `hint-size="100%,188px"`
- **24 mounts become `variant="row"`**, keeping `hint-size="100%,124px"` — `Analytics` 3, `Availability` 2, `Booking Request` 2, `Invoices` 3, `Mark Complete` 1, `My Bookings` 3, `My Calendar` 2, `My Performance` 3, `My Services` 3, `Payment Received` 1, `Propose Time and Price` 1

Also raise `$preview` height from `280` to about `380` so the 330px horizontal variant is fully visible in the editor.

## 5. In `Components`, put the skeleton beside the card it mirrors

The Skeleton section currently shows the two shimmers on their own, where being the wrong height is invisible. Move them so **the horizontal skeleton sits directly next to the horizontal `ServiceCard`, and the full skeleton directly above or below the full card** — same row, same width.

Label the pairing `Skeleton matches the card it stands in for`. Add the `row` variant separately underneath, labelled as the generic list row, so the distinction is documented where people look it up.

Like the `Same frame, any amount of data` pair from Round 35, this is the regression test: if the card's height changes again and the skeleton does not follow, the component sheet shows it immediately.

---

## Leave alone

- The shimmer itself — the gradient, `background-size:200% 100%`, the 1.4s linear timing, the `#E8EEF6`/`#F4F8FC` colours. Only geometry changes.
- `aria-hidden="true"` on both variants. A shimmer is decoration and must stay out of the accessibility tree.
- The `row` variant's internals, once renamed — three bars, centred, 96px thumbnail, no fixed height. It is correct for what it does.
- Every screen's loading *layout* — how many skeletons, where they sit, the section headings around them. Only the variant name and `hint-size` change on those 24 mounts.
- `ServiceCard`. It is settled; nothing in this round touches it.
- The bespoke skeletons that are not `SkeletonCard` — `Home`'s category-tile shimmer, `Provider Profile`'s avatar-and-header block, `Booking Request`'s summary block. Those mirror layouts that have no shared component, and they are legitimately hand-drawn.

## Optional, and only if it is quick

The shimmer gradient is written out inline seven times in this file, which is how the shapes drift apart. A single `.sh` class in the existing `<style>` block would fix that. **Not required** — if it complicates the diff, leave it and say so.
