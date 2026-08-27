Three corrections. Both artboards are strong — the draft-card fix landed, the availability screen's three layers work, and the cross-listing reserved case is handled better than the brief asked for. **Change only these three things.**

## 1. `Availability` — the ordinary Reserved slot never renders

`RESERVED` defines two booked times:

```
'd1-11:00' → Aminath S. · Home Deep Cleaning · #4812
'd2-09:00' → Hussain M. · AC Service & Repair · #4821  (other listing)
```

`d1` is **Friday 28 Aug**, and no weekly rule covers Friday — rule 1 is Mon–Thu, rule 2 is Sat. So Friday generates no times at all, and `d1-11:00` never appears. The only Reserved chip that renders in the whole preview is `d2-09:00` — the *other-listing* edge case.

That inverts the lesson. A provider opening this screen sees exactly one booked time and it belongs to a different listing, which reads as though that were the normal case. The legend advertises a state the preview barely shows.

**Move the same-listing reservation onto a day the rules actually cover** — `d0-11:00` (Today, Thu 27 Aug) or `d4-11:00` (Mon 31 Aug). Keep `d2-09:00` exactly as it is, cross-listing copy and all; it is the best thing on the screen. The goal is both cases visible at once: an ordinary booking on this listing, and one held by another listing.

Friday having no times is correct — it is the Maldivian weekend, and `No rule covers Fri` is the right thing to show. Don't change the rules.

## 2. `Availability` — no exception ever overlaps the preview

The exceptions are `Ramadan hours · 18 Feb – 19 Mar` and `Malé trip · 4 – 6 Sep`; the preview shows **27–31 Aug**. Every preset added from the sheet lands in Sep, Oct or Nov. So the section promises that exceptions remove times, and the preview never shows a single time being removed.

Layer 3 is the one layer whose effect is invisible. **Give at least one exception a range that overlaps the five days shown** — a trip across `30 – 31 Aug` would empty Mon 31 Aug — and let the affected day say why it is empty (`Malé trip · no times`), distinct from `No rule covers Sun`. A provider needs to see the difference between "I don't work Sundays" and "I'm away".

## 3. `My Services` — the Published count contradicts the card

`liveCount` filters `status === 'published' && !hidden && x.live` and is labelled **Published**. But a card's status reads `Published` whenever it is not a draft and not hidden — pausing does not change it, and it shouldn't.

So pausing Home Deep Cleaning leaves the card reading `Published` while the stat drops 2 → 1. Two numbers on one screen disagreeing about the same listing is the kind of thing that makes a provider stop trusting the rest of the figures.

**Drop `&& x.live` from that count.** Paused is still published — it is temporarily hidden from customers, not unpublished. Hidden-over-limit staying out of the count is right, because those cards read `Hidden` and agree with it.

---

## Leave everything else as it is

- The draft card's `Finish & publish` in place of a Live toggle, and the toggle on published cards only
- `VerificationBadge` imported with the badge-is-not-payment line; listing states styled inline rather than pressed into `StatusPill`
- The per-card menu, including `Continue editing` for a draft and no `View as customer` on one
- The delete sheet's wording — removed from your services, history and reviews stay
- The over-limit card: the 1-live-service explanation, Upgrade, and `Make this one live instead`
- The drafts-only note about not appearing in search until something is published
- On `Availability`: the listing-scoped header, three slot states and nothing more, the unsaved-preview banner with its delta line, `Times someone has already booked stay exactly as they are` at the moment of saving, the 60-day rolling horizon through Mon 26 Oct, and the reserved-time sheet routing to the booking rather than offering to free the time
- The AC card's hatched placeholder instead of a hotlinked photo. If you would rather it looked finished, upload an AC photo to the project and reference it by filename — never link to a remote image
