import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

enum SaveHeartStyle {
  /// A 32 dp white disc with a shadow — sits over a card image.
  overlay,

  /// A 28 dp disc on the muted surface — sits in a card body.
  flat,
}

/// The save heart (`ServiceCard.dc.html` → heart). Outline when not saved,
/// filled red when saved. Stateless: the owner holds `saved` and flips it
/// optimistically in [onChanged], rolling back visibly if the call fails
/// (`frontend/CLAUDE.md` → optimistic updates).
///
/// The disc is 32 or 28 dp; the tap area is 48 dp via [Pressable]. Announces
/// as a toggle — "Save, off" / "Saved, on" — so a screen reader hears the
/// state, not just the verb.
class SaveHeartToggle extends StatelessWidget {
  const SaveHeartToggle({
    required this.saved,
    required this.onChanged,
    super.key,
    this.style = SaveHeartStyle.overlay,
    this.itemName,
  });

  final bool saved;
  final ValueChanged<bool>? onChanged;
  final SaveHeartStyle style;

  /// Named in the spoken label: "Save Home Deep Cleaning".
  final String? itemName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final overlay = style == SaveHeartStyle.overlay;
    final dimension = overlay ? 32.0 : 28.0;
    final verb = saved ? 'Saved' : 'Save';
    final label = itemName == null ? verb : '$verb $itemName';

    return Pressable(
      onTap: onChanged == null ? null : () => onChanged!(!saved),
      toggled: saved,
      semanticLabel: label,
      focusRadius: AppRadius.pill,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: overlay
              ? colors.surface.withValues(alpha: 0.94)
              : colors.surfaceMuted,
          shape: BoxShape.circle,
          boxShadow: overlay ? AppShadows.overlay(colors.ink) : null,
        ),
        child: SizedBox.square(
          dimension: dimension,
          child: Center(
            child: AnimatedSwitcher(
              duration: motion.fast,
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeIn,
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(saved),
                size: overlay ? 16 : 14,
                color: saved ? colors.error : colors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
