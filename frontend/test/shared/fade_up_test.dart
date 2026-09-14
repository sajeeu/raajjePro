import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// `fadeUp` — the entrance 52 of the 61 artboards specify and the app did not
/// have until 2026-09-14.
void main() {
  /// The paint offset of the child, which is what `Transform.translate`
  /// moves. Layout is untouched by design, so this reads the painted
  /// position rather than the box.
  Offset paintedOffset(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find
          .ancestor(of: find.text('content'), matching: find.byType(Transform))
          .first,
    );
    return Offset(
      transform.transform.getTranslation().x,
      transform.transform.getTranslation().y,
    );
  }

  Future<void> pumpFadeUp(
    WidgetTester tester, {
    required bool reduced,
    int index = 0,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: FadeUp(child: Text('content')),
      ),
    ),
  );

  testWidgets('rises into place from 14 dp below', (tester) async {
    await pumpFadeUp(tester, reduced: false);
    // First frame: the full rise, which is `AppMotion.fadeUpSlide`.
    expect(paintedOffset(tester).dy, closeTo(AppMotion.fadeUpSlide, 0.01));

    await tester.pumpAndSettle();
    expect(paintedOffset(tester).dy, closeTo(0, 0.01));
  });

  testWidgets('renders at rest on the first frame under reduced motion', (
    tester,
  ) async {
    // The plan makes this non-negotiable: "every motion primitive has a
    // reduced-motion path honouring the OS setting" (§Phase 1). Asserted on
    // the *first* frame, because a zero-duration animation still lays out one
    // off-screen frame — the flash `ResolvedMotion` documents.
    await pumpFadeUp(tester, reduced: true);
    expect(paintedOffset(tester).dy, closeTo(0, 0.01));
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('content'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      closeTo(1, 0.01),
    );
  });

  group('the stagger', () {
    const motion = ResolvedMotion(reduced: false);

    test('steps 30 ms per item and caps at the sixth', () {
      // `calc(min(index, 6) * 30ms)` — `My Bookings` and `Discovery`.
      expect(motion.staggerFor(0), Duration.zero);
      expect(motion.staggerFor(1), const Duration(milliseconds: 30));
      expect(motion.staggerFor(6), const Duration(milliseconds: 180));
      // The cap is what stops a long list making its tail wait: the
      // hundredth row starts when the seventh does, not three seconds later.
      expect(motion.staggerFor(7), motion.staggerFor(6));
      expect(motion.staggerFor(100), motion.staggerFor(6));
    });

    test('collapses to nothing under reduced motion', () {
      const reduced = ResolvedMotion(reduced: true);
      expect(reduced.staggerFor(0), Duration.zero);
      expect(reduced.staggerFor(6), Duration.zero);
    });
  });
}
