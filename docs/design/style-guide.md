# RaajjePro — design style guide

Paste this into a Claude Design project's `CLAUDE.md`. It is the shared half of the design brief: the visual language and the constraints that hold across every screen. The per-screen content lives in `designer-brief.md` — this file says *how*, that file says *what*.

Read this once. It is what stops separately-designed areas from looking and behaving like different products.

## What you are designing

RaajjePro is a mobile marketplace for local services in the Maldives — cleaning, plumbing, electrical, AC repair, beauty, photography, gardening, computer repair, moving, fitness, events and boat charter. Customers find a provider, book them, and the provider does the work at the customer's home or business. Flutter, portrait phone.

**Three facts shape almost every screen, and they are unusual.**

| Fact | What it means for design |
|---|---|
| **The platform never touches the money** | Customers pay providers directly by bank transfer. RaajjePro shows the provider's account details and both sides confirm separately. No card fields, no checkout, no "payment successful" anywhere. |
| **Phone numbers are never exchanged** | Customers and providers coordinate entirely through in-app chat — arrival times, gate codes, "running late". There is exactly one narrow exception, in emergencies only. |
| **Connectivity is unreliable** | Island internet drops constantly. Anything a user types can be interrupted mid-action, and must survive it. |

**Two audiences, one app.** A customer looking for a plumber, and a provider running a small business from their phone. Many people are both, and switch between modes. Provider screens are work tools used daily; customer screens are used occasionally and must explain themselves.

## The rules that never bend

These come from product and legal constraints rather than design opinion. Everything else is open to your judgement; these are not.

**Never claim a payment was verified.** RaajjePro cannot see the bank transfer. Never "Payment verified", "Paid ✓", a lock icon, a shield, or a certainty check mark anywhere in a payment flow. Use **"Provider confirmed receipt"** — which is what actually happened: a human said so. The same honesty applies to anything the platform has not itself checked. A provider-declared warranty renders as **"Provider states: 90-day warranty"**, never as a badge.

**Never generate a judgement about a provider.** Providers are scored on completion, cancellation, no-show, punctuality and price adherence. Show the numbers — `94% on time · 3% cancelled · 47 jobs`. Never a label like "Prone to cancel" or "Unreliable". These were considered and rejected: they are automated public accusations in a market where everyone knows everyone. Below **10 completed bookings**, show "New provider" and the job count instead of percentages.

**Never put friction in the message composer.** No warning banner about sharing details, no redaction, no interference of any kind. Customers legitimately send appliance serial numbers, model numbers, addresses and photos of their homes. A Maldivian mobile number and an AC serial are both seven digits — anything that flags one flags the other and ruins the channel. Text field, attachment, send.

**Never show an unavailable time.** Slot pickers show only times that are genuinely bookable right now — not greyed-out unavailable slots, not times that have passed, not times too soon to reach. Unavailable options are not rendered at all.

**Never mention price during provider signup.** The "Become a Provider" intro must not mention subscription, pricing, plans or premium. Someone deciding whether to join must not meet a price first. Money is introduced much later.

**Never render a bare "Verified".** Verification is three tiers and each carries its own words — see below.

**Never claim chat is encrypted.** It is readable by an admin during a dispute. The honest claim is "Private messaging — your contact details are never shared."

## Tokens

Measured from the delivered designs, not proposed. Keep these unless you have a reason — the seventeen existing screens and the working prototype already use them.

### Colour

| Role | Value |
|---|---|
| Primary | `#2563EB` · pressed `#1D4ED8` |
| CTA gradient | `#5B8DF6 → #2563EB 60% → #1D4ED8`, 135° |
| Ink | `#0F1B2D` |
| Secondary text | `#5B6B84` · tertiary `#41526B` |
| Placeholder | `#9AA9C0` |
| Page background | `#F2F6FB` |
| Surface | `#FFFFFF` |
| Border | `#E3EAF3` · subtle divider `#EEF3FA` |
| Accent tint | `#E8F0FE` · border `#CDDDFB` |
| Success | `#16A34A` · tint `#E5F6EC` |
| Error | `#DC2626` |
| Warning | `#D97706` · tint `#FEF3DC` |
| Disabled | fill `#C6D4EA` · text `#8296B3` |

**Verification badge palettes** — one per tier, fill · text · border:

| Tier | Fill | Text | Border |
|---|---|---|---|
| Bronze | `#FBEDE3` | `#9A5B2D` | `#E8C4A0` |
| Silver | `#F1F5F9` | `#475569` | `#CBD5E1` |
| Gold | `#FEF3C7` | `#B45309` | `#FCD34D` |
| None | — | — | — (the badge is absent; never a grey "unverified" chip) |

**Category accents** — each of the twelve carries its own tint for icon chips: Cleaning indigo, Plumbing emerald, Electrical amber, AC Repair blue, Beauty pink, Photography orange, Gardening green, Computer blue, Moving orange, Fitness violet, Events yellow, Boat Charter cyan. Tints sit around 8% saturation on white; the icon takes the full colour.

### Type — Inter

| Role | Size / weight | Notes |
|---|---|---|
| Screen title | 24–26 / 800 | `letter-spacing: -.02em` |
| Section heading | 16–18 / 750 | |
| Card title | 15 / 700 | |
| Body | 14–14.5 / 400–600 | line height 1.5–1.55 |
| Secondary / helper | 12.5–13 / 400 | colour `#5B6B84` |
| Uppercase label | 11–13 / 800 | `letter-spacing: +.06em` |
| Button | 15–16 / 700 | |

**Nothing lighter than 600 appears anywhere in this product.** That is deliberate and it is a large part of why the existing screens feel solid.

### Geometry & motion

- **Radii:** 10 · 12 · 14 (inputs) · 16 (buttons, small cards) · 20 · 24 (feature cards) · 28 (bottom sheets) · fully round (pills, avatars)
- **Heights:** 52 inputs · 54 primary CTA · 44 icon buttons and minimum touch target · 38 filter chips · 26 checkboxes
- **Borders:** 1px dividers · 1.5px inputs and selectable cards · 2px selected states
- **Screen padding:** 20px horizontal, consistently
- **Motion:** screen transition 350ms `cubic-bezier(.2,.8,.3,1)` · element fade-up 200ms ease · bottom sheet 400ms `cubic-bezier(.2,.9,.3,1)` · toast 250ms ease · spinner 800ms linear

## Components

Design each once and reuse it everywhere. Where a page brief says "a card", it means this card.

| Component | Variants required |
|---|---|
| **Button** | Primary (gradient) · secondary (outline) · text · destructive. Each with default, pressed, disabled and loading. Loading keeps the label and adds a spinner. |
| **Text input** | Default · focused · filled · error · disabled · read-only. Error shows a message below in `#DC2626`, never a tooltip. |
| **Select** | Same states. Native picker on mobile. |
| **Textarea** | With character counter where capped. |
| **Chip** | Filter (selectable) · input (removable, with an ×) · static label. Selected chips invert to primary. |
| **Card** | Plain container · listing card (image, title, category, rating, price, mode affordance) · row card with leading icon. |
| **Toggle** | On · off · **disabled-with-reason**. The disabled state must be able to show why. |
| **Verification badge** | Four states: none (absent) · Bronze · Silver · Gold. Compact for cards, full for profiles. |
| **Status pill** | Booking statuses, listing states, payment states. Semantic colour, **never colour alone** — always with a label. |
| **Bottom sheet** | Confirmations, action menus, success moments. 28px top radius, drag affordance. |
| **Toast** | Transient confirmation. Never for errors that need action. |
| **Avatar** | With image · initials fallback · with badge overlay. |
| **Bottom navigation** | Five tabs: Home · Explore · Bookings · Messages · Profile. Active state as a tinted pill. |

### The verification badge is load-bearing

Verification is **three tiers, not a yes/no**, and the tier decides what a provider is allowed to do — Gold is required for emergency electrical and plumbing work. A customer at 2am needs to read that at a glance. Each tier carries its own copy, verbatim.

| Tier | Public copy | What it means |
|---|---|---|
| **Bronze** | `ID checked by RaajjePro` | Identity document checked, phone confirmed by a human |
| **Silver** | `ID checked, work verified` | Bronze plus a track record of completed jobs |
| **Gold** | `ID checked, registered trade` | Silver plus business registration or trade certificate — and emergency eligibility |
| **None** | *(badge absent)* | Never a grey "unverified" badge. Absence is the signal, and an unverified provider is still fully listed and bookable |

### Booking mode is on every card

Every listing card, search result and Home card states how it is booked: **`Book instantly`** (the customer picks a published time) or **`Request a time`** (the provider comes back with a time and a price), plus **`Emergency available`** where it applies. A customer must never be uncertain which kind of wait they are in.

## Every screen needs four states

A hard requirement, not a nice-to-have. A screen delivered with only its populated state is not finished.

| State | What it must do |
|---|---|
| **Loading** | Skeleton matching the real layout, not a centred spinner. The user should already see the shape of what is coming. |
| **Empty** | Explain why it is empty and offer the action that fills it. "No bookings yet" plus a route to Explore, never just an icon. |
| **Error** | Say what went wrong and what to do. Offer retry. Never a raw code, never "Something went wrong" alone. |
| **Populated** | Including the awkward cases — very long names, a provider with 400 reviews and one with none, twelve islands selected. |

## Offline is normal, not an edge case

Connectivity drops constantly on the islands. Three flows must survive it because losing them silently costs a real job: **the service creation wizard**, **the provider's booking accept prompt**, and **chat**.

- Actions taken offline show as **pending**, survive the app closing, and send on reconnect.
- Per-item states: **pending · sent · failed**, with retry on failure.
- Never a blocking "no internet" screen over work someone has already typed.

Chat is the only way a customer and provider coordinate. A silently lost message means a tradesperson at the wrong address, or a customer waiting in for someone who is not coming.

## Voice

- **Plain, specific, calm.** "Waiting for Ibrahim to accept" beats "Pending confirmation".
- **Name what happens next.** Most screens in this product are somebody waiting for someone else; say what they are waiting for and roughly how long.
- **Say what is true, not what is reassuring.** The product's credibility rests on not overstating what it knows.
- **Errors explain and offer a way forward.** Never blame the user, never say "invalid".
- **Money is always MVR**, formatted `MVR 500`, with the unit where one applies — `MVR 500/session`, `MVR 150/hr`. Decimals only where a value has them.
- **English throughout.** Dhivehi is not in this release, but see below.

## Two platform constraints

**Design right-to-left ready.** Dhivehi is written in Thaana, which runs right to left. It is not in this release, but layouts must not *assume* left-to-right — no hard-coded left padding where it should be leading, no arrow that only makes sense pointing one way, no row order that breaks when mirrored. Retrofitting this later means rebuilding the presentation layer.

**Accessibility baseline, not optional.** Minimum **48dp touch targets**. **WCAG AA contrast** on all text and status colours — amber on white is the one that usually fails. Every icon-only control needs a label. Layouts must survive **200% text scale** without clipping, which means no fixed-height text containers. Every motion effect needs a reduced-motion path.

**This is Flutter, not a website.** The existing prototype is HTML because that is what the design tool produces — match its values, not its idioms. Use native scroll physics, native sheets, and platform-appropriate page transitions.

## Where everything lives

| | |
|---|---|
| `designer-brief.md` | All 71 page briefs — what each page is and what data it carries |
| `mockups/` | Seventeen delivered screens as images |
| `mockups/round-16-redraws.html` | Corrections to nine of them. **Where these disagree with an image, these win** |
| `mockups/design-composer/Become a Provider.dc.html` | A working prototype, not a picture. The highest-fidelity reference there is |

---

**If you take one thing from this document:** the rules that never bend are not style guidance you can improve on. Each one exists because a specific alternative was tried, argued about, and rejected for a reason. Everything else — layout, hierarchy, illustration, motion, how a screen feels — is yours.
