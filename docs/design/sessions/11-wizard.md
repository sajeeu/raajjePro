Build the **Create/Edit Service Wizard** — all seven steps in **one artboard**. The seven steps share one shell (header, progress, footer navigation), and splitting them across artboards guarantees drift. Use a `step` scenario prop (1–7) plus whatever state props each step needs.

**Attach:** `Create_service_widget1.jpg` through `Create_service_widget7.jpg`, **plus `round-16-redraws.html`**. ⚠ **Four of these mockups are wrong against the plan.** They are attached for layout vocabulary only — where this brief contradicts an image, the brief wins, every time. The specific defects are listed per step below; do not reproduce any of them.

**Import the components**: `Chip` (tags, islands) · `EmptyState` · `SkeletonCard` as needed. No `BottomNav` — the wizard is a full-screen flow with its own footer (Back · step context · Continue). Cast as established: Ibrahim Rasheed is the provider, editing an **Electrical** service (`Wiring & Fault Repair`, illustrative), verification tier **Silver**.

---

## The frame that shapes everything

**Progress leads with required fields, not steps.** The headline progress line is `4 required fields left to publish` (or whatever the count is), with `Step 1 of 7` as the secondary label. Six fields are required in total — **name, category, short description, at least one island, a price, and a cover image** — and leading with "step 1 of 7" overstates the commitment.

**A draft saves with nothing filled in.** Zero required fields to save. Only publishing enforces anything. Say this on step 1 (`Saved as draft — nothing here is required until you publish`, or similar), and render a persistent quiet autosave indicator in the shell (`Saved just now` / `Saving…` / `Saved offline — will sync`).

**Step navigation is never blocked.** A provider can tap forward to step 7 with everything empty. No "complete this step to continue." The review step is where gaps surface — as a field-level list, not a wall.

**Every step saves as it goes, and saves offline.** A dropped connection queues the change and sends it on reconnect. Navigation waits until the current step is safely stored — this is the highest-value flow in the app and it must never lose work. Show the offline-queued state somewhere reachable (a scenario prop is fine).

## Step 1 · Details

Mockup: `Create_service_widget1.jpg` — **two corrections.**

- Service name, category, short description — the three required fields here
- ⚠ The mockup's category list shows **Tuition. It does not exist.** The twelve categories: Cleaning · Plumbing · Electrical · AC Repair · Beauty · Fitness · Photography · **Pest Control** · **Appliance Repair** · Moving · Events · **Boat Charter**. (Never Gardening, never Computer — both replaced.)
- ⚠ The mockup has free-text tag entry only. Render **tags as tappable chips scoped to the chosen category**, with free text underneath for anything not covered — typing a tag from memory asks a provider to guess what customers search for. Helper line: `Relevant tags help customers find you in search`
- Before a category is chosen, the tag chips section states it's waiting on the category

## Step 2 · Location

Mockup: `Create_service_widget2.jpg` — clean.

- Searchable island multi-select, **pre-filled from the provider's default coverage areas** and editable here per service — a mover may cover five islands but photograph on one
- At least one island required to publish; selected islands shown as removable chips
- Placeholder islands (`Malé` · `Hulhumalé` · `Villimalé` · `Maafushi` · `Thulusdhoo` · `Hithadhoo`) **with a visible note that the real island list is pending** — do not present these as the seed

## Step 3 · Pricing

Mockup: `Create_service_widget3.jpg` — **three corrections.**

- **How the price works** — one of `Fixed` (one rate per job) · `Hourly` · `Daily` · `Range` (from–to) · `Price on request`
- ⚠ The mockup renders the price field **twice. Once.**
- **What the customer sees it as** — separate from how it's calculated: `per job` · `per hour` · `per day` · `per session` · `per visit`. `Fixed` + `per session` reads as `MVR 450/session`
- Fact stated on this step: choosing **Range** or **Price on request** means the service **cannot** be booked as a fixed time slot — it becomes request-based. A customer cannot book a fixed time at an unknown price. (Step 5 must honour this — see below.)
- ⚠ The mockup includes **Service packages. Remove them entirely** — tiered options are not in this version. Do not leave a "coming soon" stub.
- Money is always MVR

## Step 4 · Media

Mockup: `Create_service_widget4.jpg` — clean.

- **Cover image — required to publish.** It's the first thing a customer sees on every card and in every result; say so
- Gallery, optional, reorderable
- Upload states: in flight, and failed with a retry
- Photos uploaded, never hotlinked

## Step 5 · Availability

Mockup: `Create_service_widget5.jpg` — ⚠ **do not implement it as drawn. Two corrections.**

- **How this service is booked:** fixed time slots, or request a time. If step 3 chose Range or Price on request, the slot option is **disabled with the reason shown** (`Range pricing can't be booked as a fixed slot`) — never silently hidden
- Working days and hours (this is deliberately simple — the full availability engine with recurring rules and exceptions is a separate provider screen in session 11, not this step)
- **Emergency service toggle**, and this is the correction that matters:
  - ⚠ It is **disabled with the reason shown** wherever the category or the provider's tier doesn't qualify. For the cast scenario: `Emergency work on Electrical needs Gold verification. You are Silver.` For a non-emergency category: emergency isn't offered on that category, stated plainly. (Emergency exists only on Plumbing, Electrical, AC Repair and Moving — Electrical/Plumbing need Gold, AC Repair/Moving need Silver.)
  - Where it IS available (give this a scenario — e.g. the same provider at Gold): `Customers expect a response within 30 minutes`. The window is read from the category's configuration, not hardcoded into copy — every emergency category currently reads 30
  - Convey to the provider that **answering fast and arriving fast are different commitments**: they state their own arrival estimate when they answer an emergency, so a mover needing two hours to load a van says so rather than answering late
- ⚠ The mockup carries an **`Accepting New Customers` toggle. Remove it entirely** — that setting is account-level and belongs in the provider's own settings, not on a listing

## Step 6 · Extra info

Mockup: `Create_service_widget6.jpg` — **one correction.**

- Everything here is optional and none of it blocks publishing — say so at the top
- What's included, what's not
- ⚠ The mockup renders the **FAQs accordion twice. Once.**
- **Warranty** (offered? terms as free text) and **Insurance** (public liability held? details) — with the fact stated to the provider on this screen: **RaajjePro does not check either, and customers are told so.** They render to customers as `Provider states: …`
- **Callback guarantee** opt-in — a free return visit within `7 days` if the same problem comes back. **This one RaajjePro does enforce**, and it must be **visually separate from the warranty block** — grouping an enforced commitment with two unverified claims launders the claims

## Step 7 · Review & publish

Mockup: `Create_service_widget7.jpg` — clean.

- Everything entered, reviewable, **each section editable in place** (one tap back to its step)
- **The six required fields, and which are still missing** — a field-level list, each row naming the field and deep-linking to its step. Never a generic "form incomplete"
- Save as draft, and Publish
- Missing-fields scenario: publish attempt names exactly which fields, each reachable in one tap
- **Over-limit scenario**: a free-tier provider already holding one published service sees what upgrading would allow — a calm upgrade prompt, **never an error, and the draft is never lost**. Publishing isn't refused with a dead end; the draft stays a draft
- Success scenario: published, with where it now appears

## States and combinations

The shell needs: normal, saving, saved-offline (queued, will sync on reconnect). Per-step states as listed. Then check **reachable prop combinations** — every combination of scenario props must describe a listing that can exist:

- `Range`/`Price on request` pricing must never co-occur with slot booking enabled on step 5
- The emergency toggle enabled state must only be reachable with an emergency-capable category AND a qualifying tier for that category
- The over-limit prompt only makes sense for a free-tier provider with a published service already

## Guardrails carried forward

- Categories are the Round 25 twelve — no Tuition, no Gardening, no Computer, anywhere, in any list or demo data
- No "Payment Verified" language; no editorial labels; no phone numbers rendered; no encryption claims
- No invented endpoints or features: no service packages, no scheduling engine beyond working days/hours, no "Accepting New Customers"
- The emergency response window is 30 minutes wherever it appears — never 120, and never conflated with arrival time
- Money as MVR. Photos uploaded, never hotlinked.
