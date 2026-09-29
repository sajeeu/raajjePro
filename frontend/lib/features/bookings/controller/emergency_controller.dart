import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/features/bookings/data/emergency_api.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';

// `retry: null`, for the reason every controller in this app passes it
// (frontend/CLAUDE.md): Riverpod 3's silent backoff would fight the screens'
// own "Try again" and outlive a test.
Duration? _noRetry(int retryCount, Object error) => null;

/// One emergency request, as its customer watches it. `autoDispose` — a live
/// request is exactly the thing a stale copy of is worse than a spinner.
///
/// The screen refreshes it on a short timer while the request is live: there
/// is no push-to-app channel for the customer's own request yet (§Phase 19),
/// and the countdowns it draws are the server's deadlines, not the refresh's.
final emergencyRequestProvider = FutureProvider.autoDispose
    .family<EmergencyRequest, String>(
      (ref, requestId) => ref.watch(emergencyApiProvider).read(requestId),
      retry: _noRetry,
    );

/// One broadcast, as a provider it reached reads it.
final emergencyBroadcastProvider = FutureProvider.autoDispose
    .family<EmergencyBroadcast, String>(
      (ref, requestId) =>
          ref.watch(emergencyApiProvider).readAsProvider(requestId),
      retry: _noRetry,
    );

/// The customer's dispatch fees and RaajjePro's own bank account.
final dispatchFeesProvider = FutureProvider.autoDispose<DispatchFees>(
  (ref) => ref.watch(emergencyApiProvider).dispatchFees(),
  retry: _noRetry,
);

/// "4:05" — minutes and seconds left until [deadline], never negative. The
/// deadline is the server's; this only counts down to it.
String countdown(DateTime? deadline, DateTime now) {
  if (deadline == null) return '0:00';
  final left = deadline.difference(now);
  final s = left.isNegative ? 0 : left.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
