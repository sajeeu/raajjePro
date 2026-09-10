# Round 56 — a slot is still a request

One line, one artboard. `Create Service.dc.html`, step 5 only.

**Leave alone:** every other step, every other artboard, all seven steps' layout
and order, the two radio cards' structure and states (including the locked
"Fixed time slots" variant with its padlock and reason line), the Working days
chips, the Emergency Service toggle and its disabled reasoning, all colour,
radius, spacing and motion. Nothing gains or loses a control. The **"Request a
time"** card's own sub-line is correct and does not change.

---

## Why

Step 5's first radio card tells the provider:

> Fixed time slots — Customers pick a published time and **it's confirmed
> instantly.**

That is a promise the booking machine does not keep, and it was retired a
dozen rounds ago. **§0.0 item 13 (Round 44)**: picking a published slot creates
a **`requested`** booking that the provider still has to accept, on the same
24-hour auto-decline clock as a request-based one. That is why the customer-side
card affordance changed from "Book instantly" to **"Pick a time"** in the same
round, and why §1c's slot signal answers *how soon* rather than standing as
evidence for instant confirmation — "there is no such promise to evidence".

This line is worse than the customer-facing copy Round 44 fixed, because of
where it sits: it is the sentence a provider reads **at the moment they choose
their booking mode**. A provider picking slots on the strength of it believes
they have opted out of accepting bookings, and then spends their first week
being asked to accept them. The mode is right; the description of it is not.

It is also the only remaining instance anywhere in the set — every other
artboard was corrected in Round 44, which is what makes this one a survivor
rather than a pattern.

---

## The change

Step 5, the "Fixed time slots" card, sub-line only:

- **From:** "Customers pick a published time and it's confirmed instantly."
- **To:** "Customers pick from the times you publish, then you accept."

Same one line, same two-line budget at 12.5px, same colour token
(`{{ slotsSubFg }}`, so it keeps dimming with the card when the mode is locked).

The wording is deliberate on two points:

- **"then you accept"** names the provider's own next action, which is what
  makes the two cards genuinely different from each other. Both modes end in
  the provider accepting; what differs is whether the *time* is theirs or the
  customer's, and that is exactly what the two sub-lines now say.
- **No timing claim of any kind** — not "quickly", not "in minutes", not the
  24-hour clock. The clock is a decline deadline, not a service promise, and it
  belongs on the provider's accept prompt where it already lives, not in a
  sentence chosen before a single booking exists.

---

## What must not change

- **The two cards stay a two-option radio.** This is not the place to explain
  the booking state machine; it is the place to pick one of two modes.
- **The locked state stays exactly as designed.** When the category forces
  `request` mode, the "Fixed time slots" card is still disabled, still shows
  the padlock, and still shows `{{ slotsReason }}` — this round changes what
  the enabled card *says*, not when it is available.
- **Nothing about emergency.** The Emergency Service toggle, its tier
  reasoning and its disabled copy are untouched.
