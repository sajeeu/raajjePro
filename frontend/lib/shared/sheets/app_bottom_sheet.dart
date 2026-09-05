import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// The bottom-sheet shell (style guide → Bottom sheet): white, 28 dp top
/// radius, a drag handle, 20 dp side padding, safe-area aware. Wraps the
/// content of every confirmation, action menu and success moment.
///
/// Present it with [showAppBottomSheet], which supplies the "spring sheet"
/// motion primitive: `sheetUp` — fade plus a 64 dp rise over `sheet` on
/// `easeOut` — and `sheetDown` over `base` on `easeIn`. Under reduced motion
/// the sheet appears and disappears with no travel.
///
/// Dragging the handle down past a third of the sheet's height dismisses it.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    required this.child,
    super.key,
    this.title,
    this.onClose,
    this.padding = const EdgeInsetsDirectional.fromSTEB(
      AppSpacing.xl,
      0,
      AppSpacing.xl,
      AppSpacing.xl,
    ),
  });

  final Widget child;

  /// Optional heading row: title at section-heading size, with a close
  /// control when [onClose] is given.
  final String? title;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Material(
      color: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle — 36 × 4 pill, 10 dp from the top edge.
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: AppSpacing.sm + 2,
                  bottom: AppSpacing.md,
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.disabledFill,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const SizedBox(width: 36, height: 4),
                  ),
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(title!, style: type.sectionHeading),
                      ),
                    ),
                    if (onClose != null)
                      Pressable(
                        onTap: onClose,
                        semanticLabel: 'Close',
                        tooltip: 'Close',
                        focusRadius: AppRadius.pill,
                        builder: (context, s) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: s.pressed
                                ? colors.background
                                : colors.neutralTint,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(
                            dimension: AppSizes.avatarMedium,
                            child: Center(
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presents [builder]'s widget — normally an [AppBottomSheet] — from the
/// bottom edge with the spring-sheet motion. Returns whatever the sheet
/// pops with.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  String barrierLabel = 'Close sheet',
}) {
  return Navigator.of(context).push<T>(
    _AppSheetRoute<T>(
      builder: builder,
      dismissible: dismissible,
      barrierLabel: barrierLabel,
      motion: AppMotion.of(context),
      scrim: context.colors.scrim,
    ),
  );
}

class _AppSheetRoute<T> extends PopupRoute<T> {
  _AppSheetRoute({
    required this.builder,
    required this.dismissible,
    required this.barrierLabel,
    required this.motion,
    required this.scrim,
  });

  final WidgetBuilder builder;
  final bool dismissible;
  final ResolvedMotion motion;
  final Color scrim;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => scrim;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Duration get transitionDuration => motion.sheet;

  @override
  Duration get reverseTransitionDuration => motion.base;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Rise above the keyboard when the sheet holds an input.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsetsDirectional.only(bottom: keyboard),
        child: Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: _DragToDismiss(
            enabled: dismissible,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: builder(context),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (motion.reduced) return child;
    // Different curves in and out: easeOut arriving, easeIn leaving.
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.easeOut,
      reverseCurve: AppMotion.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, AppMotion.sheetSlide * (1 - curved.value)),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

class _DragToDismiss extends StatefulWidget {
  const _DragToDismiss({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_DragToDismiss> createState() => _DragToDismissState();
}

class _DragToDismissState extends State<_DragToDismiss> {
  double _offset = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final motion = context.motion;
    return GestureDetector(
      onVerticalDragUpdate: (d) =>
          setState(() => _offset = (_offset + d.delta.dy).clamp(0, 1000)),
      onVerticalDragEnd: (d) {
        final height = context.size?.height ?? 0;
        if (_offset > height / 3 ||
            d.primaryVelocity != null && d.primaryVelocity! > 700) {
          Navigator.of(context).maybePop();
        } else {
          setState(() => _offset = 0);
        }
      },
      child: AnimatedContainer(
        duration: _offset == 0 ? motion.base : Duration.zero,
        curve: AppMotion.easeOut,
        transform: Matrix4.translationValues(0, _offset, 0),
        child: widget.child,
      ),
    );
  }
}
