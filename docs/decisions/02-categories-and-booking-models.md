# Decision 02 — Category changes and booking models

**Status: adopted as Round 25 (2026-08-26)** — Appliance Repair as the label · Pest Control on the 2h/4h window · `occasion` ships in v1. Plan amended at revision 5.11, with CLAUDE.md and the designer brief brought along. The prototype corrections (Home, Discovery, ServiceCard) ride the Round 25 design prompt.

---

## The finding that reframes most of this

**The structure being asked for already exists, and most of the perceived gap is a labelling gap, not a missing system.**

The platform is already Category → Provider → **Listing** → Booking, and a Listing *is* "the provider's specific offering": its own title, description, pricing model (`fixed`/`hourly`/`daily`/`range`/`quote`), price unit (`job`/`hour`/`day`/`session`/`visit`), photos, and booking mode. A boat charter operator can publish **"Fishing Trip"**, **"Sandbank Trip"** and **"Sunset Cruise" as three listings today** — each with its own price and duration in the description — with zero new machinery. A photographer can publish "Wedding Photography" and "Family Photoshoots" as separate listings the same way.

And the booking record already reads the **listing title**, not the category. Every prototype shows "Home Deep Cleaning · Tue 25 Aug" — a listing title. "26 August — Boat Charter" only happens when a provider titles their listing "Boat Charter". So the history problem (❌ *Boat Charter — 26 Aug* → ✅ *Fishing Trip — 26 Aug*) is solved by **provider behaviour plus wizard guidance**, not schema.

What does *not* exist, and is explicitly decided:

- **Packages as tiers within one listing were cut in Round 16** ("Service packages (tiered options) are deferred to post-v1"). Tiered pricing multiplies through slots, quotes, `agreedAmount`, price adherence and the booking record. The deferral stands — but note it only blocks *tiers inside a listing*. One-listing-per-package is allowed, is exactly Option C, and is also how the free-cap monetisation works (quantity of listings is the thing the subscription gates).
- **Programs/enrollment (Model 5) does not exist** and is real new scope: an enrollment entity, sessions-remaining tracking, and a completion definition that spans weeks. The closest existing machinery is `RecurringSeries` (slot listings, weekly, each occurrence individually accepted, three misses pause it).

## 1–2. The twelve categories: two changes, ten unchanged

### Computer → **Appliance Repair** (rename and broaden — recommended)

Absorb computer/device work rather than stranding it: seed the description as *"Washing machines, refrigerators, ovens, TVs, air-con units out of scope (see AC Repair), computers and phones"* — the tile label stays short. Keep everything Computer carries: request mode, the fast 2h/4h quote window (right for a broken fridge, exactly as it was for a dead laptop), 120-minute lead time, not emergency-capable. Round 20's slot-vs-request reasoning (diagnostics vs parts repair) transfers word for word.

Runner-up name: "Appliance & Device Repair" — more precise, but long for a 3-column grid tile; put the device scope in the description instead.

### Gardening → **Pest Control** (recommended)

Of the suggested directions, everything else on the list already exists as a category (Cleaning, Moving, Plumbing, Electrical, AC) or is taken by the rename above. That leaves **Pest Control** and **Handyman**:

- **Pest Control** is a distinct trade with real, recurring Malé demand (cockroaches, bedbugs, termites, rodents), zero overlap with the other eleven, and a natural request-with-quote shape — you describe or photograph the infestation, the provider quotes. Recommended config: request mode, **2h/4h quote window** (an infestation is closer to a blocked drain than to a wedding), 180-minute lead time, not emergency-capable.
- **Handyman** is the wrong kind of broad: it overlaps Plumbing, Electrical and AC Repair, which muddies search, category stats, and — worse — the emergency-tier logic, because "handyman" jobs that are really electrical would flow around the GOLD gate. Rejected.

Both changes are **data, not schema** — Phase 4 seeds categories via API ("a 13th category added via API appears in Explore with no rebuild") and Phase 10b edits them. The cost is textual: the plan's twelve-list, invariant 13's window groups, the lead-time table, two Round notes, CLAUDE.md, the designer brief, and redrawing the two category grids (Explore, wizard step 1). Neither category is emergency-capable, so the emergency configuration is untouched.

## 3–5. Boat Charter, Photography, Events — Option B + Option C, no new booking model

All three are already request mode, which is Model 6 — and request mode already has the right bones: the customer proposes a window and describes the job, the provider quotes a concrete time and price. Two additive moves cover Models 2/3/4:

**Option C via listings (build nothing).** Wizard guidance for these categories nudges providers to publish one listing per offering — "Fishing Trip", not "Boat Charter"; "Wedding Photography", not "Photography". This gives per-offering price, duration, photos and comparability now, and the booking history reads right automatically.

**Option B as a small additive field: `occasion` chips on the request form** — recommended as the one real build item. For Photography, Events and Boat Charter, the request flow's quick-pick row (Round 7 already put "trip type" chips there) becomes a seeded per-category chip set (Wedding · Birthday · Corporate · … / Fishing · Sandbank · Sunset cruise · …, always with Other), stored on the booking and rendered as the record's subtitle: **"Wedding — 26 Aug"** even when the listing title is generic. One nullable field on Booking, seeded chips per category, no state-machine change, and every downstream surface (My Bookings, Booking Detail, threads) already renders a subtitle line.

Option A (a first-class activity/package entity with its own dates, capacity and add-ons) is Round 16's deferred package system wearing a boat costume — same verdict, post-v1.

## 5. Fitness — sessions now, programs post-v1

Fitness is slot mode, and 1-on-1 PT sessions fit it exactly. The multi-week ask is already half-built: **RecurringSeries** gives "same Tuesday every week," each session individually accepted, misses handled. What it doesn't give is enrollment — "12 sessions, MVR X for the block" — which needs sessions-remaining tracking and a block price interacting with price adherence and attestation. That's a post-v1 module alongside packages; slot in additively when packages return. In v1, a trainer expresses a program as a `fixed`+`session` listing plus a series, and the block-of-sessions price is a per-listing description fact.

## 6. All twelve, reviewed

| Category | Mode today | Verdict |
|---|---|---|
| Cleaning | slot | **Unchanged.** "Deep cleaning package" = a listing, today. |
| Plumbing | request + emergency | **Unchanged.** |
| Electrical | request + emergency | **Unchanged.** |
| AC Repair | request + emergency | **Unchanged.** "AC servicing package" = a listing. |
| Beauty | slot | **Unchanged.** Pure appointment. |
| Photography | request | Mode unchanged + occasion chips + package-listings guidance. |
| Gardening | request | **Replaced → Pest Control** (request, 2h/4h, lead 180). |
| Computer | request | **Renamed → Appliance Repair**, scope broadened, config kept. |
| Moving | request + emergency | **Unchanged.** Big jobs are already quote-shaped. |
| Fitness | slot | Unchanged + series; **programs post-v1**. |
| Events | request | Mode unchanged + occasion chips. |
| Boat Charter | request | Mode unchanged + trip-type chips + package-listings guidance. |

No category changes booking mode. The six "models" collapse onto what exists: 1 = slot · 6 = request · 2/3 = request + occasion · 4 = listing-per-package (tiers post-v1) · 5 = post-v1.

## 7. Discovery UX

Almost nothing. The grid gets two new tiles (redraw, as when Tuition→Boat Charter). Cards already carry the mode-appropriate second signal (next open time / median response time) and already lead with the **listing title**, which after the package-listings guidance does the differentiation work by itself. The one candidate addition — occasion chips as a filter inside Photography/Events/Boat Charter category results — is worth considering only after the field exists and providers have data; don't build a filter over an empty column.

## 8. Technical shape

One booking machine, exactly as today. The recommendation is precisely **not** to add booking systems: keep slot/request/emergency as the only modes, and express variety through the two levers that already exist (listing granularity, per-category seed data) plus one new nullable field:

1. **Category data changes** — rename/replace two rows in the Phase 4 seed and the plan text.
2. **`occasion` on Booking** — nullable string from a seeded per-category chip list, request mode only, shown as the record subtitle. Additive; nothing existing changes shape.
3. **Wizard step-1 guidance** for the three activity categories — copy, not code.
4. **Post-v1, unchanged from Round 16**: packages/tiers, and programs/enrollment layered on the same machinery.

---

## What adopting this requires (Round 25 checklist)

Plan: §1c twelve-list · invariant 13's window groups (Computer→Appliance Repair in the fast group; Pest Control added to it; Gardening removed from the slow group) · Phase 4 seed block (lead times: Appliance Repair 120, Pest Control 180) · Round 20/22 notes naming Computer or Gardening · Booking entity gains `occasion` (Phase 17) · request-flow chip row (Phase 17.2) · wizard guidance (Phase 9). Repo: CLAUDE.md invariant 13 · designer-brief · grid redraws in `Discovery.dc.html` and wizard step 1 when session 10 runs · `verify-dc.py` if it greps category names.

**Open questions before adoption:** (a) Appliance Repair vs Appliance & Device Repair as the tile label; (b) Pest Control's quote window — 2h/4h as recommended, or the 24h/72h it would inherit from Gardening's slot; (c) whether `occasion` lands in v1 (recommended — it's one field) or rides with packages post-v1.
