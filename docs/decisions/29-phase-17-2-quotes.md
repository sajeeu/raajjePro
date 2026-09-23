# Phase 17.2 — the request-with-quote path

Built 2026-09-23. `01_Development_Plan_v5.md` revision 5.34, §Phase 17's
**17.2 — Done when**, §1c's request-based flow, §1h's locked agreement.

Nine of the twelve seeded categories are `request` mode. §Phase 17.1 refused
them by name (`BOOKING_MODE_NOT_AVAILABLE`), so three-quarters of the
catalogue could be published, found and priced but not booked. This slice is
what opens them.

---

## 1. The conflict this slice had to resolve, and how

**A request booking's provider window is the category's `quoteExpiryMinutes`,
not the flat 24 hours.** This is the one place §1c contradicts itself and the
one decision here that changes something §Phase 17.1 shipped.

The two sentences:

- **§1c step 4** — "Three accept timeouts, not one: … **Slot and
  request-based: 24 hours** → auto-decline, release the slot or reservation,
  notify the customer to look elsewhere."
- **§1c's request-based flow (Round 15)** — "They were a flat 24h to quote and
  72h to approve, which meant booking a plumber could legitimately take four
  days… **Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control and
  Home Repairs: 2 hours to quote, 4 hours to approve.** … Seeded as
  `quoteExpiryMinutes` and `quoteApprovalMinutes`."

"24h to quote" **is** the request-mode accept window, and Round 15 says in as
many words that it was replaced. Three things decided it:

1. **The artboard promises the category's figure to the customer, twice.**
   `Request a Time.dc.html` renders "He has 2 hours to reply with a concrete
   time and a real price" and, on the sent screen, "Ibrahim has 2 hours — until
   12:30 today — to reply… **If he doesn't, the request expires and you owe
   nothing.**" Its own code comment reads *"Quote + approval windows are
   category rules, not screen constants."* A 24-hour job would make that copy a
   lie in the customer's favour by twenty-two hours.
2. **`quoteExpiryMinutes` would otherwise have no reader anywhere.** It is
   seeded for all nine request categories, documented on the column as "how
   long a provider may take to quote", and rendered by a committed artboard. A
   column that nothing reads is the shape a decision takes when it was dropped.
3. **The long-lead group is unchanged either way.** Photography, Moving and
   Boat Charter carry `quoteExpiryMinutes: 1440` — exactly 24 hours. Step 4's
   figure survives intact precisely where planning happens; the split only
   bites on the six household trades, which is what Round 15 was about.

**What changed.** `findAcceptTimeouts` now sweeps `bookingMode: 'slot'` alone.
It read `['slot', 'request']` while no request booking could exist to be found,
and a request booking never reaches `requested` at all (§2 below). The 24-hour
window §Phase 17.1's Done-when asserts is untouched for slot bookings, which is
the only mode that could ever have met it.

**Flagged, not resolved silently.** Root `CLAUDE.md`: *"If a prompt conflicts
with the plan, flag it."* §0.0's precedence rule settles it — Round 15 is later
than step 4's flat statement, and step 4 was edited by Round 15 for its
*approval* clause while its *quote* clause was left behind — but the plan
should say so in one voice. `docs/design/sessions/round-54-phase-17-2.md`
carries it back, and the verification session has it.

---

## 2. `awaiting_quote` is the creation state, not `requested`

§1c says both of these:

- **Step 1** — "Customer picks an open slot (slot-based), submits a preferred
  window (request-based), or submits an ASAP request (emergency). Status
  `requested`."
- **The status machine** — "Request-based / quote-priced listings insert
  `awaiting_quote → quote_offered → accepted` before the diagram above."

A request booking is created at **`awaiting_quote`**. The reasoning:

- **Nothing could move `requested → awaiting_quote`.** No endpoint in §Phase
  17's list does it and no screen offers it. Read step 1 literally and
  `awaiting_quote` is a status the plan puts in its own machine and nothing can
  ever reach — and the plan does not put unreachable states in its machine.
- **It is the state the booking is actually in.** The provider owes a *quote*,
  on the category's own clock. A slot booking at `requested` owes an *accept*,
  on the flat 24 hours. Two different facts on two different clocks, and
  keeping them one status would mean one sweep querying two windows.
- **Nothing user-facing depends on the distinction.** `StatusPill.dc.html` maps
  both to the same "Waiting for provider", which is why the artboards do not
  settle it and why the choice costs the customer nothing.

Step 1's sentence generalises across three modes in one line; the mode-specific
refinement is authoritative for the mode, exactly as it is for emergency
(`emergency_offered`, which §Phase 17.3 will reach the same way).

---

## 3. The provisional hold, and the length nobody specifies

§1c requires the hold — *"offering a quote creates a provisional reservation on
the proposed time, expiring with the quote's approval window. Without this, the
provider could sell that time to someone else in the interim and the customer's
approval would fail on a constraint violation after they had already agreed a
price."* — and the constraint it feeds is a **range**,
`tstzrange(startsAt, endsAt)`.

The plan gives request-based work **no duration anywhere**, by design: the
whole reason these categories are `request` is that "duration depends on
diagnosis, property, negotiation, or trip type". `Propose Time and Price.dc.html`
asks the provider for a date, a departure time, a price and a note — and for no
length.

**`REQUEST_HOLD_MINUTES = 120`**, recorded rather than buried, the same
treatment `pricing.ts` gives a `daily` rate on a sub-day slot. It is the length
the schema's own example of a request-based hold already uses ("a plumbing
quote for 11:00–13:00"). The alternative — a zero-length range — is not one: an
empty `tstzrange` overlaps nothing, so the hold would hold nothing and the
provider could sell the time twice, which is the exact failure the provisional
reservation exists to prevent. It is a **hold**, not a promise about how long
the job takes; nothing is shown to either party and no amount derives from it.

**One transaction, both ways.** The hold and the status move together or not at
all — the property §Phase 17.1 proved for the firm hold (ledger **P9A-2**),
asserted here in both directions: a time already taken leaves the booking at
`awaiting_quote` with no half-quote on screen, and a failure *after* the hold is
taken leaves no hold. The second needs a forced failure; 17.1 used a bad island
foreign key, and the quote path takes no island, so the test spies the
service's own repository and asserts the spy was reached — otherwise it would
prove nothing.

---

## 4. Where the two clocks live

Both deadlines are **stored on the booking** rather than recomputed per read:

| Column | Set from | Rendered as |
|---|---|---|
| `quoteDueAt` | `createdAt + Category.quoteExpiryMinutes` | "until 12:30 today" |
| `quoteExpiresAt` | `quoteOfferedAt + Category.quoteApprovalMinutes` | the live countdown |

Each is a promise already made to somebody who is watching it count down. An
admin editing the category in §Phase 10b must move the deadline for the *next*
request, never for one already on a customer's screen. They also make each
sweep one indexed range scan instead of a join through the category table.

The provisional reservation's own `expiresAt` is set to the **same instant** as
`quoteExpiresAt` — §1c's "expiring with the quote's approval window" is one
value written twice rather than two clocks that can drift.

---

## 5. Where a quote ends up when nobody acts

| Edge | To | Actor | Why |
|---|---|---|---|
| `quote-request-timeout` | `declined` | `system` | The **provider** never quoted. Same status and actor as the slot window's `accept-timeout`; §1f reads the actor to keep timeouts in response rate and out of acceptance rate. |
| `quote-approval-timeout` | `cancelled` | `system` | The **customer** never answered. `cancelledByRole` is left **null** — nobody cancelled, a clock ran out. |
| `decline-quote` | `cancelled` | `customer` | `Quote Received.dc.html`'s "Decline this quote". |

**A customer declining a price must never land on `declined`.** §1f defines
acceptance rate as "accepted ÷ (accepted + declined) — explicit responses
only", which measures what the *provider* did; a customer turning down a number
would otherwise count against the provider who answered promptly and quoted
honestly. `cancelledByRole: 'customer'` is then the row §1f's cancellation rate
explicitly never counts.

The artboard's declined state is headed "Quote declined" — that is the screen
naming its own outcome, and the booking's status is `cancelled`. The two are
allowed to differ because §1f reads the status and the customer reads the
screen.

---

## 6. Revising a quote, rather than a reject-and-requote loop

§1c describes the negotiation directly: *"the provider proposes Tuesday 2pm at
a price and the customer wants Tuesday 3pm — an earlier revision left it with
no channel at all, so the customer's only levers were approve or reject as
offered, forcing the provider to guess again from scratch."* The channel is the
chat, which opens at `quote_offered`; the outcome is a **revised quote** on the
same endpoint, `quote_offered → quote_offered`. It releases the old hold and
takes a new one in one transaction, and restarts the customer's approval clock,
because the terms they are being asked to consider are new.

So there is no "rejected, awaiting a new quote" state and none is needed.
`Quote Received.dc.html` agrees: its declined state offers "Send a new request",
not "ask again".

---

## 7. The chat state — 17.2 owns it, §Phase 18 owns the thread

§0.0 item 7 and the Done-when: the `booking` thread opens at `quote_offered`,
not at `accepted`. There is no `Conversation` model yet, so what this slice
delivers is the **state**: `bookingChatState` in `chat.ts`, derived from
`quoteOfferedAt`, `amountSetAt`, the status and `completedAt`, surfaced on the
DTO as `chatState`.

Derived rather than stamped, for §1a's reason: every input is already on the
booking, and a `chatOpenedAt` column would be a second copy that could disagree
with the status. Reading the two *stamps* rather than the status is what lets a
terminal booking be answered correctly — a request cancelled at
`awaiting_quote` never had a thread and one cancelled after a quote did, and
both are `cancelled`.

Round 27's seven-day post-completion lock is in the same helper. Ledger row
**P17-4** records what cannot be verified until §Phase 18 exists.

---

## 8. Two judgment calls on the client

**The window chips resolve server-side.** §1c names four — "Tomorrow morning",
"Tomorrow afternoon", "This week", "This weekend" — and gives none of them
hours. `quotes.ts` resolves them against the **Maldives** calendar day, and the
client sends only which chip was tapped: two clients would otherwise resolve
"this weekend" two ways (invariant 4). The weekend is **Friday and Saturday**.
The resolved range is a machine-readable restatement for a later provider-side
calendar view; nothing computes on it, because §1c is explicit that a preferred
window "is a preference, not a slot".

**The provider picks a day from chips and the time from a clock.** The artboard
offers both as chips, but its four time chips ("06:00 · 06:30 · 07:00 · 16:30")
are sample values with **no source** — a `request` listing publishes no slots
and its category seeds no hours, so four literals would be invented
configuration. The day rail is faithful; the time is picked.

---

## 9. What this slice did not build, and why

- **Photo attachments on a request.** `Request a Time.dc.html` draws three
  photo slots ("optional — they help Ibrahim quote accurately"). §Phase 17's
  `Booking` field list has no media and no item mentions them. Not invented —
  raised in `docs/design/sessions/round-54-phase-17-2.md`.
- **Saved addresses.** The artboard's "Home / Office / Somewhere else" picker
  is §1h's Saved Preferences, reattributed to **§Phase 17.4** on 2026-09-10.
  The address is a plain field here, as `Pick a Time`'s is.
- **The thread itself.** §Phase 18. The control that would open it renders and
  states plainly that messaging lands with the messaging module, rather than
  pretending to open one.
- **Anything of §Phase 17.3's or 17.4's.** No emergency edge reaches
  `emergency_offered`; `test/bookings-pricing.test.ts` still asserts that, and
  now asserts that the two quote statuses *are* reachable.

---

## 10. Audit of the three artboards

Run before committing, as root `CLAUDE.md` requires. `verify-dc.py` passes on
all three; these are what a structural check cannot see.

| Finding | Severity | Disposition |
|---|---|---|
| "He has 2 hours to reply" contradicts §1c step 4's flat 24 hours | **Material** | The artboard is right — §1 above. |
| A native `<select>` for the island in the new-address branch | **Material** | **Invariant 15**: "a native `<select>` is never an acceptable island control anywhere, including Saved Preferences and the emergency request form." Not implemented; correction raised. |
| Three photo slots on the request form | Material | Not built — §9 above. |
| Saved addresses on the request form | Expected | §Phase 17.4's. |
| Four hardcoded time chips on the quote form | Minor | No seeded source — §8 above. |
| `WINDOWS` map (4h household / 72h long-lead, Home Repairs at 4) | ✅ correct | Matches invariant 13 and §0.0 item 16. |
| "Sending opens the chat with Mariyam right away" | ✅ correct | §0.0 item 7. |

---

## 11. How to verify it

```
cd backend && npx vitest run test/phase17-2-done-when.test.ts
cd frontend && flutter test test/features/bookings/phase17_2_quote_screens_test.dart
scripts/verify.sh
```

`test/phase17-2-done-when.test.ts` asserts the four clauses 17.2 owns and the
phone-number rule standing over all four slices, and **reads every window back
from the seeded category** rather than naming a number — a test that hardcoded
240 and 4320 would pass against a service that hardcoded them too, which is the
failure invariant 13 exists to prevent.
