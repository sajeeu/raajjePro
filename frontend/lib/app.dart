import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/gallery/presentation/gallery_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// Root widget: the themed [MaterialApp] carrying the Phase 1 design tokens.
///
/// Routing is a plain named-route table until a phase needs more — the plan
/// names no router package, and adding one now would be building ahead. The
/// gallery is a real route in every build; the home screen links to it only
/// in debug builds.
class RaajjeProApp extends StatelessWidget {
  const RaajjeProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RaajjePro',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (_) => const _PlaceholderHome(),
        GalleryScreen.routeName: (_) => const GalleryScreen(),
      },
    );
  }
}

/// Phase 0's boot screen, themed. Phase 3 replaces it with the real entry.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader.brand(),
          Expanded(
            child: Center(
              child: Padding(
                padding: AppSpacing.screenInsets,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('RaajjePro', style: context.type.screenTitle),
                    if (kDebugMode) ...[
                      const SizedBox(height: AppSpacing.xl),
                      AppButton.secondary(
                        label: 'Component gallery',
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed(GalleryScreen.routeName),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
