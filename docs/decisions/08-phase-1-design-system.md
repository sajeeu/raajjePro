# Phase 1 — the design system, and where it departs from the prototypes

**Status: built 2026-09-05. Plan revision 5.19, §Phase 1.**

Phase 1 turns the measured tokens in `frontend/CLAUDE.md` into a Flutter theme and the shared widgets §Phase 1 lists. Three decisions the plan left open were put to the product owner, and a set of colour values measured from the prototypes were changed because they failed the plan's own accessibility bar. Both are recorded here so nobody later "restores" a prototype value without knowing why it moved.

## Three decisions, answered

**Inter only.** §Phase 1 names the typography as "Plus Jakarta Sans / Inter". Every one of the 61 prototypes, the style guide and the measured token sheet use Inter alone, at weights 500–800. The slash was read as *either*, and Inter chosen so the app matches the design references. Four weights are bundled (`frontend/assets/fonts/`, OFL); nothing lighter than Medium exists in the build, so a style asking for w400 falls back to 500 — the rule enforces itself. §6's note that a Thaana face will be needed later stands.

**Scope: the plan's list plus the verification badge, text input, toggle and avatar.** §Phase 1 lists buttons, `AppCard`, `StatusBadge`, chips, `StatMiniCard`, `RatingStars`, `AnimatedBottomNav`, `AppHeader`, `SaveHeartToggle`, `EmptyState`, `SkeletonLoader` and the bottom-sheet shell. Four more are built:

- **`VerificationBadge`**, with the `VerificationTier` enum under it. It is not in §Phase 1's list but it is one of the seven component files the prototypes import, `frontend/CLAUDE.md` requires the three-tier treatment with the exact §1e copy, and root `CLAUDE.md` invariant 1a forbids a bare "Verified" — the copy has to live in exactly one place before any screen renders it. Built here so Phase 5 and later cannot each define it.
- **`AppTextField`, `AppToggle`, `AppAvatar`** — from the style guide's component table, put to the product owner and approved. Their tokens were already measured, and Phase 3's Login and Register would otherwise define an input ad hoc.

`AppSpinner` exists as the loading indicator inside `AppButton`; it is a support piece, not a component in its own right. **Toast is not built**: the style guide says never to use one for an error that needs action, and no phase yet needs one for anything else.

**The gallery is a plain named route, linked from Home only in debug builds.** The plan says "component gallery route" and names no router. Adding `go_router` now would be building ahead; `MaterialApp.routes` with `/gallery` is enough until a phase needs more. The route exists in every build; the link to it does not.

## What was built

| Plan item | Widget | File |
|---|---|---|
| Theme tokens | `AppColors`, `AppTypography` (ThemeExtensions), `AppSpacing`/`AppRadius`/`AppSizes`, `AppMotion`, `CategoryAccents` | `lib/core/theme/` |
| Buttons | `AppButton` — primary · secondary · text · destructive × default · pressed · disabled · loading | `lib/shared/buttons/` |
| `AppCard` | plain · tappable · selected · `AppCard.row` | `lib/shared/cards/` |
| `StatusBadge` | the twelve `StatusPill` statuses plus draft · hidden · published; labels live here | `lib/shared/badges/` |
| Chips | `AppChip.filter` · `.input` · `.label` | `lib/shared/chips/` |
| `StatMiniCard` | plus `StatMiniCardRow`, which sheds columns as text grows | `lib/shared/cards/` |
| `RatingStars` | `.compact` · `.row` · `.input` | `lib/shared/rating/` |
| `AnimatedBottomNav` | sliding pill; tab set supplied by the screen | `lib/shared/navigation/` |
| `AppHeader` | `.brand` · `.page`, with `AppHeaderAction` | `lib/shared/headers/` |
| `SaveHeartToggle` | overlay · flat | `lib/shared/toggles/` |
| `EmptyState` | plus `EmptyState.error` with retry | `lib/shared/states/` |
| `SkeletonLoader` | shimmer scope, `SkeletonBox`, `SkeletonRow`, `.rows()` | `lib/shared/states/` |
| Bottom-sheet shell | `AppBottomSheet` + `showAppBottomSheet` | `lib/shared/sheets/` |
| Motion primitives | tap-scale (in `Pressable`), spring sheet (`showAppBottomSheet`), animated nav pill; page transition in `AppTheme` | `lib/shared/motion/`, `lib/core/theme/app_theme.dart` |
| Added by decision | `VerificationBadge` (+ `VerificationTier`), `AppTextField`, `AppToggle`, `AppAvatar`; `AppSpinner` in support | `lib/shared/badges/`, `lib/core/domain/`, `inputs/`, `toggles/`, `avatar/`, `feedback/` |
| Gallery | `GalleryScreen` at `/gallery`, with RTL · 200% · reduced-motion switches | `lib/features/gallery/` |

`Pressable` is the one interaction base under every control. It owns the 48 dp floor, the semantics (button or toggle, labelled, enabled state, focusable), the focus ring and the tap-scale — so no widget can forget one of them.

**The card-shaped skeletons are not here.** `SkeletonCard.dc.html` has a 250 × 330 horizontal and a 188-high full variant that mirror `ServiceCard`. A skeleton must be built beside the card it stands in for or the two drift, and the listing card belongs to Phases 15–16. The row skeleton and the primitives are here.

## Where the build departs from the prototypes — accessibility

The plan makes WCAG AA contrast "non-negotiable and built in here", naming amber-on-white as the case to watch. `test/core/theme/contrast_test.dart` computes every text-on-surface pair and fails under 4.5:1 (3:1 for non-text graphics). Seven measured values did not clear it. Each moved to the nearest value on the same scale the designer was using, and the test pins the result.

| Token | Measured | Ratio | Now | Ratio | Why |
|---|---|---|---|---|---|
| placeholder text | `#9AA9C0` | 2.38 on white | `#627187` | 4.96 white · 4.57 page | a placeholder is text |
| warning **text** | `#D97706` | 3.19 on white | `#A15C00` | 5.19 white · 4.71 tint | `StatusPill` already used this; `#D97706` stays as the icon/dot amber |
| success **text** | `#16A34A` | 3.30 on white | `#166534` | 6.36 on tint | `#16A34A` stays as the icon/dot green |
| inactive nav label | `#8296B3` | 3.02 on white | `#5B6B84` | 5.41 | an inactive tab is live, not disabled |
| rating star stroke (filled) | `#D99A1E` | 2.44 | `#B45309` | 5.02 | the stroke is what separates filled from empty |
| rating star (empty) | `#C6D4EA` | 1.60 | `#8296B3` | 3.02 | graphic bar is 3:1 |
| Home Repairs icon | `#CA8A04` on `#FEFCE8` | 2.84 | `#A16207` | 4.76 | the only category glyph under 3:1 on its tint |

Two further changes of the same kind:

- **Category label text.** The prototypes set a card's category label in the category's icon hue; Electrical (`#D97706`, 3.19) and Home Repairs (`#CA8A04`, 2.94) fail as text. Each accent now carries a `text` colour one step darker on the same Tailwind scale (indigo-700, amber-800, …), all ≥ 4.5 on white and on the tint. Icons keep the measured hue.
- **The CTA gradient's middle stop moved from 60% to 40%.** With the light end `#5B8DF6` reaching primary only at 60%, white text at the label's leading edge sat on ~4.1:1. At 40% every point a centred label can reach is ≥ 4.5. The three colours are unchanged.

`#8296B3` remains as `disabledText`, for disabled controls only — WCAG 1.4.3 exempts inactive components, and the test pins it *below* 4.5 so it can never be promoted to a live-text role by accident.

**These go back to the design project as a correction round**, `docs/design/sessions/round-53-contrast-corrections.md`, so the prototypes and the app agree. Until that round is applied the prototypes are the ones that are wrong.

## Where the build departs from the prototypes — layout

- **The header is not a `PreferredSizeWidget`.** `Scaffold.appBar` gives its child a fixed height; at 200% text a two-line title was clipped, and the gallery test caught it. `AppHeader` is placed at the top of the body and sizes to its content.
- **Avatar initials do not follow the OS text scale.** They are an identity glyph sized to a fixed disc; at 200% "MS" wrapped to two lines inside a 52 dp circle. The name is in the semantics label and scales wherever it is written out. The tier overlay's ◆ is treated the same way.
- **Bottom-nav labels scale to at most 1.3×.** Five tabs on a phone leave ~70 dp each; at 2× "Bookings" laid out as "Bookin / gs" — not clipped, so the clipping audit could not see it. The label is clamped and held to one line; the icon, the 48 dp target and the spoken label scale and read normally. A word-break audit (`auditWordBreaks`) now fails the suite if any single-word paragraph anywhere in the gallery wraps.
- **Stat tiles reflow.** Three tiles across a phone break `1,284` into `1,28` / `4` at 200%. `StatMiniCardRow` computes columns from the scaled minimum tile width — three at 100%, two around 150%, one at 200% — and a number never wraps.
- **The input chip is one control.** A separate 48 dp × cannot live inside a 38 dp pill; the whole chip removes on tap and is announced "Remove Hulhumalé". The × is the affordance.
- **Chips and buttons hug their content.** A `Container` with `alignment:` set expands to fill its constraints; the first screenshot showed three full-width filter chips. Removed from both.

## Verification — what the tests prove and what still needs a device

`flutter test` (56 tests) covers:

- every text/surface pair at AA, every graphic at 3:1, the gradient under a centred label;
- the gallery scrolled end to end under LTR, RTL, 200% text, RTL + 200%, and reduced motion — asserting no `RenderFlex` overflow, no paragraph larger than its box, no single word broken across lines, no tappable node under 48 × 48 dp, no unlabelled control or image, and that at least sixty controls were actually inspected (so a semantics restructure cannot make the audit pass vacuously). The bottom sheet is opened and audited under each scenario too — it is a route on the root navigator, outside the gallery's own wrappers, and the first version of the gallery let it escape them;
- a source scan of `lib/` and `test/` for retired copy — "Book instantly", "Emergency available", Gardening / Computer / Events, SMS, a bare "Verified", "Payment verified", any editorial provider label;
- `lib/` uses only directional insets, alignment and positioning (a source-scanning test, since the analyzer has no rule for it);
- the product rules the widgets carry: tier `none` renders nothing, the three tiers' copy verbatim, "Provider confirmed receipt", loading keeps the label, a disabled button is announced disabled with no tap action, the 48 dp floor lands taps, a disabled toggle speaks its reason, reduced motion zeroes every duration and stops every loop (asserted by an idle frame scheduler), the page transition enters from the trailing edge in both directions.

Tests run in the real Inter face and Material Icons (`test/flutter_test_config.dart`); the framework's default test font draws every glyph as a square and would make the layout assertions meaningless.

**Not yet done, and only a device can do it:** the screen-reader pass with TalkBack or VoiceOver. This machine has no emulator or attached phone. The semantics tree is asserted structurally, which is necessary but not the same as hearing it. The checklist for that pass:

1. Home → Component gallery. Every section heading announced as a heading.
2. Buttons: variant and state read as "button"; the loading one adds "loading"; disabled ones read as dimmed/unavailable and do not activate.
3. Text input: focusing reads the label, then the hint or value; the error field reads its message with the label; the read-only field says "read only".
4. Toggle: reads "switch, on/off"; the disabled one reads its reason.
5. Chips: filter chips read selected/not selected; input chips read "Remove …".
6. Verification badge: full form reads "Gold — ID checked, registered trade"; the absent one is skipped entirely.
7. Status badge: reads "Status: …".
8. Rating input: each star is its own stop, "1 star … 5 stars"; the chosen one reads selected.
9. Bottom nav: "Home, tab 1 of 5, selected".
10. Save heart: "Save Home Deep Cleaning, switch, off" → after tap "Saved …, on".
11. Skeleton: one stop, "Loading"; no bones read individually.
12. Bottom sheet: focus moves into the sheet on open; the scrim reads "Close sheet"; focus returns on close.
13. Switch the OS to 200% text and to reduce-motion and repeat 1–12.

## Known limits, for the phases that meet them

- `AppCard` with `onTap` excludes its children's semantics (the card is one control), so an interactive `trailing` inside a tappable `AppCard.row` is unreachable to a screen reader. Make the row non-tappable and let the trailing control carry the action, or the reverse — not both.
- `_DragToDismiss` on the bottom sheet competes with a scrolling body; drag-to-dismiss works reliably from the handle and title. The sheet does rise above the keyboard.
- Skeleton bone heights are fixed and do not follow the text scale, so at 200% the layout shifts when data lands. Phase 15/16 should size the card skeletons from the scaled type roles.
- `AppPageTransitionsBuilder.transitionDuration` is still 350 ms under reduced motion: nothing draws, but the route waits it out. Flutter offers no context at that call site.

## Not decided here

- Whether the gallery's RTL/200%/reduced-motion switches should survive into a debug menu for later phases, or stay gallery-only.
- Icon art. Material Icons stand in; the prototypes draw their own glyphs. If the product wants those, they arrive as an icon font or SVG set in a later phase, not as tokens.
