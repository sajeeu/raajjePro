# Round 39 — three fixes to the seed, before the walk-through

Round 38's structure is right. The launcher, the session, the role-aware `BottomNav` and the navigation all work, and the seed obeys most of the rules it needs to: all twelve categories are present, every listing's booking mode matches its category, the callback guarantee is on exactly the six eligible categories, and money is plain MVR integers throughout.

Three things in `session.js` are wrong, and one name. **Change only these** — do not touch the structure, the launcher or any navigation.

## 1. The emergency could not have happened

`emergencyBooking.category` is **Plumbing**, which needs **Gold** (`emergencyMinimumTier`). Two of its three offers are from providers who are not eligible — on tier *and* on category:

| Offer | Tier | Their listing | Why it is impossible |
|---|---|---|---|
| Ibrahim Rasheed | Gold | Plumbing | ✓ correct |
| **Ali Waheed** | Silver | Electrical | Below Gold, and has no Plumbing listing |
| **Hassan Zahir** | Silver | Home Repairs | Below Gold, no Plumbing listing, and **Home Repairs is not emergency-capable at any tier** |

Dispatch broadcasts only to providers whose **listing is emergency-capable in that category** and whose tier meets that category's bar. Neither of those two could ever have received this request, so the screen shows a result the rule could not produce — and the emergency flow is the one journey where being wrong matters most.

**Fix: the seed needs three Gold plumbers, so three eligible offers exist.** It currently has one.

Two more plumbing providers already exist in the artboards and can be lifted into the seed rather than invented — `Discovery` carried a plumbing set that the seed dropped, including **Naseem Ali** and **AquaFix Maldives**. Give each a Plumbing listing on Malé at **Gold**, and let them be the other two offers.

Keep everything else about the offers exactly as it is: each carries **its own callout fee and its own ETA**, and the ETA stays the provider's estimate, never a platform guarantee.

If you would rather not have three Gold plumbers, the alternative is to move the emergency to **AC Repair**, whose bar is Silver — but that ripples into `Booking Detail`, `Emergency Flow`, `Dispatch Fee` and `Provider Emergency`, all of which already show a plumbing call-out. **Adding the two providers is the smaller change**, and it is the one I would make.

## 2. One booking uses a status key that does not exist

Booking `4833` has `status: 'waiting_for_provider'`. **`StatusPill`'s key is `waiting_provider`** — no `for`.

`StatusPill` falls back to rendering the raw string in grey when it does not recognise a key, so this *looks* like it works while the label silently comes from the data instead of from the component. That is the exact drift the component exists to prevent, and it is the third time it has come up — the same mistake was in `Pay by Bank Transfer` and `Verification` at session 13.

**Change it to `waiting_provider`.**

## 3. Three of the twelve states have no booking

The brief asked for one booking per `StatusPill` state. Ten are seeded; these are missing:

- **`waiting_provider`** — fixed by item 2 above
- **`receipt_confirmed`** — a booking where the provider has confirmed receipt. Note the wording rule: this is the provider's own attestation, so it means *"Provider confirmed receipt"*, never *"Payment verified"* and never anything implying RaajjePro checked it.
- **`pending_offline`** — an action taken with no connection, saved on the device and sending on reconnect

Add one booking for each of the last two, following the shape of the existing rows.

## 4. The customer has two names

`session.js` and `Start` call her **Aishath Naeema**. `Profile` renders **Aishath Nazim**.

This is the same collision as Mariyam being both a provider and a customer, and in a walkable app it is worse — you sign in as one person and land on a profile belonging to someone else.

**Use `Aishath Naeema` everywhere**, including `Profile`. `Components` already writes it that way in its form example.

---

## Leave alone

- Everything structural from Round 38 — `Start`, `session.js`'s shape and API, the role-aware `BottomNav` and its tab→screen mapping, every navigation edge added
- The rest of the seed: the twelve categories and their modes, the callback set, the thirteen listings, Aishath's addresses and standing instructions, Ibrahim's conduct numbers, the subscription and its invoices at the introductory MVR 75
- The MVR 200 dispatch fee, recorded as owed and never blocking dispatch
- All sixty-one screens' layouts and copy
