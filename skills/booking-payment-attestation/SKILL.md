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

Emergency bookings additionally REQUIRE `finalAmount` to complete — the real settled total after parts and labour. It gates completion exactly as `agreedAmount` gates `awaiting_payment`. It is the number a dispute needs, and the provider has no incentive to volunteer it.
