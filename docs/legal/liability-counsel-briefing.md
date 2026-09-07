# Briefing for legal counsel — RaajjePro's liability position

> **Status: a factual briefing prepared for counsel, 2026-09-07. It is not
> legal advice, contains no legal conclusions, and is not draft legal text.**
> Its only purpose is to describe accurately what the platform does, so that
> counsel can answer the question in §6 without having to reverse-engineer the
> product. Every factual claim below is drawn from `01_Development_Plan_v5.md`
> revision 5.20 and is current as of this date. Nothing here should be reused
> as customer-facing or contractual wording.

**The question in one line:** RaajjePro is built as a marketplace, but it
verifies its providers' identities, restricts who may take emergency work,
publishes performance metrics, and broadcasts urgent jobs. Does a marketplace
position — "we introduce, we do not perform" — survive that degree of
curation under Maldivian law, and if not, where is the line?

The plan records this as unresolved and states it must be settled **before
emergency dispatch goes live** rather than after an incident.

---

## 1 · What the platform is

RaajjePro is a mobile marketplace for local services in the Maldives —
cleaning, plumbing, electrical, AC repair, beauty, photography, pest control,
appliance repair, moving, fitness, home repairs and boat charter. Customers
browse or search, choose a provider, and agree a job. Providers are
independent businesses and sole traders; none is an employee, contractor or
agent of RaajjePro, and the platform assigns no work.

Three booking modes exist:

- **Slot** — the provider publishes available times; the customer picks one.
- **Request** — the customer proposes a window; the provider replies with a
  concrete time and price.
- **Emergency** — available on plumbing, electrical, AC repair and moving
  only. Described in §3 below because it is the most consequential.

## 2 · Where money moves, and where it does not

**RaajjePro never handles payment for any job.** The customer pays the
provider directly and entirely off-platform — cash or bank transfer between
the two of them. The platform has no visibility of whether payment happened;
both sides simply tell it what they claim. The interface is deliberately
worded to reflect that ("Provider confirmed receipt", never "Payment
verified").

The platform collects only two things, both by manual bank transfer confirmed
by a human:

1. **A provider subscription** — MVR 150 per month, or MVR 75 for the first
   100 providers. Charged to providers, never to customers.
2. **An emergency dispatch fee** — MVR 200, charged to the **customer**, once,
   when they select an emergency offer.

Every customer-facing feature is free. Nothing a customer does is ever gated
behind a payment.

## 3 · The four things that make this more than a listings board

These are the facts we believe bear on the question. They are stated plainly,
including where they are unflattering.

### 3.1 The platform verifies provider identity, in three tiers

- **Bronze** — a RaajjePro administrator checks a government identity
  document and confirms the provider's phone number by calling it.
- **Silver** — Bronze, plus verified work history. Also reachable
  automatically after five clean completed bookings, with no human review.
- **Gold** — Silver, plus business registration documents.

The tier is displayed to customers with specific wording: *"ID checked by
RaajjePro"*, *"ID checked, work verified"*, *"ID checked, registered trade"*.
A provider may hold no tier at all and still be fully listed and bookable.
The interface never displays a bare "Verified".

**Why this matters to the question:** the platform is making a positive
representation, in its own name, that it checked something.

### 3.2 The platform restricts who may take emergency work

Emergency jobs are available only from providers at or above a minimum tier
set per category — **Gold** for electrical and plumbing, **Silver** for AC
repair and moving. A provider below that tier cannot receive emergency
requests at all.

**Why this matters:** RaajjePro is deciding, by its own criteria, who is
permitted to attend an urgent job in a stranger's home at night.

### 3.3 The platform publishes performance metrics it computes itself

Completion rate, cancellation rate, no-show rate, on-time rate, price
adherence, acceptance rate and median response time — all computed from
booking outcomes over a rolling 90 days, hidden entirely below 10 completed
bookings.

These are **numbers only**. The platform never generates an editorial label; a
proposal to display phrases such as "prone to cancel" was considered and
rejected. Providers see their own metrics before customers do.

**Why this matters both ways:** the platform influences who gets hired, but it
publishes measured facts rather than opinions or recommendations.

### 3.4 The platform broadcasts emergency jobs — but never chooses the provider

This mechanism matters more than any other and is easily misdescribed:

1. A customer submits an emergency request.
2. It is broadcast **simultaneously to every eligible provider** in that
   category. It is never aimed at one provider.
3. Providers who wish to may accept, each stating their own callout fee and
   their own arrival estimate.
4. The first acceptance opens a **90-second window** during which others may
   also accept.
5. The customer is shown **up to three offers side by side and chooses one.**

So the platform transmits the request and enforces eligibility, but **the
customer selects the provider, and the provider sets their own price and
their own arrival estimate.** RaajjePro sets neither, and recommends nobody.
Arrival estimates are shown as the provider's own estimate and never as a
platform commitment.

## 4 · What RaajjePro does promise, in its own name

One thing, and it is deliberate: a **callback guarantee**. On eligible
categories, where a provider opts in per listing, a customer whose problem
recurs within 7 days can claim a free return visit. The platform enforces this
— a claim creates a new, linked, zero-cost booking — and a provider who
refuses an honoured claim goes to a dispute queue and takes a rating penalty.

This is the clearest instance of RaajjePro standing behind an outcome rather
than merely introducing two parties, and counsel should treat it as such.

## 5 · What RaajjePro explicitly does not stand behind

- **Provider warranties.** A provider may state a warranty; the platform does
  not check it, does not adjudicate it, and displays it attributed —
  *"Provider states: 90-day workmanship warranty"*. Never with a check mark,
  a shield, or the word "verified".
- **Insurance.** A provider may declare public liability cover. **It is not
  verified and not required** — including for emergency work. A Gold provider
  may voluntarily attach a certificate, and where an administrator has sighted
  one the listing says *"Insurance certificate on file"*.
- **Phone numbers.** Collected but never verified as belonging to whoever
  supplied them, and never displayed with a check mark. Exactly one endpoint
  in the entire system ever reveals a phone number to another user, on
  emergency bookings only, mutually and on the customer's initiative.
- **Messages.** In-app messaging is not end-to-end encrypted, is readable by
  an administrator during a dispute, and the interface says so.

## 6 · What we are asking

1. **Does a marketplace or intermediary position survive the four facts in
   §3** — identity verification represented in the platform's own name,
   tier-gating of emergency work, published performance metrics, and emergency
   broadcast — under Maldivian law? If it survives some but not all, which?
2. **What is RaajjePro's exposure when work goes badly wrong** — property
   damage, injury, or death — where the provider was verified by RaajjePro,
   was permitted by RaajjePro's tier rule to attend, and was reached through
   RaajjePro's emergency broadcast? Does the answer change between the three
   booking modes?
3. **Does the callback guarantee (§4) change the position**, being a promise
   the platform makes and enforces itself?
4. **Does not requiring insurance for emergency work increase exposure**, and
   would requiring it reduce it enough to be worth the cost described in §7?
5. **What must appear in the Terms of Service and Provider Agreement** to
   support the position you advise? We have deliberately written no such text
   yet.
6. **Is any registration, licence or insurance required of the platform
   itself** to operate this model in the Maldives?

## 7 · Two product decisions that turn on your answer

Both are recorded as revisitable specifically pending this advice.

- **Insurance is optional, not mandatory, including for emergency work.** The
  reasoning was supply, not risk: emergency work is already restricted to Gold
  in two categories, few sole traders in this market carry cover, and
  mandating it risks an emergency pool that is empty at launch — which fails
  customers more reliably than the uninsured case it prevents. **The plan
  states this should be revisited if this advice comes back badly.**
- **Emergency dispatch is in scope for version 1.** If the exposure is
  unacceptable, the mode can be removed without disturbing the other two — but
  that decision needs to be taken before it launches, not after an incident.

## 8 · What we are not asking

We are not asking for drafted Terms of Service or a Provider Agreement in this
engagement, and we have not written any such text ourselves — nor will we
without your input. We are asking for a position and its reasoning, so the
product can be built to fit it rather than papered over afterwards.
