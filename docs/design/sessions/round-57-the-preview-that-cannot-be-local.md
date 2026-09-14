# Round 57 — the preview that cannot be local

**One screen: `Availability.dc.html`. Leave every other artboard alone.**

Phase 9a is built, and all of this screen is implemented except one mechanism.
This round is about that mechanism, and about two smaller things the build
found. Nothing here is a complaint about the design's intent — the intent is
right and the copy is better than what a developer would have written.

## 1. The local preview cannot be built as drawn, and the reason is worth knowing

The screen currently edits a rule into a **local preview** — the editor's
"Update preview", the amber "Preview updated — not saved yet" banner with
"Save changes" / "Discard", and then the confirmation sheet.

Producing that preview means turning rules into actual times **in the app**.
The app cannot do that correctly. Which times a rule produces is not a
property of the rule: it also depends on the listing's modified-hours
exceptions, the provider's time away across every service, the category's
minimum lead time, the 60-day horizon, and which times are already reserved
by bookings on *other* listings. All of that lives on the server, and it is
the same computation that decides what customers can actually book.

Building a second copy of it in the app would produce two answers to "when am
I available", and the one on screen is the one the provider would trust. That
is the failure mode worth avoiding — not the extra work.

**What was built instead:** the rule saves in one step, straight through the
confirmation sheet, and the grid below then shows what the server actually
did. The confirmation keeps this screen's own copy, which is the part that
matters — *"Times someone has already booked stay exactly as they are. Only
future, unbooked times change."*

**What to change on the artboard:**

- The editor's primary button reads **"Save rule"**, not "Update preview".
- **Remove the dirty banner entirely** — the amber "Preview updated — not
  saved yet" block with its "Save changes" and "Discard" pair. There is no
  unsaved state to be in.
- The confirmation sheet **stays exactly as it is**, including its title and
  the sentence above. It now fires from the editor's Save rather than from the
  banner's "Save changes".
- The grid keeps its heading and its "Tap an open time to block it" line.
  Retitle it from "Preview" wording to plain **"Your times"** — it is the
  published grid, not a proposal.

**If the preview is worth keeping,** there is a way, and it is worth saying so
rather than only removing it: the server could answer "what would these rules
produce?" without saving. That is a real option for a later round — it keeps
one implementation and honours the original interaction. It was not built now
because Phase 9a's endpoint list does not include it and inventing one was out
of scope. Say if you want it; it is a small addition.

## 2. Two things the artboard says that the build cannot keep

- **"First 5 days shown."** Kept. The grid renders the first five days that
  have times, which is what the line promises.
- **The horizon line.** Kept, and it is accurate: the date comes from the
  server, and the app prints no total anywhere.

## 3. What the reserved sheet gets right, and should not be touched

The sheet's sentence — *"A booking on any of your listings holds your time, so
you can never be double-booked."* — is the single best explanation of the
reservation model anywhere in the artboards, and it is exactly what the
database does. It is now also load-bearing in a way the design may not have
intended: a slot on **this** listing can read `Reserved` because of a booking
on a **different** one, and that sentence is the only place the provider is
told why. Leave it alone.

## 4. What is deliberately absent, so it does not read as missing

The customer picker (`Pick a Time.dc.html`) is implemented **only down to the
time grid**. Address, job notes, the price footer, the email-verification
banner, Confirm and the "Request sent" screen are all booking creation, which
is Phase 17.1's. They are not lost and they need no change — this is a note so
that a review of the running app does not read them as dropped.

Likewise `My Calendar.dc.html`'s commitment rows currently show the time and
nothing else. The customer name, the booking reference and the mode chip all
live on a booking, which does not exist until Phase 17.1. The artboard is
right; the data is not there yet.
