import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_preview/controller/service_preview_controller.dart';
import 'package:raajjepro/features/service_preview/data/public_listing_models.dart';
import 'package:raajjepro/features/service_preview/presentation/preview_copy.dart';
import 'package:raajjepro/features/service_preview/presentation/preview_sections.dart';
import 'package:raajjepro/shared/shared.dart';

class ServicePreviewArgs {
  const ServicePreviewArgs({required this.listingId});

  /// Built from untyped route arguments so no feature has to import this one
  /// to push it — the shape `VerifyEmailArgs` established.
  factory ServicePreviewArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return ServicePreviewArgs(listingId: map['listingId'] as String? ?? '');
  }

  final String listingId;
}

/// The hero's height in the artboard (`Service Preview.dc.html`, 250). It is a
/// picture's frame rather than a rhythm step, so it is not a spacing token.
const double _heroHeight = 250;

/// **Service Preview** — `Service Preview.dc.html`, the public listing page
/// (§Phase 12).
///
/// ## What it does
///
/// Reads `GET /v1/listings/:id/public` and renders it: a hero with overlay
/// controls, the price and — before the customer taps anything — how they will
/// book it, the provider's identity and badge, the description, the provider's
/// own claims (attributed, never verified), the callback guarantee where the
/// category carries it, questions, reviews, and a sticky footer.
///
/// ## Book Now routes by `bookingMode`
///
/// `slot` → the time picker, `request` → the request form, and — alongside
/// either, never instead — the emergency door where the server says the
/// listing offers it, with its dispatch fee stated up front. A guest is sent to
/// sign in and an unverified user to verify their email first (§1c: booking and
/// messaging require a verified email), but **that is routing, not the rule**:
/// the server refuses an unverified booking on its own (invariant 4).
///
/// ## What is not built here
///
/// Message, Report and Save are drawn where the artboard draws them and land on
/// the phase that owns each (18, 22 and 14) — see [_openUnbuilt]. The artboard
/// is one scrolling page; the plan's "About / Reviews / Provider tabs" are its
/// three groups of sections, in the order the artboard puts them.
class ServicePreviewScreen extends ConsumerStatefulWidget {
  const ServicePreviewScreen({required this.args, super.key});

  static const routeName = AppRoutes.listingPreview;

  final ServicePreviewArgs args;

  @override
  ConsumerState<ServicePreviewScreen> createState() =>
      _ServicePreviewScreenState();
}

class _ServicePreviewScreenState extends ConsumerState<ServicePreviewScreen> {
  int _faqOpen = -1;
  int _imageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(servicePreviewProvider(widget.args.listingId));
    return Scaffold(
      backgroundColor: context.colors.background,
      body: switch (state) {
        AsyncLoading() => const _PreviewSkeleton(),
        AsyncError(:final error) =>
          isListingUnavailable(error)
              ? _Unavailable(onBrowse: _browse)
              : _LoadError(
                  onRetry: () => ref
                      .read(
                        servicePreviewProvider(widget.args.listingId).notifier,
                      )
                      .reload(),
                ),
        AsyncData(:final value) => _Body(
          preview: value,
          imageIndex: _imageIndex,
          faqOpen: _faqOpen,
          onImage: (i) => setState(() => _imageIndex = i),
          onFaq: (i) => setState(() => _faqOpen = _faqOpen == i ? -1 : i),
          onBook: () => _book(value.listing),
          onEmergency: () => _emergency(value.listing),
          onMessage: () => _message(value.listing),
          onEdit: () => _edit(value.listing),
          onReport: _report,
          onProvider: () => Navigator.of(context).pushNamed(
            AppRoutes.providerProfile,
            arguments: <String, dynamic>{
              'providerId': value.listing.provider.id,
            },
          ),
        ),
      },
    );
  }

  // -- Routing -------------------------------------------------------------

  void _browse() => Navigator.of(context).popUntil((route) => route.isFirst);

  /// §1c: booking and messaging need a verified email. This routes to the
  /// screen that fixes it; it is not the check — the server refuses an
  /// unverified request on its own, so a client that skips this is refused
  /// rather than let through.
  bool _signedInAndVerified() {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn) {
      Navigator.of(context).pushNamed(AppRoutes.signIn);
      return false;
    }
    if (!auth.user.emailVerified) {
      Navigator.of(context).pushNamed(
        AppRoutes.verifyEmail,
        arguments: <String, dynamic>{
          'email': auth.user.email,
          'purpose': 'verifyEmail',
        },
      );
      return false;
    }
    return true;
  }

  void _book(PublicListing listing) {
    if (!_signedInAndVerified()) return;
    final providerName = listing.provider.businessName;
    switch (listing.bookingMode) {
      case BookingMode.slot:
        Navigator.of(context).pushNamed(
          AppRoutes.bookSlot,
          arguments: <String, dynamic>{
            'listingId': listing.id,
            'serviceName': listing.name,
          },
        );
      case BookingMode.request:
        Navigator.of(context).pushNamed(
          AppRoutes.requestTime,
          arguments: <String, dynamic>{
            'listingId': listing.id,
            'serviceName': listing.name,
            'providerName': ?providerName,
            'categoryId': listing.category.id,
          },
        );
    }
  }

  /// The ASAP request is raised against a **category and an island**, never a
  /// listing (§1c) — so this carries the category and nothing about who the
  /// customer was looking at.
  void _emergency(PublicListing listing) {
    if (!_signedInAndVerified()) return;
    Navigator.of(context).pushNamed(
      AppRoutes.emergency,
      arguments: <String, dynamic>{
        'categoryId': listing.emergency.categoryId ?? listing.category.id,
      },
    );
  }

  /// §Phase 12: "Message button restored (§1c) — opens the pre-booking enquiry
  /// thread." The thread is §Phase 18's, which is not built, so past the
  /// verification gate this lands on the placeholder that names the phase.
  void _message(PublicListing listing) {
    if (!_signedInAndVerified()) return;
    _openUnbuilt('Messages', 'Phase 18');
  }

  void _report() => _openUnbuilt('Report', 'Phase 22');

  void _edit(PublicListing listing) => Navigator.of(context).pushNamed(
    AppRoutes.createService,
    arguments: <String, dynamic>{'listingId': listing.id},
  );

  /// A control the artboard draws whose destination a later phase owes lands on
  /// [UnbuiltScreen] naming that phase, the way Profile's rows do — a row that
  /// silently did nothing would be indistinguishable from a slow one.
  void _openUnbuilt(String title, String owedBy) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnbuiltScreen(title: title, owedBy: owedBy),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.preview,
    required this.imageIndex,
    required this.faqOpen,
    required this.onImage,
    required this.onFaq,
    required this.onBook,
    required this.onEmergency,
    required this.onMessage,
    required this.onEdit,
    required this.onReport,
    required this.onProvider,
  });

  final ServicePreview preview;
  final int imageIndex;
  final int faqOpen;
  final ValueChanged<int> onImage;
  final ValueChanged<int> onFaq;
  final VoidCallback onBook;
  final VoidCallback onEmergency;
  final VoidCallback onMessage;
  final VoidCallback onEdit;
  final VoidCallback onReport;
  final VoidCallback onProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = preview.listing;
    final now = ref.watch(clockProvider)();
    final providerName = listing.provider.businessName ?? 'The provider';
    final owner = listing.viewerIsOwner;
    final statements = listing.selfDeclared.statements;

    final sections = <Widget>[
      TitleBlock(listing: listing),
      PriceCard(
        listing: listing,
        providerName: providerName,
        onEmergency: onEmergency,
      ),
      ProviderCard(
        listing: listing,
        providerName: providerName,
        now: now,
        onTap: onProvider,
      ),
      AboutCard(listing: listing),
      if (statements.isNotEmpty) SelfDeclaredCard(statements: statements),
      if (listing.callbackGuarantee) const CallbackCard(),
      if (listing.faqs.isNotEmpty)
        FaqCard(faqs: listing.faqs, openIndex: faqOpen, onToggle: onFaq),
      // Messaging yourself is not a thing; the owner sees the page as a
      // customer does, minus the controls that would act on their own listing.
      if (!owner)
        AppButton.secondary(
          label: 'Ask $providerName a question before booking',
          icon: Icons.chat_bubble_outline_rounded,
          expand: true,
          onPressed: onMessage,
        ),
      ReviewsCard(rating: listing.rating, reviews: preview.reviews, now: now),
      if (!owner)
        AppButton.text(
          label: 'Report this listing',
          icon: Icons.flag_outlined,
          expand: true,
          onPressed: onReport,
        ),
    ];

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeUp(
                  child: _Hero(
                    listing: listing,
                    imageIndex: imageIndex,
                    onImage: onImage,
                    onReport: onReport,
                    showReport: !owner,
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.xl,
                    AppSpacing.lg2,
                    AppSpacing.xl,
                    AppSpacing.xxl2,
                  ),
                  child: _SpacedColumn(children: sections),
                ),
              ],
            ),
          ),
        ),
        _Footer(
          listing: listing,
          providerName: providerName,
          onBook: onBook,
          onMessage: onMessage,
          onEdit: onEdit,
        ),
      ],
    );
  }
}

/// Sections with a gap between each, entering one step behind the last. The
/// stagger is over the sections a reader sees, not a container around them
/// (`frontend/CLAUDE.md`); the hero above is step zero.
class _SpacedColumn extends StatelessWidget {
  const _SpacedColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (final (index, child) in children.indexed) {
      if (index > 0) spaced.add(const SizedBox(height: AppSpacing.lg));
      spaced.add(child);
    }
    return FadeUpColumn(
      startIndex: 1,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.listing,
    required this.imageIndex,
    required this.onImage,
    required this.onReport,
    required this.showReport,
  });

  final PublicListing listing;
  final int imageIndex;
  final ValueChanged<int> onImage;
  final VoidCallback onReport;
  final bool showReport;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final images = listing.imageUrls;
    final index = images.isEmpty ? 0 : imageIndex.clamp(0, images.length - 1);
    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: colors.accentTint,
            child: images.isEmpty
                ? Icon(
                    Icons.image_outlined,
                    color: colors.placeholder,
                    size: AppSizes.iconDisc,
                  )
                : Image.network(
                    images[index],
                    fit: BoxFit.cover,
                    semanticLabel: listing.name,
                    // The listing is fine; the signed URL expired or the
                    // connection dropped. A wash, not a broken-image glyph.
                    errorBuilder: (context, error, stack) => Icon(
                      Icons.image_outlined,
                      color: colors.placeholder,
                      size: AppSizes.iconDisc,
                    ),
                  ),
          ),
          // Keeps the white controls legible over any photograph.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.34, 0.62, 1],
                colors: [
                  colors.scrim,
                  colors.scrim.withValues(alpha: 0),
                  colors.scrim.withValues(alpha: 0),
                  colors.scrim,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.md2,
                AppSpacing.lg,
                AppSpacing.md2,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleBackButton(
                        semanticLabel: 'Back',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      // Saving is §Phase 14's. Drawn where the artboard draws
                      // it, wired to nothing, marked so a test can tell.
                      const InertControl(
                        label: 'Save this service',
                        owedBy: 'Phase 14',
                        child: SaveHeartToggle(saved: false, onChanged: null),
                      ),
                      if (showReport) ...[
                        const SizedBox(width: AppSpacing.sm2),
                        _OverlayButton(
                          icon: Icons.flag_outlined,
                          semanticLabel: 'Report this listing',
                          onTap: onReport,
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CategoryPill(category: listing.category),
                      const Spacer(),
                      if (images.length > 1)
                        _Thumbnails(
                          urls: images.take(3).toList(),
                          selected: index,
                          onSelect: onImage,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      focusRadius: AppRadius.pill,
      builder: (context, state) => Container(
        width: AppSizes.iconButtonSize,
        height: AppSizes.iconButtonSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          boxShadow: AppShadows.card(colors.ink),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: AppSizes.iconLg, color: colors.textTertiary),
      ),
    );
  }
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({
    required this.urls,
    required this.selected,
    required this.onSelect,
  });

  final List<String> urls;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (final (i, url) in urls.indexed)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
            child: Pressable(
              semanticLabel: 'Photo ${i + 1} of ${urls.length}',
              selected: i == selected,
              onTap: () => onSelect(i),
              focusRadius: AppRadius.sm,
              builder: (context, state) => Container(
                width: AppSizes.avatarMedium + AppSpacing.xs,
                height: AppSizes.avatarMedium + AppSpacing.xs,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: i == selected
                        ? colors.surface
                        : colors.surface.withValues(alpha: 0.7),
                    width: AppSizes.selectedStroke,
                  ),
                ),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      ColoredBox(color: colors.skeletonBase),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The sticky footer. For a customer: the price, a message control and the
/// mode's CTA. For the owner: the price and **Edit** — the only place that
/// control exists, drawn from the server's `viewerIsOwner` and nothing else.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.listing,
    required this.providerName,
    required this.onBook,
    required this.onMessage,
    required this.onEdit,
  });

  final PublicListing listing;
  final String providerName;
  final VoidCallback onBook;
  final VoidCallback onMessage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final price = priceCopy(listing.pricing, providerName);
    final owner = listing.viewerIsOwner;
    final accepting = listing.provider.acceptingNewCustomers;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(price.footPrice, style: type.price),
                    Text(price.footSub, style: type.caption),
                  ],
                ),
              ),
              if (owner)
                AppButton.primary(label: 'Edit service', onPressed: onEdit)
              else ...[
                Pressable(
                  semanticLabel: 'Message $providerName',
                  onTap: onMessage,
                  focusRadius: AppRadius.button,
                  builder: (context, state) => Container(
                    width: AppSizes.ctaHeight,
                    height: AppSizes.ctaHeight,
                    decoration: BoxDecoration(
                      color: state.pressed
                          ? colors.surfaceMuted
                          : colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      border: Border.all(
                        color: colors.border,
                        width: AppSizes.inputStroke,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                AppButton.primary(
                  label: bookingCta(listing.bookingMode),
                  // A provider who has paused new customers cannot be booked;
                  // the server refuses too, and the card above says why.
                  onPressed: accepting ? onBook : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonLoader(
    label: 'Loading the service',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: _heroHeight, radius: 0),
        Padding(
          padding: AppSpacing.screenInsets,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSpacing.lg2),
              SkeletonBox(height: AppSpacing.xl2, width: 240),
              SizedBox(height: AppSpacing.md),
              SkeletonBox(height: AppSpacing.n13, width: 160),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(height: 96, radius: AppRadius.panel),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(height: 78, radius: AppRadius.panel),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(height: 150, radius: AppRadius.panel),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The listing is not public: a draft, a hidden or deleted listing, or a
/// provider who is not active — all the same answer, so the page never
/// confirms that a hidden thing exists.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => _MessagePage(
    child: EmptyState(
      icon: Icons.search_off_rounded,
      title: 'This listing is unavailable',
      body:
          'The provider has taken it down or isn’t active on RaajjePro '
          'right now, so it can’t be booked.',
      actionLabel: 'Browse services',
      onAction: onBrowse,
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _MessagePage(
    child: EmptyState.error(
      title: 'Couldn’t load this service',
      body:
          'Your connection may have dropped — that happens. Nothing is '
          'lost; try again.',
      onRetry: onRetry,
    ),
  );
}

class _MessagePage extends StatelessWidget {
  const _MessagePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AppHeader.page(
        title: 'Service',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: AppSpacing.screenInsets,
            child: FadeUp(child: child),
          ),
        ),
      ),
    ],
  );
}
