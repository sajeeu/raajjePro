# Round 28 — the callback guarantee is per-category

**Status: adopted as Round 28 (2026-08-31). Plan revision 5.14.**

## The decision

The callback guarantee is offered on **six categories only**, read from a seeded `callbackEligible` flag:

| Eligible | Not eligible |
|---|---|
| Plumbing · Electrical · AC Repair · Appliance Repair · Pest Control · Home Repairs | Cleaning · Beauty · Fitness · Photography · Moving · Boat Charter |

Before this it was "opt-in per listing" with no category gate, so a fishing charter could advertise a free return visit.

## Why this line

The promise is **"a free return visit within 7 days if the same problem comes back."** That only means something where a thing was *fixed or treated and can un-fix*. A drain re-blocks, a compressor fails again, bedbugs return, a tile re-cracks — those are recurrences, and a free revisit is a real commitment.

A fishing trip, a wedding shoot, a house move, a deep clean and a haircut either happened or did not. There is no "same problem" to come back. Offering to redo them free is a promise with no referent — and worse, an unenforceable one that RaajjePro would nonetheless be holding providers to.

**Two boundary calls worth recording, because both are arguable:**

- **Cleaning** is the closest case. "You missed a room" feels callback-shaped, but it is a *quality complaint*, not a recurrence — and the review and dispute paths already handle it. A clean does not come back broken.
- **Moving** is where damage happens, but damage is an insurance matter. §1h already forbids rendering a provider warranty in the callback badge's treatment; folding damage into the callback would collapse exactly the distinction that rule protects.

**A coincidence worth keeping visible:** the eligible six are *exactly* the short-quote-window group (120/240). Reactive repair work is quick to quote, short-lead, and the only work a callback can apply to. Two independent groupings landing on the same six is a sign the category model is coherent — if a future round changes one list, check the other.

## How it renders

- On an ineligible category the wizard's step-6 opt-in **does not render at all** — absent, not disabled. There is nothing to explain, so a disabled control with a reason would be noise.
- No callback badge on any card, preview or profile for an ineligible listing.
- The claim path is unreachable for those bookings; the completed-booking chat says nothing about a callback window.

## Enforcement

`verify-dc.py` gains a rule matching an ineligible `cat:` against `cb: true` / `callback: true` in the same object literal. The first regex written for this checked textual proximity of the word "callback" to a category name and **passed on a genuine violation** — `Discovery` carries a Cleaning listing with `cb: true`, with the two fields far apart. A rule that misses the real case is worse than no rule, because it manufactures confidence; the tightened version catches it.
