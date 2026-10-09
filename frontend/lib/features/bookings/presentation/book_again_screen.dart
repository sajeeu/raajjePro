import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/data/repeat_models.dart';
import 'package:raajjepro/features/bookings/presentation/book_slot_screen.dart';
import 'package:raajjepro/features/bookings/presentation/request_time_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// What [BookAgainScreen] is pushed with: the completed booking to repeat.
class BookAgainArgs {
  const BookAgainArgs({required this.bookingId});

  factory BookAgainArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return BookAgainArgs(bookingId: map['bookingId'] as String? ?? '');
  }

  final String bookingId;
}

/// **Book again** — `Book Again.dc.html`, §Phase 17 frontend item 13 and
/// §1h's "a repeat booking is genuinely one screen".
///
/// ## Routed by the listing's mode now, not the old booking's
///
/// "Pre-fills a new booking request against the same provider and listing,
/// routed by that listing's **current** `bookingMode`." The server answers
/// which mode that is; the CTA is "Pick a time" or "Request a time"
/// accordingly, and where the provider switched since last time the screen
/// says so rather than surprising the customer with a different flow.
///
/// ## A prefill, never a booking
///
/// Nothing here sends anything. The CTA opens the ordinary booking screen with
/// the address and notes filled in, so every rule of creation — the email
/// gate, the paused toggle, the dispatch-fee block — applies exactly as it
/// does to a first booking.
class BookAgainScreen extends ConsumerWidget {
  const BookAgainScreen({required this.args, super.key});

  static const routeName = '/bookings/book-again';

  final BookAgainArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefill = ref.watch(bookAgainProvider(args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Book again',
            backLabel: 'Back to booking',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (prefill) {
              AsyncLoading() => const _BookAgainSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load this',
                  body: error is ApiNetworkException
                      ? 'Your connection may have dropped. Your saved details '
                            'are safe. Try again.'
                      : 'Something went wrong fetching it. Your saved details '
                            'are safe. Try again.',
                  onRetry: () =>
                      ref.invalidate(bookAgainProvider(args.bookingId)),
                ),
              ),
              AsyncData(:final value) when !value.available => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState(
                  icon: Icons.search_rounded,
                  title: 'This service is no longer offered',
                  body:
                      '${value.providerName} has taken '
                      '${value.listingName ?? 'this service'} off RaajjePro. '
                      'Your past booking and its record stay in place, and '
                      'your saved details stay yours.',
                  actionLabel: 'Find someone similar',
                  onAction: () =>
                      Navigator.of(context).pushNamed(AppRoutes.explore),
                ),
              ),
              AsyncData(:final value) => _BookAgainBody(prefill: value),
            },
          ),
        ],
      ),
    );
  }
}

class _BookAgainBody extends StatelessWidget {
  const _BookAgainBody({required this.prefill});

  final BookAgain prefill;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isRequest = prefill.bookingMode == BookingKind.request;
    final first = _firstName(prefill.providerName);
    final price = prefill.priceLaari;
    final service = [
      prefill.listingName ?? 'This service',
      if (price != null) mvr(price),
    ].join(' · ');
    final lastDone = prefill.lastDoneAt;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screenInsets,
            children: fadeUpAll([
              if (lastDone != null)
                Text(
                  '${prefill.listingName ?? 'This service'} · last done '
                  '${dayAndMonth(lastDone)}',
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AppAvatar(
                    name: prefill.providerName,
                    size: AppSizes.avatarMedium,
                  ),
                  const SizedBox(width: AppSpacing.sm2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(prefill.providerName, style: type.bodyStrong),
                            VerificationBadge(
                              tier: prefill.providerVerificationTier,
                            ),
                          ],
                        ),
                        Text(
                          service,
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Everything is carried over', style: type.bodyStrong),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'A repeat booking is one confirmation — not a re-entry '
                      'of what RaajjePro already knows.',
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _CarriedRow(label: 'Service', value: service),
                    _CarriedRow(label: 'Address', value: prefill.addressLine),
                    _CarriedRow(
                      label: 'Preferred window',
                      value: prefill.preferredWindowLabel,
                    ),
                    _CarriedRow(
                      label: 'Standing notes',
                      value: prefill.standingInstructions,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton.secondary(
                      label: 'Change something',
                      expand: true,
                      onPressed: () => _continue(context),
                    ),
                  ],
                ),
              ),
              if (prefill.modeChanged) ...[
                const SizedBox(height: AppSpacing.md),
                NoticeBanner(
                  icon: Icons.info_outline_rounded,
                  message: isRequest
                      ? 'Since your last booking, $first switched from open '
                            'slots to requests — $first now confirms each '
                            'time.'
                      : 'Since your last booking, $first switched from '
                            'requests to open slots — you pick from the times '
                            '$first publishes.',
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            children: [
              AppButton.primary(
                label: isRequest ? 'Request a time' : 'Pick a time',
                expand: true,
                onPressed: () => _continue(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isRequest
                    ? 'Your details go with the request — $first confirms the '
                          'time.'
                    : '$first still has to accept — picking a slot sends '
                          'the request.',
                style: type.caption.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Into the ordinary booking screen for the listing's mode, filled in.
  void _continue(BuildContext context) {
    final notes = prefill.carriedNotes;
    final args = <String, dynamic>{
      'listingId': prefill.listingId,
      'serviceName': ?prefill.listingName,
      if (notes.isNotEmpty) 'jobNotes': notes,
      'addressDetail': ?prefill.addressDetail,
      'islandId': ?prefill.islandId,
    };
    Navigator.of(context).pushNamed(
      prefill.bookingMode == BookingKind.request
          ? RequestTimeScreen.routeName
          : BookSlotScreen.routeName,
      arguments: {...args, 'providerName': prefill.providerName},
    );
  }
}

class _CarriedRow extends StatelessWidget {
  const _CarriedRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final shown = value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              shown == null || shown.trim().isEmpty ? 'Not set' : shown,
              style: shown == null || shown.trim().isEmpty
                  ? type.secondary.copyWith(color: colors.textTertiary)
                  : type.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookAgainSkeleton extends StatelessWidget {
  const _BookAgainSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: const [
      SizedBox(height: AppSpacing.md),
      SkeletonLoader(
        child: Column(
          children: [
            SkeletonBox(height: 60),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 220),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 54),
          ],
        ),
      ),
    ],
  );
}

String _firstName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'The provider';
  return trimmed.split(RegExp(r'\s+')).first;
}
