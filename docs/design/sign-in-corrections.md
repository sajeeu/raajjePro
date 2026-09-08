# Sign In — three corrections still to apply

**For whoever holds `frontend/lib/features/auth/presentation/sign_in_screen.dart`.**
Written 2026-09-08 after measuring the built screen against
`mockups/design-composer/Sign In.dc.html` on an Android 15 emulator at
1080×2400 (DPR 2.625 → a 411.4 dp frame, which is the prototype's 412 frame).

Four other defects on this screen are already fixed in `b220783` —
`widgets/auth_hero.dart` and `widgets/social_sign_in_row.dart`, with
`test/features/auth/sign_in_layout_test.dart` guarding them. These three were
left because they live in a file another session was holding uncommitted, and
editing underneath it is how two of my own files got reverted an hour earlier.

Every number below is measured from the prototype's computed styles, not read
off a design.

---

## 1 · "Continue as Guest" is a text link, not a button

**Prototype:** an `<a>` — **141 × 16**, centred (`left: 136` in a 412 frame),
**13.5 px / weight 700**, colour **`rgb(91, 107, 132)`** (`#5B6B84`, the
`textSecondary` token). Transparent background, no border, no fill.

**As built:** `AppButton.secondary(label: 'Continue as Guest', expand: true)`
— a full-width tinted button.

**Why it matters beyond appearance:** a filled full-width control competes
with `Sign In` for primary emphasis, and this screen already has a real
primary action. The prototype makes guest browsing available without
advertising it as the equal of signing in.

**Apply:** `AppButton.text` centred, or a `Pressable` wrapping a
`Text(style: type.helper.copyWith(fontWeight: FontWeight.w700, color:
colors.textSecondary))`. Keep the 48 dp tap target; only the *painted* box
changes.

---

## 2 · The footer caption is heavier and darker than intended

**Prototype:** 11.5 px, **weight 500**, `rgb(130, 150, 179)` = `#8296B3`,
`line-height: 17.825` (1.55), centred.

**As built:** `type.caption` (11.5 px, weight **600**) with the colour
overridden to `colors.textTertiary` = `#41526B`.

**Do not copy the prototype's colour.** It fails WCAG AA, which §Phase 1
makes non-negotiable:

| Colour | On `#F2F6FB` | |
|---|---|---|
| Prototype `#8296B3` | **2.78 : 1** | fails (4.5 needed) |
| `textSecondary` `#5B6B84` | 4.99 : 1 | passes |
| `textTertiary` `#41526B` (current) | 7.32 : 1 | passes |

**Apply:** weight **500** and **`colors.textSecondary`**. That is 4.99 : 1 —
compliant, visibly lighter than the current 7.32 : 1, and as close to the
prototype's intent as contrast allows. Decided 2026-09-08.

### 🔧 A palette bug behind this, for Phase 1

**`textTertiary` (`#41526B`) is darker than `textSecondary` (`#5B6B84`).**
Anyone reaching for "tertiary" to de-emphasise text gets the opposite, which
is how this caption ended up heavier than the design intended. The names
imply a lightness order the values do not have. Worth either renaming or
re-valuing, and worth checking every other `textTertiary` use for the same
inversion.

---

## 3 · The password field is 66 dp tall; the prototype's is 54

**Measured on device:** email field 49 dp, password field **66 dp**. Both
should be 54. Widths are correct (L26 W360 against L24 W364 — within
edge-detection tolerance).

**Cause:** the eye toggle is a bare `Pressable`, and `Pressable.minSize`
defaults to `AppSizes.touchTarget` = **48**. A 48 dp child plus the field's
own vertical padding pushes the row to 66. `AppSizes.inputHeight` (52) is a
*minimum*, so it cannot pull it back.

**This is a genuine tension, not a typo.** The prototype's eye button is
**40 × 40**, which is below the 48 dp minimum touch target. So:

- `Pressable(minSize: 40)` matches the prototype and shrinks the tap target
  below the guideline. Not recommended without a recorded decision.
- **Recommended:** keep the 48 dp tap area and stop it dictating the row
  height — render the icon in a 40 dp box and let the hit area overflow
  (`SizedBox(height: 40)` around an `OverflowBox`, or a `Stack` with the
  `Pressable` unclipped). The field lands at 54 and the target stays 48.

Whichever is chosen, record it: this pattern recurs on every field with a
trailing control, and Register's password fields have the same shape.

---

## How to check the result

`flutter test test/features/auth/sign_in_layout_test.dart` guards the four
already-fixed defects; extend it rather than starting a new file. It asserts
geometry and computed styles, because copy comparison is what missed all
seven of these — the wording matched the prototype exactly the whole time.

To measure on device: `adb exec-out screencap -p > shot.png`, then compare
runs of non-background pixels per row against the prototype's own numbers.
Serve the artboards with `python3 -m http.server` from
`mockups/design-composer/` and read the real values out of
`getBoundingClientRect()` and `getComputedStyle()` — the prototypes are
self-contained and render in any browser.
