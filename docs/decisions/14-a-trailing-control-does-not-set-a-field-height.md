# A trailing control inside a field paints at 40 and hits at 48

**Status: decided 2026-09-08, applied to Sign In and Forgot Password.**
Asked for by `docs/design/sign-in-corrections.md` item 3, which required the
choice to be recorded because the pattern recurs on every field with a trailing
control.

## The tension

`AppTextField` lays its `suffix` inside a `Row` with 14 dp of vertical padding
and a 1.5 dp border each side. `Pressable.minSize` defaults to
`AppSizes.touchTarget` = 48. So a bare `Pressable` suffix makes the field
**79 dp**: 48 + 28 + 3. `AppSizes.inputHeight` (52) is a *minimum* and cannot
pull it back. Measured in the 412 dp test frame: Sign In's email field 52, its
password field 79.

The prototype's eye button is **40 × 40** — below the 48 dp touch minimum
§Phase 1 makes non-negotiable. So neither number can simply be copied: matching
the prototype shrinks the tap target below the guideline, and honouring the
guideline inflates a field the prototype draws at 54.

## The decision

**The field pads its text, not its row.** `AppTextField` moved its
`vertical: 14` off the outer `Padding` and onto the `Expanded` text child. A
trailing control now sits inside the height the text sets rather than adding
its own to it, so `FieldRevealToggle` can stay a plain `Pressable` at the full
48 dp target and the field lands at 52 — parity with the field above it.

Measured before and after, in the same frame:

| | plain | **with a 48 dp suffix** | multiline |
|---|---|---|---|
| before, 100% text | 52 | **79** | 94 |
| after, 100% text | 52 | **52** | 94 |
| before, 200% text | 73 | **79** | 157 |
| after, 200% text | 73 | **73** | 157 |

Only the suffixed field moves. Everything else is unchanged, including
multiline and how the field grows with the OS text size.

**This is a change to a Phase 1 shared component, made deliberately.** It is
where the defect actually lives — every screen with a password field had it —
and the two alternatives were worse: `Pressable(minSize: 40)` matches the
prototype by dropping the tap target below the 48 dp minimum, and leaving it
alone keeps a 27 dp discrepancy between two adjacent fields.

### The 200% row is the reason this was worth doing properly

Before the fix the suffixed field measured **79 dp at every text scale**. The
48 dp `Pressable` set the height, so the one field in the app a user with large
text most needs to grow was the one that could not — the text scaled inside a
box that stayed put. That is an accessibility defect, not a cosmetic one, and
nothing in the original report had spotted it.

### An approach that measures correct and is not

First attempt kept the fix local to the toggle: a 48 dp `Pressable` painted out
of a zero-height `SizedBox` through an `OverflowBox`. The field measured 52 and
`getSize` on the control returned exactly 48 × 48 — both assertions a geometry
test would happily make, and both green.

It was still broken. **Flutter hit-tests a child against its parent's bounds**,
so the 48 dp of control hanging outside a zero-height box received no taps at
all. `sign_in_screen_test.dart` caught it only because that test *taps* the
toggle rather than measuring it — `tap()` warned that the derived offset "would
not hit test on the specified widget" and the reveal never toggled.

Worth keeping in mind for the rest of this test file's geometry assertions: a
size assertion cannot tell a laid-out control from a painted one.

**The target is 52, not the prototype's 54.** 52 is `AppSizes.inputHeight`, the
value Phase 1 derived from all 61 prototypes ("Heights: 52 inputs" — root
`frontend/CLAUDE.md`), and it is what every other field in the app renders at.
Sign In's 54 is one screen's variance from the system number, and the defect
worth fixing was the 27 dp gap between two adjacent fields, not the 2 dp gap
between one screen and the token.

`test/features/auth/sign_in_layout_test.dart` asserts the geometry and
`sign_in_screen_test.dart` asserts the tap.

## Still to apply

The `AppTextField` change fixes the height on **every** screen at once, so
nothing is left broken. What remains is de-duplication, not a defect: two
screens still build the reveal toggle inline instead of using
`FieldRevealToggle`, and each is a one-line substitution.

- `features/account/presentation/change_password_screen.dart` — three fields
- `features/auth/presentation/register_screen.dart` — password fields

`register_screen.dart` was deliberately not touched: another session is
actively working on Register (`test/features/auth/register_layout_test.dart`
appeared mid-session).

## 🔧 A palette bug this exposed, for Phase 1

Raised by `docs/design/sign-in-corrections.md` and **not fixed here** — it is a
token change with app-wide reach, which is not this phase's to make.

**`textTertiary` (`#41526B`) is darker than `textSecondary` (`#5B6B84`).**
Against the `#F2F6FB` page they are 7.32:1 and 4.99:1. The names imply a
lightness order the values do not have, so anyone reaching for "tertiary" to
de-emphasise text gets the opposite — which is exactly how Sign In's footer
caption ended up heavier than designed. Worth renaming or re-valuing, and worth
checking every other `textTertiary` use for the same inversion.
