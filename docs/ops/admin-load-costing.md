# Admin load against launch revenue

**Requested by plan §4 Sequencing ("Do before Phase 0 — Round 15"), delivered
2026-09-07 — overdue rather than backlog: Phases 0–2 were built without it.**

> Put hours against every manual step — identity review, the confirmation
> call, CSV reconciliation, disputes, the recovery queue — at 50, 200 and 500
> providers, against subscription income at those counts.

**Every effort figure below is an assumption, not a measurement.** None of
this work has been performed yet, because the queues that generate it are
Phase 10a. The model is built so each assumption is visible and replaceable:
correct one number and the conclusions move with it. What matters more than
the totals is which number the answer is *sensitive* to, and that turns out
to be a single one.

## What the model assumes

| Manual step | Minutes | Source of the estimate |
|---|---|---|
| Bronze identity review + confirmation call | 10 | assumption |
| Payment confirmation, CSV auto-matched | 1.5 | assumption — one click after the matcher proposes |
| Payment confirmation, manual receipt | 4 | assumption — reading the advisory analysis, then deciding |
| Unmatched-transaction resolution | 6 | assumption |
| Booking dispute | 25 | assumption |
| `payment_unresolved` case | 20 | assumption |
| Recovery queue (squatting, recycled numbers) | 15 | assumption |

| Volume driver | Value | Note |
|---|---|---|
| CSV auto-match rate | 70% | the rest need a manual receipt read |
| Unmatched transactions | 10% of payments | garbled reference, split transfer |
| Disputes | 2 per 100 bookings | **the number the answer hinges on** |
| `payment_unresolved` | 1 per 100 bookings | |
| New providers per month | 10% of base | steady growth |
| Identity reviews per new provider | 1.2 | includes rejected resubmissions |
| Bookings per provider per month | **4 / 8 / 12** | rises with density — see below |
| Working days per month | 22 | |
| Admin cost | MVR 12,000/month, 168 h | **the figure I am least sure of** |

**Bookings per provider rise with scale, and that choice is load-bearing.**
The plan's own reasoning — "admin load grows faster than revenue because
disputes track bookings rather than signups" — is only true if a provider in
a denser marketplace takes more jobs. Held flat, every line scales linearly
with providers and the plan's warning cannot be reproduced. Modelled as
4 → 8 → 12, it can be tested.

## The result

| | 50 providers | 200 | 500 |
|---|---|---|---|
| Identity review + call | 1.0 h | 4.0 h | 10.0 h |
| Payments (CSV matched) | 0.9 h | 3.5 h | 8.8 h |
| Payments (manual receipt) | 1.0 h | 4.0 h | 10.0 h |
| Unmatched transactions | 0.5 h | 2.0 h | 5.0 h |
| **Booking disputes** | 1.7 h | 13.3 h | **50.0 h** |
| `payment_unresolved` | 0.7 h | 5.3 h | 20.0 h |
| Recovery queue | 0.1 h | 0.5 h | 1.2 h |
| **Total per month** | **5.8 h** | **32.7 h** | **105.0 h** |
| Per working day | 0.27 h | 1.48 h | 4.77 h |
| As an FTE | 0.03 | 0.19 | **0.62** |
| Subscription income | MVR 3,750 | MVR 22,500 | MVR 67,500 |
| — in USD | $243 | $1,459 | $4,377 |
| Revenue per admin hour | MVR 643 | MVR 689 | MVR 643 |
| Admin minutes per provider | 7.0 | 9.8 | 12.6 |
| Payment confirmations per working day | 2.3 | **9.1** | 22.7 |

**The model checks out against the plan's own figure.** §1b states manual
review at 200 providers is "~10 confirmations per working day forever". This
model, built independently from per-step estimates, produces **9.1**. That
agreement is the main reason to trust the shape of the rest.

## Four conclusions

**1. Admin load is not the constraint. It costs about 11% of subscription
revenue, at every scale.** 105 hours a month at 500 providers is 0.62 FTE, or
roughly MVR 7,500 of an admin's time against MVR 67,500 of income. The same
ratio holds at 50 and at 200. Revenue per admin hour is flat at about
MVR 650 — nine times what an hour of admin time costs.

**2. The plan's premise does not hold under these assumptions, and the reason
is worth keeping.** §4 expects load to outgrow revenue. It does not, because
the two forces cancel: bookings per provider roughly triple between 50 and
500, and so does revenue per provider as the first-100 introductory rate
(MVR 75) converts to standard (MVR 150). **If that conversion fails, the
margin thins but does not invert** — 500 providers all held at MVR 75 still
yield MVR 357 per admin hour, five times the cost. The conclusion is robust;
the premise it contradicts was a reasonable worry, not a wrong one.

**3. Everything depends on the dispute rate.** Disputes are 29% of load at 50
providers and **48% at 500**. It is the only assumption that changes the
staffing answer:

| Disputes per 100 bookings | Hours/month at 500 | FTE |
|---|---|---|
| 2 (modelled) | 105 | 0.62 |
| 3.5 | 142 | 0.85 |
| 5 | 180 | **1.07** |

At 5 per 100 the platform needs a full-time person for admin alone. Nothing
else in the model comes close to that leverage — halving the identity-review
time saves 5 hours a month at 500 providers; halving the dispute rate saves 25.

**4. The lever §4 named is the right one, and it should be aimed narrowly.**
Round 15 fixed that verification quality is not adjustable — the document
check and the confirmation call stay — and that load must come out of
everything else. Correct: identity review is only 10 of 105 hours, so there
was never much there to take. **The saving is in disputes and in the 30% of
payments the CSV matcher misses.** Lifting auto-matching from 70% to 90%
saves 5 hours a month at 500 providers; reducing disputes by a third saves 17.

## What would make this real

Three things to measure once Phase 10a is live, in this order of value:

1. **Disputes per 100 completed bookings**, and minutes per dispute. Half the
   model rests on these two.
2. **CSV auto-match rate** against real bank statements from more than one
   bank. 70% is a guess about data quality nobody has seen yet.
3. **Bookings per provider per month**, and whether it rises with density at
   all. If it stays flat, load per provider stays flat and the margin
   improves rather than holds.

Until then this document is a sanity check that the operating model is not
obviously broken — which it is not — and a list of what to watch. It is not a
staffing plan.
