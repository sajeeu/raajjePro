# Deferred verification ledger

**This file is appended by every phase and worked through at the end. It is
the only place a deferred check is recorded.**

A phase is done when the thing it built works. Some acceptance lines cannot be
proved when the phase that owns them is built — they need a live vendor
account, or a domain a later phase creates. That is normal and it is not a
defect. What is dangerous is recording such a line as *met* and moving on,
because nothing then remembers to go back.

So each one becomes a row here, with the specific thing that closes it.

## The rule

- **A phase never records one of these as met outright, and never as "checked
  later".** It records it as met **for the mechanism**, or **against the file
  transport** — in those words — and adds a row here.
- **Phases add rows. A phase does not close its own row** — the row is closed
  by whoever runs the real check, at the event or phase named in *Closed by*.
- **Closing means someone ran it**, and the row says what they saw. A row
  closed by reading the code was never open.
- **If a line is testable now, test it now.** Deferring something that could
  have been checked is the failure this file exists to prevent. A row is for
  what is impossible today, not what is inconvenient today.

## Open — closed at deployment

These need a live AWS account. Deferred by the owner on 2026-09-06; the plan
records the decision at §0.0 item 17 and
`docs/decisions/11-email-deferred-to-deployment.md` explains it. The runbook
to work through is `docs/ops/ses-production-access.md`.

| # | What is unverified | Closed by |
|---|---|---|
| L1 | A real send through the SESv2 API. `SesEmailTransport` is unit tested against a fake. | One OTP to a mailbox you control, then `email_message.status = delivered`. |
| L2 | A live SNS notification reaching `/v1/webhooks/ses-events`. Signature checking is tested against a test-generated RSA keypair. | A growing `email_event` count after a real send. |
| L3 | The `SubscriptionConfirmation` handshake. No real `SubscribeURL` has been fetched. | The log line `sns subscription confirmed`, once. |
| L4 | Suppression on a real hard bounce. | Send to `bounce@simulator.amazonses.com`; a row appears in `email_suppression`. |
| L5 | Suppression on a real complaint. | Send to `complaint@simulator.amazonses.com`; same check. |
| L6 | Domain deliverability — SPF, DKIM, DMARC alignment and the custom MAIL FROM. | The receiving mailbox's headers show all three passing. |
| L7 | That the three configuration sets keep their reputation metrics apart. | Three sends, one per channel, each landing under its own set in the SES console. |
| L8 | The OTP mail reaching a real inbox with the six-digit code readable, and the sender/subject rendering as intended. Phase 3 verified the whole register → verify → login cycle against `EMAIL_TRANSPORT=file`. | Register with an address you control after L1; the code from that inbox verifies the account. |
| L9 | A Flutter exception reaching Sentry. The `CrashReporter` interface is wired; without `SENTRY_DSN` it is a no-op. | A forced test exception in a build with a real DSN appears in the Sentry project within minutes. |

## Open — closed by a later phase

| # | What is unverified | Closed by |
|---|---|---|
| P1 | A deleted account's reviews remain with anonymised attribution. Phase 3 built `AnonymisationHooks` and tested that a registered hook runs in the anonymisation transaction. | Phase 11 registers the review hook and its test asserts a review survives with the author anonymised. |
| P2 | A deletion request with an open booking completes automatically when that booking terminates. Phase 3 built the `DeletionBlocker` seam and tested it with an injected blocker. | Phase 17 supplies the real blocker; its test creates a booking, requests deletion, terminates the booking and sees anonymisation on the next run. |
| P3 | A password-reset attempt for an unverified email is refused without revealing existence. Phase 3 built and tested `assertRecoverableByEmail`. | Phase 3b's reset flow calls it and its test asserts an identical response with no mail sent for an unverified address. |

## Closed

Nothing yet. Rows move here with what was actually seen, so the ledger reads
as a record afterwards rather than an empty promise.

| # | What was unverified | Closed by | Closed on | What was seen |
|---|---|---|---|---|
