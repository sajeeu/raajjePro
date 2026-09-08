import 'dart:io';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/push/push_messaging.dart';

/// The `/v1/push` surface. Nothing here returns a phone number, and the raw
/// device token only ever travels outward — the API never echoes it back.
class PushApi {
  const PushApi(this._client);
  final ApiClient _client;

  /// Registers or refreshes this install's token. The backend keys on
  /// `installationId`, so calling it again after a rotation updates the same
  /// registration rather than creating a second one.
  Future<void> registerDevice({
    required String installationId,
    required String token,
    required String deviceName,
    PushPermission? permission,
  }) async {
    await _client.post(
      '/v1/push/devices',
      body: {
        'installationId': installationId,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'token': token,
        'deviceName': deviceName,
        if (permission != null) 'permission': permission.wire,
      },
    );
  }

  Future<void> unregisterDevice(String installationId) async {
    await _client.delete('/v1/push/devices/$installationId');
  }

  /// Reports what the OS said. Not a preference — there is no in-app toggle
  /// for booking notifications (§Phase 3c); this records a fact about the
  /// operating system so the backend knows to send email instead.
  Future<void> reportPermission(PushPermission permission) async {
    await _client.post(
      '/v1/push/permission',
      body: {'permission': permission.wire},
    );
  }

  /// Confirms a push actually arrived. This is what stops the 30-minute
  /// fallback email; a vendor accepting the message does not.
  Future<void> acknowledge(String dispatchId, {String? installationId}) async {
    await _client.post(
      '/v1/push/dispatches/$dispatchId/ack',
      body: {'installationId': ?installationId},
    );
  }
}
