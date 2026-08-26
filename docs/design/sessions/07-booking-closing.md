Build the screens that close a booking out: **Did this happen?**, **Rate this job**, **Cancel a booking**, **Raise a dispute**, **Report**, **Book again**, and **Recurring — same time next week**.

Session 5 built the record; this session builds everything that ends it, judges it, or repeats it. The through-line is the same honesty constraint as the payment step: **RaajjePro never touched the money, never watched the work, and cannot adjudicate either.** What it holds is the record — agreed terms, amendments, chat, both attestations — and every screen here has to be honest about that boundary without feeling like a shrug. The dispute screen is where that tension peaks.

**Import the components; do not re-derive them.** `ServiceCard` · `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` · `SkeletonCard` · `EmptyState` are sibling files with declared props. Status labels live in `StatusPill` — never retype one. `Booking Detail.dc.html` is the immediate predecessor: these screens are all reached from it (or from a notification that deep-links into them), so match its frame, header pattern and tokens, and back-link to it.

**No mockups exist for any of these.** Propose the design. Where you make a structural call — whether rate is a screen or a sheet, how the two cancel severities are separated — say so in a short note so it can be reviewed as a decision rather than discovered later.

Cast stays consistent with sessions 4–5: `Home Deep Cleaning · Mariyam Shifa` (slot, Cleaning) is the default booking; Ibrahim Rasheed is the emergency plumber where an emergency example is needed.

---

## Where these sit in the lifecycle

```
scheduledFor passes … provider silent 7 days ──→ Did this happen?  ── yes ─→ completed → Rate this job
                                                        │ no ─→ flagged (possible no-show)
                                                        │ silence +3 days ─→ completed anyway → Rate this job
completed ──────────────────────────────────────→ Book again · Same time next week?
anything before completion ─────────────────────→ Cancel
anything, before or after completion ───────────→ Raise a dispute
any content, anywhere ──────────────────────────→ Report
```

Cancel, dispute and report are three different severities of "something is off" and **must not look alike**. Cancel is neutral — plans change. Dispute is serious — something went wrong with this booking. Report is about content or conduct, not this booking's outcome. If a customer can't tell which one they're in from a glance, the screens have failed.

---

## Screen 1 — Did this happen?

Seven days after `scheduledFor` with the provider silent, the customer is asked once, plainly:

**`Did Mariyam Shifa complete this job?`** with the booking card for context.

**Three outcomes, and the third is doing nothing:**
- **Yes** → the booking completes normally and flows straight into Rate this job.
- **No** → flagged for review as a possible no-show. This goes to the same moderation path as a dispute — but the customer-facing copy is "we'll look into it", never a promise of refund or adjudication.
- **No response** → after a further **3 days** the booking completes anyway, marked internally as unconfirmed. The screen must convey this without threatening: a provider cannot block a review forever by staying quiet, so silence does not leave the booking open.

This prompt fires for emergency bookings too — do not special-case them out.

Keep it to one decision. No stars here, no text field, no reasons — the moment a "did this happen" screen asks for anything beyond the answer, answer rates die.

## Screen 2 — Rate this job

A completed booking, rated. **Finishable in two taps: stars, then submit.** Everything else on the screen is optional and must read as optional — every extra field that looks required costs a review, and reviews are what make the platform work.

- **Stars, 1–5.** The primary and only required input.
- **Tags, one tap each — fixed per category, positive and negative together:** `On time` · `Fair price` · `Quality materials` · `Good communication` · `Left a mess` · `Arrived late` · `Poor communication` · `Price changed on site`. Use the `Chip` component. These are Cleaning's tags — the set comes from the category, so treat it as data, not copy.
- **Written review, optional**, clearly labelled so.
- One small honesty line the customer should see: **a tag appears on a provider's profile only after three different customers have applied it** — one review brands nobody.

One review per booking. Never generate or display editorial labels about the provider anywhere on this screen — stars, tags and the customer's own words are the entire vocabulary.

## Screen 3 — Cancel a booking

Two very different sides of one event.

**Customer cancels (the screen):** before payment this is straightforward and the copy says so — the time is freed, nobody is penalised, plans change. A reason is asked for but the design should make clear what's optional. No guilt, no dark patterns, no "are you really sure" double-gates beyond one confirm.

**Provider cancelled (the state the customer lands in):** the moment a customer decides a platform is unreliable — it must never dead-end. The customer is **never left with nothing:**
- A **normal booking** drops them back into the booking flow with **service, date, time and preferences already filled** — rebooking is a confirmation, not a re-entry. It does not broadcast to other providers.
- An **emergency** goes back out to the other eligible providers automatically, excluding the one who cancelled, **with no second dispatch fee** — say that explicitly, the fee question is the first thing an emergency customer will have.

The cancelling provider takes the conduct hit; the customer-facing copy states the facts of what happens next and does not editorialise about the provider.

## Screen 4 — Raise a dispute

Something went wrong. **What is being disputed, from a fixed set:** `work_not_done` · `price_changed_on_site` · `unsafe_work` · `payment_dispute` — rendered as human labels, never raw enum strings. A description, and photos (upload into the project, never hotlink).

**The copy this screen lives or dies on:** RaajjePro cannot adjudicate a payment it never handled. What it *can* do is real and should be stated as the promise: it holds the agreed terms, the full amendment history, the chat, and both attestations, and it acts on patterns across bookings. Write that as capability, not apology. Session 5 already learned this lesson twice — there is no adjudication step, no "we'll review and refund", no outcome the platform cannot deliver.

- A dispute **after completion is still accepted** — the booking stays completed; the dispute is its own track.
- **Disputing is not declining.** If any part of this screen could be mistaken for the provider's decline action or the payment "Payment Not Received" action, redraw it.
- What the customer sees afterwards: the dispute is open, an admin will look at it, both sides' records are visible to them. No deadline promise unless the plan states one — it doesn't.

## Screen 5 — Report

Reachable from a listing, a review, a profile, a message, a photo — one screen, five contexts. **The reason set changes with the target:**

- listing: `misleading_description` · `wrong_category` · `contact_details_in_listing` · `prohibited_service` · `not_the_real_provider`
- review: `fake_review` · `abusive_language` · `not_about_this_service`
- person: `harassment` · `impersonation` · `fraud` · `repeated_no_show`
- message: `harassment` · `contact_solicitation` · `spam` · `abusive_content`
- photo: `not_own_work` · `inappropriate_content` · `contains_contact_details`

A description field, and a submitted state. The one fact worth a line on the confirmation: **reported content is hidden, never deleted, its owner is told the reason and can appeal.** Reporting here is transparent moderation, not a trapdoor.

Make the target a scenario prop (`target: listing | review | person | message | photo`) so all five reason sets are demonstrable from one artboard.

## Screen 6 — Book again

One completed booking, repeated in one screen. The service, the provider and the previous details **pre-filled**: saved address, preferred time window, standing instructions ("gate code 4471") carried forward.

**It routes to whichever flow the service uses now** — a slot listing goes to Pick a time, a request listing to Request a time. If the listing changed mode since last time, the current mode wins; the screen should demonstrate both routes. The point of the screen is that a repeat booking is genuinely one confirmation, not a re-entry of everything the platform already knows.

## Screen 7 — Recurring — same time next week

Slot-based services only. `Home Deep Cleaning · Mariyam Shifa · Tuesdays 14:00`.

- **The one-tap entry: `Same time next week?`** on a completed slot booking, and the series view once one exists.
- **The fact the whole screen must convey: each week still needs Mariyam to accept.** This is a convenience, not a standing authorisation — the provider always gets a real chance to decline. If the series view looks like a subscription that runs by itself, it is lying.
- **A skipped week is stated plainly and does not kill the series:** `This week was not confirmed; your series continues next week`.
- **Three missed weeks in a row pause the series** and ask the customer whether to continue — show the paused state.
- **Cancel this occurrence and cancel the series are two different actions** and must be visually distinct — one frees a week, the other ends the relationship.

---

## States, and the combinations to check

Every screen: populated, loading, error. Empty applies where a list can be empty (Report's description is not a list; Book again with a delisted service is worth an error state that says the service is no longer offered rather than a dead button).

Enumerate scenario-prop combinations and confirm each is legal before finishing — the session-3 rule. The ones to watch here:

- Rate this job can only exist on a `completed` booking — never render it against an active status.
- Recurring is slot-only — never show `Same time next week?` on a request-based or emergency booking.
- Book again routes by the listing's *current* mode — a scenario that shows slot routing against a request listing is an illegal combination.
- Did this happen never appears once either party has already marked completion.
- The dispute screen's reason set never mixes with Report's reason sets — they are different systems.

## Guardrails carried from sessions 1–5

- No phone number, WhatsApp or Viber reference anywhere on any of these screens — the emergency reveal on Booking Detail is the only contact surface in the product.
- Never "Payment Verified", never a certainty checkmark on anything payment-shaped; the only payment language is two-sided attestation.
- No editorial labels about providers — "reliable", "prone to cancel" and every euphemism are banned; numbers and the customer's own review are the vocabulary.
- Money is MVR, formatted as in prior sessions.
- Emergency stays quiet: nothing in this session reintroduces banners.
- Photos: upload into the project, reference by filename, never hotlink.

## One line of housekeeping

While you're in the project: in `Propose Amendment.dc.html`, delete the dead line `const wasSentByMe = sc==='sent' || (s.phase==='sent');` — round 2 made it unnecessary and nothing reads it. No other change to that file.
