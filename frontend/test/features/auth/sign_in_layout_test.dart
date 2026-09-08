import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/widgets/auth_hero.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Geometry, not copy. Every other test on this screen asserts what it says;
/// these assert how big things are, because that is the axis two reviews
/// missed. `pumpScreen` already pumps a 412x915 frame at DPR 1 — the
/// prototype's own frame — so the numbers below are the prototype's numbers.
///
/// The defects that prompted this file, both measured on a device against
/// `Sign In.dc.html`:
///
///  * The hero rendered 293 dp wide on a 412 dp screen. Every element in it
///    was positioned except one `Padding`, so the `Stack` sized to the
///    widest line of text. A CSS block `<div>` fills its container by
///    default and the prototype therefore never says so; Flutter has no such
///    default, and the port carried the gradient, the padding, all three disc
///    offsets and the wave's SVG path — everything except the width.
///  * The four social buttons were one row of bare 48 dp circles reading
///    `G`, `A`, `f`, `V`, where the prototype has a two-column grid of 50 dp
///    pills each naming its provider.
///
/// Neither is visible to `flutter analyze`, and no copy comparison can see
/// either one.
void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const SignInScreen(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      deviceNameProvider.overrideWith((_) async => 'Test phone'),
    ],
    routes: {
      '/register': (_) => const Scaffold(body: Text('REGISTER')),
      '/forgot-password': (_) => const Scaffold(body: Text('FORGOT')),
      '/': (_) => const Scaffold(body: Text('HOME')),
    },
  );

  testWidgets('the hero is full-bleed, not shrink-wrapped to its text', (
    tester,
  ) async {
    await pump(tester);

    final frame = tester.getSize(find.byType(Scaffold)).width;

    // Measure the box that PAINTS the gradient, not `AuthHero` itself. The
    // widget is a `Stack` and reports the full 411 dp even when the gradient
    // inside it is short, because a `Stack` hands non-positioned children
    // loose constraints. An earlier version of this test measured `AuthHero`
    // and passed against the defect it was written to catch.
    final gradientBox = find.descendant(
      of: find.byType(AuthHero),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient != null,
      ),
    );
    expect(gradientBox, findsOneWidget);

    expect(
      tester.getSize(gradientBox).width,
      frame,
      reason:
          'The gradient must span the frame (412 in the prototype). It '
          'painted 293 dp on a 411 dp device while the Stack around it '
          'stayed full width.',
    );
    expect(tester.getRect(gradientBox).left, 0);

    // The prototype centres the wordmark and tagline: its icon badge sits at
    // x=126 in a 412 frame, not at the 24 dp page padding. Making the
    // gradient full-bleed is what exposed this — while the banner was 293 dp
    // the content filled it and looked centred.
    final hero = tester.getRect(gradientBox);
    // The badge and wordmark are one Row; measure the Row. The wordmark
    // alone sits 53 dp (badge 42 + gap 11) right of the Row's start, so its
    // own centre is 26.5 dp off the banner's — correct, and not what this
    // asserts.
    final brandRow = tester.getRect(
      find
          .ancestor(
            of: find.bySemanticsLabel('RaajjePro'),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(
      brandRow.center.dx,
      closeTo(hero.center.dx, 1),
      reason: 'the hero badge and wordmark must be centred in the banner',
    );
    final tagline = tester.getRect(
      find.text('🇲🇻 Maldives Local Service Marketplace'),
    );
    expect(tagline.center.dx, closeTo(hero.center.dx, 1));
  });

  testWidgets('social sign-in is a two-column grid of equal, named pills', (
    tester,
  ) async {
    await pump(tester);

    // Named, not glyph-only: `A` and a lower-case `f` are not guessable.
    for (final name in ['Google', 'Apple', 'Facebook', 'Viber']) {
      expect(find.text(name), findsOneWidget, reason: '$name must be named');
    }

    Rect pill(String name) => tester.getRect(
      find
          .ancestor(of: find.text(name), matching: find.byType(Container))
          .first,
    );

    final google = pill('Google');
    final apple = pill('Apple');
    final facebook = pill('Facebook');
    final viber = pill('Viber');

    // Two columns, equal width — the failure mode is one pill sizing to its
    // own label, which is what `Expanded` prevents.
    expect(google.width, apple.width);
    expect(facebook.width, viber.width);
    expect(google.width, facebook.width);

    // Two rows, in provider order.
    expect(google.top, apple.top);
    expect(facebook.top, viber.top);
    expect(facebook.top, greaterThan(google.top));

    // `gap: 10px` on both axes, and the prototype's 50 dp pill.
    expect(apple.left - google.right, closeTo(10, 0.5));
    expect(facebook.top - google.bottom, closeTo(10, 0.5));
    expect(google.height, closeTo(50, 0.5));

    // Each glyph carries its provider's brand colour, not ink. Viber's
    // purple is the one a reader notices immediately when it is missing.
    Color glyphColour(String glyph) => (tester.widget(
      find.descendant(
        of: find
            .ancestor(of: find.text(glyph), matching: find.byType(Container))
            .first,
        matching: find.text(glyph),
      ),
    ) as Text).style!.color!;
    expect(glyphColour('G'), const Color(0xFF4285F4));
    expect(glyphColour('f'), const Color(0xFF1877F2));
    expect(glyphColour('V'), const Color(0xFF7360F2));
  });
}
