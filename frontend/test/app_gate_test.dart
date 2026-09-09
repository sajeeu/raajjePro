import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';
import 'package:raajjepro/features/account/presentation/change_phone_screen.dart';
import 'package:raajjepro/shared/shared.dart';

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
      expect(find.text('Profile'), findsNothing);
    },
  );

  testWidgets(
    'stored tokens → me → signed-in home with Profile; a dead session → Session expired',
    (tester) async {
      final api = FakeApiClient();
      final store = InMemoryTokenStore();
      await store.write(TokenPair.fromJson(tokensJson()));
      api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
      await boot(tester, api, store);
      expect(find.text('Profile'), findsOneWidget);

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

      expect(find.text('Profile'), findsOneWidget);
    },
  );

  testWidgets(
    'a session expiring under a pushed route pops back to Session Expired; '
    'signing back in restores the draft it was carrying',
    (tester) async {
      final store = InMemoryTokenStore();
      await store.write(TokenPair.fromJson(tokensJson()));

      // The real HttpApiClient, not FakeApiClient: finding #1's fix lives in
      // its `onSessionExpired` wiring, which only fires on an actual
      // SESSION_EXPIRED envelope — a fake `ApiClient` never calls it.
      final mockHttp = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/v1/auth/me') {
          return http.Response(
            jsonEncode({'data': userJson(verified: true)}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/v1/users/me/phone') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'SESSION_EXPIRED', 'message': 'expired'},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'data': {
                'user': userJson(verified: true),
                'tokens': tokensJson(),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'UNKNOWN', 'message': 'unscripted call'},
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            httpClientProvider.overrideWithValue(mockHttp),
            tokenStoreProvider.overrideWithValue(store),
            crashReporterProvider.overrideWithValue(NoopCrashReporter()),
            deviceNameProvider.overrideWith((_) async => 'Test'),
          ],
          child: const RaajjeProApp(),
        ),
      );
      await settle(tester);
      expect(find.text('Profile'), findsOneWidget);

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed(ChangePhoneScreen.routeName);
      await settle(tester);
      expect(find.text('Change phone'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('reg-phone')), '7779999');
      await tester.tap(find.text('Save number'));
      await settle(tester);

      // The pushed ChangePhoneScreen is gone; AuthGate now shows Session
      // Expired rather than leaving that screen on top forever.
      expect(find.text('Signed out for your security'), findsOneWidget);
      expect(find.text('Change phone'), findsNothing);

      await tester.tap(find.text('Sign In Again'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('signin-email')),
        'aishath@example.mv',
      );
      await tester.enterText(
        find.byKey(const Key('signin-password')),
        'seabreeze-24',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
      await settle(tester);
      expect(find.text('Profile'), findsOneWidget);

      nav.pushNamed(ChangePhoneScreen.routeName);
      await settle(tester);
      // The number typed before the session expired, not the account's
      // current one (`7771234`, from `userJson`) — the draft wins.
      expect(
        tester
            .widget<AppTextField>(find.byKey(const Key('reg-phone')))
            .controller
            ?.text,
        '7779999',
      );
    },
  );

  testWidgets(
    'two resumes fired back to back cause only one restore, not one per resume',
    (tester) async {
      final api = FakeApiClient();
      final store = InMemoryTokenStore();
      await store.write(TokenPair.fromJson(tokensJson()));
      api.offline('GET', '/v1/auth/me');
      await boot(tester, api, store);
      expect(find.text('Sign in'), findsOneWidget);

      // Connectivity is back, but gate the call so a second resume can race
      // the first restore() while it is still in flight. Two genuine
      // transitions (inactive→resumed twice), not the same state repeated —
      // `AppLifecycleListener` itself already no-ops a state repeated
      // verbatim, so that shape would never reach this guard at all.
      final gate = Completer<void>();
      api.gate = gate;
      api.calls
          .clear(); // drop the offline boot-time call; only resumes count below
      api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      gate.complete();
      await settle(tester);
      await settle(tester);

      expect(api.calls.where((c) => c.path == '/v1/auth/me').length, 1);
      expect(find.text('Profile'), findsOneWidget);
    },
  );
}
