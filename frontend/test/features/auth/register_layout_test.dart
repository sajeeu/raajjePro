import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Geometry, not copy — the axis that let seven defects through on Sign In
/// while every string matched the prototype exactly.
///
/// Numbers are read out of `Register.dc.html` with
/// `getBoundingClientRect()` and `getComputedStyle()`, at the prototype's own
/// 412 frame, which is what `pumpScreen` pumps.
///
/// Measure with `tester.getRect`, not a device screenshot and not
/// `uiautomator dump`: pixel scanning misreads borders and selected-state
/// tints (it reported these two cards as 146 and 127 dp wide when they are
/// in fact identical), and uiautomator reports Flutter's *semantics* rects,
/// which are larger than the painted box — it gives both bottom buttons as
/// 79 dp tall.
void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const RegisterScreen(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      deviceNameProvider.overrideWith((_) async => 'Test phone'),
    ],
    routes: {
      '/verify-email': (_) => const Scaffold(body: Text('VERIFY')),
      '/sign-in': (_) => const Scaffold(body: Text('SIGNIN')),
      '/forgot-password': (_) => const Scaffold(body: Text('FORGOT')),
      '/legal/terms': (_) => const Scaffold(body: Text('TERMS')),
    },
  );

  /// The painted card for a label. Named explicitly as `AnimatedContainer`,
  /// which is what `RoleToggle` draws with — `find.byType(Container)` does
  /// NOT match it, and walking up to "the nearest Container" instead landed
  /// on an inner shrink-wrapped box, reporting 146 and 128 dp for two cards
  /// that are actually identical. Verify what a finder resolves to before
  /// trusting the number it gives you.
  Rect cardFor(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );

  testWidgets('the two role cards are equal, and the prototype height', (
    tester,
  ) async {
    await pump(tester);

    final find_ = cardFor(tester, 'Find Services');
    final offer = cardFor(tester, 'Offer Services');

    // `grid-template-columns: 177px 177px; gap: 10px` inside a 364 dp
    // content width.
    expect(find_.width, offer.width, reason: 'the two cards must be equal');
    expect(find_.width, closeTo(177, 1.5));
    expect(offer.left - find_.right, closeTo(10, 2.5));

    // The prototype's cards are 124 dp tall.
    expect(
      find_.height,
      closeTo(124, 2),
      reason: 'prototype role card is 124 dp tall',
    );
    expect(offer.height, closeTo(124, 2));
  });

  testWidgets(
    'every input surface is one height; the full-width ones are 364',
    (tester) async {
      await pump(tester);

      // The painted input surface is the `AnimatedContainer` around each
      // `TextField` — not `AppTextField`, which also wraps the label above and
      // any helper text below, so its own height legitimately differs per
      // field (81, 81, 108 on this screen). Measuring that instead is what an
      // earlier version of this test did, and the numbers looked like a defect
      // when they were not.
      //
      // The height is the point. A trailing control used to add to the row, so
      // the two password fields stood 79 dp against 52 for name and email —
      // and stayed 79 at every text scale, which made the field a large-text
      // user most needs to grow the only one that could not. Fixed in
      // `AppTextField`; this keeps it fixed. The earlier assertion here
      // checked width only while its name promised a height.
      //
      // The bar is equality plus the `inputHeight` token, not the prototype's
      // literal 54: the token is 52, and closing that 2 dp is an app-wide
      // change, so it stands as a recorded divergence.
      Rect surfaceOf(int i) => tester.getRect(
        find
            .ancestor(
              of: find.byType(TextField).at(i),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );

      final count = find.byType(TextField).evaluate().length;
      expect(count, 6, reason: 'name, email, dial code, phone, password x2');

      final heights = <double>[
        for (var i = 0; i < count; i++) surfaceOf(i).height,
      ];
      expect(
        heights.map((h) => h.round()).toSet().length,
        1,
        reason: 'every input surface must be one height; got $heights',
      );
      expect(heights.first, closeTo(AppSizes.inputHeight, 2));

      // Name, email, password and confirm span the content width; the phone
      // row splits it between a dial-code segment and the number.
      for (final i in [0, 1, 4, 5]) {
        expect(
          surfaceOf(i).width,
          closeTo(364, 2),
          reason: 'field $i spans the 364 dp content width',
        );
      }
    },
  );
}
