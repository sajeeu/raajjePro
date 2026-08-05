---
name: wizard-step-pattern
description: Use when building, editing, or reviewing any step of the Create/Edit Service Wizard, or any other multi-step flow (provider onboarding, booking request, forgot-password). Triggers on mentions of "wizard," "step," "multi-step flow," or work inside frontend/lib/features/service_wizard/.
---
# Multi-Step Wizard Pattern

- Each step is a standalone widget accepting the current draft state + an onChange callback — never reads global state directly, so it can be tested in isolation.
- Step navigation state (which step is active, which are "complete") lives in a single Riverpod controller for the wizard, not per-step.
- "Complete" for progress-bar purposes means "has the minimum data for this step to be meaningful," NOT "passes publish validation" — different checks. A step can be visited and left blank; it just won't show a green check.
- Every step's onChange triggers a debounced PATCH to the draft entity — don't wait for "Continue" to persist.
- Offline resilience uses the shared queue-and-replay helper (see the offline-queue-and-replay skill), not a wizard-local implementation.
- The final review step is the only place full validation runs, and it must produce a FIELD-LEVEL list — not a generic "form invalid" — mapping to "Fix" deep links back to the offending step.
- Step navigation is never blocked by incomplete validation. A user can always jump straight to review with nothing filled in.
- Progress framing leads with required-fields-remaining, not step count, wherever the plan specifies it.
