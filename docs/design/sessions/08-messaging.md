Build the messaging surface: **Conversations**, the **enquiry thread**, the **booking thread**, and the **block / mute / decline** controls.

Chat is the only way a customer and a provider ever communicate — no phone call, no WhatsApp, no handover to anything else, before a booking, during it, and after it. That makes these screens load-bearing in a way a normal chat UI is not: a message that fails silently here is a plumber on the wrong street, not a missed pleasantry. Two design consequences run through the whole session — **the channel carries no interference of any kind**, and **offline behaviour is a first-class state, not an edge case**.

**Import the components; do not re-derive them.** `ServiceCard` · `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` · `SkeletonCard` · `EmptyState` are sibling files with declared props. `StatusPill` already carries `pending_offline` ("Pending — sends on reconnect") — the offline message state should agree with it rather than inventing a second vocabulary. `Booking Detail.dc.html` and the session-6 screens are the neighbours these link to and from.

**No mockups exist.** Propose the design; note structural calls so they can be reviewed as decisions.

Cast as established: Mariyam Shifa (Home Deep Cleaning, Silver) for the booking thread, Ibrahim Rasheed (Emergency Plumbing, Gold) for the enquiry.

---

## The one rule that shapes every screen

**The composer carries nothing beyond a send control.** No banner, no reminder, no "phone numbers are not shared" notice, no warning icon — nothing, on either thread type. Contact-pattern detection exists but is entirely invisible: nothing is blocked, nothing is redacted, and the sender is never told. An earlier revision had an inline nudge; Round 12 deleted it because it put friction on exactly the content the channel exists to carry — appliance serial numbers, model numbers, property details are all 7-to-15-digit strings indistinguishable from a phone number, and all of them are *the point* of an enquiry.

So: if any state of any of these artboards renders a warning near the composer, a redacted message, a "this message may contain contact details" flag, or any hint that scanning exists, it is a defect. The message always sends, unmarked.

Equally: **no phone number appears anywhere in this session.** The emergency reveal lives on Booking Detail and is the product's single contact surface; messaging never renders one, not even in sample message content.

---

## Screen 1 — Conversations

Every thread, both kinds together, newest activity first.

Each row: the other person's name, what it concerns, the last message, age, unread state.

- `Ibrahim Rasheed` · `Emergency Plumbing & Pipe Repair` · *"I'll be there in 20 minutes"* · `4m` · unread
- `Mariyam Shifa` · `Home Deep Cleaning · Tue 25 Aug` · *"See you Tuesday"* · `2d`

**The two kinds must be tellable apart at a glance** — an *enquiry* about a service versus a *booking* thread — but this is a secondary signal, not a shouting match; the primary scan is name + last message, like every messaging app the user already knows.

Empty state: `No messages yet`, with a line that explains how a conversation starts (message a service, or book one). Loading and error as usual.

## Screen 2 — Enquiry thread

A question about a service, before any booking exists. Reached from the Message button on Service Preview.

- **Header: the service it concerns**, with a route back to the listing.
- Messages both ways, timestamps, sender clear, **photo attachments** both ways.
- **Everything is allowed here, and the sample content should demonstrate it**: an appliance model number, a serial number, a photo of the problem, a price question. Write the demo conversation as the real exchange the channel exists for — *"Is it a split unit or ducted? What's the model number on the outdoor unit?"* / *"GREE GWH12, serial 5CV0912847"*. That serial is exactly the string a naive filter would eat; here it just sends.
- **Email-verification gate:** sending requires a verified email. Design the state where it isn't — the thread is readable, the composer is replaced by a short explanation and a route to verify. Never a dead button with no reason.
- **Report** and the mute/block entry, tucked behind the header's overflow — present, findable, not looming over a channel that's supposed to feel open.
- **Read-only lifecycle state:** a thread whose listing was taken down stays readable but accepts no new messages, and says why in plain language. (If a booking between the same two people is live, its booking thread is unaffected — different thread.)

## Screen 3 — Booking thread

Coordination for a live booking. The only channel there is.

- **Header: the booking**, its status (`StatusPill`) and time, with a route to Booking Detail.
- Messages, timestamps, photos. The demo conversation is arrival logistics: the exact address, the gate code, *"I'm at the blue gate"* — the content that in every other product would have moved to a phone call. Here it can't, and the screen should feel adequate to that.
- **Opens at `quote_offered` for request bookings** (offering a quote is what opens the chat) **and at `accepted` for slot and emergency. It never closes** — including after completion. Show a post-completion state: booking `completed`, thread quiet, composer still live. A customer with a follow-up question about the same job still has the thread.
- **Offline is part of this screen, not a detail.** A message sent with no connection renders immediately in the thread with a pending treatment consistent with `pending_offline`, and sends on reconnect. It is never silently dropped, and the customer is never left wondering. Show this state.
- **The block notice.** When one party has blocked the other while this booking is still live, the thread stays open — a scheduled visit still has to be coordinated — with a visible notice to both parties explaining exactly that: the block applies to future bookings and messages; this thread stays open until the booking ends. Design that notice. It should read as fact, not apology, and it must not disable the composer.

## Screen 4 — Mute, block, decline

Three actions, three scopes, and the difference is the design problem. Present them together (a sheet from the thread header is the natural home — your call) with each one stating **what it stops and what it does not**:

- **Mute this conversation** — silences this thread's notifications. Nothing else. They can still message; you just aren't pinged.
- **Block this person** — account-level, both directions: neither of you can message the other or book with the other again. A live booking's thread survives until that booking ends (the notice above).
- **Decline future bookings from this customer** — *provider only*: stops new bookings from this customer, leaves the conversation intact. Independent of reporting — it's self-service protection, not an accusation.

Confirmation states for each, honest about scope. A live booking's thread survives all three — say so wherever it's relevant, because it is the counter-intuitive part.

The decline action appears only in the provider's view; if one artboard serves both roles, make the role a scenario prop rather than showing a customer an action they don't have.

---

## States and combinations

Every screen: populated, loading, error; empty for the list. Watch these combinations:

- The enquiry composer gate is about **email verification**; the read-only lifecycle state is about the **listing**. Different causes, different copy — never one state pretending to be the other.
- A booking thread never renders as read-only while its booking is non-terminal — not for a hidden listing, not for a block.
- `pending_offline` messages appear only in a thread the sender can write to — never in a read-only enquiry.
- The decline-future-bookings action never appears in a customer's view.

## Guardrails carried forward

- No phone number, WhatsApp or Viber reference anywhere — including inside demo message text.
- Nothing near either composer beyond the send control. No detection UI of any kind.
- No "Payment Verified" language anywhere; payment talk in demo messages stays as coordination ("transferred just now — tap I've Paid when you see it" is the *customer's own words*, fine; a platform-rendered checkmark is not).
- No editorial labels on anyone.
- Emergency stays quiet; photos uploaded into the project, never hotlinked.
- Money as MVR, as in prior sessions.
