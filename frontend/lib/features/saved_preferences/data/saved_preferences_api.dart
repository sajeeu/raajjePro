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

/// The label a window will be saved under — **a mirror** of the server's
/// `timeWindowLabel` (`backend/src/modules/saved-preferences/types.ts`), used
/// only for the editor's preview. Once saved, the chip prints the server's own
/// string, so this can never be the label of record. Pinned by the same cases
/// as the server's tests; change both or neither.
///
/// [weekdays] are ISO (1 = Monday … 7 = Sunday); [start] and [end] `HH:MM`.
String previewTimeWindowLabel(List<int> weekdays, String start, String end) =>
    '${_weekdaysLabel(weekdays)} · ${_shortClock(start)}–${_shortClock(end)}';

/// The server's sets: the Maldivian working week is Sunday to Thursday.
const _maldivesWeekdays = {7, 1, 2, 3, 4};
const _maldivesWeekend = {5, 6};

/// The server lists days Sunday first.
const _displayOrder = [7, 1, 2, 3, 4, 5, 6];
const _long = [
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _short = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _weekdaysLabel(List<int> weekdays) {
  final days = weekdays.toSet();
  if (days.length == 7) return 'Every day';
  if (days.length == _maldivesWeekdays.length &&
      days.containsAll(_maldivesWeekdays)) {
    return 'Weekdays';
  }
  if (days.length == _maldivesWeekend.length &&
      days.containsAll(_maldivesWeekend)) {
    return 'Weekend';
  }
  final ordered = _displayOrder.where(days.contains).toList();
  if (ordered.length == 1) return _long[ordered.first];
  return ordered.map((d) => _short[d]).join(', ');
}

/// `9:00` rather than `09:00`, as the server prints it.
String _shortClock(String hhmm) {
  final parts = hhmm.split(':');
  return '${int.parse(parts[0])}:${parts[1]}';
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

  /// [weekdays] are ISO, 1 = Monday … 7 = Sunday; times are `HH:MM`,
  /// Maldives wall clock. The server renders the label.
  Future<SavedTimeWindow> addTimeWindow({
    required List<int> weekdays,
    required String startTime,
    required String endTime,
  }) async => SavedTimeWindow.fromJson(
    await _api.post(
      '$_base/time-windows',
      body: {'weekdays': weekdays, 'startTime': startTime, 'endTime': endTime},
    ),
  );

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
