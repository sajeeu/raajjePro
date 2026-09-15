import 'package:flutter/material.dart';

import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Step 4 — Photos & media.
///
/// The cover image is the sixth required field (§0.2 item 4): it is the first
/// thing a customer sees on every card and in every search result, and v4 let
/// a listing go live without one.
///
/// An upload is three steps and the middle one is the provider's connection
/// (§Phase 8). Until the server has finalised the bytes the row is `pending`,
/// and the publish gate treats a pending cover as a missing one — which is
/// why "Uploading…" and "Upload failed · Retry" are separate states here
/// rather than one spinner.
class MediaStep extends StatelessWidget {
  const MediaStep({required this.view, required this.controller, super.key});

  final WizardView view;
  final ServiceWizardController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final listing = view.listing;
    final upload = view.upload;
    final gallery = listing.gallery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Photos & media',
          body:
              'Good photos dramatically increase bookings. Show your work at '
              'its best.',
        ),
        const SizedBox(height: AppSpacing.lg2),
        WizardSection(
          title: 'Cover image',
          requirement: FieldRequirement.mandatory,
          helper:
              'The first thing customers see — on every card, in every '
              'search result.',
          children: [
            if (upload?.target == MediaTarget.cover)
              _UploadTile(
                upload: upload!,
                aspectRatio: 16 / 9,
                onRetry: controller.retryUpload,
                onDismiss: controller.dismissUpload,
              )
            else if (listing.coverMedia == null)
              _UploadPrompt(
                fieldKey: const Key('wizard-cover-upload'),
                title: 'Upload cover image',
                subtitle: 'JPG, PNG or WEBP · Max 10 MB · 1200×675 works best',
                onTap: controller.pickCover,
              )
            else ...[
              _Thumbnail(
                media: listing.coverMedia!,
                aspectRatio: 16 / 9,
                semanticLabel: 'Cover image',
              ),
              const SizedBox(height: AppSpacing.sm2),
              Row(
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Replace',
                      size: AppButtonSize.compact,
                      expand: true,
                      onPressed: controller.pickCover,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm2),
                  AppButton.text(
                    label: 'Remove',
                    size: AppButtonSize.compact,
                    onPressed: () =>
                        controller.removeMedia(listing.coverMedia!.id),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg2),
        WizardSection(
          title: 'Gallery',
          requirement: FieldRequirement.optional,
          helper:
              'Up to $maxGalleryPhotos photos of your work '
              '(${gallery.length}/$maxGalleryPhotos). Use the arrows to '
              'reorder — the first photo shows first.',
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.sm2,
              crossAxisSpacing: AppSpacing.sm2,
              padding: EdgeInsets.zero,
              children: [
                for (var index = 0; index < gallery.length; index++)
                  _GalleryTile(
                    media: gallery[index],
                    position: index,
                    total: gallery.length,
                    onMove: (delta) =>
                        controller.moveGalleryPhoto(index, delta),
                    onRemove: () => controller.removeMedia(gallery[index].id),
                  ),
                if (upload?.target == MediaTarget.gallery)
                  _UploadTile(
                    upload: upload!,
                    aspectRatio: 1,
                    onRetry: controller.retryUpload,
                    onDismiss: controller.dismissUpload,
                  )
                else if (gallery.length < maxGalleryPhotos)
                  _AddPhotoTile(onTap: controller.addGalleryPhoto),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.n15,
                  vertical: AppSpacing.n13,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PHOTO TIPS',
                      style: type.overline.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Natural light where possible · show the finished '
                      'result · landscape works best on cards. Photos are '
                      'stored on RaajjePro, so they keep working even if the '
                      'original goes away.',
                      style: type.secondary.copyWith(
                        height: 1.6,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The empty cover slot: dashed, so it reads as somewhere to put something
/// rather than as a card that failed to load.
class _UploadPrompt extends StatelessWidget {
  const _UploadPrompt({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.fieldKey,
  });

  final Key? fieldKey;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Pressable(
      key: fieldKey,
      semanticLabel: '$title. $subtitle',
      onTap: onTap,
      minSize: 0,
      focusRadius: AppRadius.button,
      builder: (context, state) => DecoratedBox(
        decoration: BoxDecoration(
          color: state.pressed ? colors.accentTint : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: colors.accentBorderPressed,
            width: AppSizes.inputStroke,
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xxl2,
          ),
          child: Column(
            children: [
              Container(
                width: AppSizes.iconDisc,
                height: AppSizes.iconDisc,
                decoration: BoxDecoration(
                  color: colors.accentTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.file_upload_outlined,
                  size: AppSpacing.xl,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.n9),
              Text(
                title,
                style: type.bodyStrong.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.accentText,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An upload in flight, or the one that failed.
///
/// Retry re-sends the bytes the provider already chose — it does not reopen
/// the picker, because finding the photo again is work they already did.
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.upload,
    required this.aspectRatio,
    required this.onRetry,
    required this.onDismiss,
  });

  final MediaUpload upload;
  final double aspectRatio;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final failed = upload.failed;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: failed ? colors.errorTint : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: failed ? colors.errorBorder : colors.border,
            width: AppSizes.inputStroke,
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.sm2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (failed) ...[
                Icon(
                  Icons.error_outline_rounded,
                  size: AppSizes.iconMd,
                  color: colors.error,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Upload failed',
                  textAlign: TextAlign.center,
                  style: type.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.errorText,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppButton.destructive(
                  key: const Key('wizard-upload-retry'),
                  label: 'Retry',
                  size: AppButtonSize.compact,
                  onPressed: onRetry,
                ),
              ] else ...[
                AppSpinner(size: AppSizes.iconMd, color: colors.primary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Uploading…',
                  style: type.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      key: const Key('wizard-add-photo'),
      semanticLabel: 'Add a photo to the gallery',
      onTap: onTap,
      minSize: 0,
      focusRadius: AppRadius.input,
      builder: (context, state) => DecoratedBox(
        decoration: BoxDecoration(
          color: state.pressed ? colors.accentTint : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: colors.accentBorderPressed,
            width: AppSizes.inputStroke,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_rounded,
              size: AppSizes.iconLg,
              color: colors.primary,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Add',
              style: context.type.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.media,
    required this.position,
    required this.total,
    required this.onMove,
    required this.onRemove,
  });

  final ListingMedia media;
  final int position;
  final int total;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Thumbnail(
          media: media,
          aspectRatio: 1,
          semanticLabel: 'Photo ${position + 1} of $total',
        ),
        PositionedDirectional(
          top: 5,
          end: 5,
          child: _TileButton(
            icon: Icons.close_rounded,
            label: 'Remove photo ${position + 1}',
            circular: true,
            onTap: onRemove,
          ),
        ),
        PositionedDirectional(
          bottom: 5,
          start: 5,
          end: 5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (position > 0)
                _TileButton(
                  icon: Icons.chevron_left_rounded,
                  label: 'Move photo ${position + 1} earlier',
                  onTap: () => onMove(-1),
                )
              else
                const SizedBox.shrink(),
              if (position < total - 1)
                _TileButton(
                  icon: Icons.chevron_right_rounded,
                  label: 'Move photo ${position + 1} later',
                  onTap: () => onMove(1),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.circular = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      minSize: 0,
      focusRadius: circular ? AppRadius.pill : AppRadius.xs,
      builder: (context, state) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colors.ink.withValues(alpha: state.pressed ? 0.75 : 0.55),
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circular ? null : BorderRadius.circular(AppRadius.xs),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 13, color: colors.onPrimary),
      ),
    );
  }
}

/// One stored image, behind its short-lived signed URL.
///
/// A URL that has expired, or an image the device cannot reach, renders the
/// neutral placeholder rather than throwing — a listing whose photo will not
/// load is still a listing the provider must be able to edit.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.media,
    required this.aspectRatio,
    required this.semanticLabel,
  });

  final ListingMedia media;
  final double aspectRatio;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = media.url;

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ColoredBox(
            color: colors.surfaceMuted,
            child: url == null
                ? _Placeholder(colors: colors)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        _Placeholder(colors: colors),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : SkeletonLoader(
                            child: ColoredBox(color: colors.skeletonBase),
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.image_outlined,
      size: AppSizes.iconLg,
      color: colors.placeholder,
    ),
  );
}
