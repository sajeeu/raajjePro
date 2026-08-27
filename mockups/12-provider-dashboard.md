Build the provider dashboard: **My Services** and **Availability & time slots**. Two artboards.

**Attach:** `Profile_serviceProvider.jpg` — despite the filename, this is the services dashboard, not a profile. It audited clean overall, so My Services is mostly fidelity work — but three additions and one correction below. Availability has **no mockup at all**: nothing in the delivered designs resembles it, and wizard step 5 is a toy version that will mislead if treated as the pattern. Propose it, inheriting the established vocabulary.

**Import the components**: `VerificationBadge` · `Chip` · `StatusPill` (booking statuses only — see guardrails) · `BottomNav` (`active="Profile"`, matching the mockup) · `SkeletonCard` · `EmptyState`. Cast: Ibrahim Rasheed, the provider from the wizard session, tier **Silver** by default with a tier scenario prop. His listings are the mockup's three — Home Deep Cleaning and AC Service & Repair published, and the electrical draft, which you should rename **Wiring & Fault Repair** so it is recognisably the same draft the wizard session left open.

Suggested artboards:

- `My Services` — the mockup screen with states
- `Availability` — the slot management screen, no mockup, the priority design work of this session

---

## My Services

Match the mockup: header with bell and avatar, title row with the create action, stats band, All/Published/Draft filter chips, list/grid toggle, service cards (cover, name, category chip, status, rating, price, views, bookings, updated-age), the dashed add-another card. Stats are **illustrative** — the mockup's Published/Bookings/Views tiles are fine as drawn.

**The one correction: a draft card must not carry a Live toggle.** The mockup gives the Electrical draft the same Live/Off switch as the published cards. A draft cannot be switched live — publishing runs through the wizard's review step and its six required fields. The draft card's action is **`Finish & publish`**, routing into `Create Service.dc.html`. The Live toggle appears on published cards only, where it pauses and resumes visibility.

**Three additions the mockup omits:**

1. **The verification badge**, near the provider's name/avatar — the `VerificationBadge` import, reflecting **tier alone**. The fact worth a quiet line somewhere sensible: the badge does not depend on the subscription — a provider whose subscription lapses keeps it, because it is a safety signal, not a payment status.
2. **A route to Availability & time slots** — visible, not buried in a menu. It's the other half of this session.
3. **The per-card menu** (the ⋮ the mockup already draws): edit · duplicate · hide · delete · view as customer. Edit routes to `Create Service.dc.html`; view-as-customer routes to `Service Preview.dc.html`. Delete gets a confirm sheet — word it honestly (`removed from your services`), never as permanent erasure, and never implying the numbers and history vanish.

**States:**

- **Drafts-only** — a provider with nothing published reaches this screen normally, everything at zero, never gated. Worth one honest line on this state: with nothing published, the provider doesn't appear in search — publishing is what makes them visible.
- **Hidden-over-limit** — a free-tier provider holds one published service; a second one is hidden for that reason. The card **says so, with what would restore it** (upgrade, or swap which service is live) — never styled as an error, and the data is never lost. This is a scenario prop (`plan: paid | free-over-limit`); the default two-published cast implies the paid tier.
- Loading, error, and the empty filter results.

Links: bell → `Notifications.dc.html`, create/edit → `Create Service.dc.html`, back/avatar → `Profile.dc.html`.

## Availability & time slots — the priority

Where a provider says when they work. **Scoped to one slot-mode listing** — the header names the listing (Home Deep Cleaning), with a switcher if more than one listing takes slots. Request-based listings have no slots and never appear here.

Three layers, and the middle one is the point of the screen:

1. **Recurring weekly rules** — which days, which hours, how long each appointment is: `Mon–Thu · 09:00–17:00 · 2 hours each` *(illustrative)*. Add, edit, remove.
2. **A preview of the times these rules actually produce, before they are saved.** Rules are abstract and times are concrete — a provider must see what they have just committed to. Editing a rule updates the preview; saving is a distinct act.
3. **Exceptions and blocked ranges** — a named range that removes times: `Ramadan hours · 10:00–15:00 · 18 Feb – 19 Mar`, travel, public holidays *(illustrative)*.

The generated times, by date, each **`open` · `reserved` · `blocked`** — exactly three states, no fourth. Any single open time can be individually blocked or unblocked. A reserved time cannot be touched at all — and it may belong to a booking on a **different listing**, because double-booking protection covers the provider as a whole; name the booking it belongs to so the provider recognises it.

**Facts the screen must convey:**

- Times are generated **60 days ahead, rolling**
- **Changing a rule never touches a time someone has already booked.** Only future unbooked times change — say this at the moment of saving a rule change, not buried in help text
- A customer never sees a time that is blocked, taken, or already past

**States:** empty (no rules yet, and what publishing some would do — this is the drafts-only provider's first visit), populated, loading, error, plus the unsaved-preview state from layer 2.

## Guardrails

- **`StatusPill` carries the twelve booking statuses and nothing else.** Listing states (Published / Draft / Hidden) are a different vocabulary — style them as the mockup does, and do not press StatusPill into that role or duplicate its labels.
- The tier copy lives in `VerificationBadge` — import it, never restate it.
- **No emergency content on either screen.** Emergency work takes no calendar reservation — it interrupts the published calendar rather than blocking it — so there are no "emergency slots" and no emergency toggle here; that lives in wizard step 5.
- No editorial labels on anything; conduct metrics are session 13's problem, not this one's.
- Money as MVR, all figures illustrative. Categories are the Round 25 twelve. Photos uploaded, never hotlinked.
- No subscription/billing UI beyond the over-limit card state — billing is session 13.
