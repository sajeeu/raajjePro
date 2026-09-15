# Phase 10a part 1 — Provider Billing

Built 2026-09-15 against `01_Development_Plan_v5.md` §Phase 10a part 1, §1b
and §0.4 (plan revision **5.31**, with one correction taken from **5.32**
while the build was running — see §7). Flutter, plus the backend that half of
the phase needed.

**Part 2 — the admin panel — was not built.** The owner's instruction on
2026-09-15 was to build Part 1 and the rest of the phase around it and to
leave the panel until called for. §8 says what that costs the phase's
Done-when.

---

## 1. An appeal is a re-review request on the rejected row

Ledger row **P8A-1** had been open since §Phase 8a: §1b step 5 and §Phase 10a
both offer a rejected provider "resubmit **or** appeal", §Phase 10a's
Done-when tests "working resubmit and appeal", and no section said what an
appeal *changes*. §Phase 8a declined to invent it. This phase needed it, so
it went to the owner with three shapes and came back settled.

**What was built.** `POST /v1/providers/me/payment-submissions/:id/appeal`
stamps `appealedAt` and an optional `appealNote` on the **rejected** row.

- **It changes no status.** The row stays `rejected`; the entitlement stays
  exactly what a rejection left. An appeal is a request, not a state a
  payment sits in — which is what the ledger row predicted was the right
  answer, and the reason a fourth `PaymentSubmissionStatus` value was never
  a candidate.
- **One per submission.** A second re-review request has nothing new to say,
  and `PAYMENT_APPEAL_ALREADY_FILED` names the first one's date.
- **A reversal is appealable.** §1b's reversal lands the row as `rejected`
  with its own stamps, and a provider may disagree with a reversal exactly as
  they may with a rejection.
- **Resubmit and appeal are independent.** Appealing does not stop a provider
  paying again properly, and paying again does not withdraw the appeal. Both
  are in front of the admin.
- **Audit-logged as the provider**, `payment_submission.appealed`, with the
  note deliberately **not** in the metadata: it is the provider's own words on
  their own row, and audit metadata is ids, enums and counts (root
  `CLAUDE.md` 1d).

🔧 **§1b step 5 is what settled it, and the next reader should not reopen it.**
The sentence reads "resubmit immediately — no cooldown — or **appeal for
re-review**". The plan does say what an appeal is *for*; what it never said
was what it changes. A re-review request is that sentence implemented and
nothing more. The admin outcomes on an appealed row — overturn, or uphold with
a reason — are §Phase 10a part 2's, and the queue lists a rejected row with
`appealedAt` set and no later decision.

**Row P8A-1 closes here.**

---

## 2. The billing screen carries the pause consequence — row P8A-4

§1b's pause "keys off the provider-level `acceptingNewCustomers` toggle", and
a clock that starts under an already-off toggle starts paused. So the toggle
has a billing consequence that has to be **said** rather than discovered.
§Phase 6a was resolved (no subscription there, so no consequence to describe)
and §Phase 10 answered (its dashboard renders no toggle). The sentence was
owed by this screen alone.

It is in the pause card, which is where the effect renders beside a live
subscription:

> Pausing is the same switch as "Accepting new customers" in your provider
> profile — turning that off pauses billing too. Either way it spends this
> subscription's 10 pause days, which don't refill, and moves your billing
> anchor by however long you paused.

Three facts, each one §1b's: **the same switch**, **a per-subscription
ten-day allowance that does not refill**, and **the anchor moves**.

🔧 **The pause card renders during the trial as well as on a paid period**,
where `Billing.dc.html` draws it on the premium state only. §1b: "the
identical mechanism applies to the trial period — one function, one cap, one
resume rule, shared by `trialing` and `active`". A card that appeared only
when paying would hide a control the trial has.

**Row P8A-4 closes here.**

---

## 3. Two CTAs, because they are for two different people

§Phase 10a's first bullet asks for "upgrade CTA, **and** 'Try Premium' CTA for
a provider who has never started a trial" (§0.4). They are not two labels for
one button:

| Who | What renders |
|---|---|
| Free, never trialled | **Try Premium free for 30 days** — and no pay CTA |
| Free, trial used | **Pay by bank transfer** — and no trial CTA |
| Trialing / premium / expired | **Pay by bank transfer** |
| Paused | **Resume now — keep the N unused days** |

`trial.available` is the server's field and the only thing that decides it. A
provider who has had a trial never sees the offer again, which is §1b's one
trial per account made visible rather than enforced only on the endpoint.

---

## 4. No billing rule is evaluated in Flutter, and two fields were added to make that true

Round 19 (§Phase 23) is a **build requirement** on this phase: keep the
billing UI "behind a boundary thin enough to re-render on the web — no billing
logic in Flutter widgets, all of it behind the same endpoints the admin panel
uses. A rejection must cost a port, not a rewrite." Invariant 4 says the same
thing for a different reason.

Two dates the artboards print were not on the wire, so they were **added to
the server's DTOs additively** rather than computed in Dart:

- **`billing.nextPeriod`** — the 30-day period the next confirmed payment
  would buy, on both `GET /v1/providers/me/subscription` and the
  upgrade-request response. `Pay by Bank Transfer.dc.html` prints "Premium ·
  13 Sep – 12 Oct".
- **`billing.graceEndsAt`** — when §1b's seven days of grace run out.
  `Billing.dc.html`'s expired state prints "without a confirmed payment by
  6 Sep".

🔧 **Both are one function on the server, shared with the confirmation.**
`periodAPaymentWouldBuy` is now called by `requestUpgrade` (the quote) and by
`confirmSubmission` (the fact), so what the screen shows is what the invoice
will say — asserted by a test that pays the quoted period and reads the
invoice back. Computing either in Flutter would have drifted from the server
the first time anyone paused, because §1b's anchor is explicitly not a
calendar month and **pause shifts it**.

`bankTransfer` was also added to the status DTO, so the pay screen can resume
an intent the provider already opened — and the reference code they may
already have written on a transfer — without creating a second one just to
learn where to send the money.

---

## 5. Nothing is queued offline, and the artboard said otherwise

`Pay by Bank Transfer.dc.html` carries a `pending-offline` state: *"Saved on
this phone — sends on reconnect… no need to keep the app open."*

**Not built.** §0.0 item 14 bounds the offline queue to exactly three
surfaces — the wizard's autosave, the slot/request accept prompt and chat
sends — and a payment submission is none of them. Beyond the scope rule, the
copy is a promise about **money** that nothing keeps: no code queues it and
none would send it.

What renders instead: the form exactly as it was, the receipt still attached,
and a notice with a live retry. The test asserts the absence of both
sentences, not just the presence of the notice.

---

## 6. Three more places the screens differ from their artboards

All three were checked against the plan before anything was written, and all
three go back to the design project as `docs/design/sessions/round-59-billing-corrections.md`
rather than being fixed in the prototype — the project is the source and the
repo is the copy.

1. **"Same page on the web — nothing here needs the app"**, the Billing
   header's subtitle. A web billing page exists only as §Phase 23's App Store
   contingency, *if* App Review refuses the in-app flow. The screen states it
   as present fact. **No subtitle renders.**
2. **"appeal and a second person looks at it"**, in the rejected state. Root
   `CLAUDE.md` lists **second-admin sign-off** among the things deliberately
   out of v1 scope, by name. The screen says "an admin looks at it again",
   which is what the system does.
3. **`MVR 150` printed beside the introductory rate.** §1b: the price is
   per-provider and "never a global constant". The standard rate is not on the
   wire for a provider who is not paying it, and printing it would be exactly
   the pinned platform price §1b removed. The copy names the cohort, the
   twelve months and the conversion date **without a second number**.

---

## 7. One copy correction taken from plan revision 5.32, mid-build

§0.0 item 19 landed while this was being built: a submission whose
bank-statement row matches on all four of reference, amount, account and
period now **confirms without a human**. That is Part 2's mechanism and
nothing here implements it — but it made this screen's copy wrong in one
respect, because it named the reviewer:

| Was | Now |
|---|---|
| "Pending admin confirmation" | "Pending confirmation" |
| "An admin matches the transfer against your reference code" | "Your transfer is checked against the bank statement using your reference code" |
| "until an admin confirms the transfer" | "until the transfer is confirmed" |
| "confirmed by an admin within 48 hours" | "confirmed within 48 hours" |

The wait, the 48 hours and "nothing activates on submission" are unchanged and
are the part a provider actually needs. Naming the reviewer would now be wrong
in the case that no longer has one.

---

## 8. What this leaves open, and what it does not claim

**§Phase 10a's Done-when spans both parts, and two of its five lines cannot be
asserted without Part 2:**

| Done-when clause | State |
|---|---|
| a provider submits with proof and sees pending | **Met**, end to end through the real route table |
| a rejection surfaces its reason with working resubmit and appeal | **Met**, likewise |
| an admin confirms and the entitlement activates | The endpoint is §Phase 8a's and is tested there; **no panel confirms it** |
| CSV import proposes correct matches | Part 2 — not built |
| the three XSS payloads render inert in every admin view | Part 2 — there is no admin view |
| an aged `payment_unresolved` item triggers its alert | Part 2 — and the queue does not exist |

**So the phase stays open.** Part 1 lands as a verified increment; §Phase 10b
does not start off the back of it.

Three new ledger rows: **P10A-1** (the Done-when half Part 2 owes),
**P10A-2** (the invoice PDF against a real object store) and **P10A-3** (the
receipt picker and the presigned PUT on a real device).

---

## 9. Where the code is

| Piece | Where |
|---|---|
| The appeal endpoint, its schema and its audit entry | `backend/src/modules/subscriptions/{routes,schema,service}.ts` |
| `appealedAt` / `appealNote` | `backend/prisma/schema.prisma`, migration `20260915130000_phase10a_payment_appeal` |
| The quoted period and the grace end | `subscriptions/types.ts`, `periodAPaymentWouldBuy` in `service.ts` |
| Backend tests | `backend/test/phase10a-part1.test.ts` |
| The three screens | `frontend/lib/features/billing/presentation/` |
| The wire models and the API | `frontend/lib/features/billing/data/` |
| The three controllers | `frontend/lib/features/billing/controller/` |
| Frontend tests | `frontend/test/features/billing/` |

**Three things moved on their second consumer**, which `lib/README.md` calls
the convention rather than a refactor: `shareProvider` and `tempDirProvider`
out of `features/account/` into `core/files/` (the invoice PDF is the second
thing this app hands to a share sheet), the accent icon disc out of
`features/my_services/` into `shared/cards/row_icon.dart`, and `mvr()` into
`core/format/money.dart` as the one place integer laari becomes a string.
