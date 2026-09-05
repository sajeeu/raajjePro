import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The loading state (`SkeletonCard.dc.html`). Every loading screen shimmers
/// **in the shape of the real layout** — never a centred spinner, never a
/// blank — so nothing moves when the data arrives.
///
/// [SkeletonLoader] is the scope: it owns the one shimmer clock its
/// descendants share, announces "Loading" once to a screen reader, and hides
/// the bones from it. Build the shape out of [SkeletonBox]es, or use
/// [SkeletonLoader.rows] for the generic list-row shape.
///
/// Under reduced motion the shimmer stops: the bones stay as static blocks,
/// which is the state the user asked for.
///
/// The card-shaped skeletons (250 × 330 horizontal, 188 full) arrive with
/// the listing card in Phase 15/16 — a skeleton must be built beside the
/// card it stands in for, or the two drift.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    required this.child,
    super.key,
    this.label = 'Loading',
  });

  /// A column of [count] generic rows (`SkeletonCard variant="row"`): a
  /// 96 dp square and three lines. For bookings, invoices, metrics — any
  /// list whose real row is card-shaped and roughly that tall.
  static Widget rows({int count = 3, Key? key}) => SkeletonLoader(
    key: key,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          const SkeletonRow(),
        ],
      ],
    ),
  );

  final Widget child;

  /// What the screen reader hears, once, for the whole skeleton.
  final String label;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.motion.reduced) {
      _controller.stop();
      _controller.value = 0;
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
    return Semantics(
      label: widget.label,
      liveRegion: true,
      excludeSemantics: true,
      child: _ShimmerScope(animation: _controller, child: widget.child),
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.animation != animation;
}

/// One shimmering bone. Sized by the caller to where a real element sits.
/// Outside a [SkeletonLoader] it renders the static base colour.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadius.sm,
    this.shape = BoxShape.rectangle,
  });

  const SkeletonBox.circle({required double dimension, super.key})
    : width = dimension,
      height = dimension,
      radius = 0,
      shape = BoxShape.circle;

  /// A text-line bone: 12 high, 6 radius, as wide as asked.
  const SkeletonBox.line({super.key, this.width, this.height = 12})
    : radius = AppRadius.xxs,
      shape = BoxShape.rectangle;

  final double? width;
  final double? height;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final animation = SkeletonLoader.maybeOf(context);
    final reduced = context.motion.reduced;

    Widget paint(double t) {
      // The band sweeps from -1 to 2 across the box (the CSS 200% trick),
      // so it enters from one edge and leaves by the other. Directional
      // alignment mirrors the sweep under RTL.
      final dx = -1.5 + 3 * t;
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: shape == BoxShape.circle
              ? null
              : BorderRadius.circular(radius),
          color: colors.skeletonBase,
          gradient: reduced || animation == null
              ? null
              : LinearGradient(
                  begin: AlignmentDirectional(dx - 1, 0),
                  end: AlignmentDirectional(dx + 1, 0),
                  colors: [
                    colors.skeletonBase,
                    colors.skeletonHighlight,
                    colors.skeletonBase,
                  ],
                ),
        ),
        child: SizedBox(width: width, height: height),
      );
    }

    if (animation == null || reduced) return paint(0);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => paint(animation.value),
    );
  }
}

/// The generic list row: a 96 dp square beside three lines at 65 / 85 / 50 %.
/// Deliberately unsized in height — it stands in for a dozen different real
/// rows.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderCard),
        borderRadius: BorderRadius.circular(AppRadius.panel),
        boxShadow: AppShadows.card(colors.ink),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(14),
        child: Row(
          children: [
            const SkeletonBox(width: 96, height: 96, radius: AppRadius.input),
            const SizedBox(width: 13),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: c.maxWidth * 0.65,
                      height: 15,
                      radius: AppRadius.xs,
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    SkeletonBox.line(width: c.maxWidth * 0.85),
                    const SizedBox(height: AppSpacing.sm + 2),
                    SkeletonBox.line(width: c.maxWidth * 0.5),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
