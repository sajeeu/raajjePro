# Round 41 — corrections

Seven small fixes found while importing Rounds 38–40. Item 1 is the one that
matters most; the rest are cleanup that has been accumulating.

**Leave alone:** every layout, colour, component and animation. This round removes
things and rewords copy. It adds no new UI, no new behaviour and no new screens.
Do not revisit the motion work from Round 40 — it landed correctly.

---

## 1. A verification badge must never appear next to a customer

**Screens: `Booking Request`, `Payment Received`.**

On `Booking Request` the provider is reviewing an incoming request, and the person
shown is the customer — Aishath. She currently renders with a **Bronze** badge
beside her name. On `Payment Received` the provider is confirming money arrived,
and the counterparty there carries a **Bronze** badge too.

Both are wrong, and not just visually. `verificationTier` is an attribute of the
**provider profile**. It means "ID and trade checked by RaajjePro" — a trade check
only exists for someone selling a trade. A customer has no tier, so a badge beside
a customer's name claims a check that never happened, and invents a trust signal
the product does not produce.

**Do:** remove the `VerificationBadge` mount from both screens. Nothing replaces it.
The customer's name and avatar stand alone.

Keep `Full name appears once you accept` on `Booking Request` exactly as it is — that
one is right, and it is the correct kind of statement about a customer.

**The rule, so it does not come back:** a badge renders only where the subject is a
provider. On a provider-side screen the subject is the customer, so there is no badge.
`VerificationBadge` cannot enforce this itself — it renders whatever tier it is
handed — so it is the mounting screen's job.

Screens where a badge **is** correct, for contrast, all of which show a provider and
none of which should change: `Service Preview`, `Provider Profile`, `Discovery`,
`My Services`, `Verification`, `Billing`, `My Bookings`, `Booking Detail`,
`Quote Received`, `Pick a Time`, `Request a Time`, `Book Again`, `Rate This Job`,
`Did This Happen`, `Enquiry Thread`, `Booking Thread`.

### 1b. While you are in `Payment Received`

The counterparty is named **Mariyam Shifa**, who is a provider persona elsewhere in
the seed — she is the cleaner on `Home Deep Cleaning`. On a screen where the provider
confirms a customer's payment, the counterparty has to be a customer. Rename her to
**Aishath Naeema**, the customer persona, and set the avatar initials to `AN`.

---

## 2. Never print an island total

**Screens: `Home`, `Discovery` is already clean, `Emergency Flow`, `Become a Provider`,
`Create Service`, `Saved Preferences`.**

Each island picker closes with:

> Sample list — the live app has all 192 inhabited islands

Drop the number. Use exactly:

> Sample list — the live app has every inhabited island

A printed count is wrong the moment the register is revised, and the picker is a
search rather than a browsable list, so its size was never the reader's problem.
This was decided in Round 30 and the count survived anyway.

---

## 3. Remove the Emergency quick-filter chip

**Screen: `Home`.**

The chip row under the search field reads `Near me · Available today · Book instantly ·
Emergency`. Remove the **Emergency** chip and leave the other three.

Round 23 removed the emergency search filter outright: dispatch broadcasts to every
eligible provider and never targets one, so filtering a browse list by emergency
offers a cut that does not exist. Emergency has its own entry, which `Home` already
carries directly above this row — *"Something urgent? Get help now"*.

Do not touch that entry, and do not add a replacement chip.

---

## 4. `Report this listing` goes nowhere

**Screen: `Service Preview`.**

`report` is `() => {}`, and it is wired to two controls — the flag icon in the photo
header and the text button at the foot of the page. `Report.dc.html` exists.

Point both at `Report.dc.html`. A dead end on a moderation path is worse than a dead
end anywhere else, because the person tapping it is already unhappy.

---

## 5. Drop the dead `on-tap` handlers on `BottomNav`

**Screens: `Discovery`, `Messages`, `Profile`, `My Bookings`, `My Services`.**

Since Round 38 the tab-to-screen mapping lives inside `BottomNav`, which navigates on
its own. These five still pass an `on-tap` handler, and `My Services` defines `navTab`
and never passes it at all.

`Discovery`'s is actively wrong — it toasts *"Opens Home"* and then the component
navigates anyway, so a stray toast flashes on the way out.

**Do:** remove the `on-tap` attribute from every `BottomNav` mount on those screens,
and delete the now-unused `navTap` / `navTab` functions. Keep `role` and `active`.

---

## 6. `Messages` shows the same threads to both roles

**Screen: `Messages`.**

The bar is role-aware — no `role` prop, so it resolves from `RPSession` — but the
thread list is fixed. Signed in as the provider you get a conversation with **Ibrahim
Rasheed**, who is you.

**Do:** branch the list on `RPSession.role()`, the way `Booking Thread` already
branches its menu and `Profile` branches its rows.

- **customer** — keep the two threads exactly as they are.
- **provider** — same two rows, same kinds, same times and same unread state, but the
  counterparties are customers: `Aishath Naeema` (`AN`) on the enquiry, and
  `Ibrahim Waheed` (`IW`) on the booking. Keep the listing names as they are, since
  those are the provider's own listings.

Reuse the avatar colours already in the file. No new UI.

### 6b. Same gap in `Booking Thread`

Its header always shows **Mariyam Shifa** with her Silver badge, even when the
provider is the one viewing. Branch the header the same way: for the provider, show
the customer — `Aishath Naeema`, initials `AN`, and **no badge**, per item 1.

---

## 7. Reword the emergency panel heading on a listing

**Screen: `Service Preview`.**

On a plumbing listing the emergency panel is headed:

> Emergency call-out also available

Change it to:

> Need this urgently?

Keep the panel, the icon, the arrow through to `Emergency Flow`, and the sub-copy
exactly as written — the sub-copy is already honest about the mechanism, saying offers
arrive from several providers with their own callout fees and arrival estimates.

The heading is the problem: sitting on Ibrahim's listing it reads as *Ibrahim* being
available for emergency, which is the confusion Round 23 removed from cards. Nobody is
dispatched by name.

---

## Checklist

Confirm each before finishing:

- [ ] `Booking Request` and `Payment Received` have no `VerificationBadge` mount
- [ ] `Payment Received`'s counterparty is Aishath Naeema / `AN`
- [ ] No screen contains the string `192`
- [ ] `Home`'s chip row has three chips and no Emergency
- [ ] `Service Preview`'s two report controls both reach `Report.dc.html`
- [ ] No `BottomNav` mount passes `on-tap`; `navTap` / `navTab` are gone
- [ ] `Messages` and `Booking Thread` show customers to the provider, with no badge
- [ ] `Service Preview`'s emergency heading reads "Need this urgently?"
- [ ] Nothing in Round 40's motion work changed
