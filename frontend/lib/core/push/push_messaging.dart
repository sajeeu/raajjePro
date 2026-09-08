import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the operating system last said about notifications.
///
/// [unknown] is not a synonym for [denied]: a user who has never been asked
/// has not refused, and the backend's fallback chain treats the two
/// differently (§Phase 3c — a known denial sends email immediately).
enum PushPermission {
  unknown,
  granted,
  denied;

  String get wire => name;
}

/// One push as the app receives it. `dispatchId` is the handle the app acks
/// with — the backend treats an ack, and nothing the vendor returns, as proof
/// the notification actually arrived.
class PushPayload {
  const PushPayload({
    required this.dispatchId,
    required this.kind,
    this.data = const {},
  });
  final String dispatchId;
  final String kind;
  final Map<String, String> data;

  static PushPayload? tryParse(Map<String, String> data) {
    final id = data['dispatchId'];
    if (id == null || id.isEmpty) return null;
    return PushPayload(dispatchId: id, kind: data['kind'] ?? '', data: data);
  }
}

/// The seam over the push vendor (FCM on Android, APNs on iOS), in the same
/// shape as [CrashReporter]'s seam over Sentry: domain code never imports a
/// vendor SDK, and the app builds and runs with no vendor account at all.
///
/// **Nothing behind this interface exists yet.** There is no Firebase project
/// and no Apple developer account, and Phase 3c deliberately procures
/// neither (docs/decisions/15-phase-3c-push.md). Adding `firebase_messaging`
/// would require a `google-services.json` just to compile the Android app, so
/// the dependency is not in `pubspec.yaml` either. What ships is this
/// interface, the registration flow above it, and [UnavailablePushMessaging].
abstract class PushMessaging {
  /// True once a real vendor is wired in. Everything above this interface
  /// reads it rather than asking which implementation it holds.
  bool get isAvailable;

  /// Asks the OS. Returns what it said, including a refusal.
  Future<PushPermission> requestPermission();

  /// What the OS says right now, without prompting.
  Future<PushPermission> currentPermission();

  /// The device token, or null when there is none to give.
  Future<String?> token();

  /// Fires when the vendor rotates the token. The install is the identity;
  /// the token is a rotating credential, so this re-registers rather than
  /// adding a device.
  Stream<String> get onTokenRefresh;

  /// Fires when a push arrives with the app running.
  Stream<PushPayload> get onMessage;
}

/// The no-vendor implementation. Reports honestly that push is unavailable
/// and never claims a permission it has not been given: permission stays
/// [PushPermission.unknown], which is what keeps the backend from treating a
/// missing vendor as a user's refusal.
class UnavailablePushMessaging implements PushMessaging {
  @override
  bool get isAvailable => false;

  @override
  Future<PushPermission> requestPermission() async {
    if (kDebugMode) {
      debugPrint('push: no vendor configured — permission not requested');
    }
    return PushPermission.unknown;
  }

  @override
  Future<PushPermission> currentPermission() async => PushPermission.unknown;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushPayload> get onMessage => const Stream.empty();
}

final pushMessagingProvider = Provider<PushMessaging>(
  (_) => UnavailablePushMessaging(),
);
