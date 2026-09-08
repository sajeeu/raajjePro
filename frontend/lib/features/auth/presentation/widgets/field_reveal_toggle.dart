import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The show/hide-password control that sits in an [AppTextField]'s `suffix`.
///
/// One widget rather than the same `Pressable` rebuilt on each screen, so the
/// spoken label, the icon pair and the 48 dp target stay identical everywhere
/// a password is typed — and so there is one place to change if they move.
///
/// It is a plain [Pressable] at the full [AppSizes.touchTarget]. Keeping the
/// field at 52 dp is [AppTextField]'s job, not this widget's: the field pads
/// its text rather than its row, so a 48 dp control sits inside the height the
/// text sets instead of adding to it. Recorded in
/// `docs/decisions/14-a-trailing-control-does-not-set-a-field-height.md`.
///
/// An earlier version tried to solve it here, painting a 48 dp `Pressable`
/// out of a zero-height `SizedBox` through an `OverflowBox`. The field
/// measured 52 and the target measured 48, and it was still wrong: Flutter
/// hit-tests against the parent's bounds, so the part of the control outside
/// that zero-height box took no taps. It is recorded because it measures as
/// correct — `getSize` reports 48 × 48 — and only a test that actually taps
/// the thing catches it.
class FieldRevealToggle extends StatelessWidget {
  const FieldRevealToggle({
    required this.revealed,
    required this.onTap,
    super.key,
  });

  /// True when the password is currently visible.
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel: revealed ? 'Hide password' : 'Show password',
      onTap: onTap,
      builder: (context, state) => Icon(
        revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: colors.textSecondary,
        size: AppSizes.iconLg,
      ),
    );
  }
}
