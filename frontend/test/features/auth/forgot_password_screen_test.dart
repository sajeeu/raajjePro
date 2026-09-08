import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/features/auth/presentation/forgot_password_screen.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

const _request = '/v1/auth/password-reset/request';
const _verify = '/v1/auth/password-reset/verify';
const _confirm = '/v1/auth/password-reset/confirm';

void main() {
  late FakeApiClient api;
  var now = DateTime.utc(2026, 9, 8, 10);

  /// The body the server sends whether or not the address has an account.
  Map<String, dynamic> sentBody({
    int expiryMinutes = 30,
    int cooldown = 60,
  }) => {
    'expiresAt': now.add(Duration(minutes: expiryMinutes)).toIso8601String(),
    'resendAvailableAt': now.add(Duration(seconds: cooldown)).toIso8601String(),
  };

  setUp(() {
    api = FakeApiClient();
    now = DateTime.utc(2026, 9, 8, 10);
    api.on('POST', _request, (_) => sentBody());
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

  Future<void> requestFor(WidgetTester tester, String email) async {
    await tester.enterText(find.byKey(const Key('fp-email')), email);
    await tester.pump();
    await tester.tap(find.text('Send Reset Code'));
    await settle(tester);
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(Key('otp-$i')), code[i]);
      await tester.pump();
    }
  }

  /// Request → inbox → a good code → the set-a-new-password step.
  Future<void> reachSetNew(WidgetTester tester) async {
    api.on('POST', _verify, (_) => {});
    await pump(tester);
    await requestFor(tester, 'aishath@example.mv');
    await typeCode(tester, '123456');
    await tester.tap(find.text('Continue'));
    await settle(tester);
  }

  testWidgets(
    'step 1 asks for an email and will not send without a valid one',
    (tester) async {
      await pump(tester);
      expect(find.text('Forgot Password?'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('fp-email')), 'not-an-email');
      await tester.pump();
      await tester.tap(find.text('Send Reset Code'));
      await settle(tester);

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets('the confirmation never says whether the address is registered', (
    tester,
  ) async {
    await pump(tester);
    await requestFor(tester, 'nobody@example.mv');

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(
      find.text(
        'If this address has a RaajjePro account, a password reset code is on its way to it.',
      ),
      findsOneWidget,
    );
    // Nothing anywhere claims an account exists, or that one does not.
    expect(find.textContaining('No account'), findsNothing);
    expect(find.textContaining("We've sent"), findsNothing);
  });

  testWidgets('the inbox card counts the code down and names the address', (
    tester,
  ) async {
    await pump(tester);
    await requestFor(tester, 'aishath@example.mv');

    expect(find.text('aishath@example.mv'), findsOneWidget);
    expect(find.text('The code expires in 30:00'), findsOneWidget);
    expect(find.text("Didn't get it? Resend in 1:00"), findsOneWidget);
  });

  testWidgets('a wrong code stays on the inbox step and counts down attempts', (
    tester,
  ) async {
    api.fail(
      'POST',
      _verify,
      status: 422,
      code: 'OTP_INCORRECT',
      details: {'attemptsRemaining': 3},
    );
    await pump(tester);
    await requestFor(tester, 'aishath@example.mv');
    await typeCode(tester, '000000');
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(find.textContaining('3 attempts left'), findsOneWidget);
    expect(find.text('Set a new password'), findsNothing);
  });

  testWidgets(
    'five wrong codes land on the expired card, which offers a fresh one',
    (tester) async {
      api.fail('POST', _verify, status: 422, code: 'OTP_INVALIDATED');
      await pump(tester);
      await requestFor(tester, 'aishath@example.mv');
      await typeCode(tester, '000000');
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.text('This reset code has expired'), findsOneWidget);
      expect(
        find.text('That code was invalidated after 5 incorrect attempts.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Request a New Code'));
      await settle(tester);
      expect(find.text('Forgot Password?'), findsOneWidget);
    },
  );

  testWidgets('a good code opens the password step and does not spend it', (
    tester,
  ) async {
    await reachSetNew(tester);

    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.text('For aishath@example.mv'), findsOneWidget);
    expect(
      api.calls.where((c) => c.path == _confirm),
      isEmpty,
      reason: 'verifying must not save anything',
    );
  });

  testWidgets(
    'the password step states its requirement and blocks Save until met',
    (tester) async {
      await reachSetNew(tester);
      expect(find.text('At least 8 characters'), findsWidgets);

      final save = find.widgetWithText(AppButton, 'Save New Password');
      expect(tester.widget<AppButton>(save).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('fp-password')), 'short');
      await tester.enterText(find.byKey(const Key('fp-confirm')), 'short');
      await tester.pump();
      expect(tester.widget<AppButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('fp-password')),
        'a long enough one',
      );
      await tester.enterText(
        find.byKey(const Key('fp-confirm')),
        'a different one',
      );
      await tester.pump();
      expect(find.text("These passwords don't match yet."), findsOneWidget);
      expect(tester.widget<AppButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('fp-confirm')),
        'a long enough one',
      );
      await tester.pump();
      expect(tester.widget<AppButton>(save).onPressed, isNotNull);
    },
  );

  testWidgets('the password step is honest that every device signs out', (
    tester,
  ) async {
    await reachSetNew(tester);
    expect(
      find.text(
        'When you save, every device signs out — all other sessions end and will need this new password.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'saving sends the code and the new password, then lands on Sign In',
    (tester) async {
      api.on('POST', _confirm, (_) => {});
      await reachSetNew(tester);

      await tester.enterText(
        find.byKey(const Key('fp-password')),
        'a long enough one',
      );
      await tester.enterText(
        find.byKey(const Key('fp-confirm')),
        'a long enough one',
      );
      await tester.pump();
      await tester.tap(find.text('Save New Password'));
      await settle(tester);

      final call = api.calls.lastWhere((c) => c.path == _confirm);
      expect(call.body, {
        'email': 'aishath@example.mv',
        'code': '123456',
        'newPassword': 'a long enough one',
      });
      expect(find.text('SIGN IN'), findsOneWidget);
    },
  );

  testWidgets(
    'a code that dies between the check and the save shows the expired card',
    (tester) async {
      api.fail('POST', _confirm, status: 422, code: 'OTP_EXPIRED');
      await reachSetNew(tester);

      await tester.enterText(
        find.byKey(const Key('fp-password')),
        'a long enough one',
      );
      await tester.enterText(
        find.byKey(const Key('fp-confirm')),
        'a long enough one',
      );
      await tester.pump();
      await tester.tap(find.text('Save New Password'));
      await settle(tester);

      expect(find.text('This reset code has expired'), findsOneWidget);
      expect(find.text('SIGN IN'), findsNothing);
    },
  );

  testWidgets('offline on the request step shows the notice and retries', (
    tester,
  ) async {
    api.offline('POST', _request);
    await pump(tester);
    await requestFor(tester, 'aishath@example.mv');

    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Check your inbox'), findsNothing);

    api.on('POST', _request, (_) => sentBody());
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Check your inbox'), findsOneWidget);
  });

  testWidgets('a resend confirms itself and restarts the cooldown', (
    tester,
  ) async {
    await pump(tester);
    await requestFor(tester, 'aishath@example.mv');

    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Resend code'));
    await settle(tester);

    expect(
      find.text('A new code is on its way to your inbox.'),
      findsOneWidget,
    );
    expect(api.calls.where((c) => c.path == _request), hasLength(2));
  });

  testWidgets('the whole flow never signs anyone in', (tester) async {
    api.on('POST', _confirm, (_) => {});
    await reachSetNew(tester);
    await tester.enterText(
      find.byKey(const Key('fp-password')),
      'a long enough one',
    );
    await tester.enterText(
      find.byKey(const Key('fp-confirm')),
      'a long enough one',
    );
    await tester.pump();
    await tester.tap(find.text('Save New Password'));
    await settle(tester);

    // No token ever comes back, so nothing can have been stored.
    for (final call in api.calls) {
      expect(call.path, isNot(contains('login')));
    }
    expect(find.text('SIGN IN'), findsOneWidget);
  });
}
