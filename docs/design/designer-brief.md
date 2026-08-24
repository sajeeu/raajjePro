# Design brief — RaajjePro mobile app · content only

A brief for designing every page of the app, one page at a time. This document says nothing about how any page should be designed — no layout, no ordering, no hierarchy, no components, no colours. Each page section states what the page is about and what fields and data must be present. Everything else is the designer's.

The visual language is not in this file. It is the language defined in `frontend/CLAUDE.md` (§ Design tokens), the seventeen delivered screens in `mockups/`, and the reference prototype `mockups/design-composer/Become a Provider.dc.html` — which is a working prototype, not a picture, and is the highest-fidelity reference in the repository. Where an original mockup image and `mockups/round-16-redraws.html` disagree, the redraw wins.

Every page brief follows the same format: what it is, then the required fields and data. Pages marked **PRIORITY** are wanted first.

## The app, in one paragraph

A mobile app for finding and booking local services in the Maldives — plumbers, cleaners, electricians, photographers, boat charters. A customer browses, books, and pays the provider directly. A provider publishes services, accepts or declines each booking, and pays RaajjePro a monthly subscription. Payment for the job itself never touches RaajjePro. Customer and provider never exchange phone numbers, with one narrowly-scoped emergency exception. The two roles live in one app and a person can be both, switching between them. Portrait phone app, and **the connection is unreliable** — this is an atoll country and the app is designed for it.

---

## Data facts that hold on every page

- Every value in this document is fixed data. Use it verbatim; invent no figure that is not here. Rows marked *(illustrative)* stand for "any record in this state" — their state is required, their figures are examples.
- **Currency is code-first: `MVR 450`.** Decimals appear only when a value has them (`MVR 1,250.50`, but `MVR 450`). Never a decimal point on a whole number, never a currency symbol.
- **There are twelve categories**, no more and no fewer: `Cleaning` · `Plumbing` · `Electrical` · `AC Repair` · `Beauty` · `Photography` · `Gardening` · `Computer` · `Moving` · `Fitness` · `Events` · `Boat Charter`. There is no Tuition category. Any grid showing categories shows twelve.
- **Every service is one of two booking modes**, and every card, result and listing must say which: **`slot`** — the customer picks a published time — labelled `Book instantly`; **`request`** — the customer proposes a window and the provider comes back with a time and a price — labelled `Request a time`.
- **A card carries a second signal, matched to its mode**: `slot` shows the next open time (`Next: today 14:00`), `request` shows the provider's typical reply time (`Usually replies in 12 min`, or `New provider` below ten bookings). Both are measured numbers, never labels.
- **There is no `Emergency available` marker on a card, and no emergency filter.** Emergency dispatch goes to every eligible provider at once, so it can never be aimed at the one whose card you are reading. Emergency is reached from its own entry on Home and Explore.
- **Verification is three tiers**, and the badge carries its own words: `Bronze` — `ID checked by RaajjePro` · `Silver` — `ID checked, work verified` · `Gold` — `ID checked, registered trade`. A provider may have no tier at all and still be fully listed and bookable. **Never render a bare "Verified"** — a customer reads that as "has a good track record" rather than "passed an ID check".
- **The system's status values.** Booking: `requested`, `awaiting_quote`, `quote_offered`, `emergency_offered`, `accepted`, `awaiting_payment`, `payment_claimed`, `payment_unresolved`, `confirmed`, `completed`, `declined`, `cancelled`, `disputed`, `dispute_resolved`. Listing: `draft`, `published`, and separately visible or hidden. Subscription: `trialing`, `active`, `free`, `paused`, `expired`. These are the underlying data. How they are labelled on screen is the designer's choice; **every status must be distinguishable by its label, not colour alone.**
- **Money the platform takes:** a provider subscription (`MVR 150` per month standard, `MVR 75` for the first 100 providers) and the `MVR 200` emergency dispatch fee charged to a customer. Nothing else. No page may gate any other customer action behind a payment.
- **Money the platform never touches:** what a customer pays a provider for the job. Every page that mentions it says so.

### People

A fixed cast. Use these names; invent no others.

- `Aishath Nazim` — Customer · Malé
- `Ibrahim Rasheed` — Provider · `Rasheed Plumbing Services` · business · Plumbing · **Gold**
- `Mariyam Shifa` — Provider · individual · Cleaning · **Silver**
- `Hassan Waheed` — Provider · Electrical · **Gold**
- `Ahmed Shakir` — Provider · AC Repair · **Silver**

### Services

- `Home Deep Cleaning` — Cleaning — `Mariyam Shifa` — `MVR 450/session` — **Book instantly**
- `Emergency Plumbing & Pipe Repair` — Plumbing — `Ibrahim Rasheed` — `From MVR 350` — **Request a time** · **Emergency available**
- `AC Servicing & Gas Refill` — AC Repair — `Ahmed Shakir` — `MVR 600/visit` — **Request a time** · **Emergency available**

### Islands

`Malé` · `Hulhumalé` · `Villimalé` · `Maafushi` · `Thulusdhoo` · `Hithadhoo`. *(Illustrative — the real seed list is not yet finalised. Design for a searchable list of a few hundred, not a dropdown of six.)*

### The rules that never bend

Break any of these and the page is wrong regardless of how it looks.

1. **No page shows a phone number to another user.** Not on a profile, not on a listing, not on a booking, not in search. The single exception is the emergency contact reveal, which has its own page brief in this document and appears nowhere else.
2. **A phone number is never shown with a check mark and never described as verified.** Nothing proves a number belongs to whoever typed it.
3. **Payment is a self-attestation between two people, never a platform confirmation.** Use `I've Paid` and `Provider confirmed receipt`. **Never** `Payment verified`, never a lock, never a certainty check mark on this flow.
4. **Provider conduct is numbers only.** `94% on time · 3% cancelled · usually responds in 12 minutes · 47 jobs completed`. **Never** a system-generated label like "Prone to cancel" or "Price hiking", and never a euphemism for one. Show the numbers; let the customer conclude.
5. **A provider's warranty and insurance are claims, not facts.** Render as `Provider states: 90-day workmanship warranty`. Never a check mark, a shield, a lock, or the word *verified* on either. Never in the same visual treatment as the callback guarantee, which is a promise RaajjePro actually enforces.
6. **Nothing in the app is encrypted end-to-end and no page may say it is.** Chat is readable by an admin during a dispute. The honest claim is `Private messaging — your contact details are never shared`.
7. **Every screen has four states**: loading, empty, error, populated. An empty state names what to do next; it never merely reports that nothing is there.

---

# Shared & system

## Sign in — PRIORITY

Sign in to an existing account.

*A mockup exists: `mockups/Login.jpg`. It was audited and needed no correction.*

- Product name: `RaajjePro`
- Email field — example `aishath@example.mv`
- Password field, obscured, with a reveal
- A sign-in action
- A forgot-password route
- A create-account route
- Third-party sign-in: `Apple`, `Google`, `Facebook`, `Viber`. **Apple must be present** wherever any other third-party sign-in is offered
- Failure data: a wrong email or password produces one message that does not say which was wrong; entered values are kept
- Fact: a guest can browse, search and view everything without signing in — signing in is for saving, booking and messaging

## Create account — Find Services

Register as a customer.

*A mockup exists: `mockups/Register_customer.jpg`.*

- Full name, email, phone, password
- Phone: dial code defaulting to `+960`, accepting **6–15 digits**. Foreign numbers are valid — resort guests and expatriate residents are real customers
- Fact: an email already in use is **blocked at the email field**, naming it, with a route to sign in or reset the password
- Fact: a phone number already in use is blocked **only if it belongs to a verified provider**; otherwise it is accepted. An unverified number may be held by several accounts
- Terms and privacy acceptance
- A create-account action, leading to email verification

## Create account — Offer Services

Register as a provider. Identical to the customer variant plus one field.

*A mockup exists: `mockups/Register_serviceProvider.jpg`.*

- Everything from the customer variant
- **Business or trade name** — the additional field, and the only difference
- Fact: registering here does not make someone a provider. It creates an account; the Become a Provider flow is what sets them up

## Verify your email — PRIORITY

A code was emailed. Enter it.

- Fact: the code went to **email**, and the address is shown — e.g. `aishath@example.mv`
- Fact: **there is no SMS in this system**. Nothing anywhere may offer to send a code by text
- A 6-digit code entry
- A resend action with a real countdown
- Rate-limit data, stated as a wait rather than a generic error: `3` sends per address per `15 minutes`, `5` per account per hour, `5` attempts per code before it is invalidated
- Fact that must be conveyed: booking, enquiring and messaging need a verified email; browsing does not
- A way to correct the email address

## Forgot password

Request a reset link by email.

*A mockup exists: `mockups/ForgotPassword.jpg`.*

- Email field
- A send action
- Fact: the link expires in `30 minutes`
- The confirmation is identical whether or not the address is registered. The page must never reveal whether an email exists

## Check your inbox

Confirmation that a reset email was sent.

- The address it went to
- A resend action with a countdown
- A route back to sign in

## Set a new password

Choose a new password from a valid reset link.

- New password, confirm password, both obscured with a reveal
- Password requirements stated before submission, not only on failure
- Fact that must be conveyed: signing in again will be needed **on every device** — all other sessions end
- Expired-link data: the link has expired, with a route to request a new one

## Session expired

Shown when the server stops accepting the session.

- A sign-in-again action
- Fact: whatever was being typed is kept and restored after signing in
- Nothing on this page may claim work was lost

## No connection

The device has no network.

- Message: `No internet connection.`
- A retry action
- Fact that must be conveyed, and this is the important one: **three things keep working offline and send when the connection returns** — saving a step of the service wizard, accepting a booking, and sending a message. Each shows a pending state
- Nothing may claim a booking was made or a payment recorded while offline

## Notifications

What happened that concerns the signed-in person.

- Unread count: `3`
- Entries, each with event, detail and age:
  - `Booking accepted` — `Home Deep Cleaning · Mariyam Shifa` — `2h`
  - `Payment confirmed` — `Ibrahim Rasheed confirmed receipt` — `1d`
  - `New message` — `Ibrahim Rasheed` — `1d`
- Unread entries distinguishable from read ones
- Fact: booking notifications cannot be switched off in the app — they are transactional. Marketing and the weekly digest are opt-in and separate
- Empty state data: `Nothing new.`

## Profile — customer

The customer's own account.

*A mockup exists: `mockups/Profile_customer.jpg`.*

- Name `Aishath Nazim`, photo, member since `Jan 2026`
- Counts: saved `7` · bookings `12`
- Rows to: My bookings · Saved · Saved preferences · Account settings · Help & support · Legal
- A route into provider mode
- A sign-out action

## Role switcher

The pivot between customer mode and provider mode. One person can be both.

- The two modes, named, with the current one evident
- Fact: switching to provider mode **for the first time** opens the Become a Provider flow, not a dashboard
- Fact: a provider who has already set up goes straight to My Services
- Fact: switching is instant and reversible; nothing is lost either way

## Account settings

Everything about the account itself.

- Rows: `Change password` · `Change email` · `Change phone` · `Active sessions` · `Saved preferences` · `Download my data` · `Delete account`
- Each of email and phone re-verifies on change
- **Active sessions:** one entry per device, each with device name, last-used age, and current-device marker; revoke per device — `iPhone 14 · Malé · active now` · `Pixel 7 · 3 days ago` *(illustrative)*
- **Download my data:** what it contains, and that it arrives as a file
- **Delete account** — the one that needs care in the words, not the layout:
  - Fact: the request is **accepted immediately** and never refused, even with bookings open
  - Fact: the account is frozen at once — no new bookings, no new listings, hidden from search
  - Fact: deletion completes once open bookings finish, and **within `30 days` regardless**
  - Fact: reviews already written stay, with the name removed
  - Fact: identity documents are deleted outright, not anonymised
  - A confirm action that is hard to hit by accident

## Saved preferences

Details reused by every booking, so a repeat booking is one screen.

- **Saved addresses**, each with a label and the island: `Home · Malé` · `Office · Hulhumalé` *(illustrative)*
- **Preferred time windows**: `Weekday mornings` *(illustrative)*
- **Standing instructions**, free text: `Gate code 4471. Please call from the lobby.` *(illustrative)*
- Add, edit and remove for each
- Fact: these pre-fill a booking and are always editable there

## Help & support

The route to a human, reachable in one tap from any failure.

- A searchable FAQ
- A contact form: subject, message, and the ability to attach a screenshot
- Fact: a submission becomes a tracked case with a reference, not an email into a void
- A **product feedback** entry, distinct and clearly labelled as feedback about RaajjePro — not a provider review
- Fact: feedback about the app never appears on any provider's profile

## Legal

Terms, policies, and the platform's own position.

- Rows: `Terms of Service` · `Privacy Policy` · `Provider Agreement` · `Trust & Safety`
- Each opens a readable scrolling document with a last-updated date
- Fact that must be conveyed on Trust & Safety: RaajjePro is a **marketplace**, not the supplier of the work
- **Design against placeholder text.** The legal wording is not written yet and must be visibly marked as a placeholder — never mocked up as though it were final

---

# Customer — finding a service

## Home — PRIORITY

The customer's landing screen. Where a customer who does not yet know what they want ends up.

*A mockup exists: `mockups/HomePage1.jpg` and `mockups/HomePage2.jpg` — one screen, two captures. Two corrections apply, listed below.*

- A location control naming the browsing island: `Malé`, changeable
- Search entry
- The twelve-category grid, or a route to it
- Sections, each a horizontal set of service cards: `Popular near you` · `Featured providers` · `Popular this week` · `Nearby` · `Recently viewed`
- **A service card carries:** cover image, service name, provider name, category, rating with review count, price with its unit, island, verification badge where the provider has one, save control, and **its booking mode** — `Book instantly` or `Request a time`, plus `Emergency available` where it applies
  - `Home Deep Cleaning` — `Mariyam Shifa` — `Cleaning` — `4.8 (24)` — `MVR 450/session` — `Malé` — Silver — **Book instantly**
  - `Emergency Plumbing & Pipe Repair` — `Ibrahim Rasheed` — `Plumbing` — `4.6 (31)` — `From MVR 350` — `Malé` — Gold — **Request a time · Emergency available**
- A **Become a Provider** entry
- **Trust content**, and its wording is corrected data: `Private messaging — your contact details are never shared`. The delivered mockup says "Secure Messaging — Private, encrypted communication within the app", which is **false and must not be reproduced**
- The featured card in the delivered mockup is a Tuition listing. **There is no Tuition category** — replace it

## Home — launch mode

The same screen at launch, when the catalogue is nearly empty. This is the first impression every early user gets.

- Fact: below `50` published services, Home collapses to **two sections plus the category grid**
- The two sections and the grid, rendered convincingly against roughly `20` services
- Fact that must be conveyed: this must not read as a broken or abandoned product. Nine rows over twenty services shows the same three services repeatedly, which is worse than showing fewer

## Explore — categories

The twelve categories.

*A mockup exists: `mockups/Explore_services.jpg`. One correction applies.*

- All twelve, each with a name and an icon: `Cleaning` · `Plumbing` · `Electrical` · `AC Repair` · `Beauty` · `Photography` · `Gardening` · `Computer` · `Moving` · `Fitness` · `Events` · `Boat Charter`
- The delivered mockup shows **Tuition**. Replace it with **Boat Charter** — the grid stays twelve
- Each opens its results
- Fact: the grid is driven by live data. A thirteenth category must appear without a redesign

## Search results — PRIORITY

What matched, and how to narrow it.

- The query, and a result count: `18 services`
- **Sort, in this order:** `Distance` · `Rating` · `Price`. Distance leads — a provider who cannot reach your island is not a result at all
- **Filters:** island, category, price range, booking mode, `Emergency available`, `Maldivian-owned business`
- Result cards carrying everything a Home card carries, **including the booking-mode label on every one**
- Fact: some results are **paid placement, and each one says so** — a visible `Sponsored` label. No unlabelled paid placement anywhere
- Fact that must be conveyed: verification does not affect whether a provider appears in results, only what badge they carry
- Empty data: `No services matched` plus the filters that could be relaxed

## Category results

One category's services. Structurally the same as search results.

- Category name and count: `Plumbing · 6 services`
- The same cards, sort and filters as search
- Empty data: `No plumbers on Malé yet` plus a route to change the island or browse everything

## Service preview — PRIORITY

One service, everything needed to decide to book it. The most important customer page in the app.

*A mockup exists: `mockups/Service-full-post.jpg`. Two corrections apply.*

- Cover image and gallery
- Service name `Home Deep Cleaning` · category `Cleaning` · rating `4.8 (24 reviews)`
- Price `MVR 450/session`, and the price is labelled by how it is calculated — a flat rate, an hourly rate, a daily rate, a **range** (`From MVR 350`), or **price on request**
- **Booking mode, unmissable:** `Book instantly` or `Request a time`. Where emergency applies, it is presented **alongside** the normal path, never instead of it, and states the callout-fee expectation up front
- Provider identity: name, photo, **verification tier with its exact words**, response time, jobs completed
- The delivered mockup shows a single `Verified Provider` badge. **There are three tiers** — Bronze, Silver and Gold must be visually distinct and each carries its own copy
- The delivered mockup's description is about AC installation under a Cleaning listing. **Match the description to the service**
- Description, service areas (islands), what is included
- **Extra information, all optional and all attributed:**
  - `Provider states: 90-day workmanship warranty`
  - `Provider states: public liability insurance held` — or, where an admin has sighted a certificate, `Insurance certificate on file`
  - Neither ever carries a check mark, a shield, or the word verified
- **Callback guarantee**, where offered — `Free return visit within 7 days if the same problem comes back`. This is RaajjePro's promise, not the provider's, and it must be **visually distinct from the warranty above**, which is the provider's
- FAQs
- Reviews: star breakdown, individual reviews, and **tag counts** — `On time (31) · Fair price (28) · Arrived late (3)`
- A **Message** action, opening an enquiry before any booking exists
- A save control
- A **Report** affordance
- Fact: no phone number, no bank details, no contact information of any kind appears on this page

## Provider public profile — PRIORITY

The person or business behind the services. The trust surface.

- Name `Ibrahim Rasheed` · business `Rasheed Plumbing Services` · photo · joined `Mar 2026`
- **Verification tier with its exact copy** — `Gold · ID checked, registered trade`
- `Maldivian-owned business`, where it applies — an attribute of the **business**, shown only at Gold. Never a nationality, never about a person
- Overall rating and review count
- **Conduct metrics — numbers only:**
  - `94% completed` · `3% cancelled` · `2% no-show` · `91% on time` · `97% price honoured` · `usually responds in 12 minutes` · `47 jobs completed`
  - Fact: these cover a rolling `90 days`
  - Fact: **on time** covers emergency work too, measured against the arrival the provider themselves promised when they made the offer — not a time the platform assigned them
  - **Below `10` completed bookings, none of them appear.** Instead: `New provider · 4 jobs completed`. One cancellation out of two bookings is 50% and means nothing
  - Fact that must be conveyed: **no label, no grade, no summary judgement.** The numbers are the whole output
- The provider's published services, as cards
- A save-provider control
- A **Report** affordance
- Not-found data: a provider with nothing published has no public page. Design what a customer sees when they reach that

## Saved

Services and providers the customer kept.

- Two kinds in one place: **saved services** and **saved providers**
- Saved services as cards, identical to Home's
- Saved providers with name, tier and rating
- Unsave from here
- Fact that must be conveyed: saving a provider is how a customer remembers a person — there is no phone number to write down
- Empty data: `Nothing saved yet` plus a route to browse

---

# Customer — booking

Three booking modes. They are genuinely different flows and must not be forced into one shape.

## Book — pick a time — PRIORITY

The **slot** flow. The provider has published times; the customer takes one.

- The service and its price: `Home Deep Cleaning` — `MVR 450/session`
- A date selection, and the open times on the chosen date: `09:00` · `11:00` · `14:00` *(illustrative)*
- Fact that must be conveyed: **only genuinely open, not-yet-passed times are ever shown.** No greyed-out unavailable slots, no times that have already gone by
- Fact: this category needs `3 hours` notice, so today's earliest time reflects that. Lead time varies by category — `1 hour` for Plumbing, `2 days` for Events
- Address: chosen from saved addresses or entered, with the island
- Job notes, free text
- The total, shown before committing: `MVR 450`
- A confirm action
- Fact that must be conveyed: **the provider still has to accept.** Booking a time is a request, not a confirmation
- Race data: a slot taken by someone else in the meantime produces a clear `No longer available`, not a silent failure
- Empty data: a service with no open times — `No times published yet` plus the option to message the provider

## Book — request a time — PRIORITY

The **request** flow. The customer proposes a window; the provider comes back with a concrete time and a price.

- The service: `Emergency Plumbing & Pipe Repair` — `From MVR 350`
- **Preferred window, leading with one-tap choices:** `Tomorrow morning` · `Tomorrow afternoon` · `This week` · `This weekend`, with free text underneath for anything more specific. A blank text box as the primary interaction asks too much
- Job description, free text — what is wrong, what needs doing
- Photos of the problem, optional
- Address and island
- Fact that must be conveyed: **the price is not settled yet.** `From MVR 350` is an estimate; the provider will send a real price
- Fact: the provider has `2 hours` to respond on this category, and the customer then has `4 hours` to accept. On Photography, Gardening, Moving, Events and Boat Charter those become `24 hours` and `72 hours`. **The screen states the real numbers for the category being booked**
- A send action

## Quote received

The provider has come back with a time and a price. The customer accepts or rejects.

- The proposed time: `Tue 25 Aug · 14:00`
- The quoted price: `MVR 650`
- Any note the provider added
- Accept and reject actions
- A countdown on the time left to accept: `3h 42m left`
- Fact that must be conveyed: **the chat is already open.** If the time or the price is nearly right, the customer messages rather than rejecting — this is the moment negotiation happens
- Expiry data: an expired quote states that the time was released, with a route to ask again

## Book — emergency — PRIORITY

The **emergency** flow. Something is broken now.

- Fact that must be conveyed, before anything else: this is for **urgent problems only** and it costs `MVR 200` to dispatch
- Available on Plumbing, Electrical, AC Repair and Moving only
- Job description, free text
- Address and island
- Fact: the request goes to **every qualified provider at once**, not one at a time
- Fact: qualified means the provider carries the tier this category demands — **Gold** for Electrical and Plumbing, **Silver** for AC Repair and Moving
- Fact: the whole window is `30 minutes`, on every emergency category including Moving. A mover answers as fast as a plumber; what takes longer is arriving, and that is stated per offer rather than by stretching the clock
- Fact: **each offer carries the provider's own arrival estimate** — `arrives in ~25 min`. It is the provider's estimate, never a promise the platform is making
- Fact: the `MVR 200` is charged **only when the customer picks a provider**. A request nobody answers costs nothing
- A submit action
- Over-limit data: `3` emergency requests per `24 hours` and `10` per `7 days`. Design the state where a customer has reached that, and give it a route to a normal booking rather than a dead end

## Emergency — waiting

The request is out. Nobody has answered yet.

- A countdown on the overall window: `26:14 remaining`
- How many providers it reached: `Sent to 4 providers`
- **A second state, once the first provider answers:** offers are being collected for `90 seconds` before the customer is shown them. This is a real interval the customer sits through and it needs its own treatment — the first answer has arrived, and waiting a moment longer is what gets them a choice instead of a single take-it-or-leave-it
- What happens next, in plain terms
- A cancel action
- Fact: this screen must not look stalled. Something has to show it is live

## Emergency — offers — PRIORITY

Providers have answered. The customer picks one. This screen does not exist anywhere else in the app and has no precedent to borrow from.

- **Up to three offers, side by side**, each carrying: provider name, **verification tier**, rating, distance, and **callout fee**
  - `Ibrahim Rasheed` — Gold — `4.6` — `1.2 km` — `MVR 350`
  - `Hassan Waheed` — Gold — `4.9` — `2.8 km` — `MVR 450`
  - `Ahmed Shakir` — Silver — `4.4` — `0.8 km` — `MVR 500`
- Accept on each, and a reject-all action
- **Two countdowns, and both matter:** `4:31` to respond to these offers, and `21:06` left on the overall request. The customer must be able to see what rejecting costs them
- Fact that must be conveyed: the callout fee is **what the provider charges to attend**. `The final bill may differ` — parts and labour are settled directly with the provider afterwards
- Fact: accepting incurs the `MVR 200` dispatch fee, payable to RaajjePro afterwards by bank transfer
- Fewer-than-three data: one or two offers is normal and must not read as a failure
- None-arrived data: the request keeps going; new offers can still arrive

## Emergency — nobody came

The window expired with no accepted offer.

- Message: `No one accepted in time`
- Two actions: try again, or turn this into a normal scheduled request
- Fact: nothing has been charged

## Payment step — PRIORITY

The provider accepted. The customer pays them directly.

- The amount, and **what kind of amount it is** — the label changes the meaning and must be exact:
  - `Agreed price` — `MVR 450`
  - `Agreed total — 3 hours at MVR 200/hour` — `MVR 600`
  - `Quoted price` — `MVR 650`
  - `Callout fee — what this provider charges to attend. The final bill may differ.` — `MVR 350`
- **The provider's bank details**: account holder name, bank, account number — with a copy action on the number
- Fact that must be conveyed, unmissably: **RaajjePro is not handling this money.** The transfer goes from the customer to the provider
- An **`I've Paid`** action
- Fact that must be conveyed about that action: it is the customer **saying** they paid. Nothing is checked. **Never `Payment verified`, never a lock, never a certainty check mark**
- Fact: the provider's bank details are the one piece of provider information a customer ever sees — and they are not contact details

## My bookings

Every booking, as a customer.

*A mockup exists: `mockups/Bookings.jpg` — Upcoming, Active and Completed, with its empty state.*

- Filters across the status groups
- Each entry with service, provider, date and time, amount, and **status** — and the status set is long, so every one of these must be legible at a glance: `Waiting for provider` · `Quote received` · `Awaiting payment` · `Payment sent` · `Confirmed` · `Completed` · `Declined` · `Cancelled` · `Disputed` · `Unresolved`
  - `Home Deep Cleaning` — `Mariyam Shifa` — `Tue 25 Aug · 14:00` — `MVR 450` — Confirmed
  - `Emergency Plumbing & Pipe Repair` — `Ibrahim Rasheed` — `today` — `MVR 350` — Awaiting payment *(illustrative)*
- Each opens its detail
- Empty data: `No bookings yet` plus a route to browse

## Booking detail & timeline — PRIORITY

One booking, its whole history, and whatever needs doing next. Everything that can happen to a booking surfaces here.

- Service, provider, date and time, address, job notes
- The amount and its label
- **A status timeline** — every transition, when it happened, and **who caused it**: `Requested · you · 22 Aug 09:14` → `Accepted · Mariyam Shifa · 22 Aug 09:41` → `Payment sent · you · 22 Aug 10:02` → `Provider confirmed receipt · Mariyam Shifa · 22 Aug 10:30`
- **The locked agreement**, stated as such: price, date, time and scope were fixed when the provider accepted, and neither side can change them alone
- **Amendments**, where any exist: what was proposed, by whom, and whether it was accepted — the original terms stay visible alongside
- A route into the **chat**, prominent
- Actions appropriate to the state: cancel, dispute, reschedule, mark complete, rate, **book again**
- **Emergency bookings additionally carry:** a `Provider has not arrived` action once the window has elapsed, and the contact-reveal action described below
- Fact: the chat stays open **after completion** and is never taken away — a follow-up question or a warranty claim still has a thread

## Propose an amendment

Changing an agreed price, date, time or scope. Either party may propose; the other must accept.

- What is being changed, showing **the original and the proposed value side by side**: `MVR 450` → `MVR 600`
- A reason, free text
- Send, and on the receiving side accept or reject
- Fact that must be conveyed: **the original terms are kept either way**, and every attempt is recorded whether it is accepted or not
- Fact: a provider charging more than agreed without an accepted amendment shows up on their public price-adherence number

## Reveal contact — emergency only

The one place in the entire app where a phone number crosses between two people.

- Fact that must be conveyed: this is **emergency bookings only**, and only once the provider has accepted
- Fact: **the reveal is mutual.** Both numbers appear, or neither. The other person is told at the moment it happens
- Fact: the number was **confirmed by RaajjePro when the provider was verified**. It is not live-checked, and the page must not say it is
- A request action, initiated by the customer only
- The two numbers, once revealed
- Fact: access ends `24 hours` after the booking finishes
- Unavailable data: this can be switched off at any time. Design the state where it simply is not available

## Settle the dispatch fee

The `MVR 200` owed to RaajjePro after an emergency dispatch.

- The amount `MVR 200` and what it was for, naming the booking
- RaajjePro's bank details and a **reference code**: `RP-4471-EMG` *(illustrative)*
- Proof of transfer upload
- A submit action
- Fact that must be conveyed: **submitting the proof lifts the block immediately.** The customer does not wait for anyone to check it
- Blocked-state data, shown wherever a new booking is attempted while a fee is owed: new bookings are on hold until this is settled; **existing bookings are unaffected and the account is not suspended**

## Did this happen?

Seven days after the job was scheduled and nobody marked it complete, the customer is asked.

- The question, naming the provider: `Did Mariyam Shifa complete this job?`
- Three outcomes: yes, no, and doing nothing
- Fact: no answer after a further `3 days` closes the booking anyway — a provider cannot block a review forever by staying quiet

## Rate this job

A completed booking, rated.

- Stars, 1 to 5
- **Tags, one tap each, fixed per category, positive and negative:** `On time` · `Fair price` · `Quality materials` · `Good communication` · `Left a mess` · `Arrived late` · `Poor communication` · `Price changed on site`
- Optional written review
- Fact that must be conveyed: **this must be finishable in two taps** — stars, then submit. Everything after the stars is optional. Every extra required field costs a review, and reviews are what make the whole system work
- Fact: a tag only becomes visible on a profile once three different customers have applied it

## Cancel a booking

- Fact: cancelling before payment is straightforward and frees the time
- A reason, where one is asked for
- Fact that must be conveyed on the provider-cancelled side: the customer is **never left with nothing.** A normal booking drops them back into booking with service, date, time and preferences already filled in; an emergency goes back out to other providers **with no second dispatch fee**

## Raise a dispute

Something went wrong with a booking.

- What is being disputed, from a fixed set: `work_not_done` · `price_changed_on_site` · `unsafe_work` · `payment_dispute`
- A description and photos
- Fact that must be conveyed: **RaajjePro cannot adjudicate a payment it never handled.** It can see the agreed terms, the amendment history, the chat and both attestations, and it acts on patterns
- Fact: a dispute after completion is still accepted
- Fact: disputing is not the same as declining, and the two must never look alike

## Report

Reporting content or a person. Reachable from a listing, a review, a profile, a message, a photo.

- The reason, from a fixed set that changes with what is being reported:
  - a listing: `misleading_description` · `wrong_category` · `contact_details_in_listing` · `prohibited_service` · `not_the_real_provider`
  - a review: `fake_review` · `abusive_language` · `not_about_this_service`
  - a person: `harassment` · `impersonation` · `fraud` · `repeated_no_show`
  - a message: `harassment` · `contact_solicitation` · `spam` · `abusive_content`
  - a photo: `not_own_work` · `inappropriate_content` · `contains_contact_details`
- A description
- Fact: reported content is **hidden, never deleted**, and its owner is told the reason and can appeal

## Book again

One completed booking, repeated.

- The service, provider and the previous details, pre-filled
- Fact: it routes to whichever flow that service uses now — pick a time, or request a time
- Saved address, time window and standing instructions carried forward

## Recurring — same time next week

Repeat work at a fixed weekly time. Slot-based services only.

- The service, the provider, and the weekly time: `Home Deep Cleaning · Mariyam Shifa · Tuesdays 14:00`
- Fact that must be conveyed: **each week still needs the provider to accept.** This is a convenience, not a standing authorisation
- A one-tap `Same time next week?`
- Skipped-week data: a week the provider missed is skipped and stated plainly — `This week was not confirmed; your series continues next week`
- Fact: three missed weeks in a row pauses the series and asks the customer to reconfirm
- Cancel one occurrence, or cancel the series — two different things

---

# Messaging

Two kinds of conversation, and they behave differently. Chat is the **only** way a customer and a provider ever communicate — there is no phone call, no WhatsApp, no handover to anything else.

## Conversations

Every thread, both kinds together.

- Each entry with the other person's name, the service or booking it concerns, the last message, age, and unread state
  - `Ibrahim Rasheed` — `Emergency Plumbing & Pipe Repair` — `I'll be there in 20 minutes` — `4m` — unread
  - `Mariyam Shifa` — `Home Deep Cleaning · Tue 25 Aug` — `See you Tuesday` — `2d`
- The two kinds are distinguishable: an **enquiry** about a service, and a **booking** thread
- Empty data: `No messages yet`

## Enquiry thread

A question about a service, before any booking exists.

- The service it concerns, as a header, with a route back to it
- Messages both ways, with timestamps and the sender clear
- Photo attachments
- A composer
- Fact that must be conveyed: **everything is allowed here.** Appliance model numbers, serial numbers, property details, photos of the problem, price questions. This is what the channel is for
- Fact: **the composer carries nothing beyond a send control.** No warning, no reminder, no banner about contact details — none
- A **Report** and a **Block** affordance
- Fact: the customer's email must be verified to send. A route to verify, where it is not
- Read-only data: a thread whose service was taken down stays readable but accepts no new messages, and says why

## Booking thread

Coordination for a live booking. The only channel there is.

- The booking it concerns, with its status and time, and a route to its detail
- Messages, timestamps, photos
- Fact that must be conveyed: this is where the exact address, the gate code, access instructions and arrival updates happen — **there is no other channel**
- Fact: the thread opens when the provider accepts, or when they send a quote, and it **never closes**, including after the job is done
- **Offline behaviour is part of this screen, not a detail:** a message sent with no connection shows a pending state and sends when the connection returns. It is never silently dropped
- Fact: blocking someone does not close a live booking's thread — a scheduled visit still has to be coordinated. Design the notice that explains this

## Block, mute, and decline

Three different actions with three different scopes, and the difference matters.

- **Mute this conversation** — silences one thread and nothing else
- **Block this person** — neither party can message the other or book against them again
- **Decline future bookings from this customer** — provider only; stops new bookings, leaves the conversation intact
- Fact that must be conveyed for each: what it stops, and what it does not
- Fact: a live booking's thread survives all three

---

# Provider — setting up

## Become a provider — intro — PRIORITY

What being a provider on RaajjePro means, before asking for anything.

*A working prototype exists: `mockups/design-composer/Become a Provider.dc.html`. Open it — it runs.*

- The mechanics, in plain terms: publish a service, get bookings, **get paid directly by the customer**, communicate entirely through the app
- Fact that must be conveyed: **RaajjePro never collects or holds a payment for a job**
- Fact: nothing about subscriptions or pricing belongs on this screen. That conversation happens much later
- A continue action
- A **`Not right now`** action that returns cleanly to customer mode, leaving nothing half-finished and no prompt nagging them later

## Become a provider — your details — PRIORITY

The account-level details a provider needs before a service can exist. **Three groups** — an ungrouped list of these fields reads as a wall.

**About you**
- Photo or logo — optional
- Provider or business name — required
- **Individual or business** — required. Not cosmetic: it decides what verification later asks for, and it is what the Maldivian-owned-business attribute hangs from
- **Phone** — pre-filled from the account and **confirmed, not re-typed**. Editing it is a deliberate act that reveals the field. Dial code defaults to `+960`, `6–15` digits, foreign numbers accepted
- **Email** — read-only, with its verified state shown. **An unverified email blocks continuing**, with its own message: booking notifications go there
- Short introduction — capped at `160` characters

**Getting paid**
- Account holder name, account number, bank — all required
- The line, and it is context rather than fine print: `Customers pay you directly into this account. RaajjePro never collects or holds your payments`

**Availability**
- An `Accepting new customers` toggle, on by default
- Fact that must be conveyed: this is **account-level and hides every service at once**, not one service

- A continue action
- Fact: leaving halfway and coming back resumes where they left off

## Become a provider — where you work

The islands this provider generally covers.

- A searchable island multi-select: `Malé` · `Hulhumalé` · `Villimalé` · `Maafushi` · `Thulusdhoo` · `Hithadhoo`
- Selected islands shown as removable
- Fact that must be conveyed: this is a **default that pre-fills every new service**, and it stays editable per service — a mover may cover five islands but photograph on one
- A finish action, which leads straight into creating a first service

## Create a service — step 1 of 7 · Details

*A mockup exists: `mockups/Create_service_widget1.jpg`. Two corrections apply — see `mockups/round-16-redraws.html`.*

- Step position: `1 of 7`
- **Progress framed by what is left to publish**, not only by step: `4 required fields left to publish`. Six fields are required in total, and leading with "step 1 of 7" overstates the commitment
- Service name — required
- Category — required, one of the twelve. The delivered mockup shows **Tuition**; it is **Boat Charter**
- Short description — required
- **Tags as tappable chips**, scoped to the chosen category, with free text underneath for anything not covered. The delivered mockup has free-text entry only — typing a tag from memory asks a provider to guess what customers search for
- Helper line: `Relevant tags help customers find you in search`
- Fact: **a draft saves with nothing filled in.** Nothing here is required to save; only publishing enforces anything

## Create a service — step 2 of 7 · Location

*A mockup exists: `mockups/Create_service_widget2.jpg`.*

- Step position: `2 of 7`
- Searchable island multi-select, **pre-filled from the provider's default areas** and editable here
- At least one island is required to publish
- Selected islands shown as removable

## Create a service — step 3 of 7 · Pricing

*A mockup exists: `mockups/Create_service_widget3.jpg`. Three corrections apply.*

- Step position: `3 of 7`
- **How the price works**, one of: `Fixed` (one rate per job) · `Hourly` · `Daily` · `Range` (from–to) · `Price on request`
- **The price itself** — and the delivered mockup renders this field **twice**. Once
- **What the customer sees it as**, a separate thing from how it is calculated: `per job` · `per hour` · `per day` · `per session` · `per visit`. `Fixed` + `per session` reads as `MVR 450/session`
- Fact that must be conveyed: choosing **Range** or **Price on request** means this service **cannot** be booked as a fixed time slot — it becomes request-based. A customer cannot book a fixed time at an unknown price
- The delivered mockup includes **Service packages**. **Remove them** — tiered options are not in this version

## Create a service — step 4 of 7 · Media

*A mockup exists: `mockups/Create_service_widget4.jpg`.*

- Step position: `4 of 7`
- **A cover image — required to publish.** It is the first thing a customer sees on every card and in every result
- A gallery, optional, reorderable
- Upload states: in flight, failed with a retry
- Fact: the cover is one of the six required fields

## Create a service — step 5 of 7 · Availability

*A mockup exists: `mockups/Create_service_widget5.jpg`. **Do not implement it as drawn** — two corrections apply.*

- Step position: `5 of 7`
- **How this service is booked:** fixed time slots, or request a time
- Working days and hours
- **Emergency service** toggle — and this is the correction that matters:
  - It is **disabled with the reason shown** where the category or the provider's tier does not qualify: `Emergency work on Electrical needs Gold verification. You are Silver.`
  - Where it is available: `Customers expect a response within 30 minutes` — the same on every emergency category. Read it from the category rather than writing it into the screen, since it is configurable, but every category currently reads 30
- Fact that must be conveyed to the provider: answering fast and arriving fast are different commitments. They state their own arrival estimate when they answer, so a mover needing two hours to load a van says so rather than answering late
- The delivered mockup carries an **`Accepting New Customers`** toggle. **Remove it entirely** — that setting is account-level and belongs in the provider's own settings
- Fact: a provider told the wrong response window stops trusting everything else the app says

## Create a service — step 6 of 7 · Extra info

*A mockup exists: `mockups/Create_service_widget6.jpg`. One correction applies.*

- Step position: `6 of 7`
- Everything here is optional and none of it blocks publishing
- What is included, what is not
- **FAQs** — and the delivered mockup renders this accordion **twice**. Once
- **Warranty**: whether one is offered, and its terms as free text
- **Insurance**: whether public liability cover is held, and details
- Fact that must be conveyed, on this screen, to the provider: **RaajjePro does not check either of these, and customers are told so.** They appear as `Provider states: …`
- **Callback guarantee** opt-in — a free return visit within `7 days` if the same problem comes back. Fact: **this one RaajjePro does enforce**, and it must not be visually grouped with the warranty above

## Create a service — step 7 of 7 · Review & publish

*A mockup exists: `mockups/Create_service_widget7.jpg`.*

- Step position: `7 of 7`
- Everything entered, reviewable, each section editable in place
- **The six required fields, and which are still missing**: name, category, short description, at least one island, a price, and a cover image
- Save as draft, and publish
- Blocked data: publishing with something missing names **exactly which fields**, and each is reachable in one tap
- Over-limit data: a free-tier provider already holding one published service sees what upgrading would allow — not a generic error
- Fact: **every step saves as it goes, and saves offline.** A dropped connection queues the change and sends it on reconnect. Navigation waits until the current step is safely stored — this is the highest-value flow in the app and it must never lose work

---

# Provider — running the business

## My services

The provider's home. What they have published and how it is doing.

*A mockup exists: `mockups/Profile_serviceProvider.jpg` — despite the filename, this is the services dashboard, not a profile.*

- Stats: views, bookings, rating, earnings *(illustrative)*
- **The verification badge, reflecting the tier alone** — `Gold · ID checked, registered trade`. Fact: it does **not** depend on the subscription. A provider whose subscription lapses keeps their badge, because it is a safety signal and not a payment status
- Filters across published and draft
- List and grid views
- Service cards, each with cover, name, price, status, views, bookings, and a live toggle
- A per-card menu: edit, duplicate, hide, delete, view as customer
- A route to **availability and time slots**
- A create-service action
- Drafts-only data: a provider with nothing published still reaches this screen normally, with everything at zero. It is never gated
- Hidden-over-limit data: a service hidden because the free tier allows one is stated as such, with what would restore it — **never as an error, and the data is never lost**

## Availability & time slots — PRIORITY

Where a provider says when they work. Nothing in the delivered designs resembles this, and step 5 of the wizard is a toy version of it that will mislead if it is treated as the pattern.

- **Recurring weekly rules**: which days, which hours, how long each appointment is — `Mon–Thu · 09:00–17:00 · 2 hours each` *(illustrative)*
- **Exceptions and blocked ranges**: travel, public holidays, Ramadan hours — a named range that removes times — `Ramadan hours · 10:00–15:00 · 18 Feb – 19 Mar` *(illustrative)*
- **A preview of the times these rules actually produce**, before they are saved. This is the point of the screen: rules are abstract and times are concrete, and a provider must see what they have just committed to
- The generated times, by date, each `open`, `reserved` or `blocked`
- Individual override on any single time
- Fact: times are generated `60 days` ahead, rolling
- Fact that must be conveyed: **changing a rule never touches a time someone has already booked.** Only future unbooked times change
- Fact: a customer never sees a time that is blocked, taken, or already past
- Empty data: no rules yet, and what publishing some would do

## Booking request — PRIORITY

The prompt a provider answers. The highest-stakes screen in the provider app: a lost tap is a lost job.

- What the job is: service, the customer's **first name only**, date and time or the requested window, address, island, job notes, photos
- Fact that must be conveyed: **no contact details of any kind appear here**, and there is no chat yet
- The amount they would be agreeing to: `MVR 450`
- **A countdown matching the real window** — `24 hours` for a normal booking, `30 minutes` for an emergency on any of the four emergency categories, Moving included
- Three actions: accept, decline, and — on a request-based booking — **propose a time and price**
- Fact that must be conveyed: **accepting locks the price, date, time and scope.** Changing any of them afterwards needs the customer to agree
- **Offline behaviour belongs on this screen:** a tap with no connection is recorded, shows as pending, and sends on reconnect. The provider is never left unsure whether it registered
- Timed-out data: the window passed and the booking is gone, stated plainly

## Propose a time and price

The provider's answer to a request-based booking.

- The customer's preferred window, restated
- A concrete date and time
- A price
- An optional note
- A send action
- Fact that must be conveyed: **sending this holds that time** for as long as the customer has to accept — nobody else can take it
- Fact: sending it **opens the chat immediately**, so the provider lands in a conversation rather than back on a list. This is where the customer says "could we do 3pm instead"
- Fact: the customer has `4 hours` to accept on this category — or `72 hours` on Photography, Gardening, Moving, Events and Boat Charter. **The real number for the category is stated**

## Emergency — accept with your fee — PRIORITY

Answering an emergency. The fee is part of accepting, not a later step.

- The job: description, island, distance, how long ago it came in
- **A callout fee entry** — `MVR` prefixed
- Fact that must be conveyed: this is **what you charge to attend**, and parts and labour are settled directly with the customer afterwards
- Fact: **other providers are being asked too**, and the customer picks from up to three. This is a competitive bid, not a race — accepting first does not win it
- One accept action carrying the fee
- Waiting data: the offer is in, and the customer has `5 minutes` to choose
- Not-chosen data: the customer went with someone else. Stated cleanly, with no reason given, and never left on a spinner

## Payment received?

The customer says they have paid. The provider says whether that is true.

- The amount, the customer, the booking
- **Three visually distinct actions**: `Payment received` · `Payment not received` · `Decline booking`
- Fact that must be conveyed: `Payment received` is **the provider's own statement**, not a check RaajjePro performed
- Fact: no answer within `7 days` sends this to RaajjePro to look at, and **nothing is unlocked by that** — it is not a confirmation

## Mark the job complete

- The booking, and a confirm action
- **Emergency bookings additionally require a final amount** — what the job actually came to once parts and labour were added on top of the callout fee. **The job cannot be marked complete without it**
- Fact that must be conveyed about that field: it is the number a price dispute needs. It is required precisely because a provider has no incentive to volunteer it when it reflects badly on them
- Fact: not marking a job complete does not bury it. After `7 days` the customer is asked, and it closes either way

## My performance

The provider's own conduct numbers, and they see them before anyone else does.

- The same metrics the public profile shows: `94% completed` · `3% cancelled` · `2% no-show` · `91% on time` · `97% price honoured` · `usually responds in 12 minutes` · `47 jobs completed`
- **The bookings underneath each number**, listed. Nobody should learn their own on-time rate from a customer
- Fact: a rolling `90 days`
- Fact: nothing is public below `10` completed bookings
- **Threshold alerts**, naming the specific bookings that caused one and what would clear it: `Your cancellation rate crossed 15%. Three cancellations in the last 90 days.` A provider who does not know they have a problem cannot fix it
- Fact that must be conveyed about consequences, in order: an alert first, then lower search placement, then losing emergency work, and only then a human review. **Never an automatic account action**
- An **appeal** route for a booking the provider says should not count
- Below-floor data: `New provider · 4 jobs completed` and nothing else

## Analytics

Per-service performance. Premium only.

- Per service: views, bookings, conversion, rating trend, response time
- Fact: `No data yet` where there is none — never a zero that reads worse than no number at all
- Free-tier data: what this screen would show, and what unlocks it. Never a blank wall

## Verification

The tier ladder, and how to climb it.

- The three tiers with **exactly what each requires and exactly what it says publicly**:
  - **Bronze** — a national ID or passport matching the account name — `ID checked by RaajjePro`
  - **Silver** — Bronze, plus photos of completed work, plus **either** a customer reference RaajjePro will contact **or** `5` completed bookings with no unresolved dispute — `ID checked, work verified`
  - **Gold** — Silver, plus a business registration **or** a recognised trade certificate — `ID checked, registered trade`
- The current tier, and what the next one needs
- Fact that must be conveyed: **the 5-bookings route to Silver is automatic.** No submission, no review, no waiting
- Fact: **a tier is not needed to be listed or booked.** A provider with no tier is fully visible and fully bookable
- Fact: **emergency work needs a tier** — Gold on Electrical and Plumbing, Silver on AC Repair and Moving
- Fact: **the badge does not depend on the subscription** and never lapses with it
- Fact: an admin will confirm the phone number as part of the ID check
- Document submission: what to send, upload states, and — stated plainly — **documents are deleted `90 days` after the decision**
- Review-pending, rejected-with-a-reason, and resubmit states. A rejection always carries a real reason and a route to try again
- Fact: tiers never expire and there is no annual recheck

## Billing & subscription — PRIORITY

Where a provider sees what they are on and what it costs. Money-adjacent and trust-sensitive.

- The current state, one of: `Trial · 18 days left` · `Premium · next payment 12 Sep` · `Free` · `Paused · 6 days of 10 used` · `Expired`
- **The price this provider actually pays** — `MVR 150/month`, or `MVR 75/month` for the first 100 providers. Fact: **there is no single platform price.** Two providers may legitimately see different numbers
- Fact, where the introductory rate applies: it holds for `12 months`, then becomes `MVR 150` with `30 days` notice
- **Free tier** — `1 active service`, full search visibility, no analytics
- **Premium** — multiple services, analytics and a weekly digest, priority placement. Fact, stated plainly: **it does not include the verification badge**
- A `Try Premium` action for a provider who has never had a trial, and fact: the trial is `30 days`
- **Pause**, and its real terms: `10 days` in total, resumable, and the billing date moves by however long it was paused
- Fact that must be conveyed about lapsing: a lapsed subscription **hides services beyond the first — it never deletes anything**, and one confirmed payment brings them all back. The badge is unaffected
- Warning data: `7 days` before a trial or a period ends
- Grace data: `7 days` after expiry with nothing changing
- **Build this screen so it can be rendered on the web as well as in the app.** The App Store may refuse in-app bank-transfer billing; if it does, this page moves to a browser and the app shows state only

## Pay by bank transfer

Paying RaajjePro. There is no card, and no gateway.

- The amount: `MVR 150`
- **RaajjePro's bank details** and a **reference code**: `RP-2026-0842` *(illustrative)*, with a copy action
- Proof of transfer upload
- A submit action
- Fact that must be conveyed: **nothing activates on submission.** The state is `pending admin confirmation`, and pending grants exactly what no payment grants. No screen may imply instant activation
- Fact: confirmation takes up to `48 hours`
- Rejected data: the reason, verbatim, plus **resubmit immediately** and **appeal** — there is no cooldown
- A route to the Provider Agreement, from here, where it is most relevant

## Invoices

- One entry per confirmed payment: date, amount, period, reference code
- A PDF download per entry
- Fact: no GST line appears at launch. Design so one could be added later without a redesign
- Empty data: `No payments yet`

---

# Not in this brief

**The admin panel.** Roughly fifteen screens — the payment and identity queues, account management, configuration, search, the audit log, and the ops dashboard. It is a **separate React web app on a desktop**, used by one or two people, with keyboard and hover behaviour and none of this document's mobile assumptions. Its visual language is not the app's. It needs its own brief and gets one separately.

**Anything post-v1.** These are named so nobody designs toward them: a credit wallet, advertising, referrals, service packages or tiered pricing, Dhivehi and Thaana, and any form of escrow or in-app payment for a job.
