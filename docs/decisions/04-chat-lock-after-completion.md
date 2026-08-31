# Round 27 — the booking chat locks 7 days after completion

**Status: adopted as Round 27 (2026-08-31). Plan revision 5.13.**

## The decision

The `booking` thread stays the sole coordination channel through the life of a booking **and for 7 days after completion — the callback-guarantee window — then locks read-only.** It replaces the pre-Round-27 rule that the thread "is never torn down."

The concern that prompted it: an indefinitely open thread is a free, warm channel between two people who now know each other. "Can you come again Tuesday?" happens in that thread, the job happens, and the platform never sees the booking. Closing the channel funnels repeat work through **Book Again**, where it becomes a real booking.

## What the lock is, exactly

- **Timing:** 7 days after `completed` — the exact moment the callback-guarantee right lapses, so the one platform-enforced commitment always has a live channel for its whole validity.
- **Read-only, never deleted.** Both parties keep the full history forever (invariant 8: nothing is hard-deleted). The composer is replaced by a plain closed-job state.
- **Two routes out of a locked thread:** **Book Again** (repeat work, pre-filled), and — where a callback claim was made inside the window — the claim's own **linked zero-cost booking**, which has its own thread through the normal machinery (§17.4). No reopening mechanism is needed for callbacks because a claim never lived in the old thread's future: it creates a new booking.
- **A dispute reopens the thread** for its duration and relocks on resolution. `payment_unresolved` is non-terminal and never locks.
- **Provider-stated warranties beyond 7 days** (e.g. "90-day warranty on workmanship") are unverified claims RaajjePro does not enforce; the honest path is a Book Again request describing the issue, which the provider can quote at zero. No dedicated warranty channel is built.

## What this deliberately does not claim

- **It does not prevent direct contact.** The two parties met in person at the job; numbers change hands on-site, and contact-pattern detection stays silent-and-logged, never blocking. The lock's real effect is friction and funnelling, not sealing.
- **The enquiry channel stays open by design** — anyone can message any listing pre-booking, with everything allowed. Restricting it would gut pre-booking Q&A, so a determined pair always has an in-app channel. The lock removes the *warm, zero-effort* thread, which is where casual off-book arrangement actually happens.
- **Live-booking chat behaviour is untouched:** blocks still never sever a live booking's thread, and the thread still opens at `quote_offered` / `accepted` as before.

## Enforcement

`verify-dc.py` gains a locked rule banning "never torn down" and "stays open after completion" in prototypes. `Mark Complete` (in the design project, round 1) carries both and fails the gate until the Round 27 correction lands. `Booking Thread` gains a locked scenario in the same round.
