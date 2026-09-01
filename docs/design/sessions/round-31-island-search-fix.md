# Round 31 — two fixes to the island picker

Round 30 landed well: the native `<select>` is gone from `Saved Preferences` and `Emergency Flow`, both placeholder notices are deleted, `Discovery` no longer quotes a total, and the search sheet, atoll-prefix labels and no-cap result list are all correct.

Two things to fix. **Change only these.**

## 1. Typing `male` finds nothing — fold accents in search

`searchIslands` normalises apostrophes, dots, spaces and case, but not the accented `é`:

```js
const norm = s => s.toLowerCase().replace(/['’.\s]/g, '');
```

So `norm('Malé')` is `'malé'`, and `'malé'.includes('male')` is **false**. Typing `male` returns nothing. Typing `hulhumale` returns nothing. Those are the two most-searched islands in the country, and the fix in Round 30 §7 — standardising on the accented spelling — is what introduced it.

**Fold diacritics before comparing:**

```js
const norm = s => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
                   .toLowerCase().replace(/['’.\s]/g, '');
```

The **displayed** label keeps its accent — `Malé` still renders as `Malé`. Only the comparison key is folded.

Apply it in every copy of `searchIslands`: `Discovery`, `Home`, `Create Service`, `Become a Provider`, `Saved Preferences` and `Emergency Flow`.

After the change these must all work: `male` and `malé` → Malé, Hulhumalé · `hulhumale` → Hulhumalé · `mee` → the three Meedhoos · `dh mee` / `dhmee` → Dh. Meedhoo.

## 2. Widen the sample list

The 14-island sample reads as though it were the whole list, and two things are missing from it that the rule depends on. Replace it with these **20**, keeping the same `{ l, c }` shape and the same atoll-prefix convention:

```
Malé
Hulhumalé
Villimalé
Maafushi
Thulusdhoo
K. Guraidhoo
Th. Guraidhoo
Dh. Meedhoo
R. Meedhoo
S. Meedhoo
L. Hithadhoo
S. Hithadhoo
K. Vilingili
GA. Vilin'gili
An'golhitheemu
Kulhudhuffushi
Fuvahmulah
Kudahuvadhoo
GDh. Faresmaathodaa
GDh. Thinadhoo
```

Three of these are carrying weight and should not be dropped:

- **`An'golhitheemu`** is the only entry with a Dhivehi apostrophe *inside* the name. It is what proves the apostrophe-insensitive rule — typing `angolhi` must find it.
- **`K. Vilingili` and `GA. Vilin'gili`** are two different islands one apostrophe apart. They are the case that only an apostrophe-folded comparison distinguishes, and the reason the ambiguous set is computed on a normalised name rather than an exact one.
- **`GDh. Faresmaathodaa`** and **`GDh. Thinadhoo`** give the south a presence and make `gdh` a working query. Note `GDh. Thinadhoo` and `V. Thinadhoo` — add **`V. Thinadhoo`** as well if you want the pair; otherwise leave Thinadhoo prefixed as written.

Where a screen shows a smaller subset for space (a chip row, a card), keep whatever it shows — this is about the list the search sheet draws from.

---

## Leave alone

Everything else from Round 30, all of which came back right:

- The searchable sheet replacing the `<select>` in `Saved Preferences` and `Emergency Flow` — position, validation and the surrounding flow are all correct
- `Discovery`'s `Showing {{ islandShown }} — keep typing to narrow` with no denominator, and its `islandQ: 'mee'` default that shows the search working rather than a list at rest
- The atoll-prefix labels, the unprefixed unambiguous names, and the prefix rendered as part of the label rather than as a badge
- Prefix-first ranking, atoll-code matching, the uncapped scrolling result list, and the plain `No island matches "…"` line
- Both deleted placeholder notices — they do not come back
- The `Malé` / `Hulhumalé` spelling itself. It is correct; only the search comparison was wrong.
