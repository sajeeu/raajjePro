import 'package:flutter/material.dart';

/// Marks a control that is drawn to the prototype but wired to nothing yet,
/// naming the phase that owes it a destination.
///
/// It is a real widget rather than a comment so that a test can assert the
/// control is present *and* has no callback — when [owedBy] lands and wires
/// it, that test fails and has to be removed on purpose, which is the point.
/// `test/features/explore/explore_chrome_test.dart` and
/// `test/features/profile/profile_screen_test.dart` are the tripwires.
///
/// Introduced by Phase 4 inside the Explore screen; moved here by Phase 6,
/// which needs it for the change-photo control on Profile. Two features draw
/// it, so `lib/README.md` puts it in `shared/`.
///
/// Not every unbuilt control belongs in one. Where a dead tap would advertise
/// an action with a person on the other end of it, the control is **absent**
/// instead — Explore's emergency entry is the precedent (Round 23).
class InertControl extends StatelessWidget {
  const InertControl({
    required this.label,
    required this.owedBy,
    required this.child,
    super.key,
  });

  final String label;
  final String owedBy;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
