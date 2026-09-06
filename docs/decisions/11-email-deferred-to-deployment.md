# Email delivery is deferred to deployment

**Decided 2026-09-06 by the owner. Recorded in the plan as §0.0 item 17,
revision 5.20.** Build the app first; procure the email vendor last.

This is the decision. The running list of what it leaves unproved lives in
`docs/deferred-verification.md`, rows L1–L7 — that file is appended by every
phase and worked through at deployment.

## The decision

No AWS account, no SES identity, no production-access request is a
prerequisite for any phase before deployment. Every email-dependent flow is
built and verified against `EMAIL_TRANSPORT=file`, which Phase 2 already
ships: each message is written as JSON into `backend/.mail/`, so an OTP is
read out of the written file exactly as a test would read it from a mailbox.

This reverses the sequencing Round 13 fixed. That reversal is deliberate, and
its cost is carried in the ledger rather than absorbed silently.

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
