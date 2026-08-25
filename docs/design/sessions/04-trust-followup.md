# Session 3 corrections — Service Preview, Provider Profile

Both screens are in good shape. The callback guarantee and the provider warranty
came out properly distinct, the conduct metrics carry no colour verdict, and the
ten-booking floor works. Leave all of that exactly as it is.

Six changes, all content. No layout work.

---

## Service Preview

### 1. The emergency block names the wrong fee — material

Current: **"Call-out fee MVR 200 applies — confirmed with you before anyone is dispatched."**

Two different sums are being conflated:

- The **MVR 200 dispatch fee** is what RaajjePro charges the customer. Fixed.
- The **callout fee** is what the provider charges to attend. It varies, the
  provider supplies it when they accept, and nobody knows it until offers arrive.

As written, a customer reads MVR 200 as the price of attendance — and the number
that actually varies is the one not shown.

The sequence is also inverted. The request broadcasts to every eligible provider
*first*; the MVR 200 is incurred when the customer **selects an offer**, and never
on submitting the request. There is no confirmation step before dispatch.

Replace the body line with:

> Offers arrive with each provider's own callout fee and arrival estimate. Choosing
> one adds RaajjePro's MVR 200 dispatch fee, settled later by bank transfer.

Keep the heading, the icon, the red treatment and the chevron into the emergency
flow — all correct.

### 2. The emergency block is on a Cleaning listing

`emergencyPath` can be switched on for Mariyam Shifa's Home Deep Cleaning. Emergency
layers onto **Plumbing, Electrical, AC Repair and Moving only**, and Mariyam is
Silver — below the Gold bar Plumbing and Electrical require.

Either drop `emergencyPath` from this screen's props, or add a second sample
listing the toggle applies to: **Ibrahim Rasheed · Emergency Plumbing & Pipe Repair
· Gold · Malé · From MVR 350 · request mode**. Ibrahim already exists on Provider
Profile with those exact values — reuse them rather than inventing a new provider.

### 3. Reply time is shown on an instant-booking listing

The provider row reads "Usually replies in ~1 hour" while the listing is in
`instant` mode. Slot-mode listings answer a different question — *how soon can
someone come?* — so the signal is the next open time.

Make the provider row's second line follow the mode:

- `instant` → **Next available: tomorrow 09:00 · 86 jobs completed**
- `request` → **Usually replies in ~1 hour · 86 jobs completed**

`tomorrow 09:00` is Mariyam's existing `nextSlot` on Discovery. Use it verbatim so
the card and the detail page agree.

### 4. One invented review tag

`'Thorough (14)'` is not in the seeded tag set. Review tags are fixed per category
and never free text — a minted name starts exactly the drift the fixed set prevents.

Replace with **`'Quality materials (14)'`**. Leave `On time (19)`, `Fair price (12)`
and `Arrived late (3)` as they are — all three are correct, and `Arrived late (3)`
sits right on the three-application display threshold, which is a good edge to keep.

---

## Provider Profile

### 5. One invented review tag

Same rule. `'Tidy work (14)'` → **`'Quality materials (14)'`**.

`On time (26)`, `Fair price (21)` and `Arrived late (4)` are correct. Hassan Faiz's
single `On time (3)` is also correct — it sits exactly on the threshold, which is
worth keeping as the edge case it demonstrates.

---

## Both screens

### 6. Pin Mariyam's job count

"86 jobs completed" is a new number for a provider who already appears on Home and
Discovery. It contradicts nothing, so keep it — but it is now fixed at **86**, and
her review count stays **24**. Do not let a third figure appear on a later screen.

---

## Leave alone

- The callback guarantee card — green, shield-check, "Enforced by RaajjePro."
- The warranty card — plain white, `Provider states:` on every line, "RaajjePro has
  not checked them." The separation between these two is the point of the section.
- The Track record grid: six metrics, one colour, no ticks or arrows.
- `New provider · 7 jobs completed` for Hassan Faiz, and the suppressed grid behind it.
- The not-found copy on Provider Profile. It describes derived visibility correctly.
- Every `dc-import`. The components are doing their job.
