# Round 59 — three claims on the billing screens the product cannot keep

**Three corrections to two artboards, found while building §Phase 10a part 1
on 2026-09-15.** All three are copy, none is layout, and each was checked
against `01_Development_Plan_v5.md` before the Flutter screen was written —
the app already renders the corrected form, so this round is what brings the
prototypes back into line with it.

Change these three things. **Leave everything else in both files alone** —
the structure, the states, the motion and the rest of the copy are right, and
the Flutter build follows them closely.

---

## 1. `Billing.dc.html` — the header subtitle claims a web page that does not exist

The header currently reads:

> Billing & subscription
> **Same page on the web — nothing here needs the app**

**Delete the second line. Render the title alone.**

A web billing page is not a thing this product has. It appears in the plan
exactly twice and both mentions are conditional: §5's risk table says a web
fallback "may also be needed", and §Phase 23 describes it as the **App Store
contingency** — the 3.1.3(f) shape to fall back to *if App Review refuses the
in-app flow*, with the iOS app then showing state only and no price, no bank
details and no upgrade CTA. §Phase 23's decision is to "build Phase 10a's
in-app billing flow as designed and submit it", and to learn empirically.

So the line states as present fact a page that exists only as a fallback that
may never be built — and if it ever is built, it is the fallback for a
*rejected* app, at which point this screen no longer looks like this.

---

## 2. `Pay by Bank Transfer.dc.html` — the rejected state promises a second reviewer

The rejected state currently reads:

> You can resubmit straight away — there's no waiting period. If you think the
> admin is wrong, appeal and **a second person looks at it**.

**Change the last clause to "appeal and an admin looks at it again".**

Root `CLAUDE.md` lists **second-admin sign-off** by name among the things
deliberately out of v1 scope, alongside IP allowlisting and bulk queue
actions. §7's accepted risk is a **single admin**. There is no second person,
there is no plan to add one, and the costed admin model is one person clearing
every queue.

The appeal itself is real and is now built: it is a re-review request stamped
on the rejected submission, which puts the same payment back in front of the
admin. "An admin looks at it again" is exactly what happens.

---

## 3. `Billing.dc.html` — the introductory copy prints the standard price

The price block's explanation currently reads:

> Introductory rate for the first 100 providers, held for 12 months from your
> billing anchor — until **8 Mar 2027**, then **MVR 150** with 30 days'
> notice. Prices are set per provider; another provider may see a different
> number.

**Remove `MVR 150`. Keep everything else, including the conversion date and
the sentence about prices being per provider.** The clause becomes "…then the
standard rate with 30 days' notice."

§1b is emphatic that the subscription price is **per provider**, read from
`providerProfile.subscriptionPriceLaari`, and "never a global constant". Two
price points coexist by design, and the plan's own record says a pinned
platform-wide price is the thing Round 9 removed. A provider on the
introductory rate has no standard rate on their record, so the number is not
theirs and is not on the wire — printing it re-introduces the single platform
price in the one place a provider reads about pricing.

The rest of the block is right and should not change: the big number is the
provider's own next payment, `per 30-day period` is correct and must not
become "per month", and the `YOUR RATE` label is good.

---

## What is already correct and should not be touched

Worth saying, because a correcting round invites tidying:

- **The five plan states** (`trial` / `premium` / `free` / `paused` /
  `expired`) and their copy. The Flutter screen renders all five plus a sixth
  reading of `free` — a **downgraded** provider, where the hiding has already
  happened — and takes the wording from these.
- **"Premium does not include the verification badge"** and the plan table's
  closing line. Both are exactly §1e and §1b.
- **The pause card's four bullets.** The Flutter build adds one sentence after
  them, naming the toggle the pause shares (`Accepting new customers`), that
  the ten days do not refill, and that the anchor moves. That sentence is owed
  by the plan (ledger row P8A-4) and could be added here too, but it is not a
  correction — the four bullets are not wrong.
- **"Pending grants nothing yet"**, on the pay screen. This is §1b's most
  load-bearing sentence on the whole surface and is well put.
- **`Invoices.dc.html` entirely.** Nothing in it needed correcting.

---

## One note, not a change request

Since these artboards were drawn, plan revision **5.32** (§0.0 item 19) made a
payment confirm **without a human** where an imported bank-statement row
matches the submission on all four of reference code, amount, destination
account and billing period. The Flutter copy no longer names the reviewer as a
result — "Pending confirmation" rather than "Pending admin confirmation",
"checked against the bank statement" rather than "an admin matches the
transfer".

The prototypes' "up to 48 hours" and "an admin confirms" are not *wrong* for
the manual path, which is still most of them. If this round is being applied
anyway, matching the Flutter wording would keep the two in step; if not,
nothing breaks.
