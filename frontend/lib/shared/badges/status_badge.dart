import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// The display statuses a badge can show. These are what a customer or
/// provider *reads*, not the booking state machine (plan §1c): Phase 17 maps
/// machine states onto these, and the label for each lives here so a status
/// is described identically on every screen it appears (`StatusPill.dc.html`).
enum BadgeStatus {
  // Booking
  waitingProvider,
  quoteReceived,
  awaitingPayment,
  paymentSent,
  receiptConfirmed,
  confirmed,
  completed,
  declined,
  cancelled,
  disputed,
  unresolved,

  // Offline queue
  pendingOffline,

  // Listing
  draft,
  hidden,
  published,
}

/// Semantic colour family. Never colour alone — every badge carries a label.
enum BadgeTone { amber, green, blue, red, grey }

/// The status pill: dot + label, one of five tones, radius 999. Reads as
/// "Status: <label>" to a screen reader.
///
/// Copy note (plan §1c, invariant 1c): the payment step reads
/// **"Provider confirmed receipt"** — what actually happened — never
/// "Payment verified". RaajjePro cannot see the transfer.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key})
    : customLabel = null,
      customTone = null;

  /// For a status this enum does not know yet. Prefer adding to
  /// [BadgeStatus] so the label is shared; use this for one-offs only.
  const StatusBadge.custom({
    required String label,
    required BadgeTone tone,
    super.key,
  }) : status = null,
       customLabel = label,
       customTone = tone;

  final BadgeStatus? status;
  final String? customLabel;
  final BadgeTone? customTone;

  static String labelFor(BadgeStatus s) => switch (s) {
    BadgeStatus.waitingProvider => 'Waiting for provider',
    BadgeStatus.quoteReceived => 'Quote received',
    BadgeStatus.awaitingPayment => 'Awaiting payment',
    BadgeStatus.paymentSent => 'Payment sent',
    BadgeStatus.receiptConfirmed => 'Provider confirmed receipt',
    BadgeStatus.confirmed => 'Confirmed',
    BadgeStatus.completed => 'Completed',
    BadgeStatus.declined => 'Declined',
    BadgeStatus.cancelled => 'Cancelled',
    BadgeStatus.disputed => 'Disputed',
    BadgeStatus.unresolved => 'Unresolved',
    BadgeStatus.pendingOffline => 'Pending — sends on reconnect',
    BadgeStatus.draft => 'Draft',
    BadgeStatus.hidden => 'Hidden',
    BadgeStatus.published => 'Published',
  };

  static BadgeTone toneFor(BadgeStatus s) => switch (s) {
    BadgeStatus.waitingProvider ||
    BadgeStatus.awaitingPayment ||
    BadgeStatus.draft => BadgeTone.amber,
    BadgeStatus.receiptConfirmed ||
    BadgeStatus.confirmed ||
    BadgeStatus.published => BadgeTone.green,
    BadgeStatus.quoteReceived ||
    BadgeStatus.paymentSent ||
    BadgeStatus.completed => BadgeTone.blue,
    BadgeStatus.declined ||
    BadgeStatus.cancelled ||
    BadgeStatus.disputed ||
    BadgeStatus.unresolved => BadgeTone.red,
    BadgeStatus.pendingOffline || BadgeStatus.hidden => BadgeTone.grey,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = customLabel ?? labelFor(status!);
    final tone = customTone ?? toneFor(status!);
    final (bg, fg, bd, dot) = switch (tone) {
      BadgeTone.amber => (
        colors.warningTint,
        colors.warningText,
        colors.warningBorder,
        colors.warning,
      ),
      BadgeTone.green => (
        colors.successTint,
        colors.successText,
        colors.successBorder,
        colors.success,
      ),
      BadgeTone.blue => (
        colors.accentTint,
        colors.accentText,
        colors.accentBorder,
        colors.primary,
      ),
      BadgeTone.red => (
        colors.errorTint,
        colors.errorText,
        colors.errorBorder,
        colors.error,
      ),
      BadgeTone.grey => (
        colors.neutralTint,
        colors.neutralText,
        colors.neutralBorder,
        colors.neutralDot,
      ),
    };

    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: bd),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: 5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 6),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  style: context.type.pill.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
