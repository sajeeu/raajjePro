import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// What a [Pressable] child needs to know to draw itself.
@immutable
class PressState {
  const PressState({
    required this.pressed,
    required this.focused,
    required this.hovered,
    required this.enabled,
  });

  final bool pressed;
  final bool focused;
  final bool hovered;
  final bool enabled;
}

typedef PressableBuilder = Widget Function(BuildContext context, PressState s);

/// The interaction base for every tappable thing in the app. It owns the
/// three things the plan's accessibility baseline makes non-negotiable so
/// no widget can forget one:
///
/// * a **48 dp minimum hit area** — the visual child may be smaller (a 38 dp
///   chip, a 32 dp heart) and is centred inside the floor;
/// * **semantics** — a button (or a toggle when [toggled] is given) with a
///   label, correctly reported as disabled;
/// * the **tap-scale** motion primitive (0.98 over `fast`), which is a no-op
///   under the OS reduced-motion setting;
///
/// plus a visible focus ring for keyboard and switch-access users. It draws
/// nothing itself — the [builder] draws the control from the [PressState].
class Pressable extends StatefulWidget {
  const Pressable({
    required this.builder,
    required this.semanticLabel,
    super.key,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.toggled,
    this.selected,
    this.minSize = AppSizes.touchTarget,
    this.focusRadius = AppRadius.button,
    this.excludeSemantics = false,
    this.tooltip,
  });

  final PressableBuilder builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// Read by screen readers. Never empty — an icon-only control still says
  /// what it does.
  final String semanticLabel;

  /// Set for a two-state control (save heart, toggle): announced as
  /// "on"/"off" rather than as a plain button.
  final bool? toggled;

  /// Set for a selectable-in-a-set control (filter chip, nav tab).
  final bool? selected;

  /// Hit-area floor on both axes.
  final double minSize;

  /// Corner radius of the focus ring, matched to the child's shape.
  final double focusRadius;

  /// When the child carries its own complete semantics.
  final bool excludeSemantics;

  /// Long-press hint for icon-only controls.
  final String? tooltip;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Pressable');
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final colors = context.colors;
    final state = PressState(
      pressed: _pressed && _interactive,
      focused: _focused,
      hovered: _hovered && _interactive,
      enabled: _interactive,
    );

    Widget child = widget.builder(context, state);

    // Only a keyboard/switch focus shows the ring — a touch focus does not.
    final showRing =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    child = AnimatedScale(
      scale: state.pressed ? motion.pressScale : 1,
      duration: motion.fast,
      curve: AppMotion.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.focusRadius),
          border: showRing
              ? Border.all(
                  color: colors.primary,
                  width: AppSizes.selectedStroke,
                )
              : null,
        ),
        child: child,
      ),
    );

    child = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.minSize,
        minHeight: widget.minSize,
      ),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );

    child = FocusableActionDetector(
      enabled: _interactive,
      focusNode: _focusNode,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      mouseCursor: _interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _interactive ? (_) => _setPressed(true) : null,
        onTapUp: _interactive ? (_) => _setPressed(false) : null,
        onTapCancel: _interactive ? () => _setPressed(false) : null,
        onTap: _interactive ? widget.onTap : null,
        onLongPress: _interactive ? widget.onLongPress : null,
        child: child,
      ),
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip, child: child);
    }

    if (widget.excludeSemantics) return child;

    return Semantics(
      container: true,
      button: widget.toggled == null,
      toggled: widget.toggled,
      selected: widget.selected,
      enabled: _interactive,
      // excludeSemantics drops the detector's own focus node from the tree,
      // so focusability is restated here for switch-access users.
      focusable: _interactive,
      focused: _focused,
      onFocus: _interactive ? _focusNode.requestFocus : null,
      label: widget.semanticLabel,
      onTap: _interactive ? widget.onTap : null,
      onLongPress: _interactive ? widget.onLongPress : null,
      excludeSemantics: true,
      child: child,
    );
  }
}
