# Phase 3b — Forgot Password, and why it sends a code rather than a link

**Status: built 2026-09-08. Plan revision 5.20, §Phase 3b, with §Phase 3's OTP
rules and §0.0 item 17 (email built against the file transport).**

Phase 3b is three steps: request a reset, read what arrives, set a new password.
The plan specifies the mechanism in one line — "Reset-token issuance, expiry,
consumption; invalidates all refresh tokens on success" — and the design was
delivered in Session 8 as `Forgot Password.dc.html`. This file records the one
place the build departs from that artboard, and the choices the plan leaves open.

## The decision that matters: a code, not a link

`Forgot Password.dc.html` sends a **reset link**. The build sends a **six-digit
code**. Approved by the owner on 2026-09-08 before implementation began.

A link has to land somewhere. Opening one inside the app needs universal links
and app links plus a domain to serve the association files and a web fallback
for anyone without the app — and **all of that is Phase 16** (§Phase 16, "Deep
links / web fallback"). The domain does not exist until deployment. Building the
link now would ship a step no one can complete and no test can cover, which
collides directly with the ledger's own rule: *if a line is testable now, test
it now.*

Three things point the same way:

- **The plan says token, not link.** §Phase 3b's Done-when is "request a reset,
  receive a token, and set a new password".
- **This exact question was settled one phase earlier.** §Phase 3's Done-when
  read "an email confirmation link verifies" until 2026-09-08, when it was
  corrected to the six-digit OTP the mechanism had always been — the clause
  contradicted the same section's "5 verification attempts per issued OTP",
  a rule with no meaning for a link.
- **The component already exists.** `OtpCodeEntry`, the resend countdown and the
  five-attempt invalidation are Verify Email's, unchanged.

The correction goes back to the design project as
`docs/design/sessions/round-54-reset-code-not-link.md`. Nothing else about the
artboard changes: the four states, their order, the 30-minute expiry, the
"every device signs out" notice and the expired card are all built as delivered.

## The decisions the plan left open

| # | Decision | Choice |
|---|---|---|
| 1 | Where the reset token lives | `EmailOtp` under a third `OtpPurpose`, `password_reset` — not a parallel table. The two send limits, the five-attempt invalidation, the sha256-at-rest and the delivery log are Phase 3's, already built and tested |
| 2 | Expiry | 30 minutes (`AUTH_PASSWORD_RESET_EXPIRY_MINUTES`), against an OTP's 10. The artboard's number, and a reset code is read out of a mailbox someone may have to go and open |
| 3 | Steps | Three endpoints, not two. `verify` checks the code **without spending it**, so the set-a-new-password screen opens on a code already known good; `confirm` re-checks and spends it. A wrong digit costs one attempt, not a re-typed password |
| 4 | What `confirm` returns | Nothing but success. No tokens: the flow ends at Sign In, so a reset prompted by a stolen session signs that session out rather than handing the flow a fresh one |
| 5 | Session revocation | `revokeAllSessions` with a new `password_reset` reason — every device, including whichever one asked |
| 6 | Non-disclosure | An unknown address, an unverified one and a frozen or anonymised account all return the **same body** from `request` and the same `OTP_EXPIRED` from `verify`/`confirm` that a real account with a stale code gets |
| 7 | A rate-limited resend | Swallowed into that same body. A 429 would be an existence oracle — only a real account accumulates the rows the limits count. Nothing is lost: being over the limit means three codes reached that inbox in the last quarter hour and the newest is still live |
| 8 | Route tiers | 10/hour per IP on `request`; 20/15 min per IP on `verify` and `confirm`, above the five-attempt rule so the fifth wrong code is answered by `OTP_INVALIDATED` rather than a 429 that hides it |
| 9 | Whether a reset may reuse the old password | Not specified by the plan, so not invented. The server enforces length only, as `change-password` does |

## What was built

**Backend.** `src/modules/auth/password-reset.ts` (`PasswordResetService`), three
routes under `/v1/auth/password-reset/`, `OtpService.check` (the non-consuming
match, factored out of `confirm` so both use one matcher), purpose-aware email
copy and expiry, and two additive enum values. `test/auth-password-reset.test.ts`
— 14 cases.

**Frontend.** `ForgotPasswordScreen` and `ForgotPasswordController`, one screen
rendering the artboard's four states, reusing `CircleBackButton`, `OtpCodeEntry`,
`CountdownText`, `InlineNotice`, `AppTextField` and `AppButton`. The
`_ComingSoon` placeholder `/forgot-password` used to point at is gone.
`test/features/auth/forgot_password_screen_test.dart` — 13 cases.

## Verification

Every Done-when clause was exercised end to end against `EMAIL_TRANSPORT=file`
on 2026-09-08, reading the six digits out of `backend/.mail/`: register → verify
→ request → verify code → confirm → sign in with the new password (200) → the
old password refused (401) → a pre-reset refresh token refused
(`SESSION_EXPIRED`). An unknown address returned a byte-identical body and wrote
no new file.

What a real mailbox would add — that the message arrives, and renders as
intended — is ledger row **L10**. Row **P3**, which Phase 3 opened for this
phase to close, is closed.
