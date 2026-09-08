import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
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

  setUp(() => api = FakeApiClient());

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('signin-email')),
      'aishath@example.mv',
    );
    await tester.enterText(
      find.byKey(const Key('signin-password')),
      'seabreeze-24',
    );
  }

  testWidgets(
    'default state: the prototype copy, four third-party buttons including Apple, no SMS anywhere', // retired-ok: asserting SMS's absence
    (tester) async {
      await pump(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign in to your RaajjePro account'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
      for (final p in ['Google', 'Apple', 'Facebook', 'Viber']) {
        expect(find.bySemanticsLabel('Continue with $p'), findsOneWidget);
      }
      expect(
        find.textContaining('SMS'), // retired-ok: asserting SMS's absence
        findsNothing,
      );
      expect(find.textContaining('text message'), findsNothing);
      expect(
        find.textContaining(
          'Browsing, searching and viewing providers need no account',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the hero carries the 42dp icon badge beside the wordmark, prototype-matched (final review #3)',
    (tester) async {
      await pump(tester);
      // `Sign In.dc.html` lines 28-40: the icon badge sits inside the
      // gradient hero, above `Welcome back` — which is its own Text in the
      // body now, not an AuthHero title/subtitle param.
      expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    },
  );

  testWidgets(
    'submitting shows the button\'s own loading state, then success signs in',
    (tester) async {
      api.gate = Completer<void>();
      api.on(
        'POST',
        '/v1/auth/login',
        (_) => {'user': userJson(), 'tokens': tokensJson()},
      );
      await pump(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
      await tester.pump();
      expect(find.text('Signing in…'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
      ); // the button spins, not the page
      expect(
        tester
            .widget<AppTextField>(find.byKey(const Key('signin-email')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<AppTextField>(find.byKey(const Key('signin-password')))
            .enabled,
        isFalse,
      );
      api.gate!.complete();
      await settle(tester);
      expect(api.calls.single.path, '/v1/auth/login');
    },
  );

  testWidgets(
    'a wrong password shows one undifferentiated message and keeps both values and the reveal state',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/login',
        status: 401,
        code: 'INVALID_CREDENTIALS',
      );
      await pump(tester);
      await fill(tester);
      await tester.tap(find.bySemanticsLabel('Show password'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
      await settle(tester);
      expect(
        find.text(
          "That email and password combination didn't work. Check both and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('aishath@example.mv'), findsOneWidget);
      expect(
        find.text('seabreeze-24'),
        findsOneWidget,
      ); // revealed, so visible as text
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
      // `findRichText: true` matches the underlying `RichText` for *any*
      // qualifying `Text` (including the mandated banner copy, which itself
      // says "email") — never a `Text`, so a hard `as Text` cast here throws
      // regardless of implementation. Read the flattened text off whichever
      // type actually matched instead.
      expect(
        find.textContaining('email', findRichText: true).evaluate().any((e) {
          final w = e.widget;
          final text = w is RichText
              ? w.text.toPlainText()
              : (w is Text ? (w.data ?? w.textSpan?.toPlainText() ?? '') : '');
          return text.contains('not found');
        }),
        isFalse,
      );
    },
  );

  testWidgets(
    'RATE_LIMITED shows a distinct banner with the wait time and keeps both values',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/login',
        status: 429,
        code: 'RATE_LIMITED',
        details: {'retryAfterSeconds': 90},
      );
      await pump(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
      await settle(tester);
      expect(find.textContaining('1:30'), findsOneWidget);
      expect(
        find.text(
          "That email and password combination didn't work. Check both and try again.",
        ),
        findsNothing,
      );
      expect(find.text('aishath@example.mv'), findsOneWidget);
      expect(find.text('seabreeze-24'), findsOneWidget);
    },
  );

  testWidgets(
    'a 500-class code shows the generic banner, not the credentials banner',
    (tester) async {
      api.fail('POST', '/v1/auth/login', status: 500, code: 'INTERNAL_ERROR');
      await pump(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
      await settle(tester);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text(
          "That email and password combination didn't work. Check both and try again.",
        ),
        findsNothing,
      );
    },
  );

  testWidgets('offline shows an inline notice with retry, never a raw error', (
    tester,
  ) async {
    api.offline('POST', '/v1/auth/login');
    await pump(tester);
    await fill(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
    await settle(tester);
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets(
    'a third-party button answers with an inline "not available yet" notice',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/social/apple',
        status: 422,
        code: 'SOCIAL_AUTH_UNAVAILABLE',
        message: "Sign-in with apple isn't available yet — use your email and password",
      );
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Continue with Apple'));
      await settle(tester);
      expect(find.textContaining("isn't available yet"), findsOneWidget);
    },
  );

  testWidgets(
    'Create Account, Forgot password and Continue as Guest navigate',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Create Account'));
      await settle(tester);
      expect(find.text('REGISTER'), findsOneWidget);
      // Not `tester.pageBack()`: it looks for a real back-button widget, and
      // the '/register' route here is the test's own bare placeholder
      // (`Scaffold(body: Text('REGISTER'))`, no AppBar) — popping the
      // Navigator directly is the equivalent of a hardware/gesture back.
      Navigator.of(tester.element(find.text('REGISTER'))).pop();
      await settle(tester);
      await tester.tap(find.text('Forgot password?'));
      await settle(tester);
      expect(find.text('FORGOT'), findsOneWidget);
    },
  );

  testWidgets('every control meets the 48 dp floor', (tester) async {
    await pump(tester);
    for (final p in tester.widgetList<Pressable>(find.byType(Pressable))) {
      final size = tester.getSize(find.byWidget(p));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
