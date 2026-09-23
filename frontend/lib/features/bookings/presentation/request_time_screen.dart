import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/categories/categories_controller.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// §1c's four quick-pick chips, and **the one place their labels live**.
///
/// The wire value is the server's vocabulary and the label is what a customer
/// reads; the server stores the label it resolves for itself, so these two
/// must agree in wording and neither computes the other's range. The range
/// itself is resolved server-side — a client that worked out what "this
/// weekend" means would be a second answer to the same question.
enum WindowChip {
  tomorrowMorning('tomorrow_morning', 'Tomorrow morning'),
  tomorrowAfternoon('tomorrow_afternoon', 'Tomorrow afternoon'),
  thisWeek('this_week', 'This week'),
  thisWeekend('this_weekend', 'This weekend');

  const WindowChip(this.wire, this.label);

  final String wire;
  final String label;
}

/// What [RequestTimeScreen] is pushed with.
///
/// `categoryId` is optional and is what lets the screen state the real quote
/// windows before anything is sent. Without it the screen says the same thing
/// qualitatively rather than inventing a number — see [_WhatHappensNext].
class RequestTimeArgs {
  const RequestTimeArgs({
    required this.listingId,
    this.serviceName,
    this.providerName,
    this.categoryId,
  });

  factory RequestTimeArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return RequestTimeArgs(
      listingId: map['listingId'] as String? ?? '',
      serviceName: map['serviceName'] as String?,
      providerName: map['providerName'] as String?,
      categoryId: map['categoryId'] as String?,
    );
  }

  final String listingId;
  final String? serviceName;
  final String? providerName;
  final String? categoryId;
}

/// **Requesting a time** — `Request a Time.dc.html`, and the customer half of
/// §Phase 17.2.
///
/// ## A preference, not a slot
///
/// §1c: the customer submits "a preferred date/time window (not an exact slot
/// — 'Tuesday afternoon', 'this week')". The screen says so in those words
/// under the chips, because the difference from `Pick a Time` is the whole
/// point of the mode: nothing here books anything, and the provider comes back
/// with a concrete time and a real price.
///
/// ## The chips lead and the text field follows
///
/// §1c: "the window picker **leads with quick-pick chips** … with free text
/// available underneath for anything more specific. A blank text field as the
/// primary interaction asks more of the customer than most bookings need."
///
/// ## Both clocks are the category's, and neither is computed here
///
/// The screen tells the customer how long the provider has to answer and how
/// long they will then have to accept. Both come from the category off the
/// wire (invariant 13) — never a literal, and never a client-side default.
/// Where the category is not known the copy drops the numbers rather than
/// guessing them.
class RequestTimeScreen extends ConsumerStatefulWidget {
  const RequestTimeScreen({required this.args, super.key});

  static const routeName = '/request';

  final RequestTimeArgs args;

  @override
  ConsumerState<RequestTimeScreen> createState() => _RequestTimeScreenState();
}

class _RequestTimeScreenState extends ConsumerState<RequestTimeScreen> {
  final _windowText = TextEditingController();
  final _notes = TextEditingController();
  final _address = TextEditingController();
  WindowChip? _chip;
  String? _occasion;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The CTA enables on the window alone, so both inputs have to re-render it.
    _windowText.addListener(_onTyped);
  }

  @override
  void dispose() {
    _windowText.removeListener(_onTyped);
    _windowText.dispose();
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  /// The window is the only thing the server insists on, and the screen asks
  /// for exactly that — a chip, or something typed, or both.
  bool get _hasWindow => _chip != null || _windowText.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final auth = ref.watch(authControllerProvider);
    final verified = auth is AuthSignedIn && auth.user.emailVerified;
    final category = _category();

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Request a time',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: ListView(
              padding: AppSpacing.screenInsets,
              children: fadeUpAll([
                const SizedBox(height: AppSpacing.md),

                if (_subtitle() != null) ...[
                  Text(
                    _subtitle() ?? '',
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                if (_error != null) ...[
                  NoticeBanner(message: _error ?? ''),
                  const SizedBox(height: AppSpacing.md),
                ],

                _WhenCard(
                  chip: _chip,
                  controller: _windowText,
                  onChip: (chip) {
                    AppHaptics.selection();
                    setState(() => _chip = _chip == chip ? null : chip);
                  },
                  providerName: widget.args.providerName,
                ),
                const SizedBox(height: AppSpacing.md),

                // Round 25: Photography and Boat Charter only, and only where
                // the category actually seeds them. An empty list renders
                // nothing at all rather than an empty row.
                if ((category?.occasionPresets ?? const []).isNotEmpty) ...[
                  _OccasionCard(
                    presets: category?.occasionPresets ?? const [],
                    selected: _occasion,
                    onTap: (value) {
                      AppHaptics.selection();
                      setState(
                        () => _occasion = _occasion == value ? null : value,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppTextField(
                  label: 'What’s the job?',
                  controller: _notes,
                  hint:
                      'What’s wrong and what needs doing — e.g. steady leak '
                      'under the kitchen sink, cupboard base is wet',
                  maxLines: 4,
                  maxLength: 2000,
                  requirement: FieldRequirement.optional,
                  helper:
                      'This is what the provider quotes from. The more they '
                      'know, the closer the price comes back.',
                ),
                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  label: 'Where',
                  controller: _address,
                  hint: 'House name, floor, street',
                  maxLength: 300,
                  requirement: FieldRequirement.optional,
                  helper:
                      'Anything more precise can go in the chat, which opens '
                      'as soon as the quote arrives.',
                ),
                const SizedBox(height: AppSpacing.md),

                _WhatHappensNext(
                  category: category,
                  providerName: widget.args.providerName,
                ),
                const SizedBox(height: AppSpacing.md),

                if (!verified) ...[
                  _VerifyEmailCard(
                    email: auth is AuthSignedIn ? auth.user.email : '',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppButton.primary(
                  label: _hasWindow ? 'Send request' : 'Add a window to send',
                  expand: true,
                  loading: _sending,
                  onPressed: !_hasWindow || !verified || _sending
                      ? null
                      : _send,
                ),
                const SizedBox(height: AppSpacing.sm2),
                Text(
                  'Nothing is booked and nothing is owed until you accept a '
                  'quote. RaajjePro never handles the money.',
                  style: type.caption.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.n28),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String? _subtitle() {
    final service = widget.args.serviceName;
    final provider = widget.args.providerName;
    if (service == null && provider == null) return null;
    if (service == null) return provider;
    if (provider == null) return service;
    return '$service · $provider';
  }

  /// The category behind this listing, where the caller named one and the
  /// catalogue has loaded. Null is a first-class answer here: the screen
  /// renders without the numbers rather than with invented ones.
  ServiceCategory? _category() {
    final id = widget.args.categoryId;
    if (id == null) return null;
    final categories = ref.watch(categoriesControllerProvider).value;
    if (categories == null) return null;
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final booking = await ref
          .read(bookingApiProvider)
          .createRequestBooking(
            listingId: widget.args.listingId,
            preferredWindowChip: _chip?.wire,
            preferredWindowText: _windowText.text,
            occasion: _occasion,
            jobNotes: _notes.text,
            addressDetail: _address.text,
          );
      ref.invalidate(bookingsListProvider);
      if (!mounted) return;
      AppHaptics.commit();
      // Replace rather than push, as slot creation does: going "back" to a
      // form that has already been sent invites sending it twice.
      await Navigator.of(context).pushReplacementNamed(
        BookingDetailScreen.routeName,
        arguments: {'bookingId': booking.id},
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on ApiNetworkException {
      if (!mounted) return;
      setState(
        () => _error =
            'No connection — nothing was sent. Your details are still here; '
            'try again when you’re back online.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// "When suits you?" — the chips, then the free-text line under them.
class _WhenCard extends StatelessWidget {
  const _WhenCard({
    required this.chip,
    required this.controller,
    required this.onChip,
    required this.providerName,
  });

  final WindowChip? chip;
  final TextEditingController controller;
  final ValueChanged<WindowChip> onChip;
  final String? providerName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final who = providerName ?? 'the provider';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('When suits you?', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.sm2),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final option in WindowChip.values)
                AppChip.filter(
                  label: option.label,
                  selected: chip == option,
                  onTap: () => onChip(option),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Or say exactly when',
            controller: controller,
            hint: 'Thursday after 16:00',
            maxLength: 300,
            requirement: FieldRequirement.optional,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This is a preference, not a slot — $who replies with a concrete '
            'time.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Round 25's occasion chips. Rendered only where the category seeds them.
class _OccasionCard extends StatelessWidget {
  const _OccasionCard({
    required this.presets,
    required this.selected,
    required this.onTap,
  });

  final List<String> presets;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What’s the occasion?', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Optional, and it becomes the booking’s own subtitle — so your '
            'history reads as what you actually hired.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm2),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final preset in presets)
                AppChip.filter(
                  label: preset,
                  selected: selected == preset,
                  onTap: () => onTap(preset),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The artboard's numbered "What happens after you send".
///
/// **The two windows are the category's or they are not stated.** Invariant 13
/// forbids a hardcoded 2 hours or 4 hours anywhere, and a screen that guessed
/// would be promising a customer a deadline the server does not hold.
class _WhatHappensNext extends StatelessWidget {
  const _WhatHappensNext({required this.category, required this.providerName});

  final ServiceCategory? category;
  final String? providerName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final who = providerName ?? 'The provider';
    final quote = _hours(category?.quoteExpiryMinutes);
    final approve = _hours(category?.quoteApprovalMinutes);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What happens after you send', style: type.cardTitle),
          const SizedBox(height: AppSpacing.sm2),
          _Step(
            n: '1',
            text: 'Your request goes to $who — no time or price is fixed yet.',
          ),
          _Step(
            n: '2',
            text: quote == null
                ? '$who replies with a concrete time and a real price, within '
                      'the window their category sets.'
                : '$who has $quote to reply with a concrete time and a real '
                      'price.',
          ),
          _Step(
            n: '3',
            text: approve == null
                ? 'You then get a window to accept that quote. Nothing is '
                      'booked and nothing is owed until you do.'
                : 'You then get $approve to accept that quote. Nothing is '
                      'booked and nothing is owed until you do.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: colors.divider, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Text(
            category == null
                ? 'Both windows are set by the service’s category. Chat opens '
                      'the moment the quote arrives.'
                : 'These windows are set by the ${category?.name} category. '
                      'Chat opens the moment the quote arrives.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Minutes as the sentence reads them. Whole hours where it divides, and
  /// minutes where it does not — 120 is "2 hours", never "120 minutes".
  static String? _hours(int? minutes) {
    if (minutes == null || minutes <= 0) return null;
    if (minutes < 60) return '$minutes minutes';
    if (minutes % 60 != 0) return '$minutes minutes';
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hour' : '$hours hours';
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSizes.stepBullet,
            height: AppSizes.stepBullet,
            decoration: BoxDecoration(
              color: colors.accentTint,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(n, style: type.caption.copyWith(color: colors.primary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: type.secondary.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// §1c's access-control table, stated rather than hidden. The server refuses
/// regardless (invariant 4); this is so the customer is told before they fill
/// the form in rather than after.
class _VerifyEmailCard extends StatelessWidget {
  const _VerifyEmailCard({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verify your email to send this', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Requests, enquiries and messages all need a verified email '
            'address — it is how a provider knows there is a real person '
            'behind a job.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.secondary(
            label: 'Verify email',
            expand: true,
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.verifyEmail,
              arguments: {'email': email, 'purpose': 'verify_email'},
            ),
          ),
        ],
      ),
    );
  }
}
