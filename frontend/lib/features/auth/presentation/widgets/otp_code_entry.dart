import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// Six one-digit boxes (`Verify Email.dc.html`): typing advances, backspace
/// on an empty box retreats, a paste of six digits fills all. Error paints
/// every border red; disabled greys the fill (the invalidated state).
class OtpCodeEntry extends StatefulWidget {
  const OtpCodeEntry({
    required this.onChanged,
    required this.onCompleted,
    super.key,
    this.enabled = true,
    this.error = false,
    this.clearToken = 0,
  });
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool error;

  /// Bump to clear every box (after a wrong attempt).
  final int clearToken;

  @override
  State<OtpCodeEntry> createState() => _OtpCodeEntryState();
}

class _OtpCodeEntryState extends State<OtpCodeEntry> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focus = List.generate(6, (_) => FocusNode());

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void didUpdateWidget(OtpCodeEntry old) {
    super.didUpdateWidget(old);
    if (old.clearToken != widget.clearToken) {
      for (final c in _controllers) {
        c.clear();
      }
      _focus.first.requestFocus();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _changed(int i, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var j = 0; j < 6; j++) {
        _controllers[j].text = j < digits.length ? digits[j] : '';
      }
      _focus[digits.length.clamp(0, 5)].requestFocus();
    } else {
      _controllers[i].text = digits;
      if (digits.isNotEmpty && i < 5) _focus[i + 1].requestFocus();
    }
    widget.onChanged(_code);
    if (_code.length == 6) widget.onCompleted(_code);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Semantics(
      container: true,
      label: '6-digit verification code',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.xxs,
              ),
              child: SizedBox(
                width: 48,
                height: 58,
                child: KeyboardListener(
                  focusNode: FocusNode(skipTraversal: true),
                  onKeyEvent: (e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.backspace &&
                        _controllers[i].text.isEmpty &&
                        i > 0) {
                      _focus[i - 1].requestFocus();
                    }
                  },
                  child: TextField(
                    key: Key('otp-$i'),
                    controller: _controllers[i],
                    focusNode: _focus[i],
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: type.stat.copyWith(color: colors.ink),
                    onChanged: (v) => _changed(i, v),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: widget.enabled
                          ? colors.surface
                          : colors.surfaceMuted,
                      semanticCounterText: 'Digit ${i + 1}',
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.circular(AppRadius.input),
                        borderSide: BorderSide(
                          color: widget.error
                              ? colors.errorBorder
                              : colors.border,
                          width: AppSizes.inputStroke,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.circular(AppRadius.input),
                        borderSide: BorderSide(
                          color: colors.primary,
                          width: AppSizes.inputStroke,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.circular(AppRadius.input),
                        borderSide: BorderSide(
                          color: colors.errorBorder,
                          width: AppSizes.inputStroke,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
