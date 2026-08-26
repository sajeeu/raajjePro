Build the identity surface: **Sign in**, **Create account** (both variants), **Verify your email**, the **forgot-password flow** (request → check your inbox → set a new password), and the two app-level states — **Session expired** and **No connection**.

**Attach:** `Login.jpg` · `Register_customer.jpg` · `Register_serviceProvider.jpg` · `ForgotPassword.jpg`. All four were audited against the plan and needed **no correction** — this session is the rare one where the image is right. The job is fidelity: match the delivered mockups, then add the states a JPEG cannot show. Where a screen has no mockup (verify email, check inbox, set new password, session expired, no connection), it inherits the identity screens' own vocabulary, not a new one.

**Import the components**: `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` · `SkeletonCard` · `EmptyState` are sibling files. `StatusPill` carries `pending_offline`, which No Connection will need.

Suggested artboards — group where only data differs, your call on the split:

- `Sign In` — plus its failure state
- `Register` — one artboard, `role: customer | provider`; the provider variant adds exactly one field
- `Verify Email` — entry, resend countdown, rate-limited, wrong-code states
- `Forgot Password` — one artboard, phases `request | sent | set_new | link_expired`
- `App States` — `session_expired | no_connection` (or two small artboards)

---

## The rules that shape this session

**There is no SMS anywhere in this system.** The verification code goes to **email**, the reset link goes to **email**, and nothing on any screen may offer to send anything by text. If a state renders "send via SMS," a phone icon next to a code entry, or copy implying a text message, it is a defect.

**A phone number is never verified here.** Registration collects it, nothing checks it. No check mark, no "we'll verify this," no green tick after typing. It is user-supplied text until an admin confirms it at Bronze — which is nowhere near these screens.

**Failure copy never reveals what exists.** Sign-in failure is one message that doesn't say whether email or password was wrong, with entered values kept. Forgot-password confirmation is *identical* whether or not the address is registered. The single deliberate exception: **registration** blocks a duplicate **at the field, naming it** — an in-use email says so at the email field with routes to sign in or reset; an in-use phone blocks **only if it's held by a verified provider (Bronze or above)**, otherwise it is accepted without comment, because an unverified number may legitimately be held by several accounts.

---

## Screen notes beyond the mockups

**Sign in.** Third-party sign-in as delivered: Apple, Google, Facebook, Viber — **Apple must be present wherever the others are**. Provider icons are uploaded assets, never hotlinked. The guest fact belongs somewhere quiet: browsing, searching and viewing need no account; signing in is for saving, booking and messaging.

**Register.** Dial code defaults to `+960` but accepts 6–15 digits — resort guests and expatriate residents are real customers, so a foreign number is valid, not an error. Terms/privacy acceptance links to placeholder pages (never invent legal text). Create-account leads into Verify Email. The provider variant's one extra field is **Business or trade name** — and registering there does *not* make anyone a provider; if the screen says anything about it, it says the Become a Provider flow does that.

**Verify your email.** Six-digit entry, the address shown in full with **a way to correct it**, and a resend action with a **real countdown** — the rate limits are product facts, not error strings: 3 sends per address per 15 minutes, 5 per account per hour, 5 attempts per code before it's invalidated and a fresh send is needed. Design the rate-limited state as a wait ("try again in 4:32"), never a generic failure. Also carry the incentive honestly: booking, enquiring and messaging need this; browsing doesn't, and a "later" route exists.

**Forgot password.** Request (mockup) → check-your-inbox (address shown, resend with countdown, back to sign in) → set new password. The reset link expires in **30 minutes**. Set-new-password states its requirements *before* submission, not only on failure, and tells the truth about scope: **every device signs out** — all other sessions end. The expired-link state routes to a fresh request.

**Session expired.** One action — sign in again — and one promise, which must be true and must not be oversold: whatever was being typed is kept and restored after signing in. Nothing on this page may claim work was lost.

**No connection.** `No internet connection.`, a retry, and the load-bearing fact: **three things keep working offline and send on reconnect** — saving a wizard step, accepting a booking, sending a message — each with a pending state (`pending_offline` is the established treatment). Nothing may claim a booking was made or a payment recorded while offline.

## States and combinations

Every screen: its main state plus loading/error where it fetches anything (most of these don't — they're forms; their "error" states are the failure copy above). Watch:

- The verify-email rate-limit countdown and the resend countdown are different timers — don't render one as the other.
- The registration duplicate-phone block appears only for a Bronze-or-above holder; the accepted case shows nothing at all.
- Sign-in failure keeps both entered values; the reveal toggle doesn't reset.
- No state anywhere shows a check mark on a phone number or the word "verified" near one.

## Guardrails carried forward

- No SMS, anywhere, in any state.
- No password strength theatre beyond the stated requirements; no fabricated legal text — terms and privacy are clearly-marked placeholders.
- Third-party icons uploaded, never hotlinked; photos likewise.
- Money doesn't appear this session; neither do phone numbers as content (the register field collects one — placeholder `777-1234` style sample values are fine in the input, but never rendered as a verified fact anywhere).
- Emergency stays out of this session entirely.
