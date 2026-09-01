# Round 34 — Home stops keeping its own copy of the card

Round 33 removed the `Emergency available` badge cleanly. Removing it showed why it had survived so long: **`Home` renders service cards from its own inline markup instead of mounting `ServiceCard`.** One root cause, three defects, none of which looked wrong on screen — the badge lived on for ten rounds, Round 23's replacement signal never arrived, and `Components` drifted separately.

This round closes the cause rather than the symptom.

## 1. Both card runs mount `ServiceCard`

`Home` has two horizontal runs — **Popular near you** (`popNear`) and **Popular this week** (`popWeek`). Both render 250px-wide cards from hand-written markup. `ServiceCard`'s `horizontal` variant **is** a 250px card; they are the same component drawn twice.

Replace the inline card `<div>` inside each `<sc-for>` with:

```html
<dc-import name="ServiceCard" variant="horizontal"
  title="{{ s.title }}" provider="{{ s.prov }}" tier="{{ s.tier }}"
  rating="{{ s.rating }}" count="{{ s.count }}"
  price="{{ s.price }}" unit="{{ s.unit }}"
  island="{{ s.island }}" category="{{ s.cat }}" mode="{{ s.mode }}"
  next-slot="{{ s.nextSlot }}" reply-time="{{ s.replyTime }}" bookings="{{ s.bookings }}"
  callback="{{ s.callback }}" photo="{{ s.photo }}"
  saved="{{ s.saved }}" on-save="{{ s.onSave }}"
  hint-size="250px,330px"></dc-import>
```

**Keep the runs themselves exactly as they are** — the `hscroll` wrapper, `gap:12px`, `scroll-snap-type: x mandatory`, `scroll-snap-align: start`, the 20px side padding, the section headings and their `See all` buttons. Only the card inside the loop changes. Wrap each import in a `<div style="flex:none;scroll-snap-align:start">` if the snap behaviour needs the wrapper to work.

## 2. `mkCard` gets much smaller

`ServiceCard` already derives everything Home was computing by hand. Delete from `mkCard` and the class:

- `cBg`, `cFg`, `cD` and the `CATS` colour/icon lookup **for cards** — `ServiceCard` maps category → colour and icon itself. (Keep `CATS` if the category tiles still use it.)
- `photoCss`, `hasPhoto`, `noPhoto` and the `PHOTOS` CSS-`url()` wrapping — `ServiceCard` takes a plain path in `photo`. Pass `this.PHOTOS[s.cat] ?? ''` straight through.
- `pInit` — it computes initials itself.
- `hasBadge`, `tBg`, `tFg`, `tBd` and the `BADGE` map **for cards** — it mounts `VerificationBadge`, which owns the tier colours and copy.
- `hFill`, `hStroke` — it owns the heart.
- `instant`, `request`, `hasUnit` — it derives all three from `mode` and `unit`.

`mkCard` should come out as roughly: the row's own fields, `count`, `saved`, and `onSave`.

## 3. The data needs the fields Round 23 asked for

This is the actual defect. Home's rows carry a mode but no evidence for it, so the cards show only a `Book instantly` / `Request a time` chip and nothing else. Round 23 made that second signal the replacement for the emergency badge, and Home never got it.

**Split the rating**, since `ServiceCard` takes them separately and formats `4.8 (24)` itself: `rating: '4.8 (24)'` becomes `rating: '4.8', count: 24`.

**Then give every row its signal.** Corrected modes are in item 4 — these follow from them:

| # | Service | Category | Mode | Add |
|---|---|---|---|---|
| 1 | Home Deep Cleaning | Cleaning | instant | `nextSlot: 'tomorrow 09:00'` |
| 2 | Emergency Plumbing & Pipe Repair | Plumbing | request | `replyTime: '12 min'`, `bookings: 44`, `callback: true` |
| 3 | AC Servicing & Gas Refill | AC Repair | request | `replyTime: '25 min'`, `bookings: 20`, `callback: true` |
| 4 | Event & Wedding Photography | Photography | request | `replyTime: '2 hr'`, `bookings: 58` |
| 5 | Bridal Makeup & Styling | Beauty | instant | `nextSlot: 'today 16:00'` |
| 6 | Home Pest Treatment | Pest Control | **request** | `replyTime: ''`, `bookings: 7`, `callback: true` |
| 7 | House & Office Moving | Moving | request | `replyTime: '3 hr'`, `bookings: 21` |
| 8 | Appliance & Computer Repair | Appliance Repair | request | `replyTime: '40 min'`, `bookings: 186`, `callback: true` |

Row 6 is deliberately left under ten bookings so **`New provider`** renders on at least one card — `ServiceCard` shows it instead of a reply time below that threshold, and the state should be visible on the home feed rather than only described.

`callback` is set only on the six eligible categories (Round 28). `ServiceCard` gates it again internally, so an ineligible `true` would render nothing — but do not rely on that; the data should be right.

## 4. Three cards claim a booking mode their category does not have

Independent of the above, and worth stating plainly because it is the same failure as the emergency badge — advertising an action the product cannot perform.

§1c: **`slot` mode (shown as "Book instantly") is Cleaning, Beauty and Fitness. Nothing else.** Every other category quotes a price before booking, so it is `request`.

- **`Home` row 6** — `Home Pest Treatment`, Pest Control, `mode: 'instant'` → **`request`**
- **`Discovery`** — `Home Pest Treatment` (`g1`), Pest Control, `mode: 'instant'` with `nextSlot: 'today 14:00'` → **`request`**, replace `nextSlot` with `replyTime` and a `bookings` count
- **`Discovery`** — `Drain Cleaning & Unblocking` (`p4`), Plumbing, `mode: 'instant'` with `nextSlot: 'today 13:30'` → **`request`**, same substitution

A plumber cannot publish bookable time slots in this product. `Book instantly` on that card offers a customer something no plumbing listing can honour.

## 5. The loading skeleton mounts `SkeletonCard`

Same principle, smaller stakes. Home's loading state draws its own shimmering card shapes. `SkeletonCard.dc.html` exists and has a `horizontal` variant matching the run. Replace the hand-drawn card skeletons in the card sections with `<dc-import name="SkeletonCard" variant="horizontal" hint-size="250px,240px">`.

Leave the **category-tile** skeleton as it is — there is no component for a category tile, so that one is legitimately bespoke.

---

## Leave alone

- The emergency entry row — compact single line, small red bolt, `Something urgent? Get help now`, above the fold. It is right and it is how emergency is reached.
- The category tiles, the section headings, `See all`, the island bottom sheet with its 20-island sample and its sample-list line, the trust strip, the bottom nav.
- **Featured Providers** (`featured`) — that is a provider card, not a service card, and has no shared component. Do not fold it into `ServiceCard`.
- Home's `Appliance & Computer Repair` title. The category is `Appliance Repair`, which is correct; Round 25 broadened it to household appliances and devices, so a provider naming computers in their own service title is fine.
- Every empty and error state.
