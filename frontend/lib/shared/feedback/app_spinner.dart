import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The small ring that sits beside a button label while it works — a track
/// at 35% and a 90° arc in the foreground colour, one turn per
/// [AppMotion.spinner]. Under reduced motion the arc holds still: the state
/// is still visible, nothing moves.
///
/// Semantically silent on purpose; the owning control reports busy.
class AppSpinner extends StatefulWidget {
  const AppSpinner({
    required this.color,
    super.key,
    this.size = 16,
    this.strokeWidth = 2.5,
    this.trackColor,
  });

  final Color color;
  final double size;
  final double strokeWidth;

  /// Defaults to [color] at 35% opacity.
  final Color? trackColor;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.spinner,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.motion.reduced) {
      _controller.stop();
      _controller.value = 0.125;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _RingPainter(
              turn: _controller.value,
              color: widget.color,
              track: widget.trackColor ?? widget.color.withValues(alpha: 0.35),
              stroke: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.turn,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double turn;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inset, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      inset,
      turn * math.pi * 2 - math.pi / 2,
      math.pi / 2,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.turn != turn || old.color != color || old.track != track;
}
