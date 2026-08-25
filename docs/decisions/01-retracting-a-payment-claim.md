# Plan question: can a customer retract "I've Paid"?

**Status:** open — needs a decision before Phase 17.1 is built.
**Raised by:** the session 4 Payment Step prototype, which shipped an undo control that the plan does not specify.
**Affects:** `01_Development_Plan_v5.md` §1c (the flow, steps 7–9), the state diagram, and Phase 17.1's endpoint list.

---

## The question

A customer taps **"I've Paid"** and the booking moves to `payment_claimed`. Can they take that back?

The plan does not say. Nothing forbids it and nothing provides it, so whoever builds Phase 17.1 will have to decide — which is how an unconsidered default becomes a shipped behaviour.

## What the plan specifies today

- Step 7: *"Customer taps 'I've Paid' — self-attestation, no proof upload. Status `payment_claimed`."*
- Step 8: the provider then confirms or disputes. Confirm → `confirmed`. Dispute → `disputed`.
- Step 9: provider silence for 7 days → `payment_unresolved`, resolved by an admin.
- The state diagram allows `cancelled` from `requested` only, annotated **"customer, pre-payment."**
- Phase 17.1's endpoints: create, accept, decline, **claim-payment**, confirm-receipt, complete, cancel.
- `Booking` already carries `paymentClaimedAt` and `statusHistory`.

So once the customer taps, **every remaining exit belongs to the provider or to an admin.** The customer has no way back.

## Why it matters

The tap is one button, reached immediately after acceptance, on a screen the customer sees while they are also switching to their banking app. A mis-tap is easy, and the consequence is not cosmetic: the provider is told money is on the way, and may travel, buy parts, or start work on that basis.

Today the only route out is for the customer to message the provider and ask them to press **"Payment Not Received"** — which sets `disputed` and drops the booking into the Phase 22 queue. That puts an honest mistake into an adversarial state, and consumes admin time on a booking where nobody did anything wrong.

**Note on scope:** retraction changes only the record. Money moved off-platform or it didn't, and RaajjePro never held it either way. This is a question about the honesty of the booking record, not about funds.

---

## Options

### A — Retraction while the claim is still unanswered *(recommended)*

Allowed **only** while status is exactly `payment_claimed` and the provider has not yet confirmed or disputed. Returns the booking to `awaiting_payment`, clears `paymentClaimedAt`, notifies the provider, and writes both transitions to `statusHistory` so nothing is erased. Once per booking, so it cannot be used as a toggle.

- **For:** fixes the actual failure without inventing a new state or a new queue. Keeps the record truthful — an attestation that was withdrawn is more honest than one left standing that both parties know is false. Reuses machinery that exists.
- **Against:** a second customer-side action to specify, build and test.
- **Sub-decision if you pick this:** is the window **open until the provider acts**, or **time-boxed** (e.g. 60 minutes from `paymentClaimedAt`, whichever comes first)? Open-until-provider-acts is simpler to explain and to build; time-boxing guards against a customer retracting days later after the provider has already travelled.

### B — No retraction; make the tap harder to make by accident

Add a confirmation step before "I've Paid" — *"Have you actually sent the transfer?"* — and leave the state machine untouched.

- **For:** preserves the current design's cleanest property: exactly one attestation per side, never revised. Nothing new to build in the domain layer.
- **Against:** does not fix the case it is meant to fix. A customer who taps through a confirmation dialog by reflex is in exactly the same position, with the dispute queue as their only exit.

### C — No retraction; route the correction through the existing dispute path

Add a customer-side *"I made a mistake — I haven't paid"* that sets `disputed` with an enumerated reason marking it customer-initiated rather than provider fault.

- **For:** builds nothing new; the dispute machinery and its admin queue already exist.
- **Against:** puts a self-corrected mistake in front of an admin, against a Phase 22 queue that already carries a 5-business-day resolution target and an alert above 25 open items. It spends the scarcest resource in the system on the one case that needs no adjudication.

### D — Retraction allowed any time before `completed`

- **For:** simplest rule to state.
- **Against:** lets the record be rewritten after the provider has already confirmed receipt, which turns a settled two-sided agreement back into an open one. This is the option to reject explicitly rather than leave unexamined.

---

## Recommendation

**Option A, with the window open until the provider acts.**

It is the only option that fixes the case without spending admin time on it, and the "until the provider acts" boundary is self-explaining in the UI — the moment the provider has responded, the customer's own correction is no longer the right instrument, and the dispute path is.

## If A is chosen, the plan changes in three places

1. **§1c step 7** gains a sentence: the claim may be withdrawn by the customer while it remains unanswered, returning the booking to `awaiting_payment`.
2. **The state diagram** gains a return arrow `payment_claimed → awaiting_payment`, annotated *"customer withdraws, provider not yet responded."*
3. **Phase 17.1's endpoint list** gains `withdraw-payment-claim` alongside `claim-payment`, and its Done-when gains: a withdrawal succeeds while unanswered, is rejected once the provider has confirmed or disputed, is rejected on a second attempt, and leaves both transitions visible in `statusHistory`.

## Also needs settling under any option

Whether a withdrawn or disputed payment claim touches **§1f conduct metrics**. The plan currently states conduct consequences for a declined callback claim only; it is silent on payment disputes. A mis-tap must not mark the provider, and that should be written down rather than assumed.

---

## Where this currently lives in the prototype

`mockups/design-composer/Payment Step.dc.html` carries an *"I haven't actually paid yet — undo"* control on the payment-sent state, with a source comment marking it as unspecified. **It is a placeholder, not a decision.** If B is chosen the control comes out; if A is chosen the comment comes out and the window rule goes in.
