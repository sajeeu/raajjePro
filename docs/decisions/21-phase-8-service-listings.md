# Phase 8 — Service Listings: Backend Domain

Built 2026-09-10 against `01_Development_Plan_v5.md` §Phase 8, §1b, §1c, §1d
and §1i. What follows is what was decided during the build and why, in the
order the decisions were forced. The plan is the source; this file is the
record of the places it left a choice.

---

## 1. Five answers arrived from the plan mid-build, and three changed the build

This phase asked one question and reported three decisions taken on
precedent. All five came back settled **in the plan** rather than in a chat —
`01_Development_Plan_v5.md` is at revision 5.25 and §Phase 8 carries five new
🔧 notes. Two confirmed what was already built; three changed it. What
follows records the change, not the deliberation, because the plan now holds
the reasoning.

| Answer | Effect here |
|---|---|
| No `Category.priceUnits` | **Reverted.** The column, its seed and its DTO field were built and are removed — see below |
| `Category.suggestedTags` **is** this phase's column | **Added**, seeded from the prototype's twelve-category `TAGS` map (§14) |
| The over-cap refusal needs its own code | Already correct — `LISTING_CAP_REACHED` was distinct from `LISTING_INCOMPLETE` and carries the cap |
| `MEDIA_STORAGE=file` copies §0.0 item 17's posture **including its production refusal** | **Added** the missing half (§2) |
| A media row needs reversible moderation visibility | **Added** — `hiddenByAdminAt` (§13) |

### `priceUnit` gets no per-category column

The bullet says "seed a short list per category" and then names no list for
any category anywhere. The plan's own note settles why that is not an
oversight to fill: `Create Service.dc.html`'s `UNITS` is a flat five rendered
whatever category step 1 chose, **in the same file that keys its tag
suggestions by category** — the designer keyed the thing the plan calls
category-scoped and left the units alone — and §Phase 10b's editable Category
fields are enumerated without units, so the column would be identical across
all twelve rows and editable from nowhere.

This was initially built the other way (column present, all five seeded
everywhere) and is reverted: a column nothing narrows and nothing can edit
reads to a later consumer as a narrowing feature that does not exist. The
closed `PriceUnit` enum is the whole guard, and three spellings of "session"
are impossible either way. `allowedPriceUnits` came off the listing DTO with
it — a field returning the same five values for every category is a response
nobody could act on, and adding it later is additive. Ledger row **P8-1**
holds the unbuilt half.

## 2. Media storage: a transport boundary, because there is no bucket

§Phase 8 asks for "media upload via presigned URL — **server-side
content-type and size validation, EXIF stripping on every image**". No object
store exists, and §0.0 item 17 puts vendor procurement at deployment.

**Decision: the same posture Phase 2 took for email and Phase 3c for push.**
`MediaStorage` is the boundary, `MEDIA_STORAGE=file` writes objects under
`backend/.media/`, and `MEDIA_STORAGE=s3` is **refused at config load** the
way `PUSH_TRANSPORT=fcm_apns` is — so a deployment cannot believe images are
landing in a bucket that does not exist. Ledger row **L13**.

### The production guard, which is the other half of the posture

🔧 The first pass copied only the refusal above, and the plan's answer
(2026-09-10) is that half a posture is a decorative seam. `EMAIL_TRANSPORT`
is *also* refused unless `ses` in production, and `MEDIA_STORAGE` now carries
the same rule: **`file` is refused in production.**

The two rules are unsatisfiable together today, and that is the point rather
than a mistake. Production cannot boot until the object store lands, which is
the honest signal — a local directory in production is worse than no images
at all, because they vanish on the next deploy and the provider who uploaded
them is never told.

It is deliberately **unlike `PUSH_TRANSPORT`**, which has no production rule
for the opposite reason: requiring an unbuilt transport there would make
production unbootable *without buying anything*, since §Phase 3c's email
fallback carries a notification when push cannot. Nothing carries a listing's
cover image if the store does not.

### The constraint this surfaced, which is not a workaround

A genuine presigned PUT means **the client uploads straight to the store and
the server never sees the bytes**. That is the point of it — a 10 MB photo
does not pass through the API — and it means content-type validation and EXIF
stripping *cannot happen during the upload*.

So an upload is three steps, and step 3 is where the guarantee is kept:

1. `POST …/media` — the server chooses the object key, records a `pending`
   row, hands back an expiring upload target.
2. The client PUTs the bytes to that URL.
3. `POST …/media/:id/complete` — the server **reads the object back**, sniffs
   its real type, checks its real size, strips its metadata and **rewrites it
   at the same key**.

Rewriting in place rather than to a second key is deliberate: there is no
window in which the store holds a copy that still carries the GPS
coordinates, and no orphan for a cleanup job to miss. Step 3 is identical for
a local directory and for S3, which is what makes the eventual swap a
transport change rather than a redesign.

`PUT /v1/media/uploads` and `GET /v1/media` exist **only** because this
process is currently playing the object store. Neither carries an auth guard,
and that is correct rather than an omission — the signed token *is* the
authorization, exactly as it is for an S3 presigned URL, which travels with no
AWS credential either. The token goes in the query string for the same reason
S3 puts its signature there, and because the logger already drops query
strings (`core/logging.ts`: "a query string may carry an email or a reference
code").

## 3. EXIF stripping is a container rewrite, not a re-encode

`modules/media/exif.ts` walks the JPEG segment list, the PNG chunk list and
the WEBP RIFF chunk list, and drops what carries metadata. It adds no
dependency.

Re-encoding the pixels would also drop the metadata and would need a native
image library — and it would recompress every photo a provider uploaded,
which is a visible quality loss applied to the one thing §Phase 8 says most
affects bookings. Walking the container removes exactly what must go and
leaves the compressed image data byte-identical.

What is **kept** is colour management, not metadata: JPEG's APP0 (JFIF), APP2
(ICC) and APP14 (Adobe), PNG's `gAMA` / `iCCP` / `sRGB`. Dropping those shifts
the colours of a provider's photo rather than protecting anybody. Everything
that can carry a location, a device, a name or free text goes — every other
`APPn`, `COM`, `eXIf`, `tEXt`/`zTXt`/`iTXt`, `tIME`, and WEBP's `EXIF` and
`XMP `.

Two details that are easy to get wrong and are tested for:

- **WEBP's `VP8X` flags are cleared, not just the chunks dropped.** A decoder
  that reads the EXIF flag and cannot find the chunk may treat the file as
  corrupt, so dropping without clearing produces an image some readers refuse
  — a subtler failure than not stripping at all. The RIFF size is rewritten
  for the same reason.
- **A container that cannot be walked is refused, not passed through.** An
  image whose structure is not understood is one whose metadata cannot be
  shown to be gone, and storing it would make the guarantee false without
  saying so.

## 4. The entitlement cap is a seam, and "1" is not a placeholder

§Phase 8's 🔧 note (decided 2026-09-10) is explicit, and this build followed
it exactly: `modules/listings/entitlements.ts` defines
`ProviderEntitlementReader` with **one method** — `activeListingCap` — and
`FREE_TIER_ONLY` returns §1b's free-tier cap of 1. No `ProviderSubscription`,
no trial, no pause, no grace, no tier.

The "1" is not standing in for a real answer. §1b sets the free tier at one
active listing and a provider with no subscription row is on it; until Phase
8a creates that table, **every** account is in exactly that state, so today
the free-tier value *is* the correct answer for everyone. Phase 8a replaces
the registration in `app.ts` with the live `getProviderEntitlements` read and
its callers do not change.

### The cap is enforced at publish, and at un-hiding

§Phase 8: "v1 checked the cap only at draft creation, so drafts made during a
trial could all be published after downgrade." So `createDraft` does not check
it — a provider may hold any number of drafts, which is what the wizard's own
over-limit sheet promises ("This draft is saved and isn't going anywhere").

**Publish is not the only door into the visible set**, so
`PATCH …/visibility` back to `active` re-checks it too. Without that, a
provider at the cap could hide one listing, publish another, un-hide the first
and hold two live.

### 🔧 A plan tension flagged, not resolved

**§Phase 9's last bullet says "Over-cap new-draft attempt shows an upgrade
prompt, not a generic error."** That needs a draft-creation cap that §Phase 8
is explicit about *not* building, and the Create Service prototype agrees with
§Phase 8 — its over-limit sheet fires at Publish. Enforced at publish only,
and raised here for whoever builds §Phase 9 rather than resolved silently in
either direction.

## 5. `COUNTS_AGAINST_CAP` is an alias, not a second predicate

The set the cap counts and the set the public sees are the **same three
clauses** — `status: 'published'`, `visibility: 'active'`, `deletedAt: null` —
so `COUNTS_AGAINST_CAP` is a one-line alias of `PUBLICLY_VISIBLE_LISTING`
rather than a copy. If they diverged, a provider could be over their cap with
nothing visible, or under it with two listings live. A test asserts the two
counts agree.

`PUBLICLY_VISIBLE_LISTING` is the listing-side twin of §1a's
`findVisibleProviders`: Phase 12's Service Preview, Phase 15's search and
Phase 16's Home all narrow **on top of** it, and none may restate the three
clauses. A consumer that writes `status: 'published'` on its own has already
lost the deleted case.

## 6. Ledger P5-1: the seam changed shape, and the loop is gone

P5-1 and `docs/decisions/17-phase-5-provider-profiles.md` decision 2 both
named the work: implement `PublishedListingSource` over the real table, fold
the predicate into the candidate query, drop the batch-accumulating loop.

`PublishedListingSource` was a batch lookup returning a `Set`, because a set
is all a fake can produce — and that is precisely why the page had to be
filled by scanning candidates 200 at a time. It is now **one method returning
a `Prisma.ProviderProfileWhereInput`**, so the whole rule (suspension, account
status, the caller's filters, the published-listing requirement) is one
indexed query with `take: limit + 1`.

Every caller of `findVisibleProviders` is unaffected, which is what decision 2
predicted. `FakeListings` survives — reshaped to `id IN (…)` — because a test
of the *visibility rule* should not have to build a publishable listing (six
required fields, a category, an island and an uploaded cover) to say "this
provider has one". `test/listings-visibility.test.ts` is where the same
assertions run against real published rows.

The Phase 5 test that asserted "asks the listing source in batches" was
guarding the loop, so it is replaced rather than kept: the property worth
guarding now is that a page is **full** even when most candidates fail the
rule.

## 7. Soft delete is a timestamp, not a third `ListingStatus`

`status` is the wizard's axis (`draft` / `published`); `deletedAt` is
orthogonal. A deleted listing that had been published must still read as
having been published — a booking or a review references it, and the record of
what a customer actually booked cannot become a draft.

### Cascade rules — what §Phase 8 asks to be documented

§Phase 8: "Soft-delete only; **document cascade rules** for a listing with
bookings, reviews, or reserved slots." Nothing here can be enforced yet —
there is no `Booking` until §Phase 17, no `Review` until §Phase 11 and no slot
until §Phase 9a — so this section is the specification those phases build to,
and ledger row **P8-2** carries the check.

**Nothing cascades. Deleting a listing changes exactly one column.**

| Related to a deleted listing | What happens | Why |
|---|---|---|
| The `Listing` row | `deletedAt` stamped. `status`, `visibility` and every field keep their values | Invariant 8, and the record of what was booked must stay legible |
| `ListingServiceArea` | Untouched | They describe where the service *was* offered; a booking's location resolves through them |
| `ListingMedia` and its objects | Untouched, in the store and in the database | A completed booking's history renders the listing as it looked |
| `ListingEvent` | Untouched | §1b's 90-day windows must stay computable across a deletion |
| **Bookings** (§Phase 17) | **Unaffected in every state.** A non-terminal booking runs to completion, keeps its chat, its payment attestation and its dispute path | A listing is the provider's to withdraw; a booking is an agreement between two people and the platform vouched for it (§1h). Cancelling live bookings because a provider tidied their dashboard is the platform breaking a commitment on their behalf |
| **Reviews** (§Phase 11) | **Unaffected, and still counted.** They stay attached to the listing and keep feeding §1f's provider conduct | Otherwise deleting a listing is a way to erase a bad record, which is exactly the pressure §1f exists to resist |
| **Reserved slots** (§Phase 9a) | Future *unreserved* slots stop being offered, because the listing has left `PUBLICLY_VISIBLE_LISTING` and no picker can reach it. **Reserved** slots stay reserved until their booking terminates | Same reasoning as bookings: the reservation is somebody's appointment |
| §1a provider visibility | Recomputed immediately, because the count is derived | No cache to invalidate — the deletion *is* the update |

The one thing a phase must **not** do is add a "block deletion while bookings
are open" rule. §1d's posture on account deletion is the model: the request is
accepted, and the consequences resolve as the bookings terminate. A refusal
would leave a provider unable to withdraw a listing they no longer offer.

## 8. Tags and FAQs are stored inline; media is a table

`tags` is `String[]` and `faqs` is `Json`. Neither has an identity of its own,
neither is referenced from anywhere, and the wizard edits each as a whole
step — so invariant 8's soft delete has no work to do, and a table would be
ceremony. The precedent in this schema is `Category.occasionPresets` and
`emergencyEtaPresetsMinutes`.

`ListingMedia` **is** a table, because an uploaded object has a real lifecycle
(pending → stored, ordered, replaced, removed) and invariant 8 has genuine
work to do: removing an image stamps the row and leaves the bytes, so a
booking that referenced the listing as it looked still resolves.

`faqs` is re-validated on the way out of the Json column rather than cast —
Zod checked it on the way in, but a hand-edited row or a future migration is
exactly the case a cast hides.

## 9. §1c's emergency rule is one function, called from three places

Round 17's own words: "Four fields across three entities gate emergency work
and no single place had put them together." `modules/listings/emergency.ts` is
that place, and publish, update and the tier-drop re-evaluation all call it.

It returns the **reason**, not a boolean, because every caller needs it:
the write paths turn it into a structured error, and §Phase 9's step 5 renders
the toggle "disabled with the reason shown". The own-listing DTO carries the
server's answer (`emergency.allowed` / `.reason` / `.requiredTier`) so the
client renders the server's explanation rather than recomputing the rule and
drifting from it.

A capable category with a **null** `emergencyMinimumTier` is refused rather
than treated as open. Refusing is the safe direction: the alternative admits
anyone to 2am work in a stranger's home because a column was left unset.

### The tier-drop re-evaluation has no caller yet, on purpose

§1c (Round 17): a downward tier change "re-checks every published listing with
`isEmergency: true`, clears the flag where the category's bar is no longer met,
and notifies the provider". Tier changes are §Phase 10a's verification queue,
which does not exist.

`reevaluateEmergencyEligibility` is built and tested here and called from no
route. It lives in this module because it is a rule *about listings*, and the
alternative is Phase 10a writing a second copy of the emergency gate — the
failure §1a's one-helper rule exists to prevent. **The notification is not
built**: §Phase 19 owns notifications and the copy is unspecified. Ledger row
**P8-3** carries both halves.

## 10. Where the routes live, and what is deliberately unclaimed

Everything is under **`/v1/providers/me/listings`**. That follows the
codebase's established split for an owner's own representation —
`GET /v1/providers/me`, `POST /v1/providers/me/service-areas`,
`PATCH /v1/users/me` — and it leaves **`/v1/listings/:id` unclaimed** for
§Phase 12's Service Preview and §Phase 15's search.

The alternative was one URL whose response shape depends on who is asking.
§Phase 5 declined that for providers (its own read is `/v1/providers/me`, the
public one is Phase 13's) and the same reasoning holds here: the owner's shape
carries `missingRequiredFields`, gallery upload states and the entitlement
answer, none of which a customer should receive.

🔧 **Four Phase 5 comments predicted `POST /v1/listings`** as §1a's implicit
profile-creation moment. The *moment* is unchanged — creating a draft creates
the profile — and all four comments now name the real URL.

## 11. The pricing/booking-mode rule bites on a published listing, not a draft

§Phase 8 says to "reject the combination at publish". `updateOwn` also
enforces it, but **only once the listing is published**: on a draft the two
fields are being filled in and a transient disagreement between step 3 and
step 5 is normal (invariant 2 — a draft saves with zero required fields).
On a live listing it would mean a customer reaching a bookable slot at an
unknown price.

`isEmergency` and the callback guarantee are different: §Phase 8 says
"enforced on publish **and** update" for the first, and both are *claims*
rather than omissions, so they are refused on any write. Changing the category
out from under an existing claim **clears** it rather than refusing the
category change — the provider is mid-edit and the claim, not the choice of
category, is what stopped being true.

## 12. A defect the tests caught: the rollup's boundary

The first `rollUp` used `occurred_at > watermark`. An event stamped at
**exactly** the previous run's `now` therefore fell outside every window that
would ever run and was lost permanently. The very first test that recorded
events and rolled up twice caught it.

The window is now half-open, `[watermark, now)`, and
`test/listings-events.test.ts` pins the boundary explicitly rather than
letting it be incidental.

## 13. A media row needs moderation visibility, not just soft delete

🔧 Added 2026-09-10 on the plan's answer. `photo` is one of §Phase 22's six
`Report.targetType` values, so an admin must be able to hide **a single
image** of a listing and put it back (§1d: moderation is always a status
flag, never a hard delete). Invariant 8's soft delete covers the *provider*
removing an image; it does not cover moderation.

`ListingMedia` therefore carries `hiddenByAdminAt` / `hiddenByAdminReason`
**alongside** `removedAt`, and the two must stay separate for exactly §1b's
reason for keeping `hidden_by_provider` and `hidden_by_admin` apart on a
listing: under one field the two cases are indistinguishable, and un-hiding a
moderated image would resurrect one the provider had deliberately taken down.

Three consequences, all tested:

- A moderated image **drops out of the gallery** — the listing stays up and
  the reported photo does not render.
- It **cannot be promoted to the cover**. That is the sharpest case: a
  provider answering a moderation decision by making the hidden photo their
  cover would put it back on every card and in every search result, the most
  visible place it could be.
- A listing whose **cover** is moderated becomes *incomplete* again rather
  than publishing with a blank thumbnail — which is the whole reason §0.2
  item 4 made the cover required.

Phase 8 owns the columns and the filter; §Phase 22 owns the action, its
required reason and its audit entry. Same split §Phase 5 used for
`ProviderProfile.suspendedAt`, so the tests here write the stamp directly and
assert that the rest of the module honours it.

## 14. `Category.suggestedTags` is this phase's column

🔧 Added 2026-09-10 on the plan's answer, and it comes out the opposite way
from `priceUnits` for a reason worth keeping: §Phase 9 requires
category-scoped tag chips, §Phase 9 is **frontend-only** and cannot add a
column, and the content is designed rather than invented — the prototype's
`TAGS` map covers all twelve categories and is the seed, transcribed verbatim.
Leaving it would have stopped Phase 9 mid-build over a missing column.

**The seed recomputes it on every run**, which is the *island* seed's pattern
rather than the category seed's. The category seed is create-if-absent
precisely because every number on a category is admin-editable from Phase
10b — but §Phase 10b enumerates those fields (name, icon, active, lead time,
accept window, ETA presets, both quote windows, `callbackEligible`) and this
is not among them, so there is no admin edit to revert. It is also necessary:
the twelve rows already exist from Phase 4, and create-if-absent would leave
every one of them with an empty chip list forever. `npm run db:seed` names
the categories it refreshed rather than counting them, so a run that rewrote
twelve is legible as such rather than as a silent upsert.

Suggestions only — a listing's own `tags` stay free text underneath the
chips, and nothing validates a tag against this list.

---

## What is deliberately not built

- **No public listing endpoint.** §Phase 12 owns the Service Preview page and
  §Phase 15 owns search; both map their own shape from
  `PUBLICLY_VISIBLE_LISTING`. Inventing one here would be guessing at what
  those screens show.
- **No view or booking recorder on a route.** The event log, the rollup and
  the counters are built and tested (§Phase 8's own bullet), but §Phase 12
  records the view and §Phase 17 the booking. `ListingEvents.record` is the
  seam they call.
- **Nothing from §Phase 8a.** No `ProviderSubscription`, no trial trigger, no
  pause, no downgrade sweep — 8a's triggers hook booking transitions §Phase 9a
  has not built, so they could not be tested.
- **No availability rules, slots or reservations.** §Phase 9a's. The listing
  carries the wizard's simple working window (`workingDays`,
  `workingHoursFrom/To`) and nothing more, which is what step 5 collects.
- **No service packages / tiered options.** Round 16 deferred them post-v1 and
  told the wizard to remove the section rather than ship a control that cannot
  be booked against.
- **No notification on the emergency re-evaluation** — §Phase 19's, and the
  copy is unspecified.

## What Phase 8a, 9, 10, 12 and 15 inherit

- **`ProviderEntitlementReader`** — Phase 8a replaces the body of
  `activeListingCap` with the live read. `FREE_TIER_ACTIVE_LISTING_CAP` is
  exported so 8a's own free-tier answer asserts against the same constant.
- **`PUBLICLY_VISIBLE_LISTING`** — the one predicate every public consumer
  composes. Never restate the three clauses.
- **`ListingEvents.record`** — Phase 12 records `view`, Phase 17 records
  `booking`. Neither should touch the counters.
- **`reevaluateEmergencyEligibility`** — Phase 10a's tier change calls it, and
  supplies the notification §1c asks for.
- **A listing's own service areas are what discovery matches on** (P7-3).
  `ProviderServiceArea` is the account-level default the wizard pre-fills
  from. Phase 15's island filter must read `ListingServiceArea`, and nothing
  may match on a name.
- **The wizard's over-cap moment is publish**, and the error names the listing
  already live so §Phase 9 can render the sheet the prototype draws.

## Deferred verification

Rows **P8-2** (cascade rules against real bookings, reviews and slots),
**P8-3** (the tier-drop re-evaluation wired to Phase 10a, with its
notification) and **L13** (a real object store) are added to
`docs/deferred-verification.md`; **P8-1** is the plan's own row for the
unbuilt per-category `priceUnit` narrowing (§1). Row **P5-1** is **closed** — the seam is
implemented over the real table and its assertions re-run against published
rows. Row **P7-3** is advanced but stays open: the two tables are separate and
proven not to touch each other, and what still needs §Phase 15 is that the
island *filter* reads the listing's set.
