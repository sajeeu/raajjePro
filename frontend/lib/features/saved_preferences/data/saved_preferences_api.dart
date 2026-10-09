import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';

/// §1h's saved preferences — `Saved Preferences.dc.html`, §Phase 17.4.
///
/// "Saved addresses with labels, preferred time windows, and standing service
/// instructions, reused across bookings." Every call is the signed-in user's
/// own; the server scopes each write to them.

@immutable
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.islandId,
    required this.islandDisplayName,
    required this.addressLine,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    islandId: json['islandId'] as String? ?? '',
    islandDisplayName: json['islandDisplayName'] as String? ?? '',
    addressLine: json['addressLine'] as String? ?? '',
  );

  final String id;
  final String label;

  /// By id, never by name (§0.0 item 12).
  final String islandId;

  /// The server's rendering — `Dh. Meedhoo` or `Kulhudhuffushi`.
  final String islandDisplayName;
  final String addressLine;
}

@immutable
class SavedTimeWindow {
  const SavedTimeWindow({required this.id, required this.label});

  factory SavedTimeWindow.fromJson(Map<String, dynamic> json) =>
      SavedTimeWindow(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );

  final String id;

  /// "Weekdays · 9:00–12:00" — rendered by the server, so "Weekdays" means
  /// Sunday to Thursday everywhere.
  final String label;
}

@immutable
class SavedPreferences {
  const SavedPreferences({
    required this.addresses,
    required this.timeWindows,
    required this.standingInstructions,
  });

  factory SavedPreferences.fromJson(Map<String, dynamic> json) =>
      SavedPreferences(
        addresses: ((json['addresses'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SavedAddress.fromJson)
            .toList(growable: false),
        timeWindows: ((json['timeWindows'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SavedTimeWindow.fromJson)
            .toList(growable: false),
        standingInstructions: json['standingInstructions'] as String?,
      );

  final List<SavedAddress> addresses;
  final List<SavedTimeWindow> timeWindows;
  final String? standingInstructions;

  bool get isEmpty =>
      addresses.isEmpty &&
      timeWindows.isEmpty &&
      (standingInstructions ?? '').trim().isEmpty;
}

class SavedPreferencesApi {
  const SavedPreferencesApi(this._api);

  final ApiClient _api;

  static const _base = '/v1/users/me/saved-preferences';

  Future<SavedPreferences> read() async =>
      SavedPreferences.fromJson(await _api.get(_base));

  Future<SavedAddress> addAddress({
    required String label,
    required String islandId,
    required String addressLine,
  }) async => SavedAddress.fromJson(
    await _api.post(
      '$_base/addresses',
      body: {'label': label, 'islandId': islandId, 'addressLine': addressLine},
    ),
  );

  Future<SavedAddress> updateAddress(
    String id, {
    required String label,
    required String islandId,
    required String addressLine,
  }) async => SavedAddress.fromJson(
    await _api.patch(
      '$_base/addresses/$id',
      body: {'label': label, 'islandId': islandId, 'addressLine': addressLine},
    ),
  );

  Future<void> removeAddress(String id) => _api.delete('$_base/addresses/$id');

  Future<void> removeTimeWindow(String id) =>
      _api.delete('$_base/time-windows/$id');

  Future<SavedPreferences> setStandingInstructions(String text) async =>
      SavedPreferences.fromJson(
        await _api.put('$_base/standing-instructions', body: {'text': text}),
      );
}

final savedPreferencesApiProvider = Provider<SavedPreferencesApi>(
  (ref) => SavedPreferencesApi(ref.watch(apiClientProvider)),
);
