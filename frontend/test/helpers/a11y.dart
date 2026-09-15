import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/shared/shared.dart';

/// Fails if a tappable wrapper has swallowed a control inside it.
///
/// `Pressable` announces itself as one thing: it wraps its child in
/// `Semantics(..., excludeSemantics: true)`, which is correct and deliberate —
/// a card with an icon, a title and three lines of text should be one control,
/// not five nodes a screen reader reads one at a time.
///
/// The cost is that it is **total**. Anything interactive inside the child
/// disappears with the decoration. §Phase 10's service card is where this was
/// found (2026-09-15): making the whole card tappable erased its overflow
/// menu, its live toggle and its Finish & publish button from the semantics
/// tree at once, leaving a screen-reader user a summary and no controls. It
/// looked right, it passed every other test, and what exposed it was a finder
/// that could not locate the menu.
///
/// Nothing in the type system prevents the next one, so this is the guard.
/// Call it after pumping a screen. It reads the **widget** tree rather than
/// the semantics tree, so it can name the control that is hidden instead of
/// only reporting that something is missing.
///
/// **If a card genuinely needs to be tappable and hold a control**, the answer
/// is not to suppress this. Make the card a container and leave the tap to the
/// controls inside it — which is what the artboards draw anyway.
void expectNoSwallowedControls(WidgetTester tester) {
  final swallowed = <String>[];
  final wrappers = find.byWidgetPredicate(
    (w) => w is Pressable && w.onTap != null,
  );

  for (final element in wrappers.evaluate()) {
    final outer = element.widget as Pressable;
    final inner = find.descendant(
      of: find.byWidget(outer),
      matching: find.byWidgetPredicate(
        (w) => w is Pressable && w.onTap != null,
      ),
    );
    for (final hidden in inner.evaluate()) {
      swallowed.add(
        '"${(hidden.widget as Pressable).semanticLabel}" is inside '
        'tappable "${outer.semanticLabel}"',
      );
    }
  }

  expect(
    swallowed,
    isEmpty,
    reason:
        'A tappable Pressable excludes its descendants from the semantics '
        'tree, so these controls do not exist for a screen reader. Make the '
        'outer one a container and leave the tap to the controls inside it.\n'
        '${swallowed.join('\n')}',
  );
}
