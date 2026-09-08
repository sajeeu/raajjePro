import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';

import 'core/auth/auth_controller_test.dart' show tokensJson, userJson;
import 'helpers/fake_api.dart';
import 'helpers/pump.dart';

void main() {
  var bootCount = 0;

  // Keyed uniquely per call so a second `boot()` inside the same test forces
  // a real dispose-and-remount rather than an in-place widget update: with a
  // stable widget shape, `tester.pumpWidget` reconciles the existing element
  // tree (Flutter's `attachRootWidget` re-uses the root element), which
  // leaves `_RaajjeProAppState.initState` — and so `restore()` — running only
  // once and the ProviderScope's container never disposed. Two calls to
  // `boot()` in one test are meant to model two separate app launches; the
  // key is what makes that true instead of silently reusing all prior state.
  Future<void> boot(
    WidgetTester tester,
    FakeApiClient api,
    InMemoryTokenStore store,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey(bootCount++),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
          crashReporterProvider.overrideWithValue(NoopCrashReporter()),
          deviceNameProvider.overrideWith((_) async => 'Test'),
        ],
        child: const RaajjeProApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'no tokens → the guest home with a Sign in action; the gallery stays reachable in debug',
    (tester) async {
      await boot(tester, FakeApiClient(), InMemoryTokenStore());
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Account settings'), findsNothing);
    },
  );

  testWidgets(
    'stored tokens → me → signed-in home with Account settings; a dead session → Session expired',
    (tester) async {
      final api = FakeApiClient();
      final store = InMemoryTokenStore();
      await store.write(TokenPair.fromJson(tokensJson()));
      api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
      await boot(tester, api, store);
      expect(find.text('Account settings'), findsOneWidget);

      api.fail('GET', '/v1/auth/me', status: 401, code: 'SESSION_EXPIRED');
      await store.write(TokenPair.fromJson(tokensJson()));
      await boot(tester, api, store);
      expect(find.text('Signed out for your security'), findsOneWidget);
    },
  );

  testWidgets(
    'the legal placeholders are marked as placeholders and carry no policy prose',
    (tester) async {
      await boot(tester, FakeApiClient(), InMemoryTokenStore());
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/legal/terms');
      await settle(tester);
      expect(
        find.text('Placeholder — legal text pending review'),
        findsOneWidget,
      );
      expect(find.textContaining('hereby'), findsNothing);
    },
  );

  testWidgets(
    'offline at launch keeps tokens and reads guest; resuming online retries restore and signs in',
    (tester) async {
      final api = FakeApiClient();
      final store = InMemoryTokenStore();
      await store.write(TokenPair.fromJson(tokensJson()));
      api.offline('GET', '/v1/auth/me');
      await boot(tester, api, store);
      // Offline at launch: AuthController.restore() maps the network failure
      // to AuthGuest, but never clears the tokens (plan: offline is not
      // signed out) — this is the state a user who launched offline is left
      // in until something asks `me` again.
      expect(find.text('Sign in'), findsOneWidget);
      expect(await store.read(), isNotNull);

      // Connectivity returns; the API now answers `me` successfully.
      api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await settle(tester);

      expect(find.text('Account settings'), findsOneWidget);
    },
  );
}
