# Round 32 — the real list in Discovery, and two things Round 30 missed

Round 31 landed correctly: search folds accents, `male` finds Malé, and the twenty-island sample exercises `gdh`, `angolhi` and the Vilingili pair. Three changes.

## 1. `Discovery` carries all 192 islands

The sample keeps reading as the whole list. Twice now someone has gone looking for a real island — **Faresmaathodaa**, then **Huraa** — found it absent from the picker, and reasonably concluded the data was wrong. It wasn't; the picker was showing twenty of a hundred and ninety-two with nothing saying so.

**Replace `Discovery`'s `ISLANDS` with the full list below.** It is generated from the government register, and it is what makes the picker worth testing: real scroll length, real search behaviour, real ambiguity.

Everything about the search stays exactly as it is — the same `searchIslands`, the same accent and apostrophe folding, the same prefix-first ranking, the same uncapped scrolling list. Only the data grows. Keep `islandQ: 'mee'` as the default so the sheet still opens mid-search rather than showing 192 rows at rest.

Two things to note about the list itself:

- **33 of the 192 carry an atoll prefix**, being the ones whose name is shared. The other 159 stand bare. This is the Round 30 rule applied to the real data, computed on the case-folded apostrophe-stripped name — which is why both `K. Vilingili` and `GA. Vilin'gili` are prefixed even though the raw strings differ.
- **`Villimalé` is gone, and that is deliberate.** The current sample lists both `Villimalé` and `K. Vilingili` — those are the same island under two names, so the picker was offering it twice. The register's name is `Vilingili`, so `K. Vilingili` is what remains. (Locally it is still called Villimalé; if you want that as a searchable alias it is a separate change, not this one.)

```js
ISLANDS = [
    { l: 'Bodufolhudhoo', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Feridhoo', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Himendhoo', c: 'AA', a: 'Alifu Alifu' },
    { l: 'AA. Maalhos', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Mathiveri', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Rasdhoo', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Thoddoo', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Ukulhas', c: 'AA', a: 'Alifu Alifu' },
    { l: 'Dhan\'gethi', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Dhigurah', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'ADh. Dhihdhoo', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Fenfushi', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Hangnaameedhoo', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'ADh. Kun\'burudhoo', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Maamin\'gili', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Mahibadhoo', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Mandhoo', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'ADh. Omadhoo', c: 'ADh', a: 'Alifu Dhaalu' },
    { l: 'Dharavandhoo', c: 'B', a: 'Baa' },
    { l: 'Dhonfanu', c: 'B', a: 'Baa' },
    { l: 'Eydhafushi', c: 'B', a: 'Baa' },
    { l: 'Fehendhoo', c: 'B', a: 'Baa' },
    { l: 'Fulhadhoo', c: 'B', a: 'Baa' },
    { l: 'B. Goidhoo', c: 'B', a: 'Baa' },
    { l: 'Hithaadhoo', c: 'B', a: 'Baa' },
    { l: 'Kamadhoo', c: 'B', a: 'Baa' },
    { l: 'Kendhoo', c: 'B', a: 'Baa' },
    { l: 'Kihaadhoo', c: 'B', a: 'Baa' },
    { l: 'Kudarikilu', c: 'B', a: 'Baa' },
    { l: 'B. Maalhos', c: 'B', a: 'Baa' },
    { l: 'Thulhaadhoo', c: 'B', a: 'Baa' },
    { l: 'Ban\'didhoo', c: 'Dh', a: 'Dhaalu' },
    { l: 'Hulhudheli', c: 'Dh', a: 'Dhaalu' },
    { l: 'Kudahuvadhoo', c: 'Dh', a: 'Dhaalu' },
    { l: 'Maaen\'boodhoo', c: 'Dh', a: 'Dhaalu' },
    { l: 'Dh. Meedhoo', c: 'Dh', a: 'Dhaalu' },
    { l: 'Rin\'budhoo', c: 'Dh', a: 'Dhaalu' },
    { l: 'Vaanee', c: 'Dh', a: 'Dhaalu' },
    { l: 'Bileiydhoo', c: 'F', a: 'Faafu' },
    { l: 'Dharan\'boodhoo', c: 'F', a: 'Faafu' },
    { l: 'Feeali', c: 'F', a: 'Faafu' },
    { l: 'F. Magoodhoo', c: 'F', a: 'Faafu' },
    { l: 'F. Nilandhoo', c: 'F', a: 'Faafu' },
    { l: 'Dhaandhoo', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'Dhevvadhoo', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'Gemanafushi', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'Kan\'duhulhudhoo', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'Kolamaafushi', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'Kon\'dey', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'GA. Maamendhoo', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'GA. Nilandhoo', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'GA. Vilin\'gili', c: 'GA', a: 'Gaafu Alifu' },
    { l: 'Faresmaathodaa', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Fiyoari', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Gahdhoo', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Hoan\'dehdoo', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Madaveli', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Nadellaa', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Rathafandhoo', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'GDh. Thinadhoo', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'GDh. Vaadhoo', c: 'GDh', a: 'Gaafu Dhaalu' },
    { l: 'Fuvahmulah', c: 'Gn', a: 'Gnaviyani' },
    { l: 'Baarah', c: 'HA', a: 'Haa Alifu' },
    { l: 'HA. Dhihdhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Filladhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Huvarafushi', c: 'HA', a: 'Haa Alifu' },
    { l: 'Ihavandhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Kelaa', c: 'HA', a: 'Haa Alifu' },
    { l: 'Maarandhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Mulhadhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Muraidhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Thakandhoo', c: 'HA', a: 'Haa Alifu' },
    { l: 'Thuraakunu', c: 'HA', a: 'Haa Alifu' },
    { l: 'Uligamu', c: 'HA', a: 'Haa Alifu' },
    { l: 'Utheemu', c: 'HA', a: 'Haa Alifu' },
    { l: 'Vashafaru', c: 'HA', a: 'Haa Alifu' },
    { l: 'Finey', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Hanimaadhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Hirimaradhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Kulhudhuffushi', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Kumundhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'HDh. Kun\'burudhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Kurin\'bee', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Makunudhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Naivaadhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Nellaidhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Neykurendhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Nolhivaramu', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Nolhivaranfaru', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Vaikaradhoo', c: 'HDh', a: 'Haa Dhaalu' },
    { l: 'Dhiffushi', c: 'K', a: 'Kaafu' },
    { l: 'Gaafaru', c: 'K', a: 'Kaafu' },
    { l: 'Gulhi', c: 'K', a: 'Kaafu' },
    { l: 'K. Guraidhoo', c: 'K', a: 'Kaafu' },
    { l: 'Hinmafushi', c: 'K', a: 'Kaafu' },
    { l: 'Hulhumalé', c: 'K', a: 'Kaafu' },
    { l: 'Huraa', c: 'K', a: 'Kaafu' },
    { l: 'Kaashidhoo', c: 'K', a: 'Kaafu' },
    { l: 'Maafushi', c: 'K', a: 'Kaafu' },
    { l: 'Malé', c: 'K', a: 'Kaafu' },
    { l: 'Thulusdhoo', c: 'K', a: 'Kaafu' },
    { l: 'K. Vilingili', c: 'K', a: 'Kaafu' },
    { l: 'Dhan\'bidhoo', c: 'L', a: 'Laamu' },
    { l: 'Fonadhoo', c: 'L', a: 'Laamu' },
    { l: 'Gan', c: 'L', a: 'Laamu' },
    { l: 'L. Hithadhoo', c: 'L', a: 'Laamu' },
    { l: 'Isdhoo', c: 'L', a: 'Laamu' },
    { l: 'Kalhaidhoo', c: 'L', a: 'Laamu' },
    { l: 'Kunahandhoo', c: 'L', a: 'Laamu' },
    { l: 'Maabaidhoo', c: 'L', a: 'Laamu' },
    { l: 'L. Maamendhoo', c: 'L', a: 'Laamu' },
    { l: 'Maavah', c: 'L', a: 'Laamu' },
    { l: 'Mundoo', c: 'L', a: 'Laamu' },
    { l: 'Hinnavaru', c: 'Lh', a: 'Lhaviyani' },
    { l: 'Kurendhoo', c: 'Lh', a: 'Lhaviyani' },
    { l: 'Maafilaafushi', c: 'Lh', a: 'Lhaviyani' },
    { l: 'Naifaru', c: 'Lh', a: 'Lhaviyani' },
    { l: 'Olhuvelifushi', c: 'Lh', a: 'Lhaviyani' },
    { l: 'Dhiggaru', c: 'M', a: 'Meemu' },
    { l: 'Kolhufushi', c: 'M', a: 'Meemu' },
    { l: 'M. Maduvvari', c: 'M', a: 'Meemu' },
    { l: 'Mulah', c: 'M', a: 'Meemu' },
    { l: 'Muli', c: 'M', a: 'Meemu' },
    { l: 'Naalaafushi', c: 'M', a: 'Meemu' },
    { l: 'Raiymandhoo', c: 'M', a: 'Meemu' },
    { l: 'Veyvah', c: 'M', a: 'Meemu' },
    { l: 'Fohdhoo', c: 'N', a: 'Noonu' },
    { l: 'Hen\'badhoo', c: 'N', a: 'Noonu' },
    { l: 'Holhudhoo', c: 'N', a: 'Noonu' },
    { l: 'Ken\'dhikulhudhoo', c: 'N', a: 'Noonu' },
    { l: 'Kudafari', c: 'N', a: 'Noonu' },
    { l: 'Landhoo', c: 'N', a: 'Noonu' },
    { l: 'Lhohi', c: 'N', a: 'Noonu' },
    { l: 'Maafaru', c: 'N', a: 'Noonu' },
    { l: 'Maalhendhoo', c: 'N', a: 'Noonu' },
    { l: 'N. Magoodhoo', c: 'N', a: 'Noonu' },
    { l: 'Manadhoo', c: 'N', a: 'Noonu' },
    { l: 'Miladhoo', c: 'N', a: 'Noonu' },
    { l: 'Velidhoo', c: 'N', a: 'Noonu' },
    { l: 'Alifushi', c: 'R', a: 'Raa' },
    { l: 'An\'golhitheemu', c: 'R', a: 'Raa' },
    { l: 'Dhuvaafaru', c: 'R', a: 'Raa' },
    { l: 'Fainu', c: 'R', a: 'Raa' },
    { l: 'Hulhudhuffaaru', c: 'R', a: 'Raa' },
    { l: 'In\'guraidhoo', c: 'R', a: 'Raa' },
    { l: 'Innamaadhoo', c: 'R', a: 'Raa' },
    { l: 'Kinolhas', c: 'R', a: 'Raa' },
    { l: 'Maakurathu', c: 'R', a: 'Raa' },
    { l: 'R. Maduvvari', c: 'R', a: 'Raa' },
    { l: 'R. Meedhoo', c: 'R', a: 'Raa' },
    { l: 'Rasgetheemu', c: 'R', a: 'Raa' },
    { l: 'Rasmaadhoo', c: 'R', a: 'Raa' },
    { l: 'Un\'goofaaru', c: 'R', a: 'Raa' },
    { l: 'R. Vaadhoo', c: 'R', a: 'Raa' },
    { l: 'S. Feydhoo', c: 'S', a: 'Seenu' },
    { l: 'S. Hithadhoo', c: 'S', a: 'Seenu' },
    { l: 'Hulhudhoo', c: 'S', a: 'Seenu' },
    { l: 'Maradhoo', c: 'S', a: 'Seenu' },
    { l: 'Maradhoofeydhoo', c: 'S', a: 'Seenu' },
    { l: 'S. Meedhoo', c: 'S', a: 'Seenu' },
    { l: 'Bileiyfahi', c: 'Sh', a: 'Shaviyani' },
    { l: 'Feevah', c: 'Sh', a: 'Shaviyani' },
    { l: 'Sh. Feydhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Foakaidhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Funadhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Sh. Goidhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Kan\'ditheemu', c: 'Sh', a: 'Shaviyani' },
    { l: 'Komandoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Lhaimagu', c: 'Sh', a: 'Shaviyani' },
    { l: 'Maaun\'goodhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Maroshi', c: 'Sh', a: 'Shaviyani' },
    { l: 'Milandhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Narudhoo', c: 'Sh', a: 'Shaviyani' },
    { l: 'Noomaraa', c: 'Sh', a: 'Shaviyani' },
    { l: 'Burunee', c: 'Th', a: 'Thaa' },
    { l: 'Dhiyamigili', c: 'Th', a: 'Thaa' },
    { l: 'Gaadhiffushi', c: 'Th', a: 'Thaa' },
    { l: 'Th. Guraidhoo', c: 'Th', a: 'Thaa' },
    { l: 'Hirilandhoo', c: 'Th', a: 'Thaa' },
    { l: 'Kan\'doodhoo', c: 'Th', a: 'Thaa' },
    { l: 'Kin\'bidhoo', c: 'Th', a: 'Thaa' },
    { l: 'Madifushi', c: 'Th', a: 'Thaa' },
    { l: 'Th. Omadhoo', c: 'Th', a: 'Thaa' },
    { l: 'Thimarafushi', c: 'Th', a: 'Thaa' },
    { l: 'Vandhoo', c: 'Th', a: 'Thaa' },
    { l: 'Veymandoo', c: 'Th', a: 'Thaa' },
    { l: 'Vilufushi', c: 'Th', a: 'Thaa' },
    { l: 'Felidhoo', c: 'V', a: 'Vaavu' },
    { l: 'Fulidhoo', c: 'V', a: 'Vaavu' },
    { l: 'Keyodhoo', c: 'V', a: 'Vaavu' },
    { l: 'Rakeedhoo', c: 'V', a: 'Vaavu' },
    { l: 'V. Thinadhoo', c: 'V', a: 'Vaavu' }];
```

## 2. The other five pickers keep a sample — and say so

`Home`, `Create Service`, `Become a Provider`, `Saved Preferences` and `Emergency Flow` keep the twenty-island list exactly as it is now. Duplicating 192 entries into six files would be six copies of the same data drifting apart, and the seed is the source of truth.

But they must stop pretending to be complete. Add one quiet line at the **bottom of each island sheet**, below the results, in the same muted style as `Discovery`'s "Showing … — keep typing to narrow":

> Sample list — the live app has all 192 inhabited islands

Small, grey, not a warning box. It is a statement of fact about a prototype, not an alert. Do not bring back the amber placeholder banners that Round 30 removed — those said the data did not exist, which is no longer true.

`Discovery` does **not** get this line; it has the real list.

## 3. Qualified island names outside the pickers

Round 30 §8 asked for this and it did not land — every one of these screens still shows a bare island name, so the atoll rule exists only where it is least needed.

**`ServiceCard`, `Service Preview`, `Provider Profile`, `Booking Request`, `Pick a Time` and `Request a Time`** each render one island beside a pin icon. The rule is the same everywhere: an ambiguous name carries its atoll code, an unambiguous one does not.

Change **at least two** of the demo values to a qualified name so the pattern is visible at card and booking scale — `Th. Guraidhoo` on a `ServiceCard` and `Dh. Meedhoo` on a `Booking Request` would do it. Leave `Malé` and `Hulhumalé` as they are elsewhere; they need no prefix and are the realistic common case.

Also update `ServiceCard`'s `island` prop description so the convention is documented where the component is defined, not only where it is used.

## 4. `Components` passes a prop that does not exist

`Components.dc.html` mounts `ServiceCard` with `emergency="{{ true }}"`. **`ServiceCard` has no `emergency` prop** — Round 23 removed the emergency marker from cards, because dispatch never targets a provider and the badge advertised an action that did not exist.

It renders nothing, so it has been invisible. But the component sheet is the gallery people read as the spec, and it currently documents a prop that was deliberately deleted. **Remove the attribute.** Nothing replaces it — the card's second signal is already next-open-time or median response time, and the callback badge is separate.

---

## Leave alone

- `searchIslands` in all six screens — the accent folding, apostrophe folding, prefix ranking, atoll-code matching and uncapped results are all correct
- `Discovery`'s missing denominator and its `islandQ: 'mee'` default
- The searchable sheet that replaced the native `<select>` in `Saved Preferences` and `Emergency Flow`
- The `Malé` / `Hulhumalé` spelling
- Every selection model — multi-select where it is multi-select, single where it is single
