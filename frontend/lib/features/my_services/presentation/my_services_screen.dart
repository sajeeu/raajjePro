import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/my_services/controller/my_services_controller.dart';
import 'package:raajjepro/features/my_services/presentation/widgets/service_actions_sheet.dart';
import 'package:raajjepro/features/my_services/presentation/widgets/service_card.dart';
import 'package:raajjepro/features/notifications/presentation/push_denied_reminder.dart';
import 'package:raajjepro/shared/shared.dart';

/// **My Services** (`My Services.dc.html`) — §Phase 10, the provider's
/// workspace and the screen §Phase 6's role switcher has been pointing at
/// since it was built.
///
/// ## What this screen is responsible for
///
/// Everything a provider can do to a listing that is not *editing* it: see
/// how many are live, put one in front of customers or take it back, open the
/// wizard on one, remove one, and reach the two surfaces that hang off a
/// listing rather than sitting inside it — §Phase 9a's availability and
/// calendar.
///
/// ## Three things it deliberately does not do
///
///  * **It never re-fetches to show the result of an action.** §Phase 10's
///    Done-when is "every context-menu action performs a real mutation with
///    no manual refresh", so each mutation adopts the listing the server
///    hands back. The one refresh that does happen is on returning from the
///    wizard, which can have changed anything.
///  * **It renders no rating and no conduct metric.** §1f's numbers are the
///    provider's before they are anyone's, and `My Performance.dc.html` is
///    where they live; a star here would have to come from a `Review` that
///    §Phase 11 has not built.
///  * **It carries no `acceptingNewCustomers` toggle.** The artboard draws
///    none and §Phase 10's bullets ask for none; §1b's pause consequence is
///    owed where the toggle actually renders beside a live subscription,
///    which is §Phase 10a's billing screen (ledger **P8A-4**).
class MyServicesScreen extends ConsumerStatefulWidget {
  const MyServicesScreen({super.key});

  static const routeName = AppRoutes.providerDashboard;

  @override
  ConsumerState<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends ConsumerState<MyServicesScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(myServicesControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.brand(
            surface: true,
            actions: const [
              // Inert, as it is on Explore: §Phase 19 owes the destination.
              AppHeaderAction(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                onTap: null,
              ),
            ],
            trailingSlot: _AccountAvatar(
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
            ),
          ),
          Expanded(
            child: switch (state) {
              AsyncLoading() => const _DashboardSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load your services',
                  body: error is ApiNetworkException
                      ? 'Your listings are safe — we just couldn’t reach '
                            'them. Check your connection and try again.'
                      : 'Your listings are safe — something went wrong '
                            'fetching them. Try again.',
                  onRetry: () =>
                      ref.read(myServicesControllerProvider.notifier).reload(),
                ),
              ),
              AsyncData(:final value) => _Dashboard(state: value),
            },
          ),
          AnimatedBottomNav(
            items: const [
              AppNavItem(
                icon: Icons.calendar_today_outlined,
                label: 'Calendar',
              ),
              AppNavItem(icon: Icons.work_outline_rounded, label: 'Services'),
              AppNavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Messages',
              ),
              AppNavItem(icon: Icons.credit_card_outlined, label: 'Billing'),
              AppNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
            ],
            currentIndex: 1,
            onSelected: (index) => _onTabSelected(context, index),
          ),
        ],
      ),
    );
  }

  /// The provider tab set (`BottomNav.dc.html` → `provider`). There is no tab
  /// shell yet — §Phase 16 owns it — so a tab is a plain push, exactly as
  /// Profile's and Explore's are.
  static void _onTabSelected(BuildContext context, int index) {
    if (index == 1) return; // already here
    final route = switch (index) {
      0 => AppRoutes.providerCalendar,
      3 => AppRoutes.providerBilling,
      4 => AppRoutes.profile,
      _ => null,
    };
    if (route != null) {
      Navigator.of(context).pushNamed(route);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const UnbuiltScreen(title: 'Messages', owedBy: 'Phase 18'),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.state});

  final MyServicesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(myServicesViewProvider);
    final now = ref.watch(clockProvider)();
    final visible = state.where(view.filter);
    final capLabel = _capLabel(state);

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const PushDeniedReminder(),
        _Heading(state: state),
        const SizedBox(height: AppSpacing.lg),
        _Stats(state: state),
        if (!state.hasPublished && state.hasDrafts) ...[
          const SizedBox(height: AppSpacing.md),
          const NoticeBanner(
            message:
                'Nothing live yet — you don’t appear in search until you '
                'publish a service. Your draft is saved and ready to finish.',
            icon: Icons.info_outline_rounded,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        ..._workspaceRows(context, ref, state),
        const SizedBox(height: AppSpacing.lg),
        if (state.listings.isNotEmpty) _FilterRow(view: view),
        if (state.listings.isEmpty)
          _NoServicesYet(onCreate: () => _openWizard(context, ref))
        else if (visible.isEmpty)
          _NothingInFilter(
            filter: view.filter,
            onCreate: () => _openWizard(context, ref),
          )
        else ...[
          const SizedBox(height: AppSpacing.md),
          if (view.layout == ServiceLayout.list)
            for (final listing in visible) ...[
              ServiceCard(
                listing: listing,
                category: state.categoryOf(listing),
                now: now,
                capLabel: capLabel,
                onFinishDraft: () =>
                    _openWizard(context, ref, listing: listing),
                onMenu: () => _openMenu(context, ref, listing),
                onSetLive: (live) => _setLive(context, ref, listing, live),
                onUpgrade: () =>
                    Navigator.of(context).pushNamed(AppRoutes.providerBilling),
                onKeepVisible: () => _keepVisible(context, ref, listing),
              ),
              const SizedBox(height: AppSpacing.md),
            ]
          else
            _Grid(
              listings: visible,
              onMenu: (listing) => _openMenu(context, ref, listing),
            ),
          const SizedBox(height: AppSpacing.md),
          _AddAnother(onCreate: () => _openWizard(context, ref)),
        ],
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }

  /// "1 live service" / "3 live services". Null where the entitlement has no
  /// cap at all — a premium provider never sees the over-cap card, and a
  /// sentence naming their limit would describe one they do not have.
  static String? _capLabel(MyServicesState state) {
    final cap = state.cap.activeListingCap;
    if (cap == null) return null;
    return cap == 1 ? '1 live service' : '$cap live services';
  }

  /// The three rows that hang off the workspace rather than off one listing.
  static List<Widget> _workspaceRows(
    BuildContext context,
    WidgetRef ref,
    MyServicesState state,
  ) {
    final slotListings = state.slotListings;
    return [
      // §Phase 10's "slot management entry point (Phase 9a)". Absent, not
      // disabled, where the provider has no `slot` listing: §Phase 9a's screen
      // is per listing and a request-based one has no grid for it to draw.
      if (slotListings.isNotEmpty) ...[
        AppCard.row(
          leading: const _RowIcon(icon: Icons.schedule_rounded),
          title: 'Availability & time slots',
          subtitle: slotListings.length == 1
              ? slotListings.single.name ?? 'Your bookable times'
              : 'Bookable times for ${slotListings.length} services',
          onTap: () => _openAvailability(context, ref, slotListings),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      AppCard.row(
        leading: const _RowIcon(icon: Icons.calendar_month_outlined),
        title: 'My Calendar',
        subtitle: 'Every commitment across your services',
        onTap: () =>
            Navigator.of(context).pushNamed(AppRoutes.providerCalendar),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppCard.row(
        leading: const _RowIcon(icon: Icons.verified_user_outlined),
        title: 'Verification',
        subtitle: 'Your badge and the checks behind it',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            // §1e: "the full evidence checklist, rejection-reason taxonomy
            // and resubmission path are built in Phase 23".
            builder: (_) =>
                const UnbuiltScreen(title: 'Verification', owedBy: 'Phase 23'),
          ),
        ),
      ),
    ];
  }

  /// One `slot` listing goes straight in; several open a picker first.
  /// §Phase 9a's screen takes a `listingId` because availability is per
  /// listing — "a provider with a two-hour clean and a one-hour clean
  /// publishes a different grid for each" — so there is no such thing as
  /// opening it for the account.
  static Future<void> _openAvailability(
    BuildContext context,
    WidgetRef ref,
    List<ServiceListing> slotListings,
  ) async {
    var target = slotListings.first;
    if (slotListings.length > 1) {
      final chosen = await showAppBottomSheet<ServiceListing>(
        context: context,
        builder: (sheetContext) => AppBottomSheet(
          title: 'Which service?',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final listing in slotListings)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.sm,
                  ),
                  child: AppCard.row(
                    leading: const _RowIcon(icon: Icons.schedule_rounded),
                    title: listing.name ?? 'Untitled service',
                    subtitle: 'Weekly hours and the times they publish',
                    onTap: () => Navigator.of(sheetContext).pop(listing),
                  ),
                ),
            ],
          ),
        ),
      );
      if (chosen == null || !context.mounted) return;
      target = chosen;
    }
    await Navigator.of(context).pushNamed(
      AppRoutes.providerAvailability,
      arguments: <String, dynamic>{
        'listingId': target.id,
        'serviceName': target.name,
      },
    );
    // A rule saved in there can publish or withdraw times, which changes
    // nothing this screen shows — but a listing deleted from the wizard
    // reached through it would. Cheap, and never wrong.
    await ref.read(myServicesControllerProvider.notifier).refreshQuietly();
  }

  /// The wizard — on a fresh draft with no arguments, or resumed on this
  /// listing with its id (§Phase 9). Anything can have changed by the time it
  /// comes back, so this is the one place the dashboard re-reads.
  static Future<void> _openWizard(
    BuildContext context,
    WidgetRef ref, {
    ServiceListing? listing,
  }) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.createService,
      arguments: listing == null
          ? null
          : <String, dynamic>{'listingId': listing.id},
    );
    await ref.read(myServicesControllerProvider.notifier).refreshQuietly();
  }

  static Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    ServiceListing listing,
  ) async {
    final action = await showServiceActionsSheet(
      context: context,
      listing: listing,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case ServiceMenuAction.edit:
        await _openWizard(context, ref, listing: listing);
      case ServiceMenuAction.viewAsCustomer:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            // §Phase 12 owns the Service Preview, and `/v1/listings/:id` is
            // deliberately unclaimed until it defines the public shape.
            builder: (_) => const UnbuiltScreen(
              title: 'Service preview',
              owedBy: 'Phase 12',
            ),
          ),
        );
      case ServiceMenuAction.pause:
        await _setLive(context, ref, listing, false);
      case ServiceMenuAction.resume:
        await _setLive(context, ref, listing, true);
      case ServiceMenuAction.delete:
        await _remove(context, ref, listing);
    }
  }

  /// §1b's override. The server sets a pin and re-reconciles, so the message
  /// names what changed on both sides — a provider who is told only that this
  /// one is live will go looking for the other.
  static Future<void> _keepVisible(
    BuildContext context,
    WidgetRef ref,
    ServiceListing listing,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(myServicesControllerProvider.notifier)
        .keepVisible(listing);
    if (error == null) AppHaptics.commit();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'This one is live now — the other is hidden while you are over '
                  'your plan’s limit, and comes back when you upgrade.',
        ),
      ),
    );
  }

  static Future<void> _setLive(
    BuildContext context,
    WidgetRef ref,
    ServiceListing listing,
    bool live,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(myServicesControllerProvider.notifier)
        .setLive(listing, live: live);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (live
                  ? 'Live — customers can find it again.'
                  : 'Paused — hidden from customers until you switch it '
                        'back.'),
        ),
      ),
    );
  }

  static Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ServiceListing listing,
  ) async {
    final confirmed = await confirmServiceRemoval(
      context: context,
      listing: listing,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(myServicesControllerProvider.notifier)
        .remove(listing);
    if (error == null) {
      // The one action here that cannot be quietly undone from this screen.
      AppHaptics.commit();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'Removed from your services — history and reviews stay in your '
                  'account.',
        ),
      ),
    );
  }
}

class _Heading extends ConsumerWidget {
  const _Heading({required this.state});

  final MyServicesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final colors = context.colors;
    final auth = ref.watch(authControllerProvider);
    final account = auth is AuthSignedIn ? auth.user : null;
    final name = state.provider.businessName ?? account?.fullName ?? '';
    final tier = state.provider.verificationTier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('My Services', style: type.screenTitle),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppButton.primary(
              label: 'New Service',
              icon: Icons.add_rounded,
              size: AppButtonSize.compact,
              onPressed: () => _Dashboard._openWizard(context, ref),
            ),
          ],
        ),
        if (name.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            name,
            style: type.bodyStrong.copyWith(color: colors.textTertiary),
          ),
        ],
        // §1e, and §Phase 10's own bullet: the badge reflects
        // `verificationTier` alone. `none` renders nothing at all — absence
        // is the signal — so the sentence explaining what the badge means
        // goes with it rather than standing on its own.
        if (tier != VerificationTier.none) ...[
          const SizedBox(height: AppSpacing.sm),
          VerificationBadge(tier: tier, size: VerificationBadgeSize.full),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your badge reflects verification checks, not payment — it stays '
            'with you even if a subscription lapses.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.state});

  final MyServicesState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StatMiniCardRow(
      children: [
        StatMiniCard(
          icon: Icons.check_circle_outline_rounded,
          // Deliberately "Live" rather than the artboard's "Published": the
          // number under it counts published **and** `active` listings, and
          // the filter pills directly below use "Published" for the other
          // axis. One word doing both jobs on one screen is how a provider
          // comes to believe a hidden listing is reaching customers.
          label: 'Live',
          value: '${state.liveCount}',
          iconColor: colors.successText,
          iconTint: colors.successTint,
        ),
        StatMiniCard(
          icon: Icons.calendar_today_outlined,
          label: 'Bookings',
          value: state.totalBookings?.toString(),
          iconColor: colors.accentText,
          iconTint: colors.accentTint,
        ),
        StatMiniCard(
          icon: Icons.visibility_outlined,
          label: 'Views',
          value: state.totalViews?.toString(),
          iconColor: colors.accentText,
          iconTint: colors.accentTint,
        ),
      ],
    );
  }
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.view});

  final MyServicesView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(myServicesViewProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final filter in ServiceFilter.values)
                AppChip.filter(
                  label: filter.label,
                  selected: view.filter == filter,
                  onTap: () => controller.filter(filter),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _LayoutToggle(layout: view.layout, onChanged: controller.layout),
      ],
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.layout, required this.onChanged});

  final ServiceLayout layout;
  final ValueChanged<ServiceLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LayoutButton(
            icon: Icons.view_list_rounded,
            label: 'List view',
            selected: layout == ServiceLayout.list,
            onTap: () => onChanged(ServiceLayout.list),
          ),
          _LayoutButton(
            icon: Icons.grid_view_rounded,
            label: 'Grid view',
            selected: layout == ServiceLayout.grid,
            onTap: () => onChanged(ServiceLayout.grid),
          ),
        ],
      ),
    );
  }
}

class _LayoutButton extends StatelessWidget {
  const _LayoutButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      toggled: selected,
      semanticLabel: label,
      focusRadius: AppRadius.sm,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.accentTint : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          size: AppSizes.iconMd,
          color: selected ? colors.accentText : colors.textSecondary,
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.listings, required this.onMenu});

  final List<ServiceListing> listings;
  final ValueChanged<ServiceListing> onMenu;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      // Taller than it is wide: the cover is fixed and the name below it can
      // run to two lines at large text.
      childAspectRatio: 0.72,
      children: [
        for (final listing in listings)
          ServiceGridCard(listing: listing, onMenu: () => onMenu(listing)),
      ],
    );
  }
}

/// A provider with no listings at all — the state onboarding hands off into
/// if the wizard was abandoned before the first draft was saved.
class _NoServicesYet extends StatelessWidget {
  const _NoServicesYet({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.work_outline_rounded,
      title: 'No services yet',
      body:
          'Customers find you through a service. Create your first one — you '
          'can save it as a draft and finish later.',
      actionLabel: 'Create service',
      onAction: onCreate,
    );
  }
}

class _NothingInFilter extends StatelessWidget {
  const _NothingInFilter({required this.filter, required this.onCreate});

  final ServiceFilter filter;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final published = filter == ServiceFilter.published;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.md),
      child: EmptyState(
        icon: Icons.search_rounded,
        title: published ? 'Nothing published yet' : 'No drafts',
        body: published
            ? 'Customers only find services that are live. Publish your draft '
                  'to appear in search.'
            : 'Everything you’ve made is published. Start a new service any '
                  'time.',
        actionLabel: published ? 'Finish & publish' : 'New service',
        onAction: onCreate,
      ),
    );
  }
}

class _AddAnother extends StatelessWidget {
  const _AddAnother({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Pressable(
      onTap: onCreate,
      semanticLabel: 'Add another service',
      focusRadius: AppRadius.panel,
      // The same treatment the wizard's empty cover slot uses: an accent
      // border on a muted fill, which reads as somewhere to put something
      // rather than as a card that failed to load.
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.pressed ? colors.accentTint : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(
            color: colors.accentBorderPressed,
            width: AppSizes.inputStroke,
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            children: [
              Container(
                width: AppSizes.iconDisc,
                height: AppSizes.iconDisc,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accentTint,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: colors.accentText,
                  size: AppSizes.iconLg,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Add another service', style: type.cardTitle),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Publish a new listing to reach more customers.',
                style: type.secondary.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: AppSizes.iconDisc,
      height: AppSizes.iconDisc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.compact),
      ),
      child: Icon(icon, color: colors.accentText, size: AppSizes.iconLg),
    );
  }
}

class _AccountAvatar extends ConsumerWidget {
  const _AccountAvatar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is AuthSignedIn ? auth.user.fullName : null;
    // A real control gets `Pressable`'s 48 dp floor around the 36 dp disc,
    // for the reason Explore's header records: an `OverflowBox` lays the
    // child out larger but hit-tests at the parent's size.
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Your profile',
      focusRadius: AppRadius.pill,
      builder: (context, s) =>
          AppAvatar(name: name ?? '', size: AppSizes.avatarMedium),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView(
        padding: AppSpacing.screenInsets,
        children: const [
          SkeletonBox.line(width: 180, height: 26),
          SizedBox(height: AppSpacing.xl),
          SkeletonRow(),
          SizedBox(height: AppSpacing.md),
          SkeletonRow(),
          SizedBox(height: AppSpacing.md),
          SkeletonRow(),
        ],
      ),
    );
  }
}
