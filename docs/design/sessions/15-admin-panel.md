# Session 15 — the admin panel, all of it

**The last undesigned surface in the product.** Every one of the app's screens now has an
artboard; these do not. Eighteen screens across three phases, and one brief because they are
one app that must feel like one app.

**Content only, like `docs/design/designer-brief.md`.** This says what each screen holds and
what must be true of it. It does not say how anything should look.

---

## What this is, and how it differs from everything designed so far

A **separate internal React web app**, not a Flutter screen and not a mobile layout. Desktop
first. Its user is **the owner and, later, one or two staff** — function over form, and no
onboarding: whoever opens this knows the business.

That single fact should change the design. This is the surface where **one person absorbs the
manual work the product deliberately keeps manual**: no payment gateway, no automated KYC, no
automated moderation. Every screen here is a queue that a human clears. The costed load is
5.8 hours a month at 50 providers, 32.7 at 200, 105.0 at 500 — so a screen that takes three
clicks instead of one is a real hour, and a queue that hides its oldest item is a missed SLA.

**Not a dashboard product.** Only Phase 10c is a dashboard; the rest is queues, a directory,
records and switches.

---

## Data facts, fixed — use these, invent nothing

- **Money is `MVR 450`, code first, decimals only when the value has them.** Stored as integer
  laari; never shown as laari. The subscription is **MVR 150** a month, **MVR 75** for the first
  100 providers held 12 months, and the emergency dispatch fee is **MVR 200**.
- **Verification is three tiers with fixed copy:** `Bronze` — "ID checked by RaajjePro" ·
  `Silver` — "ID checked, work verified" · `Gold` — "ID checked, registered trade". A provider
  can be publicly visible at tier `none`.
- **Evidence per tier:** Bronze is a national ID or passport matching the account name, plus the
  admin confirming the phone number by calling it or matching it to the document. Silver is
  Bronze plus photos of completed work plus a non-paperwork second factor — a customer reference
  RaajjePro contacts, or five clean completed bookings. Gold is Silver plus a business
  registration or a recognised trade certificate. **Photos of work are never sufficient alone at
  any tier.**
- **Payment submission states:** `pending` / `confirmed` / `rejected`. A `pending` submission
  grants nothing at all.
- **Booking states:** `requested`, `awaiting_quote`, `quote_offered`, `emergency_offered`,
  `accepted`, `awaiting_payment`, `payment_claimed`, `confirmed`, `completed`, `cancelled`,
  `declined`, `disputed`, `dispute_resolved`, `payment_unresolved`.
- **Twelve categories:** Cleaning · Plumbing · Electrical · AC Repair · Beauty · Photography ·
  Pest Control · Appliance Repair · Moving · Fitness · Home Repairs · Boat Charter.
- **Four are emergency-capable** — Plumbing, Electrical, AC Repair, Moving — at a minimum tier
  of `gold` for Plumbing and Electrical, `silver` for AC Repair and Moving.

---

## Rules that constrain the design, not just the copy

**1. The analysis is advisory and the screen must say so.** Uploaded receipts are checked
against the submission and the findings shown beside the image. It must **never use the word
"verified"**, never auto-confirm, and never pre-fill or gate the confirm button. *The admin
confirming is the verification.* Design the findings as something read on the way to a decision,
not as a verdict already reached.

**2. "Couldn't read" is a first-class outcome, not an error.** Each finding is `matches`,
`does not match — <what was found vs what was expected>`, or `couldn't read`. These are phone
photographs of paper slips; the third outcome is common and must not look like a failure of the
system or a mark against the provider.

**3. The bank statement outranks the receipt.** Where an imported CSV row matches the reference
code, that row is authoritative and the receipt analysis is secondary. The design must make
which source is speaking unmistakable.

**4. Ban and hard-delete are not actions here.** Deliberately excluded from v1 so one
credential cannot destroy an account in one click. Suspend and unsuspend exist, reason required.

**5. View-as-user excludes message content.** It renders a user's own view of their listings,
bookings and subscription state, for answering "I can't see my booking". Chat carries home
addresses, gate codes and photographs of people's houses, so it is not in there — and the
screen should say why rather than looking like it lost a panel.

**6. A CSV export carries IDs, statuses, dates, amounts and counts only.** Never a phone
number, a name, an email address or a bank detail. The export control should not offer a column
picker that implies otherwise.

**7. Identity documents are handled differently from every other image.** Separate private
storage, short-lived signed URLs, every access logged, **re-authentication before viewing one**,
and purged 90 days after the decision. The decision, the evidence type and the reviewing admin
survive; the images do not. A case reopened after 90 days shows a decision with no pictures, and
that state needs designing rather than looking broken.

**8. Internal notes are never visible to their subject**, and are deleted with the account.

**9. Everything a user wrote is rendered as text, never as markup.** Listing descriptions,
review bodies and enquiry messages reach this app. Do not design anything that implies rich
text, embedded images from a description, or a clickable link taken from user input.

---

## The screens

### A. Shell — the frame all of it sits in
Persistent sidebar navigation, **each queue item showing its live open count**, and one
consistent severity treatment so that anything past its SLA is flagged the same way everywhere.
A **kill-switch banner** persists wherever a switch is off, because a flipped switch that gets
forgotten is the failure this exists to prevent.

### B. Global search
One command-palette search across users (phone or name), bookings (ID) and payments (reference
code); typed input routes to the matching record type. It is for "I have an ID or a phone
number", not for browsing — each list screen keeps its own filters. The Done-when is **any
record in under two actions**.

### C. Payment submissions queue
Pending submissions: submitter, amount, reference code, submitted-at, proof thumbnail, and
whether a CSV row already matches. This is the highest-frequency queue in the product.

### D. Payment submission detail — the most consequential screen here
The proof image at a size a reference code can actually be read at, the submission's claimed
values, and the five findings beside it: **reference code, amount** (checked against *this
provider's* own rate, never a global price), **destination account, date, duplicate**. Duplicate
means this image or this transaction reference was already submitted for another period — the
clearest fraud signal available and the one a human eye misses.

Actions: **confirm**, **reject with a required reason**, and **reverse** a previous decision.
All three are audit-logged. Reject must produce a reason the provider will read in the app.

### E. Bank-statement CSV import
Upload, then a table of proposed matches by reference code for one-click confirmation, with the
unmatched rows separated out rather than buried.

### F. Unmatched transactions queue
CSV rows the matcher could not resolve — a garbled reference, an amount that does not match, a
payment with no submission at all. Each needs a route to the record it probably belongs to.

### G. Identity verification queue
Submitted cases by tier applied for and age. Note that **the five-clean-bookings route to Silver
is granted automatically and never appears here** — only ID checks, customer references and Gold
paperwork reach a human.

### H. Identity verification case detail
The evidence for the tier applied for, the tier decision, and a **rejection-reason taxonomy**
with a resubmission path. Re-auth before a document opens. The screen must make the phone-number
confirmation an explicit step, because that is where a phone number becomes a checked fact.

### I. `payment_unresolved` queue
A booking whose payment claim went unanswered for seven days. **Five-business-day resolution
target**, with the aging visible and an alert when an item passes it or the queue exceeds 25
open items. Resolution is to `confirmed` or `cancelled`, with an enumerated outcome.

### J. Disputes queue
Either party can dispute a booking. Both parties' history shown together, and resolution
requires one of the enumerated outcomes. A dispute reopens the booking's chat for its duration.

### K. User directory
Search by phone number or name; filter by role (customer / provider) and status. Suspension must
be visible in the list, because a suspended provider disappearing from search is the thing the
admin is checking for.

### L. User detail
Profile, listings, booking history, reports filed against and by them, verification history and
internal notes — **one screen, not five tabs to hunt through**. Suspend and unsuspend live here,
reason required. A suspended provider leaves search, Home and the public profile through the one
shared query, and existing non-terminal bookings are untouched until they resolve.

### M. View-as-user
Read-only, access-logged, no ability to act, message content excluded (rule 5).

### N. Category configuration
The twelve categories with name, icon, active state, and every per-category number: lead time,
emergency window, minimum tier, ETA presets, quote windows, callback eligibility, occasion
presets. All audit-logged.

**One refusal needs designing:** a `bookingMode` change is **blocked outright** while any
published listing in that category has open time slots or non-terminal bookings, and the refusal
must **name the blocking listings** rather than saying no.

### O. Kill switches
Audit-logged flags for emergency bookings, new registrations, new listing publication, the
emergency contact reveal, and **three separate email switches — OTP, notification/fallback and
marketing**. Those three are independent by design: killing marketing email must not touch an
OTP. These are incident controls, not a feature-flag framework.

### P. Alerting
Alerts fire **outbound** — email or Slack/Telegram — as well as in-panel, because a single admin
who has not opened the panel is the normal case. **De-duplicated per threshold crossing**: an
alert that fires every fifteen minutes gets muted and then missed.

### Q. Audit log viewer
Every admin action with admin, timestamp, action, target and reason. Queryable by date, admin
and action type.

### R. Ops dashboard (Phase 10c)
KPI cards — open items across every queue, bookings today and this week by status, active/trial/
paid provider counts, listings against the launch-mode threshold. Two trend lines: bookings over
time, and **trial-to-paid conversion split by price cohort**, which is what makes the
introductory-rate decision measurable rather than a guess. Plus a recent-activity feed off the
audit log.

### Shared conventions for every list above
Filter by status, date and type; sortable columns; server-side pagination **with a visible total
count**; a shared date-range control with presets (today, 7 days, 30 days, custom); and CSV
export of the current filtered view under rule 6.

---

## Do not design these — declined for v1, on the record

Bulk queue actions and keyboard triage · a proactive risk-signal dashboard (Phase 22's
contact-pattern and cancel-pattern signals stay report-driven, surfacing beside a filed report)
· second-admin sign-off · admin IP allowlisting · admin-defined feature flags · provider
broadcast messaging · any general force-cancel or booking state override beyond dispute and
`payment_unresolved` resolution.

Leaving these out is not an oversight to be helpfully corrected — each was raised and declined.

---

## Checklist

- [ ] Eighteen screens, one visual system, desktop-first
- [ ] Receipt findings read as advisory; the word "verified" appears nowhere
- [ ] `couldn't read` looks like a normal outcome, not an error
- [ ] The CSV row visibly outranks the receipt where both exist
- [ ] No ban or hard-delete control anywhere
- [ ] View-as-user says why message content is absent
- [ ] Every queue shows its oldest item's age and its SLA state
- [ ] Sidebar counts, one severity treatment, kill-switch banner
- [ ] The `bookingMode` refusal names its blocking listings
- [ ] Three independent email switches, not one
- [ ] Identity documents: re-auth to view, and a decided case with purged images still reads
- [ ] Nothing from the declined list appears
