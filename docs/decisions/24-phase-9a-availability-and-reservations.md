# Phase 9a — Availability, Time Slots & Reservations

What was decided while building §Phase 9a, and why. The plan is the source of
truth; this records the choices it left open and the two places the build
departs from a literal reading of it.

## 1. The availability model is rules, exceptions and time off — three tables

§Phase 9a says slots are "generated from the listing's availability rules with
individual override" and never says what a rule is. §Phase 9's step 5 collects
only `workingDays` / `workingHoursFrom` / `workingHoursTo`, and both its own
helper text and §1's mockup table warn that this "will mislead if treated as
the pattern". So the real model is this phase's to define, and it is defined
from the delivered prototypes rather than invented:

| Entity | Prototype | Scope | Effect |
|---|---|---|---|
| `AvailabilityRule` | `Availability.dc.html` → "Weekly hours" | listing | Days, a window, and a visit length. What generates slots. |
| `AvailabilityException` | `Availability.dc.html` → "Modified hours" | listing | A named date range that **replaces** the hours. Ramadan is the designed case. |
| `ProviderTimeOff` | `My Calendar.dc.html` → "Time away" | **provider** | All-day absence. Removes slots on those dates across every listing. |

**Exceptions and time off are deliberately two tables, not one with a
discriminator.** The two screens keep them apart and cross-link them in both
directions ("Trips and holidays live in My Calendar"; "A trip or a holiday is
time away — add it in My Calendar"). One table would need a nullable
`listingId` meaning *all* and nullable hours meaning *none*, and every reader
would have to know both conventions.

Three rules the expansion follows, none of which the plan states and all of
which it implies:

1. **Time off wins outright.** A covered day produces nothing.
2. **An exception modifies; it never creates.** On a weekday the rules do not
   work, an exception covering that date still produces nothing — otherwise
   "Ramadan hours" would quietly add Fridays to a Sunday-to-Thursday week.
3. **A trailing remainder is not a slot.** Nobody is sold two thirds of a job.

`Listing.workingDays` / `workingHoursFrom` / `workingHoursTo` are read in
exactly one place: the rule editor's defaults, so a provider who already stated
their hours in the wizard is not asked twice. They generate nothing.

## 2. Two sessions of prototype scope that belong to Phase 17, not here

`Pick a Time.dc.html` and `My Calendar.dc.html` each contain material this
phase cannot honestly build:

- **The picker's lower half** — address selection, job notes, the price
  footer, the email-verification gate, Confirm, and the "Request sent" screen
  — is **booking creation**, which is §Phase 17.1. This phase builds the
  *time-selection* surface and hands the chosen slot back to its caller.
- **My Calendar's "Upcoming commitments"** renders a customer name, a booking
  reference and a mode chip, all of which live on a `Booking`. What exists here
  is the `Reservation` — the commitment itself — so the section is real but the
  booking-derived fields arrive in §Phase 17.1. In practice the designed empty
  state is what renders today, which is correct rather than a placeholder.

Ledger row **P9A-1** carries both.

## 3. A `TimeSlot` is derived data and may be replaced — the one exception to invariant 8

Invariant 8 says nothing is ever hard-deleted. §Phase 9a says an availability
change "regenerates **future unreserved slots only**". Those two cannot both be
read literally, and the plan's own sentence resolves it: a future slot nobody
has taken is the *expansion of a rule*, not a record of anything.

So regeneration removes rows, and the removal is bounded on every side:

- **Future only** — `startsAt > now`. A past slot is history and is never
  touched, by generation or by anything else.
- **Unreserved only** — a `reserved` slot is somebody's appointment.
- **Never the record.** The rule is soft-deleted, the exception is
  soft-deleted, the time off is soft-deleted, and the `Reservation` — which is
  what an appointment actually *is* — is never deleted at all, only stamped.

A `blocked` slot the rules still produce survives an unrelated rule edit; one
the rules no longer produce goes with the rest, which is what the save sheet
promises: "Only future, unbooked times change."

**Known and not addressed:** nothing prunes slots once they are in the past.
At sixty days rolling that is roughly 4,000 rows per slot-publishing listing
per year. The plan specifies no retention for them and this phase did not
invent one; it is worth revisiting before launch, not now.

## 4. The exclusion constraint carries a `WHERE`, and that is load-bearing

```sql
EXCLUDE USING gist (provider_profile_id WITH =, tstzrange(starts_at, ends_at) WITH &&)
  WHERE (released_at IS NULL)
```

Without the predicate, invariant 8 and the constraint contradict each other: a
released reservation stays forever, so a cancelled booking's time could never
be booked again — the exact opposite of §Phase 9a's "a cancelled booking's slot
reappears". Two `CHECK (ends_at > starts_at)` constraints sit beside it because
an empty or inverted range never overlaps anything and would silently disable
the guarantee for that row.

`btree_gist` is required for the `=` on a uuid and is created by the migration.
`test/schema-phase9a.test.ts` asserts all of it against `pg_constraint`, so a
later `migrate dev` that regenerated the migration without the hand-written
section fails a test rather than shipping a marketplace that can double-book.

**`TimeSlot` also carries `@@unique([listingId, startsAt])`, and it is not the
guard.** It is the generation key that makes `createMany({ skipDuplicates })`
idempotent. It is scoped to one listing and says nothing about the provider,
which is precisely why it is not the `UNIQUE (providerId, listingId, startsAt)`
that §Phase 9a and root `CLAUDE.md` reject. Both the schema comment and a test
say so, because the resemblance is close enough to be misread.

## 5. Two guards on reserving, because they catch different things

`reserveSlot` claims the slot row with a conditional `UPDATE … WHERE status =
'open' AND starts_at > now` **before** inserting the reservation.

- The **claim** resolves two customers racing the same published slot, with a
  clean `SLOT_NO_LONGER_AVAILABLE` rather than a caught constraint error, and
  re-checks that the time has not passed since the picker rendered it.
- The **constraint** resolves everything the claim cannot see: the same
  provider's time taken from another listing, or by a request-based quote that
  never had a slot at all. It is the database's guarantee and no code path can
  opt out of it.

Prisma does not model exclusion constraints, so the SQLSTATE arrives nested
inside the driver adapter's error (`P2039` →
`meta.driverAdapterError.cause.code` on Prisma 7 with `@prisma/adapter-pg`).
All three known nestings plus the constraint name are checked, because getting
it wrong fails *open* — a raw driver error would reach the global handler and
turn "that time just went" into a 500 with an internal message in it. The
Done-when suite exercises it against a real violation.

## 6. An unavailable time is resolved on read, not written onto rows

A reservation is provider-scoped; a slot belongs to one listing. So a plumbing
quote held for 11:00–13:00 makes the cleaning slot at 12:00 unbookable, and
that slot's row knows nothing about it.

Writing `reserved` onto rows a booking does not belong to could not be unwound
correctly when it is released, so the collision is resolved when the grid is
read, against the small set of holds in the window being looked at. §1c's "no
picker ever shows an unavailable time" is met, and the provider sees the same
truth on their own grid — rendered as `reserved`, which is the state
`Availability.dc.html`'s sheet already has copy for: "A booking on any of your
listings holds your time, so you can never be double-booked."

## 7. Generation is narrow by construction, and says how long it may take

The phase brief named the failure to avoid: §Phase 8a's `runLifecycle` selected
every subscription row and then did a `findUnique` per candidate, crossing five
seconds at a thousand rows.

So `ListingSlotState` is a durable work list with one indexed column,
`nextGenerationAt`, and the job's entire condition is `nextGenerationAt <=
now`. A listing with nothing to do is **never read**, rather than read and
skipped. Null means dormant — no rules, not slot mode, or deleted. A change
sets it to now; a successful run sets it to the next Maldives midnight, which
is when the rolling horizon next needs extending.

Regenerating one listing is **six queries regardless of the size of its grid**:
the listing, its rules, its exceptions, the provider's time off, its existing
future slots, then one delete and one `createMany`.

**The stated budget: 5 seconds and 50 listings per run, every 5 minutes.** At a
thousand providers the steady state is a few hundred regenerations a day
against a capacity of fourteen thousand, so the budget is a tripwire rather
than a throughput limit. On overrun the job logs a structured
`slot_generation_overrun` warning and stops; nothing is lost, because the work
list is in the database. §Phase 21 gives that warning a destination — ledger
row **P9A-3**.

**A rule edit does not wait for the job.** It regenerates inside the same
transaction that saved the rule, so "Save rules" is atomic: a provider never
sees a saved rule whose grid has not caught up, and a failure rolls both back.
The job is the backstop and the horizon-roller, not the primary path.

## 8. The provisional hold's expiry is an input, never a number here

§Phase 9a's bullet says "a 72-hour expiry". That is a **pre-Round-15 residue**:
Round 15 made quote windows per-category (`quoteExpiryMinutes` /
`quoteApprovalMinutes` — 120/240 on the household trades, 1440/4320 where
planning happens), root `CLAUDE.md` invariant 13 says never to hardcode 24h/72h,
and §1c says the hold expires "with the quote's approval window".

So `Reservation.expiresAt` is supplied by the caller offering the quote, and
nothing in this module knows a duration. The sweep releases whatever has
passed. Flagged rather than resolved silently, per the scope rules; the
Done-when test reads Plumbing's seeded 240 and asserts against that.

## 9. Timezone: the convention, and the boundary rule the plan asks for

Every instant is stored UTC; Maldives Standard Time is **UTC+5, year round,
with no DST and no history of one**, so the offset is a constant and not an
IANA lookup. `src/core/maldives-time.ts` owns every conversion.

**The boundary rule: a day is a Maldives calendar day**, `[date 00:00+05,
date+1 00:00+05)` — which is `[date-1 19:00Z, date 19:00Z)`. Weekday
membership, an exception's range, a time-off range and the picker's date rail
all resolve on that, never on the UTC date. A 02:00 Malé appointment is 21:00Z
the *previous* UTC day, and filing it by UTC date would put it on a day the
provider may not even work.

Overnight windows are refused: the plan specifies none, and a silently wrapping
window would generate slots on a day nobody picked.

## 10. Where the entry points are

The Availability and My Calendar screens are this phase's; the **route into
them from the dashboard is §Phase 10's**, whose own bullet list carries "Slot
management entry point (Phase 9a)". The routes are registered and reachable by
name; Phase 10 puts the door on. Same for the picker, which §Phase 12's Service
Preview will push.

## 11. The rule editor saves in one step, because a local preview cannot be honest

`Availability.dc.html` edits a rule into a **local preview** — "Preview
updated — not saved yet", with Save changes and Discard — and commits it with
a second action.

Producing that preview means expanding rules into times **in Flutter**. Which
times a rule produces is not a property of the rule: it also depends on the
listing's exceptions, the provider's time away across every service, the lead
boundary, the 60-day horizon, and which times are already held by bookings on
*other* listings. That is `expandSlots` plus four more inputs, all server-side,
and a second implementation of it would eventually disagree with the one that
decides what customers can actually book — while being the one on screen, and
therefore the one the provider trusts.

So the rule saves in one step, behind the artboard's own confirmation sheet
and its exact reassurance — *"Times someone has already booked stay exactly as
they are. Only future, unbooked times change."* — and the grid then renders
what the server actually did. What is lost is seeing the new grid before
committing; what is kept is that the grid is never a guess.

**The alternative, not taken:** a server-side dry run
(`POST …/rules/preview`) would honour the interaction exactly and keep one
implementation. It was not built because §Phase 9a's endpoint list is
"generate/regenerate, block/unblock, list open slots for a listing" and adding
a fifth endpoint on the strength of an artboard is the kind of gap-filling
§Scope Discipline asks to be raised rather than resolved. It is offered to the
design round instead — `docs/design/sessions/round-57-the-preview-that-cannot-be-local.md`.

## 12. The client presents in Maldives time and never calls `toLocal()`

`core/format/maldives_time.dart` is the client half of §9's convention, and
every screen in the feature groups, labels and compares through it.

That matters even in a single-timezone market. A device left on another
timezone — a traveller's phone, an emulator on UTC, a CI runner — would
otherwise file a 21:00 Malé appointment under the wrong heading while the
server and the provider both call it Tuesday. `test/core/maldives_time_test.dart`
asserts the same instant expressed two ways reads identically, which is the
assertion a `toLocal()` would fail.

## 13. Nothing in this feature goes through the offline queue

§0.0 item 14 keeps the queue to exactly three surfaces — the wizard's
autosave, the slot/request accept prompt, and chat sends. None of these is one
of them, and the reasoning transfers: a replayed rule edit would rewrite a
published grid from a decision made somewhere else, and a replayed block would
withdraw a time minutes after the provider changed their mind. These fail
visibly, show the server's own message, and are retried by hand.

The server's message is rendered verbatim on refusal, because every refusal
here is a sentence written for a provider to read — "Those hours overlap
another rule on the same day (09:00–13:00). Edit that one instead." A generic
failure would throw that away.
