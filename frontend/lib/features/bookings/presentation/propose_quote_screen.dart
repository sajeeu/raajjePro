import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Propose a time and price** — `Propose Time and Price.dc.html`, and the
/// provider half of §Phase 17.2.
///
/// ## One action, two things
///
/// §1c: the provider "responds with a proposed concrete date/time **and
/// price**". They are one call and one screen deliberately — a time without a
/// price is not something a customer can accept, and the whole reason request
/// mode exists is that neither is knowable until the provider has read the job.
///
/// ## Sending holds the time
///
/// §1c: "offering a quote creates a provisional reservation on the proposed
/// time, expiring with the quote's approval window. Without this, the provider
/// could sell that time to someone else in the interim and the customer's
/// approval would fail on a constraint violation after they had already agreed
/// a price." The screen says so above the button, because a provider who does
/// not know their calendar just moved will double-book themselves by hand.
///
/// ## Sending opens the chat
///
/// §0.0 item 7: the `booking` thread opens at `quote_offered`, not at
/// `accepted`. The artboard states it to the provider as they send, and so
/// does this screen — it is the difference between landing in a conversation
/// and landing back on a list.
///
/// ## Revising is the same screen
///
/// A quote already offered can be replaced while the customer is deciding,
/// which is what the chat is for. The screen opens on the live quote's own
/// numbers so a revision is an edit rather than a re-entry, and the server
/// moves the hold and restarts the customer's clock.
class ProposeQuoteScreen extends ConsumerStatefulWidget {
  const ProposeQuoteScreen({required this.args, super.key});

  static const routeName = '/bookings/quote';

  final BookingActionArgs args;

  @override
  ConsumerState<ProposeQuoteScreen> createState() => _ProposeQuoteScreenState();
}

class _ProposeQuoteScreenState extends ConsumerState<ProposeQuoteScreen> {
  final _price = TextEditingController();
  final _note = TextEditingController();
  DateTime? _when;
  bool _prefilled = false;
  String? _priceError;

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final booking = ref.watch(bookingDetailProvider(widget.args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Propose a time & price',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: booking.when(
              loading: () => const _Loading(),
              error: (_, _) => _Failed(
                onRetry: () => ref.invalidate(
                  bookingDetailProvider(widget.args.bookingId),
                ),
              ),
              data: _form,
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(Booking booking) {
    final colors = context.colors;
    final type = context.type;
    final action = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final revising = booking.status == BookingStatus.quoteOffered;

    // A revision opens on the numbers already on the table. Done once, and
    // never on a later rebuild, so it cannot overwrite what is being typed.
    if (!_prefilled) {
      _prefilled = true;
      if (revising) {
        _when ??= booking.scheduledFor;
        if (_price.text.isEmpty && booking.quotedAmountLaari != null) {
          _price.text = '${(booking.quotedAmountLaari ?? 0) ~/ 100}';
        }
        if (_note.text.isEmpty) _note.text = booking.quoteNote ?? '';
      }
    }

    final when = _when;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),

        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        // What the customer asked for. §1c step 2's prompt carries "job
        // details and the customer's name only" — the same rule holds here,
        // and there is nothing on this card that could reach them.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${booking.customer.name} asked for',
                style: type.overline.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                booking.preferredWindowText ?? 'No particular time',
                style: type.cardTitle,
              ),
              if ((booking.jobNotes ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  booking.jobNotes ?? '',
                  style: type.body.copyWith(color: colors.textTertiary),
                ),
              ],
              if ((booking.islandDisplayName ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  booking.islandDisplayName ?? '',
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The time you’re offering', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.sm2),
              // The artboard leads with day chips, and so does this — the
              // common answer is "one of the next few days" and it should be
              // one tap. Its **time** chips are sample values with no source:
              // a `request` listing publishes no slots and its category seeds
              // no hours, so four literals here would be invented
              // configuration. The clock is picked instead.
              SizedBox(
                height: AppSizes.touchTarget,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _dayOptions,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, index) {
                    final day = _dayAt(index);
                    return AppChip.filter(
                      label: _dayLabel(day),
                      selected: when != null && _sameDay(when, day),
                      onTap: () {
                        AppHaptics.selection();
                        setState(() => _when = _withDay(day));
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                when == null
                    ? 'Pick the day, then the time you can actually be there.'
                    : bookingWhen(when),
                style: when == null
                    ? type.secondary.copyWith(color: colors.textSecondary)
                    : type.body,
              ),
              const SizedBox(height: AppSpacing.sm2),
              AppButton.secondary(
                label: when == null ? 'Set the time' : 'Change the time',
                expand: true,
                onPressed: _pickClock,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          label: 'Your price',
          controller: _price,
          hint: '0',
          keyboardType: TextInputType.number,
          prefix: const Text('MVR'),
          errorText: _priceError,
          helper:
              'The whole job, in rufiyaa. ${booking.customer.name} accepts '
              'this exact number — once they do, it is the agreed price and '
              'changing it needs an amendment they accept.',
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'e.g. replace joint, reseal line — parts included',
          maxLines: 3,
          maxLength: 2000,
          requirement: FieldRequirement.optional,
          helper: 'What the price covers. This becomes the agreed scope.',
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sending does two things', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.xs),
              Text(
                when == null
                    ? 'It holds that time in your calendar while they decide, '
                          'so nobody else can take it — and it opens the chat '
                          'with ${booking.customer.name} right away.'
                    : 'It holds ${bookingWhen(when)} in your calendar while '
                          'they decide, so nobody else can take it — and it '
                          'opens the chat with ${booking.customer.name} right '
                          'away.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'If they don’t answer in time the quote expires on its own and '
                'the time is released back to you.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        AppButton.primary(
          label: _ctaLabel(revising),
          expand: true,
          loading: action.isWorking,
          onPressed: when == null || action.isWorking
              ? null
              : () => _send(controller, booking),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  String _ctaLabel(bool revising) {
    final laari = _parsePrice();
    final verb = revising ? 'Send revised quote' : 'Send quote';
    if (laari == null || _when == null) return verb;
    return '$verb — ${mvr(laari)}';
  }

  /// Rufiyaa in the field, integer laari on the wire (invariant 7). The
  /// conversion happens once, here, and never as a float.
  int? _parsePrice() {
    final digits = _price.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return null;
    final rufiyaa = int.tryParse(digits);
    if (rufiyaa == null || rufiyaa <= 0) return null;
    return rufiyaa * 100;
  }

  /// How many days the rail offers. Two weeks covers the near-term jobs these
  /// categories actually take; anything further out is a conversation, and the
  /// chat is open by then.
  static const _dayOptions = 14;

  DateTime _dayAt(int index) {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day + index);
  }

  /// `Tomorrow`, or `Wed 2 Sep` — Maldives wall clock, like every other date
  /// in the app.
  String _dayLabel(DateTime day) {
    final today = _dayAt(0);
    if (_sameDay(day, today)) return 'Today';
    if (_sameDay(day, _dayAt(1))) return 'Tomorrow';
    return '${maldivesWeekdayShort(day)} ${maldivesShortDate(day)}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Moves the chosen day while keeping whatever time is already set, so
  /// changing the day does not silently discard the hour.
  DateTime _withDay(DateTime day) {
    final existing = _when;
    return DateTime(
      day.year,
      day.month,
      day.day,
      existing?.hour ?? 9,
      existing?.minute ?? 0,
    );
  }

  Future<void> _pickClock() async {
    final current = _when;
    final time = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      // No day chosen yet: the time alone means tomorrow, which is what a
      // provider setting an hour first is almost always saying.
      final day = current ?? _dayAt(1);
      _when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    });
  }

  Future<void> _send(
    BookingActionsController controller,
    Booking booking,
  ) async {
    final when = _when;
    final laari = _parsePrice();
    if (when == null) return;
    if (laari == null) {
      // Inline, under the field — never a toast (frontend/CLAUDE.md).
      setState(
        () => _priceError =
            'Enter the price you’re offering — ${booking.customer.name} '
            'accepts this exact number.',
      );
      return;
    }
    setState(() => _priceError = null);

    final done = await controller.offerQuote(
      scheduledFor: when,
      amountLaari: laari,
      note: _note.text,
    );
    if (!mounted) return;
    if (done) {
      AppHaptics.commit();
      Navigator.of(context).pop();
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: const [
      SizedBox(height: AppSpacing.md),
      SkeletonLoader(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox.line(width: 200, height: 26),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 110),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 140),
          ],
        ),
      ),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppSpacing.screenInsets,
      child: EmptyState.error(
        title: 'Couldn’t load this request',
        body: 'Nothing was sent. Check your connection and try again.',
        onRetry: onRetry,
      ),
    ),
  );
}
