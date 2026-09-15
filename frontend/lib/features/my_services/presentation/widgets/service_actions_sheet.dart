import 'package:flutter/material.dart';

import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// What the card's context menu can do. Every one of these performs a real
/// mutation or opens a real screen — §Phase 10's Done-when, and the reason
/// the menu is assembled from the listing's own state rather than drawn
/// whole and half-disabled.
enum ServiceMenuAction {
  /// The wizard, resumed on this listing.
  edit,

  /// §Phase 12's Service Preview — the listing as a customer meets it.
  viewAsCustomer,

  /// §1b's `hidden_by_provider`.
  pause,

  /// Back to `active`.
  resume,

  /// Invariant 8's soft delete, behind its own confirmation.
  delete,
}

/// The card's context menu (`My Services.dc.html`).
///
/// **Which entries appear depends on the listing**, because an entry that
/// cannot do anything is worse than an absent one: a draft has nothing for a
/// customer to view and nothing to pause, and a listing hidden over the
/// entitlement cap cannot be resumed by the provider at all — §1b reserves
/// `hidden_over_cap` to the entitlement system, so a Resume here would ask
/// the server for something it is built to refuse.
Future<ServiceMenuAction?> showServiceActionsSheet({
  required BuildContext context,
  required ServiceListing listing,
}) {
  final isDraft = listing.status == ListingStatus.draft;

  return showAppBottomSheet<ServiceMenuAction>(
    context: context,
    builder: (sheetContext) => AppBottomSheet(
      title: listing.name ?? 'Untitled service',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionRow(
            icon: Icons.edit_outlined,
            label: isDraft ? 'Continue editing' : 'Edit service',
            onTap: () => Navigator.of(sheetContext).pop(ServiceMenuAction.edit),
          ),
          if (!isDraft)
            _ActionRow(
              icon: Icons.visibility_outlined,
              label: 'View as customer',
              onTap: () =>
                  Navigator.of(sheetContext)
                      .pop(ServiceMenuAction.viewAsCustomer),
            ),
          if (!isDraft && !listing.isOverCap)
            if (listing.isLive)
              _ActionRow(
                icon: Icons.pause_circle_outline_rounded,
                label: 'Pause — hide from customers',
                onTap: () =>
                    Navigator.of(sheetContext).pop(ServiceMenuAction.pause),
              )
            else
              _ActionRow(
                icon: Icons.play_circle_outline_rounded,
                label: 'Resume — make live',
                onTap: () =>
                    Navigator.of(sheetContext).pop(ServiceMenuAction.resume),
              ),
          _ActionRow(
            icon: Icons.delete_outline_rounded,
            label: 'Remove service',
            destructive: true,
            onTap: () =>
                Navigator.of(sheetContext).pop(ServiceMenuAction.delete),
          ),
        ],
      ),
    ),
  );
}

/// The removal confirmation. Says what actually happens — customers stop
/// finding it, and everything the listing has already been part of stays —
/// because invariant 8 means nothing is really destroyed and a warning that
/// implied otherwise would be false.
Future<bool> confirmServiceRemoval({
  required BuildContext context,
  required ServiceListing listing,
}) async {
  final confirmed = await showAppBottomSheet<bool>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      final type = sheetContext.type;
      return AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: AppSizes.iconDisc,
              height: AppSizes.iconDisc,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.errorTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: colors.errorText,
                size: AppSizes.iconLg,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(
                'Remove “${listing.name ?? 'this service'}”?',
                style: type.sectionHeading,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'It leaves your services, so customers can no longer find or '
              'book it. Your booking history, reviews and earnings from past '
              'jobs stay in your account.',
              style: type.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Keep it',
                    expand: true,
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm2),
                Expanded(
                  child: AppButton.destructive(
                    label: 'Remove service',
                    expand: true,
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final tint = destructive ? colors.errorTint : colors.surfaceMuted;
    final ink = destructive ? colors.errorText : colors.textTertiary;

    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      focusRadius: AppRadius.input,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.pressed || s.hovered ? colors.surfaceMuted : null,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm2,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.avatarMedium,
                height: AppSizes.avatarMedium,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: AppSizes.iconMd, color: ink),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: type.bodyStrong.copyWith(
                    color: destructive ? colors.errorText : colors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
