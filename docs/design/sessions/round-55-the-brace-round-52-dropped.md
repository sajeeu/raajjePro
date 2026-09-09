# Round 55 — the brace Round 52 dropped

Round 52 added an `alias` to the `Villimalé` island row in six files. In **four
of them the closing brace went with it**, and the row now reads:

```js
{ l: 'Villimalé', c: '', alias: 'Vilingili K. Villingili' ,
```

That is not a data typo. The object never closes before the next `{`, so it is
a **JavaScript syntax error in the component script** — the `ISLANDS` array does
not parse, and island search on that screen is gone. Not one row missing: the
control.

**Leave alone:** everything else. No layout, no colour, no copy, no component,
no animation, no other island row, and nothing from Rounds 40–54. This round
inserts one character in each of four files.

---

## The four files

`Home`, `Emergency Flow`, `Create Service`, `Saved Preferences`.

`Discovery` and `Become a Provider` took the same Round 52 edit and are
**correct** — leave both untouched.

## The fix

In each of the four, close the object before the comma. The row must end:

```js
... alias: 'Vilingili K. Villingili' },
```

Change nothing else on that line — not the label, not the alias string, not
`c: ''`, and do not add or remove an `a:` field. Two of these files carry
`a: 'Malé Region'` on the row and two do not; whichever the file has today is
what it keeps. The only edit is the missing `}`.

---

## Why this is worth a round of its own

**The repo has already repaired all four locally**, so the prototypes in
`mockups/design-composer/` are correct and the verifier passes on all 61. That
is exactly what makes this urgent rather than cosmetic: **the project is the
source and the repo is the copy**, so the next round that touches an island
list copies these four broken rows back down over the repairs. Fixing it here
is the only fix that holds.

It also means the design project's own preview of those four screens is broken
right now, and has been since Round 52.

## What to check before calling it done

- Each of the four screens **renders at all** — a parse error in the script
  block is not always a quiet failure.
- Open the island picker on each and type `villimale`, `vilingili` and
  `villingili`. All three must reach the one `Villimalé` row.
- `vilin'gili` must still reach `GA. Vilin'gili` — a different island, and
  Round 52 §5 says so.
- The row appears **once** per picker.

## One note for the next edit of this kind

Round 52 asked for the same one-field addition in six copies of the same array,
and it landed malformed in four of them. That is the failure mode of duplicated
data, not of anyone's attention — Round 52 §6 already recorded that the island
list exists seven times and belongs in `session.js`. This round is the second
bill for that duplication. Still not this round.

---

## Checklist

- [ ] `Home` — row closes with `},`
- [ ] `Emergency Flow` — row closes with `},`
- [ ] `Create Service` — row closes with `},`
- [ ] `Saved Preferences` — row closes with `},`
- [ ] `Discovery` and `Become a Provider` untouched
- [ ] All four screens render, and island search works in each — checked by typing
- [ ] `vilin'gili` still finds `GA. Vilin'gili`
- [ ] Nothing else in any file changed
