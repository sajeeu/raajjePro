import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The inline notices this screen family uses: error (red tint), offline
/// (with retry), info (accent tint) and success (green tint). Shared by
/// Sign In, Register and Verify Email — never a toast, always inline and
/// actionable.
class InlineNotice extends StatelessWidget {
  const InlineNotice._(this.text, this._kind, this.onRetry);
  factory InlineNotice.error(String text) =>
      InlineNotice._(text, _NoticeKind.error, null);
  factory InlineNotice.info(String text) =>
      InlineNotice._(text, _NoticeKind.info, null);
  factory InlineNotice.success(String text) =>
      InlineNotice._(text, _NoticeKind.success, null);
  factory InlineNotice.offline({required VoidCallback onRetry}) =>
      InlineNotice._('No internet connection.', _NoticeKind.offline, onRetry);

  final String text;
  final _NoticeKind _kind;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final (bg, border, fg) = switch (_kind) {
      _NoticeKind.error => (
        colors.errorTint,
        colors.errorBorder,
        colors.errorText,
      ),
      _NoticeKind.info => (
        colors.accentTint,
        colors.accentBorder,
        colors.accentText,
      ),
      _NoticeKind.offline => (
        colors.warningTint,
        colors.warningBorder,
        colors.warningText,
      ),
      _NoticeKind.success => (
        colors.successTint,
        colors.successBorder,
        colors.successText,
      ),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.lg),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: AppRadius.circular(AppRadius.button),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(text, style: type.secondary.copyWith(color: fg)),
              ),
              if (onRetry != null)
                AppButton.text(
                  label: 'Try again',
                  size: AppButtonSize.compact,
                  onPressed: onRetry!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NoticeKind { error, info, offline, success }
