import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/presentation/change_email_screen.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {List<Override> extra = const []}) =>
      pumpScreen(
        tester,
        const ChangeEmailScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          ...extra,
        ],
        routes: {
          '/': (_) => const Scaffold(body: Text('HOME')),
          VerifyEmailScreen.routeName: (context) => VerifyEmailScreen(
            args: VerifyEmailArgs.fromRouteArguments(
              ModalRoute.of(context)!.settings.arguments,
            ),
          ),
        },
      );

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('ce-email')), 'new@example.mv');
    await tester.enterText(
      find.byKey(const Key('ce-password')),
      'correcthorse',
    );
    await tester.tap(find.text('Send code'));
    await settle(tester);
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(Key('otp-$i')), code[i]);
      await tester.pump();
    }
  }

  testWidgets('EMAIL_IN_USE renders under the email field', (tester) async {
    api.fail(
      'POST',
      '/v1/users/me/change-email/request',
      status: 409,
      code: 'EMAIL_IN_USE',
    );
    await pump(tester);
    await fillAndSubmit(tester);
    expect(
      find.text('This email already has a RaajjePro account.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'EMAIL_UNCHANGED renders under the field as "That is already your email address"',
    (tester) async {
      api.fail(
        'POST',
        '/v1/users/me/change-email/request',
        status: 409,
        code: 'EMAIL_UNCHANGED',
      );
      await pump(tester);
      await fillAndSubmit(tester);
      expect(find.text('That is already your email address'), findsOneWidget);
    },
  );

  testWidgets('INVALID_CREDENTIALS renders under the password field', (
    tester,
  ) async {
    api.fail(
      'POST',
      '/v1/users/me/change-email/request',
      status: 401,
      code: 'INVALID_CREDENTIALS',
    );
    await pump(tester);
    await fillAndSubmit(tester);
    expect(find.text('Your current password is not right'), findsOneWidget);
  });

  testWidgets('offline shows the inline notice', (tester) async {
    api.offline('POST', '/v1/users/me/change-email/request');
    await pump(tester);
    await fillAndSubmit(tester);
    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets(
    'success calls change-email/request with the new address and current password, and navigates to Verify Email showing the new address and "Verify your new email"',
    (tester) async {
      api.on('POST', '/v1/users/me/change-email/request', (body) {
        expect((body as Map)['newEmail'], 'new@example.mv');
        expect(body['currentPassword'], 'correcthorse');
        return {
          'status': 'sent',
          'expiresAt': '2026-09-07T10:10:00.000Z',
          'resendAvailableAt': '2026-09-07T10:01:00.000Z',
        };
      });
      await pump(tester);
      await fillAndSubmit(tester);

      expect(find.text('Verify your new email'), findsOneWidget);
      expect(find.text('new@example.mv'), findsOneWidget);
    },
  );

  testWidgets(
    'on the pushed Verify Email screen, confirming with the change-email code shows "Email changed"',
    (tester) async {
      api.on(
        'POST',
        '/v1/users/me/change-email/request',
        (_) => {
          'status': 'sent',
          'expiresAt': '2026-09-07T10:10:00.000Z',
          'resendAvailableAt': '2026-09-07T10:01:00.000Z',
        },
      );
      api.on('POST', '/v1/users/me/change-email/confirm', (body) {
        expect((body as Map)['code'], '123456');
        return {
          'id': 'u1',
          'fullName': 'Aishath Naeema',
          'email': 'new@example.mv',
          'emailVerified': true,
          'phone': {'dialCode': '+960', 'number': '7771234'},
          'status': 'active',
          'deletionDeadlineAt': null,
          'isProvider': false,
          'createdAt': '2026-09-06T10:00:00.000Z',
        };
      });
      await pump(tester);
      await fillAndSubmit(tester);
      expect(find.text('Verify your new email'), findsOneWidget);

      await typeCode(tester, '123456');
      await tester.tap(find.text('Verify Email'));
      await settle(tester);

      expect(find.text('Email changed'), findsOneWidget);
    },
  );

  testWidgets(
    'a draft saved under /account/change-email is restored into the new-email field on initState, and taken so a second mount does not see it again',
    (tester) async {
      final store = FormDraftStore()
        ..save('/account/change-email', {'newEmail': 'restored@example.mv'});
      await pump(
        tester,
        extra: [formDraftStoreProvider.overrideWithValue(store)],
      );

      expect(find.text('restored@example.mv'), findsOneWidget);
      expect(store.peek('/account/change-email'), isNull);
    },
  );

  testWidgets(
    'a session-expired submit saves the typed address — never the password — for the round trip',
    (tester) async {
      api.fail(
        'POST',
        '/v1/users/me/change-email/request',
        status: 401,
        code: 'SESSION_EXPIRED',
      );
      final store = FormDraftStore();
      await pump(
        tester,
        extra: [formDraftStoreProvider.overrideWithValue(store)],
      );
      await fillAndSubmit(tester);

      expect(store.peek('/account/change-email'), {
        'newEmail': 'new@example.mv',
      });
    },
  );
}
