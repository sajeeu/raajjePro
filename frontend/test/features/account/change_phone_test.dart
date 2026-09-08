import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/presentation/change_phone_screen.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Fixes [AuthController]'s state at construction — same seam
/// `delete_account_test.dart` uses — so the screen sees the account this
/// test wants before it mounts.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {List<Override> extra = const []}) =>
      pumpScreen(
        tester,
        const ChangePhoneScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(
              AuthSignedIn(UserAccount.fromJson(userJson())),
            ),
          ),
          ...extra,
        ],
      );

  /// Every `Text` widget's data, joined, lower-cased — for scanning the
  /// whole tree at once (mirrors `phone_never_verified_test.dart`).
  String allText(WidgetTester tester) =>
      tester.allWidgets.whereType<Text>().map((t) => t.data ?? '').join(' | ');

  testWidgets(
    'the current number is shown as plain text with no check icon and no "verified"',
    (tester) async {
      await pump(tester);
      expect(find.text('Current number: +960 7771234'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.verified), findsNothing);
      expect(find.byIcon(Icons.verified_user), findsNothing);
      expect(allText(tester).toLowerCase().contains('verified'), isFalse);
    },
  );

  testWidgets(
    'uses the same PhoneField widgets as Register (reg-dial / reg-phone keys)',
    (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('reg-dial')), findsOneWidget);
      expect(find.byKey(const Key('reg-phone')), findsOneWidget);
    },
  );

  testWidgets('PHONE_IN_USE renders under the field', (tester) async {
    api.fail('PATCH', '/v1/users/me/phone', status: 409, code: 'PHONE_IN_USE');
    await pump(tester);
    await tester.enterText(find.byKey(const Key('reg-phone')), '7779999');
    await tester.tap(find.text('Save number'));
    await settle(tester);
    expect(
      find.text('This number belongs to a verified provider account.'),
      findsOneWidget,
    );
  });

  testWidgets('VALIDATION_FAILED for phone renders as errorText', (
    tester,
  ) async {
    api.fail(
      'PATCH',
      '/v1/users/me/phone',
      status: 422,
      code: 'VALIDATION_FAILED',
      details: [
        {'path': 'number', 'message': 'Enter 6 to 15 digits'},
      ],
    );
    await pump(tester);
    await tester.enterText(find.byKey(const Key('reg-phone')), '1');
    await tester.tap(find.text('Save number'));
    await settle(tester);
    expect(find.text('Enter 6 to 15 digits'), findsOneWidget);
  });

  testWidgets(
    'success shows "Number updated" and the new number, again with no check icon',
    (tester) async {
      api.on('PATCH', '/v1/users/me/phone', (body) {
        expect((body as Map)['dialCode'], '+960');
        expect(body['number'], '7779999');
        return {
          'id': 'u1',
          'fullName': 'Aishath Naeema',
          'email': 'aishath@example.mv',
          'emailVerified': false,
          'phone': {'dialCode': '+960', 'number': '7779999'},
          'status': 'active',
          'deletionDeadlineAt': null,
          'isProvider': false,
          'createdAt': '2026-09-06T10:00:00.000Z',
        };
      });
      await pump(tester);
      await tester.enterText(find.byKey(const Key('reg-phone')), '7779999');
      await tester.tap(find.text('Save number'));
      await settle(tester);

      expect(
        find.text('Number updated — shown as you entered it'),
        findsOneWidget,
      );
      expect(find.text('Current number: +960 7779999'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.verified), findsNothing);
      final body = allText(tester);
      expect(body.toLowerCase().contains('verified'), isFalse);
    },
  );

  testWidgets('offline shows the inline notice', (tester) async {
    api.offline('PATCH', '/v1/users/me/phone');
    await pump(tester);
    await tester.enterText(find.byKey(const Key('reg-phone')), '7779999');
    await tester.tap(find.text('Save number'));
    await settle(tester);
    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets(
    'a session-expired submit saves the typed number for the round trip, and a later mount restores it',
    (tester) async {
      api.fail(
        'PATCH',
        '/v1/users/me/phone',
        status: 401,
        code: 'SESSION_EXPIRED',
      );
      final store = FormDraftStore();
      await pump(
        tester,
        extra: [formDraftStoreProvider.overrideWithValue(store)],
      );
      await tester.enterText(find.byKey(const Key('reg-phone')), '7770000');
      await tester.tap(find.text('Save number'));
      await settle(tester);

      expect(store.peek(ChangePhoneScreen.routeName), {
        'dialCode': '+960',
        'number': '7770000',
      });

      // A different widget at the root forces a real dispose-and-remount
      // (see `app_gate_test.dart`'s `boot` helper) — pumping the same
      // screen shape again would reconcile onto the existing `State` and
      // its live `TextEditingController`s rather than re-running `initState`.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(
        tester,
        extra: [formDraftStoreProvider.overrideWithValue(store)],
      );
      expect(find.text('7770000'), findsOneWidget);
      expect(store.peek(ChangePhoneScreen.routeName), isNull);
    },
  );
}
