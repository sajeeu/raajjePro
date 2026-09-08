import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The four third-party buttons (`Sign In.dc.html`). Apple is present because
/// App Review requires it wherever another sign-in is offered (plan §1
/// divergence 6). Glyphs are letters, never hotlinked brand assets. Every
/// provider is a stub in v1: the tap surfaces the API's own "not available
/// yet" notice inline (plan §6 — real social auth is post-v1).
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({required this.onTap, super.key});
  final void Function(String provider) onTap;

  static const providers = [
    ('google', 'Google', 'G'),
    ('apple', 'Apple', 'A'),
    ('facebook', 'Facebook', 'f'),
    ('viber', 'Viber', 'V'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (id, name, glyph) in providers)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.sm,
            ),
            child: Pressable(
              semanticLabel: 'Continue with $name',
              onTap: () => onTap(id),
              builder: (context, state) => Container(
                width: AppSizes.touchTarget,
                height: AppSizes.touchTarget,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                  border: Border.all(
                    color: colors.border,
                    width: AppSizes.inputStroke,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  glyph,
                  style: type.cardTitle.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
