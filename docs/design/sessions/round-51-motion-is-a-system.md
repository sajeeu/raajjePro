# Round 51 — the press feedback left the motion system

Two small things, both one line each. The restyle of `Your bookings` and
`Dispatch fee` is good and stays — this round only puts its timings back on the
token scale.

**Leave alone:** every layout, colour, component and every piece of copy, and
all of Rounds 40–50. Nothing about how either screen looks or reads changes.

---

## 1. Twelve literal durations where there had been none

The new press feedback is written as:

```css
transition:transform .15s ease
```

Before that restyle, **all 61 files contained zero literal transition
durations** — every one used `--m-fast`, `--m-base`, `--m-sheet` or `--m-page`.
There are now twelve, in two files:

| File | Count |
|---|---|
| `Dispatch fee` | 9 |
| `Your bookings` | 2 (plus one `background .2s ease`) |

`.15s` is not a token value. It sits between `--m-fast` (120ms) and `--m-base`
(200ms), so it is not even a rounding of one — a reader can't tell whether it
was meant to be the fast tier or the base tier.

**Do:**

- `transition:transform .15s ease` → `transition:transform var(--m-fast)`
- On `Dispatch fee`'s submit button, `transition:transform .15s ease,background .2s ease`
  → `transition:transform var(--m-fast),background var(--m-base)`

The easing comes with the token set — `var(--e-out)` where a curve is wanted,
and bare where the default is fine, matching how the other 59 files do it. Do
not change any duration's *feel*: 120ms for a press-scale is the intent, and
`--m-fast` is that value.

The one exception the corpus already makes is infinite loops — `shimmer 1.4s`
and `spin .7s` / `.8s` keep literal durations by convention, because they are
ambient rather than responses to a tap. Leave those.

### Why this is worth a round

The motion scale is only a scale while everything is on it. One screen at
`.15s` is invisible; the second screen copies the first, and by the fifth nobody
knows which value is canonical. The corpus went from zero to twelve in a single
import, which is exactly how that starts.

---

## 2. `Messages` is the last screen duplicating BottomNav's routes

`Profile`, `Discovery` and `My Bookings` have all dropped `on-tap` — `BottomNav`
navigates itself via its own `t.h`, so a screen-level route map is a second copy
of something the component already owns. `Messages` still has one, mounted four
times:

```html
<dc-import name="BottomNav" active="Messages" on-tap="{{ navTap }}" …>
```

```js
navTap: (t) => { const m = { Home: 'Home.dc.html', Explore: 'Discovery.dc.html',
  Bookings: 'My%20Bookings.dc.html' }; if (m[t]) window.location = m[t]; },
```

Its map is also one entry short — no `Profile` — so that tab currently falls
through to `BottomNav`'s own routing while the other three go via the copy.
Two mechanisms, one of them incomplete, for one behaviour.

**Do:** drop `on-tap="{{ navTap }}"` from all four mounts and delete `navTap`.
Nothing else. The nav keeps working because the component was always the thing
doing the work.

---

## 3. What must not change

- **Every visual change in the restyle.** The press-scale values (`.94`, `.95`,
  `.985`, `.98`), the 64px min-width on the copy buttons, `Not now` at a 44px
  target, the horizontally scrolling filter row and its fourth skeleton chip.
  All of it is right; only the durations move.
- **`Dispatch fee`'s copy, all of it.** It is the most rule-dense screen in the
  prototype and it gets every rule right — MVR 200 owed to RaajjePro and not to
  a provider, the hold lifting on submission rather than on admin confirmation,
  existing bookings and the account untouched, and the one honest explanation of
  why this payment *is* admin-checked when payments to providers never are.
- **`shimmer` and `spin`** keep their literal durations.
- Everything in Rounds 40–50.

---

## Checklist

- [ ] No file contains a literal duration in a `transition:` declaration
- [ ] `shimmer` and `spin` still read `1.4s` and `.7s` / `.8s`
- [ ] The press feedback still looks and feels the same
- [ ] `Messages` mounts `BottomNav` without `on-tap`, and `navTap` is gone
- [ ] Every bottom-nav tab still navigates from `Messages`
- [ ] Nothing from Rounds 40–50 changed
