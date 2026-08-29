One new artboard: **`My Calendar`**. The three corrections in the previous round still stand — apply them if they haven't landed yet.

## Why this screen exists

`Availability` handles **slot** listings: rules in, published times out. That covers three of the twelve categories — Cleaning, Beauty and Fitness.

The other **nine are request-based** — Plumbing, Electrical, AC Repair, Photography, Pest Control, Appliance Repair, Moving, Events and Boat Charter. They publish no times, so they have no rules and no generated slots, and `Availability` has nothing to say to them. But they are not free of a calendar:

- An accepted request booking **holds the provider's time exactly like a slot booking does** — the same provider-wide reservation, the same protection against being in two places at once
- Providers block ranges for travel, public holidays and seasonal hours whatever mode they work in

So a Boat Charter operator today has commitments they cannot see and a trip they cannot record. `My Calendar` is that screen, and it is **provider-wide** — every listing, both modes, one place.

## What it contains

**A header that is not listing-scoped.** `My Calendar` · *Every commitment across your services.* This is the deliberate contrast with `Availability`, which is scoped to one slot listing.

**1 · Upcoming commitments, by date.** Each entry: time, the customer's **first name only**, which listing it belongs to, the booking reference, and a quiet mode marker distinguishing a slot booking from a request booking. Tapping opens `Booking Detail.dc.html`. Group by day the way `Availability` groups its times, so the two screens read as relatives.

The fact this screen exists to make obvious: **a booking on any one of your listings holds the time across all of them.** `Availability`'s reserved-time sheet already says this well — reuse that language rather than inventing a second phrasing.

**2 · Time away.** Named, all-day absences with a date range: `Malé trip · 4 – 6 Sep`, `Public holiday · 24 Sep`. Add, list, remove.

Be careful with the copy here. A blocked range **removes published time slots** where the provider has any, and it is a record the provider keeps so their own calendar tells the truth when they are deciding whether to take a job. It does **not** stop a customer sending a request for those dates — nothing in the product does that, and saying so would promise a filter that doesn't exist.

**What this screen does not have:** no weekly rules, no generated-times preview, no per-time blocking. Those are slot concepts and they stay in `Availability`.

## The one split to get right

`Availability` currently owns two kinds of exception, and they are different things:

- **`Ramadan hours · 10:00–15:00 only`** — a *modified schedule*. It only means something where hours are published, so it **stays in `Availability`**.
- **`Malé trip · All day · 4 – 6 Sep`** — an *absence*. It applies to the provider whatever they have listed, so it **moves to `My Calendar`**.

Move the trip out of `Availability`'s exceptions and leave Ramadan hours there. One concept, one home, in each case. Don't build a second editor for the same thing.

## Reaching it

`My Services` routes to both, but not every provider needs both. Add a scenario prop for what the provider has listed:

- **slot listings only** — `Availability & time slots` and `My Calendar`
- **request listings only** — `My Calendar` alone; no `Availability` row at all, since there is nothing there for them
- **both** — both rows

Default the artboard to **both**, so the relationship is visible.

## States

Populated · empty · loading · error, matching `Availability`'s treatment. The empty state is a real one: a new request-mode provider with nothing booked yet. Say what will fill it — accepted bookings appear here automatically — and offer time away as the thing they can do now.

## Cast

Ibrahim Rasheed, as everywhere else this session. Give him at least one **Boat Charter or Events** commitment so the screen exercises a request-mode job — a fishing trip or a wedding — alongside a Cleaning slot booking. That contrast is the whole point of the screen and no artboard in the project has shown a request-mode job on either of those categories yet.

## Guardrails

- **Emergency jobs take no calendar reservation** — an emergency interrupts the published calendar rather than blocking it. Nothing on this screen may render an emergency job as reserved or blocked time. Simplest correct answer: leave emergency out of this screen entirely.
- No phone numbers, no customer surnames, no contact details of any kind.
- Import `EmptyState`, `SkeletonCard` and `Chip` rather than redrawing them; listing and booking states keep the styling `My Services` and `Availability` already use.
- Money as MVR. Categories are the Round 25 twelve. Photos uploaded, never hotlinked.
