Build the four screens that turn browsing into a booking: **pick a time**, **request a time**, **quote received**, and **the payment step**.

This is where RaajjePro's central design constraint becomes unavoidable: **the platform never touches the money and never confirms that anyone paid.** A customer transfers to a provider's bank account and then *tells* us they did. Every screen here has to be honest about that without making the product feel unsafe — those two goals pull against each other, and resolving that tension is the actual work of this session.

**Import the components; do not re-derive them.** `ServiceCard` · `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` · `SkeletonCard` · `EmptyState` exist as sibling files with declared props. The twelve status labels live inside `StatusPill` — never retype one into a screen. `Service Preview.dc.html` is the immediate predecessor and the reference for frame, padding and tokens.

**No mockups exist for any of these four.** Propose the design. Where you make a structural call — how the time picker is laid out, where the amount sits relative to the bank details — say so in a short note so it can be reviewed as a decision rather than discovered later.

---

## The sequence these four sit in

Two entry paths converge on one payment step:

```
slot listing    → Pick a time  → Waiting for provider ─┐
                                                        ├→ Awaiting payment → Payment step
request listing → Request a time → Waiting for provider │
                  → Quote received → (customer accepts) ┘
```

Design them as one flow with a shared spine, not four unrelated screens.

---

## Screen 1 — Pick a time (slot listings)

The provider has published times; the customer takes one. `Home Deep Cleaning` · `Mariyam Shifa` · `MVR 450/session`.

**A date strip, then the open times on the chosen date** — `09:00` · `11:00` · `14:00`.

**Only genuinely open, not-yet-passed times are ever shown.** No greyed-out unavailable slots, no times that have already gone. A slot that looks disabled invites a customer to wonder what they did wrong; an absent slot asks nothing of them.

**Cleaning needs 3 hours' notice**, so today's earliest offered time reflects that. Lead time is per-category — 1 hour for Plumbing, 2 days for Events — so express it as a rule the screen obeys, never as a hardcoded three.

**Address**, chosen from saved addresses or entered fresh, with the island.

**Job notes**, free text, optional.

**The total before committing** — `MVR 450`.

**A confirm action, and the fact that has to survive it: the provider still has to accept.** Booking a time is a request. If this screen lets a customer walk away believing they have a cleaner confirmed for 14:00, the screen has failed regardless of how it looks. The resulting status is `Waiting for provider`.

**The chat does not open here.** For slot bookings it opens when the provider accepts. Do not put a message affordance on the confirmation that implies a thread already exists.

## Screen 2 — Request a time (request listings)

The customer proposes a window; the provider comes back with a concrete time and a price. `Emergency Plumbing & Pipe Repair` · `Ibrahim Rasheed` · `From MVR 350`.

**Preferred window, leading with one-tap choices:** `Tomorrow morning` · `Tomorrow afternoon` · `This week` · `This weekend`, with free text underneath for anything more specific. A blank text box as the primary interaction asks the customer to guess what format we want.

**Job description**, free text — what is wrong, what needs doing.

**Photos of the problem**, optional. Upload them into the project rather than hotlinking.

**Address and island.**

**The price is not settled.** `From MVR 350` is a starting price and the provider will send a real one. This is the same honesty problem as the range price on Service Preview, and it should be solved the same way so the two screens agree.

**State the real windows for this category.** Plumbing gives the provider **2 hours to respond**, and the customer **4 hours to accept** after that. On Photography, Gardening, Moving, Events and Boat Charter those are **24 hours** and **72 hours**. Both numbers come from the category — never hardcode 24/72, and never show a window that belongs to a different category than the one being booked.

## Screen 3 — Quote received

The provider has come back. `Tue 25 Aug · 14:00` · `MVR 650`, plus any note they added.

**Accept and reject**, and a **countdown on the time left to accept** — `3h 42m left` against Plumbing's 4-hour approval window.

**The chat is already open.** For request bookings it opens the moment the quote is offered, and this is the single most important thing on the screen. If the time is nearly right or the price is nearly right, the customer should message rather than reject — this is where negotiation actually happens, and a reject is a dead end that costs both sides the job. Design the message route as a real third option, not a footnote under two buttons.

**Accepting locks the agreement.** The price, the date, the time and the scope are fixed at that moment; changing any of them afterwards takes an amendment the other party accepts. This is not escrow and no money moves — it is a record of what was agreed. Convey the commitment without implying RaajjePro is holding funds.

**Expired quote:** state that the time was released, and give a route to ask again.

## Screen 4 — The payment step

The provider accepted. The customer pays them directly, by bank transfer, off the platform.

**The amount, and what kind of amount it is.** The label changes the meaning and must be exact:

| | |
|---|---|
| `Agreed price` | `MVR 450` |
| `Agreed total — 3 hours at MVR 200/hour` | `MVR 600` |
| `Quoted price` | `MVR 650` |
| `Callout fee — what this provider charges to attend. The final bill may differ.` | `MVR 350` |

**The provider's bank details** — account holder name, bank, account number, with a copy action on the number.

**RaajjePro is not handling this money**, and this has to be unmissable rather than fine print. The transfer goes from the customer to the provider.

**An `I've Paid` action — and it is the customer *saying* they paid.** Nothing is checked. Never `Payment verified`, never a lock icon, never a certainty check mark. The provider separately confirms receipt, and the honest phrasing for that later state is `Provider confirmed receipt` — a statement about what a person did, not a platform guarantee.

**The bank details are the one piece of provider information a customer ever sees, and they are not contact details.** A bank account number is not a way to reach a person. Nothing on this screen may drift toward "get in touch directly."

---

## Fixed sample data — use these exact values

**The customer:** `Aishath Nazim`.

**Slot booking** — `Home Deep Cleaning` · `Mariyam Shifa` · Silver · `Cleaning` · `Malé` · `MVR 450/session` · lead time `3 hours` · open times `09:00` · `11:00` · `14:00`.

**Request booking** — `Emergency Plumbing & Pipe Repair` · `Ibrahim Rasheed` · Gold · `Rasheed Plumbing Services` · `Plumbing` · `Malé` · `From MVR 350` · quote window `2 hours` · approval window `4 hours`.

**The quote** — `Tue 25 Aug · 14:00` · `MVR 650` · countdown `3h 42m left`.

**Bank details** — pin these and reuse them anywhere bank details appear again:

- Slot booking: `Mariyam Shifa` · `Bank of Maldives` · `7730 0000 145 872`
- Request booking: `Rasheed Plumbing Services` · `Bank of Maldives` · `7730 0000 291 604`

Note that Ibrahim's account is in his **business** name while Mariyam's is in her own — that difference is real, it will confuse someone comparing the name on the account to the name on the booking, and the design should absorb it rather than pretend every account matches a person's display name.

**Saved addresses** — `Home · M. Fehi Villa, Malé` and `Office · H. Athama Building, Malé`.

---

## States

Every screen gets loading, error and populated. Beyond that:

**Pick a time**
- **Slot taken while deciding** — a clear `No longer available` when confirm hits a slot someone else took. Not a silent failure, and not a generic error.
- **No times published** — `No times published yet`, with the option to message the provider instead.
- **All of today's times are inside the lead-time window** — today is offered but empty, and the reason is stated.

**Request a time** — the send action pending, and the sent confirmation.

**Quote received** — live countdown, near-expiry, and expired.

**Payment step** — before `I've Paid`, and after it while awaiting the provider's confirmation.

**All four: email not verified.** Booking requires a verified email address. Show the state and the route to fix it — but the server enforces this, so treat the UI as a courtesy rather than the gate.

---

## The rules that never bend

1. **RaajjePro never moves money for a booking.** No escrow, no holding, no gateway. The customer pays the provider directly.
2. **"I've Paid" is an attestation, not a verification.** Never render it as confirmed, verified, secured or protected. The same applies to the provider's side.
3. **A locked agreement is not escrow.** At acceptance the terms fix; that is a record, not funds being held.
4. **No phone numbers, anywhere, in any state.** Bank details are shown at this step and only this step. Nothing else identifying is.
5. **Category numbers come from the category.** Lead times, quote windows and approval windows all vary; the screen states the real ones for what is being booked and hardcodes none of them.
6. **Money is always whole rufiyaa in the UI** — `MVR 450`, never `MVR 450.00`, never a decimal.
7. **A slot that has passed is never shown**, whatever its stored status says.
8. **The chat opens at different moments for the two paths** — at the quote for request bookings, at acceptance for slot bookings. Do not show a thread that does not exist yet.
9. **Import the components.** Status labels live in `StatusPill`; tier copy lives in `VerificationBadge`. Duplicating either into a screen is a defect.

---

## Check the prop combinations, not just the props

This is new, and it comes from a defect the last session shipped: Service Preview let a `range` price sit next to `Book instantly`, which advertised a starting price as bookable. Each prop was individually correct; the combination was impossible.

For the payment step specifically, **the amount kind is determined by the booking that produced it and is never free-floating**:

- `Agreed price` comes from a flat-priced listing — so it can pair with the cleaning booking, never with the plumbing one.
- `Quoted price` comes from an accepted quote — so it pairs with the plumbing booking, never with the cleaning one.
- `Callout fee` comes **only from emergency dispatch**. It can never be reached from either of the two entry screens in this session. If you build that variant, it must clearly belong to the emergency path.

Before you finish: list every combination your props allow, and confirm each one describes a booking that could actually exist.

---

## What I will be looking at hardest

Whether the payment step manages to be honest and still feel safe. Everything about that screen wants to reassure — a shield, a lock, a green tick, the word *secure* — and every one of those would be a lie, because nothing is being checked and no money is protected. The screens that get this wrong do not look wrong; they look better than the honest version. What I will be checking is whether the reassurance on that screen comes from clarity — the customer knowing exactly what happens next and what recourse exists — rather than from borrowed security iconography that describes a system we did not build.

Second: whether "the provider still has to accept" survives the confirm action on screen 1. It is the easiest fact in this session to lose to a satisfying success state.
