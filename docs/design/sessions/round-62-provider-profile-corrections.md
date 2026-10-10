# Round 62: corrections to Provider Profile

Raised while building **§Phase 13** (the provider public profile) against
`Provider Profile.dc.html` and the `ServiceCard` component's `full` variant.
`verify-dc.py` passes on both. The items below are things a structural check
cannot see.

**Two are corrections to the prototype. One concerns how the card derives a
badge. The last section lists what was right and built as drawn, so nobody
"fixes" those.**

Change only what is named. Everything else on this screen was implemented as
drawn.

---

## 1. The headline is the business name, not a person's name

The header draws a person's name as the headline ("Ibrahim Rasheed"), the
business name under it ("Rasheed Plumbing Services"), and an avatar photo slot.
The footer button reads "Message Ibrahim".

The public provider shape carries **no personal name and no photo**. It has
`businessName` only, which §Phase 6a requires at onboarding. Elsewhere, a
person's name reaches only the two parties to a booking. The plan does not say
which name a public page shows. The control session decided, on the owner's
behalf, not to put new personal data on an endpoint a guest can read.
`docs/decisions/34-phase-13-provider-profile.md` §3 carries the reasoning.

**Change:**

- The headline becomes `d.biz`, and the second name line is removed.
- The avatar becomes the business name's initials (`RP`). Remove the
  `image-slot` there.
- The button becomes **"Message provider"**.

Leave the badge row, "Provider since", the rating row and the footer's privacy
line exactly as they are.

Do not add a provider photo anywhere. One would need its own plan decision.

---

## 2. "New provider" is only true below ten lifetime jobs

The below-floor card reads *"New provider · {jobs} jobs completed"*, and its
logic is `showNew: d.jobs < 10`.

§1f's floor is ten completed bookings **in the 90-day window**. The job count
beside it is **lifetime**, so a provider with 47 lifetime jobs and nine this
quarter is below the floor. That provider would read "New provider · 47 jobs
completed", which contradicts itself. Whether the rates show is the server's
`metricsBelowFloor` and nothing else, so the client cannot decide it from the
job count.

**Change:**

- Drive `showMetrics` and `showNew` from a `belowFloor` field, not from
  `d.jobs`.
- Below the floor, the title is "New provider · {jobs} jobs completed" only
  where `jobs < 10`. Otherwise it is "{jobs} jobs completed" alone.
- The body becomes *"Reliability numbers appear once a provider has completed
  ten bookings **in the last 90 days**."*

Add a third scenario, `below_floor_established` (47 jobs, below floor), so the
case is visible.

---

## 3. The card's callback badge must come from the listing, not a category table

`ServiceCard.dc.html` holds a `CALLBACK` map of six category names and shows the
badge where `p.callback && CALLBACK[p.category]`.

The rule is right (Round 28), but the mechanism is a hardcoded list, which is
what invariant 12a says never to do. The server already sends
`callbackGuarantee` as `offered && category.callbackEligible`, and the build
renders only that.

**Change:** show the badge from `p.callback` alone, and delete the `CALLBACK`
map with a comment that eligibility is the category's `callbackEligible`, decided
server-side. Nothing visible changes.

---

## 4. Implemented as drawn

Listed so a later round does not "fix" something that is already right:

- **The full `VerificationBadge`** in the header, with the tier's words, not
  the chip.
- **"Maldivian-owned business"** only at Gold with the attribute evidenced
  (§1g), never a statement about a person.
- **The track record**: six cells, numbers only, "Rolling last 90 days", and
  the response time beneath. No acceptance rate, which §1f's own example line
  does not use either. There is no editorial label anywhere.
- **"What customers say"**: tags as counts, negative tags included.
- **The not-found state's copy** and "Explore services". The server's 404 for a
  drafts-only provider is what renders it.
- **Save and Report appear only over a real profile**, as `hasBody` gates them.
