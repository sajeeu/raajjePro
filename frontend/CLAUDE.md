# Frontend — RaajjePro (Flutter)

Applies to everything under `frontend/`. The root `CLAUDE.md` and `01_Development_Plan_v5.md` still govern; this file adds the conventions specific to this app.

- Feature-based structure: `lib/features/<feature>/` with presentation, controller (Riverpod), and data layers. Shared widgets live in `lib/shared/`, cross-cutting concerns in `lib/core/`.
- Riverpod for all state. No `setState` for anything that outlives a single widget's local interaction.
- EVERY screen implements loading, empty, error and populated states. This is part of the screen's own definition of done, not a later QA pass. An empty state names what the user should do next; it never merely reports that nothing is there.
- Network failures degrade gracefully. Where a flow is marked offline-resilient — the service wizard, the provider accept prompt, chat sends — queue locally on failure, show a pending indicator, and replay on reconnect. Never silently discard user input.
- Optimistic updates roll back visibly on failure.
- Errors surface INLINE where the user can act on them, not as generic toasts. A field error belongs under its field.
- Accessibility is built in, not retrofitted: 48x48 minimum touch targets, visible focus states, semantic labels, and reduced-motion handling that degrades shimmer and transitions when the OS flag is set.
- Never hardcode a color, font, spacing value or radius. Use design tokens; add to them explicitly if genuinely missing.

---

# Design System — source of truth

- Tokens are derived from the mockups and live in a Theme extension. Scattered constants are a defect.
- Component states are explicit and complete: buttons carry pressed, disabled and loading; inputs carry normal, focused, error and disabled.
- A button that triggers a network call shows ITS OWN loading state. Do not cover the screen with a page-level spinner for a local action.
- Skeleton loaders for content that is fetching; not spinners, and not a blank screen.
- Verification tier badges are three distinct treatments (Bronze/Silver/Gold), each carrying the exact public copy from the plan's §1e: "ID checked by RaajjePro" / "ID checked, work verified" / "ID checked, registered trade". NEVER render a bare "Verified" — a customer may read that as "has a good track record" rather than "passed an ID and trade check".
- Booking-mode affordances appear on every card and listing surface: 🔧 **"Pick a time"** (slot — Round 44; it was "Book instantly", which named an immediacy the state machine does not produce, since a slot booking is still a `requested` booking the provider has to accept) and **"Request a time"** (request). A customer must never be uncertain which kind of wait they are in.
- 🔧 **There is no "Emergency available" marker on a card, and no emergency search filter — Round 23.** Dispatch never targets a provider, so both advertised an action that does not exist. The card's second signal is mode-appropriate instead: next open time for `slot`, median response time for `request`. The callback guarantee is the card badge. Emergency is reached from its own entry on Home and Explore.
- Where a mockup predates the current plan, THE PLAN WINS and you flag the mismatch — do not silently implement the mockup.

---

# Testing

- Every business rule gets a test asserting the rule, not the implementation. A test that would pass against a wrong implementation is not a test.
- Concurrency is tested explicitly wherever the plan names it: simultaneous slot booking, cross-listing overlap on one provider, 1,000 concurrent attempts asserting zero double-books, simultaneous admin confirmation, repeated idempotent POSTs.
- State machines are tested at their boundaries — the transition that should be rejected matters more than the one that should succeed.
- Scheduled jobs are tested by advancing time, not by waiting.
- Authorization tests cover reads as well as writes, and cover the wrong-user case, not just the unauthenticated one.
- Any endpoint touching a phone number is tested for its ABSENCE in the response, not only for the presence of what it should return.
- Registration is tested against both a duplicate email and a duplicate phone, asserting each is blocked with a message naming the specific field.

---

# Design tokens — extracted from the delivered designs

🔧 **These are measured values, not proposals.** They come from `mockups/design-composer/Become a Provider.dc.html`, which is a working Design Composer prototype rather than a flat image — so every colour, radius and duration below is exact rather than eyedropped. Phase 1 builds the Theme extension from these.

**`Become a Provider.dc.html` is the highest-fidelity reference in the repo.** It carries interaction detail no image can: which field shows which error text, when a CTA disables, how long a transition runs. When implementing a screen it covers, read it rather than the JPEGs.

## Colour

| Role | Value |
|---|---|
| Primary | `#2563EB` · pressed `#1D4ED8` · gradient `#5B8DF6 → #2563EB 60% → #1D4ED8` |
| Ink | `#0F1B2D` |
| Secondary text | `#5B6B84` · tertiary `#41526B` |
| Placeholder | `#9AA9C0` |
| Page background | `#F2F6FB` · outer frame `#DEE7F3` |
| Surface | `#FFFFFF` |
| Border | `#E3EAF3` · subtle divider `#EEF3FA` / `#F0F4FA` |
| Accent tint | `#E8F0FE` · border `#CDDDFB` |
| Success | `#16A34A` · tint `#E5F6EC` |
| Error | `#DC2626` |
| Warning | `#D97706` · tint `#FEF3DC` |
| Disabled fill | `#C6D4EA` · disabled text `#8296B3` |

## Type — Inter

Sizes in use: **11 · 12 · 12.5 · 13 · 13.5 · 14 · 14.5 · 15 · 16 · 22 · 24 · 26**. Weights: **600 · 700 · 800** only — nothing lighter than semibold appears anywhere. Headings carry `letter-spacing: -.02em`; uppercase labels carry `+.06em`.

## Geometry

- **Radii:** 10 · 12 · 14 (inputs) · 16 (buttons, cards) · 20 · 24 (feature cards) · 28 (bottom sheets) · `999` (pills)
- **Heights:** 52 inputs · 54 primary CTA · 44 touch targets and icon buttons · 38 filter chips · 26 checkboxes
- **Borders:** `1px` dividers, `1.5px` inputs and selectable cards, `2px` selected states

## Motion

🔧 **Round 40 replaced the per-animation durations with a four-step scale.** Build the Flutter side from the scale, not from the old literals — `mockups/design-composer/motion.css` is the live definition.

| Token | Duration | Used for |
|---|---|---|
| `--m-fast` | **120ms** | hover, press, colour, border |
| `--m-base` | **200ms** | in-place change, content swap, sheet OUT |
| `--m-sheet` | **300ms** | sheets, overlays, dialogs IN |
| `--m-page` | **350ms** | page and view transitions |

Two curves only: `--e-out` `cubic-bezier(.2,.8,.3,1)` for entering and settling, `--e-in` `cubic-bezier(.4,0,1,1)` for leaving. Infinite loops keep literal durations by convention — shimmer 1.4s, spinner .7s/.8s — because they are ambient rather than a response to a tap.

🔧 **These are web idioms and must not be transliterated.** `100dvh`, CSS gradients, `box-shadow` and `overflow-y:auto` all have Flutter equivalents, but copying them literally produces something that feels like a website in an app. Match the *values*; use Flutter's own elevation, scroll physics and page transitions.
