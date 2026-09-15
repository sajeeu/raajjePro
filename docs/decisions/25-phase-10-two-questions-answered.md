# 25 — Phase 10's two open questions, answered from the plan

**Written by the verification session, 2026-09-15, before Phase 10's own
decision record exists.** It is here rather than in a chat because the answers
were sent to a stale socket and very nearly did not arrive at all. §Phase 10's
own record should cite this and then supersede it.

Neither answer is really a judgment call. Both follow from text already in the
plan, which is why they are recorded as readings with citations rather than as
new decisions the owner has to ratify.

---

## Q1 — how a provider overrides which listing stays visible over the cap

**Answer: a keep-visible pin. Not the two-step hide-then-activate.**

§1b already *requires* the override — "**The provider can override the choice
from the dashboard**" — so the only open question was its mechanism, and the
plan answers that too, two lines earlier:

> `hidden_over_cap` is set and cleared **only** by the entitlement system;
> `hidden_by_provider` **only** by the provider … Upgrade therefore restores
> exactly what downgrade hid and never resurrects a listing the provider took
> down for their own reasons — under a single `hidden` value those two cases
> are indistinguishable, and a paid upgrade would silently republish something
> the provider had deliberately withdrawn.

The two-step path — hide the kept listing with `PATCH …/visibility`, activate
the other — makes the provider write `hidden_by_provider` onto a listing the
*system* hid. That is the same conflation the Round 17 split exists to
prevent, arriving one listing at a time through a supported endpoint, and it
breaks §1b's "**any confirmed payment restores everything**" for the swapped
listing: on upgrade, entitlement restores what it hid and leaves the
provider-hidden one down.

`docs/decisions/22-phase-8a-subscription-and-trial.md` ("No provider-facing
'keep this one instead' endpoint") noted the two-step path is *reachable*
today and asked §Phase 10 to decide whether it is good enough. It is not.

**Shape:** a nullable pin on the provider profile, set by
`POST /v1/providers/me/listings/:id/keep-visible`.
`applyEntitlementVisibility` ranks the pinned listing ahead of §1b's ranking
(confirmed bookings over 90 days → views → recency) and stays the **only**
writer of `hidden_over_cap`. Two things to get right:

- **A stale pin must not hold a slot.** Clear or ignore it when the pinned
  listing is no longer publishable, or a draft keeps a live listing hidden.
- **The endpoint sets the pin; it does not toggle visibility.** That is what
  keeps the two writers from ever overlapping.

---

## Q2 — "Duplicate as draft" in the service-card context menu

**Answer: drop it from the menu.**

Nothing is owed. The plan specifies no duplicate action anywhere — its four
occurrences of the word cover three concepts, none of them a listing: a
duplicated FAQ accordion to delete (§Phase 9), a payment-fraud signal
(§Phase 10a), and alert de-duplication (§Phase 21), which appears twice
because §0.0's Round 8 corrections summary restates it.
§Phase 10's bullet asks for "service cards with context menu" and enumerates
no actions, and its Done-when — "every context-menu action performs a real
mutation" — constrains whichever actions exist rather than requiring this one.
Building it would be adding a feature nobody asked for, which Scope Discipline
rules out.

**And it could not work as drawn.** A duplicate that does not carry the media
lands a draft with no cover image, and a cover image is a publish requirement
(invariant 2) — so the copy cannot be published until the provider re-uploads
the photos they just asked the app to copy. That is a menu item whose normal
outcome is an unpublishable draft.

🔧 **The obvious fix does not work either, and this is worth knowing before
anyone proposes it.** "Copy the media rows by object key" is blocked by the
schema: `ListingMedia.objectKey` is `@unique`, so two listings cannot
reference one stored object. A real Duplicate therefore needs either a genuine
re-upload per image or a schema change (drop the uniqueness, or model a
shared object with per-listing references) — not one endpoint. If the owner
wants Duplicate, it is scope with a schema question attached, and should be
asked for as such.

**Menu stays:** Edit · View as customer · Pause/Resume · Delete. All real
mutations, Done-when clean. Removing it from `My Services.dc.html` is a design
round, not a prototype edit.

---

## Two calls Phase 10 flagged, both of which stand

- **`acceptingNewCustomers` does not render on this dashboard.** The artboard
  draws no toggle, §Phase 10's bullets ask for none, and `Billing.dc.html`
  surfaces the pause as "Pause Premium". Ledger **P8A-4** should record the
  dashboard half as answered "does not render here" and leave the copy owed by
  §Phase 10a's billing screen — a row closes when the thing is proven, not
  when one of its two halves turns out to be moot.
- **The Verification row points at `UnbuiltScreen(owedBy: 'Phase 23')`**,
  matching what §Phase 6 did when it deferred the same row.

## One Done-when clause that is easy to half-test

§Phase 10 wants the badge to persist through a subscription lapse. That needs
a fixture where entitlement has degraded **while `verificationTier` is bronze
or above** — two axes, separately set. A fixture that degrades both together
passes while proving nothing, and invariant 1b is explicit that the badge is
gated by `verificationTier` alone, never by subscription state.
