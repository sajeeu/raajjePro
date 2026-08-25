# Session 3 corrections, round 2 — Service Preview

All six corrections from the last round landed correctly. The second listing you
built rather than just deleting the prop was the right call, and forcing it into
request mode because it is range-priced is exactly right — a range is advertising,
never a bookable amount.

Three changes. Two are content, one is a prop-coupling fix.

---

## 1. The same range rule is broken on the Cleaning listing — material

You enforced it for plumbing (`instant = plumb ? false : ...`) but `priceKind` and
`mode` are still independent props for cleaning. So this combination is reachable:

> **From MVR 350** · Starting price
> ⚡ **Book instantly** — Pick one of Mariyam's published times
> `[ Book now ]`

That tells a customer they can book at a starting price. `range` and `on_request`
listings can only ever be request-based, for the same reason you already applied to
Ibrahim's listing.

Couple the props: when `priceKind` is `range` or `on_request`, force request mode
regardless of what `mode` is set to — mode block, CTA label and footer all follow.
`flat`, `hourly` and `daily` keep honouring the `mode` prop as they do now.

## 2. "licensed for mains and pump work" has no field to live in

A listing carries exactly two self-declared claims: **warranty**
(`warrantyOffered` / `warrantyTermsText`) and **insurance** (`insuranceDeclared` /
`insuranceDetailText`). There is no licence field, so this line cannot be built.

It is also the riskiest of the three claims to imply. Gold's own badge copy reads
"ID checked, registered trade" — a licence claim directly beneath a Gold badge
invites the customer to read the platform as having checked the licence. The
disclaimer underneath helps, but the field still has to exist.

Change Ibrahim's second statement to an insurance one, so it maps to the field that
exists and mirrors the cleaning listing's shape:

```
stated:['6-month warranty on fitted parts', 'public liability insurance held']
```

Keep the first statement as it is — a warranty on fitted parts is exactly what
`warrantyTermsText` is for.

## 3. The unavailable state still says "cleaning"

`action-label="Browse cleaning services"` is hardcoded while the listing can now be
plumbing. Make it follow the selected listing — **"Browse cleaning services"** /
**"Browse plumbing services"** — or make it category-neutral: **"Browse services"**.
Either is fine; the neutral version is one less thing to keep in sync.

---

## Leave alone

- Everything from the last round. All six corrections are correct.
- The whole `emergency_plumbing` listing — Ibrahim at Gold on Plumbing is the right
  provider on the right category, and his numbers match Provider Profile and
  Discovery. The FAQ answer "The fee is set per job and stated in the offer before
  you accept" is a precise description of how the callout fee actually works.
- `emerg: plumb && !!p.emergencyPath`.
- The mode-appropriate `provLine`.
- The callback guarantee card and the "From the provider" card, and the separation
  between them.

## Not for this session — a note for later

Plumbing's category colour (`#ECFDF5` background, `#059669` text) is the same pair
as the callback guarantee card. Green currently means both "this is the Plumbing
category" and "RaajjePro stands behind this." That came from Discovery, not from
this screen, so do not change it here — it needs deciding once, across every screen
at the same time.
