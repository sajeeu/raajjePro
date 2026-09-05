import 'package:flutter/widgets.dart';

/// The motion scale (Round 40 — `mockups/design-composer/motion.css`). One
/// scale, two curves. Ambient loops (shimmer, spinner) keep literal
/// durations by convention because they are not a response to a tap.
///
/// Every primitive built on this reads the OS reduced-motion setting through
/// [AppMotion.of]: with it on, durations collapse to zero and loops freeze
/// in place. Use `AppMotion.of(context).fast` rather than [fast] directly
/// wherever a `BuildContext` is available, so the reduced path is automatic.
abstract final class AppMotion {
  /// Hover, press, colour, border.
  static const Duration fast = Duration(milliseconds: 120);

  /// In-place change, content swap, sheet OUT.
  static const Duration base = Duration(milliseconds: 200);

  /// Sheets, overlays, dialogs IN.
  static const Duration sheet = Duration(milliseconds: 300);

  /// Page and view transitions.
  static const Duration page = Duration(milliseconds: 350);

  /// Skeleton shimmer period.
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// Button spinner period.
  static const Duration spinner = Duration(milliseconds: 800);

  /// Entering, settling.
  static const Curve easeOut = Cubic(0.2, 0.8, 0.3, 1);

  /// Leaving.
  static const Curve easeIn = Cubic(0.4, 0, 1, 1);

  /// Tap-scale target.
  static const double pressScale = 0.98;

  /// The distance a screen or sheet travels while entering.
  static const double screenSlide = 26;
  static const double sheetSlide = 64;
  static const double fadeUpSlide = 14;

  /// Durations resolved against the OS reduced-motion setting.
  static ResolvedMotion of(BuildContext context) =>
      ResolvedMotion(reduced: MediaQuery.disableAnimationsOf(context));
}

/// [AppMotion] with the reduced-motion decision already applied.
@immutable
class ResolvedMotion {
  const ResolvedMotion({required this.reduced});

  /// True when the OS asks for reduced motion. Loops (shimmer, spinner,
  /// pulse) should render their resting frame; transitions should cut.
  final bool reduced;

  Duration get fast => reduced ? Duration.zero : AppMotion.fast;
  Duration get base => reduced ? Duration.zero : AppMotion.base;
  Duration get sheet => reduced ? Duration.zero : AppMotion.sheet;
  Duration get page => reduced ? Duration.zero : AppMotion.page;

  /// Slide distances go to zero too — a zero-duration slide still lays out
  /// one off-screen frame, which is visible as a flash on slow devices.
  double get screenSlide => reduced ? 0 : AppMotion.screenSlide;
  double get sheetSlide => reduced ? 0 : AppMotion.sheetSlide;
  double get fadeUpSlide => reduced ? 0 : AppMotion.fadeUpSlide;
  double get pressScale => reduced ? 1 : AppMotion.pressScale;
}
