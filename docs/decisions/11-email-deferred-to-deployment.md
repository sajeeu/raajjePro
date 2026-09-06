# Email delivery is deferred to deployment — the ledger

**Decided 2026-09-06 by the owner. Recorded in the plan as §0.0 item 17,
revision 5.20.** Build the app first; procure the email vendor last.

## The decision

No AWS account, no SES identity, no production-access request is a
prerequisite for any phase before deployment. Every email-dependent flow is
built and verified against `EMAIL_TRANSPORT=file`, which Phase 2 already
ships: each message is written as JSON into `backend/.mail/`, so an OTP is
read out of the written file exactly as a test would read it from a mailbox.

This reverses the sequencing Round 13 fixed. That reversal is deliberate and
its cost is stated below rather than absorbed silently.

## What this does not change

- **Bounce and complaint handling is built** — SNS event destination,
  per-message delivery log, suppression list honoured before every send
  (Phase 2, `docs/decisions/10-phase-2-backend-core.md`). The plan's §0.0
  item 8 is satisfied. Deferring the *vendor* does not defer the *handling*,
  and the handling is what the production-access attestation is about.
- **`EMAIL_TRANSPORT=ses` is still mandatory in production.** The config
  module refuses to start a production process on the file transport, and
  refuses `ses` without all five SES variables. That guard stays.
- **The email architecture.** SES remains the sole vendor (root `CLAUDE.md`
  invariant 10), three configuration sets, one SNS topic, everything sent
  through the `EmailSender` interface.
- **`docs/ops/ses-production-access.md` stays the runbook.** It is correct;
  only its timing moved.

## The ledger — what is unverified, and until when

Nothing here is a defect. Each line is a real thing that cannot be exercised
without a live AWS account, and each must be closed during deployment.

| # | Deferred | Closed by |
|---|---|---|
| 1 | A real send through the SESv2 API. `SesEmailTransport` is unit tested against a fake. | One OTP to a mailbox you control, then `email_message.status = delivered`. |
| 2 | A live SNS notification reaching `/v1/webhooks/ses-events`. Signature checking is tested against a test-generated RSA keypair. | A growing `email_event` count after a real send. |
| 3 | The `SubscriptionConfirmation` handshake. No real `SubscribeURL` has been fetched. | The log line `sns subscription confirmed`, once. |
| 4 | Suppression on a real hard bounce. | Send to `bounce@simulator.amazonses.com`; a row appears in `email_suppression`. |
| 5 | Suppression on a real complaint. | Send to `complaint@simulator.amazonses.com`; same check. |
| 6 | Domain deliverability — SPF, DKIM, DMARC alignment and the custom MAIL FROM. | The receiving mailbox's headers show all three passing. |
| 7 | That the three configuration sets keep their reputation metrics apart. | Three sends, one per channel, each landing under its own set in the SES console. |

**Phases add to this table, they do not close their own lines.** Any phase
that sends email — Phase 3 (OTP), 3b (reset), 3c (fallback), 10b (admin
alerting), 19 (notifications) — is *done* when its flow works on the file
transport, and adds a row here for whatever only a real mailbox can prove.
A phase must never record an email Done-when criterion as met on the grounds
that it will be checked later; it records it as met **against the file
transport**, in those words, and adds the line here.

## Two things that will bite if forgotten

- **Request production access early in the deployment phase, not at the end.**
  AWS answers in roughly 24 hours but can come back for more information, and
  this is now the last external dependency in the plan. Left to the end it
  becomes the thing that delays launch by itself.
- **The custom MAIL FROM subdomain needs an MX record**, not only the SPF
  record §2 of the runbook mentions. Without it, MAIL FROM verification never
  completes and SES silently falls back to `amazonses.com`. The SES console
  shows the exact records when the subdomain is configured — take them from
  there. (Found 2026-09-06 auditing the runbook; the runbook's §2 is
  incomplete on this point.)
