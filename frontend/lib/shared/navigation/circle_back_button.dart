import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// The bare 44 dp circular back control Register, Verify Email, Forgot
/// Password and — since Phase 9 — the service wizard use
/// instead of [AppHeader] (`Register.dc.html` line 29, `Verify Email.dc.html`
/// line ~29): white surface, a 1 px border, the ink-coloured arrow — no
/// title bar sits above it, so it is not `AppHeader.page`. [Pressable]
/// still gives it the 48 dp hit floor around the 44 dp visual.
///
/// 🔧 **Moved out of `features/auth/` by Phase 9**, on its fourth consumer and
/// its second feature (`lib/README.md`: a widget a second feature needs moves
/// to `shared/`; it is not copied).
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      focusRadius: AppRadius.pill,
      builder: (context, state) => Container(
        width: AppSizes.iconButtonSize,
        height: AppSizes.iconButtonSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state.pressed ? colors.surfaceMuted : colors.surface,
          border: Border.all(color: colors.border),
          boxShadow: AppShadows.card(colors.ink),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.arrow_back, size: AppSizes.iconLg, color: colors.ink),
      ),
    );
  }
}
