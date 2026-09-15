import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/badges/status_badge.dart';
import 'package:raajjepro/shared/buttons/app_button.dart';
import 'package:raajjepro/shared/cards/app_card.dart';

/// One thing that keeps working with no connection.
class OfflineCapability {
  const OfflineCapability({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// The app-wide **no-connection** state (`App States.dc.html`).
///
/// §Phase 9 owns it, and the reason is in the second card: this is the first
/// phase in which queue-and-replay exists, and therefore the first point at
/// which the explainer's claims are true. A screen that had promised offline
/// saving before there was any would have been a lie with a nice icon.
///
/// ## The list grows; it is not written once
///
/// [_capabilities] carries exactly what the app can actually do offline today.
/// Later phases append to it as they build the surface:
///
///  - **§Phase 17.1** adds the slot and request accept prompt.
///  - **§Phase 18** adds message sending.
///  - **§Phase 17.3** adds the *exclusion*: the emergency accept needs a live
///    connection (§0.0 item 14 — a replayed offer would commit a provider to a
///    callout fee and an arrival estimate calculated somewhere else, and
///    offers are collected in 90 seconds). `App States.dc.html` draws that row
///    in red beneath the list. It is deliberately **not here yet**: telling a
///    provider today that emergency offers need a connection would describe a
///    control this app does not have.
///  - **§Phase 17.1** also owns the payment half of the footnote — the
///    prototype's "and no payment is recorded" describes an attestation no
///    phase has built.
class NoConnectionView extends ConsumerStatefulWidget {
  const NoConnectionView({super.key, this.onRetry});

  /// An extra thing to do once the connection is back — usually the screen's
  /// own reload. The queue replays either way.
  final Future<void> Function()? onRetry;

  @override
  ConsumerState<NoConnectionView> createState() => _NoConnectionViewState();
}

class _NoConnectionViewState extends ConsumerState<NoConnectionView> {
  bool _checking = false;

  /// Only after a retry has been asked for and failed. A line that says
  /// "Still offline" before anybody tried is not information.
  bool _stillOffline = false;

  static const _capabilities = [
    OfflineCapability(
      icon: Icons.save_outlined,
      label: 'Saving a step of the service wizard',
    ),
  ];

  Future<void> _retry() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _stillOffline = false;
    });
    await ref.read(offlineQueueProvider.notifier).retryNow();
    await widget.onRetry?.call();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _stillOffline = !ref.read(offlineQueueProvider).online;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.screen,
          vertical: AppSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              radius: AppRadius.feature,
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xxl,
                AppSpacing.n28,
                AppSpacing.xxl,
                AppSpacing.xxl,
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.feature),
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: AppSpacing.n34,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No internet connection.',
                    textAlign: TextAlign.center,
                    style: type.screenTitle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "We'll reconnect automatically — or try now.",
                    textAlign: TextAlign.center,
                    style: type.body.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton.primary(
                    label: _checking ? 'Checking…' : 'Try Again',
                    loading: _checking,
                    onPressed: _checking ? null : _retry,
                  ),
                  if (_stillOffline) ...[
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        "Still offline — we'll keep trying in the background.",
                        textAlign: TextAlign.center,
                        style: type.caption.copyWith(color: colors.warningText),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('These keep working offline', style: type.bodyStrong),
                  const SizedBox(height: AppSpacing.md),
                  for (final capability in _capabilities)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.md,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: colors.surfaceMuted,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(
                              capability.icon,
                              size: AppSizes.iconMd,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  capability.label,
                                  style: type.body.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                const StatusBadge(BadgeStatus.pendingOffline),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Divider(height: 1, color: colors.divider),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'They send when the connection returns — nothing reaches '
                    'RaajjePro until they do.',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
