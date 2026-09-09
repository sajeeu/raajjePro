import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The role switcher (`Profile.dc.html`'s sheet; plan §Phase 6).
///
/// > **Role switcher:** an explicit customer ⇄ provider mode control.
/// > Providers are the only paying users; their workspace must not be buried.
///
/// The sheet states the rule and the row below it acts on it. Round 48 §8
/// lists the sheet, its copy and the Become-a-Provider link among the things
/// that must not change, so the three paragraphs are the prototype's
/// verbatim — and they read correctly for either case, because they describe
/// the rule rather than asserting which branch this user is on.
class RoleSwitchSheet extends StatelessWidget {
  const RoleSwitchSheet({required this.onSwitch, super.key});

  /// Called when the Provider card is chosen. The destination is decided by
  /// [RoleSwitch], not here — this widget does not know or care whether the
  /// user has onboarded.
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppBottomSheet(
      title: "How you're using RaajjePro",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          const _ModeCard(
            icon: Icons.person_outline_rounded,
            label: 'Customer',
            description: 'Find and book services',
            current: true,
            onTap: null,
          ),
          const SizedBox(height: AppSpacing.md),
          _ModeCard(
            icon: Icons.work_outline_rounded,
            label: 'Provider',
            description: 'List services and take bookings',
            current: false,
            onTap: onSwitch,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg - 2,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.accentTint,
              border: Border.all(color: colors.accentBorder),
              borderRadius: AppRadius.circular(AppRadius.button),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: AppSizes.iconMd,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md - 1),
                Expanded(
                  child: Text(
                    'Your first switch opens Become a Provider — a short '
                    'setup for your first listing. Already set up? You land '
                    'straight on My Services. Switching is instant and '
                    'reversible, and nothing on your customer side is lost.',
                    style: type.secondary.copyWith(
                      color: colors.accentText,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Not now',
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// How prominent a [ModePill] is. Two only: the solid primary pill marking
/// the mode you are in, and the quiet neutral one naming it on the row that
/// opens the sheet.
enum ModePillEmphasis { primary, neutral }

/// The small mode pill (`Profile.dc.html`). Not an [AppChip]: the chip's
/// three kinds are a 38 dp filter, a removable input and a 28 dp static
/// label, and this is a 22 dp badge inside a row of text. Not a
/// [StatusBadge] either — that owns *booking* status copy, and a role is not
/// a booking status.
class ModePill extends StatelessWidget {
  const ModePill({required this.label, required this.emphasis, super.key});

  final String label;
  final ModePillEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final primary = emphasis == ModePillEmphasis.primary;
    return Container(
      height: 22,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm + 1,
      ),
      decoration: BoxDecoration(
        color: primary ? colors.primary : colors.neutralTint,
        borderRadius: AppRadius.circular(AppRadius.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: type.pill.copyWith(
          color: primary ? colors.onPrimary : colors.neutralText,
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.current,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      onTap: onTap,
      semanticLabel: onTap == null ? null : '$label. $description',
      selected: current,
      color: current ? colors.surfaceMuted : null,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconDisc - 2,
            height: AppSizes.iconDisc - 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current ? colors.accentTint : colors.neutralTint,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 19,
              color: current ? colors.primary : colors.neutralText,
            ),
          ),
          const SizedBox(width: AppSpacing.md + 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(label, style: type.cardTitle)),
                    if (current) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const ModePill(
                        label: "You're here now",
                        emphasis: ModePillEmphasis.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: colors.placeholder),
        ],
      ),
    );
  }
}
