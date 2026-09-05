import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// Star ratings in three shapes.
///
/// * [RatingStars.compact] — one star and `4.6 (31)`, the card form.
/// * [RatingStars.row] — five read-only stars, for a profile or a review.
/// * [RatingStars.input] — five tappable stars (each a 48 dp target), for
///   `Rate This Job`.
///
/// Conduct rule (plan §1f, invariant 11): a rating is a **number the
/// customer reads**, never an editorial label. This widget renders the
/// number and nothing else about the provider. Star ratings are their own
/// axis — §1f's ten-booking floor applies to the conduct metrics, not to
/// stars, and is not enforced here.
class RatingStars extends StatelessWidget {
  const RatingStars.compact({
    required this.rating,
    super.key,
    this.count,
    this.size = 13,
  }) : _shape = _Shape.compact,
       onChanged = null;

  const RatingStars.row({
    required this.rating,
    super.key,
    this.count,
    this.size = 18,
  }) : _shape = _Shape.row,
       onChanged = null;

  const RatingStars.input({
    required int value,
    required ValueChanged<int> this.onChanged,
    super.key,
    this.size = 32,
  }) : rating = value,
       count = null,
       _shape = _Shape.input;

  final num rating;
  final int? count;
  final double size;
  final ValueChanged<int>? onChanged;
  final _Shape _shape;

  String get _ratingText {
    final r = rating.toDouble();
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  String get _spoken {
    final base = 'Rated $_ratingText out of 5';
    if (count == null) return base;
    return '$base from $count ${count == 1 ? 'review' : 'reviews'}';
  }

  @override
  Widget build(BuildContext context) => switch (_shape) {
    _Shape.compact => _compact(context),
    _Shape.row => _row(context),
    _Shape.input => _input(context),
  };

  Widget _compact(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Semantics(
      label: _spoken,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: size, color: colors.warning),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            count == null ? _ratingText : '$_ratingText ($count)',
            style: type.secondary.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context) {
    final colors = context.colors;
    final filled = rating.round().clamp(0, 5);
    return Semantics(
      label: _spoken,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            _Star(
              filled: i <= filled,
              size: size,
              fill: colors.ratingStar,
              stroke: colors.ratingStarStroke,
              empty: colors.ratingStarEmpty,
            ),
        ],
      ),
    );
  }

  Widget _input(BuildContext context) {
    final colors = context.colors;
    final value = rating.toInt();
    return Semantics(
      container: true,
      label: value == 0
          ? 'Rating, none chosen'
          : 'Rating, $value of 5 ${value == 1 ? 'star' : 'stars'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Pressable(
              onTap: () => onChanged!(i),
              selected: i == value,
              semanticLabel: '$i ${i == 1 ? 'star' : 'stars'}',
              focusRadius: AppRadius.sm,
              builder: (context, s) => AnimatedScale(
                scale: s.pressed && !context.motion.reduced ? 1.12 : 1,
                duration: context.motion.fast,
                curve: AppMotion.easeOut,
                child: _Star(
                  filled: i <= value,
                  size: size,
                  fill: colors.ratingStar,
                  stroke: colors.ratingStarStroke,
                  empty: colors.ratingStarEmpty,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _Shape { compact, row, input }

class _Star extends StatelessWidget {
  const _Star({
    required this.filled,
    required this.size,
    required this.fill,
    required this.stroke,
    required this.empty,
  });

  final bool filled;
  final double size;
  final Color fill;
  final Color stroke;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    // Filled star: amber fill with a darker stroke. Empty: outline only.
    // Two icons stacked so the stroke reads at the 3:1 graphics bar.
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: AlignmentDirectional.center,
        children: [
          if (filled) Icon(Icons.star_rounded, size: size, color: fill),
          Icon(
            Icons.star_border_rounded,
            size: size,
            color: filled ? stroke : empty,
          ),
        ],
      ),
    );
  }
}
