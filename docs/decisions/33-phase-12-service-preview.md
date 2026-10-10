# Phase 12 — Service Preview (the public listing page)

Built 2026-10-10 against `01_Development_Plan_v5.md` revision 5.37: §Phase 12
and its **Done when**, with §1c (booking modes, the Message button, the
emergency door), §1e (the badge), §1f (conduct is numbers) and §1i
(self-declared cover) read alongside. Design: `Service Preview.dc.html`.

## 1. What was built

**Backend** — `modules/public-listings/`, two open routes:

- `GET /v1/listings/:id/public` → `PublicListingDto`
- `GET /v1/providers/:id/public-summary` → the provider (`PublicProviderDto`)
  and a two-field rating summary

`/v1/listings/:id` stayed unclaimed in Phase 8 so this phase could define the
public shape without inheriting a body full of `missingRequiredFields`; this is
that shape, and `OwnListingDto` and it share no mapper.

Both answer a guest. A signed-in caller is *recognised*, not required — the
principal hook already runs on every request — and is used for exactly two
things: `viewerIsOwner` (the Edit control's only source) and not counting an
owner's own look as a view.

**Not found is one answer.** A draft, a provider-hidden listing, a deleted
one, a suspended provider's and an id that never existed are the same 404 with
the same body; the endpoint never confirms that a hidden thing exists. The
listing half is `PUBLICLY_VISIBLE_LISTING` and the provider half is
`ProviderProfileService.readPublic` → §1a's `findVisibleProviders` gate —
neither restated.

**The listing view is recorded** (`ListingEvents.record('view')` — the seam
Phase 8 left for this phase). A failure to record is logged and never fails the
page.

**Frontend** — `features/service_preview/`: model, API, controller, the screen
and its sections, and `preview_copy.dart`, where every composed sentence lives
so the words are testable without a widget. Route `/listing`
(`AppRoutes.listingPreview`), reached from My Services' "View as customer" and
the wizard's "View listing" — both of which had been parked on placeholders
naming this phase.

## 2. How "no contact or payment data, under any circumstance" is held

Not by a check per handler. The response types have no field that could carry
one: `PublicProviderDto` has no phone or payment field, the listing DTO reads no
`User` row, and the Flutter models parse by name, so a field the server should
never send has nowhere to land (asserted by planting `phone`, `email` and
`bankAccountNumber` in a response and finding none on screen). The backend test
scans the **raw body text** for the provider's phone, `+960` form, email, bank
name, account name and number, and the customer's own phone and email — for a
guest, a customer and the owner, on a slot listing, a request listing and an
emergency listing.

## 3. Decisions the plan left open, and what was chosen

**The second signal comes from the server.** Slot listings carry `nextOpenAt`
from the same `listOpenSlots` query a customer's picker uses, so the page can
never promise a time the picker would refuse. Request listings carry the
provider's median response time, taken from `provider.conduct` — where §1f's
ten-booking floor is already applied — rather than from a second source that
could forget it. Below the floor the figure is absent, not zero.

**The emergency door is re-derived at read time**, from the category's
`emergencyMinimumTier` and the provider's tier *now*, not only from the stored
`isEmergency`. The tier-drop sweep clears the flag, but the page must not
advertise an emergency door for the gap before it runs. The dispatch fee shown
(MVR 200) is the server's `EMERGENCY_DISPATCH_FEE_LAARI`, stated before
anything is sent; the request is raised against a **category**, never a
listing or a provider (Round 23).

**`callbackGuarantee` is `offered && category.callbackEligible`**, so a stale
flag on an ineligible category (Round 28) is not shown.

**Self-declared cover** returns the warranty and insurance text only behind
their flags, and the screen prints each as "Provider states: …" with the
statement that RaajjePro has not checked it — outside the callback card's
treatment.

**The full verification badge, not the chip.** The prototype uses the chip
(`◆ Silver`), which carries its §1e words only in the semantics label. The
screen uses `VerificationBadgeSize.full`, so the words — "ID checked, work
verified" — are on screen. A bare tier name next to a business name is what §1e
and the Phase 16 trust-grid note warn a customer will read as a track record.

**One prototype sentence was dropped.** "…confirms it, usually within the hour"
had no source: nothing computes a confirmation time. A response time appears
only where the server sent one.

## 4. Conflicts between the plan and what the task said — flagged, not resolved silently

1. **"Unverified users route to phone verification first."** There is no SMS and
   no phone verification anywhere in this system (root `CLAUDE.md` 1c). The
   gate routes an unverified user to **email** verification, which is what
   `requireEmailVerified` enforces. The plan's wording is stale.
2. **"About / Reviews / Provider tabs."** The approved prototype is one scrolling
   page whose sections fall in that order. It was built as drawn; a tab bar
   would be a design the owner has not seen.
3. **"Provider response-time metric displayed (Phase 19 computes it)."** Phase 11
   computes `medianResponseSeconds`; Phase 19 has nothing to add. The metric
   renders from Phase 11's snapshot.
4. **"Message button restored → opens the pre-booking enquiry thread."** The
   thread is §Phase 18's. See §5.

## 5. What is deliberately not built

- **The enquiry thread** (Phase 18). The Message button is drawn in both places
  the artboard puts it, gated on a verified email, and past the gate lands on
  `UnbuiltScreen('Messages', 'Phase 18')`. Ledger **P12-1**.
- **The report flow** (Phase 22). Same treatment; ledger **P12-2**.
- **Saving** (Phase 14). The heart is drawn and wired to nothing, marked by
  `InertControl` so a test can tell. Ledger **P12-3**.
- **The provider's profile** (Phase 13). The provider card is a real tap target
  that lands on `UnbuiltScreen`. Ledger **P12-4**.
- **The stats grid.** §Phase 12 asks for the response-time metric only; the
  grid is Phase 13's.
- **A paged review list.** The page shows the newest three under the summary,
  as the artboard does; `GET /v1/listings/:id/reviews` already pages the rest.

## 6. Verification

`backend/test/phase12-done-when.test.ts` (18) and
`frontend/test/features/service_preview/phase12_done_when_test.dart` (34), one
group per clause of the Done-when. The booking-mode clause is asserted by
pushing the real route table's names and reading the arguments each receives;
`AppRoutes.bookSlot` and `.requestTime` are asserted equal to the strings the
booking screens own, so the two copies cannot drift.
