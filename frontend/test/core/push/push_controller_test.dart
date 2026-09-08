import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/push/installation_id.dart';
import 'package:raajjepro/core/push/push_controller.dart';
import 'package:raajjepro/core/push/push_messaging.dart';

import '../../helpers/fake_api.dart';

/// A scriptable stand-in for FCM/APNs. Neither vendor exists
/// (docs/decisions/15-phase-3c-push.md), so what these tests assert is what
/// the controller ASKED the vendor and the API to do.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({
    this.available = true,
    this.permission = PushPermission.granted,
    this.deviceToken = 'tok-abc',
  });

  bool available;
  PushPermission permission;
  String? deviceToken;
  int permissionRequests = 0;

  // ignore: close_sinks — closed in tearDown; the lint cannot see across it.
  final refreshes = StreamController<String>.broadcast();
  // ignore: close_sinks — as above.
  final messages = StreamController<PushPayload>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Future<PushPermission> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<PushPermission> currentPermission() async => permission;

  @override
  Future<String?> token() async => deviceToken;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Stream<PushPayload> get onMessage => messages.stream;
}

void main() {
  late FakeApiClient api;
  late FakePushMessaging messaging;
  late ProviderContainer container;

  ProviderContainer build() => ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      pushMessagingProvider.overrideWithValue(messaging),
      installationIdProvider.overrideWithValue(
        InMemoryInstallationIdStore('install-1'),
      ),
    ],
  );

  setUp(() {
    api = FakeApiClient();
    api.on('POST', '/v1/push/devices', (_) => {'data': <String, dynamic>{}});
    api.on('POST', '/v1/push/permission', (_) => {'data': <String, dynamic>{}});
    api.on(
      'DELETE',
      '/v1/push/devices/install-1',
      (_) => {'data': <String, dynamic>{}},
    );
    messaging = FakePushMessaging();
    container = build();
  });
  tearDown(() {
    container.dispose();
    messaging.refreshes.close();
    messaging.messages.close();
  });

  test('registers the device token under a stable installation id', () async {
    await container.read(pushControllerProvider.notifier).start();

    final call = api.calls.firstWhere((c) => c.path == '/v1/push/devices');
    final body = call.body! as Map<String, dynamic>;
    expect(body['installationId'], 'install-1');
    expect(body['token'], 'tok-abc');
    expect(body['permission'], 'granted');
    expect(container.read(pushControllerProvider).registered, isTrue);
  });

  test(
    'a token refresh re-registers the same install, never a second device',
    () async {
      await container.read(pushControllerProvider.notifier).start();
      messaging.refreshes.add('tok-rotated');
      await Future<void>.delayed(Duration.zero);

      final registrations = api.calls
          .where((c) => c.path == '/v1/push/devices')
          .toList();
      expect(registrations, hasLength(2));
      for (final call in registrations) {
        expect(
          (call.body! as Map<String, dynamic>)['installationId'],
          'install-1',
        );
      }
      expect(
        (registrations.last.body! as Map<String, dynamic>)['token'],
        'tok-rotated',
      );
    },
  );

  test('a denied permission is reported and no token is registered', () async {
    messaging.permission = PushPermission.denied;
    await container.read(pushControllerProvider.notifier).start();

    expect(api.calls.any((c) => c.path == '/v1/push/devices'), isFalse);
    final report = api.calls.firstWhere((c) => c.path == '/v1/push/permission');
    expect((report.body! as Map<String, dynamic>)['permission'], 'denied');
    expect(
      container.read(pushControllerProvider).permission,
      PushPermission.denied,
    );
  });

  test('an incoming push is acknowledged — the ack is what cancels the fallback email', () async {
    api.on(
      'POST',
      '/v1/push/dispatches/d-1/ack',
      (_) => {'data': <String, dynamic>{}},
    );
    await container.read(pushControllerProvider.notifier).start();

    messaging.messages.add(
      const PushPayload(dispatchId: 'd-1', kind: 'booking_accept_prompt'),
    );
    await Future<void>.delayed(Duration.zero);

    final ack = api.calls.firstWhere(
      (c) => c.path == '/v1/push/dispatches/d-1/ack',
    );
    expect((ack.body! as Map<String, dynamic>)['installationId'], 'install-1');
  });

  test(
    'registration failing never throws — the server falls back to email',
    () async {
      api.fail('POST', '/v1/push/devices', status: 500, code: 'INTERNAL');
      await expectLater(
        container.read(pushControllerProvider.notifier).start(),
        completes,
      );
      expect(container.read(pushControllerProvider).registered, isFalse);
    },
  );

  test('being offline never throws either', () async {
    api.offline('POST', '/v1/push/devices');
    api.offline('POST', '/v1/push/permission');
    await expectLater(
      container.read(pushControllerProvider.notifier).start(),
      completes,
    );
  });

  test('signing out unregisters the device', () async {
    await container.read(pushControllerProvider.notifier).start();
    await container.read(pushControllerProvider.notifier).stop();

    expect(
      api.calls.any(
        (c) => c.method == 'DELETE' && c.path == '/v1/push/devices/install-1',
      ),
      isTrue,
    );
    expect(container.read(pushControllerProvider).registered, isFalse);
  });

  test('with no vendor wired in, nothing is registered and permission stays unknown', () async {
    messaging
      ..available = false
      ..permission = PushPermission.unknown
      ..deviceToken = null;
    await container.read(pushControllerProvider.notifier).start();

    final state = container.read(pushControllerProvider);
    expect(state.available, isFalse);
    expect(state.permission, PushPermission.unknown);
    // Unknown is not denied: the server must not read a missing vendor as a
    // user refusing notifications.
    expect(state.shouldWarnDenied, isFalse);
    expect(api.calls.any((c) => c.path == '/v1/push/devices'), isFalse);
  });

  test(
    'the reminder only warns when a real vendor’s permission was refused',
    () {
      expect(
        const PushState(
          available: true,
          permission: PushPermission.denied,
        ).shouldWarnDenied,
        isTrue,
      );
      expect(
        const PushState(
          available: false,
          permission: PushPermission.denied,
        ).shouldWarnDenied,
        isFalse,
      );
      expect(
        const PushState(
          available: true,
          permission: PushPermission.granted,
        ).shouldWarnDenied,
        isFalse,
      );
    },
  );
}
