Build the discovery screens for RaajjePro — four screens, in one file where they share state.

**Import from `Components.dc.html`** rather than re-deriving anything. The service card, verification badge, chips, status pills, bottom navigation, skeleton and empty state all exist there and are settled. This is the first session that inherits from that sheet, and every session after this one does too — so if an import does not resolve, say so rather than copying the markup across, and I will fix the sheet.

**Match the existing language, do not improve it.** `Home.dc.html` is the reference for how these pieces sit together — same 412px frame, same 20px screen padding, same header treatment, same tokens.

---

## Screen 1 — Explore

The twelve categories.

- All twelve, each with a name and an icon: `Cleaning` · `Plumbing` · `Electrical` · `AC Repair` · `Beauty` · `Photography` · `Gardening` · `Computer` · `Moving` · `Fitness` · `Events` · `Boat Charter`
- Each carries its own accent tint for the icon chip, as on Home
- Each opens its category results
- A search entry at the top
- **The attached mockup shows Tuition. There is no Tuition category — replace it with Boat Charter.** The grid stays twelve
- Fact: the grid is driven by live data. A thirteenth category must appear without a redesign, so do not hand-place twelve tiles

## Screen 2 — Search results

What matched, and how to narrow it. High traffic, and the screen where a customer decides who to look at.

- The query and a result count: `18 services`
- **Sort, in this order:** `Distance` · `Rating` · `Price`. Distance leads deliberately — a provider who cannot reach your island is not a result at all, so it is the first cut rather than a preference
- **Filters:** island · category · price range · booking mode · `Emergency available` · `Maldivian-owned business`
- Result cards using the full-width card from the sheet, **with the booking-mode label on every one**
- **Some results are paid placement, and each one says so** — a visible `Sponsored` label. There is no unlabelled paid placement anywhere in this product, and a sponsored result still has to be genuinely relevant; priority affects ordering within the matching set, never membership of it
- Convey: **verification does not affect whether a provider appears.** It changes the badge they carry, not their findability. An unverified provider ranks normally
- `Maldivian-owned business` is an attribute of the **business**, shown only where it applies. It is never a nationality and never a filter on people

### States

- **Loading** — skeleton cards in the real layout
- **Populated** — a mix: at least one sponsored, at least one with no badge at all, at least one `Request a time`, one `Book instantly`, one `Emergency available`
- **Empty** — `No services matched`, naming **which filters could be relaxed** rather than just reporting nothing
- **Error** — with retry

## Screen 3 — Category results

One category's services. Structurally the same as search, so reuse it rather than building a second thing.

- Category name and count: `Plumbing · 6 services`
- The same cards, sort and filters
- Empty: `No plumbers on Malé yet`, with a route to change island or browse everything. The empty state here is the interesting one — at launch most categories on most islands will be empty, and this screen is where that is felt

## Screen 4 — Saved

Services and providers the customer kept.

- **Two kinds in one place** — saved services and saved providers. Decide how they sit together; they are different objects and a customer thinks about them differently
- Saved services as cards, identical to search results
- Saved providers with name, tier and rating
- Unsave from here, with the optimistic toggle and a visible rollback if it fails
- Convey: **saving a provider is how a customer remembers a person.** There is no phone number to write down — that is the point of the feature, not a limitation of it
- Empty: `Nothing saved yet` plus a route to browse

---

## Fixed data

- `Aishath Nazim` — the customer, browsing `Malé`
- `Ibrahim Rasheed` — `Rasheed Plumbing Services` — Plumbing — **Gold** — `4.6 (31)` — `From MVR 350` — Request a time · Emergency available
- `Mariyam Shifa` — Cleaning — **Silver** — `4.8 (24)` — `MVR 450/session` — Book instantly
- `Ahmed Shakir` — AC Repair — **Silver** — `4.4 (12)` — `MVR 600/visit` — Request a time · Emergency available
- Islands: `Malé` · `Hulhumalé` · `Villimalé` · `Maafushi` · `Thulusdhoo` · `Hithadhoo` *(placeholder — the real list runs to a few hundred, so design the picker as searchable, not a dropdown of six)*

Invent at least two further providers to fill the results, including **one with no verification badge at all** — that is the common case at launch and the results screen must look right when it happens.

## Rules that override anything else

- **Never render a bare "Verified"** — three tiers, each with its own copy, and absent where there is no tier
- **Never a judgement about a provider** — numbers only, never "Top rated" or "Recommended"
- **Never unlabelled paid placement**
- **Money is `MVR 450`** — code first, no symbol, decimals only where a value has them
- **Every screen needs four states**, and the empty states here carry real weight
