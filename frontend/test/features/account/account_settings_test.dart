import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());
  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const AccountSettingsScreen(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
    ],
    routes: {
      for (final r in [
        '/account/password',
        '/account/change-email',
        '/account/phone',
        '/account/sessions',
        '/account/download',
        '/account/delete',
      ])
        r: (_) => Scaffold(body: Text('ROUTE $r')),
    },
  );

  testWidgets('loading shows skeleton rows, not a spinner', (tester) async {
    api.gate = Completer<void>();
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {'_list': <Map<String, dynamic>>[]},
    );
    await pump(tester);
    expect(find.byType(SkeletonLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    api.gate!.complete();
    await settle(tester);
  });

  testWidgets(
    'populated: the six rows, the delete row, the name·email header, no Saved preferences and no toggles',
    (tester) async {
      api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
      api.on(
        'GET',
        '/v1/auth/sessions',
        (_) => {
          '_list': [
            {
              'id': 'a',
              'deviceName': 'iPhone 14',
              'createdAt': '2026-09-06T10:00:00.000Z',
              'lastSeenAt': '2026-09-06T10:00:00.000Z',
              'current': true,
            },
            {
              'id': 'b',
              'deviceName': 'Pixel 7',
              'createdAt': '2026-09-01T10:00:00.000Z',
              'lastSeenAt': '2026-09-03T10:00:00.000Z',
              'current': false,
            },
          ],
        },
      );
      await pump(tester);
      expect(find.text('Aishath Naeema · aishath@example.mv'), findsOneWidget);
      for (final t in [
        'Change password',
        'Change email',
        'Change phone',
        'Active sessions',
        'Download my data',
        'Delete account',
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('2 devices signed in'), findsOneWidget);
      expect(
        find.text('Accepted immediately, completes within 30 days'),
        findsOneWidget,
      );
      expect(find.text('Saved preferences'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(AppToggle), findsNothing);
      await tester.tap(find.text('Active sessions'));
      await settle(tester);
      expect(find.text('ROUTE /account/sessions'), findsOneWidget);
    },
  );

  testWidgets('error: EmptyState with retry, then populated', (tester) async {
    api.offline('GET', '/v1/auth/me');
    await pump(tester);
    expect(find.text("Couldn't load settings"), findsOneWidget);
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {'_list': <Map<String, dynamic>>[]},
    );
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets(
    'frozen: a banner with the deadline and the delete row reads Deletion in progress',
    (tester) async {
      api.on(
        'GET',
        '/v1/auth/me',
        (_) => {
          ...userJson(status: 'frozen'),
          'deletionDeadlineAt': '2026-10-06T10:00:00.000Z',
        },
      );
      api.on(
        'GET',
        '/v1/auth/sessions',
        (_) => {'_list': <Map<String, dynamic>>[]},
      );
      await pump(tester);
      expect(find.textContaining('Deletion in progress'), findsOneWidget);
      expect(find.textContaining('6 Oct 2026'), findsOneWidget);
    },
  );
}
