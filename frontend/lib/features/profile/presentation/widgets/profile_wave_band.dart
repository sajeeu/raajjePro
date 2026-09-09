import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// The hero's wave band (`Profile.dc.html`). Round 48 §8 lists it among the
/// things that must not change, so it is drawn rather than dropped.
///
/// Three cubic curves over a 412 × 88 viewBox, rendered 78 dp tall with
/// `preserveAspectRatio="none"` — so the vertical scale is 78/88 and the
/// horizontal one follows the real width. The coordinates are the
/// prototype's; only the colours come from tokens, and every one of them
/// already existed (`background`, `accentBorder`, and the CTA gradient).
///
/// It is decoration and carries no information, so it is hidden from the
/// semantics tree entirely.
class ProfileWaveBand extends StatelessWidget {
  const ProfileWaveBand({super.key});

  /// `height:78px` on a `viewBox="0 0 412 88"`.
  static const height = 78.0;
  static const _viewBox = Size(412, 88);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(
            below: colors.background,
            middle: colors.accentBorder,
            gradient: colors.ctaGradient,
            // The CTA gradient is declared with `AlignmentDirectional`, so
            // its shader cannot resolve without a reading direction — and
            // under RTL the band should sweep the other way, like every other
            // directional token in the app.
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.below,
    required this.middle,
    required this.gradient,
    required this.textDirection,
  });

  final Color below;
  final Color middle;
  final Gradient gradient;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / ProfileWaveBand._viewBox.width,
      size.height / ProfileWaveBand._viewBox.height,
    );

    // M0 46 C120 92 260 22 412 66 L412 88 L0 88 Z — the page background
    // sweeping up under the band, so white sits above it and the scrolling
    // page below.
    final backdrop = Path()
      ..moveTo(0, 46)
      ..cubicTo(120, 92, 260, 22, 412, 66)
      ..lineTo(412, 88)
      ..lineTo(0, 88)
      ..close();

    // M0 12 C100 60 250 -10 412 34 L412 50 C260 8 120 78 0 40 Z
    final trailing = Path()
      ..moveTo(0, 12)
      ..cubicTo(100, 60, 250, -10, 412, 34)
      ..lineTo(412, 50)
      ..cubicTo(260, 8, 120, 78, 0, 40)
      ..close();

    // M0 20 C100 68 240 -2 412 42 L412 66 C260 22 120 92 0 46 Z
    final band = Path()
      ..moveTo(0, 20)
      ..cubicTo(100, 68, 240, -2, 412, 42)
      ..lineTo(412, 66)
      ..cubicTo(260, 22, 120, 92, 0, 46)
      ..close();

    canvas.drawPath(backdrop, Paint()..color = below);
    canvas.drawPath(trailing, Paint()..color = middle);
    canvas.drawPath(
      band,
      Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(
            0,
            0,
            ProfileWaveBand._viewBox.width,
            ProfileWaveBand._viewBox.height,
          ),
          textDirection: textDirection,
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.below != below ||
      old.middle != middle ||
      old.gradient != gradient ||
      old.textDirection != textDirection;
}
