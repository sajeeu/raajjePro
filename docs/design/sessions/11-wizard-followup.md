Two corrections to `Create Service.dc.html`. The audit found the wizard substantially correct — every mockup defect was caught, the emergency config table is exactly right, and the required-fields framing works. **Change only these two things.**

## 1. The Appliance Repair tag list says `Computer`

In `TAGS`, Appliance Repair reads:

```
'Appliance Repair': ['Washing machine', 'Refrigerator', 'Oven', 'TV', 'Computer', 'Phone'],
```

Appliance Repair **is** the category that absorbed computers, so a tag covering them is right — but the bare word `Computer` is the retired category name, and it must not appear anywhere in the product. Rename that one entry to **`Laptops & PCs`**. Leave the other five tags alone.

## 2. Tag chips and island chips are hand-rolled — import `Chip` instead

The wizard draws its own chip markup for the category tag chips (step 1) and the selected-island chips (step 2). `Chip.dc.html` is a sibling in this project and already covers both cases:

- **Tag chips on step 1** — `<dc-import name="Chip" kind="filter" selected="{{ … }}" label="{{ … }}" on-tap="{{ … }}">`
- **Selected islands on step 2** — `<dc-import name="Chip" kind="input" label="{{ … }}" on-remove="{{ … }}">`

Components are files here and every screen imports them rather than copying them — that is the whole reason they were split into their own files, and hand-drawn copies are how thirteen sessions drift into looking like thirteen products. Swap both to `<dc-import>`. If `Chip` genuinely can't express something the wizard needs, say so rather than working around it.

---

## Leave everything else exactly as it is

Listing these so they don't get "improved" in passing — all of them audited correct:

- The twelve categories, the Boat Charter replacement for Tuition, and the per-category tag suggestions
- `EMG` — Plumbing/Electrical at Gold, AC Repair/Moving at Silver, all four at a 30-minute window, read from config rather than written into copy
- The emergency lock reasons, including the no-category-chosen and category-not-eligible cases
- `N required fields left to publish` leading, `Step N of 7` secondary; the six-field `missing()` list and its per-field Fix links
- The single price field (`Price in MVR`, or `Price from`/`Price to` for a range only) — the mockup's duplicate is correctly gone
- The Range/Price-on-request → request-mode lock on step 5, with its reason shown
- Warranty and insurance as `Provider states: …` with the not-checked line, and the callback guarantee kept visually separate as the one RaajjePro enforces
- The single FAQ editor; the removed Service Packages; the removed Accepting New Customers toggle
- The placeholder island note, the offline banner and queued-sync copy, and the over-limit publish screen that keeps the draft instead of erroring
