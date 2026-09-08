import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The gradient banner Sign In alone carries (`Sign In.dc.html` lines
/// 28–40): the brand gradient with three faint discs, a 42 dp circular icon
/// badge next to the `Raajje`/`Pro` wordmark, the Maldives tagline, and a
/// wave that overlaps the bottom 34 dp in the page colour. It carries no
/// title or subtitle — Sign In renders those itself, below the hero, in ink
/// on the page background (Register renders neither the hero nor a title
/// here at all; see `CircleBackButton` and `register_screen.dart`).
class AuthHero extends StatelessWidget {
  const AuthHero({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Stack(
      children: [
        // `width: double.infinity` is load-bearing. The screen gives this
        // widget a TIGHT 411 dp width (`CrossAxisAlignment.stretch` in
        // `sign_in_screen.dart`), but a `Stack` hands its non-positioned
        // children LOOSE constraints — `StackFit.loose` is the default. So
        // the gradient box below sized to its own child instead, which is a
        // `Column(mainAxisSize: min)` whose widest line is the tagline: the
        // banner painted 293 dp wide on a 411 dp screen, with a hard vertical
        // edge two-thirds across, while the `Stack` around it stayed full
        // width.
        //
        // That asymmetry is why it survived review. The prototype's CSS never
        // states a width because a block `<div>` fills its container; and
        // measuring `AuthHero` itself reports 411, because the Stack is 411 —
        // only the gradient inside it is short. `sign_in_layout_test.dart`
        // therefore measures this box, not the widget.
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  colors.gradientStart,
                  colors.primary,
                  colors.primaryPressed,
                ],
                stops: const [0, .55, 1],
              ),
            ),
            child: Stack(
              children: [
                // The three faint discs behind the wordmark, positioned to
                // match the prototype's top-right pair and bottom-left single
                // disc — each its own opacity (.08 / .07 / .06).
                PositionedDirectional(
                  top: -46,
                  end: -34,
                  child: ExcludeSemantics(
                    child: _Disc(150, colors.onPrimary.withValues(alpha: .08)),
                  ),
                ),
                PositionedDirectional(
                  top: 64,
                  end: 64,
                  child: ExcludeSemantics(
                    child: _Disc(90, colors.onPrimary.withValues(alpha: .07)),
                  ),
                ),
                PositionedDirectional(
                  bottom: -20,
                  start: -30,
                  child: ExcludeSemantics(
                    child: _Disc(110, colors.onPrimary.withValues(alpha: .06)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.xxl,
                    54,
                    AppSpacing.xxl,
                    26,
                  ),
                  // Full width for the same reason as the gradient above, with a second
                  // consequence: the Column centres its children (CrossAxisAlignment.center
                  // is the default), but centring inside a box that has shrink-wrapped to
                  // its widest child does nothing. Without this the wordmark and tagline
                  // sat hard against the leading edge — visible only once the gradient
                  // stopped being 293 dp wide and hiding it. The prototype centres them:
                  // its icon badge sits at x=126 in a 412 frame, not at the 24 dp padding.
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _IconBadge(colors: colors),
                            const SizedBox(width: 11),
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
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm + 2),
                        Text(
                          '🇲🇻 Maldives Local Service Marketplace',
                          style: type.secondary.copyWith(
                            color: colors.onPrimary.withValues(alpha: .85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The wave: painted over the hero's own bottom 34 dp in the page
        // colour, the Flutter equivalent of the prototype's `margin-top:
        // -34px` overlap (`M0 20 C 90 36 210 4 412 16 L 412 34 L 0 34 Z`).
        PositionedDirectional(
          bottom: 0,
          start: 0,
          end: 0,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 34,
              child: CustomPaint(painter: _HeroWavePainter(colors.background)),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: colors.onPrimary.withValues(alpha: .16),
      border: Border.all(color: colors.onPrimary.withValues(alpha: .28)),
    ),
    alignment: Alignment.center,
    child: Icon(Icons.location_on_rounded, size: 20, color: colors.onPrimary),
  );
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

/// Traces `M0 20 C 90 36 210 4 412 16 L 412 34 L 0 34 Z` from the 412×34
/// prototype viewBox, scaled to whatever width the hero actually renders at.
class _HeroWavePainter extends CustomPainter {
  const _HeroWavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 412;
    final sy = size.height / 34;
    final path = Path()
      ..moveTo(0, 20 * sy)
      ..cubicTo(90 * sx, 36 * sy, 210 * sx, 4 * sy, 412 * sx, 16 * sy)
      ..lineTo(412 * sx, 34 * sy)
      ..lineTo(0, 34 * sy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeroWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
