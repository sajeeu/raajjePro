import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// Where a bottom-nav tab lands while its screen does not exist yet.
///
/// The nav bar is Phase 1's and is real, so its tabs are real taps. Letting
/// one do nothing would be the worst of the options — the user cannot tell a
/// dead control from a slow one. This says plainly that the screen is not
/// built, and goes away when Phase 16 owns the tab shell.
class TabPlaceholderScreen extends StatelessWidget {
  const TabPlaceholderScreen({required this.tab, super.key});

  final String tab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(title: tab, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: Center(
              child: Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState(
                  icon: Icons.construction_outlined,
                  title: '$tab is not built yet',
                  body:
                      'This part of the app is still being built. Explore works today — '
                      'browse the categories and come back to this tab later.',
                  actionLabel: 'Back to Explore',
                  onAction: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
