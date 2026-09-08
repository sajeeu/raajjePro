import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/push/installation_id.dart';
import 'package:raajjepro/core/push/push_api.dart';
import 'package:raajjepro/core/push/push_messaging.dart';

final pushApiProvider = Provider<PushApi>(
  (ref) => PushApi(ref.watch(apiClientProvider)),
);

/// What the app knows about push right now. [available] is false while no
/// vendor is wired in, and the UI reads that rather than guessing from a
/// permission of [PushPermission.unknown].
class PushState {
  const PushState({
    this.permission = PushPermission.unknown,
    this.available = false,
    this.registered = false,
  });

  final PushPermission permission;
  final bool available;
  final bool registered;

  /// The one condition the reminder banner renders on: the OS said no, and
  /// there is a real vendor whose permission it was refusing. Without a
  /// vendor the message would be untrue — enabling notifications would not
  /// make a push arrive.
  bool get shouldWarnDenied => available && permission == PushPermission.denied;

  PushState copyWith({
    PushPermission? permission,
    bool? available,
    bool? registered,
  }) => PushState(
    permission: permission ?? this.permission,
    available: available ?? this.available,
    registered: registered ?? this.registered,
  );
}

final pushControllerProvider = NotifierProvider<PushController, PushState>(
  PushController.new,
);

/// Registration, refresh and acknowledgement (§Phase 3c).
///
/// Everything here is best-effort by design. Push is the fast path, not the
/// guaranteed one — the backend's email fallback is what makes a notification
/// reliable — so a failure to register must never block signing in or break a
/// screen. Failures are swallowed deliberately, and each one is a state the
/// server already handles: a user with no registration gets email immediately.
class PushController extends Notifier<PushState> {
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<PushPayload>? _messageSub;

  @override
  PushState build() {
    ref.onDispose(() {
      unawaited(_refreshSub?.cancel());
      unawaited(_messageSub?.cancel());
    });
    return PushState(available: _messaging.isAvailable);
  }

  PushMessaging get _messaging => ref.read(pushMessagingProvider);
  PushApi get _api => ref.read(pushApiProvider);

  /// Called once the user is signed in. Asks the OS, registers the token if
  /// there is one, and reports a refusal so the server can fall back to email
  /// from the very first notification rather than after the first missed one.
  Future<void> start() async {
    // No vendor, nothing to ask and nothing to report. Reporting `unknown`
    // would be a network call on every sign-in that writes the value the
    // account already has, and it would put a push call in the trace of
    // every registration for no benefit.
    if (!_messaging.isAvailable) {
      state = state.copyWith(available: false);
      return;
    }
    final permission = await _messaging.requestPermission();
    state = state.copyWith(
      permission: permission,
      available: _messaging.isAvailable,
    );

    if (permission == PushPermission.denied) {
      await _report(permission);
      return;
    }

    final token = await _messaging.token();
    if (token == null) {
      // Permission may be granted with no token yet (iOS returns the APNs
      // token asynchronously). The refresh stream below picks it up.
      await _report(permission);
    } else {
      await _register(token, permission);
    }

    _refreshSub ??= _messaging.onTokenRefresh.listen((token) {
      unawaited(_register(token, state.permission));
    });
    _messageSub ??= _messaging.onMessage.listen((payload) {
      unawaited(acknowledge(payload));
    });
  }

  /// Re-asks the OS — for when the user comes back from Settings. Nothing in
  /// the app can grant the permission itself.
  Future<void> refreshPermission() async {
    if (!_messaging.isAvailable) return;
    final permission = await _messaging.currentPermission();
    if (permission == state.permission) return;
    state = state.copyWith(permission: permission);
    await _report(permission);
    if (permission == PushPermission.granted) await start();
  }

  /// Confirms delivery. This — and not the vendor accepting the message — is
  /// what tells the server the push arrived, and it is what stops the
  /// 30-minute fallback email going out on top of it.
  Future<void> acknowledge(PushPayload payload) async {
    try {
      await _api.acknowledge(
        payload.dispatchId,
        installationId: await ref.read(installationIdProvider).read(),
      );
    } on ApiException {
      // Nothing to retry usefully: the worst case is a duplicate email, which
      // is the safe direction for a notification that says a job is waiting.
    } on ApiNetworkException {
      // Same.
    }
  }

  /// Sign-out: the device must stop receiving this account's notifications.
  Future<void> stop() async {
    await _refreshSub?.cancel();
    await _messageSub?.cancel();
    _refreshSub = null;
    _messageSub = null;
    if (!_messaging.isAvailable) {
      state = const PushState();
      return;
    }
    try {
      await _api.unregisterDevice(
        await ref.read(installationIdProvider).read(),
      );
    } on Object {
      // Best effort, like the local sign-out itself. The server also revokes
      // the registration when the vendor reports the token dead.
    }
    state = PushState(available: _messaging.isAvailable);
  }

  Future<void> _register(String token, PushPermission permission) async {
    try {
      await _api.registerDevice(
        installationId: await ref.read(installationIdProvider).read(),
        token: token,
        deviceName: await _deviceName(),
        permission: permission,
      );
      state = state.copyWith(registered: true);
    } on Object {
      state = state.copyWith(registered: false);
    }
  }

  Future<void> _report(PushPermission permission) async {
    try {
      await _api.reportPermission(permission);
    } on Object {
      // Best effort.
    }
  }

  Future<String> _deviceName() async {
    try {
      return await ref.read(deviceNameProvider.future);
    } on Object {
      return 'Unknown device';
    }
  }
}
