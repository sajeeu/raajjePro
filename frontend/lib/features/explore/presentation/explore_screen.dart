import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/explore/controller/categories_controller.dart';
import 'package:raajjepro/features/explore/presentation/tab_placeholder_screen.dart';
import 'package:raajjepro/features/explore/presentation/widgets/category_tile.dart';
import 'package:raajjepro/shared/shared.dart';

/// Explore (`Discovery.dc.html` → Explore) — §Phase 4's one screen.
///
/// **The grid is the endpoint's answer and nothing else.** There is no
/// compiled-in list of twelve anywhere in this file or below it: a category
/// added through the API reaches this screen on the next fetch, which is what
/// §Phase 4's first Done-when line asks for. Four states, all four the
/// prototype's own — skeleton, empty, error, populated.
///
/// **The chrome around the grid is rendered but inert.** Every control here
/// whose destination a later phase owns is drawn exactly as the prototype
/// draws it and does nothing when tapped, marked in the tree by [InertControl]
/// so a test can hold the line (`test/features/explore/explore_chrome_test.dart`):
/// the island pill (Phase 7), the search field (Phase 15), the Saved heart
/// (Phase 14) and the notification bell (Phase 19).
///
/// **One control the prototype has is deliberately absent, not inert:** the
/// "Something urgent? Get help now" entry. Round 23 removed the per-card
/// emergency marker for advertising an action that did not exist; a tappable
/// emergency affordance that goes nowhere is that same error with a person on
/// the other end of it. §Phase 16 owes the entry and Phase 17.3 the dispatch
/// behind it. Recorded in `docs/design/explore-corrections.md`.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  static const routeName = '/explore';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final categories = ref.watch(categoriesControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          const AppHeader.brand(
            leadingSlot: InertControl(
              label: 'Island',
              owedBy: 'Phase 7',
              child: _IslandPill(),
            ),
            actions: [
              // An inert action: the disc renders as it always does and
              // reports itself disabled. Phase 19 supplies the destination.
              AppHeaderAction(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                onTap: null,
              ),
            ],
            trailingSlot: InertControl(
              label: 'Account',
              owedBy: 'Phase 6',
              child: _AccountAvatar(),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Explore Services', style: type.screenTitle),
                  ),
                ),
                const InertControl(
                  label: 'Saved',
                  owedBy: 'Phase 14',
                  child: SaveHeartToggle(
                    saved: false,
                    onChanged: null,
                    style: SaveHeartStyle.flat,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xl,
              AppSpacing.md + 2,
              AppSpacing.xl,
              AppSpacing.md + 2,
            ),
            child: InertControl(
              label: 'Search',
              owedBy: 'Phase 15',
              child: _SearchField(),
            ),
          ),
          Expanded(
            child: switch (categories) {
              AsyncLoading() => const _GridSkeleton(),
              AsyncError(:final error) => _GridError(
                offline: error is ApiNetworkException,
                onRetry: () =>
                    ref.read(categoriesControllerProvider.notifier).reload(),
              ),
              AsyncData(:final value) when value.isEmpty => _GridEmpty(
                onRetry: () =>
                    ref.read(categoriesControllerProvider.notifier).reload(),
              ),
              AsyncData(:final value) => _Grid(categories: value),
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
            currentIndex: 1,
            onSelected: (index) {
              const labels = [
                'Home',
                'Explore',
                'Bookings',
                'Messages',
                'Profile',
              ];
              if (index == 1) return; // already here
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TabPlaceholderScreen(tab: labels[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Marks a control that is drawn to the prototype but wired to nothing yet,
/// naming the phase that owes it a destination.
///
/// It is a real widget rather than a comment so that
/// `explore_chrome_test.dart` can assert the control is present *and* has no
/// callback. When [owedBy] lands and wires the control, that test fails and
/// has to be removed on purpose — which is the point.
class InertControl extends StatelessWidget {
  const InertControl({
    required this.label,
    required this.owedBy,
    required this.child,
    super.key,
  });

  final String label;
  final String owedBy;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The header avatar. Reads the signed-in account rather than asserting one:
/// a guest browses Explore freely (§0.2), and a "G" disc for a signed-in
/// customer named Aishath would be a small lie in the corner of every screen.
class _AccountAvatar extends ConsumerWidget {
  const _AccountAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(authControllerProvider);
    final name = state is AuthSignedIn ? state.user.fullName : null;

    if (name != null && name.trim().isNotEmpty) {
      // No tier overlay here: the badge's words have to be reachable on the
      // same screen wherever the overlay appears, and Explore has nowhere to
      // put them.
      return AppAvatar(name: name, size: AppSizes.avatarMedium);
    }
    return Semantics(
      label: 'Account. Sign in to see yours.',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accentTint,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: AppSizes.avatarMedium,
          child: Icon(
            Icons.person_outline_rounded,
            size: AppSizes.iconLg,
            color: colors.accentText,
          ),
        ),
      ),
    );
  }
}

class _IslandPill extends StatelessWidget {
  const _IslandPill();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Pressable(
      onTap: null,
      semanticLabel: 'Choose your island',
      focusRadius: AppRadius.pill,
      minSize: 0,
      builder: (context, s) => Container(
        height: AppSizes.chipHeight,
        constraints: const BoxConstraints(maxWidth: 130),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.accentTint,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: colors.accentBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 13,
              color: colors.accentText,
            ),
            const SizedBox(width: AppSpacing.xxs + 1),
            Flexible(
              child: Text(
                // Not a stored preference and not a default the product has
                // chosen — Phase 7 owns island selection, and until then the
                // pill names the action rather than asserting a location.
                'Island',
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.accentText,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs + 1),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 11,
              color: colors.accentText,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Semantics(
      label: 'Search services. Not available yet.',
      enabled: false,
      textField: true,
      excludeSemantics: true,
      child: Container(
        height: AppSizes.inputHeight,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          0,
          AppSpacing.sm,
          0,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: colors.border),
          boxShadow: AppShadows.card(colors.ink),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 18, color: colors.placeholder),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'What service do you need?',
                style: type.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.placeholder,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: colors.ctaGradient,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: AppSizes.chipHeight,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: AppSizes.iconMd,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 3-column grid, 12 dp gutters, 20 dp screen insets — the prototype's.
class _Grid extends StatelessWidget {
  const _Grid({required this.categories});

  final List<ServiceCategory> categories;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm + 2,
        AppSpacing.xl,
        AppSpacing.xxl + 4,
      ),
      gridDelegate: _gridDelegate(context),
      itemCount: categories.length,
      itemBuilder: (context, i) => CategoryTile(
        category: categories[i],
        // Category results are Phase 15's surface; the tile is a real control
        // with nothing behind it yet, so it stays inert rather than pretending.
        onTap: null,
      ),
    );
  }
}

/// Three columns, and tall enough for the tile at the user's text scale — a
/// fixed `childAspectRatio` clips the label at 200%, which is the failure the
/// gallery test caught on the header.
SliverGridDelegate _gridDelegate(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(12.5) / 12.5;
  // 56 chip + 10 gap + 18/14 padding + up to two label lines.
  final extent = 56 + 10 + 32 + (15 * scale * 2);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    mainAxisSpacing: AppSpacing.md,
    crossAxisSpacing: AppSpacing.md,
    mainAxisExtent: extent,
  );
}

/// The loading state has the populated layout's shape — twelve tile-shaped
/// bones in the same grid — not a centred spinner.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SkeletonLoader(
        child: GridView.builder(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.sm + 2,
            AppSpacing.xl,
            AppSpacing.xxl + 4,
          ),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: _gridDelegate(context),
          itemCount: 12,
          itemBuilder: (context, _) => const _TileSkeleton(),
        ),
      ),
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: colors.borderCard),
      ),
      child: const Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm,
          AppSpacing.lg + 2,
          AppSpacing.sm,
          AppSpacing.md + 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBox(
              width: CategoryTile.chip,
              height: CategoryTile.chip,
              radius: AppRadius.card,
            ),
            SizedBox(height: AppSpacing.sm + 2),
            SkeletonBox.line(width: 52, height: 10),
          ],
        ),
      ),
    );
  }
}

class _GridError extends StatelessWidget {
  const _GridError({required this.offline, required this.onRetry});

  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppSpacing.screenInsets,
      child: EmptyState.error(
        title: "Categories didn't load",
        // The prototype ends this sentence "Search still works." It does not
        // in this build — the field above is inert until Phase 15 — and a
        // recovery instruction that does not recover is worse than none.
        // Restored with search; see docs/design/explore-corrections.md.
        body: offline
            ? 'Your connection dropped while loading.'
            : "We couldn't reach RaajjePro just then.",
        onRetry: onRetry,
      ),
    );
  }
}

class _GridEmpty extends StatelessWidget {
  const _GridEmpty({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppSpacing.screenInsets,
      child: EmptyState(
        icon: Icons.search_rounded,
        title: 'Nothing to explore yet',
        body:
            'No service categories are available right now. This is usually '
            'temporary — try again in a moment.',
        actionLabel: 'Try again',
        onAction: onRetry,
      ),
    );
  }
}
