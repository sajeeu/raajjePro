import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/presentation/change_password_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {List<Override> extra = const []}) =>
      pumpScreen(
        tester,
        const ChangePasswordScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          ...extra,
        ],
        routes: {'/': (_) => const Scaffold(body: Text('HOME'))},
      );

  testWidgets('the new-password helper is shown before submission', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('At least 8 characters'), findsOneWidget);
  });

  testWidgets(
    "a mismatch blocks locally with \"Passwords don't match\" and never calls the API",
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('cp-current')), 'oldpass1');
      await tester.enterText(find.byKey(const Key('cp-new')), 'newpassword');
      await tester.enterText(
        find.byKey(const Key('cp-confirm')),
        'somethingelse',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Change password'));
      await tester.pump();

      expect(find.text("Passwords don't match"), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets('too-short blocks locally and never calls the API', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('cp-current')), 'oldpass1');
    await tester.enterText(find.byKey(const Key('cp-new')), 'short');
    await tester.enterText(find.byKey(const Key('cp-confirm')), 'short');
    await tester.tap(find.widgetWithText(AppButton, 'Change password'));
    await tester.pump();

    expect(find.text('At least 8 characters'), findsWidgets);
    expect(api.calls, isEmpty);
  });

  testWidgets('INVALID_CREDENTIALS renders under the current-password field', (
    tester,
  ) async {
    api.fail(
      'POST',
      '/v1/users/me/change-password',
      status: 401,
      code: 'INVALID_CREDENTIALS',
    );
    await pump(tester);
    await tester.enterText(find.byKey(const Key('cp-current')), 'wrong123');
    await tester.enterText(find.byKey(const Key('cp-new')), 'newpassword');
    await tester.enterText(find.byKey(const Key('cp-confirm')), 'newpassword');
    await tester.tap(find.widgetWithText(AppButton, 'Change password'));
    await settle(tester);

    expect(find.text('Your current password is not right'), findsOneWidget);
  });

  testWidgets(
    'an unmapped code shows the shared generic banner, never the raw server message (final review #8)',
    (tester) async {
      api.fail(
        'POST',
        '/v1/users/me/change-password',
        status: 500,
        code: 'INTERNAL_ERROR',
        message: 'oh no',
      );
      await pump(tester);
      await tester.enterText(find.byKey(const Key('cp-current')), 'oldpass1');
      await tester.enterText(find.byKey(const Key('cp-new')), 'newpassword');
      await tester.enterText(
        find.byKey(const Key('cp-confirm')),
        'newpassword',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Change password'));
      await settle(tester);

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('oh no'), findsNothing);
    },
  );

  testWidgets(
    'success calls the change-password endpoint, shows the snackbar and pops back to the previous screen',
    (tester) async {
      api.on('POST', '/v1/users/me/change-password', (body) {
        expect((body as Map)['currentPassword'], 'oldpass1');
        expect(body['newPassword'], 'newpassword');
        return <String, dynamic>{};
      });
      // A real push/pop, not a bare `home:` screen (which has nothing below
      // it to pop back to) — same shape as
      // `delete_account_test.dart`'s "Keep my account pops back" test.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            initialRoute: '/host',
            routes: {
              '/host': (context) => Scaffold(
                body: Center(
                  child: AppButton.primary(
                    label: 'Go to change password',
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/account/password'),
                  ),
                ),
              ),
              '/account/password': (_) => const ChangePasswordScreen(),
            },
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Go to change password'));
      await settle(tester);

      await tester.enterText(find.byKey(const Key('cp-current')), 'oldpass1');
      await tester.enterText(find.byKey(const Key('cp-new')), 'newpassword');
      await tester.enterText(
        find.byKey(const Key('cp-confirm')),
        'newpassword',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Change password'));
      await settle(tester);

      expect(
        find.text('Password changed — other devices were signed out'),
        findsOneWidget,
      );
      expect(find.text('Go to change password'), findsOneWidget);
    },
  );

  testWidgets('offline shows the inline notice', (tester) async {
    api.offline('POST', '/v1/users/me/change-password');
    await pump(tester);
    await tester.enterText(find.byKey(const Key('cp-current')), 'oldpass1');
    await tester.enterText(find.byKey(const Key('cp-new')), 'newpassword');
    await tester.enterText(find.byKey(const Key('cp-confirm')), 'newpassword');
    await tester.tap(find.widgetWithText(AppButton, 'Change password'));
    await settle(tester);

    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets(
    'a session-expired submit does not crash, and saves nothing — every field here is a password',
    (tester) async {
      api.fail(
        'POST',
        '/v1/users/me/change-password',
        status: 401,
        code: 'SESSION_EXPIRED',
      );
      final store = FormDraftStore();
      await pump(
        tester,
        extra: [formDraftStoreProvider.overrideWithValue(store)],
      );
      await tester.enterText(find.byKey(const Key('cp-current')), 'oldpass1');
      await tester.enterText(find.byKey(const Key('cp-new')), 'newpassword');
      await tester.enterText(
        find.byKey(const Key('cp-confirm')),
        'newpassword',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Change password'));
      await settle(tester);

      // The controller ruling: no password is ever saved to the draft
      // store. The key is still marked (an empty map, from `run`'s
      // unconditional save on SESSION_EXPIRED) but carries nothing to
      // restore.
      expect(store.peek(ChangePasswordScreen.routeName), <String, String>{});

      // A different widget at the root forces a real dispose-and-remount
      // (see `app_gate_test.dart`'s `boot` helper) — pumping the same
      // screen shape again would reconcile onto the existing `State` and
      // its live `TextEditingController`s rather than re-running `initState`.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(
        tester,
        extra: [formDraftStoreProvider.overrideWithValue(store)],
      );
      final field = tester.widget<AppTextField>(
        find.byKey(const Key('cp-current')),
      );
      expect(field.controller!.text, isEmpty);
    },
  );
}
