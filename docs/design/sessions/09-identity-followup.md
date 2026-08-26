# Session 8 corrections — two screens missing, one invented field

The three artboards that exist are strong, and the constraints that matter most held. Sign-in failure is one undifferentiated message with both values kept. Registration blocks a duplicate email **at the field** with routes to sign in or reset, and blocks a duplicate phone **only** for a verified provider account — the correct scoping. The provider variant's business-name field carries the right disclaimer about Become a Provider. Verify Email is email-only throughout, with a real resend countdown, a rate-limit wait rather than an error, the 5-attempt invalidation, and an honest "I'll do this later." No phone number anywhere wears a check mark. Third-party icons are labelled placeholders rather than hotlinked assets, and the legal links are marked as placeholder pages.

Five things.

---

## 1. Forgot Password is missing — and two screens already link to it

The brief asked for a `Forgot Password` artboard with four phases: `request` → `sent` → `set_new` → `link_expired`. It wasn't built. Two existing screens already point at it:

- `Sign In.dc.html` — the "Forgot password?" link, `href="./Forgot Password.dc.html"`
- `Register.dc.html` — the duplicate-email block's "Reset password" link, same href

Both are dead. Build it, four phases on one artboard:

- **request** — this one has a mockup (`ForgotPassword.jpg`): email field, send action. The confirmation must be **identical whether or not the address is registered** — the screen may never reveal whether an account exists. That is the whole design constraint here.
- **sent** — the address it went to, a resend action with a countdown, a route back to sign in. State that the link **expires in 30 minutes**.
- **set_new** — new password and confirm, both obscured with a reveal, **requirements stated before submission rather than only on failure**, and the honest scope line: signing in again will be needed **on every device**, because all other sessions end.
- **link_expired** — the link has expired, with a route to request a fresh one.

## 2. The two app states are missing

`Session expired` and `No connection` weren't built either. Both are small; one artboard with a `state` prop is fine.

- **Session expired** — a sign-in-again action, and one promise that must be kept: whatever was being typed is **kept and restored** after signing in. Nothing on this screen may suggest work was lost.
- **No connection** — `No internet connection.`, a retry, and the load-bearing fact: **three things keep working offline and send when the connection returns** — saving a step of the service wizard, accepting a booking, and sending a message. Each shows a pending state; `pending_offline` on `StatusPill` is the established treatment, so import it rather than restyling one. Nothing may claim a booking was made or a payment recorded while offline.

## 3. Register invents an island picker, and hardcodes the list

`Register.dc.html` adds a **Your Island** select between phone and password, with eight named islands plus "Another island…". Two problems.

The field isn't specified. Registration collects **full name, email, phone, password** — plus business/trade name for a provider, which the brief calls "the additional field, and the only difference." An island on the account at registration isn't in the plan, and adding one here quietly decides something about how customer location works that no phase has decided.

And the list itself is exactly what the redesign plan flags as outstanding: the real island seed list does not exist yet, and every screen that renders a picker is supposed to show placeholder islands **with a note saying so**. This one presents eight islands as though they were the list.

Remove the field. If you think registration genuinely needs it, say so and leave it out for now — that's a plan question, not a design one.

## 4. Sign In's "Remember me" isn't a thing the product has

The checkbox implies a choice about session persistence. What exists is JWT access plus refresh rotation with per-device refresh tokens and a revocable session list — there's no "remember me" concept, and no specified behaviour for the unchecked case. A control that promises a choice the backend doesn't offer is the kind of thing that gets built and then quietly does nothing.

Remove it. The row keeps "Forgot password?" on the right, which is where it already sits.

## 5. Verify Email states one rate limit; there are two

The blue note reads:

> Codes are limited to 3 per address every 15 minutes.

Correct, and incomplete — there's a second send limit that applies independently: **5 per account per hour**. A user who hits the hourly ceiling while the 15-minute window looks clear will read the current copy as a bug. Add it:

> Codes are limited to 3 per address every 15 minutes, and 5 per account each hour.

---

## Two small things, take or leave

**Link hrefs use literal spaces.** The new screens link as `./Forgot Password.dc.html` and `./Sign In.dc.html`; every other artboard in the project URL-encodes (`Booking%20Detail.dc.html`, `Mute%20Block%20Decline.dc.html`). Match the existing convention.

**The email examples drift from the delivered mockup.** The brief's example address is `aishath@example.mv`; the screens use `you@example.com` and `ahmed@example.com`. The `.mv` domain is a small piece of local texture worth keeping.

**The "Prototype · code 482913" chip** is a good testing affordance and reads honestly. Keep it — just be aware it is prototype-only scaffolding, not UI.

---

## Leave alone

Everything else on the three built screens. Specifically: the sign-in failure copy and its retained values; the Apple/Google/Facebook/Viber set and their placeholder icon treatment; the guest-browsing line; the in-screen role toggle and the provider disclaimer; both duplicate-block treatments and their scoping; the `+960` default with the 6–15-digit foreign-number hint; the terms/privacy placeholder marking; and every state of Verify Email — entry, resent, wrong code with attempts remaining, invalidation, rate-limited wait, success.
