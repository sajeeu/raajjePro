The last session. Build the provider's business surfaces: **My performance**, **Analytics**, **Verification**, **Billing & subscription**, **Pay by bank transfer**, and **Invoices**.

**Attach:** nothing — no mockup exists for any of these. Propose the design, inheriting the vocabulary already built. `My Services` and `Become a Provider` are the nearest relatives.

**Import the components**: `VerificationBadge` · `Chip` · `StatusPill` · `EmptyState` · `SkeletonCard`. Cast: Ibrahim Rasheed, tier **Silver**, four listings (Home Deep Cleaning, AC Service & Repair, Sunset Fishing Charter, and the Wiring & Fault Repair draft), 47 completed jobs.

Suggested artboards — your call on the split:

- `My Performance` — metrics, the bookings behind them, threshold alerts, appeal
- `Analytics` — per-service, premium-gated
- `Verification` — the tier ladder and document submission
- `Billing` — subscription state, plan comparison, pause
- `Pay by Bank Transfer` — the payment submission and its states
- `Invoices`

---

## The three rules this session is most likely to break

**1. Metrics are numbers. There are no labels.** Show `3% cancelled`, never "Prone to cancel". Editorial labels were considered and rejected outright as automated public accusations with defamation exposure. Every euphemism counts — no "needs improvement", no red "poor" chip, no letter grade, no emoji verdict. Colour may mark a *threshold the provider has crossed against their own targets*, never a character judgement. Show the number; let the reader conclude.

**2. Premium does not include the verification badge, and the badge never lapses with a subscription.** These are the two most confusable systems in the product, and putting them on one screen is exactly where they get merged. The badge is a **safety signal gated by `verificationTier` alone**; the subscription is a payment state. Say so plainly on the Billing screen, in the plan's own words: *it does not include the verification badge*. A lapsed-but-verified provider keeps Silver.

**3. There is no card, no gateway, and nothing activates on submission.** Payment is a manual bank transfer with a reference code, confirmed by an admin within **48 hours**. The submitted state is `pending admin confirmation`, and **pending grants exactly what no payment grants** — nothing. No screen may imply instant activation, show a card form, or animate a success state on submit.

## My performance

The provider sees their own conduct numbers before anyone else does.

- The same metrics the public profile shows: `94% completed` · `3% cancelled` · `2% no-show` · `91% on time` · `97% price honoured` · `usually responds in 12 minutes` · `47 jobs completed`
- **The bookings underneath each number, listed.** Nobody should learn their own on-time rate from a customer — tapping a metric shows which bookings produced it
- **Rolling 90 days**, stated. Nothing is public below **10 completed bookings**
- **Threshold alerts** naming the bookings that caused them and what would clear them: `Your cancellation rate crossed 15%. Three cancellations in the last 90 days.`
- **The consequence ladder, in order, stated honestly:** an alert first, then lower search placement, then losing emergency work, and only then a human review. **Never an automatic account action** — nothing here suspends anyone
- An **appeal** route for a booking the provider says shouldn't count
- **Below-floor state:** `New provider · 4 jobs completed` and nothing else. No zeros, no empty percentage rings — a 0% that means "no data" reads worse than no number at all

## Analytics

Per-service performance. **Premium only.**

- Per service: views, bookings, conversion, rating trend, response time
- `No data yet` where there is none — never a zero standing in for absent data
- **Free-tier state shows what this screen would show and what unlocks it.** Never a blank wall or a bare paywall — the provider should see the shape of what they're missing

## Verification

The tier ladder, and how to climb it. Copy the requirements exactly:

| Tier | Requires | Says publicly |
|---|---|---|
| **Bronze** | national ID or passport matching the account name | `ID checked by RaajjePro` |
| **Silver** | Bronze + photos of completed work + **either** a customer reference RaajjePro contacts **or** 5 completed bookings with no unresolved dispute | `ID checked, work verified` |
| **Gold** | Silver + a business registration **or** a recognised trade certificate | `ID checked, registered trade` |

The tier copy lives in `VerificationBadge` — import it, don't restate it.

Facts that must be conveyed:

- **The 5-bookings route to Silver is automatic.** No submission, no review, no waiting
- **A tier is not needed to be listed or booked.** A provider at no tier is fully visible and fully bookable
- **Emergency work needs a tier** — Gold on Electrical and Plumbing, Silver on AC Repair and Moving
- **The badge does not depend on the subscription** and never lapses with it
- An admin **confirms the phone number** as part of the ID check — that is the only point at which the number becomes a checked fact. Never render a phone number with a tick anywhere on this screen
- **Documents are deleted 90 days after the decision**, stated plainly at the point of upload
- **Tiers never expire** and there is no annual recheck

States: current tier, what the next needs, upload in flight, **review pending**, **rejected with a real reason and a route to resubmit**.

## Billing & subscription

- **Current state**, one of: `Trial · 18 days left` · `Premium · next payment 12 Sep` · `Free` · `Paused · 6 days of 10 used` · `Expired`
- **The price this provider actually pays** — `MVR 150/month`, or `MVR 75/month` for the first 100 providers. **There is no single platform price**; two providers may legitimately see different numbers, and the screen must never imply otherwise. Where the introductory rate applies: it holds **12 months from the billing anchor**, then becomes MVR 150 with **30 days' notice**
- **Never say "monthly" as though it meant calendar month.** Billing runs in **30-day periods from an anchor date**, and pausing shifts the anchor by however long the pause lasted. Show the next billing date; don't imply month boundaries
- **Free** — 1 active service, full search visibility, no analytics. **Premium** — multiple services, analytics, weekly digest, priority placement, and *not* the badge
- **Try Premium** for a provider who has never trialled; the trial is **30 days**
- **Pause** and its real terms: **10 cumulative days**, resumable, remaining allowance preserved if you resume early, auto-resumes at the cap, and the billing date moves by the paused duration
- **Lapsing hides, never deletes.** Services beyond the first are hidden and one confirmed payment brings them all back. Two details that matter: a listing with a live booking is **protected and stays visible regardless of the cap**, and among the rest the **highest-performing listing** is the one kept — by confirmed bookings over 90 days — **with the provider able to override which one**
- Warning **7 days** before a trial or period ends; **7 days grace** after expiry with nothing changing
- **Design this to render on the web as well as in the app.** The App Store may refuse in-app bank-transfer billing; if it does, this page moves to a browser and the app shows state only. Avoid anything that only works as a native sheet

## Pay by bank transfer

- The amount, **RaajjePro's bank details**, and a **reference code** (`RP-2026-0842`, illustrative) with a copy action
- Proof-of-transfer upload, and submit
- **Nothing activates on submission** — `pending admin confirmation`, up to **48 hours**
- **Rejected state:** the reason verbatim, plus **resubmit immediately** and **appeal**. There is no cooldown
- A route to the **Provider Agreement**, where it's most relevant. Legal text stays visibly placeholder — never write anything that could pass as final policy

## Invoices

One entry per confirmed payment: date, amount, period, reference code, PDF download. **No GST line at launch** — design so one could be added later without a redesign. Empty: `No payments yet`.

## Guardrails

- No editorial labels, anywhere, in any state
- No card fields, no gateway, no "instant activation", no escrow
- Money as MVR; the price is per-provider, never a global constant
- No phone number rendered with a tick; no "Payment Verified"
- Categories are the Round 26 twelve; callback is the six repair categories only (Round 28) and doesn't belong on these screens
- Photos and documents uploaded, never hotlinked
