import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The component gallery (plan §Phase 1 → "Component gallery route
/// rendering everything with sample data"). Every shared widget in every
/// state, with the three verification switches the phase's Done-when names:
/// forced RTL, 200% text, reduced motion. `test/features/gallery/` pumps this
/// screen under each and asserts no overflow, no missing label, no tap
/// target under 48 dp.
///
/// Sample data is real product data — twelve categories as seeded, tier copy
/// verbatim, `Pick a time` / `Request a time` — so the gallery is also a
/// place to read the rules.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  static const routeName = '/gallery';

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

/// The gallery's three verification switches, applied as an ambient wrapper.
/// Held in a value object so a route pushed from the gallery (the bottom
/// sheet) can re-apply them above the root navigator, where the gallery's own
/// wrappers do not reach.
@immutable
class GalleryOverrides {
  const GalleryOverrides({
    this.rtl = false,
    this.bigText = false,
    this.reducedMotion = false,
  });

  final bool rtl;
  final bool bigText;
  final bool reducedMotion;

  Widget wrap(BuildContext context, Widget child) {
    final base = MediaQuery.of(context);
    return MediaQuery(
      data: base.copyWith(
        textScaler: bigText ? const TextScaler.linear(2) : base.textScaler,
        disableAnimations: reducedMotion || base.disableAnimations,
      ),
      child: Directionality(
        textDirection: rtl
            ? TextDirection.rtl
            : TextDirection.ltr, // rtl-ok: the gallery's own switch
        child: child,
      ),
    );
  }
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _rtl = false;
  bool _bigText = false;
  bool _reducedMotion = false;

  GalleryOverrides get _overrides => GalleryOverrides(
    rtl: _rtl,
    bigText: _bigText,
    reducedMotion: _reducedMotion,
  );

  @override
  Widget build(BuildContext context) {
    return _overrides.wrap(
      context,
      Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              AppHeader.page(
                title: 'Components',
                onBack: Navigator.of(context).canPop()
                    ? () => Navigator.of(context).pop()
                    : null,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.screen,
                    AppSpacing.sm,
                    AppSpacing.screen,
                    AppSpacing.xxxl,
                  ),
                  children: [
                    _controls(),
                    const SizedBox(height: AppSpacing.xxl),
                    const _TokensSection(),
                    const _ButtonsSection(),
                    const _InputsSection(),
                    const _ToggleSection(),
                    const _ChipsSection(),
                    const _CardsSection(),
                    const _VerificationSection(),
                    const _StatusSection(),
                    const _StatsSection(),
                    const _RatingSection(),
                    const _AvatarSection(),
                    const _HeaderSection(),
                    const _NavSection(),
                    const _SaveHeartSection(),
                    const _StatesSection(),
                    _SheetSection(overrides: _overrides),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: 0,
      children: [
        AppChip.filter(
          label: 'RTL',
          selected: _rtl,
          onTap: () => setState(() => _rtl = !_rtl),
          icon: Icons.format_textdirection_r_to_l,
        ),
        AppChip.filter(
          label: '200% text',
          selected: _bigText,
          onTap: () => setState(() => _bigText = !_bigText),
          icon: Icons.text_increase,
        ),
        AppChip.filter(
          label: 'Reduced motion',
          selected: _reducedMotion,
          onTap: () => setState(() => _reducedMotion = !_reducedMotion),
          icon: Icons.motion_photos_off_outlined,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scaffolding

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: type.sectionHeading),
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note!, style: type.secondary),
          ],
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

/// A specimen with its state label under it.
class _Specimen extends StatelessWidget {
  const _Specimen(this.caption, {required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: AppSpacing.xs),
          Text(caption.toUpperCase(), style: context.type.overline),
        ],
      ),
    );
  }
}

Widget _panel(BuildContext context, Widget child) => AppCard(child: child);

// ---------------------------------------------------------------------------
// Tokens

class _TokensSection extends StatelessWidget {
  const _TokensSection();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final swatches = <(String, Color)>[
      ('primary', c.primary),
      ('pressed', c.primaryPressed),
      ('ink', c.ink),
      ('secondary', c.textSecondary),
      ('tertiary', c.textTertiary),
      ('placeholder', c.placeholder),
      ('background', c.background),
      ('border', c.border),
      ('accent tint', c.accentTint),
      ('success', c.success),
      ('warning', c.warning),
      ('warning text', c.warningText),
      ('error', c.error),
      ('disabled', c.disabledFill),
    ];
    return _Section(
      title: 'Tokens',
      note: 'Inter, weights 500–800. Every text colour clears WCAG AA on its surface — the test suite checks each pair.',
      children: [
        _Specimen(
          'Colour',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (name, color) in swatches)
                Semantics(
                  label: '$name colour',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: c.border),
                        ),
                        child: const SizedBox.square(dimension: 40),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: t.pillSmall.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _Specimen(
          'Category accents — tint · icon · text',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in CategoryAccents.byToken.entries)
                Semantics(
                  label: '${entry.key.name} accent',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: entry.value.tint,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.sm + 2,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 10, color: entry.value.icon),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            entry.key.name,
                            style: t.pill.copyWith(color: entry.value.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _Specimen(
          'Type',
          child: _panel(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Screen title 25/800', style: t.screenTitle),
                const SizedBox(height: AppSpacing.sm),
                Text('Section heading 17/700', style: t.sectionHeading),
                const SizedBox(height: AppSpacing.sm),
                Text('Card title 15/700', style: t.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Body 14/500 — Discover skilled professionals across Maldives islands.',
                  style: t.body,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('Body strong 14/600', style: t.bodyStrong),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Secondary 12.5/600 — helper and supporting lines',
                  style: t.secondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('Caption 11.5/600', style: t.caption),
                const SizedBox(height: AppSpacing.sm),
                Text('OVERLINE 11/800 +.06EM', style: t.overline),
                const SizedBox(height: AppSpacing.sm),
                Text('MVR 450', style: t.price),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons

class _ButtonsSection extends StatefulWidget {
  const _ButtonsSection();

  @override
  State<_ButtonsSection> createState() => _ButtonsSectionState();
}

class _ButtonsSectionState extends State<_ButtonsSection> {
  bool _loading = false;

  void _noop() {}

  Future<void> _simulate() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Button',
      note: 'Four variants; default, pressed (hold one), disabled and loading. Loading keeps the label.',
      children: [
        _Specimen(
          'Primary · tap to see loading',
          child: Row(
            children: [
              Expanded(
                child: AppButton.primary(
                  label: 'Pick a time',
                  onPressed: _simulate,
                  loading: _loading,
                  expand: true,
                ),
              ),
            ],
          ),
        ),
        const _Specimen(
          'Primary · disabled',
          child: AppButton.primary(label: 'Pick a time', onPressed: null),
        ),
        _Specimen(
          'Secondary · default · disabled · loading',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton.secondary(label: 'Retry', onPressed: _noop),
              const AppButton.secondary(label: 'Retry', onPressed: null),
              AppButton.secondary(
                label: 'Retry',
                onPressed: _noop,
                loading: true,
              ),
            ],
          ),
        ),
        _Specimen(
          'Text · default · disabled',
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              AppButton.text(label: 'See all', onPressed: _noop),
              const AppButton.text(label: 'See all', onPressed: null),
            ],
          ),
        ),
        _Specimen(
          'Destructive · default · disabled',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton.destructive(label: 'Cancel booking', onPressed: _noop),
              const AppButton.destructive(
                label: 'Cancel booking',
                onPressed: null,
              ),
            ],
          ),
        ),
        _Specimen(
          'Compact · with icon',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton.primary(
                label: 'New Service',
                onPressed: _noop,
                size: AppButtonSize.compact,
                icon: Icons.add,
              ),
              AppButton.secondary(
                label: 'Explore services',
                onPressed: _noop,
                size: AppButtonSize.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs

class _InputsSection extends StatefulWidget {
  const _InputsSection();

  @override
  State<_InputsSection> createState() => _InputsSectionState();
}

class _InputsSectionState extends State<_InputsSection> {
  final _filled = TextEditingController(text: 'Aishath Naeema');
  final _error = TextEditingController(text: '7712');
  final _readOnly = TextEditingController(text: 'RJP-2481');
  final _disabled = TextEditingController(text: 'Malé');
  final _counted = TextEditingController(text: 'Two-bedroom apartment');

  @override
  void dispose() {
    for (final c in [_filled, _error, _readOnly, _disabled, _counted]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Text input',
      note: 'Error shows as a message below — never a tooltip.',
      children: [
        _panel(
          context,
          Column(
            children: [
              const AppTextField(
                label: 'Full name',
                hint: 'e.g. Aishath Naeema',
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(label: 'Full name', controller: _filled),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Phone number',
                controller: _error,
                keyboardType: TextInputType.phone,
                errorText: 'Enter a number between 6 and 15 digits, without the country code.',
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Island',
                controller: _disabled,
                enabled: false,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Booking ID',
                controller: _readOnly,
                readOnly: true,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Describe the job',
                controller: _counted,
                maxLength: 120,
                maxLines: 3,
                helper: 'What needs doing, roughly how big it is.',
                prefixIcon: Icons.notes_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle

class _ToggleSection extends StatefulWidget {
  const _ToggleSection();

  @override
  State<_ToggleSection> createState() => _ToggleSectionState();
}

class _ToggleSectionState extends State<_ToggleSection> {
  bool _on = true;
  bool _off = false;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Toggle',
      note: 'On · off · disabled-with-reason. A disabled toggle says why.',
      children: [
        _panel(
          context,
          Column(
            children: [
              AppToggle(
                value: _on,
                onChanged: (v) => setState(() => _on = v),
                label: 'Accepting new customers',
                description: 'Turn off to pause without unpublishing anything.',
              ),
              const Divider(),
              AppToggle(
                value: _off,
                onChanged: (v) => setState(() => _off = v),
                label: 'Callback guarantee',
                description: 'A free return visit if the same problem comes back within 7 days.',
              ),
              const Divider(),
              const AppToggle(
                value: false,
                onChanged: null,
                label: 'Emergency service',
                description: 'Take urgent same-day jobs in this category.',
                disabledReason: 'Electrical emergencies need Gold verification. Yours is Silver.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chips

class _ChipsSection extends StatefulWidget {
  const _ChipsSection();

  @override
  State<_ChipsSection> createState() => _ChipsSectionState();
}

class _ChipsSectionState extends State<_ChipsSection> {
  final _selected = <String>{'Available today'};
  final _islands = <String>['Hulhumalé', 'Dh. Meedhoo'];

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Chip',
      children: [
        _Specimen(
          'Filter — selected inverts to primary',
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final label in ['Near me', 'Available today', 'Cleaning'])
                AppChip.filter(
                  label: label,
                  selected: _selected.contains(label),
                  onTap: () => setState(() {
                    _selected.contains(label)
                        ? _selected.remove(label)
                        : _selected.add(label);
                  }),
                ),
            ],
          ),
        ),
        _Specimen(
          'Input — tap to remove',
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final island in _islands)
                AppChip.input(
                  label: island,
                  onRemove: () => setState(() => _islands.remove(island)),
                ),
              if (_islands.isEmpty)
                AppButton.text(
                  label: 'Put them back',
                  onPressed: () => setState(
                    () => _islands.addAll(['Hulhumalé', 'Dh. Meedhoo']),
                  ),
                ),
            ],
          ),
        ),
        const _Specimen(
          'Static label',
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              AppChip.label(label: 'Cleaning'),
              AppChip.label(
                label: 'Request a time',
                icon: Icons.event_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cards

class _CardsSection extends StatelessWidget {
  const _CardsSection();

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return _Section(
      title: 'Card',
      children: [
        _Specimen(
          'Plain container',
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your badge reflects verification checks, not payment',
                  style: t.cardTitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'It stays with you even if a subscription lapses.',
                  style: t.secondary,
                ),
              ],
            ),
          ),
        ),
        _Specimen(
          'Tappable · selected',
          child: AppCard(
            onTap: () {},
            semanticLabel: 'Bank transfer, selected',
            selected: true,
            child: Row(
              children: [
                Icon(Icons.account_balance_outlined, color: c.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Bank transfer', style: t.cardTitle)),
                Icon(Icons.check_circle_rounded, color: c.primary),
              ],
            ),
          ),
        ),
        _Specimen(
          'Row card with leading icon',
          child: AppCard.row(
            leading: Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: c.textTertiary,
            ),
            title: 'Password',
            subtitle: 'Last changed 3 months ago',
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Verification

class _VerificationSection extends StatelessWidget {
  const _VerificationSection();

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return _Section(
      title: 'Verification badge',
      note: 'Three tiers, each with its own words, and no one-word badge. With no tier the badge is absent, and the provider is still fully listed and bookable.',
      children: [
        _panel(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final tier in [
                VerificationTier.bronze,
                VerificationTier.silver,
                VerificationTier.gold,
              ]) ...[
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    VerificationBadge(tier: tier),
                    VerificationBadge(
                      tier: tier,
                      size: VerificationBadgeSize.full,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                children: [
                  const VerificationBadge(tier: VerificationTier.none),
                  Text(
                    '(absent)',
                    style: t.caption.copyWith(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(
                      'None — nothing renders. Absence is the signal.',
                      style: t.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Status badge',
      note: 'Semantic colour, never colour alone — always with a label.',
      children: [
        _panel(
          context,
          Wrap(
            spacing: AppSpacing.sm + 2,
            runSpacing: AppSpacing.sm + 2,
            children: [for (final s in BadgeStatus.values) StatusBadge(s)],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats

class _StatsSection extends StatelessWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Section(
      title: 'Stat mini card',
      note: 'A metric with no data reads "No data yet", never a zero that reads worse. The row gives up columns as text grows.',
      children: [
        StatMiniCardRow(
          children: [
            const StatMiniCard(
              icon: Icons.visibility_outlined,
              label: 'Views',
              value: '1,284',
            ),
            StatMiniCard(
              icon: Icons.event_available_outlined,
              label: 'Bookings',
              value: '47',
              iconColor: c.successText,
              iconTint: c.successTint,
            ),
            StatMiniCard(
              icon: Icons.schedule_outlined,
              label: 'On time',
              value: null,
              iconColor: c.warningText,
              iconTint: c.warningTint,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rating

class _RatingSection extends StatefulWidget {
  const _RatingSection();

  @override
  State<_RatingSection> createState() => _RatingSectionState();
}

class _RatingSectionState extends State<_RatingSection> {
  int _value = 0;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Rating stars',
      note: 'Numbers only — never an editorial label about the provider.',
      children: [
        const _Specimen(
          'Compact — cards',
          child: RatingStars.compact(rating: 4.6, count: 31),
        ),
        const _Specimen(
          'Row — read-only',
          child: RatingStars.row(rating: 4, count: 24),
        ),
        _Specimen(
          'Input — each star is a 48 dp target',
          child: RatingStars.input(
            value: _value,
            onChanged: (v) => setState(() => _value = v),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar

class _AvatarSection extends StatelessWidget {
  const _AvatarSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Avatar',
      children: [
        _panel(
          context,
          const Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.lg,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              AppAvatar(name: 'Ibrahim Rasheed'),
              AppAvatar(name: 'Mariyam Shifa', tier: VerificationTier.silver),
              AppAvatar(name: 'Ibrahim Rasheed', tier: VerificationTier.gold),
              AppAvatar(name: 'Aishath Naeema', size: AppSizes.avatarMedium),
              AppAvatar(name: 'Ali Waheed', size: AppSizes.avatarSmall),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Header',
      children: [
        _Specimen(
          'Brand — tab root',
          child: AppCard(
            padding: EdgeInsetsDirectional.zero,
            clip: true,
            child: AppHeader.brand(
              surface: true,
              leadingSlot: AppChip.filter(
                label: 'Malé',
                selected: false,
                onTap: () {},
                icon: Icons.location_on_outlined,
              ),
              actions: [
                AppHeaderAction(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  badgeCount: 3,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
        _Specimen(
          'Page — pushed screen',
          child: AppCard(
            padding: EdgeInsetsDirectional.zero,
            clip: true,
            child: AppHeader.page(
              title: 'Booking details',
              surface: true,
              onBack: () {},
              actions: [
                AppHeaderAction(
                  icon: Icons.more_horiz_rounded,
                  label: 'More options',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom nav

class _NavSection extends StatefulWidget {
  const _NavSection();

  @override
  State<_NavSection> createState() => _NavSectionState();
}

class _NavSectionState extends State<_NavSection> {
  int _index = 0;

  static const _items = [
    AppNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    AppNavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: 'Explore',
    ),
    AppNavItem(
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      label: 'Bookings',
    ),
    AppNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Messages',
    ),
    AppNavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Bottom navigation',
      note: 'The active pill slides between tabs. Tap one.',
      children: [
        AppCard(
          padding: EdgeInsetsDirectional.zero,
          clip: true,
          child: AnimatedBottomNav(
            items: _items,
            currentIndex: _index,
            onSelected: (i) => setState(() => _index = i),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Save heart

class _SaveHeartSection extends StatefulWidget {
  const _SaveHeartSection();

  @override
  State<_SaveHeartSection> createState() => _SaveHeartSectionState();
}

class _SaveHeartSectionState extends State<_SaveHeartSection> {
  bool _a = false;
  bool _b = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Section(
      title: 'Save heart',
      children: [
        _panel(
          context,
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: CategoryAccents.byToken[AccentToken.emerald]!.tint,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                  child: SaveHeartToggle(
                    saved: _a,
                    onChanged: (v) => setState(() => _a = v),
                    itemName: 'Emergency Plumbing & Pipe Repair',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              SaveHeartToggle(
                saved: _b,
                onChanged: (v) => setState(() => _b = v),
                style: SaveHeartStyle.flat,
                itemName: 'Home Deep Cleaning',
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  'Overlay on an image · flat in a card body',
                  style: context.type.secondary.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty · error · loading

class _StatesSection extends StatelessWidget {
  const _StatesSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Empty · error · loading',
      note: 'An empty state names what to do next. An error says what failed and offers retry. Loading shimmers in the shape of the real layout.',
      children: [
        _Specimen(
          'Empty',
          child: EmptyState(
            icon: Icons.calendar_today_outlined,
            title: 'No bookings yet',
            body: 'When you book a service it appears here, with its status and chat.',
            actionLabel: 'Explore services',
            onAction: () {},
          ),
        ),
        _Specimen(
          'Error',
          child: EmptyState.error(
            title: "Couldn't load your services",
            body: 'Your listings are safe — we just couldn\'t reach them. Check your connection and try again.',
            onRetry: () {},
          ),
        ),
        _Specimen(
          'Skeleton — generic rows',
          child: SkeletonLoader.rows(count: 2),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.overrides});

  final GalleryOverrides overrides;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Bottom sheet',
      note: '28 dp top radius, drag handle, spring in over 300 ms, out over 200 ms.',
      children: [
        AppButton.secondary(
          label: 'Open a sheet',
          onPressed: () => showAppBottomSheet<void>(
            context: context,
            // The route sits on the root navigator, above the gallery's
            // wrappers, so the switches are re-applied here.
            builder: (ctx) => overrides.wrap(
              ctx,
              Builder(
                builder: (ctx) => AppBottomSheet(
                  title: 'Cancel this booking?',
                  onClose: () => Navigator.of(ctx).pop(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ibrahim will be told straight away, and the time goes back on offer.',
                        style: ctx.type.body,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton.destructive(
                        label: 'Cancel booking',
                        onPressed: () => Navigator.of(ctx).pop(),
                        expand: true,
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      AppButton.text(
                        label: 'Keep it',
                        onPressed: () => Navigator.of(ctx).pop(),
                        expand: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
