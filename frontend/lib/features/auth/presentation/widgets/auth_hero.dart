import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The gradient header Sign In and Register share (`Sign In.dc.html`): the
/// brand gradient with three faint discs, the wordmark, and a title pair.
class AuthHero extends StatelessWidget {
  const AuthHero({required this.title, required this.subtitle, super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final discColor = colors.onPrimary.withValues(alpha: .08);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [colors.gradientStart, colors.primary, colors.primaryPressed],
          stops: const [0, .55, 1],
        ),
      ),
      child: Stack(
        children: [
          // The three faint discs behind the wordmark, positioned to match
          // the prototype's top-right pair and bottom-left single disc.
          PositionedDirectional(
            top: -46,
            end: -34,
            child: ExcludeSemantics(child: _Disc(150, discColor)),
          ),
          PositionedDirectional(
            top: 64,
            end: 64,
            child: ExcludeSemantics(child: _Disc(90, discColor)),
          ),
          PositionedDirectional(
            bottom: -20,
            start: -30,
            child: ExcludeSemantics(child: _Disc(110, discColor)),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xxl,
              54,
              AppSpacing.xxl,
              26,
            ),
            child: Column(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Raajje',
                        style: type.screenTitle.copyWith(
                          color: colors.onPrimary,
                        ),
                      ),
                      TextSpan(
                        text: 'Pro',
                        style: type.screenTitle.copyWith(
                          color: colors.accentBorder,
                        ),
                      ),
                    ],
                  ),
                  semanticsLabel: 'RaajjePro',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '🇲🇻 Maldives Local Service Marketplace',
                  style: type.caption.copyWith(
                    color: colors.onPrimary.withValues(alpha: .85),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  style: type.screenTitle.copyWith(color: colors.onPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: type.body.copyWith(
                    color: colors.onPrimary.withValues(alpha: .85),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc(this.diameter, this.color);
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
