# Round 60 — corrections to the three quote screens

Raised while building **§Phase 17.2** (the request-with-quote path) against
`Request a Time.dc.html`, `Propose Time and Price.dc.html` and
`Quote Received.dc.html`. `verify-dc.py` passes on all three; everything below
is what a structural check cannot see.

**Two of these are corrections to the prototypes. Two are things the
prototypes get right and the *plan* should say more clearly — those are noted
so nobody "fixes" the design toward the stale sentence.**

Change only what is named. Everything else on these three screens is correct
and was implemented as drawn.

---

## 1. The island control on `Request a Time` is a native `<select>` — replace it

**This is the one real defect.** In the "Somewhere else" branch of the Address
card:

```html
<select style="height:46px;…">
  <option>Malé</option><option>Hulhumalé</option><option>Villimalé</option>
</select>
```

Invariant 15 and §0.0 item 12 are explicit, and this is the sentence that names
this exact case:

> **Island search is the primary way an island is chosen, not a filter over a
> browsable list** — 192 entries is not scrollable. … **A native `<select>` is
> not an acceptable island control anywhere, including `Saved Preferences` and
> the emergency request form.**

Three islands in a dropdown is also three of 192, and two of the three names it
offers are unique while a real list contains sixteen ambiguous groups.

**Replace it with the island search control** the other screens already use —
matching anywhere in the name from the first character, prefix matches ranked
first, atoll code matched too, case, accents and the Dhivehi apostrophe ignored
on both sides, every match returned with no cap, and never auto-selecting even
on a single match. Render an ambiguous name qualified (`Dh. Meedhoo`) and an
unambiguous one bare (`Kulhudhuffushi`). Print no island total.

---

## 2. The photo slots on `Request a Time` promise something the product has no field for

The "What's the job?" card carries three `image-slot`s — *"Photos — optional —
they help Ibrahim quote accurately"*.

§Phase 17's `Booking` field list has no media, and no item in the phase
mentions attachments. §1c's request-based flow asks for "job details and
location", not photos. So the screen offers a control whose content has nowhere
to go, and the build left it out rather than inventing a field.

Photos would genuinely help a plumber quote a leak, and §1c does allow them in
the **enquiry** channel — "photos of the issue" — so this is a plausible
feature that was simply never specified for the booking itself.

**Either** drop the three slots from the card, **or** leave them and flag the
screen as depending on a decision the plan has not made. Do not redraw them as
required.

---

## 3. The four time chips on `Propose Time and Price` have no source

The provider's time row offers `06:00 · 06:30 · 07:00 · 16:30`. A `request`
listing publishes no slots (that is what makes it `request` mode) and its
category seeds no hours — so unlike the day chips beside them, these four
cannot be generated from anything.

The build kept the **day rail as drawn** and picks the time with a clock
instead, because four literals would have been invented configuration.

**Suggested:** keep the day chips exactly as they are and replace the time row
with a single "Set the time" control. If the chips stay, mark them in the file
as illustrative so nobody seeds a `timePresets` column to feed them.

---

## 4. ✅ "He has 2 hours to reply" is right, and the plan has a stale sentence behind it

**Do not change this.** Recording it because it decided a real conflict.

`Request a Time` tells the customer the provider has **2 hours** to reply, and
its own comment reads *"Quote + approval windows are category rules, not screen
constants."* §1c's Round 15 table agrees: 2 hours to quote and 4 to approve for
the six household trades, 24 and 72 for the long-lead three, seeded as
`quoteExpiryMinutes` / `quoteApprovalMinutes`.

**§1c step 4 still says "Slot and request-based: 24 hours"** for the same
window. The build followed the artboard and Round 15 — a request booking now
expires on its category's own `quoteExpiryMinutes`, which is unchanged at 1440
for Photography, Moving and Boat Charter and is two hours for a plumber.
`docs/decisions/29-phase-17-2-quotes.md` §1 carries the full reasoning.

**The plan is what needs the edit, not the screen.** Step 4's first bullet
should read "slot: 24 hours; request: the category's `quoteExpiryMinutes`".

---

## 5. ✅ Everything else on these three screens was implemented as drawn

Listed so a later round does not "fix" something that is already right:

- The **quick-pick chips lead** and free text sits underneath, with "This is a
  preference, not a slot" beneath both (§1c).
- **"Sending opens the chat with Mariyam right away"** — correct, and the
  reason the chat state opens at `quote_offered` rather than `accepted` (§0.0
  item 7).
- **"Sending holds {time} for Mariyam"** — correct; offering a quote takes a
  provisional reservation on the proposed time (§1c).
- The `WINDOWS` map — 4 hours for the six household trades including **Home
  Repairs**, 72 for Photography, Moving and Boat Charter — matches invariant 13
  and §0.0 item 16 exactly.
- **"Nearly right? Say so in chat" sits above "Decline this quote"** — correct,
  and load-bearing: the provider can revise while the quote is live, and a
  decline closes the booking.
- The countdown's three bands (neutral → amber under an hour → red under
  fifteen minutes) and "Expired" disabling Accept.
- `Quote Received`'s declined state offering **"Send a new request"** rather
  than "ask again" — correct; there is no re-quote after a decline.
