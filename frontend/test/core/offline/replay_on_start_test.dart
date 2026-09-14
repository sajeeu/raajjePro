import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';
import 'package:raajjepro/core/offline/offline_queue_store.dart';
import 'package:raajjepro/core/offline/pending_request.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'offline_queue_test.dart' show FakeQueueStore;

/// What a cold start does with what the last run left behind.
///
/// §Phase 9's queue holds **data rather than closures**, in a file, precisely
/// so a request outlives the process that made it. Found on a device
/// (2026-09-14): it does outlive it, and nothing woke it. `replay()` ran only
/// from `ServiceWizardScreen`'s own lifecycle listener, from
/// `NoConnectionView`'s retry button, or from the next `submit()` — none of
/// which happen to a provider who typed offline, killed the app and reopened
/// it. The file held the PATCH across a force-stop, a reconnect and a fresh
/// sign-in, and the listing on the server still had no name.
///
/// It is worse than it sounds today: the only route back into a draft is
/// §Phase 10's My Services, which is an `UnbuiltScreen`, so nothing the
/// provider can reach would drain it either.
///
/// The queue is app-wide rather than the wizard's (§0.0 item 14 allows one),
/// so the drain belongs at the root, which is what this asserts.
void main() {
  late FakeApiClient api;
  late FakeQueueStore store;
  var bootCount = 0;

  setUp(() {
    api = FakeApiClient();
    store = FakeQueueStore();
  });

  /// Keyed per call so a second boot is a real remount rather than an
  /// in-place update — the same reason `app_gate_test.dart` keys its own.
  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey(bootCount++),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          offlineQueueStoreProvider.overrideWithValue(store),
          crashReporterProvider.overrideWithValue(NoopCrashReporter()),
          deviceNameProvider.overrideWith((_) async => 'Test'),
        ],
        child: const RaajjeProApp(),
      ),
    );
    await settle(tester);
  }

  PendingRequest stranded() => const PendingRequest(
    id: 'q1-from-the-last-run',
    method: 'PATCH',
    path: '/v1/providers/me/listings/l1',
    label: 'Saving a step of the service wizard',
    mergeKey: 'listing:l1:patch',
    body: {'name': 'Wiring'},
  );

  testWidgets('a request the last run queued is sent when the app starts', (
    tester,
  ) async {
    store.saved = [stranded()];
    api.on('PATCH', '/v1/providers/me/listings/l1', (_) => {'id': 'l1'});

    await boot(tester);

    // The wizard is never opened here, and that is the point: the provider
    // lands wherever the app starts, which after a cold start is the guest
    // home.
    expect(
      api.calls.where((c) => c.path == '/v1/providers/me/listings/l1'),
      hasLength(1),
      reason: 'the stranded PATCH should go out on start, without the wizard',
    );
    expect(store.saved, isEmpty, reason: 'and be dropped once it lands');
  });

  testWidgets('a request the network still refuses stays for the next run', (
    tester,
  ) async {
    // The other half: draining on start must not *discard* what it cannot
    // send, or a cold start offline would lose the very work the file exists
    // to protect.
    store.saved = [stranded()];
    api.offline('PATCH', '/v1/providers/me/listings/l1');

    await boot(tester);

    expect(store.saved, hasLength(1));
    expect(store.saved.single.body, const {'name': 'Wiring'});
  });
}
