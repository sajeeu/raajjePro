---
name: mockup-fidelity-check
description: Use when implementing a screen against an attached mockup image. Triggers whenever a mockup file is referenced or attached.
---
# Mockup Fidelity Self-Check

Match the mockup pixel-for-pixel including motion — tap-scale, animated toggles, skeleton loaders, spring bottom sheets.

But WHERE A MOCKUP PREDATES THE CURRENT PLAN, THE PLAN WINS AND YOU FLAG THE MISMATCH. Do not silently implement the mockup. Known divergences to expect:
- The Explore grid shows 12 categories and the plan has 12 — including Boat Charter. If a mockup shows 11, the plan wins.
- The wizard's Availability step shows a per-listing "Accepting New Customers" toggle. That is now PROVIDER-LEVEL and lives on the dashboard. Remove it from the step.
- Any mockup implying contact details are exchanged between customer and provider is obsolete except for the emergency reveal path.
- Any mockup showing a single "Verified" badge is obsolete — verification is three tiers with tier-specific copy.

Before declaring a screen done: compare against the mockup at 1:1, check every state (not just populated), and list any deliberate divergence with its reason.
