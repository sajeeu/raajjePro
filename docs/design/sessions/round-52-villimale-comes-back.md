# Round 52 — Villimalé comes back, as one island

Round 32 removed `Villimalé` from `Discovery` because the picker was listing the
same island twice. That was right about the duplicate and wrong about which name
to keep. This round brings it back as **one row under the name people use**, and
makes the register name find it.

**Leave alone:** every layout, colour, component, animation and every piece of
copy. This round changes island data and one search function.

---

## Why

`Villimalé` and `K. Vilingili` are the same place — the island administratively
part of Malé City. Round 32 kept the register spelling and dropped the common
one, which left the prototype in a state nobody intended:

| | Islands | `Villimalé` | `K. Vilingili` |
|---|---|---|---|
| `Discovery` | 192 (full register) | absent | present |
| `Home`, `Create Service`, `Become a Provider`, `Emergency Flow`, `Saved Preferences` | 20 (sample) | present | **also present** |
| `Pick a Time`, `Request a Time` | 3 (a `<select>`) | present | — |

So one screen has the register and seven do not, and five of them still ship the
exact duplicate Round 32 set out to remove. The break a customer hits: set your
island to **Villimalé** on Home, open Explore, and the picker has no such entry.

The fix is not to pick a winner between two rows. It is to have **one row with
two names** — the label people read, and an alias the search matches.

---

## 1. `Discovery` — one row, labelled `Villimalé`

**Replace** the register row

```js
{ l: 'K. Vilingili', c: 'K', a: 'Kaafu' },
```

**with**

```js
{ l: 'Villimalé', c: '', a: 'Malé Region', alias: 'Vilingili K. Villingili' },
```

- **The label is `Villimalé`** because that is what a customer types and what
  every other picker already shows. The register spelling does not disappear —
  it moves into `alias`, where search still finds it.
- **`Malé Region`, not `Kaafu`.** It is a ward of Malé City, and that is how the
  five sample pickers already group it. Keeping it in Kaafu would put it in a
  different section from Malé and Hulhumalé, which is not where anyone would
  look for it.
- Do **not** add a second row. One island, one entry.

`GA. Vilin'gili` is a different island and is unchanged.

---

## 2. `searchIslands` — match the alias

All six copies of this function are currently byte-identical. Keep them that
way: make the same edit in `Discovery`, `Home`, `Create Service`,
`Become a Provider`, `Emergency Flow` and `Saved Preferences`.

```js
return all.filter(i => norm(i.l).includes(query) || norm(i.c + i.l).includes(query))
```

**becomes**

```js
return all.filter(i => norm(i.l).includes(query) || norm(i.c + i.l).includes(query)
                    || (i.alias && norm(i.alias).includes(query)))
```

Leave `norm`, `bare` and `starts` exactly as they are — an alias hit should rank
below a label hit, which is what happens if `starts` is untouched.

**Verify by typing.** `vilingili`, `villingili`, `vilin'gili` and `villimale`
must all reach the right island, and `vilin'gili` must still reach
`GA. Vilin'gili`.

---

## 3. The other seven pickers

**Five sample lists** — `Home`, `Create Service`, `Become a Provider`,
`Emergency Flow`, `Saved Preferences` — each carry both names today. Delete
their `K. Vilingili` row and give the surviving `Villimalé` row the same
`alias` value as §1. Their `Villimalé` entries are already
`{ l: 'Villimalé', c: '' }`, so only the alias is added.

**Two `<select>` menus** — `Pick a Time` and `Request a Time` offer
`Malé / Hulhumalé / Villimalé`. They are correct and need no change.

---

## 4. Settled, and recorded so it is not reopened

**R. Maamin'gili stays out of the list.** The question was whether the register
was wrong to omit it. It was not —
[Maamigili (Raa Atoll)](https://en.wikipedia.org/wiki/Maamigili_(Raa_Atoll))
records it as **uninhabited**, and the picker lists inhabited islands. The one
`Maamin'gili` in the register is the ADh island, and it correctly stands bare
with no atoll prefix because no other Maamin'gili is in the list to collide
with.

Nothing to do. Written down because this has now been asked twice.

---

## 5. What must not change

- **`GA. Vilin'gili`** — a different island in a different atoll.
- **The 33 atoll prefixes.** The register list is internally exact: every
  prefixed name is genuinely shared, and no shared name is left bare. Replacing
  `K. Vilingili` with a bare `Villimalé` keeps that true, because nothing else
  in the list is called Villimalé.
- **`norm` and the ranking.** Round 31's apostrophe folding is what makes
  `vilin'gili` and `vilingili` both work, and it is untouched.
- The other 191 register rows, and the 20-island samples apart from the one
  deleted row and the one added alias.
- Everything in Rounds 40–51.

---

## 6. Not an instruction — the island list exists seven times

Seven copies of the island data and six identical copies of `searchIslands` are
why this correction has to be made in six places instead of one. `session.js` is
already a shared sibling that every screen loads, and island data belongs there.

Not this round — it touches every picker and this round should stay small. Noted
so the next person does not rediscover it while fixing the eighth copy.

---

## Checklist

- [ ] `Discovery` has one `Villimalé` row, in `Malé Region`, with the alias
- [ ] `K. Vilingili` appears in no file
- [ ] All six `searchIslands` copies match the alias and are still identical to each other
- [ ] `vilingili`, `villingili`, `villimale` all find Villimalé — checked by typing
- [ ] `vilin'gili` still finds `GA. Vilin'gili`
- [ ] The five sample pickers show Villimalé once
- [ ] R. Maamin'gili is still absent
- [ ] Nothing from Rounds 40–51 changed
