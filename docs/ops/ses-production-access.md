# SES production access — the owner's runbook

**Status: deferred to deployment (2026-09-06). Plan revision 5.20, §0.0 item 17.**

The steps below are correct and unchanged — only their timing moved. The app
is built first against `EMAIL_TRANSPORT=file`; this runbook is run early in
the deployment phase, not before Phase 3.
`docs/decisions/11-email-deferred-to-deployment.md` holds the ledger of what
stays unverified until then, and it is the checklist to work through here.

**§2 is incomplete:** the custom MAIL FROM subdomain also needs an MX record,
not only the SPF record named there. Take the exact records from the SES
console when you configure the subdomain.

This is a checklist for whoever holds the AWS account, not a build task. The
build-side work it depends on — bounce/complaint handling, the suppression
list, the per-message delivery log — is done as of this phase
(`docs/decisions/10-phase-2-backend-core.md`). Nothing here has been run
against a real AWS account yet; see §9.

## 1. Why this exists

A new SES account starts in the **sandbox**: 200 messages a day, and only to
addresses you have individually verified. Requesting **production access**
lifts that, but AWS requires attesting that bounces and complaints are
handled and a suppression list is honoured before every send — otherwise SES
itself becomes the thing that damages the shared sending reputation of the
whole service. That handling exists now (root `CLAUDE.md` invariant 10; plan
§0.0 item 8 / §4 Sequencing place it in the Phase 0–2 window; it was built
in Phase 2 and is what the attestation below is about). §0.0 item 17
since moved the AWS half of this to deployment.

## 2. Domain identity

- Verify the sending domain in SES, in the region you choose (`ap-south-1` is
  the default assumption — put whichever region you pick in `AWS_REGION`).
- Enable **Easy DKIM** and publish the three CNAME records SES gives you at
  your DNS provider.
- Add an SPF record: `v=spf1 include:amazonses.com -all`.
- Add a DMARC record: `v=DMARC1; p=quarantine; rua=mailto:<address>` — replace
  `<address>` with a mailbox you actually read.
- Configure a **custom MAIL FROM subdomain** (e.g. `mail.raajjepro.com`) so
  the envelope-from domain matches the sending domain.

## 3. Three configuration sets

Create three SES configuration sets, matching the three independently
killable channels (root `CLAUDE.md` invariant 10; the kill switches themselves
are Phase 10b):

| Configuration set | Environment variable |
|---|---|
| `raajjepro-otp` | `SES_CONFIGURATION_SET_OTP` |
| `raajjepro-notification` | `SES_CONFIGURATION_SET_NOTIFICATION` |
| `raajjepro-marketing` | `SES_CONFIGURATION_SET_MARKETING` |

Keeping them separate keeps their reputation metrics (bounce rate, complaint
rate) separate — a bad marketing send should never threaten the OTP channel.

## 4. One SNS topic

Create a single SNS topic, `raajjepro-ses-events`. Its ARN goes in
`SES_EVENTS_TOPIC_ARN`. All three configuration sets publish to this one
topic; the webhook distinguishes events by their content, not by topic.

## 5. Event destinations

On **each** of the three configuration sets, add an event destination of type
SNS, pointing at `raajjepro-ses-events`, publishing: Send, Delivery, Bounce,
Complaint, Reject, DeliveryDelay, and Rendering Failure. All seven, on all
three sets — the per-message log (`email_message` / `email_event`) is built
to record any of them.

## 6. HTTPS subscription

Subscribe the topic to an HTTPS endpoint:

```
https://<api-host>/v1/webhooks/ses-events
```

The API confirms the subscription automatically (it handles
`SubscriptionConfirmation` by fetching `SubscribeURL`, after checking the URL
is genuinely an AWS SNS host) and logs `sns subscription confirmed`. To
verify the subscription is live and events are landing:

```sql
SELECT count(*) FROM email_event;
```

A growing count after a real send confirms the pipeline end to end.

## 7. Production access request

In the AWS Console: **Service Quotas → Amazon SES → Request production
access** (or the SES console's own "request production access" form,
depending on region).

- **Mail type:** Transactional
- **Website URL:** the RaajjePro marketing or app site
- **Use-case description:** the text below is a **draft for the account
  owner to edit before submitting** — it is not final legal or compliance
  language, only a starting point that describes what this system actually
  does:

  > RaajjePro is a local services marketplace for the Maldives. We send
  > transactional email only: one-time passcodes for account verification,
  > booking-related notifications, and admin alerts. Estimated volume is
  > [FILL IN — expected sends/day at current user count]. Recipients are
  > registered users who created an account and, where applicable,
  > requested the notification (e.g. a booking update). Bounces and
  > complaints are consumed through an SNS event destination on every
  > configuration set, recorded per message, and used to maintain a
  > suppression list that is checked before every send — a suppressed
  > address is never sent to again without a manual admin action.
  > Marketing email, if sent at all, is opt-in only and runs through a
  > separate configuration set from transactional mail.

## 8. After approval

1. Set `EMAIL_TRANSPORT=ses` in the deployment's environment (never in a
   committed file — see `backend/.env.example`'s own strategy note).
2. Send one test message through the OTP channel to a real mailbox you
   control.
3. Confirm a `Delivery` event row appears in `email_event` for that message,
   and that `email_message.status` reaches `delivered`.

## 9. What is unverified until then

Nothing in this checklist has been exercised against a live AWS account from
this build. Specifically unverified:

- **A real send through SES** — `SesEmailTransport` is implemented and unit
  tested against a fake, but no message has gone through the real SESv2 API.
- **A real SNS delivery** to the webhook — the signature verification,
  topic check, and event handling are tested against a test-generated RSA
  keypair and synthetic payloads, not a live SNS notification.
- **The subscription handshake itself** — `SubscriptionConfirmation` handling
  is unit tested; no real `SubscribeURL` has been fetched.

All three become verifiable only once the account owner completes the AWS
steps above.
