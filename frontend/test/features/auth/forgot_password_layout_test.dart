import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/presentation/forgot_password_screen.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/widgets/otp_code_entry.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Geometry across all three steps, measured against
/// `mockups/design-composer/Forgot Password.dc.html`: the primary button is
/// `height:54px;border-radius:16px` and spans the 364 dp content width; the
/// code boxes are `48 x 58` at radius 14, the same component Verify Email
/// draws.
///
/// Written after Explore's grid turned out ragged behind a test that measured
/// the wrapper instead of the painted box. Every measurement here is of the
/// box that paints.
void main() {
  late FakeApiClient api;
  var now = DateTime.utc(2026, 9, 8, 10);

  Map<String, dynamic> sentBody() => {
    'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String(),
    'resendAvailableAt': now.add(const Duration(seconds: 60)).toIso8601String(),
  };

  setUp(() {
    api = FakeApiClient();
    now = DateTime.utc(2026, 9, 8, 10);
    api.on('POST', '/v1/auth/password-reset/request', (_) => sentBody());
    api.on('POST', '/v1/auth/password-reset/verify', (_) => {});
  });

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const ForgotPasswordScreen(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      clockProvider.overrideWithValue(() => now),
    ],
    routes: {
      SignInScreen.routeName: (_) => const Scaffold(body: Text('SIGN IN')),
    },
  );

  /// The painted surface of a control, not the widget that wraps it.
  Rect paintedOf(WidgetTester tester, Finder of) => tester.getRect(
    find.descendant(of: of, matching: find.byType(AnimatedContainer)).first,
  );

  testWidgets('step 1: the field and the button span the content width', (
    tester,
  ) async {
    await pump(tester);

    final field = paintedOf(tester, find.byType(AppTextField).first);
    expect(field.width, closeTo(364, 1));
    expect(field.height, closeTo(AppSizes.inputHeight, 1));

    final button = tester.getRect(find.byType(AppButton).first);
    expect(
      button.width,
      closeTo(364, 1),
      reason: 'the prototype button spans the content width',
    );
    expect(button.height, closeTo(54, 1), reason: 'prototype height is 54');
  });

  testWidgets('step 2: the code boxes are the prototype 48 x 58, centred', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const Key('fp-email')),
      'aishath@example.mv',
    );
    await tester.pump();
    await tester.tap(find.text('Send Reset Code'));
    await settle(tester);

    expect(find.byType(OtpCodeEntry), findsOneWidget);
    final boxes = find.descendant(
      of: find.byType(OtpCodeEntry),
      matching: find.byType(TextField),
    );
    expect(boxes, findsNWidgets(6));
    final rects = [for (var i = 0; i < 6; i++) tester.getRect(boxes.at(i))];
    for (final r in rects) {
      expect(r.width, closeTo(48, 0.5));
      expect(r.height, closeTo(58, 0.5));
      expect(r.top, closeTo(rects.first.top, 0.5));
    }
    final centre = (rects.first.left + rects.last.right) / 2;
    expect(centre, closeTo(tester.getSize(find.byType(Scaffold)).width / 2, 1));
  });

  testWidgets('step 3: both password fields are one height and full width', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const Key('fp-email')),
      'aishath@example.mv',
    );
    await tester.pump();
    await tester.tap(find.text('Send Reset Code'));
    await settle(tester);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(Key('otp-$i')), '1');
      await tester.pump();
    }
    await tester.tap(find.text('Continue'));
    await settle(tester);

    final count = find.byType(AppTextField).evaluate().length;
    expect(count, 2, reason: 'new password and confirm');
    final painted = [
      for (var i = 0; i < count; i++)
        paintedOf(tester, find.byType(AppTextField).at(i)),
    ];

    // The trailing reveal toggle used to carry the 48 dp touch minimum into
    // the row, standing the password field 79 dp against a 52 dp email field.
    expect(
      painted.map((r) => r.height.round()).toSet(),
      hasLength(1),
      reason:
          'both fields must be one height; got '
          '${painted.map((r) => r.height).toList()}',
    );
    expect(painted.first.height, closeTo(AppSizes.inputHeight, 1));
    for (final r in painted) {
      expect(r.width, closeTo(364, 1));
    }
  });
}
