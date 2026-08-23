The customer side of this flow is right — do not change it.

Specifically, leave alone: the category table and everything driven from it, the 90-second collection state, both countdowns on the offers screen, the three offer cards and their data, the dispatch-fee framing, the rate-limit state, the expired state, and all four scenarios. Those are correct against the specification and re-working them would only introduce drift.

**One screen from the brief was not built: the provider's side.** It was Screen 5 — "Provider: accept with your fee". Nothing in the file covers it, so the supply half of an emergency currently has no design at all.

Add it as a **separate artboard**, `Provider Emergency.dc.html`, not another state inside the customer file. The provider is a different person in a different mode of the app, and folding them into the customer's `screen` state machine would model the flow wrongly.

Reuse the existing visual language exactly — same 412px frame, same tokens, same tier badges, same `CATS` table and `OFFERS` data shape.

## What the screen is

A provider gets an emergency request and answers it with what they charge to attend. **The fee is part of accepting, not a later step** — there is no separate "set your price" screen after accepting.

## Required content

- The job: description, island, distance from the provider, and how long ago it came in
- **A callout fee entry**, `MVR` prefixed
- Convey: this is **what you charge to attend** — parts and labour are settled directly with the customer afterwards
- Convey: **other providers are being asked at the same time**, and the customer picks from up to three. This is a competitive bid, not a race — **answering first does not win it**. This is the single most important thing on the screen: under the old design providers raced to accept and quoted high, and the whole 90-second collection mechanism exists to stop that. A provider who thinks speed wins will behave exactly the way the design is meant to prevent
- One accept action carrying the fee
- A decline action

## Required states

- **Default** — the request, awaiting a fee
- **Offer submitted** — the fee is in, and the customer has `5 minutes` to choose. Show that countdown
- **Not chosen** — the customer went with someone else. Say it cleanly, give no reason, and never leave them on a spinner
- **Chosen** — the job is theirs, with the address and a route into chat
- **Expired** — the request window closed with no decision
- Plus loading and error, as on every screen

## Data to use

- The provider is `Ibrahim Rasheed` · `Rasheed Plumbing Services` · **Gold**
- The job is Plumbing on `Malé`, `1.2 km` away, `4 minutes ago`
- His callout fee is `MVR 350`
- The category's window is `30 minutes` — read it from the same `CATS` table rather than writing 30 into the markup

## Rules that still apply

- **No customer phone number anywhere on this screen**, and no customer surname — the provider sees a first name only until the job is accepted
- **Never a bare "Verified"** — tier badges carry their own copy
- **Never a judgement about the customer** — no ratings, no labels, no history summary
- The `MVR 200` dispatch fee is the **customer's** charge and must not appear on the provider's screen at all. A provider seeing it will assume it comes out of their fee
