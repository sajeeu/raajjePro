Design the emergency booking flow for RaajjePro — five screens.

This is the hardest flow in the app and nothing in the existing design set resembles it. A customer has a burst pipe or a dead circuit and needs somebody now. The request goes out to every qualified provider at once, several answer with their own callout fee, and the customer picks from up to three offers side by side. Two of these screens are pure waiting, and making waiting feel alive rather than stalled is most of the work.

Design all four states for every screen — loading, empty, error, populated — plus the extra states named per screen below.

**Attach:** `Become a Provider.dc.html` and `round-16-redraws.html`. **No mockup image exists for any of these five screens** — that is why this session goes first, and there is no drawn layout to argue with. Match the attached files for tokens, spacing, type and component style only.

---

## Fixed data — use these values verbatim, invent no figures

**People**
- `Aishath Nazim` — the customer, in Malé
- `Ibrahim Rasheed` — provider · Plumbing · **Gold** · `Rasheed Plumbing Services`
- `Hassan Waheed` — provider · Electrical · **Gold**
- `Ahmed Shakir` — provider · AC Repair · **Silver**

**Money** is written code-first: `MVR 350`. No currency symbol, no decimals on whole numbers.

**Verification is three tiers, each with its own words.** `Bronze` — "ID checked by RaajjePro" · `Silver` — "ID checked, work verified" · `Gold` — "ID checked, registered trade". Never a bare "Verified". A provider with no tier shows no badge at all — absence is the signal, never a grey "unverified" chip.

**Emergency is available on four categories only:** Plumbing, Electrical, AC Repair, Moving.

**Eligibility is per category, and this is not a detail:** **Gold** is required for Electrical and Plumbing, **Silver** for AC Repair and Moving.

**The response window is `30 minutes` on every emergency category, Moving included.** A mover answers as fast as a plumber; what takes two hours is arriving, and that is stated per offer instead. Read the number from the category rather than writing it into the screen.

**RaajjePro charges the customer `MVR 200` per emergency dispatch** — the only thing a customer is ever charged for. It is incurred when they pick a provider, never on submitting a request, and it is settled afterwards by bank transfer.

---

## Screen 1 — Emergency request

Something is broken now. The customer describes it and sends it out.

- Convey before anything else: this is for **urgent problems only**, and it costs `MVR 200` to dispatch
- Job description, free text
- Address and island
- Convey: the request goes to **every qualified provider at once**, not one at a time
- Convey: qualified means the provider holds the tier this category demands — Gold for Electrical and Plumbing, Silver for AC Repair and Moving
- Convey: the whole window is `30 minutes` on this category — state the real number
- Convey: the `MVR 200` is charged **only when the customer picks someone**. A request nobody answers costs nothing
- A submit action
- **Extra state — over the limit:** `3` requests per `24 hours`, `10` per `7 days`. Design what a customer sees at the limit, and give it a route to a normal booking rather than a dead end

## Screen 2 — Waiting

The request is out. This screen must not look stalled — something has to show it is live.

- A countdown on the overall window: `26:14 remaining`
- How many providers it reached: `Sent to 4 providers`
- What happens next, in plain terms
- A cancel action
- **Extra state, and it needs its own treatment — offers collecting:** once the first provider answers, offers are gathered for `90 seconds` before the customer sees any of them. The customer sits through this interval. Waiting a moment longer is what gets them a choice instead of a single take-it-or-leave-it, and the screen should make that feel like something working in their favour rather than a delay

## Screen 3 — Offers

Providers have answered. The customer picks one. **This screen has no precedent anywhere in the app or in the existing designs.**

- **Up to three offers, side by side**, each carrying provider name, verification tier, rating, distance and callout fee:
  - `Ibrahim Rasheed` — Gold — `4.6` — `1.2 km` — `MVR 350`
  - `Hassan Waheed` — Gold — `4.9` — `2.8 km` — `MVR 450`
  - `Ahmed Shakir` — Silver — `4.4` — `0.8 km` — `MVR 500`
- Accept on each, and a reject-all action
- **Two countdowns, and both matter:** `4:31` to respond to these offers, and `21:06` left on the overall request. The customer has to be able to see what rejecting costs them
- Convey: the callout fee is **what the provider charges to attend**. "The final bill may differ" — parts and labour are settled directly with the provider afterwards
- Convey: accepting incurs the `MVR 200` dispatch fee, paid to RaajjePro afterwards by bank transfer
- **Extra state — fewer than three:** one or two offers is normal and must not read as a failure
- **Extra state — none yet:** the request is still live and new offers can still arrive

## Screen 4 — Nobody came

The window expired with no accepted offer.

- Message: `No one accepted in time`
- Two actions: try again, or turn this into a normal scheduled request
- Convey: nothing has been charged

## Screen 5 — Provider: accept with your fee

The other side. A provider sees the job and answers with what they charge to attend. The fee is part of accepting, not a later step.

- The job: description, island, distance, how long ago it came in
- **A callout fee entry**, `MVR` prefixed
- Convey: this is **what you charge to attend** — parts and labour are settled directly with the customer afterwards
- Convey: **other providers are being asked too**, and the customer picks from up to three. This is a competitive bid, not a race — answering first does not win it
- One accept action carrying the fee
- **Extra state — offer submitted:** the customer has `5 minutes` to choose
- **Extra state — not chosen:** the customer went with someone else. Say it cleanly, give no reason, and never leave them on a spinner

---

## Rules that override anything else

- **Never claim a payment was verified.** RaajjePro cannot see a bank transfer. No lock, no shield, no "Paid ✓" anywhere.
- **Never generate a judgement about a provider.** Show numbers — `4.6`, `1.2 km` — never a label like "Reliable" or "Fast responder".
- **Never render a bare "Verified".** Three tiers, each with its own copy.
- **Never show a countdown that lies.** The numbers above are the real windows and they differ by category.
