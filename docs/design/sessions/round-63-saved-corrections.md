# Round 63: corrections to the Saved screen

Raised while building **§Phase 14** (favourites) against the Saved screen in
`Discovery.dc.html`, the hearts in `ServiceCard.dc.html`, and Profile's Saved
row in `Profile.dc.html`. The items below are things a structural check cannot
see. `docs/decisions/35-phase-14-favorites.md` §4 has the reasoning.

Change only what is named. Everything else on these screens was built as drawn.

---

## 1. A saved provider's headline is the business name

The "Saved providers" row heads with a person's name ("Ibrahim Rasheed") and
puts the business name in the sub-line. Round 62 §1 already changed this on
the provider profile: the public provider shape has no personal name.

**Change, in `Discovery.dc.html`'s `PROV` data and row:**

- `name` becomes the business name: `Rasheed Plumbing Services` and
  `Lens & Light Studio`.
- The initials come from that name (`RP`, `LS`).
- `sub` becomes only what they offer, from their published services:
  `Plumbing`, `Photography`. Join several with ` · `.
- The Message button's label becomes `Message <business name>`.

## 2. The provider's name and avatar open their profile

The row has no destination. Make the avatar and text block one tap target that
opens `Provider Profile.dc.html`. Message and the heart stay separate targets
beside it. Do not make the whole card tappable, because it holds two controls.

## 3. Profile's Saved row carries a count

`Profile.dc.html`'s Saved row gains a number before its chevron: services
plus providers saved, in 12.5 px / 700 / `#5B6B84`. Draw nothing when the
count is zero, not a `0`. The row stays subtitle-free (Round 48 §4).

---

## Built as drawn — do not "fix"

- The four states: skeleton cards, "Saved items didn't load" with its retry,
  "Nothing saved yet" with **Browse services**, and the two sections.
- The rollback sentence, "Couldn't remove — restored. Check your connection.",
  used for every refused unsave. A refused save reads "Couldn't save — check
  your connection."
- "Removed from saved" after an unsave on this screen.
- The heart on Explore's title row opens Saved. It is a button, not a toggle.
