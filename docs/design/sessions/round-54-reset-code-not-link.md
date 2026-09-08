# Round 54 — the reset is a code, not a link

One screen, one mechanism. `Forgot Password.dc.html` only.

**Leave alone:** the layout, the four states and the order they run in, every
colour, radius, icon, animation and piece of copy not named below. The lock
hero, the inbox card, the requirement row, the "every device signs out" notice,
the expired card and the security footer all stay exactly where they are. No
screen gains or loses a step, and no other artboard is touched.

---

## Why

The artboard sends a **reset link**. The built app sends a **six-digit code**,
and the change is not cosmetic — a link needs somewhere to land.

Opening a link inside the app needs universal links (iOS) and app links
(Android), plus a domain to host them on and a web fallback page for anyone
without the app installed. **All of that is Phase 16** (§Phase 16, "Deep links
/ web fallback"), and the domain does not exist until deployment. Shipping the
link now would mean shipping a step nobody can complete and no test can cover.

The plan's own text for this phase asks for a **token**, not a link — §Phase 3b:
"Reset-token issuance, expiry, consumption". And this exact question was already
settled once, one phase earlier: §Phase 3's Done-when said "an email
confirmation link verifies" until 2026-09-08, when it was corrected to the
six-digit OTP the mechanism had always been. `Verify Email.dc.html` is the
result, and it is the model here — same six boxes, same resend countdown, same
five-attempt rule.

Approved 2026-09-08. Everything else about this screen was right.

---

## 1. Step one — the request

**"Forgot Password?"** and the lock hero are unchanged.

- Body copy: "No worries. Enter your email and we'll send you a **code** to
  reset your password." (was "a link")
- Primary button: **"Send Reset Code"** (was "Send Reset Link")

## 2. Step two — check your inbox

The card, the mail icon and the heading **"Check your inbox"** are unchanged,
and so is the thing that matters most about this state: **the sentence must
stay identical whether or not the address is registered.** The server answers
the same either way and this screen must not become the place that leaks it.

- Card body: "If {{ sentTo }} has a RaajjePro account, a password reset **code**
  is on its way to it."
- The amber pill: **"The code expires in 30 minutes"**. Thirty minutes is
  unchanged — it is the built value.
- Add the **six-digit code entry** beneath the card, the same component
  `Verify Email.dc.html` uses. Below it, a primary **"Continue"** which is
  disabled until six digits are entered and shows "Checking…" while in flight.
- The resend affordance keeps its countdown and its "Resend link" becomes
  **"Resend code"**.
- **Delete the prototype-only escape hatch** at the bottom of this state — the
  small "Prototype: open the emailed link →" button. It exists only because
  there was no way to arrive at step three; the code entry is that way now.

### The wrong-code states this step now needs

Both mirror `Verify Email.dc.html` exactly — same treatment, same wording:

- **Wrong code:** the six boxes turn red and clear, with the error beneath:
  "That code isn't right — {{ n }} attempts left before it needs a fresh send."
- **Fifth wrong code:** the flow moves to the expired card below, which carries
  "That code was invalidated after 5 incorrect attempts." in place of its
  usual body line.

## 3. Step three — set a new password

Unchanged apart from what reaches it. "Set a new password", "For {{ sentTo }}",
the 8-character requirement row, both fields with their reveal toggles, the
mismatch message and the blue "every device signs out" notice all stay as they
are. It is now reached by entering a valid code, not by following a link.

## 4. The fourth state — expired

- Heading: **"This reset code has expired"** (was "This reset link has expired")
- Body: "Reset **codes** work for 30 minutes. This one has passed that — request
  a fresh **code** and use it right away."
- Button: **"Request a New Code"** (was "Request a New Link")

## 5. The footer

- "Reset **codes** expire after 30 minutes for your security"

---

## What must not change

- **The confirmation stays identical for a registered and an unregistered
  address.** This is the one rule on this screen that is a security property
  rather than a preference (`09-identity.md`), and the code entry sitting under
  the card must not become a tell — it renders the same either way.
- **No SMS, anywhere.** No phone icon beside the code entry, no "send by text"
  alternative, no phone number on this screen at all.
- Nothing here signs the user in. Saving a new password ends at Sign In.
