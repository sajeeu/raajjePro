import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/features/availability/data/availability_api.dart';
import 'package:raajjepro/features/availability/data/availability_models.dart';

// `retry: null`. Riverpod 3 auto-retries a failed `build()` with exponential
// backoff for ~30s before the screen's own error branch is ever reached,
// which fights the explicit "Try again" every screen here provides
// (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// Everything `Availability.dc.html` renders, in one state.
///
/// The rules, the exceptions and the grid are fetched together and refreshed
/// together, because on this screen they are one thing: saving a rule changes
/// the grid, and a grid that lagged behind the rule list would be the exact
/// contradiction the save sheet promises will not happen.
class AvailabilityState {
  const AvailabilityState({
    required this.availability,
    required this.slots,
    required this.timeAway,
  });

  final ListingAvailability availability;
  final List<TimeSlotView> slots;

  /// Provider-wide, and shown here only as the cross-link to My Calendar —
  /// `Availability.dc.html` is explicit that trips live there, not here.
  final List<TimeAway> timeAway;

  bool get isEmpty => availability.rules.isEmpty;
}

final availabilityControllerProvider =
    AsyncNotifierProvider.family<
      AvailabilityController,
      AvailabilityState,
      String
    >(AvailabilityController.new, isAutoDispose: true, retry: _noRetry);

/// Keyed by listing, because availability is per listing — a provider with a
/// two-hour clean and a one-hour clean publishes a different grid for each.
class AvailabilityController extends AsyncNotifier<AvailabilityState> {
  AvailabilityController(this.listingId);

  /// The family key, taken as a constructor argument — the shape
  /// `ServiceWizardController` established, and what `.new` is handed.
  final String listingId;

  @override
  Future<AvailabilityState> build() => _load(listingId);

  Future<AvailabilityState> _load(String listingId) async {
    final api = ref.read(availabilityApiProvider);
    // Together rather than in sequence: three independent reads behind one
    // skeleton, so the screen does not appear in three stages.
    final results = await Future.wait<Object>([
      api.read(listingId),
      api.ownSlots(listingId),
      api.timeAway(),
    ]);
    return AvailabilityState(
      availability: results[0] as ListingAvailability,
      slots: results[1] as List<TimeSlotView>,
      timeAway: results[2] as List<TimeAway>,
    );
  }

  Future<void> reload() async {
    state = const AsyncLoading<AvailabilityState>();
    state = await AsyncValue.guard(() => _load(listingId));
  }

  /// What the "Add rule" sheet opens with — §Phase 9's own step-5 window.
  Future<WeeklyRule> ruleDefaults() =>
      ref.read(availabilityApiProvider).ruleDefaults(listingId);

  /// Saves a rule and refreshes the grid it just changed.
  ///
  /// The refresh is not optimistic. Which times a rule produces is the
  /// server's answer — it folds in exceptions, the provider's time off, the
  /// lead boundary and what is already reserved — and guessing it in Dart
  /// would be a second implementation of `expandSlots` that could disagree
  /// with the one that matters.
  Future<void> saveRule(WeeklyRule rule) async {
    final api = ref.read(availabilityApiProvider);
    if (rule.id.isEmpty) {
      await api.addRule(listingId, rule);
    } else {
      await api.updateRule(listingId, rule);
    }
    await _refreshInPlace();
  }

  Future<void> removeRule(String ruleId) async {
    await ref.read(availabilityApiProvider).removeRule(listingId, ruleId);
    await _refreshInPlace();
  }

  Future<void> addException({
    required String name,
    required String startDate,
    required String endDate,
    required String startTime,
    required String endTime,
  }) async {
    await ref
        .read(availabilityApiProvider)
        .addException(
          listingId,
          name: name,
          startDate: startDate,
          endDate: endDate,
          startTime: startTime,
          endTime: endTime,
        );
    await _refreshInPlace();
  }

  Future<void> removeException(String exceptionId) async {
    await ref
        .read(availabilityApiProvider)
        .removeException(listingId, exceptionId);
    await _refreshInPlace();
  }

  /// The plan's "individual override" — one time at a time.
  Future<void> toggleBlock(TimeSlotView slot) async {
    final api = ref.read(availabilityApiProvider);
    final updated = slot.status == SlotStatus.blocked
        ? await api.unblockSlot(slot.id)
        : await api.blockSlot(slot.id);
    // One row changed, so only that row is replaced — reloading the whole
    // screen would throw away the provider's scroll position for a tap that
    // changed one chip.
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      AvailabilityState(
        availability: current.availability,
        slots: [
          for (final s in current.slots)
            if (s.id == slot.id) updated else s,
        ],
        timeAway: current.timeAway,
      ),
    );
  }

  /// Refetches without dropping back to the skeleton, so a save lands as a
  /// change rather than as the screen disappearing and coming back.
  Future<void> _refreshInPlace() async {
    state = await AsyncValue.guard(() => _load(listingId));
  }
}

/// `My Calendar` — commitments across every listing, plus time away.
final providerCalendarProvider =
    AsyncNotifierProvider<ProviderCalendarController, ProviderCalendar>(
      ProviderCalendarController.new,
      isAutoDispose: true,
      retry: _noRetry,
    );

class ProviderCalendarController extends AsyncNotifier<ProviderCalendar> {
  @override
  Future<ProviderCalendar> build() =>
      ref.read(availabilityApiProvider).calendar();

  Future<void> reload() async {
    state = const AsyncLoading<ProviderCalendar>();
    state = await AsyncValue.guard(build);
  }

  Future<void> addTimeAway({
    required String name,
    required String startDate,
    required String endDate,
  }) async {
    await ref
        .read(availabilityApiProvider)
        .addTimeAway(name: name, startDate: startDate, endDate: endDate);
    state = await AsyncValue.guard(build);
  }

  Future<void> removeTimeAway(String id) async {
    await ref.read(availabilityApiProvider).removeTimeAway(id);
    state = await AsyncValue.guard(build);
  }
}

/// The customer picker's one read, keyed by listing.
final openSlotsProvider =
    AsyncNotifierProvider.family<OpenSlotsController, OpenSlots, String>(
      OpenSlotsController.new,
      isAutoDispose: true,
      retry: _noRetry,
    );

class OpenSlotsController extends AsyncNotifier<OpenSlots> {
  OpenSlotsController(this.listingId);

  final String listingId;

  @override
  Future<OpenSlots> build() =>
      ref.read(availabilityApiProvider).openSlots(listingId);

  /// Called after a slot is refused as taken, and by the error state's retry.
  Future<void> reload() async {
    state = const AsyncLoading<OpenSlots>();
    state = await AsyncValue.guard(build);
  }
}
