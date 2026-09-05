# Phase 2 — the five defaults, and the one that changed

**Status: decided 2026-09-05, before implementation. Plan revision 5.19, §Phase 2.**

Phase 2's design proposed five defaults and asked whether they hold. Four do.
The fifth — verifying Amazon SNS signatures with hand-written code — is changed
to the `sns-validator` package.

This records the decisions. It is **not** the Phase 2 spec; the implementation
detail belongs with the build.

---

## 1. SNS signature verification — changed to `sns-validator`

**The proposal was in-house verification. It should not be.**

Verifying an SNS signature yourself means getting five separate things right:

1. fetching the signing certificate from `SigningCertURL`
2. **validating that URL is genuinely an AWS SNS host** before fetching it
3. building the canonical string-to-sign in the exact documented field order
4. RSA verification against the correct `SignatureVersion` (1 is SHA1, 2 is SHA256)
5. caching the certificate without caching a poisoned one

Miss (2) and the endpoint is both an SSRF and a forged-notification hole. Get
(3) wrong — the field order is not alphabetical and is not obvious — and
verification silently accepts anything.

### Why this endpoint in particular

A forged bounce notification adds an arbitrary address to the **suppression
list**. Email carries OTP, and per CLAUDE.md invariant 10 SES is a single point
of failure by design, with no second channel behind it. So an attacker who can
forge a notification can suppress any user's address and lock them out of
registration and login.

That is an **account-denial attack reachable from an unauthenticated HTTP
endpoint**. It is the last place in this codebase to hand-roll signature
checking.

### Why `sns-validator` over the alternatives

| Package | Version | Licence | Last published | Weekly downloads |
|---|---|---|---|---|
| **`sns-validator`** | 0.3.5 | Apache-2.0 | 2025-03-27 | **404,801** |
| `sns-payload-validator` | 2.1.0 | MIT | 2023-02-07 | 52,526 |
| `@aws-sdk/client-sns` | current | Apache-2.0 | active | — publishes messages, does not verify them |

`sns-validator` is eight times more used, more recently published than the only
real alternative, and carries the same Apache-2.0 licence as the AWS SDK.

**Its quiet release history is not abandonment.** The SNS signature format has
not changed; a library that implements a stable specification correctly has
little reason to publish. Read the last-published date as "nothing has needed
fixing", and treat a *new* advisory against it as the thing to watch — which
Phase 0's `npm audit`, `dependency-review-action` and Dependabot already do.

If the objection to a dependency is supply-chain risk, note that this is
precisely the risk that scanning was added in Phase 0 to carry, and that it
already paid for itself on day one by flagging two transitive advisories.

### Two things the proposal did not mention

- **Handle `SubscriptionConfirmation`, not only `Notification`.** SNS sends it
  first, and the subscription is not live until it is confirmed.
- **Confirm only for the topic ARN you expect.** Auto-confirming any topic that
  posts to the endpoint hands an attacker a subscription.

---

## 2. Response envelope — holds, with one thing to confirm

§Phase 2 requires a standard envelope for success and error. `backend/CLAUDE.md`
adds the part that matters: errors carry a **stable machine-readable `code`**
that the frontend routes on, and renaming one is a breaking change. A shape of
`{ success, data, error }` alone does not satisfy that — the `code` has to be
in it, and it has to be treated as API surface.

## 3. `Idempotency-Key` header — holds

The plan pins the key as `(userId, operation, clientKey)` and leaves the
transport open; `backend/CLAUDE.md` says explicitly "the transport — header or
body field". A header is the conventional choice and is the one taken.

The middleware must return the **original** result on a repeat, not a fresh
one, so its store has to be durable — a `LOGGED` table.

## 4. Rate limits, 60/300 per minute — holds, with two corrections

The plan pins no global numbers, so these are a free call. Two things it does
pin:

- **Stricter tiers on auth, OTP, payment, emergency-booking and messaging**, and
  messaging carries its own **per-conversation** tier. The per-endpoint override
  mechanism §Phase 2 asks for is what carries these.
- 🔧 **`3 emergency requests per customer per 24 hours, 10 per 7 days` is a
  business rule, not a rate-limit tier.** It belongs in the booking domain in
  Phase 17.3, where rejections deliberately do not consume it. Implementing it
  as middleware here would put a product rule somewhere the product cannot see
  it, and would count the wrong events.

Rate-limit counters go in an `UNLOGGED` table. That keeps them out of the WAL
and therefore out of Phase 0's PITR stream, which is correct for ephemeral
state — **and means an unclean shutdown truncates them and fails open for one
window.** Acceptable at v1 volume; it belongs in a comment beside the table, not
in a postmortem.

## 5. File transport in development — holds

Consistent with the `EmailSender` interface, and the only workable answer while
there is no SES account. Nothing in a domain module may call SES directly.

---

## Not decided here

- **The Phase 2 spec and implementation plan.** This records five choices; the
  build writes the rest.
- **SES production access.** It is requested *after* bounce handling exists and
  *before* Phase 3 starts, and it is the account owner's step, not a build step.
- **Whether bounce handling belongs in Phase 2 at all.** Settled already: the
  plan calls it a Phase 0–2 prerequisite in four places, §Phase 0's Done-when
  does not include it, and Phase 2 is where Prisma, an HTTP route and the
  `EmailSender` interface first exist. See `.claude/commands/phase-2.md`.
