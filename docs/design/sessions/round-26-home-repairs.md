A category changed: **Home Repairs replaces Events** (Round 26). Events is gone from the product entirely. Home Repairs is small household jobs — partial painting, tile replacement, mounting and hanging, sealing and grouting, furniture assembly, minor carpentry. Do not treat it as a rename: Events was slow-planning work with occasion chips; Home Repairs quotes fast (2h/4h), books on a short lead, and has no occasions.

Four artboards carry the old category. Change exactly these things and nothing else:

## 1. `Home.dc.html` and `Discovery.dc.html` — the category tile

Each has a category entry:

```
{ n: 'Events', bg: '#FEFCE8', fg: '#CA8A04', d: 'M4 6h16v14H4z…' }
```

Replace with **Home Repairs**. New icon — a paint roller, or a hammer beside a tile; the calendar glyph belongs to booking surfaces, not this category. Keep or change the tint as suits the icon; twelve tiles must remain twelve.

## 2. `Create Service.dc.html` — grid entry and two tag lists

- The `CATS` entry `{ n: 'Events', … }` becomes Home Repairs, same icon decision as above.
- `TAGS['Events']` (`Weddings, Birthdays, Corporate, Décor, Sound & lights`) is deleted and replaced by:

```
'Home Repairs': ['Painting', 'Tiling', 'Mounting & hanging', 'Furniture assembly', 'Door & lock fixes', 'Sealing & grouting'],
```

- In `TAGS['Photography']`, rename the bare tag `'Events'` to `'Event coverage'` — event photography is still real work; only the retired category name has to go.

## 3. `ServiceCard.dc.html` — the category prop

The `category` enum prop options include `Events`. Replace with `Home Repairs`. Nothing else on the card changes.

## 4. `My Calendar` (in flight from the last prompt)

The brief said to cast the request-mode commitment as "Boat Charter or Events". That resolves to **Boat Charter** — a fishing trip or sunset cruise. No Events job may appear.

---

## Leave alone

- Pest Control and Appliance Repair — Round 25 stands as applied.
- Boat Charter and Photography keep their occasion presets; no occasion chips for Home Repairs anywhere, ever.
- Quote-window copy: anywhere a screen states the long window ("24 hours to quote / 72 to approve"), the category list is now **Photography, Moving and Boat Charter** — but no built artboard currently states that list, so this is a check, not an edit.
- Everything else in all four files.
