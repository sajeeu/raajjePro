# Frontend — RaajjePro (Flutter)

Applies to everything under `frontend/`. The root `CLAUDE.md` and `01_Development_Plan_v5.md` still govern; this file adds the conventions specific to this app.

- Feature-based structure: `lib/features/<feature>/` with presentation, controller (Riverpod), and data layers. Shared widgets live in `lib/shared/`, cross-cutting concerns in `lib/core/`.
- Riverpod for all state. No `setState` for anything that outlives a single widget's local interaction.
- An `AsyncNotifierProvider` that renders its own error state must pass `retry: null` (or the shared no-retry function) — Riverpod 3's default retries a failed `build()` silently, with exponential backoff, for up to ~30s before the error UI ever shows.
- EVERY screen implements loading, empty, error and populated states. This is part of the screen's own definition of done, not a later QA pass. An empty state names what the user should do next; it never merely reports that nothing is there.
- Network failures degrade gracefully. Where a flow is marked offline-resilient — the service wizard, the provider accept prompt, chat sends — queue locally on failure, show a pending indicator, and replay on reconnect. Never silently discard user input.
- Optimistic updates roll back visibly on failure.
- Errors surface INLINE where the user can act on them, not as generic toasts. A field error belongs under its field.
- Accessibility is built in, not retrofitted: 48x48 minimum touch targets, visible focus states, semantic labels, and reduced-motion handling that degrades shimmer and transitions when the OS flag is set.
- Never hardcode a color, font, spacing value or radius. Use design tokens; add to them explicitly if genuinely missing.
- 🔧 **And never do arithmetic on a token** — `AppSpacing.sm + 2` is not a token, it is a literal with a token in it, and a reader cannot tell a considered value from a nudge. The scale names **every 2 dp step from 8 to 26** (`sm2` 10, `md2` 14, `lg2` 18, `xl2` 22, `xxl2` 26) precisely so you never need to. Corrected app-wide on 2026-09-14: 125 arithmetic sites across 44 files became named steps, changing no pixel. `test/shared/design_rules_test.dart` now allows **zero** — there is no value on screen a call site has to compute. A number the scale genuinely does not have is a *traced* one: 13 px appears 172 times across the artboards, which were drawn on a 1 dp grid and never had a spacing system. Those are named `AppSpacing.n13` and friends, and the `n` prefix is load-bearing — it says *measured off an artboard*, which is a different claim from `md`. Use one only when you are matching an artboard; never invent a new one.
- 🔧 **Content enters with `FadeUp`; it does not simply appear.** `motion.css` defines `fadeUp` (14 dp rise plus fade, `--m-page`, `--e-out`) and **52 of the 61 artboards use it, 194 times** — the app implemented none of it until 2026-09-14, which is most of why it read as rigid: the page transition landed and the content was just *there*. Wrap a screen's sections, and pass `index:` inside a list to stagger them the way `My Bookings` and `Discovery` do (`min(index, 6) * 30ms`). It is safe to wrap anything — under reduced motion it renders at rest on the first frame. One consequence to know: a geometry assertion must `pumpAndSettle` first, because during the entrance a child is painted up to 14 dp above where it lives.
- 🔧 **Stagger the rows a reader sees, never the boxes they sit in** (2026-09-15). This is the way the rule is got wrong, and it fails silently: `Profile` handed `FadeUpColumn` its two **containers** — a hero and a padded body — so the page had a real entrance of exactly two steps and arrived as one block. Nothing was broken, nothing failed, and the owner's report was "I don't see that in the profile page." `Explore` is the reference: twelve tiles, twelve steps. Hand the run the heading, the card, each row, the button. `fadeUpAll` and `FadeUpColumn` **skip gaps** — a `SizedBox` with no child takes no step — so a column of rows and spacers goes in as it stands, and `startIndex:` continues a run that began in an outer widget rather than restarting it. `test/shared/design_rules_test.dart` fails a screen with no entrance at all; only the screen's own test can catch a shallow one, so assert the indices there — `Profile`'s does.
- 🔧 **Consequential taps carry a haptic** (§Phase 1, owner's decision 2026-09-14). `AppHaptics.selection()` when a choice changes, `.commit()` when something lands that cannot be quietly undone, `.refused()` when the app says no — and nothing else, because a device that buzzes constantly gets ignored. Name the event, never the vibration. The shared toggles and the bottom nav already speak it, so a screen built from them inherits it; wire the other two at the moment the outcome is decided, not at the tap that requests it.

---

# Design System — source of truth

- Tokens are derived from the mockups and live in a Theme extension. Scattered constants are a defect. **Built in Phase 1:** `lib/core/theme/` (`AppColors`, `AppTypography`, `AppSpacing`/`AppRadius`/`AppSizes`, `AppMotion`, `CategoryAccents`) reached only through `context.colors`, `context.type`, `context.motion`. The shared widgets are in `lib/shared/` behind `package:raajjepro/shared/shared.dart`; the gallery at `/gallery` renders every one with sample data. `docs/decisions/08-phase-1-design-system.md` records what was decided and where the build departs from the prototypes.
- Every tappable thing is built on `Pressable` (`lib/shared/motion/pressable.dart`). It owns the 48 dp hit floor, the semantics, the focus ring and the tap-scale — do not hand-roll a `GestureDetector` for a control.
- 🔧 **A tappable card erases every control inside it** (2026-09-15). `Pressable` wraps its child in `Semantics(excludeSemantics: true)`, which is right — a card should announce as one thing, not as five nodes read out one at a time — but it is **total**. §Phase 10's service card was made tappable and its overflow menu, its live toggle and its Finish & publish button vanished from the semantics tree together, leaving a screen-reader user a summary and no controls. Nothing failed; a test finder that could not locate the menu is what exposed it. **So a card that holds a control is a container, and the tap belongs to the controls inside it** — which is what the artboards draw anyway. `expectNoSwallowedControls(tester)` (`test/helpers/a11y.dart`) is the guard; call it after pumping any screen with a card, and never suppress it by moving the label.
- `AppHeader` goes at the top of the **body**, never in `Scaffold.appBar`: a `PreferredSizeWidget` has a fixed height and clips a two-line title at 200% text.
- `StatusBadge` owns the status → label mapping and `VerificationBadge` owns the tier copy. Duplicating either into a screen is a defect (same rule as `StatusPill` / `VerificationBadge` in the prototypes).
- A metric with no data reads **"No data yet"** (`StatMiniCard` with `value: null`), never a zero. Three stat tiles across go through `StatMiniCardRow`, which sheds columns as text grows.
- Tests run in the real Inter face and Material Icons via `test/flutter_test_config.dart`. Do not use `pumpAndSettle` on a screen showing a skeleton or a loading button — those animate forever by design; pump two frames instead (`test/features/gallery/gallery_a11y_test.dart` → `settle`).
- Component states are explicit and complete: buttons carry pressed, disabled and loading; inputs carry normal, focused, error and disabled.
- A button that triggers a network call shows ITS OWN loading state. Do not cover the screen with a page-level spinner for a local action.
- Skeleton loaders for content that is fetching; not spinners, and not a blank screen.
- Verification tier badges are three distinct treatments (Bronze/Silver/Gold), each carrying the exact public copy from the plan's §1e: "ID checked by RaajjePro" / "ID checked, work verified" / "ID checked, registered trade". NEVER render a bare "Verified" — a customer may read that as "has a good track record" rather than "passed an ID and trade check".
- Booking-mode affordances appear on every card and listing surface: 🔧 **"Pick a time"** (slot — Round 44; it was "Book instantly", which named an immediacy the state machine does not produce, since a slot booking is still a `requested` booking the provider has to accept) and **"Request a time"** (request). A customer must never be uncertain which kind of wait they are in.
- 🔧 **There is no "Emergency available" marker on a card, and no emergency search filter — Round 23.** Dispatch never targets a provider, so both advertised an action that does not exist. The card's second signal is mode-appropriate instead: next open time for `slot`, median response time for `request`. The callback guarantee is the card badge. Emergency is reached from its own entry on Home and Explore.
- Where a mockup predates the current plan, THE PLAN WINS and you flag the mismatch — do not silently implement the mockup.

---

# Testing

- Every business rule gets a test asserting the rule, not the implementation. A test that would pass against a wrong implementation is not a test.
- Concurrency is tested explicitly wherever the plan names it: simultaneous slot booking, cross-listing overlap on one provider, 1,000 concurrent attempts asserting zero double-books, simultaneous admin confirmation, repeated idempotent POSTs.
- State machines are tested at their boundaries — the transition that should be rejected matters more than the one that should succeed.
- Scheduled jobs are tested by advancing time, not by waiting.
- Authorization tests cover reads as well as writes, and cover the wrong-user case, not just the unauthenticated one.
- Any endpoint touching a phone number is tested for its ABSENCE in the response, not only for the presence of what it should return.
- Registration is tested against both a duplicate email and a duplicate phone, asserting each is blocked with a message naming the specific field.

---

# Design tokens — extracted from the delivered designs

🔧 **These are measured values, not proposals** — but measured from **one** prototype, `Become a Provider.dc.html`, back when five existed. There are now **61**, and the corpus is wider than this section says. Colours and motion still hold. **Type and radii do not** — see the corrections below each.

Phase 1's job was to derive a real token set from all 61, not to transliterate the numbers here. Where this file and the prototypes disagree, measure the prototypes.

🔧 **Phase 1 did that, and seven measured colours failed the plan's WCAG AA bar.** `test/core/theme/contrast_test.dart` computes every text/surface pair. Placeholder `#9AA9C0` is 2.38:1; the warning amber `#D97706` is 3.19:1 as text (fine as an icon or dot); success `#16A34A` is 3.30:1 as text; `#8296B3` is 3.02:1 and is permitted **only on disabled controls**. The corrected values, with ratios, are in `docs/decisions/08-phase-1-design-system.md`, and `docs/design/sessions/round-53-contrast-corrections.md` carries them back to the prototypes. Until that round is applied, where the colour table below and `AppColors` disagree, **`AppColors` is right**.

**`Become a Provider.dc.html` is the highest-fidelity reference in the repo.** It carries interaction detail no image can: which field shows which error text, when a CTA disables, how long a transition runs. When implementing a screen it covers, read it rather than the JPEGs.

## Colour

| Role | Value |
|---|---|
| Primary | `#2563EB` · pressed `#1D4ED8` · gradient `#5B8DF6 → #2563EB 60% → #1D4ED8` |
| Ink | `#0F1B2D` |
| Secondary text | `#5B6B84` · tertiary `#41526B` |
| Placeholder | `#9AA9C0` |
| Page background | `#F2F6FB` · outer frame `#DEE7F3` |
| Surface | `#FFFFFF` |
| Border | `#E3EAF3` · subtle divider `#EEF3FA` / `#F0F4FA` |
| Accent tint | `#E8F0FE` · border `#CDDDFB` |
| Success | `#16A34A` · tint `#E5F6EC` |
| Error | `#DC2626` |
| Warning | `#D97706` · tint `#FEF3DC` |
| Disabled fill | `#C6D4EA` · disabled text `#8296B3` |

## Type — Inter

🔧 **Corrected against all 61 prototypes.** The list above was measured from one file and is wrong on both axes.

**Weights actually used:** `500` (28×), `600` (543×), `700` (616×), **`750` (37×)**, `800` (674×). The old claim of "600 · 700 · 800 only — nothing lighter than semibold" is wrong twice: 500 appears, and so does 750.

⚠️ **`750` has no Flutter equivalent.** `FontWeight` is defined in hundreds — there is no `w750`. Inter is a variable font so it renders on the web, but the 37 uses across 12 screens must resolve to `w700` or `w800`. **Pick one, apply it everywhere, and record the choice** — do not let each screen decide. 🔧 **Chosen in Phase 1: `w700`**, as `AppTypography.sectionHeading` — it keeps a section heading visibly lighter than the 800 screen title above it. Four static weights (500–800) are **bundled** in `assets/fonts/`, never fetched at runtime.

**Sizes:** 34 distinct values are in use, from 8.5 to 44. That is not a scale, it is the residue of 61 hand-built screens, and Phase 1 should rationalise rather than reproduce it. The nine that carry the type system are, by frequency:

| px | uses | | px | uses |
|---|---|---|---|---|
| 12.5 | 319 | | 14 | 178 |
| 13 | 235 | | 15 | 145 |
| 13.5 | 207 | | 11 | 134 |
| 11.5 | 198 | | 14.5 | 130 |
| 12 | 182 | | | |

Everything above 16px is a heading or a display number and appears in single or double digits.

🔧 **Phase 1's roles** (`AppTypography`): screenTitle 25/800 · sectionHeading 17/700 · cardTitle 15/700 · body 14/500 · bodyStrong 14/600 · secondary 12.5/600 · caption 11.5/600 · overline 11/800 +.06em · button 15/700 · buttonSmall 13.5/700 · price 16/800 tabular · stat 18/800 tabular · pill 11.5/800. Use a role; do not reach for a size.

Headings carry `letter-spacing: -.02em`; uppercase labels carry `+.06em`. **The font is Inter, and only Inter** — §Phase 1 writes "Plus Jakarta Sans / Inter", but all 61 prototypes load `family=Inter` and the word Jakarta appears in no prototype, no design document and no token file.

## Geometry

- **Radii**, 🔧 by frequency across all 61: **20** (289×, cards) · **16** (205×, buttons and cards) · **`999`** (176×, pills) · **14** (150×, inputs) · **12** (84×) · **13** (74×) · **24** (44×, feature cards) · **18** (42×) · **8** and **10** (40× each) · **28** (bottom sheets). The one-file list omitted 13, 18 and 8 and understated how dominant 20 is.
- **Heights:** 52 inputs · 54 primary CTA · 44 touch targets and icon buttons · 38 filter chips · 26 checkboxes
- **Borders:** `1px` dividers, `1.5px` inputs and selectable cards, `2px` selected states

## Motion

🔧 **Round 40 replaced the per-animation durations with a four-step scale.** Build the Flutter side from the scale, not from the old literals — `mockups/design-composer/motion.css` is the live definition.

| Token | Duration | Used for |
|---|---|---|
| `--m-fast` | **120ms** | hover, press, colour, border |
| `--m-base` | **200ms** | in-place change, content swap, sheet OUT |
| `--m-sheet` | **300ms** | sheets, overlays, dialogs IN |
| `--m-page` | **350ms** | page and view transitions |

Two curves only: `--e-out` `cubic-bezier(.2,.8,.3,1)` for entering and settling, `--e-in` `cubic-bezier(.4,0,1,1)` for leaving. Infinite loops keep literal durations by convention — shimmer 1.4s, spinner .7s/.8s — because they are ambient rather than a response to a tap.

🔧 **These are web idioms and must not be transliterated.** `100dvh`, CSS gradients, `box-shadow` and `overflow-y:auto` all have Flutter equivalents, but copying them literally produces something that feels like a website in an app. Match the *values*; use Flutter's own elevation, scroll physics and page transitions.
