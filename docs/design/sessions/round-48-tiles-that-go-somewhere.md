# Round 48 — the tiles that all go to the same place

The Profile redesign is a real improvement and it stays. The hero, the wave
band, the circular avatar and the tile grid are all kept. What this round fixes
is where the tiles point, what they are called and which two of them are not
bookings at all.

**Leave alone:** every layout, colour and animation not named below, and all of
Rounds 40–47. Nothing in this round changes the shape of the Profile screen.
One tile is removed, one is renamed, two move out of the grid, two colours swap
and one control gets a handler.

---

## Why

Six tiles sit under a heading that says **My bookings**. Four of them go to
`My Bookings.dc.html` with no parameter at all, so whichever one is tapped the
screen opens on its default `All` tab. Four labels, one destination.

That is the same defect Round 45 §5a fixed on `View my bookings`, and the
pattern for the fix is already in the file: the **Saved** tile deep-links with
`?screen=Saved`, and `Discovery` reads it with `URLSearchParams`. `My Bookings`
has the tabs — it just does not read the URL.

---

## 1. `My Bookings` — read the tab from the URL

**Screen: `My Bookings`.**

It currently holds the active filter in local state only:

```js
state = { filter: 'All' };
…
filters: ['All','Upcoming','Active','Completed'].map(…)
```

**Do:** initialise `filter` from a `tab` query parameter, validated against that
same list so an unknown value cannot produce an empty screen. `Discovery` is the
model — copy its shape rather than inventing a second one:

```js
state = { filter: (t => ['All','Upcoming','Active','Completed'].includes(t) ? t : 'All')
  (new URLSearchParams(window.location.search).get('tab')) };
```

Derive the list from one place if you can. Two copies of the tab names in one
file is how `Notifications`' *Mark all read* went wrong in Round 43.

Nothing else about the screen changes — the tab row, the rows, the fee banner
and the empty states are all correct and stay.

---

## 2. `Profile` — the booking tiles reach the tab they name

Four tabs exist: **All · Upcoming · Active · Completed**. There is no `Waiting`
tab and no `Cancelled` tab. So the grid names two views the app does not have.

**Do:** make the grid mirror the tabs exactly — four tiles, each deep-linking:

| Tile | Href |
|---|---|
| **All** | `./My%20Bookings.dc.html?tab=All` |
| **Upcoming** | `./My%20Bookings.dc.html?tab=Upcoming` |
| **Active** | `./My%20Bookings.dc.html?tab=Active` |
| **Completed** | `./My%20Bookings.dc.html?tab=Completed` |

- **`Waiting` becomes `Active`.** The tab is called Active, and its bookings are
  the ones needing something now. "Waiting" also collides with StatusPill's
  `waiting_provider` label, which is a specific booking status and not this.
- **`Cancelled` is removed** — there is no tab behind it. See §6.
- **`All` takes its place** so the grid keeps a full row.

Four tiles in a `repeat(3,1fr)` grid leaves an orphan, so make it
`repeat(2,1fr)` — a 2×2 block. That also gives each label room to grow, which
the 200% text-scale rule in the style guide needs and a four-across row would
not survive.

---

## 3. The tile colours contradict `StatusPill`

`StatusPill` owns the colour of every booking state, and two of the tiles
disagree with it:

| | `StatusPill` | The tile | |
|---|---|---|---|
| Completed | `completed` → **blue** | green | **swap** |
| Upcoming | its bookings are `confirmed` → **green** | blue | **swap** |
| Active | holds `awaiting_payment` → amber | amber | correct |

**Do:** swap those two. `Completed` takes blue `#2563EB` on `#E8F0FE`;
`Upcoming` takes green `#16A34A` on `#E5F6EC`. `Active` keeps amber
`#D97706` on `#FEF3DC`. `All` takes the system grey — `#8296B3` on `#EEF3FA` —
because it is not a state at all.

This matters because a customer sees the tile and then the pill on the very next
screen. When Completed is green in one place and blue in the other, the colour
stops carrying meaning.

---

## 4. `Saved` and `Support` are not bookings

They sit inside a card headed **My bookings**, and both use a colour that
already means something else in this system:

- **Saved** is `#DB2777` on `#FDF2F8` — that is **Beauty**'s category accent, exactly.
- **Support** is `#7C3AED` on `#F3EFFE` — `#7C3AED` is **Fitness**'s accent, and
  `#F3EFFE` is a new tint that appears nowhere else (Fitness's is `#F5F3FF`).

The style guide reserves those twelve colours for category identity. Borrowing
two of them for a shortcut is Round 45 §2's lightning bolt again: one signal,
two unrelated meanings.

**Do:** move both out of the grid and back into the rows below it, where they
were before the redesign and where the blue `#E8F0FE` circle treatment applies
to every row alike. Final row order for a customer:

1. **Saved** → `./Discovery.dc.html?screen=Saved`
2. **Saved preferences** → `./Saved%20Preferences.dc.html`
3. **Account settings** → `./Account%20Settings.dc.html`
4. **Help & support** → `./Help%20Support.dc.html`
5. **Legal** → `./Legal.dc.html`

A provider still gets **Verification** prepended, exactly as it is now.

Keep the heart and question-mark glyphs — only the colour and the placement
change. And keep the rows subtitle-free, the way the redesign has them.

---

## 5. `Change photo` looks tappable and is not

```html
<span aria-label="Change photo" style="…width:30px;height:30px…">
```

It is a `<span>` with no handler, so it does nothing, and at 30px it is under
the 48dp minimum the style guide sets. It also carries an `aria-label`, which
announces a control to a screen reader that is not one.

**Do:** make it a real `<button>` with a working handler and a target of at
least 48dp. `Become a Provider` already has this exact control — a hidden file
input and `pickPhoto: () => this.fileRef.current && this.fileRef.current.click()`
— so reuse that rather than writing a second version. The button may stay
visually 30px if it carries padding that brings the hit area to 48dp.

---

## 6. Not an instruction — should `Cancelled` exist?

§2 removes the Cancelled tile because nothing is behind it. Whether a customer
should be able to see cancelled bookings at all is a product question, not a
design correction, so it is flagged rather than answered.

If the answer is yes it is a `My Bookings` change first — a fifth tab and a
`group:'Cancelled'` row in the seed — and the tile comes back afterwards. Do not
add either in this round.

---

## 7. `Provider Emergency` — the footer shows too early

Left over from Round 46. The footer gate became:

```html
<sc-if value="{{ acceptOn }}" hint-placeholder-val="{{ true }}">
```

It was `reqOn`. So during the 750ms boot skeleton the **Send offer** and
**Decline this request** buttons now render under a body that is still
shimmering placeholders.

**Do:** gate on both — the buttons should appear only once the request has
loaded *and* the provider is online. Add an `acceptReady` value that is
`reqOn && acceptOn` and use it in the footer, leaving the body's `acceptOn`
block exactly as it is.

---

## 8. What must not change

- **The Profile hero.** Header bar, back link, 108px circular avatar and its
  ring, name, `Malé, Maldives · Member since Jan 2026`, and the wave band.
- **Aishath Naeema.** The redesign corrected the name and it is now right.
- **`BottomNav` without `on-tap`.** The component owns its own routes and
  navigates itself; the screen should not carry a second route map. This is
  correct now — `Messages`, `Discovery` and `My Bookings` are the ones still
  duplicating it, and they are not in this round.
- **The role-switcher sheet**, its copy and the `Become a Provider` link.
- **The error state**, its `EmptyState` mount and its working retry.
- **The loading skeleton's shape** — only the tile count follows §2, from six to
  four.
- Everything in Rounds 40–47.

---

## Checklist

- [ ] `My Bookings` reads `?tab=` and validates it against its own filter list
- [ ] The four booking tiles are All · Upcoming · Active · Completed, each deep-linked
- [ ] Tapping each one opens `My Bookings` on that tab — checked by tapping, not by reading
- [ ] `Completed` is blue and `Upcoming` is green, matching `StatusPill`
- [ ] The grid is 2×2 and no tile label clips at 200% text scale
- [ ] No screen uses `#DB2777` or `#7C3AED` for anything but Beauty and Fitness
- [ ] `#F3EFFE` appears nowhere
- [ ] `Saved` and `Help & support` are rows, not tiles
- [ ] `Change photo` is a button with a handler and a 48dp target
- [ ] `Provider Emergency`'s footer stays hidden during the boot skeleton
- [ ] Nothing from Rounds 40–47 changed
