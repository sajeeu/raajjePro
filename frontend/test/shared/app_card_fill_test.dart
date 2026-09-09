import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/shared/shared.dart';

import '../helpers/pump.dart';

/// `AppCard` fills the width it is given.
///
/// It did not, and nothing said so, because every card in the app happened to
/// contain something full width — an `expand: true` button, a `Row` — and so
/// looked correct. Explore's tile was the one card whose content was entirely
/// intrinsic, a fixed 56 dp chip above a `Text`, and it collapsed to its
/// longest label: "Appliance Repair" drew 75.6 dp and "Fitness" 72.3 dp inside
/// 116 dp cells, a visibly ragged grid behind a green test suite.
///
/// The child here is deliberately intrinsic-width only, so these tests measure
/// the card rather than whatever is inside it.
void main() {
  const intrinsic = SizedBox.square(dimension: 24);

  Rect painted(WidgetTester tester) =>
      tester.getRect(find.byType(AnimatedContainer).first);

  testWidgets('fills a loose bounded width — the Center case', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(child: AppCard(child: intrinsic)),
      ),
    );
    // `pumpScreen` pumps the prototype's 412 dp frame.
    expect(painted(tester).width, 412);
  });

  testWidgets('fills a tight width without fighting it', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(width: 250, child: AppCard(child: intrinsic)),
        ),
      ),
    );
    expect(painted(tester).width, 250);
  });

  testWidgets('fills inside a Pressable, which passes loose constraints', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Center(
          child: AppCard(
            onTap: () {},
            semanticLabel: 'tappable',
            child: intrinsic,
          ),
        ),
      ),
    );
    // The tappable branch wraps the surface in `Pressable`, whose
    // `Center(widthFactor: 1, heightFactor: 1)` hands loose constraints down.
    // That is what let Explore's tile shrink while its cell stayed 116.
    expect(painted(tester).width, 412);
  });

  testWidgets('EmptyState stays the prototype 340, not the full width', (
    tester,
  ) async {
    // `EmptyState.dc.html` is `width:340px`, and all 45 artboards that import
    // it use 340. It is the one card the prototypes fix a width for, so making
    // `AppCard` fill would have widened every empty and error state in the app
    // — including the one Explore shows when the catalogue is empty.
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.search,
            title: 'Nothing here',
            body: 'Short body.',
          ),
        ),
      ),
    );
    expect(painted(tester).width, 340);
  });

  testWidgets('EmptyState narrows below 340 rather than overflowing', (
    tester,
  ) async {
    // A cap, not a fixed width: a 300 dp column — a narrow phone, or a
    // sidebar — must narrow the card instead of overflowing it.
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: EmptyState(
              icon: Icons.search,
              title: 'Nothing here',
              body: 'Short body.',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(painted(tester).width, 300);
  });

  testWidgets('shrink-wraps under an unbounded width rather than throwing', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [AppCard(child: intrinsic)]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // 24 dp child plus the card's own default padding, not 412 and not an
    // infinity assertion — the shape a Phase 16 carousel needs, where the
    // parent supplies the width instead.
    expect(painted(tester).width, lessThan(412));
  });
}
