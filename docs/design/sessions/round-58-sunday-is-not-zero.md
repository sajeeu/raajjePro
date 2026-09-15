# Round 58 — Sunday is not zero

**One screen: `Availability.dc.html`. One value. Leave everything else alone,
including everything Round 57 just changed — that import is correct and is in
the repo.**

This is a small thing that the design cannot see and the build can, which is
why it comes back as its own round rather than sitting in a comment.

## The day picker emits a number the API refuses

The rule editor's seven day buttons are indexed from `DAY_NAMES`:

```js
DAY_NAMES = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
```

so Sunday is `0` and Saturday is `6`. That is JavaScript's `Date#getDay()`,
and it is a reasonable thing to reach for inside a prototype that generates
its own times.

The API uses **ISO weekdays, 1 = Monday, 7 = Sunday**, and validates them:

```ts
z.array(z.int().min(1).max(7))
```

Monday through Saturday happen to agree in both schemes, so nothing looks
wrong on screen. **Sunday is the only value that diverges, and it is the one
that would be rejected** — a rule for Sundays would be refused by the server
with no hint on the artboard as to why.

The built app is already correct: its editor runs `for (day = 1; day <= 7;
day++)` and its labels are `M T W T F S S`, Monday-first. So this is the
prototype disagreeing with both the API and the app, not a defect in the
product.

**What to change:**

- `DAY_NAMES` becomes Monday-first — `['Mon','Tue','Wed','Thu','Fri','Sat','Sun']`
  — and the rule data moves with it: `days:[1,2,3,4]` is already Mon–Thu under
  ISO, and the Saturday rule `days:[6]` stays `6`.
- The day buttons then read **M T W T F S S**, which is also the order the app
  draws and the order a Maldivian working week is usually written in.
- `genTimes` maps a real `Date` to a rule, so wherever it uses `dt.getDay()`
  it needs `((dt.getDay() + 6) % 7) + 1` to speak ISO.

Nothing visible changes except the order of the seven buttons.

## Why it is worth a round at all

The prototype is the source and the repo is the copy. A future reader who
implements a second surface from this artboard — the customer's `Pick a Time`,
or the admin's view of a provider's hours — would take the numbering from here
and be wrong about exactly one day of the week, which is the kind of thing that
ships. Fixing it in the source is cheaper than catching it twice.

## Also worth knowing, and not a change request

Adding an exception from the sheet appends it to the list but does not change
the grid, because the preset carries no `covers` range and the seeded Ramadan
entry does not either. That is a prototype limitation rather than a claim the
product cannot keep, and the copy around it is accurate. Leave it unless you
want the preset to demonstrate its own effect, in which case give each preset
a `covers` range the way `AWAY` has one.
