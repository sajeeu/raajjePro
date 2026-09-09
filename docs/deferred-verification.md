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
| L9 | A Flutter exception reaching Sentry. The Phase 3 `CrashReporter` interface and its no-op-without-`SENTRY_DSN` implementation are built and tested (`frontend/lib/core/crash/`), matching Phase 2's backend posture, but nothing has run against a real Sentry project — this build has no real DSN. | A forced test exception in a build with a real DSN appears in the Sentry project within minutes. |
| L10 | The password-reset mail reaching a real inbox with its six-digit code readable, and its subject rendering as intended. Phase 3b verified the whole request → verify → confirm → sign-in cycle against `EMAIL_TRANSPORT=file`, reading the code out of the written message. | After L1, request a reset for an address you control; the code from that inbox sets a new password. |

## Open — closed by a push vendor

Separate from the AWS rows above because they close on different accounts, at
different moments, and neither is AWS. §Phase 3c's first Done-when clause — "a
test push arrives on a real device within seconds" — is recorded as met
**against the fake**: the interface, registration, refresh, multi-device
fan-out, token cleanup, the OS-denied state and every rung of the fallback
chain are all built and tested, asserting what the sender was asked to do. A
real device is the one thing a fake cannot prove.

Deferred by the owner on 2026-09-08, before the phase started;
`docs/decisions/15-phase-3c-push.md` explains it. `PUSH_TRANSPORT=fcm_apns` is
refused at config load until these close.

| # | What is unverified | Closed by |
|---|---|---|
| L11 | **A real push arriving on a real Android device via FCM.** Phase 3c built `PushSender`, the transport boundary, device registration/refresh/multi-device, the OS-permission-denied state and every rung of the fallback chain against a fake (`RecordingPushTransport`), asserting what the sender was *asked* to do. No Firebase project exists and Phase 3c deliberately procured none (`docs/decisions/15-phase-3c-push.md`). | Create a Firebase project, build the FCM transport behind the existing `PushTransport` interface, register a real device, and see a test push arrive on it within seconds — then its ack land at `POST /v1/push/dispatches/:id/ack` and the 30-minute fallback email NOT go out. |
| L12 | **A real push arriving on a real iOS device via APNs.** Same build, same fake; a separate row because an Apple developer account carries a fee and a lead time a Firebase project does not, so this will close later than L11. | An APNs key on a paid Apple developer account, the APNs transport behind the same interface, and a test push arriving on a real iPhone within seconds, with the same ack assertion as L11. |

## Open — closed by a later phase

| # | What is unverified | Closed by |
|---|---|---|
| P1 | A deleted account's reviews remain with anonymised attribution. Phase 3 built `AnonymisationHooks` and tested that a registered hook runs in the anonymisation transaction. | Phase 11 registers the review hook and its test asserts a review survives with the author anonymised. |
| P2 | A deletion request with an open booking completes automatically when that booking terminates. Phase 3 built the `DeletionBlocker` seam and tested it with an injected blocker. | Phase 17 supplies the real blocker; its test creates a booking, requests deletion, terminates the booking and sees anonymisation on the next run. |
| P4 | **A category's `bookingMode` cannot change once it has published slots or live bookings** (plan §Sequencing, Round 15 follow-ups). Phase 4 seeds the mode and `PATCH /v1/admin/categories/:id` accepts a change to it unconditionally, because there is no `Listing` and no `Booking` to check against — the refusal has nowhere to read from. Invariant 4 means it has to be a server-side refusal when it lands, not an admin-UI control. | Phase 9a (published slots) and Phase 17 (live bookings) give the check something to read. Whichever lands second adds the refusal to `CategoryService.update` and a test that seeds a category, gives it a published slot or a non-terminal booking, and sees the mode change rejected — plus the same question for deactivating a category that still carries live listings. |
| P5-1 | **`findVisibleProviders` includes a provider the moment a real listing is published.** §Phase 5 is sequenced before §Phase 8, so there is no `Listing` table to publish. The §1a rule is built and tested — draft-only excluded, published included, unpublished excluded again, a suspended provider excluded from all three consumer shapes, and `information_schema` asserted to hold no stored visibility column — but every one of those runs **against the `PublishedListingSource` seam** (`FakeListings`), not against a listing. | Phase 8 implements `PublishedListingSource` over the real `listing` table and its test publishes a draft, sees the provider appear through `findVisibleProviders`, unpublishes it, and sees them go. The same test should fold the published-listing predicate into the candidate query and drop the batch-accumulating loop (`docs/decisions/17-phase-5-provider-profiles.md` decision 2). |
| P5-2 | **§1f's conduct numbers are the ones the booking log actually produces.** Phase 5 built the read surface — the DTO shape, the ten-completed-booking floor measured against the 90-day window, the provider-sees-their-own-first rule, and the structural absence of any field an editorial label could occupy — all **against the `ProviderConductSource` seam** (`FakeConduct`). No metric has been computed from a booking, because there are no bookings. | Phase 11 implements `ProviderConductSource` over the booking event log and its test drives real bookings to terminal states, then asserts each of the seven §1f definitions against the resulting numbers — in particular that a customer cancellation does not move `cancellationRate`, that a timeout feeds response rate and not acceptance, and that on-time covers emergency against the accepted offer's `etaMinutes` (Round 22). |
| P5-3 | **The three consumers named in §Phase 5's suspension Done-when reach the rule through the one helper.** "Verified from search, Home, and the public profile in one test" names Phases 15, 16 and 13, none of which exists. Phase 5's test exercises the three *shapes* — a filtered page, an unfiltered page and a by-id check — and asserts all three exclude a suspended provider. What it cannot assert is that the eventual endpoints call this helper rather than rebuilding the rule. | Whichever of Phases 13, 15 and 16 lands last adds a test that suspends a visible provider once and asserts they disappear from all three real endpoints — and a check that no consumer reimplements the published-listing count or adds its own suspension filter (§1a: suspension is an input to the helper). |
| P5-4 | **That the payment-step exception is actually scoped to a booking.** §Phase 5's last Done-when allows payment details in exactly one place, and `paymentDetailsForBooking` is that place — but it takes no viewer on purpose, because the booking-scoped authorization belongs to the phase that can see a booking. Phase 5 asserted the line by calling the accessor directly, which proves the *mechanism* (nothing else in the module can reach the fields) and proves nothing about the scope. | Phase 17.1 calls it from the payment step only, after authorizing the caller against the booking, and its test asserts: the customer on the booking gets the details at `awaiting_payment`; a signed-in stranger gets 403/404 on the same booking; no other booking endpoint's response carries them at any status; and no route exposes the accessor. |
| P6-1 | **That the role switcher's first switch actually reaches onboarding, and a later one the dashboard.** §Phase 6's last Done-when line names two screens that do not exist. What is verified today is the whole decision and the routing: `RoleSwitch.destinationFor` is asserted both ways, and `frontend/test/features/profile/phase6_done_when_test.dart` drives the real app — a customer's switch lands on the route §Phase 6a owns and a provider's on the route §Phase 10 owns, each identified by the `UnbuiltScreen` naming its phase. What cannot be asserted is that the screens behind those two names are the onboarding intro and the dashboard. | Phase 6a replaces `/become-a-provider`'s placeholder and asserts a first switch lands on the **intro screen, not the wizard** (its own Done-when); Phase 10 replaces `/provider/services` and asserts a returning provider lands on the dashboard. Whichever lands second should also assert the pair in one test, so the two branches are never verified only in isolation. |
| P6-2 | **That Profile's three unbuilt rows reach the screens they name.** Saved, Saved preferences and Help & support navigate — each to an `UnbuiltScreen` carrying its own title and owing phase, asserted per row — but a placeholder is not the screen. | Phase 14 (Saved), Phase 7 (Saved preferences — it needs `Island`, which is why Phase 3 deferred it and Phase 6 did not take it) and Phase 19b (Help & support), each replacing its route and deleting the assertion that names it unbuilt. Phase 14's own Done-when adds "Profile's count updates", which is also when `profile-summary` gains its first count. |
| P6-3 | **That the four booking tiles land on the tab each one names.** Round 48 §2's defect was four labels reaching one screen, so each tile has its own destination and the test asserts all four are distinct — but all four are placeholders today, and `My Bookings` has no tabs to deep-link into. | Phase 17 builds My Bookings with its four tabs and wires each tile to its own, then asserts the four land on four different tabs rather than four different placeholders. |
| P6-4 | **That a customer can change their own name from the app.** `PATCH /v1/users/me` is built and tested end to end (`backend/test/customer-profile.test.ts`) — it is met **for the mechanism**. It has no caller: neither `Profile_customer.jpg` nor `Profile.dc.html` carries a name-edit control, so Phase 6 built none rather than inventing one (`docs/decisions/18-phase-6-customer-profile.md`, decision 3). | A design round adding the affordance to `Profile.dc.html`, then the phase that implements it. Until then the endpoint is reachable only by an API client, which is a real gap in the product and not a defect in this phase. |

## Closed

Rows move here with what was actually seen, so the ledger reads as a record
afterwards rather than an empty promise.

| # | What was unverified | Closed by | Closed on | What was seen |
|---|---|---|---|---|
| P3 | A password-reset attempt for an unverified email is refused without revealing existence. | Phase 3b | 2026-09-08 | `PasswordResetService` calls `assertRecoverableByEmail` and turns the throw into a silent non-send. `backend/test/auth-password-reset.test.ts` asserts it three ways: an unregistered address and a live one return byte-identical bodies with the same status; an unverified address returns that same body, receives no mail and creates no `email_otp` row; and an unknown address fails `verify` with the same `OTP_EXPIRED` a stale code gets. A frozen account is covered by the same path. |
