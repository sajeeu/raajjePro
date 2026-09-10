import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/profile/controller/profile_controller.dart';
import 'package:raajjepro/features/profile/controller/role_switch.dart';
import 'package:raajjepro/features/profile/data/profile_api.dart';
import 'package:raajjepro/features/profile/presentation/widgets/booking_tiles.dart';
import 'package:raajjepro/features/profile/presentation/widgets/profile_hero.dart';
import 'package:raajjepro/features/profile/presentation/widgets/role_switch_sheet.dart';
import 'package:raajjepro/shared/shared.dart';

/// Profile (`Profile.dc.html`; plan §Phase 6) — the customer's account home.
///
/// Four states, all four the prototype's own: skeleton, error, populated —
/// and no empty state, deliberately. This screen renders the signed-in
/// account, and an account always has a name and a join date; "empty" here
/// would mean "you do not exist". A failed read is the error state.
///
/// **Every one of the five rows navigates**, which §Phase 6's Done-when
/// requires, and only two of the five destinations exist today: Account
/// settings is Phase 3's real screen and Legal is Phase 3's placeholder
/// index. Saved (Phase 14), Saved preferences (Phase 17.4) and Help & support
/// (Phase 19b) land on [UnbuiltScreen], which names the owing phase rather
/// than doing nothing. The four booking tiles do the same, each carrying its
/// own tab so Round 48 §2's "four labels, one destination" defect does not
/// come back through the placeholder.
///
/// **The provider-mode `Verification` row is not here.** `Profile.dc.html`
/// prepends one when the session role is provider; §Phase 6 says five rows,
/// verification review is §Phase 10a's queue and §1e's tiers, and Phase 10
/// owns the provider workspace this screen hands off to.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const routeName = AppRoutes.profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final summary = ref.watch(profileControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Profile',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (summary) {
              AsyncLoading() => const _ProfileSkeleton(),
              AsyncError(:final error) => _ProfileError(
                offline: error is ApiNetworkException,
                onRetry: () =>
                    ref.read(profileControllerProvider.notifier).reload(),
              ),
              AsyncData(:final value) => _ProfileBody(summary: value),
            },
          ),
          AnimatedBottomNav(
            items: const [
              AppNavItem(icon: Icons.home_outlined, label: 'Home'),
              AppNavItem(icon: Icons.explore_outlined, label: 'Explore'),
              AppNavItem(
                icon: Icons.calendar_today_outlined,
                label: 'Bookings',
              ),
              AppNavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Messages',
              ),
              AppNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
            ],
            currentIndex: 4,
            onSelected: (index) => _onTabSelected(context, index),
          ),
        ],
      ),
    );
  }

  /// There is no tab shell yet — §Phase 16 owns it — so a tab push is a
  /// plain push, exactly as Explore's is. Explore exists and is pushed by
  /// name; the other three land on their placeholder.
  static void _onTabSelected(BuildContext context, int index) {
    const labels = ['Home', 'Explore', 'Bookings', 'Messages', 'Profile'];
    if (index == 4) return; // already here
    if (index == 1) {
      Navigator.of(context).pushNamed(AppRoutes.explore);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnbuiltScreen(
          title: labels[index],
          owedBy: switch (index) {
            0 => 'Phase 16',
            2 => 'Phase 17',
            _ => 'Phase 18',
          },
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.summary});

  final ProfileSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileHero(
            fullName: summary.fullName,
            memberSince: summary.memberSince,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xl,
              AppSpacing.md + 2,
              AppSpacing.xl,
              AppSpacing.xxl + 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 2,
                    bottom: AppSpacing.md,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text('My bookings', style: type.sectionHeading),
                  ),
                ),
                BookingTilesCard(
                  onSelected: (tile) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      // Each tile keeps its own destination: the placeholder
                      // names the tab, so the four are not four labels for
                      // one screen (Round 48 §2).
                      builder: (_) => UnbuiltScreen(
                        title: '${tile.label} bookings',
                        owedBy: 'Phase 17',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final row in _rows) ...[
                  SettingsRow(
                    icon: row.icon,
                    title: row.title,
                    onTap: () => Navigator.of(context).pushNamed(row.route),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _RoleSwitchRow(isProvider: summary.isProvider),
                const SizedBox(height: AppSpacing.sm),
                const _SignOutButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The five rows §Phase 6 names, in Round 48 §4's final order. Subtitle-free
  /// by that same section.
  static const _rows = [
    (
      icon: Icons.favorite_border_rounded,
      title: 'Saved',
      route: AppRoutes.saved,
    ),
    (
      icon: Icons.tune_rounded,
      title: 'Saved preferences',
      route: AppRoutes.savedPreferences,
    ),
    (
      icon: Icons.lock_outline_rounded,
      title: 'Account settings',
      route: AppRoutes.accountSettings,
    ),
    (
      icon: Icons.help_outline_rounded,
      title: 'Help & support',
      route: AppRoutes.help,
    ),
    (icon: Icons.description_outlined, title: 'Legal', route: AppRoutes.legal),
  ];
}

/// "Switch to providing" — §Phase 6's role switcher, and the only navigation
/// change in the app that departs from the original mockups.
///
/// Opens the sheet; the sheet's Provider card resolves through [RoleSwitch],
/// so a first switch reaches §Phase 6a's onboarding and every later one
/// §Phase 10's dashboard. The pill names the mode you are in now.
class _RoleSwitchRow extends StatelessWidget {
  const _RoleSwitchRow({required this.isProvider});

  final bool isProvider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      onTap: () => showAppBottomSheet<void>(
        context: context,
        builder: (sheetContext) => RoleSwitchSheet(
          onSwitch: () {
            // Close the sheet first, so Back from the destination returns to
            // Profile rather than to a sheet over it.
            Navigator.of(sheetContext).pop();
            Navigator.of(context)
                .pushNamed(RoleSwitch.destinationFor(isProvider: isProvider));
          },
        ),
      ),
      semanticLabel: "Switch to providing. You're a customer now.",
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg - 1,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconDisc - 2,
            height: AppSizes.iconDisc - 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: colors.ctaGradient,
              boxShadow: AppShadows.cta(colors.primary, alpha: 0.22),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.work_outline_rounded,
              size: AppSizes.iconLg,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.md + 1),
          Expanded(child: Text('Switch to providing', style: type.cardTitle)),
          const ModePill(label: 'Customer', emphasis: ModePillEmphasis.neutral),
        ],
      ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    return Pressable(
      // Signing out has to leave the screen as well as clear the session.
      // `AuthGate` renders the guest home under this route, and `app.dart`'s
      // listener pops only for a session *expiry* — so without this, Profile
      // stays on top still showing the name of the account that just signed
      // out.
      onTap: () async {
        final navigator = Navigator.of(context);
        await ref.read(authControllerProvider.notifier).signOut();
        navigator.popUntil((r) => r.isFirst);
      },
      semanticLabel: 'Sign out',
      builder: (context, s) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 17, color: colors.error),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Sign out',
              style: type.button.copyWith(color: colors.errorText),
            ),
          ],
        ),
      ),
    );
  }
}

/// The loading state has the populated layout's shape — a disc, two lines,
/// a four-tile block and three rows — not a centred spinner.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: SkeletonLoader(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              ColoredBox(
                color: colors.surface,
                child: const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.xl,
                    AppSpacing.sm + 2,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    children: [
                      SkeletonBox(
                        width: ProfileHero.avatarSize,
                        height: ProfileHero.avatarSize,
                        shape: BoxShape.circle,
                      ),
                      SizedBox(height: AppSpacing.md + 2),
                      SkeletonBox.line(width: 160, height: 18),
                      SizedBox(height: AppSpacing.sm),
                      SkeletonBox.line(width: 220),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.borderCard),
                        borderRadius: AppRadius.circular(AppRadius.feature),
                      ),
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.lg + 2,
                      ),
                      child: const Column(
                        children: [
                          _TileRowSkeleton(),
                          SizedBox(height: AppSpacing.lg + 2),
                          _TileRowSkeleton(),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (var i = 0; i < 3; i += 1)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(
                          bottom: AppSpacing.md,
                        ),
                        child: SkeletonRow(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileRowSkeleton extends StatelessWidget {
  const _TileRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _TileSkeleton()),
        Expanded(child: _TileSkeleton()),
      ],
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(width: 52, height: 52, radius: AppRadius.tile),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox.line(width: 56, height: 10),
      ],
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.offline, required this.onRetry});

  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.xxxl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: EmptyState.error(
        title: "Couldn't load your profile",
        // The prototype's own copy, which is already honest about the one
        // thing a customer would worry about here.
        body: offline
            ? 'Your connection dropped. Your account is safe — try again.'
            : 'Your account is safe — try again.',
        onRetry: onRetry,
      ),
    );
  }
}
