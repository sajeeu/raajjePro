import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

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

  Future<void> fillValid(WidgetTester tester, {bool provider = false}) async {
    if (provider) await tester.tap(find.text('Offer Services'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('reg-name')), 'Aishath Naeema');
    await tester.enterText(
      find.byKey(const Key('reg-email')),
      'aishath@example.mv',
    );
    await tester.enterText(find.byKey(const Key('reg-phone')), '777 1234');
    if (provider) {
      await tester.enterText(
        find.byKey(const Key('reg-business')),
        'Rasheed Plumbing Services',
      );
    }
    await tester.enterText(
      find.byKey(const Key('reg-password')),
      'seabreeze-24',
    );
    await tester.enterText(
      find.byKey(const Key('reg-confirm')),
      'seabreeze-24',
    );
    // The form is taller than the fixed test viewport (`pump.dart`'s 412x915
    // mobile frame): a real device scrolls to reach the terms row, and the
    // tester must do the same before `tap` can hit-test it.
    await tester.ensureVisible(find.byKey(const Key('reg-terms')));
    await tester.tap(find.byKey(const Key('reg-terms')));
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester, String label) async {
    final finder = find.widgetWithText(AppButton, label);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
  }

  final sent = {
    'status': 'sent',
    'expiresAt': '2026-09-06T10:10:00.000Z',
    'resendAvailableAt': '2026-09-06T10:01:00.000Z',
  };

  testWidgets(
    'customer variant: no business field; submitting sends the role, +960 phone and acceptTerms, then goes to Verify Email',
    (tester) async {
      api.on(
        'POST',
        '/v1/auth/register',
        (_) => {
          'user': userJson(),
          'tokens': tokensJson(),
          'verification': sent,
        },
      );
      await pump(tester);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.byKey(const Key('reg-business')), findsNothing);
      await fillValid(tester);
      await tapSubmit(tester, 'Create Account');
      await settle(tester);
      final body = api.calls.single.body as Map;
      expect(body['role'], 'customer');
      expect(body['phone'], {'dialCode': '+960', 'number': '777 1234'});
      expect(body['acceptTerms'], isTrue);
      expect(body.containsKey('businessName'), isFalse);
      expect(find.text('VERIFY'), findsOneWidget);
    },
  );

  testWidgets(
    'provider variant adds exactly Business / Trade Name with the Become a Provider disclaimer and a provider CTA',
    (tester) async {
      api.on(
        'POST',
        '/v1/auth/register',
        (_) => {
          'user': userJson(),
          'tokens': tokensJson(),
          'verification': sent,
        },
      );
      await pump(tester);
      await fillValid(tester, provider: true);
      expect(
        find.textContaining("you'll list services through Become a Provider"),
        findsOneWidget,
      );
      await tapSubmit(tester, 'Create Provider Account');
      await settle(tester);
      final body = api.calls.single.body as Map;
      expect(body['role'], 'provider');
      expect(body['businessName'], 'Rasheed Plumbing Services');
    },
  );

  testWidgets(
    'client checks are UX only: mismatch and unaccepted terms block with inline copy and no request',
    (tester) async {
      await pump(tester);
      await fillValid(tester);
      await tester.enterText(find.byKey(const Key('reg-confirm')), 'different');
      await tapSubmit(tester, 'Create Account');
      await settle(tester);
      expect(find.text("Passwords don't match"), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.enterText(
        find.byKey(const Key('reg-confirm')),
        'seabreeze-24',
      );
      await tester.ensureVisible(find.byKey(const Key('reg-terms')));
      await tester.tap(find.byKey(const Key('reg-terms'))); // untick
      await tapSubmit(tester, 'Create Account');
      await settle(tester);
      expect(find.text('Please accept the terms to continue.'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'EMAIL_IN_USE renders under the email field with Sign in and Reset password routes',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/register',
        status: 409,
        code: 'EMAIL_IN_USE',
        details: [
          {
            'path': 'email',
            'message': 'This email already has a RaajjePro account.',
          },
        ],
      );
      await pump(tester);
      await fillValid(tester);
      await tapSubmit(tester, 'Create Account');
      await settle(tester);
      expect(
        find.text('This email already has a RaajjePro account.'),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Reset password'), findsOneWidget);
      expect(find.text('aishath@example.mv'), findsOneWidget); // value kept
      await tester.ensureVisible(find.text('Reset password'));
      await tester.tap(find.text('Reset password'));
      await settle(tester);
      expect(find.text('FORGOT'), findsOneWidget);
    },
  );

  testWidgets(
    'PHONE_IN_USE renders under the phone field with the verified-provider copy; no check mark anywhere',
    (tester) async {
      api.fail(
        'POST',
        '/v1/auth/register',
        status: 409,
        code: 'PHONE_IN_USE',
        details: [
          {
            'path': 'phone',
            'message': 'This number belongs to a verified provider account.',
          },
        ],
      );
      await pump(tester);
      await fillValid(tester);
      await tapSubmit(tester, 'Create Account');
      await settle(tester);
      expect(
        find.textContaining(
          'This number belongs to a verified provider account',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('use a different number'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
    },
  );

  testWidgets('VALIDATION_FAILED details map to their fields', (tester) async {
    api.fail(
      'POST',
      '/v1/auth/register',
      status: 400,
      code: 'VALIDATION_FAILED',
      details: [
        {'path': 'password', 'message': 'Too short'},
        {'path': 'phone', 'message': 'Phone number must be 6 to 15 digits'},
      ],
    );
    await pump(tester);
    await fillValid(tester);
    await tapSubmit(tester, 'Create Account');
    await settle(tester);
    expect(find.text('Too short'), findsOneWidget);
    expect(find.text('Phone number must be 6 to 15 digits'), findsOneWidget);
  });

  testWidgets(
    'a foreign dial code shows the welcome hint; offline shows the inline notice',
    (tester) async {
      api.offline('POST', '/v1/auth/register');
      await pump(tester);
      await fillValid(tester);
      await tester.enterText(find.byKey(const Key('reg-dial')), '+44');
      await tester.pump();
      expect(
        find.text('Foreign numbers welcome — 6 to 15 digits.'),
        findsOneWidget,
      );
      await tapSubmit(tester, 'Create Account');
      await settle(tester);
      expect(find.text('No internet connection.'), findsOneWidget);
    },
  );
}
