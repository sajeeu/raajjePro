import 'package:flutter/material.dart';

import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/data/service_listing.dart';
import 'package:raajjepro/shared/shared.dart';

/// "Your service is live" — the end of the flow, and the one moment the
/// wizard congratulates anybody.
///
/// **The body says where the listing will actually appear**, naming the
/// category and the islands the provider chose, because that is the thing
/// they have been filling in seven steps to achieve.
///
/// 🔧 **One divergence from `Create Service.dc.html`: no "View listing"
/// button.** The prototype's links to `Service Preview.dc.html`, which is
/// §Phase 12's screen and does not exist — a button that landed nowhere would
/// be worse than its absence. §Phase 12 adds it back.
class PublishedSheet extends StatelessWidget {
  const PublishedSheet({
    required this.listing,
    required this.categoryName,
    required this.onDone,
    super.key,
  });

  final ServiceListing listing;
  final String? categoryName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: colors.ctaGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: AppSpacing.n34,
                color: colors.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your service is live',
            textAlign: TextAlign.center,
            style: type.screenTitle,
          ),
          const SizedBox(height: AppSpacing.sm2),
          Text(
            _body(),
            textAlign: TextAlign.center,
            style: type.body.copyWith(
              height: 1.55,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            key: const Key('published-my-services'),
            label: 'My services',
            expand: true,
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context)
                  .pushReplacementNamed(AppRoutes.providerDashboard);
            },
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.text(label: 'Done', expand: true, onPressed: onDone),
        ],
      ),
    );
  }

  String _body() {
    final name = (listing.name ?? '').trim();
    final title = name.isEmpty ? 'Your service' : '“$name”';
    final where = listing.serviceAreas.isEmpty
        ? 'your service area'
        : [for (final island in listing.serviceAreas) island.displayName]
              .join(', ');
    final category = categoryName == null ? '' : ' $categoryName';
    return '$title now appears in$category search results on $where, and on '
        'your provider profile.';
  }
}

/// The over-cap refusal, as §Phase 9 asks for it: **an upgrade prompt, not a
/// generic error**.
///
/// It is a prompt and not a cap on drafting. Nothing was lost and nothing was
/// blocked: the draft is saved, it stays in My Services, and the provider has
/// two real choices — upgrade, or swap which listing is live. The sheet says
/// both, and the footnote says the draft is safe, because a provider who has
/// just been refused needs to hear that before anything else.
class ListingCapSheet extends StatelessWidget {
  const ListingCapSheet({
    required this.detail,
    required this.onKeepDraft,
    super.key,
  });

  final ListingCapDetail detail;
  final VoidCallback onKeepDraft;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: colors.accentTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.layers_outlined,
                size: AppSpacing.xxxl,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            detail.cap == 1
                ? 'Your plan publishes one service at a time'
                : 'Your plan publishes ${detail.cap} services at a time',
            textAlign: TextAlign.center,
            style: type.screenTitle,
          ),
          const SizedBox(height: AppSpacing.sm2),
          Text(
            _body(),
            textAlign: TextAlign.center,
            style: type.body.copyWith(
              height: 1.55,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            key: const Key('cap-see-plans'),
            label: 'See what upgrading allows',
            expand: true,
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRoutes.providerBilling);
            },
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.text(
            label: 'Keep it as a draft',
            expand: true,
            onPressed: onKeepDraft,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Drafts stay in My Services — nothing is lost.',
            textAlign: TextAlign.center,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _body() {
    final live = detail.liveListingNames;
    final already = live.isEmpty
        ? 'Another service is already live.'
        : '${live.join(', ')} ${live.length == 1 ? 'is' : 'are'} already live.';
    return "$already This draft is saved and isn't going anywhere — upgrading "
        'lets you publish several services side by side, or you can swap '
        'which one is live.';
  }
}
