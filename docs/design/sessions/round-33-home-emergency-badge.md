# Round 33 — one badge on Home that Round 23 deleted

Round 32 landed correctly: `Discovery` carries all 192 islands, the other five pickers say they are showing a sample, `Booking Request` reads `Dh. Meedhoo · harbour jetty`, and `Components` no longer passes a prop that does not exist.

One change. It is small, it has been live a long time, and it contradicts a decision the plan states in capitals.

## `Home` renders an `Emergency available` badge on service cards

`Home.dc.html` has its own inline card markup rather than mounting `ServiceCard`, and inside it, twice:

```html
<sc-if value="{{ s.emg }}"><span style="…background:#FEF3DC;color:#A15C00;…">Emergency available</span></sc-if>
```

Two of the eight demo services set `emg: true` — `Emergency Plumbing & Pipe Repair` and `AC Servicing & Gas Refill` — so the badge **renders on screen right now**, in both the horizontal run and the full-width list.

**Round 23 deleted this marker.** The reason is not cosmetic: an emergency request **broadcasts to every eligible provider at once**. It is never aimed at the provider whose card you are reading. A badge on a card advertises an action the product cannot perform — you cannot summon *that* plumber — and someone in a burst-pipe situation is the worst person to mislead.

It was removed from `ServiceCard` at the time. `Home`'s own copy of the card was missed, and it has been showing ever since.

**Remove it:**

- Delete both `<sc-if value="{{ s.emg }}">…</sc-if>` badge blocks.
- Delete the `emg` field from all eight rows of the service data, and `emg: s.emg` from the mapped object in `renderVals`. Leave nothing behind for it to read.
- **Nothing replaces it.** The card's second signal is already correct — next open time for `instant`, measured reply time (or `New provider`) for `request`. That is the whole signal set.
- The emergency entry on Home stays exactly as it is: the compact single-line row, small red bolt, `Something urgent? Get help now`, above the fold. That is how emergency is reached, and it is right.

Do not reintroduce an emergency filter, an emergency chip, or an "available for emergencies" line in a provider's copy anywhere.

---

## Leave alone

- Everything from Round 32 — the 192-island list in `Discovery`, the sample line on the other five, the atoll-prefix labels, `Dh. Meedhoo` on `Booking Request`, `Th. Guraidhoo` on the `Components` card
- `searchIslands` in all six screens
- `Home`'s emergency entry row, its category tiles, its section runs and every other card signal
- `Home`'s `Appliance & Computer Repair` listing title. The **category** is `Appliance Repair`, which is correct; the provider's own service name mentioning computers is fine, since Round 25 broadened that category to household appliances and devices
