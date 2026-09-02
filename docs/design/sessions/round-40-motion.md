# Round 40 — motion: make it move like one app

The app reads as rigid, and I checked why rather than guessing. **The problem is not that motion is missing — it is that motion only ever plays in one direction, and its vocabulary has drifted.**

What is already there and works: **53 border-colour, 42 background, 16 box-shadow and 9 transform transitions**, so buttons and cards respond to hover and press. Ten keyframes exist — `fadeUp`, `fadeIn`, `sheetUp`, `screenIn`, `shimmer`, `spin`, `toastIn` and three one-offs.

Five specific gaps, in the order they are felt.

## 1. Nothing animates out — every sheet snaps shut

**16 files animate a sheet or overlay in. Zero animate one out.** They are gated by `sc-if`, so the moment the flag flips the node is gone — no fade, no slide, nothing. Opening feels considered; closing feels like the screen broke. This is the single biggest source of the rigidity.

It needs a **closing state**, because a conditional render cannot animate its own removal:

```js
close() {
  this.setState({ closing: true });
  this._ct = setTimeout(() => this.setState({ sheet: false, closing: false }), 200);
}
```

The sheet stays mounted for the exit, runs the reverse animation, then unmounts. Clear `this._ct` in `componentWillUnmount` — several of these screens already clear timers that way.

**Exits run faster than entries** — about two-thirds. An entrance can afford to be gracious; an exit that lingers feels like lag. Sheet in at 300ms, out at 200ms.

Apply to every sheet, overlay, dialog and toast: the island pickers, the role switcher on `Profile`, the appeal sheet on `My Performance`, the accept/decline sheets on `Booking Request`, the rating sheet on `Booking Detail`, and the rest.

## 2. Page-to-page is a hard cut

The app is 61 separate documents navigated with `location.href`, so every tap between screens is a full document load — a white flash, then the new page. No amount of in-page animation fixes that.

**Use cross-document view transitions.** In the shared stylesheet:

```css
@view-transition { navigation: auto; }
```

Same-origin navigations then cross-fade instead of flashing, with no per-link work. Support is uneven across browsers — where it is unsupported nothing breaks, you simply get today's behaviour. **Tell me which browser you tested and whether it took effect**, the same way I asked about `localStorage`.

Two things that help regardless, and cost nothing:
- Every screen already paints `#DEE7F3` outside the frame and `#F2F6FB` inside. Keep that identical on all 61 so the flash between loads is the same colour rather than white.
- Most screens already fade their content in on load. Make that universal and consistent — one entry, one duration.

## 3. State changes inside a screen just jump

Transitions cover colour and border, but almost nothing covers **layout or content**. Filtering `Discovery`, switching a tab on `My Bookings`, a status pill changing, a metric updating on `My Performance`, a step advancing in the wizard — all of it swaps instantly.

Give in-place changes a short, quiet transition: content that replaces content fades and rises ~6px over **200ms**; a list that reflows animates its items with a small stagger (**30ms** apart, capped at about six items so a long list does not ripple). Numbers that change should not animate their digits — a brief highlight of the surrounding element is enough and stays readable.

## 4. One vocabulary, not five durations and two curves

The current values drifted because the keyframes are copy-pasted into 39 separate `<style>` blocks:

- **Entry durations in use: .2s, .25s, .3s, .35s, .4s** — five speeds for one idea
- **Two near-identical easing curves**, `cubic-bezier(.2,.8,.3,1)` and `cubic-bezier(.2,.9,.3,1)`, in **12 files each**. A perfectly even split with no distinction in meaning — that is drift, not intent.

Settle on one scale and use nothing else:

| Token | Value | For |
|---|---|---|
| `--m-fast` | **120ms** | hover, press, colour, border — anything the finger is already touching |
| `--m-base` | **200ms** | in-place state change, content swap, list reflow, sheet **out** |
| `--m-sheet` | **300ms** | sheets, overlays, dialogs coming **in** |
| `--m-page` | **350ms** | page and view transitions |
| `--e-out` | `cubic-bezier(.2,.8,.3,1)` | anything entering or settling — **keep this one, drop `.2,.9,.3,1`** |
| `--e-in` | `cubic-bezier(.4,0,1,1)` | anything leaving |
| `linear` | — | loops only: `shimmer`, `spin`. Never for a one-shot. |

## 5. `prefers-reduced-motion` is honoured in none of the 61 files

This matters more the moment there is more motion. For some people this is nausea, not preference.

Put one block in the shared stylesheet:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: .01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: .01ms !important;
  }
  @view-transition { navigation: none; }
}
```

Everything still *works* — states change, sheets open and close — they simply arrive instantly. **Do not make the shimmer skeletons disappear under reduced motion**; keep them as static placeholder blocks so the loading state is still legible.

## 6. Put the motion in one file

Ten keyframes copy-pasted across 39 `<style>` blocks is why the durations drifted, and it will drift again. Add a sibling **`motion.css`** holding the keyframes, the tokens above, the `@view-transition` rule and the reduced-motion block, referenced from each screen's `<helmet>` exactly as `session.js` and `image-slot.js` already are. Remove the per-file copies of those keyframes.

The seven components carry their own motion the same way and should read from the same file.

---

## Where motion must stay out of the way

- **Emergency.** `Emergency Flow`, `Provider Emergency` and the dispatch-fee screens belong to someone with a burst pipe. Nothing there may delay an action or animate a countdown's digits. The 90-second collection window and the 30-minute response clock must read instantly at a glance.
- **Never gate an action behind an animation.** A tap does its thing immediately; motion describes what happened, it does not schedule it.
- **Nothing loops except loaders.** `shimmer`, `spin` and the emergency `pulseRing` are the only things that may repeat. No breathing buttons, no drifting backgrounds.
- **No motion on the error and empty states' content.** They already carry a fade-in; do not add anything that makes a failure feel decorative.
- **Do not animate a number changing into another number.** Prices, counts and conduct metrics must never be mid-tween while someone reads them.

## Leave alone

- Every layout, colour, copy string and component — this round changes timing and transition only
- `shimmer` at 1.4s linear and `spin` at .8s linear; both are correct
- The card frames, the island pickers, the seed, the navigation and the session from Rounds 35–39
- The existing hover and press treatments — they work; they only need the shared duration token
