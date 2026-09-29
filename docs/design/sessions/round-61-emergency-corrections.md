# Round 61 — corrections to the emergency screens

Raised while building **§Phase 17.3** (emergency dispatch, offer collection and
the contact reveal). It covers four prototypes:

- `Emergency Flow.dc.html`
- `Provider Emergency.dc.html`
- `Reveal Contact.dc.html`
- `Dispatch Fee.dc.html`

`verify-dc.py` passes on all four. Everything below is what a structural check
cannot see.

Four of the corrections follow from decisions the owner made on 2026-09-28,
recorded in `docs/decisions/30-phase-17-3-emergency.md` §9. The rest are
copy that promises something the product does not do.

**Change only what is named.** Everything else on these four screens is correct
and was implemented as drawn. That includes the 90-second collection
countdown, the five-minute choice, the "MVR 200 only if you pick someone"
disclosure, the "No one accepted in time — nothing has been charged" state, the
kill-switch "paused" state, and "submitting lifts the hold now".

---

## 1. Provider Emergency — a pass does not count against the provider

The decline sheet reads:

> Declining is counted in your acceptance rate — letting it lapse is not.
> Either way, no one is told you passed.

**The first sentence is wrong** (owner's decision, 2026-09-28).

- A pass on a broadcast is **recorded**. It takes the request off that
  provider's list and out of any re-broadcast of it.
- It is **excluded from §1f's acceptance rate**. That rate was written for
  bookings a provider was targeted with, and a broadcast reaches everyone
  eligible whether they wanted it or not.

**Replace the sheet body with:** "It comes off your list and nobody is told you
passed. It doesn't count against your record."

**Rename the control** from "Decline this request" to **"Pass on this
request"**. "Decline" is a booking state with a meaning in §1f, and this is not
it. Keep "No one is told you passed" as it is.

## 2. Every distance — "1.2 km", "0.8 km away", "{dist} from you" — has no source

Distances appear in three places:

- `Emergency Flow`: the offer rows, and the "on the way" card's "· 1.2 km away".
- `Provider Emergency`: the request card's "1.2 km from you", and the chosen
  state's "· 1.2 km from you".

The schema has no latitude, longitude or coordinate of any kind. The system
knows islands and nothing finer, so a distance cannot be computed from anything
that exists (owner's decision, 2026-09-28).

**Render the island instead:** "Works on Kulhudhuffushi" on an offer, and
"Kulhudhuffushi" on the provider's request card.

Every provider a broadcast reaches already serves the job's island, so this is
honest without being a comparison. **Drop distance as a comparison dimension**
on the offer row, keeping tier, fee and arrival estimate. Remove the "near you"
wording in the same pass: "Goes to every Gold-verified Plumbing provider **on
your island**", not "near you".

## 3. Emergency Flow — the three offers are the server's, in the server's order

The prototype sorts nothing: it shows the first three offers to arrive.

The owner's decision is that **every eligible provider may offer** during the
90 seconds, and the customer is shown **three**. §1c: "the first acceptance
opens a 90-second collection window during which every other eligible provider
may also accept". "Up to three" caps what is shown, not who may bid.

The three are ranked by:

1. callout fee, lowest first;
2. then the provider's own arrival estimate, soonest first;
3. then the earlier offer.

**Two changes:**

- **Render the rows in the order given.** Do not re-sort by arrival.
- When more than three answered, **add one line above the rows:** "5 providers
  answered — these are the 3 with the lowest callout fee, then the soonest
  arrival."

The "Soonest / Lowest fee / Highest tier" chips are right and stay.

## 4. Emergency Flow — "Turn into a scheduled request" cannot go to Request a Time

After "No one accepted in time", the scheduled-request button jumps to
`Request a Time.dc.html`. That screen is a request against **one provider's
listing**.

An emergency is raised by trade and island and names no provider (owner's
decision; Round 23: "dispatch never targets a provider"), so there is no
listing to request against. **Route it to discovery** — Explore, filtered to the
same trade — where the customer picks a provider and sends a scheduled request
from their listing.

The button label can stay. The body copy "Your description and address carry
over" should go: nothing can carry over into a listing that has not been chosen
yet.

The same applies to "Not urgent? Book normally" / "Make a normal booking
instead" on the form and the limit screen. Both go to discovery, not to
`Request a Time`.

## 5. Emergency Flow — the reject-all sheet understates what rejecting does

> These offers may be withdrawn once rejected.

Rejected providers are **never asked about this request again**. §Phase 17
item 4: "every provider who offered is added to `rejectedProviderIds`".
"May be withdrawn" suggests the offers might come back.

**Replace with:** "These providers won't be asked again." Keep the rest: "Your
request stays live for {time} and new offers can still arrive — but none are
guaranteed. Nothing has been charged."

## 6. Dispatch Fee — a PDF receipt cannot be uploaded

> Add your transfer receipt — A photo or PDF from your banking app

The proof upload is §Phase 8a's, and it accepts **images only** (JPEG, PNG,
WebP). It reads the bytes back, sniffs their type and strips their EXIF. A PDF
is refused.

**Replace with:** "A photo or screenshot from your banking app." The same
wording is already on `Pay by Bank Transfer`.

## 7. Emergency Flow — ratings are sample data until reviews exist

The offer rows show "4.6", "4.9" and "4.4". Reviews are §Phase 11, which is not
built. Until it is, the app renders **"No ratings yet"** rather than a number
nobody earned.

This is expected for a prototype, and **nothing needs redrawing now**. Draw the
no-rating state beside the rated one, so both exist when §Phase 11 lands.

## 8. Reveal Contact — "Call" is not wired yet

The revealed number carries a **Call** button. The app has no dialler
integration yet, so the build shows the number as selectable text with a
**Copy** button.

This is a build gap, not a design defect, and nothing needs redrawing. The copy
around it is exactly right and was implemented verbatim: "confirmed by an admin
when Ibrahim was verified as a provider. It isn't checked live."

---

## What the audit confirmed as correct

| Finding | Disposition |
|---|---|
| Category tiles carry Gold · 30 / Silver · 30, Moving included | ✅ matches the seed and Round 22 |
| Moving's arrival presets 60/90/120/180, the rest 15/30/45/60 | ✅ matches `emergencyEtaPresetsMinutes` |
| No arrival preset preselected; the send is blocked without one | ✅ Round 22 |
| "This is a bid, not a race … answering first doesn't win it" | ✅ Round 15 |
| Offline: "You're offline. Emergency jobs need a live connection…" with a retry | ✅ §0.0 item 14 — never queued |
| The island picker is a search sheet, not a `<select>` | ✅ invariant 15 |
| "Exact address is shared if the customer picks you" | ✅ implemented — the broadcast carries no address |
| Reveal: six conditions listed, "both ways", "on the record", expiry and paused states | ✅ §1c's seven, the kill switch separate |
| Dispatch fee: "the platform's own account — never a provider's"; "lifts the hold now" | ✅ §1c |
