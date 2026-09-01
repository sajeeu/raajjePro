# Round 29 — uploaded receipts are analysed, and the result is advice

**Status: adopted as Round 29 (2026-09-01). Plan revision 5.15.**

## The decision

Every uploaded `PaymentSubmission` proof is checked against what the submission claims, and the findings render **beside the receipt image in the admin payment queue** (Phase 10a part 2).

**Checked per field, each resolving to one of three outcomes:**

| Field | Checked against |
|---|---|
| Reference code | the submission's own `RP-…` code |
| Amount | the period's price **for this provider** — `subscriptionPriceLaari`, never a global constant |
| Destination account | RaajjePro's account |
| Date | plausible for the period being paid |
| **Duplicate** | this image, or this transaction reference, already submitted against another period |

Outcomes are `matches` / `does not match — <found vs expected>` / **`couldn't read`**.

## The three things that make it safe

**1. It is advice, never a verdict.** No score, no traffic light, no "looks good" summary, no aggregate. It never uses the word *verified*, never auto-confirms, and never gates or pre-fills the confirm/reject decision. The admin confirming **is** the verification.

The failure mode being designed against is specific: an admin working a queue learns to trust a green summary, stops reading the image, and confirms a wrong or forged receipt. A per-field list of what was found forces the reviewer to look; a verdict invites them not to. This is the same reasoning as §1f's rejection of editorial conduct labels — show what was found, let the human conclude.

**2. "Couldn't read" is a first-class outcome.** These are phone photos of bank-app screens, across BML and MIB, often at an angle or cropped. Extraction failing is the ordinary case, not an exception. A design that models only match/mismatch will render "does not match" for an unreadable image and mislead the reviewer into rejecting a valid payment.

**3. The bank-statement CSV outranks the receipt.** The plan already has reference-code auto-matching against imported bank statements. That row is *the bank's own record of what arrived*; the receipt is *the provider's claim about it*. Where both exist and disagree, show both and label which is which. The receipt analysis must never silently contradict or override the statement.

## Admin-only, deliberately

The provider sees none of this. A pre-submission check would reduce rejections, but §1b's rule is that **nothing activates on submission** and *pending grants exactly what no payment grants* — and a green "all looks OK" at upload time sits one step away from reading as approval. The rejection path already carries the admin's reason verbatim with immediate resubmit and no cooldown, which covers the same ground honestly and after a human has actually looked.

Two alternatives were considered and declined: showing the provider the full check (risks implying pre-approval), and showing them failures only (safer, but still puts an automated judgement in front of the person being judged before any human has seen it).

## Scope

This is the **admin panel**, which is a separate React web app and has never been part of the thirteen-session design sequence. No prototype in `mockups/design-composer/` changes. This entry exists so the requirement is written down before the admin brief is drafted, rather than living only in a chat.
