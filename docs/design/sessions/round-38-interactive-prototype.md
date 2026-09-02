# Round 38 — make the sixty artboards one walkable app

**Purpose: end-to-end verification before development starts.** Someone should be able to open one link, press **Continue as customer** or **Continue as provider**, and walk a real journey — browse, book, chat, pay, complete, review — without hitting a dead end or a toast that says "Opens X".

This is larger than previous rounds. If it needs two passes, do §1–§4 first and say so; that alone makes the app walkable.

## What already works, so we build on it rather than over it

I checked the current state before writing this:

- **182 navigation links already exist and every one of them resolves.** No broken targets anywhere.
- Navigation is plain `<a href="Screen.dc.html">` (166) and `location.href = '…'` (16). That works and should stay the mechanism.

**So do not build a single shell artboard that mounts the other screens.** Every screen is a full 412px device frame with its own scroll and its own bottom bar; nesting them would break all sixty. The app is the sixty files, linked — plus a shared session, a launcher, and the missing edges.

## 1. Two seeded accounts — both already exist in the data

Do not invent people. Both personas are already spread across the artboards; this round makes them consistent.

**Customer — Aishath Naeema.** Already the logged-in customer: `Home` and `Discovery` render her initials `AN` in the header avatar. `Saved Preferences` already holds her whole profile — saved addresses *Home* (M. Fehivina, 3rd floor, Kalaafaanu Hingun, Malé) and *Office* (H. Orchid Lodge, Unit 2B, Nirolhu Magu, Hulhumalé), preferred windows *Weekdays 9:00–12:00* and *Saturday 14:00–18:00*, standing instruction *"Gate code 4471. Please call from the lobby."*

**Provider — Ibrahim Rasheed.** Appears in **23 of the 60 files**, always the same: *Rasheed Plumbing Services*, **Gold**, 4.6 (31 reviews), 47 jobs completed, replies in 12 minutes, Malé, Plumbing. His two listings are in `Provider Profile`: *Emergency Plumbing & Pipe Repair* (From MVR 350, request mode, callback guarantee on) and *Bathroom & Kitchen Plumbing Installation* (MVR 900/day, request mode, no callback). His conduct numbers are in `My Performance` — 94% completed, 3% cancelled, 2% no-show, 91% on time, 97% price honoured.

**One collision to fix.** *Mariyam Shifa* is currently both a **provider** (Home Deep Cleaning, Silver, in 22 files) and the **customer** in `Booking Request` and `Propose Time and Price`. In a walkable app the same person cannot be both. **Mariyam Shifa stays the cleaning provider; the customer in those provider-side screens becomes Aishath Naeema** — which is also who the provider would actually be dealing with in this prototype.

## 2. `Start.dc.html` — the launcher

A new artboard, and the entry point.

- RaajjePro logo and one line: **`Prototype — pick who you are`**
- Two large buttons, one tap each, no form:
  - **Continue as customer** — *Aishath Naeema · Malé* · sets role `customer` · goes to `Home.dc.html`
  - **Continue as provider** — *Ibrahim Rasheed · Rasheed Plumbing Services · Gold* · sets role `provider` · goes to `My Calendar.dc.html`
- Below them, a quiet text link: **`See the real sign-in screen`** → `Sign In.dc.html`
- A small footer line: `Seeded demo data. Nothing here is a real account.`

**Do not put these two buttons on `Sign In.dc.html`.** That screen is the real design and must keep showing the real sign-in. A one-tap fake login sitting on it would read as product. Keep them on the launcher, and keep `Sign In` reachable from it so the screen is still in the walk.

## 3. The session — one shared file

Add a sibling **`session.js`**, referenced from each screen's `<helmet>` exactly as `image-slot.js` already is. It holds:

- the current **role** (`customer` / `provider`) and the matching persona
- the **seed** (§5) — every provider, listing, booking, thread and payment the prototype needs
- any state a walk-through changes: a booking created, a quote accepted, a job marked complete, a message sent

**Persist it in `localStorage`** so state survives navigating between files — that is the whole point of an app rather than sixty screens. `Discovery` already reads `new URLSearchParams(window.location.search)` at load, so if a shared script or storage turns out not to be available in this environment, fall back to a `?role=` parameter carried on links — **and tell me which one you used**, because it changes what I can rely on.

If nothing is in storage, treat the role as `customer` and behave exactly as the artboards do today. Nobody should ever see a broken screen for arriving without a session.

## 4. Navigation — the app's spine

### 4a. `Home` must mount `BottomNav`

`Home` renders its **own private tab bar** from a local `TABS` array and does not mount `BottomNav` at all. This is the same defect Rounds 33 and 34 dealt with on the cards — the component exists and the screen keeps a copy. Replace Home's inline tab bar with `<dc-import name="BottomNav" …>`.

### 4b. `BottomNav` gains a provider tab set

It currently has exactly one: **Home · Explore · Bookings · Messages · Profile** — the customer's. Provider screens have no bottom bar at all and are reached only by back-links.

Add a `role` prop. For `provider`, the tabs are **Calendar · Services · Messages · Billing · Profile**, going to `My Calendar`, `My Services`, `Messages`, `Billing`, `Profile`. Keep the customer set exactly as it is. The tab→screen mapping lives **in `BottomNav`**, not in each screen — that is what stops it drifting.

Then mount `BottomNav` on the provider screens that are top-level destinations: `My Calendar`, `My Services`, `Billing`. Leave it off screens that are steps inside a flow (`Propose Time and Price`, `Mark Complete`, `Payment Received`, `Pay by Bank Transfer`) — those have a back link and should not offer an escape mid-task.

### 4c. Six screens toast instead of navigating

These are the hubs, so this is what currently stops a walk dead:

| Screen | Replace the toast with |
|---|---|
| `Home` | *Opens Explore* → `Discovery` · *Opens the ASAP request* → `Emergency Flow` · *Opens notifications* → `Notifications` · *Opens all categories* → `Discovery` · *Opens Become a Provider* / *provider info* → `Become a Provider` |
| `Discovery` | *Opens the ASAP request* → `Emergency Flow` · *Opens notifications* → `Notifications` · category tile and result card → `Service Preview` |
| `Create Service` | *Opens the live listing* → `Service Preview` · *Opens plans* → `Billing` |
| `Become a Provider` | its final step → `Create Service` |
| `Emergency Flow` | selecting an offer → `Booking Detail`; the chat link → `Booking Thread` |
| `Provider Emergency` | accepting → `Booking Thread` |

Filter toasts on `Discovery` (*Opens price range*, *Opens booking mode*, *Opens all filters*) may stay as toasts — they are in-screen controls, not journeys.

### 4d. Eleven screens have no way in

Every one of them **already links back** to where it belongs, so only the forward edge is missing:

| Screen | Add an entry point on |
|---|---|
| `Account Settings` | `Profile` |
| `Help Support` | `Profile` |
| `Verification` | `My Services` (and `Profile` for the provider) |
| `Cancel Booking` | `Booking Detail` |
| `Raise Dispute` | `Booking Detail` |
| `Recurring Booking` | `Booking Detail` or `Pick a Time` |
| `Did This Happen` | `My Bookings` — the prompt after a booking's time passes |
| `Quote Received` | `My Bookings` / `Notifications`, customer side |
| `Mark Complete` | `My Calendar`, provider side |
| `Payment Received` | `My Calendar` or `Booking Thread`, provider side |

`App States` is a catalogue of loading/empty/error patterns, not a screen in a journey. **Leave it out of the navigation** and out of the launcher.

## 5. The seed

**One seed, in `session.js`, that every screen reads.** Today the same booking is described with slightly different data on different screens; that is fine for artboards and fatal for a walk-through.

It must cover: **all twelve categories** with at least one published listing each · Ibrahim's two listings and Mariyam's one, exactly as they already read · Aishath's saved addresses, windows and standing instructions · at least one booking in each state the `StatusPill` can show · one emergency booking with its offers · one thread per booking plus one enquiry thread · one subscription with an invoice history · one payment submission awaiting confirmation.

**The seed obeys every rule the artboards obey.** `verify-dc.py` will catch some of this, not all:

- **Twelve categories:** Cleaning, Beauty, Fitness, Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control, Photography, Moving, Home Repairs, Boat Charter. Not Gardening, not Computer, not Events, not Tuition.
- **Booking mode follows the category.** `slot` (shown as *Book instantly*) is **Cleaning, Beauty and Fitness only**. Every other category is `request`.
- **Callback guarantee** only on Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control and Home Repairs.
- **Emergency** only on Plumbing, Electrical, AC Repair and Moving — **Gold** for Electrical and Plumbing, **Silver** for AC Repair and Moving. 30-minute response window for all four. Offers carry the provider's own callout fee and their own ETA, and the ETA is their estimate, never a guarantee.
- **Money is MVR**, whole numbers, code first.
- **No phone number appears anywhere** except behind the emergency reveal on an accepted emergency booking.
- **Islands** follow the atoll rule — `Dh. Meedhoo` when the name is shared, `Malé` when it is not.
- **Never "Payment Verified"** or any wording implying RaajjePro checked a payment. The two-sided attestation says what actually happened.
- **No editorial labels** on providers. Numbers only.

## 6. What a successful walk looks like

These are the acceptance tests. Each must run start to finish with no dead end:

**Customer** — Start → Continue as customer → Home → Explore → a Cleaning listing → Book instantly → pick a time → confirm → Booking Detail → chat → *I've paid* → provider confirms → Rate This Job.

**Customer, request mode** — Home → a Plumbing listing → Request a time → Quote Received → accept → Payment Step → Booking Detail.

**Customer, emergency** — Home → *Something urgent?* → Emergency Flow → offers arrive → pick one → dispatch fee shown as owed → Booking Detail → reveal contact.

**Provider** — Start → Continue as provider → My Calendar → an incoming Booking Request → Propose Time and Price → accepted → chat → Mark Complete → Payment Received.

**Provider, business** — My Services → create a listing through the wizard → publish → Verification → Billing → Pay by Bank Transfer → Invoices.

**Both** — Profile → Account Settings, Help & Support, Saved Preferences, Legal, Notifications.

## 7. What must not happen

- **No new claims.** Seeded content says only what the plan already supports. If a screen needs a fact the seed does not have, leave the state empty and say so — an honest empty state beats an invented number.
- **Nothing implies a real backend.** No "verified", no confirmations RaajjePro cannot make, no delivery guarantees.
- **The launcher is clearly a prototype device** and never dressed as a real login.
- **Do not restyle anything.** No layout, copy, colour or component changes. This round is wiring, session and seed only. `ServiceCard` and `SkeletonCard` are settled — do not touch them.
- **Do not delete a screen** because it is awkward to reach. Tell me instead.

---

## Leave alone

- All sixty artboards' layouts, copy and states — including every empty, loading and error state
- The seven components. Only `BottomNav` changes, and only to gain the provider tab set
- The 182 links that already work
- `App States` and `Components` — reference sheets, not part of the app
- The island pickers, the card frames, the callback and emergency rules, the payment-attestation wording, the conduct metrics
