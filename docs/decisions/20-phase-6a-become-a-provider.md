# Phase 6a — Become a Provider: the onboarding flow

Built 2026-09-10 against `01_Development_Plan_v5.md` §Phase 6a, §1a, §1e and
the artboard `mockups/design-composer/Become a Provider.dc.html`. What follows
is what was decided during the build and why, in the order the decisions were
forced. The plan is the source; this file records the places it left a choice.

---

## 1. The plan's own Done-when needed a signal that did not exist

§Phase 6a ends on two lines that pull in opposite directions unless something
finer than `isProvider` exists:

> A provider who abandons onboarding **after step 1 or 2** (backs out, closes
> the app) and returns later **resumes from wherever they left off**.

> a provider who **already completed onboarding** never sees it again, going
> straight to the dashboard or a resumed draft instead.

§Phase 6 built the role switcher on `isProvider` — `providerProfile !== null`
— and that was right for what Phase 6 could see. It is not enough here,
because **onboarding's step 2 is §1a's profile-creation moment**. `isProvider`
therefore flips one step before the flow ends, and a provider who closed the
app on step 3 read as a returning provider: the switcher sent them to a
dashboard and they never saw the step they had stopped on. That is the
opposite of the resume line.

**Decision: derive "has this account completed onboarding?" server-side, and
route on that.** `backend/src/modules/providers/onboarding.ts` is the one
definition — the fields §Phase 6a's three steps collect, plus the verified
email §Phase 5 requires to finish:

| Input | Which step, and why it counts |
|---|---|
| `businessName` | Step 2, "About you", required there |
| `providerType` | Step 2, required. Null means *not yet asked* — §1e reads it to decide whether Gold review wants personal ID or a business registration, so a default would decide which documents a provider is later made to produce |
| `bankName`, `bankAccountName`, `bankAccountNumber` | Step 2, "Getting paid", all required. §1b never moves money for a booking, so a listing published without a destination account is a service nobody can pay for |
| ≥ 1 `ProviderServiceArea` | Step 3. Its CTA is disabled with none chosen, so this is what tells "stopped here" from "finished" |
| `User.emailVerifiedAt` | §Phase 5: "required to complete Phase 6a's provider onboarding" |

It is exposed twice from that one definition — `providerOnboardingComplete` on
`GET /v1/users/me/profile-summary` (which §Phase 6 designed as *one* call for
the Profile screen, so the switcher pays no extra request) and
`onboardingComplete` on `GET /v1/providers/me`. `isProvider` is unchanged and
still answers its own, different question.

**Nothing stores it**, for the same reason §1a stores no visibility flag: a
stored boolean is a copy of five fields that drifts the first time one is
cleared. `phase6a-onboarding.test.ts` asserts `information_schema` holds no
`provider_profile` column matching `/onboard/i`, and asserts the flag reopens
when the last service area is removed.

🔧 **The reopening cuts both ways, and the QA review was right to name it.**
The flag is **not monotonic**: five of its seven inputs are legally editable
(the three bank fields are `.nullable()` on `updateOwnProviderBody`), so a
provider who later clears one — or removes their last account-level island —
reads incomplete again and is routed back into a flow whose terminal CTA hands
off to a *fresh* wizard draft. For a provider who has not finished, that is
the behaviour §Phase 6a asks for. For one with published listings it
contradicts "never sees it again".

It is latent today: nothing outside this flow edits those fields, so no
shipped surface can reach it. Derived-not-stored is still the right shape —
a stored flag goes stale on exactly the same edits, and §1a's reasoning
applies unchanged. What this phase cannot settle is the rule for a provider
who is already trading, because `PublishedListingSource` is a seam until
Phase 8 and the switcher has no way to ask. **Ledger row P6A-3** carries it to
whichever of Phases 9 and 10 first builds a surface that can clear one of
these fields.

### Flagged: this is a reading of §Phase 6's wording, not a transcription

§Phase 6 says "a returning provider goes straight to My Services Dashboard"
and its Done-when says "on every subsequent switch". Read at its most literal,
a provider who abandoned at step 3 and switched again is making a subsequent
switch and should get the dashboard. Read that way, §Phase 6a's resume line is
unimplementable.

Taken as: **§Phase 6a's "already completed onboarding" is the operative test,
and §Phase 6's "returning provider" means someone who has been through the
flow** — a person mid-flow has not returned yet. §Phase 6a is the later and
more specific section, and it is the phase whose Done-when this is.

**The plan's §Phase 6 wording is what should change**, to "a provider who has
completed onboarding goes straight to My Services Dashboard". It has not been
changed here; the plan is amended by its owner, not by a phase.

---

## 2. The verified-email gate lives in the completeness rule, not on an endpoint

§Phase 6a: "**Unverified blocks Continue** with its own message, since booking
notifications go there." Invariant 4 says the backend is the single source of
truth, so a client-only block would be the rule's only home.

The obvious server-side answer was `requireEmailVerified` on
`PATCH /v1/providers/me`. **Rejected**: that endpoint is also §Phase 10a's
billing surface and every later provider-profile edit, and §1a says dashboard
access is never gated — editing your own bio is not booking, enquiring or
messaging, which is what §1c's stricter guard exists for. Gating it would have
made an unverified provider unable to correct their own bank details.

So the rule is enforced where the rule actually is: an unverified account can
write its own profile fields and is **not onboarded** until the address those
notifications go to is confirmed. The block on Continue is the client's, the
consequence is the server's, and an API client that skips the UI reaches the
same answer. Both are tested.

It cannot silently reverse: `POST /v1/users/me/change-email/confirm` writes the
new address and `emailVerifiedAt` in the same update, so no verified account
passes back through an unverified state and no provider is dragged into
onboarding by changing their email.

---

## 3. Step 2 submits on Continue and does not autosave

`wizard-step-pattern` says every step's `onChange` triggers a debounced PATCH.
This step deliberately does not, and the reason is specific to it: **the first
write is what creates the provider profile.** `isProvider` is
`providerProfile !== null`, nothing is ever hard-deleted (invariant 8), and
§Phase 6's switcher routes on the family of signals behind it — so autosaving
would turn a customer who typed one character into a provider permanently.
That is exactly the failure `17-phase-5-provider-profiles.md` decision 11 was
written to close, one screen earlier in the funnel.

The artboard agrees: step 2 has a single Continue with a "Setting up your
profile…" state on it, not a per-field save indicator.

That rule stays for §Phase 9's wizard, where it belongs — there the draft
listing already exists and a PATCH creates nothing.

**The consequence, and the one place it was not acceptable:** an abandon
*midway through typing* step 2 loses what was typed, and the plan's resume line
covers it only at step granularity ("after step 1 or 2"). Resuming re-opens
step 2 pre-filled from the server, which is empty for a first-timer. That is
the normal cost of not creating an account-level flag on a keystroke.

It was **not** acceptable on the one path this screen sends the provider down
itself. §Phase 6a requires the unverified-email block to carry the way out of
it, and Phase 3's Verify Email screen finishes with
`pushNamedAndRemoveUntil` back to the root — so tapping the button this step
provides emptied the form. `saveDraft` / `takeDraft` put the typed values
through `FormDraftStore`, which is Phase 3's own mechanism for the same class
of problem: **in memory, this session only, never written to disk and never
logged**, which is what makes it acceptable for the destination account under
§1d. It is consumed on read, so a provider who abandons instead gets a clean
form next time. Found by the QA review.

---

## 4. Resume is derived from the server; nothing is cached on the device

The plan says the resume "reuses Phase 9's existing resume-a-draft logic
pattern, applied one level earlier in the funnel". Phase 9's pattern is a draft
that lives on the server — so here **the provider profile is the draft**:

- No profile at all (`PROVIDER_PROFILE_NOT_FOUND`) → **step 1**. Expected, not
  an error: §Phase 5 moved creation onto the write.
- Profile with step 2's required fields incomplete → **step 2**, pre-filled.
  This also covers §1a's implicit path — a provider-variant registration, or
  someone who reached §Phase 8's wizard first, has a business name and nothing
  else.
- Step 2 complete, no service area → **step 3**. The state the plan's resume
  line is really about.

Step 3's picks write straight through §Phase 7's endpoints on every tap, which
is what makes resuming there work with no local draft to reconcile.

---

## 5. `providerType` is not on the public shape

§Phase 6a gives the new field two jobs and neither is customer-facing: it
decides what §1e's Gold review asks for, and it is what §1g's Maldivian-owned
**business** attribute hangs from. So it is on `OwnProviderDto` and the data
export, and **not** on `PublicProviderDto`. §Phase 13 owns the public profile
and can add it there additively if that screen turns out to want it.

It is also the one key in `updateOwnProviderBody` that is **not** nullable,
against that file's stated "clearing a field is a real edit" convention.
Clearing a bio returns a provider to a state they were legitimately in; there
is no "no type" to go back to. The column is nullable only because §1a's
implicit path creates a profile before anybody has been asked.

---

## 6. Four departures from the artboard, each deliberate

**The bank list has no "Other" and no free-text escape — flagged, not fixed.**
The artboard's `<select>` offers seven Maldivian banks and nothing else, the
plan names no bank register, and §Phase 6a says the three payment fields are
all required. A provider banking somewhere unlisted therefore cannot finish
this step. Inventing an option would be inventing product;
`ProviderProfile.transferInstructions` (§Phase 5's "and/or other transfer
instructions") is the field a design round would most likely reach for. The
list is built as drawn, and this is the gap the next design round should close.

**The photo or logo control is drawn and wired to nothing** (`InertControl`,
owed by Phase 8). `User` has no avatar column, `ProviderProfile` has no logo
column, and media upload via presigned URL with content-type validation and
EXIF stripping is §Phase 8's deliverable — building storage here would invent a
retention and bucket policy the plan does not specify. Phase 6 set this
precedent for the same control on Profile, and §Phase 6a marks the photo
optional, so nothing is blocked.

**The atoll filter chips on step 3 are not implemented.** They would be a
second way to narrow the same set: §Phase 7 built `IslandMultiSelect` as *the*
reusable control and the server already matches the atoll code inside the
search field (`gdh` lists that atoll, `dh mee` finds `Dh. Meedhoo`). Adding
chips would also mean changing shared Phase 7 code, which invariant 5 says to
flag rather than do as a side effect.

**"Verified" beside the email reads "Email verified".** `design_rules_test.dart`
bans the bare word in `lib/`, and it is right to: §1e's badge is three
treatments with their own copy and a lone "Verified" anywhere in this app risks
reading as that. Naming what was actually checked is more truthful too — the
row directly above it holds a phone number nothing has verified.

The artboard's "Sample list — the live app has every inhabited island"
footnote is not implemented either, for the reason Phase 7 already recorded:
it explains a 19-island stand-in that does not exist here, and §0.0 item 12
forbids an island total in UI copy.

---

## 7. Three shared files changed, and all three are flagged

Invariant 5 forbids refactoring unrelated modules as a side effect.
`lib/README.md` states the countervailing rule — "a widget that a second
feature needs moves to `shared/`; it is not copied" — which is what Phase 6 did
for `SettingsRow` and `InertControl`. These are that move, not a refactor:

- **`PhoneField` → `shared/inputs/`.** §Phase 6a's `editingPhone` state is
  exactly this dial-code-plus-number pair, and it now has three consumers
  (Register, Change phone, onboarding).
- **`genericErrorCopy` → `shared/feedback/`.** Third consumer, one string, and
  the alternative was a fourth copy of it.
- **`AppTextField` gained `requirement`**, drawing the Required/Optional pill
  on the label row and appending the word to the spoken label. Every form in
  the delivered prototypes marks its fields this way and §Phase 9's wizard
  renders the same pills, so the copy and the two tints belong in Phase 1
  rather than in either screen. `FieldRequirementPill` is exported for the
  controls that are not text fields.

The step-2 form was also split so that `account_details_step.dart` holds no
mention of notifications: `no_booking_notification_toggle_test.dart` greps for
a file containing both a toggle and the word, and the availability toggle sat
in the same file as the email row's copy. Splitting satisfied the tripwire
without weakening it — the alternative was narrowing a grep that exists to be
blunt.

---

## 8. What the QA review changed

The contract review ran against the finished phase and found nine defects.
Two were behavioural and are fixed:

- **Resume could reach step 3 with the email unverified**, because
  `_accountDetailsDone` deliberately excludes the email and step 3 carries no
  notice. A provider in that state would have seen "Your provider profile is
  ready" and been handed to the wizard while the server said otherwise, then
  been routed back with nothing on screen explaining why. `_resumeStep` now
  takes `emailVerified` and returns step 2 — which makes step 2 the single
  place the rule is enforced client-side, since step 3 is unreachable except
  through a Continue that validates it.
- **Leaving to verify the email destroyed the step-2 form.** Phase 3's Verify
  Email screen finishes with `pushNamedAndRemoveUntil` back to the root, so
  the whole stack goes and step 2 does not autosave. `saveDraft`/`takeDraft`
  now put the typed values through `FormDraftStore` — Phase 3's own mechanism
  for this, in memory and this session only — so the affordance §Phase 6a
  requires the block to carry no longer costs the provider their form.

Five smaller ones: the client's account-number rules were **narrower than the
server's** in the direction Round 17 argues against (digits-only, 16 max,
min 7 against the server's 4–40 with spaces and dashes), so a foreign account
could not be typed; the offline notice **claimed "nothing was saved"** when a
successful phone change followed by a failed profile write means something
was; `toOwnProviderDto`'s last two parameters had **fail-closed defaults**
that would have silently returned `onboardingComplete: false`; `/verify-email`
existed as **two independent literals** and is now defined once in
`core/routes.dart`; and `providers/routes.ts` still **told the next builder to
route on `isProvider`**, which is the advice this phase superseded — in a
repository with five recorded drift failures, that is the comment that causes
the sixth.

Two were documentation: a comment claimed the screen checks `onboardingComplete`
on direct open, which it does not (deliberately — there is no deep link, and a
redirect would be a second place the rule is acted on), and the rewritten
P6-1 ledger row had lost its closing table pipe.

The ninth is decision 1's non-monotonicity, above, now **P6A-3**.

---

## 9. What this phase did not build

- **No new endpoint.** §Phase 6a says "reuse Phase 5's existing update
  endpoint, do not create a parallel one", and the flow makes exactly three
  kinds of call: `PATCH /v1/providers/me` (Phase 5),
  `PATCH /v1/users/me/phone` (Phase 3, for the phone half its Done-when
  misattributes) and §Phase 7's service-area writes. A test asserts that
  `/v1/providers/me/onboarding` and two plausible siblings 404.
- **No Home CTA.** §Phase 6a's Done-when names "Home's 'Become a Provider'
  CTA or Phase 6's role switcher". §Phase 16 builds the Home feed; the
  switcher is the entry that exists, and ledger row **P6A-1** holds the other.
- **No wizard.** `/services/new` is registered and lands on `UnbuiltScreen`
  owed by Phase 9. The handoff is built and asserted; the screen behind it is
  not.

---

## Deferred verification

Rows **P6A-1** and **P6A-2** in `docs/deferred-verification.md`. Ledger row
**P6-1**'s Phase 6a half is closed by this phase — the role switcher's first
switch now lands on the real intro screen rather than a placeholder — and the
row stays open for §Phase 10's half.
