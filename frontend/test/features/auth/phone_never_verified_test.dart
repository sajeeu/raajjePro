import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/features/account/presentation/change_phone_screen.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// The design rule (root CLAUDE.md §0.0 item 6; frontend/CLAUDE.md): a phone
/// number is collected, unique from Bronze upward, and NEVER verified.
/// Uniqueness is not ownership, so no screen may render one with a check
/// mark or the word "verified" — both assertions below must fail the moment
/// someone adds a tick next to a number.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

const _tickIcons = [
  Icons.check_circle,
  Icons.check_circle_outline,
  Icons.verified,
  Icons.verified_user,
];
final _phoneLike = RegExp(r'\+\d[\d ]{5,}');

/// A `Text`'s plain content, whether it was built with `data` or as a
/// `Text.rich`/`Text.textSpan` tree — a tick or the word "verified" hidden
/// inside a `TextSpan` is just as much a defect as one in `data`.
String? _plainText(Text widget) =>
    widget.data ?? widget.textSpan?.toPlainText();

/// (a) no tick icon shares a `Row` with a `Text` that looks like a phone
/// number; (b) no single `Text` both looks like a phone number and also
/// contains the word "verified". Both walk the Row's whole subtree — not
/// just its immediate children — so a tick or a phone number one or more
/// `Padding`/`Expanded`/`SizedBox` layers deep is still caught.
void _assertNoVerifiedPhone(WidgetTester tester) {
  for (final rowElement in find.byType(Row).evaluate()) {
    final rowFinder = find.byWidget(rowElement.widget);
    final texts = find
        .descendant(of: rowFinder, matching: find.byType(Text))
        .evaluate()
        .map((e) => _plainText(e.widget as Text));
    final hasPhoneText = texts.any((t) => t != null && _phoneLike.hasMatch(t));
    if (!hasPhoneText) continue;
    final hasTick = find
        .descendant(of: rowFinder, matching: find.byType(Icon))
        .evaluate()
        .map((e) => (e.widget as Icon).icon)
        .any(_tickIcons.contains);
    expect(
      hasTick,
      isFalse,
      reason: 'a tick icon sits in a Row next to a phone-shaped Text',
    );
  }

  for (final element in find.byType(Text).evaluate()) {
    final text = _plainText(element.widget as Text);
    if (text == null || !_phoneLike.hasMatch(text)) continue;
    expect(
      text.toLowerCase().contains('verified'),
      isFalse,
      reason: 'a phone-shaped Text also contains "verified": "$text"',
    );
  }
}

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  testWidgets('Register after PHONE_IN_USE', (tester) async {
    api.fail('POST', '/v1/auth/register', status: 409, code: 'PHONE_IN_USE');
    await pumpScreen(
      tester,
      const RegisterScreen(),
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ],
    );
    await tester.enterText(find.byKey(const Key('reg-name')), 'Aishath Naeema');
    await tester.enterText(
      find.byKey(const Key('reg-email')),
      'aishath@example.mv',
    );
    await tester.enterText(find.byKey(const Key('reg-dial')), '+960');
    await tester.enterText(find.byKey(const Key('reg-phone')), '7771234');
    await tester.enterText(
      find.byKey(const Key('reg-password')),
      'correcthorse',
    );
    await tester.enterText(
      find.byKey(const Key('reg-confirm')),
      'correcthorse',
    );
    // The form is taller than the fixed test viewport (`pump.dart`'s 412x915
    // mobile frame) — scroll each control into view before tapping it, same
    // as `register_screen_test.dart`.
    await tester.ensureVisible(find.byKey(const Key('reg-terms')));
    await tester.tap(find.byKey(const Key('reg-terms')));
    await tester.pump();
    final submit = find.widgetWithText(AppButton, 'Create Account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await settle(tester);

    expect(find.textContaining('verified provider account'), findsOneWidget);
    _assertNoVerifiedPhone(tester);
  });

  testWidgets('Change phone before success', (tester) async {
    await pumpScreen(
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
      ],
    );
    _assertNoVerifiedPhone(tester);
  });

  testWidgets('Change phone after success', (tester) async {
    api.on(
      'PATCH',
      '/v1/users/me/phone',
      (_) => {
        'id': 'u1',
        'fullName': 'Aishath Naeema',
        'email': 'aishath@example.mv',
        'emailVerified': false,
        'phone': {'dialCode': '+960', 'number': '7779999'},
        'status': 'active',
        'deletionDeadlineAt': null,
        'isProvider': false,
        'createdAt': '2026-09-06T10:00:00.000Z',
      },
    );
    await pumpScreen(
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
      ],
    );
    await tester.enterText(find.byKey(const Key('reg-phone')), '7779999');
    await tester.tap(find.text('Save number'));
    await settle(tester);

    expect(find.text('Current number: +960 7779999'), findsOneWidget);
    _assertNoVerifiedPhone(tester);
  });

  testWidgets('Account settings populated', (tester) async {
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': <dynamic>[]});
    await pumpScreen(
      tester,
      const AccountSettingsScreen(),
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        authControllerProvider.overrideWith(
          () => _FixedAuthController(
            AuthSignedIn(UserAccount.fromJson(userJson())),
          ),
        ),
      ],
    );
    _assertNoVerifiedPhone(tester);
  });

  testWidgets(
    'negative fixture: a tick wrapped in Padding inside the Row is still caught',
    (tester) async {
      // Proves the helper recurses the Row's subtree rather than only its
      // immediate children (final review #4) — an icon or phone-shaped Text
      // one `Padding` layer deep must still fail both assertions.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Text('+960 7771234'),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.verified),
                ),
              ],
            ),
          ),
        ),
      );
      expect(() => _assertNoVerifiedPhone(tester), throwsA(isA<TestFailure>()));
    },
  );
}
