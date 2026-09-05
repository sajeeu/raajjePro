import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The text input (`Components.dc.html` → Text input). Label above at
/// 14/700; a 52 dp-minimum field with a 14 radius and a 1.5 border; states
/// default · focused (primary border, 3 dp glow) · filled · error · disabled
/// · read-only (dashed border, muted fill, lock).
///
/// **The error shows as a message under the field**, in error red — never a
/// tooltip, never a toast. It is spoken with the label so a screen-reader
/// user hears what is wrong on the field itself.
///
/// The field grows with the OS text size; 52 is a floor, not a height.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.helper,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.maxLength,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.autocorrect = true,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;

  /// Guidance under the field when there is no error.
  final String? helper;

  /// Sets the error state. Belongs under its field, inline.
  final String? errorText;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  /// Renders a live `n / max` counter when set.
  final int? maxLength;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool autocorrect;
  final TextCapitalization textCapitalization;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focus = widget.focusNode ?? FocusNode();
  TextEditingController? _ownController;
  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    _controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(AppTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      _focus.removeListener(_rebuild);
      if (old.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _focus.addListener(_rebuild);
    }
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    if (widget.focusNode == null) _focus.dispose();
    _controller.removeListener(_rebuild);
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final motion = context.motion;

    final hasError = widget.errorText != null;
    final focused = _focus.hasFocus;
    final interactive = widget.enabled && !widget.readOnly;

    final borderColor = !widget.enabled
        ? colors.border
        : hasError
        ? colors.error
        : focused
        ? colors.primary
        : colors.border;
    final fill = !widget.enabled
        ? colors.neutralTint
        : widget.readOnly
        ? colors.surfaceMuted
        : colors.surface;
    final textColor = widget.enabled
        ? (widget.readOnly ? colors.textTertiary : colors.ink)
        : colors.disabledText;

    final labelStyle = type.bodyStrong.copyWith(
      fontWeight: FontWeight.w700,
      color: widget.enabled ? colors.ink : colors.disabledText,
    );

    final spoken = StringBuffer(widget.label);
    if (hasError) spoken.write(', ${widget.errorText}');
    if (!hasError && widget.helper != null) spoken.write(', ${widget.helper}');
    if (widget.readOnly) spoken.write(', read only');

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autocorrect: widget.autocorrect,
      textCapitalization: widget.textCapitalization,
      cursorColor: colors.primary,
      style: type.bodyStrong.copyWith(color: textColor),
      decoration:
          InputDecoration.collapsed(
            hintText: widget.hint,
            hintStyle: type.bodyStrong.copyWith(color: colors.placeholder),
          ).copyWith(
            counterText: '',
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(widget.label, style: labelStyle)),
        const SizedBox(height: AppSpacing.sm),
        // MergeSemantics folds the label and the editable into one node whose
        // rect is the whole 52 dp box; the GestureDetector makes that box the
        // real tap target too, so a tap on the padding focuses the field.
        MergeSemantics(
          child: Semantics(
            label: spoken.toString(),
            // Read-only is still enabled — it says "read only", not "dimmed".
            enabled: widget.enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: interactive ? _focus.requestFocus : null,
              child: AnimatedContainer(
                duration: motion.fast,
                curve: AppMotion.easeOut,
                constraints: const BoxConstraints(
                  minHeight: AppSizes.inputHeight,
                ),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: widget.readOnly
                      ? null
                      : Border.all(
                          color: borderColor,
                          width: AppSizes.inputStroke,
                        ),
                  boxShadow: focused && interactive && !hasError
                      ? [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.12),
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: CustomPaint(
                  foregroundPainter: widget.readOnly
                      ? _DashedBorderPainter(
                          color: colors.border,
                          radius: AppRadius.input,
                          stroke: AppSizes.inputStroke,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md + 2,
                    ),
                    child: Row(
                      crossAxisAlignment: widget.maxLines == 1
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        if (widget.prefixIcon != null) ...[
                          Icon(
                            widget.prefixIcon,
                            size: 18,
                            color: colors.placeholder,
                          ),
                          const SizedBox(width: AppSpacing.sm + 2),
                        ],
                        Expanded(child: field),
                        if (widget.readOnly)
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 15,
                            color: colors.disabledText,
                          )
                        else if (widget.suffix != null)
                          widget.suffix!,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasError || widget.helper != null || widget.maxLength != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: hasError
                        ? Text(
                            widget.errorText!,
                            style: type.helper.copyWith(color: colors.error),
                          )
                        : widget.helper != null
                        ? Text(widget.helper!, style: type.helper)
                        : const SizedBox.shrink(),
                  ),
                ),
                if (widget.maxLength != null)
                  Text(
                    '${_controller.text.characters.length} / ${widget.maxLength}',
                    style: type.caption.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A 1.5 dp dashed rounded border for the read-only state.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.stroke,
  });

  final Color color;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(stroke / 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.stroke != stroke;
}
