---
name: screen-state-completeness
description: Use when building or reviewing any Flutter screen. Triggers on any work under frontend/lib/features/ that renders data, or mentions of a screen, page, tab, or view.
---
# Screen State Completeness

Every screen implements four states. This is part of the screen's own definition of done, not Phase 20's audit — Phase 20 only VERIFIES what each phase already specified.

1. LOADING — skeleton loader matching the populated layout's shape, not a centred spinner and not a blank screen.
2. EMPTY — names what the user should do next, with an action where one exists. "No saved services yet" plus a route into Explore, never a bare "Nothing here."
3. ERROR — states what failed in human terms and offers retry. Never a raw error code or a stack trace.
4. POPULATED — the real thing.

Also handle, where applicable:
- Offline: a visible banner, and pending indicators on anything queued.
- Partial failure: one section failing must not blank the whole screen.
- A first-time state distinct from a genuinely-empty one where the difference matters to the user.

A "no data yet" metric reads as "No data yet" — never a blank, and never a zero that reads worse than no metric at all.
