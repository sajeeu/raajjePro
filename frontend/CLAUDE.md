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
- Booking-mode affordances appear on every card and listing surface: "Book instantly" (slot), "Request a time" (request), plus an "Emergency available" marker where applicable. A customer must never be uncertain which kind of wait they are in.
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
