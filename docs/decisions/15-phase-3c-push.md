# Phase 3c — the push vendor, and the two rungs

*Decided 2026-09-08, before the phase started. Built the same day.*

## The vendor: a transport that is inert without credentials

§Phase 3c's first Done-when clause reads "a test push arrives on a real device
within seconds". That needs a Firebase project and, for iOS, a paid Apple
developer account with its own lead time.

It collides with the decision recorded at plan §0.0 item 17: no external
account is a prerequisite before deployment. `PushSender` therefore goes
behind a transport that is a no-op without credentials — the same posture as
Phase 2's `EmailSender` (`EMAIL_TRANSPORT=file`) and Phase 3's `CrashReporter`
(inert without `SENTRY_DSN`). That makes one rule across all three external
vendors rather than three separate judgements.

What ships:

- `PushTransport`, one call per device, with `platform` selecting the vendor so
  no caller ever branches on it.
- `FilePushTransport`, writing one JSON file per push into `backend/.push/`,
  exactly as the mail transport does.
- `PUSH_TRANSPORT=fcm_apns` **refused at config load**, naming the ledger rows
  that close it. A deployment that sets it fails to start with a message
  saying why, rather than believing pushes are going out.

**No `firebase_messaging` dependency in `pubspec.yaml`.** Adding it would
require a `google-services.json` to compile the Android app at all. The Flutter
side ships `PushMessaging` plus `UnavailablePushMessaging`, which reports
permission as `unknown` — never `denied`, because a missing vendor is not a
user's refusal.

### The one asymmetry with email, and why

`loadConfig` refuses `EMAIL_TRANSPORT=file` in production. There is
deliberately **no** matching "must be `fcm_apns` in production" rule for push.

Requiring a transport that is not built would make production unbootable
rather than safe. The honest posture is the one taken: refuse the unbuilt
value outright, and let the email fallback carry the notification. Push is the
fast path; email is what makes a notification reliable.

## The fallback chain

This is the part of the phase most easily got wrong, and the plan is explicit
about a revision that got it wrong before: an earlier one said "fails to
deliver within the acceptance window", and that window is 24 hours — so a
fallback could arrive at hour 23, on a booking that had died at hour two.

Three paths, decided before anything is sent, all in `dispatcher.ts`:

| Condition | What happens | Reason recorded |
|---|---|---|
| Emergency | Push **and** email in parallel, no ladder | `emergency_parallel` |
| Permission known `denied` | Email immediately, in parallel with the futile push | `permission_denied` |
| No live device registration | Email immediately | `no_registered_device` |
| Otherwise | Push, then email at **30 minutes** if unconfirmed | `unconfirmed_after_window` |

`FALLBACK_AFTER_MINUTES` is a constant, not a config knob, precisely so it
cannot drift back onto some other window.

**A vendor accepting a push is not delivery.** FCM and APNs both return an id
the moment they take the message, which says nothing about whether the phone
was on. Only the app calling `POST /v1/push/dispatches/:id/ack` sets
`confirmedAt`, and only that stops the 30-minute rung. Treating the provider
message id as confirmation would silently disable the entire second rung, so
there is a test whose only job is to catch that.

### The row the plan does not have: no registered device

§Phase 3c names two rungs. It does not say what happens to a provider with no
live device registration at all — never granted on any device, or every token
cleaned up. They are not "known denied" and push is not "permitted", so
neither rung's condition holds.

**Decided: treat it as the immediate-email rung, under its own reason code.**
The reasoning is identical to a denial — push cannot land, so waiting half an
hour only makes the provider late — and it is the same defect the plan's own
revision was written to fix. The separate reason code keeps the two
distinguishable in the 5% metric, so a push-integration regression still looks
different from users who turned notifications off.

Asked and confirmed with the owner before it was built.

## Observability

`NotificationHealth` computes two rolling-day rates and logs them with stable
`event` names. §Phase 21 wires those into APM; that is where "the alert fires
when forced above threshold" is proved end to end.

- **`notification.fallback_rate`** — scoped to `booking_accept_prompt` only,
  as the plan words it. Emergency dispatches email in parallel every single
  time by design; folding them in would peg the rate near 100% and the alert
  would stop meaning anything.
- **`email.reputation`** — bounce and complaint rates. Two thresholds because
  the 2% is ours and the 5% is AWS's: SES puts an account under review above
  5% and can pause sending above 10%, and losing email is not a degraded
  notification, it is no notification.

Neither alert sends an email. Phase 10b owns admin alerting and its recipient
configuration does not exist; and an alert about email delivery that is itself
delivered by email is a poor design regardless.

**A rate over zero sends is `null`, not zero, and never alerts.** A metric with
no data reads "no data", the same rule the UI follows.

The rolling window is bounded at **both** ends. `gte` alone makes "the rolling
day" mean "everything since yesterday, including the future" — wrong on its
face, and quietly wrong wherever rows carry a clock that is not the one asking.
Found by a test, not by review.

## The message log

§Phase 3c: "SES has no searchable activity UI, so the message log is ours to
build… Budget it here and surface it in Phase 10b."

Phase 2 built the store and the SNS event destination that fills it. What was
missing was a way to interrogate it, so this phase adds `EmailMessageLog` and
`GET /v1/admin/message-log`, shaped deliberately like the existing
`/v1/admin/audit-log` — same guard, same cursor pagination, same envelope. A
`push_dispatch` row points at the `email_message` it produced, so "did this
provider actually get the emergency alert?" is one lookup by user id. Phase 10b
adds the screen.

## Schema notes

- **The install is the identity; the token is a rotating credential.** A
  refresh updates the existing `device_token` row rather than adding one, so a
  device that rotates often does not accumulate dead registrations the sender
  then tries on every notification.
- **One live row per raw token across all accounts**, as a partial unique index
  on `revoked_at IS NULL`. A phone handed from one person to another must stop
  delivering the previous owner's booking notifications the moment the new
  owner registers. Prisma does not model partial uniques, so it is hand-written
  in the migration and `test/schema-phase3c.test.ts` asserts it.
- **`push_dispatch.context` holds what the copy is built from** — booking type,
  customer first name, island — because the 30-minute rung sends its mail from
  a job, long after the caller has gone. No address, no phone number, no
  amount is ever in it; the recipient is reached through `userId`.

## Content

§Phase 3c fixes the fallback mail exactly: booking type, customer first name,
job location island, an instruction to open the app. No links, no amounts, no
phone numbers.

The no-links rule is anti-phishing, not minimalism — a provider trained to tap
a link in a "you have a job" email will tap the next one too, and that one will
not be from us. The mail says so in as many words. The same restraint is
applied to the push payload, which the plan does not require but a lock screen
is no more private than an inbox.

`assertContentRules` runs on every built message, not only in tests, so a later
phase adding a notification kind gets the check whether or not it remembers to
write one.

## What is deferred

A real push arriving on a real device. `docs/deferred-verification.md` rows
**L11** (FCM) and **L12** (APNs) — separate rows, because a Firebase project is
free and quick while an Apple developer account has a fee and a lead time, so
they will close at different moments.

Every other clause of §Phase 3c's Done-when is met and tested now.
