import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

import '../helpers/pump.dart';

/// How the sheet arrives.
///
/// Found on a device, 2026-09-14: opening the island picker over Explore
/// showed the category grid and the bottom nav **through** the sheet for the
/// length of its entrance, with the skeleton rows drawn over the tiles. The
/// cause was a `FadeTransition` wrapping the whole route, including the
/// sheet's own opaque surface — faithful to `motion.css`'s `sheetUp`
/// keyframe, and wrong in a compositor where that surface is a real opaque
/// card rather than a positioned element over a dimmed page.
///
/// The scrim still fades, because `barrierColor` is driven by the same route
/// animation. Only the surface stopped.
void main() {
  Future<void> openSheet(WidgetTester tester) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AppButton(
              label: 'Open',
              onPressed: () => showAppBottomSheet<void>(
                context: context,
                builder: (_) =>
                    const AppBottomSheet(child: Text('Choose your island')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
  }

  testWidgets('rises without fading its own surface', (tester) async {
    await openSheet(tester);
    // Mid-entrance: the moment the old behaviour was visible.
    await tester.pump(AppMotion.sheet ~/ 2);

    final fades = find.ancestor(
      of: find.text('Choose your island'),
      matching: find.byType(FadeTransition),
    );
    expect(
      fades,
      findsNothing,
      reason:
          'A FadeTransition over the sheet makes its opaque surface '
          'translucent for the length of the entrance, and the page behind '
          'shows through it.',
    );

    await tester.pumpAndSettle();
    expect(find.text('Choose your island'), findsOneWidget);
  });

  testWidgets('still travels the distance the tokens specify', (tester) async {
    // The rise is the half of `sheetUp` that was kept, so assert it rather
    // than trusting that removing the fade left it alone.
    await openSheet(tester);
    await tester.pump();
    final entering = tester.getTopLeft(find.text('Choose your island')).dy;

    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('Choose your island')).dy;

    expect(entering, greaterThan(settled));
    expect(entering - settled, lessThanOrEqualTo(AppMotion.sheetSlide + 0.01));
  });
}
