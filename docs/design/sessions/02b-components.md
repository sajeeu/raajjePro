Split the component sheet into importable components. **Visuals unchanged** — this is a refactor, not a redesign. Every colour, size, radius, weight and spacing value stays exactly as it is in `Components.dc.html` today.

The problem being fixed: `<dc-import>` mounts a **sibling `.dc.html` file**, so a single gallery file cannot be imported from. Each reusable piece needs to be its own file with declared props. Later sessions then import the real component instead of copying markup, which is the only thing that stops twelve sessions drifting into twelve products.

## Seven new files, siblings of the sheet

**`ServiceCard.dc.html`**
`variant` ("horizontal" | "full") · `title` · `provider` · `tier` ("Gold" | "Silver" | "Bronze" | null) · `rating` · `count` · `price` · `unit` · `island` · `category` · `mode` ("instant" | "request") · `emergency` · `sponsored` · `saved` · `onSave` · `photo`

- `mode` renders the booking affordance: `instant` → **Book instantly**, `request` → **Request a time**. It is never absent
- `emergency` adds the **Emergency available** marker alongside it
- `sponsored` adds a visible **Sponsored** label — there is no unlabelled paid placement anywhere in this product
- `tier` delegates to `VerificationBadge`; **null renders nothing at all**
- `unit` is the price suffix — `/session`, `/visit`, `/hour`. Omitted for a range like `From MVR 350`
- `saved` / `onSave` drive the heart, optimistic with a visible rollback

**`VerificationBadge.dc.html`**
`tier` · `size` ("chip" | "full")

- `chip` is the compact pill used on cards; `full` carries the tier's own words alongside it
- The words are fixed and belong in this file so they can never drift: Bronze `ID checked by RaajjePro` · Silver `ID checked, work verified` · Gold `ID checked, registered trade`
- **Renders nothing when `tier` is null.** No grey "unverified" chip, no placeholder, no empty space reserved. Absence is the signal

**`Chip.dc.html`**
`label` · `kind` ("filter" | "input" | "static") · `selected` · `onTap` · `onRemove`

- `filter` inverts to primary when selected; `input` carries the × and calls `onRemove`; `static` is a label with no interaction

**`StatusPill.dc.html`**
`status`

- The status → label and colour mapping lives **inside this file**, so a booking status is described identically everywhere it appears
- Handle: `waiting_provider` → "Waiting for provider" · `quote_received` → "Quote received" · `awaiting_payment` → "Awaiting payment" · `payment_sent` → "Payment sent" · `receipt_confirmed` → "Provider confirmed receipt" · `confirmed` → "Confirmed" · `completed` → "Completed" · `declined` → "Declined" · `cancelled` → "Cancelled" · `disputed` → "Disputed" · `unresolved` → "Unresolved" · `pending_offline` → "Pending — sends on reconnect"
- **Semantic colour, never colour alone** — every pill carries its label

**`BottomNav.dc.html`**
`active` (tab name) · `onTap`

- Five tabs: Home · Explore · Bookings · Messages · Profile. Active state as the tinted pill

**`SkeletonCard.dc.html`**
`variant` matching `ServiceCard`

- Shimmers in the shape of the card it stands in for, so a loading list has the real layout already

**`EmptyState.dc.html`**
`icon` · `title` · `body` · `actionLabel` · `onAction`

- The action is part of the component, not optional decoration — an empty state names what to do next

## Then rebuild the sheet

`Components.dc.html` keeps its section headings and its explanatory copy, but **mounts each piece via `<dc-import>`** instead of holding a hand-written copy. It becomes the gallery *of* the components rather than a second definition of them. Its remaining own content is Button and Text input, which stay inline — they are style references rather than things later sessions import.

Set `hint-size` on every import, and never self-close the tag.

## Two things to expect

**Every `.dc.html` becomes its own artboard.** There is no way to hide one from the canvas, so these seven will appear. That is fine — it is the component library view. Give them a deliberate row below the existing artboards rather than letting them scatter.

**`Home.dc.html` is not in scope for this pass.** Leave it as it is. Migrating it to the imported components is worth doing, but it is a separate change and it should not ride along with an extraction that is meant to be visually identical.

## Check before you finish

- Every prop above is declared in the child's `data-props`, with `editor: null` for the callbacks
- `VerificationBadge` with `tier` null renders nothing — not an empty span, nothing
- A `ServiceCard` with `tier` null still renders correctly, since that is the common case at launch
- The sheet still looks exactly as it did
