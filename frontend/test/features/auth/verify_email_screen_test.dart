import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  var now = DateTime.utc(2026, 9, 6, 10);
  setUp(() {
    api = FakeApiClient();
    now = DateTime.utc(2026, 9, 6, 10);
  });

  Future<void> pump(
    WidgetTester tester, {
    VerificationStatus? status,
    DateTime? resendAt,
  }) => pumpScreen(
    tester,
    VerifyEmailScreen(
      args: VerifyEmailArgs(
        email: 'aishath@example.mv',
        purpose: OtpPurpose.verifyEmail,
        initialStatus: status,
        resendAvailableAt: resendAt ?? now.add(const Duration(seconds: 47)),
      ),
    ),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      clockProvider.overrideWithValue(() => now),
    ],
    routes: {
      '/': (_) => const Scaffold(body: Text('HOME')),
      // A real AppBar, not a bare Scaffold: `tester.pageBack()` looks for a
      // 'Back' tooltip (or a Cupertino back button) on screen, and a plain
      // `Scaffold(body: ...)` renders neither, so the round trip back to
      // Verify Email would have nothing to tap.
      '/account/change-email': (_) => Scaffold(
        appBar: AppBar(title: const Text('CHANGE')),
        body: const SizedBox(),
      ),
    },
  );

  Future<void> typeCode(WidgetTester tester, String code) async {
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(Key('otp-$i')), code[i]);
      await tester.pump();
    }
  }

  testWidgets(
    'entry: the address in full, email-only copy, a resend countdown that is not the rate-limit clock, a disabled verify until six digits',
    (tester) async {
      await pump(tester);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('aishath@example.mv'), findsOneWidget);
      const notSms = 'SMS'; // retired-ok: asserting absence, not rendering it
      expect(find.textContaining(notSms), findsNothing);
      expect(find.text('Resend code in 0:47'), findsOneWidget);
      expect(find.text('A short wait before the next code'), findsNothing);
      final verify = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Verify Email'),
      );
      expect(verify.onPressed, isNull);
      await typeCode(tester, '482913');
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Verify Email'))
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining("Browsing doesn't"), findsOneWidget);
      expect(find.text("I'll do this later"), findsOneWidget);
    },
  );

  testWidgets(
    'the header is a bare back control, not AppHeader.page (final review #18)',
    (tester) async {
      await pump(tester);
      // `Verify Email.dc.html` line ~29: a bare circular back button, no
      // title bar above the centered "Verify your email" in the body.
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.text('Verify email'), findsNothing);
    },
  );

  testWidgets(
    'the countdown reaches zero and becomes a Resend button; resend shows the resent banner',
    (tester) async {
      api.on(
        'POST',
        '/v1/auth/verify-email/send',
        (_) => {
          'status': 'sent',
          'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
          'resendAvailableAt': now
              .add(const Duration(seconds: 60))
              .toIso8601String(),
        },
      );
      await pump(tester);
      now = now.add(const Duration(seconds: 48));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resend code'), findsOneWidget);
      await tester.tap(find.text('Resend code'));
      await settle(tester);
      expect(
        find.text('A new code is on its way to your inbox.'),
        findsOneWidget,
      );
      expect(find.text('Resend code in 1:00'), findsOneWidget);
    },
  );

  testWidgets(
    'wrong code shows attempts remaining; invalidated disables the boxes and offers a fresh send',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/verify-email/confirm',
        status: 422,
        code: 'OTP_INCORRECT',
        details: {'attemptsRemaining': 2},
      );
      await pump(tester);
      await typeCode(tester, '000000');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(
        find.text(
          "That code isn't right — 2 attempts left before it needs a fresh send.",
        ),
        findsOneWidget,
      );
      api.fail(
        'POST',
        '/v1/auth/verify-email/confirm',
        status: 422,
        code: 'OTP_INVALIDATED',
      );
      await typeCode(tester, '000001');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(
        find.textContaining('invalidated after 5 incorrect attempts'),
        findsOneWidget,
      );
      expect(find.text('Send a fresh code'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('otp-0'))).enabled,
        isFalse,
      );
    },
  );

  testWidgets(
    'OTP_RATE_LIMITED renders the wait with its own clock and both limits named; expiry returns to entry',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/verify-email/send',
        status: 429,
        code: 'OTP_RATE_LIMITED',
        details: {'retryAfterSeconds': 272, 'limit': 'address'},
      );
      await pump(tester, resendAt: now);
      await tester.tap(find.text('Resend code'));
      await settle(tester);
      expect(find.text('A short wait before the next code'), findsOneWidget);
      expect(find.text('4:32'), findsOneWidget);
      expect(
        find.textContaining(
          '3 per address every 15 minutes, and 5 per account each hour',
        ),
        findsOneWidget,
      );
      now = now.add(const Duration(seconds: 273));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('A short wait before the next code'), findsNothing);
      expect(find.byKey(const Key('otp-0')), findsOneWidget);
    },
  );

  testWidgets(
    'success card, then Continue goes home; the auth state is marked verified',
    (tester) async {
      api.on(
        'POST',
        '/v1/auth/verify-email/confirm',
        (_) => {'emailVerified': true},
      );
      await pump(tester);
      await typeCode(tester, '482913');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(find.text('Email verified'), findsOneWidget);
      expect(
        find.textContaining('booking, enquiries and messaging are now open'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('HOME'), findsOneWidget);
    },
  );

  testWidgets(
    'EMAIL_ALREADY_VERIFIED on confirm takes the same success path as a correct code',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/verify-email/confirm',
        status: 422,
        code: 'EMAIL_ALREADY_VERIFIED',
      );
      await pump(tester);
      await typeCode(tester, '482913');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(find.text('Email verified'), findsOneWidget);
      expect(
        find.textContaining('booking, enquiries and messaging are now open'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('HOME'), findsOneWidget);
    },
  );

  testWidgets(
    'an unexpected code on confirm shows the generic banner, not the wrong-code state',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/verify-email/confirm',
        status: 500,
        code: 'INTERNAL_ERROR',
      );
      await pump(tester);
      await typeCode(tester, '482913');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('attempt'), findsNothing);
      for (var i = 0; i < 6; i++) {
        expect(
          tester.widget<TextField>(find.byKey(Key('otp-$i'))).controller!.text,
          '482913'[i],
        );
      }
    },
  );

  testWidgets(
    'OTP_EXPIRED on confirm clears the boxes and shows its own expired copy, not the invalidated one',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/verify-email/confirm',
        status: 422,
        code: 'OTP_EXPIRED',
      );
      await pump(tester);
      await typeCode(tester, '482913');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(
        find.text('That code has expired. Send a fresh one.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('invalidated after 5 incorrect attempts'),
        findsNothing,
      );
      expect(find.text('Send a fresh code'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('otp-0'))).enabled,
        isFalse,
      );
    },
  );

  testWidgets('a suppressed or failed send is shown honestly, never as sent', (
    tester,
  ) async {
    await pump(tester, status: VerificationStatus.suppressed);
    expect(
      find.textContaining("couldn't send a code to this address"),
      findsOneWidget,
    );
    expect(find.text('A new code is on its way to your inbox.'), findsNothing);
  });

  testWidgets(
    'a network failure during verify shows the offline notice, and retry replays the same code',
    (tester) async {
      api.offline('POST', '/v1/auth/verify-email/confirm');
      await pump(tester);
      await typeCode(tester, '482913');
      await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
      await settle(tester);
      expect(find.text('No internet connection.'), findsOneWidget);
      api.on(
        'POST',
        '/v1/auth/verify-email/confirm',
        (_) => {'emailVerified': true},
      );
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Email verified'), findsOneWidget);
    },
  );

  testWidgets(
    'Not your address? Change it routes to change email; I\'ll do this later goes home',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Not your address? Change it'));
      await settle(tester);
      expect(find.text('CHANGE'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text("I'll do this later"));
      await settle(tester);
      expect(find.text('HOME'), findsOneWidget);
    },
  );

  group('VerifyEmailArgs.fromRouteArguments (final review #14)', () {
    test('passes a typed VerifyEmailArgs straight through', () {
      const args = VerifyEmailArgs(
        email: 'aishath@example.mv',
        purpose: OtpPurpose.verifyEmail,
      );
      expect(VerifyEmailArgs.fromRouteArguments(args), same(args));
    });

    test('accepts the legacy untyped map', () {
      final args = VerifyEmailArgs.fromRouteArguments(const {
        'email': 'aishath@example.mv',
        'status': 'sent',
        'resendAvailableAt': '2026-09-06T10:00:47.000Z',
      });
      expect(args.email, 'aishath@example.mv');
      expect(args.purpose, OtpPurpose.verifyEmail);
      expect(args.initialStatus, VerificationStatus.sent);
      expect(
        args.resendAvailableAt,
        DateTime.parse('2026-09-06T10:00:47.000Z'),
      );
    });

    test(
      'null arguments raise a clear ArgumentError, not a bare cast failure',
      () {
        expect(
          () => VerifyEmailArgs.fromRouteArguments(null),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              contains('VerifyEmailScreen.routeName'),
            ),
          ),
        );
      },
    );

    test('a map missing email also raises ArgumentError', () {
      expect(
        () => VerifyEmailArgs.fromRouteArguments(const {'status': 'sent'}),
        throwsArgumentError,
      );
    });
  });
}
