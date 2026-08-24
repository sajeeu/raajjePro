Build the two trust surfaces for RaajjePro: the **service preview** and the **provider public profile**.

These are the screens where a customer decides whether to let a stranger into their home. More product rules converge here than anywhere else in the app, and most of them are about **not overstating what RaajjePro knows**. Read the rules at the bottom before you start, not after.

**Import the components; do not re-derive them.** `ServiceCard` · `VerificationBadge` · `Chip` · `StatusPill` · `BottomNav` · `SkeletonCard` · `EmptyState` exist as sibling files with declared props. `Home.dc.html` and `Discovery.dc.html` are the reference for how the pieces sit together — same 412px frame, same 20px padding, same tokens.

**Attach:** `Service-full-post.jpg`. It is the visual reference for the preview screen and it has two content defects, named below. The provider profile has no mockup at all.

---

## Screen 1 — Service preview

One service, everything needed to decide to book it. The most-visited page in the app.

**Hero:** cover image and gallery, with the save control and a **Report** affordance in the overlay.

**Identity of the service:** name `Home Deep Cleaning` · category `Cleaning` · rating `4.8 (24 reviews)`.

**Price, labelled by how it is calculated.** Five kinds exist and they read differently — a flat rate `MVR 450/session`, an hourly rate, a daily rate, a **range** `From MVR 350`, or **price on request**. A range is advertising, not a bookable amount; design it so a customer does not read it as the price they will pay.

**Booking mode, unmissable.** `Book instantly` or `Request a time` — the customer must know which kind of wait they are in before they commit. Where the service is emergency-capable, that path is offered **alongside** the normal one, never instead of it, and states the callout-fee expectation up front.

**Provider identity:** name, photo, **verification tier with its exact words**, typical reply time, jobs completed. Tapping it opens their profile.

**Description, service areas (the islands covered), and what is included.**

**Extra information — every line attributed, never asserted:**
- `Provider states: 90-day workmanship warranty`
- `Provider states: public liability insurance held` — or, where an admin has sighted the certificate on a Gold provider, `Insurance certificate on file`
- Neither ever carries a check mark, a shield, or the word *verified*

**Callback guarantee, where offered** — `Free return visit within 7 days if the same problem comes back`.

**This is the single most important visual decision on the screen.** The callback guarantee is **RaajjePro's** promise and RaajjePro enforces it. The warranty above is **the provider's** claim and nobody checks it. They must not share a treatment — not the same card, not the same colour, not the same iconography. A customer who reads the second as the first has been misled about who stands behind what.

**FAQs.**

**Reviews:** star breakdown, individual reviews, and **tag counts** — `On time (31) · Fair price (28) · Arrived late (3)`. Tags are fixed per category, positive and negative both, and a tag only appears once three different customers have applied it.

**A Message action**, opening an enquiry thread before any booking exists. This is how a customer asks "is it a split unit or ducted?" — it is not a lesser version of contacting them, it is the only channel there is.

**Sticky footer** carrying the price and the primary booking action.

### Two corrections to the attached mockup

1. It shows a single **`Verified Provider`** badge. There are **three tiers**, each visually distinct and each carrying its own copy. Use `VerificationBadge` at `size="full"` here.
2. Its description is about **AC installation** under a **Cleaning** listing. Match the description to the service.

### States

Loading (skeleton in the real shape) · populated · error with retry · **unavailable** — a listing whose provider is suspended or which has been taken down shows a neutral unavailable state, never a booking form.

---

## Screen 2 — Provider public profile

The person or business behind the services. No mockup exists; this is yours to shape.

**Header:** name `Ibrahim Rasheed` · business `Rasheed Plumbing Services` · photo · joined `Mar 2026` · **verification tier with its exact copy**, full size.

**`Maldivian-owned business`, where it applies.** An attribute of the **business**, evidenced by a registration document and shown only at Gold. It is never a nationality and never about a person — below Gold the attribute is absent rather than false.

**Overall rating and review count.**

**Conduct metrics — numbers and nothing else:**

`94% completed` · `3% cancelled` · `2% no-show` · `91% on time` · `97% price honoured` · `usually replies in 12 minutes` · `47 jobs completed`

- They cover a **rolling 90 days**. Say so.
- **Below ten completed bookings none of them appear.** Instead: `New provider · 4 jobs completed`. One cancellation out of two is 50% and means nothing, and publishing it would be a smear computed from noise.
- **No label, no grade, no summary, no colour-coding into good and bad.** The numbers are the entire output and the customer draws their own conclusion. Anything that reads as a verdict is wrong — including a green tick beside a high number.

**Review tag counts**, aggregated across all their services.

**Their published services**, as `ServiceCard` in the full-width variant.

**A save-provider control**, and a **Report** affordance.

### States

Loading · populated · **new provider** (under ten bookings, metrics suppressed) · **not found** — a provider with nothing published has no public page at all, and a customer arriving by an old link needs somewhere sensible to land · error.

---

## Fixed data

- `Ibrahim Rasheed` — `Rasheed Plumbing Services` — Plumbing — **Gold** — `4.6 (31)` — Maldivian-owned — 47 jobs — replies in 12 min
- `Mariyam Shifa` — Cleaning — **Silver** — `4.8 (24)` — `MVR 450/session` — Book instantly — callback guarantee offered
- `Hassan Faiz` — Electrical — **no tier** — `4.2 (7)` — 7 jobs, so metrics are suppressed. Build this state; it is the common case at launch

Photos: reference uploaded images by filename (`uploads/cleaning.jpeg`, `uploads/plumbing.jpeg`, `uploads/electrical.jpeg`). **Never hotlink** — an external image is blocked wherever the page is published, and it rots.

---

## Rules that override anything else

- **No phone number, no bank details, no contact information of any kind** appears on either screen, in any state, for any viewer. The Message action is the whole answer to "how do I reach them".
- **Never a bare "Verified"** — three tiers, each with its own copy, and absent where there is no tier.
- **Never a judgement about a provider.** No "Top rated", no "Reliable", no grade, no traffic-light colouring of a metric.
- **Never a check mark, shield or "verified" on a warranty or an insurance claim.** Those words belong to `verificationTier` alone, because a human checked it.
- **Never let the callback guarantee and the provider warranty share a treatment.** One is enforced; one is a stranger's word.
- **Money is `MVR 450`** — code first, no symbol, decimals only where a value has them.
- **Every screen needs its four states**, and the new-provider and not-found states here carry real weight.
