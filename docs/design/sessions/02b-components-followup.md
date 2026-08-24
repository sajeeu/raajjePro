The extraction is right. Props declared, callbacks typed `null`, `dc-import` used properly with `hint-size` and never self-closed, `stopPropagation` on the heart and the remove ×, and the two mappings landed where they belong — tier copy inside `VerificationBadge`, the twelve status labels inside `StatusPill`. `VerificationBadge` returning nothing for a null tier is exactly right. Do not rework any of that.

Six corrections. The first is the only one that matters much.

## 1 — `ServiceCard` knows eight categories. There are twelve.

`CATS` and the `category` enum both list: Cleaning, Plumbing, Electrical, Moving, Gardening, Beauty, Photography, Computer.

**Missing: AC Repair, Fitness, Events, Boat Charter.** All four currently fall through to `DEFAULT_CAT` and render with the generic grey wrench, so a third of the catalogue loses its identity on every card in the app.

This is the same defect as the Tuition category, arriving from the other direction — a twelve that got built as eight. Add them, with their own accents:

- **AC Repair** — blue: `bg #EFF6FF` · `fg #2563EB`
- **Fitness** — violet: `bg #F5F3FF` · `fg #7C3AED`
- **Events** — yellow: `bg #FEFCE8` · `fg #CA8A04`
- **Boat Charter** — cyan: `bg #ECFEFF` · `fg #0891B2`

Draw each a stroke icon on the same 24px grid and in the same style as the eight that exist. Add all four to the `category` enum too, so the twelve are selectable.

Keep `DEFAULT_CAT` as the fallback — a thirteenth category must still render.

## 2 — `mode` defaults the dangerous way round

`data-props` defaults `mode` to `"request"`, but `renderVals` reads `(p.mode ?? 'instant') === 'instant'`. So a card that omits `mode` renders **Book instantly**.

That is the wrong direction to fail in. Telling a customer they can book a time instantly, on a service where a provider has to quote first, sets up the exact confusion the booking-mode affordance exists to prevent. The reverse mistake merely under-promises.

Change the fallback to `'request'` so code and declared default agree.

## 3 — `VerificationBadge` size defaults disagree

`data-props` defaults `size` to `"full"`; `renderVals` reads `this.props.size ?? 'chip'`. Same class as above, lower stakes. Make both `"chip"` — it is the common use, and `ServiceCard` passes it explicitly anyway.

## 4 — The two card variants order the chips differently

Horizontal renders **mode, then emergency**. Full renders **emergency, then mode**. It is one component and should read the same way in both.

Use **mode first, emergency second**, matching the horizontal card. Mode applies to every listing; emergency is the exception that qualifies it.

## 5 — `StatusPill` should not invent a label

The fallback is `['Unknown','grey']`, so an unmapped status shows a customer the word **"Unknown"** about their own booking.

Fall back to the **raw status string** instead. A pill reading `payment_claimed` is obviously a gap during review and gets fixed; one reading "Unknown" looks deliberate and ships.

## 6 — `EmptyState` renders an empty button

The action button always renders, so an empty `actionLabel` produces a button with no text. Gate it on `actionLabel` being present.

## Before you finish

Confirm `Components.dc.html` mounts **all seven** via `<dc-import>` and no longer holds a second hand-written copy of any of them — that was the whole point of the split, and a leftover copy is the drift it was meant to close.
