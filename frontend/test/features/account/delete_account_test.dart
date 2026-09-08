import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/presentation/delete_account_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Fixes [AuthController]'s state at construction, so [DeleteController]'s
/// `build()` (which reads `authControllerProvider` once, via `ref.read`, not
/// `ref.watch`) sees the account this test wants before the screen mounts.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

UserAccount _activeUser() => UserAccount.fromJson(userJson());
UserAccount _frozenUser(DateTime deadline) => UserAccount.fromJson({
  ...userJson(status: 'frozen'),
  'deletionDeadlineAt': deadline.toIso8601String(),
});

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {required UserAccount user}) =>
      pumpScreen(
        tester,
        const DeleteAccountScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(AuthSignedIn(user)),
          ),
        ],
        routes: {'/': (_) => const Scaffold(body: Text('HOME'))},
      );

  testWidgets(
    'confirm shows all four facts and a disabled destructive button',
    (tester) async {
      await pump(tester, user: _activeUser());
      expect(find.text('Delete your account'), findsOneWidget);
      for (final fact in [
        'Your account freezes at once — no new bookings, no new listings, hidden from search.',
        'Deletion completes when your open bookings finish — and within 30 days regardless.',
        'Reviews you wrote stay, with your name removed.',
        'Identity documents are deleted outright — not anonymised.',
      ]) {
        expect(find.text(fact), findsOneWidget);
      }
      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Delete my account'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('typing delete (any case) enables the destructive button', (
    tester,
  ) async {
    await pump(tester, user: _activeUser());
    await tester.enterText(find.byKey(const Key('delete-confirm')), 'delete');
    await tester.pump();
    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Delete my account'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Keep my account pops back to the previous screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(AuthSignedIn(_activeUser())),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          initialRoute: '/host',
          routes: {
            '/host': (context) => Scaffold(
              body: Center(
                child: AppButton.primary(
                  label: 'Go to delete',
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/account/delete'),
                ),
              ),
            ),
            '/account/delete': (_) => const DeleteAccountScreen(),
          },
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Go to delete'));
    await settle(tester);
    expect(find.text('Delete your account'), findsOneWidget);

    await tester.tap(find.text('Keep my account'));
    await settle(tester);
    expect(find.text('Go to delete'), findsOneWidget);
  });

  testWidgets(
    'confirming calls the deletion-request endpoint and shows the frozen card; no refusal copy',
    (tester) async {
      api.on(
        'POST',
        '/v1/users/me/deletion-request',
        (_) => {
          'deletionRequestedAt': '2026-09-06T10:00:00.000Z',
          'deletionDeadlineAt': '2026-10-06T10:00:00.000Z',
        },
      );
      await pump(tester, user: _activeUser());
      await tester.enterText(find.byKey(const Key('delete-confirm')), 'DELETE');
      await tester.pump();
      await tester.tap(find.text('Delete my account'));
      await settle(tester);

      expect(find.text('Your deletion request is in'), findsOneWidget);
      for (final fact in [
        'Deletion completes when your open bookings finish — and within 30 days regardless.',
        'Reviews you wrote stay, with your name removed.',
        'Identity documents are deleted outright — not anonymised.',
      ]) {
        expect(find.text(fact), findsOneWidget);
      }
      expect(find.textContaining('6 Oct 2026'), findsOneWidget);

      final body = tester.allWidgets
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join(' | ')
          .toLowerCase();
      expect(body.contains("can't delete"), isFalse);
      expect(body.contains('cannot delete'), isFalse);
      expect(body.contains('refused'), isFalse);
      expect(body.contains('rejected'), isFalse);
    },
  );

  testWidgets(
    'offline: the offline notice renders, and the account is not shown as frozen',
    (tester) async {
      api.offline('POST', '/v1/users/me/deletion-request');
      await pump(tester, user: _activeUser());
      await tester.enterText(find.byKey(const Key('delete-confirm')), 'DELETE');
      await tester.pump();
      await tester.tap(find.text('Delete my account'));
      await settle(tester);

      expect(find.text('No internet connection.'), findsOneWidget);
      // Still the confirm card — never the frozen one.
      expect(find.text('Delete your account'), findsOneWidget);
      expect(find.text('Your deletion request is in'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeleteAccountScreen)),
      );
      final auth = container.read(authControllerProvider);
      expect(auth, isA<AuthSignedIn>());
      expect((auth as AuthSignedIn).user.status, AccountStatus.active);
    },
  );

  testWidgets('a Done tap goes home', (tester) async {
    api.on(
      'POST',
      '/v1/users/me/deletion-request',
      (_) => {
        'deletionRequestedAt': '2026-09-06T10:00:00.000Z',
        'deletionDeadlineAt': '2026-10-06T10:00:00.000Z',
      },
    );
    await pump(tester, user: _activeUser());
    await tester.enterText(find.byKey(const Key('delete-confirm')), 'DELETE');
    await tester.pump();
    await tester.tap(find.text('Delete my account'));
    await settle(tester);

    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets(
    'a second visit for an already-frozen user goes straight to the frozen card',
    (tester) async {
      await pump(tester, user: _frozenUser(DateTime.utc(2026, 10, 6, 10)));
      expect(find.text('Your deletion request is in'), findsOneWidget);
      expect(find.textContaining('6 Oct 2026'), findsOneWidget);
      expect(
        api.calls.any(
          (c) =>
              c.method == 'POST' && c.path == '/v1/users/me/deletion-request',
        ),
        isFalse,
      );
    },
  );
}
