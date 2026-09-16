import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **My Bookings** (`My Bookings.dc.html`) — the customer's and the provider's
/// list of everything they have booked or been booked for.
///
/// **The pills filter what is loaded; they never re-fetch.** §Phase 10's
/// dashboard established that, and the reason is the count above the list: a
/// pill that re-queried would leave "3 bookings" sitting over a list of one.
///
/// **The role switch is a second fetch, not a filter**, because it is a
/// different question — the server scopes on it and a provider's own bookings
/// as a customer are genuinely different rows.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key, this.initialFilter});

  static const routeName = '/bookings';

  /// Which pill to open on. §Phase 6's Profile draws four booking tiles whose
  /// whole point (Round 48 §2) is that they are four destinations rather than
  /// four labels for one — so the tile that was tapped selects the pill, and
  /// this slice is what finally gives them somewhere to land.
  final BookingFilter? initialFilter;

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initialFilter;
    if (initial != null) {
      // After the first frame: the notifier is read, not watched, and writing
      // to it during a build is what `setState() during build` is about.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(bookingsViewProvider.notifier).setFilter(initial);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final view = ref.watch(bookingsViewProvider);
    final bookings = ref.watch(bookingsListProvider(view.role));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Your bookings',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (bookings) {
              AsyncLoading() => const _BookingsSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load your bookings',
                  body: error is ApiNetworkException
                      ? 'Nothing has changed — we just couldn’t reach them. '
                            'Check your connection and try again.'
                      : 'Nothing has changed — something went wrong fetching '
                            'them. Try again.',
                  onRetry: () =>
                      ref.invalidate(bookingsListProvider(view.role)),
                ),
              ),
              AsyncData(:final value) => _BookingsBody(
                bookings: value,
                view: view,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _BookingsBody extends ConsumerWidget {
  const _BookingsBody({required this.bookings, required this.view});

  final List<Booking> bookings;
  final BookingsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;

    // A genuinely-empty account is a different state from a pill with nothing
    // under it, and the two say different things (screen-state completeness).
    if (bookings.isEmpty) {
      return Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: Icons.event_note_outlined,
          title: view.role == BookingRole.customer
              ? 'No bookings yet'
              : 'No one has booked you yet',
          body: view.role == BookingRole.customer
              ? 'When you book a service it appears here, with the whole '
                    'record of what was agreed.'
              : 'A request lands here the moment a customer picks one of your '
                    'times. You have 24 hours to answer it.',
        ),
      );
    }

    final filtered = bookings
        .where(view.filter.matches)
        .toList(growable: false);
    final (emptyTitle, emptyBody) = view.filter.emptyCopy;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  bookings.length == 1
                      ? '1 booking'
                      : '${bookings.length} bookings',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              _RoleChips(role: view.role),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm2),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.xl,
            ),
            children: [
              for (final filter in BookingFilter.values) ...[
                AppChip.filter(
                  label: filter.label,
                  selected: filter == view.filter,
                  onTap: () =>
                      ref.read(bookingsViewProvider.notifier).setFilter(filter),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Padding(
                  padding: AppSpacing.screenInsets,
                  child: EmptyState(
                    icon: Icons.filter_list_off_outlined,
                    title: emptyTitle,
                    body: emptyBody,
                  ),
                )
              : ListView.separated(
                  padding: AppSpacing.screenInsets,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final booking = filtered[index];
                    return FadeUp(
                      index: index,
                      child: BookingRowCard(
                        booking: booking,
                        viewerIsCustomer: view.role == BookingRole.customer,
                        onTap: () => Navigator.of(context).pushNamed(
                          BookingDetailScreen.routeName,
                          arguments: {'bookingId': booking.id},
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Which side of their bookings the user is reading.
///
/// Two chips, not a `Switch` — and the name matters: a class called
/// `_RoleSwitch` in a file that also calls `pushNamed` trips
/// `no_booking_notification_toggle_test`'s grep for a notification toggle.
/// The guard is right and the name was wrong; these were never a switch.
///
/// Rendered for everyone: a customer who has never provided anything sees an
/// empty provider list with copy that explains what would put something in it,
/// which is more useful than hiding the control and leaving a provider
/// wondering where their jobs are.
class _RoleChips extends ConsumerWidget {
  const _RoleChips({required this.role});

  final BookingRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in BookingRole.values) ...[
          AppChip.filter(
            label: option == BookingRole.customer
                ? 'As customer'
                : 'As provider',
            selected: option == role,
            onTap: () =>
                ref.read(bookingsViewProvider.notifier).setRole(option),
          ),
          if (option != BookingRole.values.last)
            const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

/// The skeleton is the populated layout's shape — three cards, not a spinner.
class _BookingsSkeleton extends StatelessWidget {
  const _BookingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.screenInsets,
      children: [
        const SizedBox(height: AppSpacing.md),
        SkeletonLoader.rows(),
      ],
    );
  }
}
