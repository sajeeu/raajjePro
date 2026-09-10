import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/domain/island.dart';

/// The island a customer is browsing from (§Phase 7's Done-when: "the header
/// bottom sheet lets a customer pick a browsing island that **persists for the
/// session**").
///
/// **In memory, and only for the session.** It is deliberately not written to
/// secure storage or to shared preferences: the plan says session, and a
/// browsing island that survived a reinstall or a fortnight of not opening the
/// app would quietly filter a customer's whole first screen against somewhere
/// they used to be. Riverpod's root container outlives every route, so the
/// choice survives navigation, backgrounding and sign-in — and goes when the
/// process does.
///
/// Null means *not chosen*, which is a real state rather than a missing one:
/// nothing here defaults to Malé. Picking the island a customer has not
/// mentioned is the same class of mistake as auto-selecting a single search
/// match, and Home's own empty state ("Pick your island to see providers who
/// actually work near you") is written for exactly this.
///
/// Nothing consumes it yet beyond the header label. §Phase 15's search and
/// §Phase 16's Home feed are what read it for real.
class BrowsingIslandController extends Notifier<Island?> {
  @override
  Island? build() => null;

  /// Records the customer's choice. Only ever called from a control the
  /// customer touched — never inferred from a single search match, and never
  /// from a device location.
  void choose(Island island) => state = island;

  /// Back to browsing everywhere.
  void clear() => state = null;
}

final browsingIslandProvider =
    NotifierProvider<BrowsingIslandController, Island?>(
      BrowsingIslandController.new,
    );
