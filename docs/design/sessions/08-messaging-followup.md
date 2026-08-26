# Session 7 corrections — two lines of copy

The hard constraints all held, and they were the session. Both composers carry nothing but attach, field, send — no banner, no reminder, in any state. The enquiry demo sends `serial 5CV0912847` unmarked, which is the whole argument for the channel in one message. The offline bubble uses `pending_offline` from `StatusPill` rather than inventing a vocabulary. The block notice keeps the composer alive and says exactly why. Decline renders only for `role="provider"`. The email gate and the listing-removed state are different causes with different copy, as briefed. No phone number appears anywhere, including inside demo messages.

Two lines of copy, both in **Mute Block Decline**, plus one label.

---

## 1. Decline — "RaajjePro is not notified" isn't true

The decline action's *Doesn't stop* panel:

> This conversation, and the booking already underway. Not a report — **RaajjePro is not notified.**

The first half of that sentence is exactly right and worth keeping: decline is self-service protection, not an accusation, and it doesn't start a moderation review. But "RaajjePro is not notified" overstates it — the platform necessarily records the action, because it's what *enforces* it at booking creation. A provider reading this could believe the decline is invisible to the platform, which is a privacy promise nobody can keep.

Say what's actually true:

> This conversation, and the booking already underway. Not a report — nothing goes to review, and Aishath isn't told why.

(If "Aishath isn't told why" claims more than the plan specifies about what the declined customer sees, keep just "nothing goes to review.")

## 2. Booking thread menu — "Report a problem" invites the wrong problems

The enquiry thread's overflow says **Report**; the booking thread's says **Report a problem**. On the one screen where "a problem" most likely means *the booking* — a no-show, a price change — that label steers people toward Report when Raise a Dispute is their path. Session 6 spent a round keeping those two systems visually distinct; the label shouldn't blur them back together.

Rename it to **Report**, matching the enquiry thread. The Report screen's own submitted state already redirects genuine booking problems to the dispute path, so the label is the only fix needed.

---

## Leave alone

Everything else, on all four artboards. Specifically: both composers exactly as they are; the enquiry demo conversation including the serial number and price talk; the email-verify and listing-removed composer replacements; the offline pending treatment; the block notice on the live thread; the stops / doesn't-stop panels for mute and block, which are accurate; the role-gated decline; the kind pills and unread treatment on Messages. `BottomNav active="Messages"` was checked against the component — it's a declared tab, not an invention.

This should be the only round on session 7.
