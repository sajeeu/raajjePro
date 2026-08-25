Build the five screens where a booking becomes a **record**: **my bookings**, **booking detail & timeline**, **propose an amendment**, **reveal contact**, and **settle the dispatch fee**.

Session 4 built the screens where a customer commits. These are the screens they return to — to check what was agreed, to change it, to chase it, or in one narrow case to phone a stranger who is on their way. More product rules converge here than on any other screen in the app, and two of them are the sharpest in the whole specification. Read the rules at the bottom **before** you start.

**Import the components; do not re-derive them.** `ServiceCard` · `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` · `SkeletonCard` · `EmptyState`. **`StatusPill` carries all twelve status labels** — this session displays more of them than any other, and every one must come from the component. Retyping a status string into a screen is a defect.

**Attach:** `mockups/Bookings.jpg`. It covers my-bookings — Upcoming, Active and Completed with its empty state — and unlike most of the set it does **not** contradict the plan. Follow it. The other four screens have no mockup: propose the design, and flag structural calls in a short note.

---

## The two things most likely to go wrong

**1. There are two different payment mechanisms in this app and this session touches both.** They must never look alike.

| | **Booking payment** (session 4) | **Dispatch fee** (this session) |
|---|---|---|
| Who is paid | the provider, directly | RaajjePro |
| Proof | none — a two-sided self-attestation | a **proof-of-transfer upload** |
| Who confirms | the other party says "Payment Received" | an **admin** confirms |
| Reference code | none | yes — `RP-4471-EMG` |

You have just built the first one, where uploading proof would be wrong and "verified" would be a lie. On the dispatch fee the opposite holds: proof upload is correct, a reference code is correct, and an admin really does check. **Do not carry either treatment across.** If a customer can't tell from the screen which of the two they're looking at, the screen has failed.

**2. Reveal contact is the only place in the entire product where a phone number reaches another person.** Every other screen showing one would be a defect. Treat it as a deliberate, narrow, audited exception — not as a feature to make convenient.

---

## Screen 1 — My bookings

Every booking, as a customer. **A mockup exists and is correct — follow it.**

Filters across the status groups, and each entry carrying service, provider, date and time, amount, and **status**. The status set is long and must be legible at a glance:

`Waiting for provider` · `Quote received` · `Awaiting payment` · `Payment sent` · `Confirmed` · `Completed` · `Declined` · `Cancelled` · `Disputed` · `Unresolved`

All of these live in `StatusPill`. Each entry opens its detail. Empty: `No bookings yet`, with a route to browse.

## Screen 2 — Booking detail & timeline · PRIORITY

One booking, its whole history, and whatever needs doing next.

**The header facts:** service, provider, date and time, address, job notes, the amount and its label.

**A status timeline — every transition, when it happened, and who caused it.** The attribution is the point, not decoration; this is the customer's evidence if anything is ever disputed:

> `Requested · you · 22 Aug 09:14` → `Accepted · Mariyam Shifa · 22 Aug 09:41` → `Payment sent · you · 22 Aug 10:02` → `Provider confirmed receipt · Mariyam Shifa · 22 Aug 10:30`

**The locked agreement, stated as such.** Price, date, time and scope were fixed when the provider accepted, and neither side can change them alone. RaajjePro records the agreement and holds no money — the same framing as the Quote Received screen, and it should read consistently with it.

**Amendments, where any exist:** what was proposed, by whom, and whether it was accepted, **with the original terms still visible alongside**.

**A prominent route into the chat**, which stays open after completion and is never taken away — a follow-up question or a warranty claim still has its thread.

**Actions appropriate to the state:** cancel, dispute, reschedule, mark complete, rate, book again. Emergency bookings additionally carry a `Provider has not arrived` action once the response window has elapsed, and the contact-reveal action below.

🔧 **New since session 4 — the withdrawal.** A customer may withdraw an unanswered "I've Paid" (§1c step 7, Round 24). It is allowed **only while the provider has neither confirmed nor disputed**, and **once per booking**. Two consequences for this screen: the withdrawal is a transition and belongs on the timeline like any other, and the control needs a designed state for when it is no longer available — the session 4 prototype only has the case where it works.

## Screen 3 — Propose an amendment

Changing an agreed price, date, time or scope. Either party may propose; the other must accept.

**The original and the proposed value side by side** — `MVR 450` → `MVR 600` — plus a free-text reason, and a send action. On the receiving side, accept or reject.

**The original terms are kept either way, and every attempt is recorded whether it is accepted or not.** A provider who charges more than agreed without an accepted amendment shows up on their public price-adherence number. Say that plainly on the provider's side; a customer proposing an amendment carries no such consequence.

## Screen 4 — Reveal contact · emergency only

The one place in the entire app where a phone number crosses between two people.

**All seven conditions hold at once, and the screen should make the shape of them visible rather than hiding them behind a button:**

1. The booking is **emergency mode**. No slot or request booking can ever reach this.
2. The booking is at **`accepted` or later** — never at `requested`.
3. The **customer initiates**, explicitly. No automatic reveal, no provider-initiated reveal.
4. **Mutual and simultaneous** — both numbers appear, or neither.
5. **The counterparty is notified** at the moment it happens.
6. **Access ends 24 hours after the booking reaches a terminal state.**
7. **Every reveal is logged**, and the pattern surfaces in moderation.

**The honesty line that must not slip.** The number was **confirmed by an admin when the provider was verified**. It is not live-checked, and nothing on this screen may describe it as *verified* — no check mark, no shield. Say what is true: it was confirmed at verification.

**Design the unavailable state.** The reveal is killable at runtime without a deploy, so it can simply not be there. That is a real state, not an error, and it needs to read as a considered absence rather than a failure.

## Screen 5 — Settle the dispatch fee

The `MVR 200` owed to RaajjePro after an emergency dispatch.

The amount and what it was for, **naming the booking**. RaajjePro's bank details and a **reference code** — `RP-4471-EMG`. A proof-of-transfer upload, and a submit action.

**Submitting the proof lifts the block immediately.** The customer does not wait for anyone to check it. This is deliberate and unusual — say it plainly, because a customer who assumes they are waiting on an admin will not try to book again.

**The blocked state**, shown wherever a new booking is attempted while a fee is owed: new bookings are on hold until this is settled, **existing bookings are unaffected, and the account is not suspended**. That distinction is the whole difference between a nudge and a punishment.

---

## Fixed sample data — use these exact values

**The customer:** `Aishath Nazim`.

**Three bookings**, enough to show the range:

| Service | Provider | When | Amount | Status |
|---|---|---|---|---|
| `Home Deep Cleaning` | `Mariyam Shifa` · Silver | `Tue 25 Aug · 14:00` | `MVR 450` · Agreed price | Confirmed |
| `Emergency Plumbing & Pipe Repair` | `Ibrahim Rasheed` · Gold | `Tue 25 Aug · 14:00` | `MVR 650` · Quoted price | Awaiting payment |
| `Emergency plumbing call-out` | `Ibrahim Rasheed` · Gold | `Today` | `MVR 350` · Callout fee | Confirmed |

**The amendment:** `MVR 450` → `MVR 600`, proposed by Mariyam, reason *"Two extra rooms added on the day."*

**The dispatch fee:** `MVR 200`, reference `RP-4471-EMG`, against the emergency call-out booking.

**Phone numbers** — these appear on exactly one screen and nowhere else, ever:

- `Aishath Nazim` — `+960 779-2140`
- `Ibrahim Rasheed` — `+960 771-8455`

**Bank details** stay as pinned in session 4: Mariyam `7730 0000 145 872`, Rasheed Plumbing Services `7730 0000 291 604`, both Bank of Maldives. RaajjePro's own account for the dispatch fee is a **different** account — invent one and pin it, and make it visibly not a provider's.

---

## States

Loading, error and populated everywhere. Beyond that:

- **My bookings** — empty overall, and at least one filter that is empty while others are not.
- **Detail** — the statuses *are* the states. Cover at minimum: awaiting payment, payment sent, confirmed, completed, and one unhappy path (disputed or unresolved).
- **Amendment** — proposing, sent and awaiting the other party, accepted, rejected; and the receiving side's decision state.
- **Reveal** — not yet requested, revealed, expired after 24 hours, and switched off.
- **Dispatch fee** — owed, proof submitted with the block lifted, and the blocked state as it appears when a new booking is attempted.

---

## The rules that never bend

1. **No phone number appears anywhere except screen 4**, in any state, on any other screen.
2. **A revealed number is never "verified."** It was confirmed at verification. No check mark, no shield.
3. **The reveal is mutual** — never design a state where one party has the other's number and not vice versa.
4. **The dispatch fee is a proof-and-admin mechanism; booking payment is a two-sided attestation.** Never blend the two treatments.
5. **Submitting proof lifts the block** — not admin confirmation.
6. **An unsettled fee blocks new bookings only.** Not existing bookings, not the account.
7. **A locked agreement is not escrow.** RaajjePro records terms and holds no money.
8. **Every amendment attempt is recorded**, accepted or not, and feeds price adherence.
9. **Money is whole rufiyaa** — `MVR 450`, never `MVR 450.00`.
10. **Import the components.** Twelve status labels live in `StatusPill`; tier copy lives in `VerificationBadge`.

---

## Check the prop combinations

This session has the largest illegal-combination surface so far, because most actions are gated by booking mode *and* status at once. Before you finish, enumerate what your props allow and confirm each combination describes a booking that could exist:

- **Reveal contact** requires emergency **and** `accepted`-or-later. Both, not either.
- **`Provider has not arrived`** requires emergency **and** an elapsed window.
- **Amendment** requires a booking that has been accepted — nothing is locked before that, so there is nothing to amend.
- **Rate** requires `completed`. **Mark complete** is the provider's action, not the customer's.
- **Withdraw payment claim** requires `payment_claimed` **and** no provider response yet.

---

## What I will be looking at hardest

Whether the two payment mechanisms stay visually and verbally distinct. You built the attestation one last session and built it well, which is exactly why the risk is real now: the safe move is to reuse a treatment that worked, and here that would tell a customer their bank transfer to RaajjePro is an unverified self-report, or that their payment to Ibrahim gets checked by staff. Both are wrong in opposite directions.

Second: whether the reveal screen resists being made convenient. Every instinct will be to reduce it to one tap with a reassuring tick. It is a narrow, audited, mutual, expiring exception to the strictest rule in the product, and the screen should feel like that without feeling like a warning.
