import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/features/account/presentation/active_sessions_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const ActiveSessionsScreen(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 6, 10)),
    ],
  );

  Map<String, dynamic> sessionJson({
    required String id,
    required String deviceName,
    required String lastSeenAt,
    required bool current,
  }) => {
    'id': id,
    'deviceName': deviceName,
    'createdAt': '2026-08-01T10:00:00.000Z',
    'lastSeenAt': lastSeenAt,
    'current': current,
  };

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    api.gate = Completer<void>();
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
    'populated: This device + Sign out on the current row, Revoke on the other, no IP anywhere',
    (tester) async {
      api.on(
        'GET',
        '/v1/auth/sessions',
        (_) => {
          '_list': [
            sessionJson(
              id: 'a',
              deviceName: 'iPhone 14',
              lastSeenAt: '2026-09-06T10:00:00.000Z',
              current: true,
            ),
            sessionJson(
              id: 'b',
              deviceName: 'Pixel 7',
              lastSeenAt: '2026-09-03T10:00:00.000Z',
              current: false,
            ),
          ],
        },
      );
      await pump(tester);

      expect(find.text('This device'), findsOneWidget);
      expect(find.text('active now'), findsOneWidget);
      expect(find.text('Last used 3 days ago'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Sign out'), findsOneWidget);
      // The current row never shows Revoke — only one Revoke control exists,
      // on the other device's row.
      expect(find.widgetWithText(AppButton, 'Revoke'), findsOneWidget);

      final body = tester.allWidgets
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(body), isFalse);
    },
  );

  testWidgets(
    'tapping Revoke opens a confirming sheet; confirming revokes only that device',
    (tester) async {
      api.on(
        'GET',
        '/v1/auth/sessions',
        (_) => {
          '_list': [
            sessionJson(
              id: 'a',
              deviceName: 'iPhone 14',
              lastSeenAt: '2026-09-06T10:00:00.000Z',
              current: true,
            ),
            sessionJson(
              id: 'b',
              deviceName: 'Pixel 7',
              lastSeenAt: '2026-09-03T10:00:00.000Z',
              current: false,
            ),
          ],
        },
      );
      api.on('DELETE', '/v1/auth/sessions/b', (_) => {'value': null});
      await pump(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Revoke'));
      await settle(tester);
      expect(find.text('Sign out Pixel 7?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-revoke')));
      await settle(tester);

      expect(
        api.calls.any(
          (c) => c.method == 'DELETE' && c.path == '/v1/auth/sessions/b',
        ),
        isTrue,
      );
      expect(find.text('Pixel 7'), findsNothing);
      expect(find.text('iPhone 14'), findsOneWidget);
      expect(
        find.text('Pixel 7 signed out — only that device'),
        findsOneWidget,
      );
    },
  );

  testWidgets('error shows EmptyState with retry', (tester) async {
    api.offline('GET', '/v1/auth/sessions');
    await pump(tester);
    expect(find.text("Couldn't load your devices"), findsOneWidget);
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {'_list': <Map<String, dynamic>>[]},
    );
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(
      find.text(
        "Everywhere you're signed in. Revoking a device signs out only that device.",
      ),
      findsOneWidget,
    );
  });
}
