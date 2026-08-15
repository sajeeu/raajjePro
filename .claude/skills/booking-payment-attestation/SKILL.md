---
name: booking-payment-attestation
description: Use when working on the booking payment flow, the "I've Paid" or "Payment Received" actions, disputes, or payment_unresolved. Triggers on mentions of attestation, claim-payment, confirm-receipt, dispute, or booking payment.
---
# Booking Payment Attestation

This is a TWO-SIDED SELF-ATTESTATION between customer and provider about an OFF-PLATFORM bank transfer. It is NEVER the `PaymentSubmission`/admin mechanism — that is exclusively RaajjePro's own subscription fees. Do not conflate the two systems.

- The customer taps "I've Paid" — self-attestation, NO proof upload. Status `payment_claimed`.
- The provider confirms or disputes. Confirm → `confirmed`. Dispute → `disputed`.
- SEVEN DAYS of provider silence → `payment_unresolved`, NOT `confirmed`. Both parties notified, a Report filed, and NOTHING further unlocked by the transition. An earlier revision auto-confirmed here, recording an attestation that may never have happened.
- Neither `disputed` nor `payment_unresolved` is terminal. An admin resolves both — disputes with a FIXED ENUMERATION (`resolved_for_customer`, `resolved_for_provider`, `inconclusive`, `fraud_confirmed`, `withdrawn`), never free text.
- Decline ≠ dispute. Separate endpoints, separate statuses, visually distinct in the UI.

HONEST FRAMING IS MANDATORY. RaajjePro has no visibility into the actual bank transfer and the UI must never imply otherwise:
- NEVER "Payment Verified". NEVER a lock or verified-checkmark on this flow.
- USE "Provider confirmed receipt."
- The whole experience here is waiting for a human decision, so status legibility and honest expectation-setting are the product. State what happens next and roughly when.

THE AGREEMENT LOCKS AT `accepted` (§1h, Round 15). Price, date, time and scope cannot be changed unilaterally — a change requires an explicit amendment the counterparty accepts, and EVERY attempt is recorded whether accepted or not, feeding price adherence (§1f). `finalAmount` above `agreedAmount` with no accepted amendment is a price-adherence failure, not just a number.

THIS IS WHAT "PAYMENT HOLD" MEANS HERE. DO NOT BUILD ESCROW, FUNDS HOLDING, OR A PAYMENT GATEWAY for bookings — holding customer money means payment-services licensing, and the plan deliberately obtains the anti-hiking and anti-no-show behaviour through the locked agreement instead.

ONE EXCEPTION TO "PaymentSubmission IS SUBSCRIPTIONS ONLY": the MVR 200 emergency dispatch fee (purpose `emergency_dispatch_fee`, Round 15) is money owed to RaajjePro by a CUSTOMER, and does use PaymentSubmission. It is incurred when the customer selects an emergency offer, never blocks dispatch, and the resulting new-booking block lifts on PROOF SUBMISSION rather than on admin confirmation.

Emergency bookings additionally REQUIRE `finalAmount` to complete — the real settled total after parts and labour. It gates completion exactly as `agreedAmount` gates `awaiting_payment`. It is the number a dispute needs, and the provider has no incentive to volunteer it.
