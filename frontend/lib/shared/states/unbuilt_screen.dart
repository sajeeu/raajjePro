import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/headers/app_header.dart';
import 'package:raajjepro/shared/states/empty_state.dart';

/// Where a route lands while the phase that owns its screen has not built it.
///
/// Phase 6's Profile has five rows and §Phase 6's Done-when says **every row
/// navigates** — but only two of the five destinations exist today, and the
/// role switcher's two destinations (§Phase 6a's onboarding, §Phase 10's
/// dashboard) exist neither. A row that silently does nothing would make the
/// Done-when unprovable and would leave a user unable to tell a dead control
/// from a slow one, so each of those routes is real, named, and lands here
/// saying plainly what is missing and who owes it.
///
/// This is the difference between it and [InertControl]: an inert control is
/// drawn in place and goes nowhere, which suits a search field or a camera
/// button; a *row* whose whole purpose is to navigate has to navigate.
///
/// [owedBy] is not decoration. Tests assert it, so a phase landing its screen
/// finds the tripwire rather than a second copy of this placeholder.
class UnbuiltScreen extends StatelessWidget {
  const UnbuiltScreen({required this.title, required this.owedBy, super.key});

  /// What the user tapped, in their words — "Saved", "Upcoming bookings".
  final String title;

  /// The phase that owes this screen — "Phase 14", "Phase 6a".
  final String owedBy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: title,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState(
                  icon: Icons.construction_outlined,
                  title: '$title is not built yet',
                  // Names the phase rather than a date: a date would be a
                  // promise this screen has no way to keep.
                  body:
                      'This part of the app is still being built ($owedBy). '
                      'Nothing you have done is lost — go back and carry on.',
                  actionLabel: 'Go back',
                  onAction: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
