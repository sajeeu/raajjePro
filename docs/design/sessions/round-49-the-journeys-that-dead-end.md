# Round 49 — the four journeys that dead-end

Round 38 §6 set six acceptance journeys and said each must run start to finish
with no dead end. They have now been run against the link graph of all 61
files. **Two pass. Four stop.**

Nothing is broken in the sense of a bad URL — every link in the prototype
resolves to a file that exists, and no screen is unreachable. What is missing is
five specific edges, and one of them contradicts an invariant.

**Leave alone:** every layout, colour, component, animation and every piece of
copy not named below, and all of Rounds 40–48. This round adds links. It adds
no screen and changes no design.

---

## How they were run

Every navigation in every file — markup `href`, `window.location`, and the
`href:` values inside `ROWS`/`TILES`/route-map objects — was extracted into a
graph, then each journey traced hop by hop. Two results worth stating before the
failures:

- **0 broken link targets.** Every `.dc.html` reference resolves.
- **0 orphans.** Every screen has at least one inbound link.

So this is not wiring rot. It is five gaps in otherwise complete flows.

---

## 1. `Booking Detail` reaches the chat only by accident

**Degrades journey 1.** This is the one that matters most, because it is not a
convenience — it contradicts the rule.

In-app chat is the sole coordination channel for a booking's entire life. There
is no contact exchange to fall back on outside the emergency reveal. Twelve
screens link to `Booking Thread`:

> `Booking Request` · `Emergency Flow` · `Mark Complete` · `Messages` ·
> `Mute Block Decline` · `Notifications` · `Payment Received` ·
> `Propose Amendment` · `Propose Time and Price` · `Provider Emergency` ·
> `Quote Received` · `Reveal Contact`

The booking's own detail screen is not one of them. It reaches the thread only
in two hops, and only through `Propose Amendment` or `Reveal Contact` — screens
a customer opens to change a booking or to swap numbers on an emergency, not to
send a message. There is no direct route.

The relationship is otherwise one-way: `Booking Thread` links **to**
`Booking Detail` twice, from its *View booking ›* header link and its menu.

The screen already refers to the thread without offering it. Its dispute banner
reads:

> RaajjePro is reviewing the record — the timeline below and both sides'
> messages. You'll hear back here.

**Do:** give `Booking Detail` a route to `Booking%20Thread.dc.html`. It belongs
with the existing action rows that already reach `Propose Amendment`,
`Reveal Contact` and `Raise Dispute` — the same treatment, labelled for the
counterparty the way `Quote Received`'s button is (**Message Ibrahim**), not a
generic *Open chat*.

---

## 2. `Booking Thread` dead-ends a provider on a customer's screen

**Blocks journey 4.**

`Booking Thread` became role-aware in Round 41 §6b and correctly shows Aishath
Naeema to a provider. Its way out did not follow. Both exits — the *View
booking ›* link and the menu row — go to `Booking Detail` for everybody.

`Booking Detail` is customer-only. It is one of the 57 screens with no role
branch at all: only `Start`, `BottomNav`, `Profile` and `Booking Thread` read
`RPSession`. So a provider who opens the thread to coordinate a job arrives at a
screen offering **Cancel Booking**, **Dispatch Fee** — a fee charged to the
customer, never to them — **Reveal Contact** and **Raise Dispute**, and has no
route onward. `Booking Thread` carries no `BottomNav`, and `Mark Complete`'s
only inbound link in the entire prototype is `My Calendar`.

So the provider journey stops at the thread. The job cannot be closed from
where the work is coordinated.

**Do:** branch the two exits on role, the way the header already branches:

| | Customer | Provider |
|---|---|---|
| Header link | `Booking Detail` — *View booking ›* | `Mark%20Complete.dc.html` — **Close this job ›** |
| Menu row | `Booking Detail` | `My%20Calendar.dc.html` |

Do **not** give `Booking Detail` a provider mode in this round. It is a
customer screen and making it dual-role is a redesign, not a link.

---

## 3. `Payment Step`'s **View booking** goes to Home

**Blocks journeys 1 and 2.**

The primary button on the confirmation reads **View booking** and links to
`Home.dc.html`.

This is Round 45 §5a exactly, on a third screen. That round found the same shape
on `Pick a Time` and `Request a Time` — *View my bookings* pointing at Home —
and fixed both. `Payment Step` has the stronger version of the defect, because
"View booking" names one specific booking rather than a list.

**Do:** point it at `Booking%20Detail.dc.html`. The two `Home.dc.html` links in
the header — *Back* and *Close* — are chrome and are correct; leave them.

---

## 4. A quote can only be found in `Notifications`

**Blocks journey 2.**

`Quote Received` has exactly two inbound links: `Notifications` and
`Payment Step`. Neither `My Bookings` nor `Booking Detail` reaches it.

A quote arriving as a notification is right. A quote existing *only* there is
not: a customer who clears the notification, or opens the app the next morning,
has nowhere to go. The booking is sitting in `My Bookings` at
`quote_received` — the status `StatusPill` already renders — and tapping it
lands on `Booking Detail`, which does not mention the quote.

**Do:** when a booking is at `quote_received`, `Booking Detail` shows the quote
and links to `Quote%20Received.dc.html`. One route is enough; do not also add
one to `My Bookings`, whose row already carries the status pill and whose job is
to get you to the booking.

Round 38 §7 said not to delete a screen because it is awkward to reach, and to
say so instead. This is that report, with the link named.

---

## 5. After publishing, a provider lands in a customer preview with no way back

**Journey 5 completes, but through a room with one door.**

`Create Service`'s success step offers *View listing* →
`Service%20Preview.dc.html` and *See plans* → `Billing.dc.html`. Both are
sensible. But `Service Preview` is the customer-facing screen, and its outbound
links are all customer ones — `Discovery`, `Pick a Time`, `Request a Time`,
`Enquiry Thread`, `Provider Profile`, `Report`, `Emergency Flow`. None returns
to `My Services`.

So the provider who taps *View listing* to check their own work is standing in
the customer's view of it with no route back to their listings.

**Do:** the smallest honest fix is on `Create Service`, not `Service Preview` —
do not give the customer screen a provider link. Have *View listing* open the
preview and leave a way home: add **My services** beside it on the success step,
pointing at `My%20Services.dc.html`.

`Verification` → `Billing` needs no change. It routes through `My Services`,
which links both, and one intermediate on a settings-to-settings hop is normal
navigation rather than a gap.

---

## 6. Not an instruction — `Notifications` is not on `Profile`

Journey 6 lists `Profile → … Notifications`. It is not linked from `Profile`.

It is reachable — `Home`, `Discovery` and `My Services` all link it, which is
the bell in the shell, and that is where a notification inbox belongs. There is
also deliberately no notification *settings* screen to put on `Profile`: the
plan gives transactional sends no in-app toggle.

So this reads as drift in the journey text rather than a missing link, and
nothing is changed for it. Flagging it so the decision is recorded rather than
rediscovered next time the journeys are run.

---

## 7. The journey text itself is one round stale

Journey 1 in Round 38 §6 still reads *"Book instantly → pick a time"*. Round 44
renamed that affordance to **Pick a time** and the flow is unchanged, so the
journey is right about what happens and wrong about what it is called.

The corrected list, which is what future runs should use:

1. **Customer · slot** — Start → customer → Home → Explore → a Cleaning listing → **Pick a time** → choose a time → send → My Bookings → Booking Detail → chat → *I've paid* → provider confirms → Rate This Job
2. **Customer · request** — Home → a Plumbing listing → Request a time → Quote Received → accept → Payment Step → Booking Detail
3. **Customer · emergency** — Home → *Something urgent?* → Emergency Flow → offers arrive → pick one → dispatch fee owed → Booking Detail → Reveal Contact
4. **Provider** — Start → provider → My Calendar → Booking Request → Propose Time and Price → accepted → chat → Mark Complete → Payment Received
5. **Provider · business** — My Services → the wizard → publish → My Services → Verification → Billing → Pay by Bank Transfer → Invoices
6. **Both** — Profile → Account Settings, Help & support, Saved Preferences, Legal; Notifications from the shell

---

## 8. What must not change

- **No new screens.** All five fixes are links on screens that already exist.
- **No role branch on `Booking Detail`.** §2 solves the provider's exit on
  `Booking Thread`, which is already role-aware.
- **`Service Preview` gains nothing.** It is the customer's screen and stays so.
- **Journey 3 and journey 6 pass** — emergency and the Profile fan-out both run
  clean. Do not touch anything on their paths.
- The two `Home.dc.html` links in `Payment Step`'s header are Back and Close.
- Everything in Rounds 40–48, including Round 48's tile deep links, which were
  verified against `My Bookings`' `FILTERS` and match exactly.

---

## Checklist

- [ ] `Booking Detail` reaches `Booking Thread` directly, labelled for the counterparty
- [ ] `Booking Thread`'s two exits branch on role — provider reaches Mark Complete and My Calendar
- [ ] `Payment Step`'s **View booking** reaches `Booking Detail`
- [ ] `Booking Detail` surfaces the quote and links to `Quote Received` at `quote_received`
- [ ] `Create Service`'s success step offers a route back to `My Services`
- [ ] All six journeys run start to finish — walked by tapping, not by reading
- [ ] Still 0 broken link targets and 0 orphan screens
- [ ] Nothing from Rounds 40–48 changed
