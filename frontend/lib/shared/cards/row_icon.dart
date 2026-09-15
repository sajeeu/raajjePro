import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The accent-tinted icon disc a row card leads with — the artboards' 46 dp
/// square behind a settings-style row's icon.
///
/// 🔧 **Moved out of `features/my_services/` by §Phase 10a**, on its second
/// consumer (the billing screen's Invoices row). `lib/README.md`: a widget a
/// second feature needs moves to `shared/`; it is not copied.
class RowIcon extends StatelessWidget {
  const RowIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: AppSizes.iconDisc,
      height: AppSizes.iconDisc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.compact),
      ),
      child: Icon(icon, color: colors.accentText, size: AppSizes.iconLg),
    );
  }
}
