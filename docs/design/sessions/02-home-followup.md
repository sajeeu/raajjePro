Home and the component sheet are structurally right — keep both. Twelve categories with Boat Charter, the five sections, launch mode collapsing to two sections plus the grid, per-section error with retry, the island sheet, all five scenarios, and the component sheet's full state coverage: all correct, do not rework them.

Four corrections, all copy. Two of them are claims the product cannot keep.

## 1 — "Upfront pricing" is false for most of the catalogue

The trust card reads **"Prices shown before you book. You pay the provider directly."**

The second sentence is true. The first is not, for **nine of the twelve categories**. Only Cleaning, Beauty and Fitness publish a bookable price. Plumbing, Electrical, AC Repair, Photography, Gardening, Computer, Moving, Events and Boat Charter are request-based: the customer sees an estimate like `From MVR 350`, and the real price arrives in a quote after the provider has understood the job.

This is the same failure as the "encrypted messaging" claim already corrected on this screen — a reassurance the system cannot deliver, printed on the highest-traffic surface in the app.

Replace with something true of every listing:

> **No hidden fees** — you agree the price before any work starts, and pay the provider directly.

That holds for all three booking modes: a published price, an accepted quote, or an agreed callout fee. Nothing is ever added afterwards without the customer accepting an amendment.

## 2 — "Verified providers" reads as though every provider is verified

The card is titled **"Verified providers"** with the subtitle "ID checked by RaajjePro, in three tiers".

Verification is **optional and earned**. A provider with no tier at all is fully listed, fully bookable, and will be the common case at launch. A customer who reads Home as promising that everyone here is verified, and then books someone with no badge, has been misled by this card.

Retitle so it describes what the tiers *are* rather than claiming coverage:

> **Three levels of verification** — Bronze, Silver and Gold. Each provider's badge says exactly what was checked.

Keep the shield icon and the placement.

## 3 — The phone error implies only Maldivian numbers are accepted

In `Components.dc.html`, the input error state reads **"That number looks short — Maldivian mobiles have 7 digits."**

Foreign numbers are valid. Resort guests and expatriate residents are real customers, numbers are stored with a country code defaulting to `+960`, and anything from **6 to 15 digits** is accepted. The seven-digit rule is a Maldives-only hint, not a validation rule.

Replace with something that does not exclude:

> **Enter a number between 6 and 15 digits, without the country code.**

## 4 — Drop the "Available" badge from the component sheet's card

The horizontal service card in `Components.dc.html` carries a green **"Available"** pill. Home's own cards do not have it, so the sheet already disagrees with the screen it was extracted from.

Remove it rather than adding it to Home. There is no real-time availability signal in this product — a provider has one account-level "accepting new customers" switch that hides all their services at once, and a green dot reading as "free right now" promises knowledge the system does not have.

## Everything else stays

Do not touch the layout, the sections, the launch-mode logic, the states, the card structure, the badge treatments or the navigation. These are four copy edits and one deletion.
