# Round 47 — the retry that does nothing

Round 45 §1 replaced nineteen `noop`s with a `retry` handler. The handler runs
and the screen does not move. This round makes it work.

**Leave alone:** every layout, colour, component, animation and flow, and all of
Rounds 40–46. This round changes one line per screen.

---

## What happened

Each of the nineteen screens got this:

```js
retry: () => this.setState({ scnOverride: 'populated' })
```

…while the line that decides which state renders was left as it was:

```js
const sc = this.props.scenario ?? 'populated';
```

`scnOverride` goes into state and nothing ever reads it back. Tapping **Try
again** sets a flag, re-renders, resolves the scenario from props exactly as
before, and leaves the error on screen.

It is worse than the `noop` it replaced, because `noop` was visible. The handler
now has a body and the control is no longer named `noop`, so both dead-control
rules pass it, and the warning that had been pointing at a real defect went
quiet while the defect stayed. The gate has a new rule for this shape —
*writes `scnOverride`, nothing reads it* — and it is currently warning on the
four screens already imported.

The six screens fixed in Round 43 do this correctly and are the model:

```js
const sc = s.scnOverride ?? this.props.scenario ?? 'populated';
```

---

## 1. Read the flag where the scenario is resolved

**All nineteen screens from Round 45 §1:**

`Book Again` · `Booking Detail` · `Booking Thread` · `Cancel Booking` ·
`Did This Happen` · `Dispatch Fee` · `Enquiry Thread` · `Messages` ·
`My Bookings` · `Payment Step` · `Pick a Time` · `Propose Amendment` ·
`Quote Received` · `Raise Dispute` · `Rate This Job` · `Recurring Booking` ·
`Report` · `Request a Time` · `Reveal Contact`

In each, find the line that resolves the scenario and put `scnOverride` in front
of it. The exact shape varies — some read `p.scenario`, some `this.props.scenario`,
some assign into `sc`, `scn` or `eff` — so match what the file already does:

| Currently | Becomes |
|---|---|
| `const sc = this.props.scenario ?? 'x'` | `const sc = this.state.scnOverride ?? this.props.scenario ?? 'x'` |
| `const sc = p.scenario ?? 'x'` | `const sc = s.scnOverride ?? p.scenario ?? 'x'` |
| `const eff = this.state.phase ?? sc` | leave `eff`; fix the `sc` line above it |

Where a file already destructures `const s = this.state`, use `s`. Where it does
not, use `this.state`. Do not add a `scnOverride` key to the `state = { … }`
initialiser — `undefined` is the correct starting value and `??` handles it.

**Verify each one by tapping it.** Set the screen to its error scenario, tap
**Try again**, and confirm the normal state renders. A handler that runs without
moving the screen is the exact defect this round exists to remove, so the check
is the point, not a formality.

### 1b. `Reveal Contact` has a second reader

Its scenario resolves in two steps:

```js
const p = this.props, sc = p.scenario ?? 'available';
const eff = this.state.phase ?? sc;
```

Fix the `sc` line. `eff` then picks the override up on its own.

### 1c. `Book Again` and `Report` have no `s`

Both read `this.props.scenario` directly with no `const s = this.state`. Use
`this.state.scnOverride` rather than introducing a new local.

---

## 2. While you are in these files — drop the unused `noop`

Every one of the nineteen still declares `noop: () => {}` beside the new `retry`,
and after Round 45 nothing references it. Delete the declaration wherever the
file has no remaining `noop` reference. Where one is still used, leave it.

This matters beyond tidiness: `noop` is the deliberate-placeholder marker the
gate is built around, and a `noop` sitting in a file that no longer has a
placeholder makes the next reader look for one.

---

## 3. What must not change

- The `on-action="{{ retry }}"` wiring itself. Round 45 got that half right and
  it stays.
- Every other Round 45 change — the clock icon, `Pick a time`, the `slot` prop
  value, the contact copy, the two `My Bookings` links, `Requested time`.
- The six screens Round 43 fixed: `Analytics`, `Booking Request`,
  `Mark Complete`, `Payment Received`, `Propose Time and Price`. They already
  read the flag correctly.

---

## Checklist

- [ ] All nineteen screens resolve their scenario through `scnOverride`
- [ ] Each **Try again** has been tapped and returns the screen to its normal state
- [ ] `Reveal Contact`'s two-step resolution works
- [ ] No file declares `noop` without using it
- [ ] Nothing from Rounds 40–46 changed
