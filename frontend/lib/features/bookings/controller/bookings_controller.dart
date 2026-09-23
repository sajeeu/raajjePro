import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/shared/shared.dart';

/// The Bookings tab's filter pills (`My Bookings.dc.html`).
///
/// **They filter what is already loaded** rather than re-fetching per pill —
/// the same choice §Phase 10's dashboard made, and for the same reason: the
/// count above the list would otherwise disagree with the list under it.
enum BookingFilter {
  all,
  upcoming,
  active,
  completed;

  String get label => switch (this) {
    all => 'All',
    upcoming => 'Upcoming',
    active => 'Active',
    completed => 'Completed',
  };

  /// The empty state for this pill when the list has rows but none of them
  /// are here. Title, then body.
  (String, String) get emptyCopy => switch (this) {
    all => (
      'No bookings yet',
      'When you book a service it appears here, with its whole record.',
    ),
    upcoming => (
      'Nothing coming up',
      'Confirmed future bookings sit here until their day arrives.',
    ),
    active => (
      'Nothing needs you right now',
      'Bookings that are underway or waiting on someone appear here.',
    ),
    completed => (
      'Nothing completed yet',
      'Finished bookings stay here for good — with their full record and their chat.',
    ),
  };

  bool matches(Booking booking) => switch (this) {
    all => true,
    // Confirmed and still to happen. A confirmed booking whose day has passed
    // is not "upcoming" — it is waiting on somebody to say it happened.
    upcoming =>
      booking.status == BookingStatus.confirmed &&
          (booking.scheduledFor?.isAfter(DateTime.now()) ?? false),
    // Anything non-terminal that is not merely upcoming — plus the two
    // statuses §1c calls non-terminal even though they read like endings.
    active =>
      !booking.status.isTerminal &&
          !(booking.status == BookingStatus.confirmed &&
              (booking.scheduledFor?.isAfter(DateTime.now()) ?? false)),
    completed => booking.status == BookingStatus.completed,
  };
}

/// The pill named in untyped route arguments, or null.
///
/// Here rather than on the screen so §Phase 6's Profile can push a tile
/// without importing the bookings feature — `lib/README.md`: features meet in
/// `core/`, and where they meet in a controller the argument shape is what
/// crosses, never a type.
BookingFilter? bookingFilterFromRouteArguments(Object? arguments) {
  final map = arguments is Map<String, dynamic>
      ? arguments
      : const <String, dynamic>{};
  final label = map['filter'] as String?;
  if (label == null) return null;
  for (final filter in BookingFilter.values) {
    if (filter.label == label) return filter;
  }
  return null;
}

/// Which side of their bookings the user is looking at, and which pill.
///
/// Separate from the data, for the reason §Phase 10 separated them: changing
/// a pill must never re-fetch, and the two live in different notifiers so it
/// cannot.
class BookingsViewController extends Notifier<BookingsView> {
  @override
  BookingsView build() =>
      const BookingsView(role: BookingRole.customer, filter: BookingFilter.all);

  void setFilter(BookingFilter filter) =>
      state = BookingsView(role: state.role, filter: filter);

  void setRole(BookingRole role) =>
      state = BookingsView(role: role, filter: state.filter);
}

class BookingsView {
  const BookingsView({required this.role, required this.filter});
  final BookingRole role;
  final BookingFilter filter;
}

final bookingsViewProvider =
    NotifierProvider<BookingsViewController, BookingsView>(
      BookingsViewController.new,
    );

// `retry: null`, for the reason every controller in this app passes it:
// Riverpod 3 auto-retries a failed `build()` with exponential backoff for
// ~30 s before the screen's own error branch is ever reached, which fights
// the explicit "Try again" each of these screens draws and leaves a pending
// timer past test teardown (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// The list itself, keyed by role so switching sides is a separate fetch that
/// keeps its own loading and error state.
final bookingsListProvider = FutureProvider.autoDispose
    .family<List<Booking>, BookingRole>(
      (ref, role) => ref.watch(bookingApiProvider).list(role),
      retry: _noRetry,
    );

/// One booking's detail read. `autoDispose` so leaving the screen drops it —
/// a booking is a live thing and a stale copy is worse than a spinner.
final bookingDetailProvider = FutureProvider.autoDispose
    .family<Booking, String>(
      (ref, bookingId) => ref.watch(bookingApiProvider).read(bookingId),
      retry: _noRetry,
    );

/// What a booking action is doing right now.
///
/// `queued` exists for exactly one action — the accept (§Phase 17 frontend
/// item 12). Every other action either sent or failed, and saying "pending"
/// about a payment claim the provider has not received would be a false
/// promise about money.
enum BookingActionPhase { idle, working, queued, failed }

class BookingActionState {
  const BookingActionState({
    this.phase = BookingActionPhase.idle,
    this.message,
  });

  final BookingActionPhase phase;

  /// What to show the user. See `_messageFor` at the foot of this file for
  /// where it comes from and why a rule refusal keeps the server's wording.
  final String? message;

  bool get isWorking => phase == BookingActionPhase.working;
}

/// Owns the mutations for one booking, and nothing else.
///
/// Every action refreshes [bookingDetailProvider] rather than patching a local
/// copy: the server's answer is the booking, and a transition that also moved
/// a reservation or filed a report has effects this layer should not try to
/// predict.
/// Riverpod 3 dropped `FamilyNotifier` — a family [Notifier] takes its
/// argument through the constructor instead, which [NotifierProvider.family]
/// invokes with the key. `bookingId` below is that constructor field, not an
/// override of `build` (the same shape `VerifyEmailController` uses).
class BookingActionsController extends Notifier<BookingActionState> {
  BookingActionsController(this.bookingId);

  final String bookingId;

  @override
  BookingActionState build() => const BookingActionState();

  Future<bool> accept() => _run(() async {
    final result = await ref.read(bookingApiProvider).accept(bookingId);
    if (result == null) {
      // Queued. The provider sees a pending state until the reconnect lands —
      // never a success, and never a silent loss.
      state = const BookingActionState(phase: BookingActionPhase.queued);
      return false;
    }
    return true;
  });

  Future<bool> decline({String? reason}) => _run(
    () => ref.read(bookingApiProvider).decline(bookingId, reason: reason),
  );

  /// §Phase 17.2. The provider's quote — a time and a price together, which
  /// is what §1c asks a request-based provider to answer with.
  ///
  /// The same call sends a first quote and a revision; the server reads the
  /// booking's status to know which. Not queued — see [BookingApi.offerQuote].
  Future<bool> offerQuote({
    required DateTime scheduledFor,
    required int amountLaari,
    String? note,
  }) => _run(
    () => ref
        .read(bookingApiProvider)
        .offerQuote(
          bookingId,
          scheduledFor: scheduledFor,
          amountLaari: amountLaari,
          note: note,
        ),
  );

  Future<bool> approveQuote() =>
      _run(() => ref.read(bookingApiProvider).approveQuote(bookingId));

  Future<bool> declineQuote({String? reason}) => _run(
    () => ref.read(bookingApiProvider).declineQuote(bookingId, reason: reason),
  );

  Future<bool> claimPayment() =>
      _run(() => ref.read(bookingApiProvider).claimPayment(bookingId));

  Future<bool> withdrawPaymentClaim() =>
      _run(() => ref.read(bookingApiProvider).withdrawPaymentClaim(bookingId));

  Future<bool> confirmPaymentReceived() => _run(
    () => ref.read(bookingApiProvider).confirmPaymentReceived(bookingId),
  );

  Future<bool> complete({int? finalAmountLaari}) => _run(
    () => ref
        .read(bookingApiProvider)
        .complete(bookingId, finalAmountLaari: finalAmountLaari),
  );

  Future<bool> answerCompletionPrompt({required bool happened}) => _run(
    () => ref
        .read(bookingApiProvider)
        .answerCompletionPrompt(bookingId, happened: happened),
  );

  Future<bool> cancel({String? reason}) => _run(
    () => ref.read(bookingApiProvider).cancel(bookingId, reason: reason),
  );

  Future<bool> dispute({required String reason, String? note}) => _run(
    () => ref
        .read(bookingApiProvider)
        .dispute(bookingId, reason: reason, note: note),
  );

  Future<bool> proposeAmendment({
    int? amountLaari,
    DateTime? scheduledFor,
    String? scopeNote,
    String? reason,
  }) => _run(
    () => ref
        .read(bookingApiProvider)
        .proposeAmendment(
          bookingId,
          amountLaari: amountLaari,
          scheduledFor: scheduledFor,
          scopeNote: scopeNote,
          reason: reason,
        ),
  );

  Future<bool> respondToAmendment(String amendmentId, {required bool accept}) =>
      _run(
        () => ref
            .read(bookingApiProvider)
            .respondToAmendment(bookingId, amendmentId, accept: accept),
      );

  Future<bool> withdrawAmendment(String amendmentId) => _run(
    () =>
        ref.read(bookingApiProvider).withdrawAmendment(bookingId, amendmentId),
  );

  void clearMessage() => state = const BookingActionState();

  Future<bool> _run(Future<Object?> Function() action) async {
    if (state.isWorking) return false;
    state = const BookingActionState(phase: BookingActionPhase.working);
    try {
      final outcome = await action();
      // `accept` returns false when it queued and set its own state; anything
      // else that returns normally succeeded.
      if (outcome is bool && !outcome) return false;
      state = const BookingActionState();
      ref.invalidate(bookingDetailProvider(bookingId));
      ref.invalidate(bookingsListProvider);
      return true;
    } on Object catch (error) {
      state = BookingActionState(
        phase: BookingActionPhase.failed,
        message: _messageFor(error),
      );
      return false;
    }
  }
}

final bookingActionsProvider =
    NotifierProvider.family<
      BookingActionsController,
      BookingActionState,
      String
    >(BookingActionsController.new);

/// What a failed action says.
///
/// A **business-rule refusal carries the server's own sentence**, the way
/// §Phase 10a's billing screens render theirs: the backend writes one honest
/// line per rule ("This booking cannot be accepted while it is declined") and
/// re-wording it here would put the rule in two places. Anything else falls
/// back to the shared copy — `genericErrorCopy` exists precisely so a screen
/// never leaks an infrastructure message it did not write.
String _messageFor(Object error) => switch (error) {
  ApiNetworkException() =>
    'No connection — nothing was changed. Try again when you’re back online.',
  ApiException(:final message) when message.isNotEmpty => message,
  _ => genericErrorCopy,
};
