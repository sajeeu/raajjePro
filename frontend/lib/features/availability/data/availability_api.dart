import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/features/availability/data/availability_models.dart';

/// §Phase 9a's endpoints, as the three screens call them.
///
/// **No response here carries a phone number**, structurally — nothing in
/// `availability_models.dart` has a field that could hold one (§1c).
///
/// **Nothing here is queued offline.** §0.0 item 14 keeps the offline queue to
/// exactly three surfaces — the wizard's autosave, the slot/request accept
/// prompt, and chat sends — and none of these is one of them. A replayed rule
/// edit would rewrite a published grid from a decision made somewhere else,
/// and a replayed block would take a time off the market minutes after the
/// provider changed their mind. These fail visibly and are retried by hand.
class AvailabilityApi {
  const AvailabilityApi(this._api);

  final ApiClient _api;

  String _base(String listingId) =>
      '/v1/providers/me/listings/$listingId/availability';

  Future<ListingAvailability> read(String listingId) async =>
      ListingAvailability.fromJson(await _api.get(_base(listingId)));

  /// What the "Add rule" sheet opens with — the wizard's own step-5 window, so
  /// a provider who already stated their hours is not asked twice.
  Future<WeeklyRule> ruleDefaults(String listingId) async {
    final json = await _api.get('${_base(listingId)}/rule-defaults');
    return WeeklyRule(
      id: '',
      weekdays: (json['weekdays'] as List<dynamic>).cast<int>(),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      slotDurationMinutes: json['slotDurationMinutes'] as int,
    );
  }

  Future<WeeklyRule> addRule(String listingId, WeeklyRule rule) async =>
      WeeklyRule.fromJson(
        await _api.post('${_base(listingId)}/rules', body: rule.toBody()),
      );

  /// A whole-resource replacement: the editor opens with every field filled.
  Future<WeeklyRule> updateRule(String listingId, WeeklyRule rule) async =>
      WeeklyRule.fromJson(
        await _api.put(
          '${_base(listingId)}/rules/${rule.id}',
          body: rule.toBody(),
        ),
      );

  Future<void> removeRule(String listingId, String ruleId) =>
      _api.delete('${_base(listingId)}/rules/$ruleId');

  Future<HoursException> addException(
    String listingId, {
    required String name,
    required String startDate,
    required String endDate,
    required String startTime,
    required String endTime,
  }) async => HoursException.fromJson(
    await _api.post(
      '${_base(listingId)}/exceptions',
      body: {
        'name': name,
        'startDate': startDate,
        'endDate': endDate,
        'startTime': startTime,
        'endTime': endTime,
      },
    ),
  );

  Future<void> removeException(String listingId, String exceptionId) =>
      _api.delete('${_base(listingId)}/exceptions/$exceptionId');

  /// The provider's own grid, `reserved` and `blocked` included.
  Future<List<TimeSlotView>> ownSlots(String listingId, {String? to}) async {
    final query = to == null ? '' : '?to=$to';
    final json = await _api.get(
      '/v1/providers/me/listings/$listingId/slots$query',
    );
    // `ApiClient` unwraps the envelope and parks a top-level array under
    // `_list` — the convention `auth_api`, `island_api` and `category_api`
    // all read.
    return (json['_list'] as List<dynamic>)
        .map((e) => TimeSlotView.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimeSlotView> blockSlot(String slotId) async => TimeSlotView.fromJson(
    await _api.post('/v1/providers/me/slots/$slotId/block'),
  );

  Future<TimeSlotView> unblockSlot(String slotId) async =>
      TimeSlotView.fromJson(
        await _api.post('/v1/providers/me/slots/$slotId/unblock'),
      );

  Future<ProviderCalendar> calendar() async =>
      ProviderCalendar.fromJson(await _api.get('/v1/providers/me/calendar'));

  Future<List<TimeAway>> timeAway() async {
    final json = await _api.get('/v1/providers/me/time-off');
    return (json['_list'] as List<dynamic>)
        .map((e) => TimeAway.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimeAway> addTimeAway({
    required String name,
    required String startDate,
    required String endDate,
  }) async => TimeAway.fromJson(
    await _api.post(
      '/v1/providers/me/time-off',
      body: {'name': name, 'startDate': startDate, 'endDate': endDate},
    ),
  );

  Future<void> removeTimeAway(String id) =>
      _api.delete('/v1/providers/me/time-off/$id');

  /// The customer picker. Public — a guest browses before signing in (§0.2).
  Future<OpenSlots> openSlots(String listingId) async =>
      OpenSlots.fromJson(await _api.get('/v1/listings/$listingId/slots'));
}

final availabilityApiProvider = Provider<AvailabilityApi>(
  (ref) => AvailabilityApi(ref.watch(apiClientProvider)),
);
