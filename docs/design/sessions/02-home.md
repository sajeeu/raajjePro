Build the Home screen for RaajjePro, plus a shared component sheet extracted from it.

This is the anchor session for rebuilding the whole app. Home is where the visual language is most visible, and twelve later sessions will inherit from what this one establishes — the service card, the bottom navigation, the header, the section rhythm.

**Match the existing design, do not improve it.** Two reference files are attached. The tokens, spacing, type and component style in them are correct and settled; reproduce them faithfully. Where you would naturally reach for something nicer, don't — consistency with what already ships matters more here than any individual screen.

Produce **two files**:

1. `Home.dc.html` — the screen
2. `Components.dc.html` — the shared vocabulary, extracted as you build

---

## About the app

RaajjePro is a mobile marketplace for local services in the Maldives — a customer finds a plumber, cleaner, electrician or photographer, books them, and pays the provider directly. Portrait phone, Flutter, 412px frame.

## `Home.dc.html`

A customer's landing screen — where someone who does not yet know what they want ends up.

- **Header:** a location control naming the browsing island, `Malé`, changeable. Search entry.
- **The twelve-category grid**, or a route to it: `Cleaning` · `Plumbing` · `Electrical` · `AC Repair` · `Beauty` · `Photography` · `Gardening` · `Computer` · `Moving` · `Fitness` · `Events` · `Boat Charter`
- **Sections**, each a horizontal run of service cards: `Popular near you` · `Featured providers` · `Popular this week` · `Nearby` · `Recently viewed`
- **A Become a Provider entry**
- **Trust content** — see the copy rule below
- **Bottom navigation**, five tabs: Home · Explore · Bookings · Messages · Profile. Active state as a tinted pill

### The service card — design this once, it is used everywhere

Cover image · service name · provider name · category · rating with review count · price with its unit · island · verification badge where the provider has one · save control · **and its booking mode**.

- `Home Deep Cleaning` — `Mariyam Shifa` — `Cleaning` — `4.8 (24)` — `MVR 450/session` — `Malé` — Silver — **Book instantly**
- `Emergency Plumbing & Pipe Repair` — `Ibrahim Rasheed` — `Plumbing` — `4.6 (31)` — `From MVR 350` — `Malé` — Gold — **Request a time · Emergency available**
- `AC Servicing & Gas Refill` — `Ahmed Shakir` — `AC Repair` — `4.4 (12)` — `MVR 600/visit` — `Hulhumalé` — Silver — **Request a time · Emergency available**

**Booking mode is on every card, always.** `Book instantly` means the customer picks a published time; `Request a time` means the provider comes back with a time and a price. A customer must never be uncertain which kind of wait they are in.

### Two corrections to the attached Home images

The images are the visual reference. They are **wrong in content** in two specific places and must not be reproduced as drawn:

1. The featured card is a **Tuition** listing. There is no Tuition category — there are twelve, listed above, including Boat Charter. Replace it.
2. The trust card claims **"Secure Messaging — Private, encrypted communication within the app."** This is false: chat is readable by an admin during a dispute. The honest copy is **"Private messaging — your contact details are never shared."**

### States

- **Loading** — skeletons matching the real layout, not a centred spinner
- **Populated** — as above
- **Error** — a section that failed to load, with retry, without breaking the rest of the page
- **Launch mode** — a required variant, not an edge case. Below `50` published services the feed collapses to **two sections plus the category grid**. Render it convincingly against roughly `20` services. This is the first impression every early user gets, and nine sparse rows showing the same three services reads as an abandoned product
- **No location set** — before the customer picks a browsing island

Add a `scenario` tweak to switch between populated, launch mode, loading and error.

## `Components.dc.html`

The shared vocabulary, as a component gallery. Later sessions import from this file rather than re-deriving each piece, which is what stops twelve separately-built sessions from drifting into twelve products.

| Component | Variants required |
|---|---|
| **Button** | Primary (gradient) · secondary (outline) · text · destructive. Each with default, pressed, disabled, loading. Loading keeps the label and adds a spinner |
| **Text input** | Default · focused · filled · error · disabled · read-only. Error message below the field, never a tooltip |
| **Chip** | Filter (selectable) · input (removable) · static. Selected inverts to primary |
| **Service card** | The card above, in the horizontal and full-width forms |
| **Verification badge** | Bronze · Silver · Gold · none. Compact for cards, full for profiles |
| **Status pill** | Semantic colour, **never colour alone** — always with a label |
| **Bottom navigation** | Five tabs, active as a tinted pill |
| **Avatar** | Image · initials fallback · with badge overlay |
| **Skeleton** | The shimmer used by every loading state |
| **Empty state** | Icon, line, and the action that fills it |

### The verification badge carries its own words

Three tiers, and the tier decides what a provider is allowed to do — Gold is required for emergency electrical and plumbing work.

- **Bronze** — `ID checked by RaajjePro`
- **Silver** — `ID checked, work verified`
- **Gold** — `ID checked, registered trade`
- **None** — the badge is **absent**. Never a grey "unverified" chip; absence is the signal, and an unverified provider is still fully listed and bookable

**Never render a bare "Verified."** A customer reads that as "has a good track record" rather than "passed an ID check."

---

## Rules that override anything else

- **Never claim a payment was verified.** RaajjePro cannot see a bank transfer. No lock, no shield, no "Paid ✓" anywhere in the product.
- **Never generate a judgement about a provider.** Numbers only — `4.8 (24)`, `94% on time`. Never a label like "Top rated" or "Reliable".
- **Never say messaging is encrypted.** It is not.
- **Every screen needs four states.** A screen delivered with only its populated state is not finished.
- **Money is `MVR 450`** — code first, no symbol, decimals only where a value has them.
