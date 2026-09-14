# Phase 9 — Create/Edit Service Wizard: Frontend

Built 2026-09-14 against `01_Development_Plan_v5.md` §Phase 9, §1 (the wizard
divergences), §1c, §1h and §1i, and against `mockups/design-composer/Create
Service.dc.html` and `App States.dc.html`. What follows is what was decided
during the build and why, in the order the decisions were forced. The plan is
the source; this file is the record of the places it left a choice.

---

## 1. The queue is data, not closures — and it is the only reason a step survives

§Phase 9 asks for "every step's autosave PATCH queued locally on failure and
replayed on reconnect", and adds the sentence the whole design hangs on: the
wizard "must not silently lose work on a weak atoll connection".

A queue of callbacks satisfies the first half and fails the second. A dropped
connection is not the only way work is lost on a phone — Android reclaims a
backgrounded app, and a `Future Function()` cannot survive that. So
`PendingRequest` is `{method, path, body, idempotencyKey, label, mergeKey}`,
which serialises, and `FileOfflineQueueStore` writes it to one JSON file in
the app documents directory. What an earlier run left behind is picked up on
the next launch and sent.

Three rules follow from it and each has a test:

- **Record before sending.** A request the network refused is written to the
  queue and to disk before the caller is told anything, so "it did not send"
  is never also "it is gone".
- **Order is kept.** Once anything is queued, later writes queue *behind* it
  rather than overtaking it — otherwise a reconnect could apply an old
  autosave over a newer one. `submit` therefore enqueues and drains rather
  than sending directly whenever the queue is non-empty.
- **A server refusal is not a connection problem.** It leaves the queue and
  surfaces as a `RejectedRequest`; retrying it forever would never succeed and
  would hide it.

**Merging is what makes it usable.** Ten offline keystrokes on the service
name are one queued PATCH, not ten, because a PATCH is a partial update and
merging bodies key-by-key produces exactly what the server would have ended up
with. Requests carry a `mergeKey` (`listing:<id>:patch`); a POST sets one
unique to itself so nothing ever merges two creations.

**Every failure in the store degrades to no persistence rather than to an
error.** The in-memory queue is authoritative and the file is a safety net
under it; a device with a full disk should still let a provider fill in their
listing.

### It is built once, in `core/`, and §0.0 item 14 bounds it

Three surfaces reach it and no others: this phase's autosave, §Phase 17.1's
slot and request accept prompt, §Phase 18's chat sends. §Phase 17.3's
`emergency-accept` is excluded in the class comment, with the reason — a
replayed offer would commit a provider to a callout fee and an `etaMinutes`
calculated somewhere else, and §1f scores on-time rate against that number.
If a later phase finds itself adding it, that is the bug.

**Publish is not queued either**, and for a different reason: telling a
provider their service is live when the request has not left the device is a
lie. Offline, publish says so and the draft stays a draft.

## 2. "Blocked until persisted" and "never blocked" are both true, and they are about different things

§Phase 9 says both "step navigation never blocked; Review always reachable"
and "step navigation is blocked until the current step's data has persisted".
They are not in tension once you separate the two gates:

- **Validation never blocks.** Review is reachable from step 1 with nothing
  typed, and every pill navigates. A step with a required field still empty
  gets an amber dot — a signpost, never a lock.
- **Persistence delays.** `goTo` flushes any pending or in-flight autosave
  first, and Continue reads "Saving this step…" while it does.

Offline that wait is instant, because the queue accepting the write **is**
persistence. That is the point of the save pill's third state: **"Saved
offline", never "Not saved"**. An edit the queue accepted is saved — on this
device, and it will reach the server — and telling a provider otherwise on a
weak connection makes them retype work that was never lost.

## 3. A server response is adopted only when nothing newer has been typed

Every PATCH answers with the whole listing, and the server owns several fields
the client cannot compute: the emergency verdict, `callbackAvailable`, the
booking mode it re-defaults on a category change. So the response is adopted.

But a response that lands after two more keystrokes would clobber them. The
controller keeps one counter, `_edits`, bumped on every local edit; a request
captures it before going out and its response is adopted only if the counter
has not moved. Otherwise only the save pill changes — a newer PATCH is already
on its way and will bring fresh derived values with it.

This also decided a test-harness rule worth stating: a fake PATCH that always
replies with the original draft *undoes* every edit on the way back, and the
wizard faithfully adopts it, because the server's answer is authoritative
(invariant 4). `WizardHarness.scriptEchoingPatch` behaves like the server.

## 4. The required-field count is mirrored client-side, and only for the header

`publish_gate.dart` is a line-for-line mirror of `backend/…/publish.ts`,
including the messages. It exists because "N required fields left to publish"
is on every step's header and cannot wait for a round trip that may not happen
for an hour — and because it must stay true while a save is queued.

**It is UX and the server is the rule** (invariant 4). What publish refuses is
what counts, and when it refuses with `LISTING_INCOMPLETE` the review step
renders the *server's* list, not this one. Both are tested, including the case
where they disagree: a cover row that exists but whose upload never finished.

## 5. Two refusal codes, two entirely different screens

§Phase 8 split the publish refusal deliberately and §Phase 9's "an upgrade
prompt, not a generic error" is exactly that distinction:

- `LISTING_INCOMPLETE` carries a row per missing field with the wizard step it
  belongs to — rendered as one tappable Fix row each, because publishing must
  not be a five-round-trip guessing game.
- `LISTING_CAP_REACHED` carries the cap and the listings already live —
  rendered as a sheet naming the live listing, offering the upgrade and saying
  the draft is safe. **It is a prompt, not a cap on drafting**: nothing was
  lost, nothing was blocked, and the footnote says so first.

Anything else — the pricing/booking-mode pair, the emergency gate, the
callback guarantee — is a form-level error that also *navigates to the step
that owns the first named field*, because the provider cannot act on a message
about a control they cannot see.

## 6. The emergency gate is rendered, never recomputed

`OwnListingDto.emergency` carries the server's own verdict and its sentence.
Step 5 renders that sentence verbatim through `AppToggle.disabledReason`.
Nothing in this app compares a tier to a bar: §1c composes the rule from four
fields across three entities, the backend owns it, and a second copy here is
how a provider ends up staring at a disabled toggle whose stated reason is
wrong.

The response window is `category.emergencyAcceptWindowMinutes` — 30 for every
emergency category, Moving included (Round 22) — and it is read, never written
down. **A null window drops the sentence rather than printing a default.** A
capable category with no seeded number is a misconfigured row, not a value to
invent, and a provider told the wrong window distrusts everything else the app
tells them.

## 7. Step 2 pre-fills by copying once, at creation

§Phase 6a hands off "pre-populated with nothing (a fresh draft)" and §Phase 9's
step 2 is "pre-filled from your default coverage areas". Both are true at once
only if the *listing* starts empty and the islands are copied across as a
separate write. `_startFreshDraft` does exactly that: `POST` the draft, read
`GET /v1/providers/me`, then `PATCH` the island **ids** onto the listing.

Doing it at creation is what makes it happen exactly once — a provider who
clears every island and comes back to step 2 does not find them silently
restored. After that write the listing owns its areas and the account default
never reaches back in, which is ledger **P7-3**'s distinction made concrete.

It is client-side because §Phase 8's `createDraft` does not do it and its
Done-when does not ask it to; changing that now would be building backwards
into a closed phase. Flagged here rather than done silently.

## 8. What moved into `core/`, and why that is the convention rather than a refactor

`lib/README.md`: *no feature may import another feature; they meet in `core/`*,
and *a widget a second feature needs moves to `shared/`; it is not copied*.
Three things had their second consumer this phase:

| Moved | From | Because |
|---|---|---|
| `CategoryApi`, `CategoriesController` | `features/explore/` | step 1's grid is the catalogue's second consumer |
| `CircleBackButton` | `features/auth/` | the wizard header is its fourth use and its second feature |
| `AppTextField.prefix` | *(new slot)* | the price field's "MVR" chip is a word, which `prefixIcon` cannot express |

The account-level service areas took the other route: `AccountServiceAreasApi`
in `core/location/` reads the one field the wizard needs out of
`GET /v1/providers/me` rather than moving §Phase 6a's whole
`ProviderOnboardingApi`. The wizard has no business modelling a provider
profile, and §Phase 10's dashboard is where the rest of that response gets a
home.

## 9. `image_picker` is a new dependency, and it is not deferred

Every other platform boundary in this app ships as a seam with nothing behind
it — `PushMessaging`, `CrashReporter` — because the vendor is procured at
deployment (§0.0 item 17). The photo library is not a vendor: it needs no
account and no per-project config file, and §Phase 9's first Done-when line is
"a service can be created end-to-end", which a wizard that cannot reach a
photo cannot satisfy — the cover image is one of the six required fields.

So `image_picker` is added, behind `core/media/media_picker.dart` so no widget
test crosses a platform channel. The PUT to the presigned URL is its own seam
(`MediaUploader`) and deliberately does **not** go through `ApiClient`: that
client attaches a bearer token, decodes an envelope and refreshes a session,
none of which belongs on a presigned upload and the first of which a real S3
endpoint would reject.

## 10. The app-wide no-connection state, and the list that is deliberately short

§Phase 9 owns `App States.dc.html`'s no-connection state because this is the
first phase in which queue-and-replay exists, and therefore the first point at
which its explainer is true.

`NoConnectionView` carries **one** capability today — saving a step of the
wizard — and the class comment names which phase adds each of the others.
Two divergences from the prototype, both deliberate:

- **The emergency exclusion row is not here yet.** §Phase 17.3 adds it, with
  the control it excludes. Telling a provider today that emergency offers need
  a live connection would describe something this app does not have.
- **The footnote drops "and no payment is recorded".** §Phase 17.1 owns the
  attestation that sentence is about.

## 11. Divergences from `Create Service.dc.html`, each with its reason

| Prototype | Built | Why |
|---|---|---|
| "View listing" in the success sheet | Absent | It links to `Service Preview.dc.html`, which is §Phase 12's screen. A button that lands nowhere is worse than its absence |
| Toasts ("Up to 10 tags", "Already added") | Inline messages | frontend/CLAUDE.md: errors surface where the user can act on them, not as toasts. The tag field says why under itself; the chips simply stop at ten |
| `<select>` for the working hours | A bottom sheet | The app's own chooser idiom, and it scales with the OS text size. (The island rule is stricter and separate: a native picker is never acceptable there) |
| `<select>` for `priceUnit` | Five filter chips | Five options fit on two rows, and a chip row is the app's own idiom for a small closed set. The five are the whole rule — ledger **P8-1** records why there is no per-category subset |
| "Sample list — the live app has every inhabited island" under step 2 | Absent | Prototype scaffolding. The real control reads the real register |
| "Saved just now" / "Saving…" / "Saved offline" | Unchanged | Kept exactly, including the third label — see §2 |
| `Accepting New Customers` on step 5 | Absent | Round 16. Account-level, and §Phase 8a's pause keys off it. Its billing sentence is §Phase 10 and §Phase 10a's (ledger **P8A-4**) |
| Duplicated FAQs accordion | One | The mockup drew it twice |
| Duplicate Price field, Service Packages | One field, no packages | Round 16; tiers stay post-v1 |

## 12. Step 1's activity-category guidance is an enumeration, and the plan seeds no flag for it

§Phase 9 (Round 25/26) asks for a different name-field helper on **Photography
and Boat Charter** — "Name the specific service … Customers book the offering,
not the category." No seeded column distinguishes them, and nothing derivable
from the DTO does either: the long quote window also catches Moving, and
`callbackEligible` catches all three.

Built as a two-entry set keyed on the seeded `iconIdentifier` (`camera`,
`boat`) rather than on the display name — a stable token this app already
resolves for icons and accents, which survives a rename the way "Computer"
became "Appliance Repair". **It is still a client-side enumeration of two
categories**, and the right home is a `Category.listingGuidance` column
whenever one is added. Flagged rather than done silently; it is guidance copy
only, nothing is enforced, and no package entity exists.

## 13. Ledger P6A-2 is closed

§Phase 6a's handoff was built and asserted against the real route table, but
what opened behind `/services/new` could not be checked because there was no
wizard and no `Listing`. `test/features/onboarding/phase6a_done_when_test.dart`
now asserts what the row asked for: arriving from onboarding's confirmation
sheet opens step 1 on a **genuinely fresh draft** — the only listing call is
the creation, nothing listed or read one by id, and the name field is empty —
while step 2 pre-fills from the account-level `ProviderServiceArea`, by id.

The counter reads *five* required fields rather than six on arrival, and that
is the assertion that proves the pre-fill landed.

## What is deliberately not built

- **No "View listing" from the success sheet** — §Phase 12 owns Service
  Preview (§11).
- **No entry point that resumes a draft.** The wizard accepts a `listingId`
  and resumes from it, and that path is tested; what does not exist is a
  screen a provider reaches it from. §Phase 10's My Services dashboard is that
  screen, and `/provider/services` is still `UnbuiltScreen`.
- **No slot management.** Step 5 collects a simple working window and says so
  in its own helper: recurring rules, exceptions and blocked ranges are
  §Phase 9a's, and §1's mockup table warns that step 5 "is a toy version and
  will mislead if treated as the pattern".
- **No provider-level analytics, no listing duplication, no bulk anything.**
- **No client-side emergency or callback rule.** Both are rendered from the
  server's answer (§6).

## What §Phase 9a, 10, 10a and 12 inherit

- **`OfflineQueue`** — §Phase 17.1 and §Phase 18 register their own
  `PendingRequest`s against it and add their row to `NoConnectionView`;
  §Phase 17.3 adds the exclusion.
- **`/provider/billing`** exists as a route name and lands on `UnbuiltScreen`;
  §Phase 10a fills it, and the over-cap sheet's CTA already points there.
- **`ServiceWizardArgs`** — §Phase 10's dashboard opens an existing listing by
  passing `{'listingId': …}`, and a fresh draft by passing nothing.
- **`MediaPicker` / `MediaUploader`** — any later screen that uploads an image
  reuses both rather than repeating the three-step dance.

## Deferred verification

No new rows. Every Done-when line is testable now and is tested; row
**P6A-2** is closed by this phase (§13) and row **P8A-4** stays open against
§Phase 10 and §Phase 10a, which is where the `acceptingNewCustomers` billing
sentence is owed — §Phase 9 correctly renders no such toggle.
