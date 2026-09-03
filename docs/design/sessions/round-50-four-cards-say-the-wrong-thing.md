# Round 50 — four cards still say "Request a time"

A full audit of all 61 prototypes against the plan. Almost everything holds.
One thing does not, and it has been wrong since Round 45.

**Leave alone:** every layout, colour, component, animation and every piece of
copy. This round changes four string values in seed data and adds one link.
Nothing about any design changes.

---

## 1. Four slot listings render as request listings

Round 45 §3c renamed the card's mode prop value `instant` → `slot`, in
`ServiceCard`, `Service Preview` and `Components`. Those three were done.

The **seed data was not**, and four entries still carry the old value:

| File | Listing | Category |
|---|---|---|
| `Home` | Home Deep Cleaning | Cleaning |
| `Home` | Bridal Makeup & Styling | Beauty |
| `Discovery` | Move-out & Deep Sofa Cleaning | Cleaning |
| `Discovery` | Home Deep Cleaning | Cleaning |

`Home` and `Discovery` pass the seed value straight through —
`mode="{{ s.mode }}"` and `mode="{{ r.mode }}"` — into a card that now resolves
slot mode as:

```js
const instant = (p.mode ?? 'request') === 'slot';
```

`'instant'` is not `'slot'`, so it falls to the request branch. All four render
**"Request a time"** with the calendar icon.

Those are the only three slot categories there are. So every slot card on Home
and Explore — the two most-seen screens in the prototype — shows the wrong
affordance, and **"Pick a time" does not appear on a card anywhere**. Round 44
existed to get that label right and Round 45 renamed the value it depends on;
the seeds are the half that was missed, and the result is that neither round is
actually visible.

**Do:** change `mode: 'instant'` to `mode: 'slot'` in all four. Nothing else —
not the titles, not the categories, not `nextSlot`, not the ordering.

### Why nothing caught it

Worth stating, because the gate looked clean the whole time. `verify-dc.py`
checks that a seed's category and mode agree, and it normalised `instant` and
`slot` to the same value before comparing. That normalisation was right before
Round 45 and became a blindfold after it: the pair `Cleaning` + `instant` passed
as consistent while the card disagreed.

The gate now has a rule for the value itself, warning on exactly these four.
When this round lands it goes to a hard failure.

---

## 2. `Booking Detail` still has no route to the chat

Carried from Round 49 §1, restated because it is the one finding there that is
an invariant rather than a convenience, and because §1 above is small enough
that both fit in one round.

In-app chat is the sole coordination channel for a booking's life. Twelve
screens link to `Booking Thread`; the booking's own detail screen is not one of
them, and reaches it only in two hops via `Propose Amendment` or
`Reveal Contact` — screens a customer opens to change a booking or swap numbers
on an emergency, not to send a message.

**Do:** add a route to `Booking%20Thread.dc.html` among the action rows that
already reach `Propose Amendment`, `Reveal Contact` and `Raise Dispute`. Label
it for the counterparty — **Message Ibrahim** — the way `Quote Received` does,
not a generic *Open chat*.

If Round 49 has already been applied, this is done; skip it.

---

## 3. What the audit found correct — do not "fix" any of these

Stated so a later round does not undo them. Every one was checked against the
plan and matches:

- **Emergency eligibility is per-category.** `Verification` states it exactly:
  *"Emergency work needs a tier: Gold on Electrical and Plumbing, Silver on AC
  Repair and Moving."* No screen hardcodes silver.
- **Visibility is not gated by tier.** *"A provider with no tier is fully
  visible and fully bookable."*
- **The badge is gated by verification alone.** `Billing`: *"Premium does not
  include the verification badge… it stays with you even if the subscription
  lapses, and no plan can buy it."*
- **The subscription price is per provider.** `Billing` shows MVR 75
  introductory, first 100 providers, 12 months from the billing anchor, then MVR
  150 with 30 days' notice — *"Prices are set per provider; another provider may
  see a different number."* Both price points coexist, which is what the
  conversion measurement needs.
- **Account deletion is queued.** *"Accepted immediately, completes within 30
  days."* Never refused.
- **The cover image is required at publish only.** `Create Service` carries a
  *Required to publish* chip, not a save-blocker.
- **Legal is placeholder and says so** — `[ placeholder — pending legal
  review ]` in monospace, with hatched bars for body text and only the one
  genuinely-true summary sentence set as real copy.
- **`Reveal Contact` states six of the seven conditions** — emergency-only, at
  accepted or later, customer-initiated, mutual and simultaneous, notified,
  24-hour expiry, logged. The seventh, the runtime kill switch, is a Phase 10b
  admin control and correctly absent from a customer screen.
- **Local preference is business ownership**, not nationality — `Discovery`'s
  *Maldivian-owned* filter and `Provider Profile`'s *Maldivian-owned business*
  attribute. No screen carries nationality on a person.
- **The 24-hour figures are the accept window, not a quote window.**
  `Booking Request`'s auto-decline copy and `Reveal Contact`'s expiry are both
  correct; the per-category 120/240 and 1440/4320 windows are a different clock
  and no screen hardcodes 24/72 for a quote.
- **The conduct threshold is 10 completed bookings** (`My Performance`), and
  Silver's auto-granted route is 5 clean bookings (`Verification`). Two
  different numbers for two different rules, both right.
- **No escrow language anywhere**, no platform-verified booking payment, and
  nothing gates a customer action behind payment.
- **90-second collection, three offers, MVR 200 dispatch fee, 30-minute
  response window** — consistent in every screen that mentions them.

---

## Checklist

- [ ] All four seeds read `mode: 'slot'`
- [ ] A slot card on Home and on Explore reads **Pick a time** with the clock icon
- [ ] `Booking Detail` reaches `Booking Thread` directly
- [ ] Nothing in §3 changed
- [ ] Nothing from Rounds 40–49 changed
