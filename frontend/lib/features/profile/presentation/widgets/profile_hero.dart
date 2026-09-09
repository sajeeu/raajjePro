import 'package:flutter/material.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/profile/presentation/widgets/profile_wave_band.dart';
import 'package:raajjepro/shared/shared.dart';

/// Profile's hero (`Profile.dc.html`): the 108 dp avatar and its ring, the
/// name, the member-since line, and the wave band.
///
/// **Two divergences from the prototype, both deliberate.**
///
/// 1. The avatar renders **initials**, and its change-photo control is drawn
///    but wired to nothing ([InertControl], owed by Phase 8). §Phase 6 never
///    mentions a photo, `User` carries no avatar column, and media upload via
///    presigned URL with content-type validation and EXIF stripping is
///    §Phase 8's deliverable. Building storage here would invent a retention
///    and bucket policy the plan does not specify.
/// 2. The subtitle reads `Member since Jan 2026` alone. The prototype's is
///    `Malé, Maldives · Member since Jan 2026`, and there is no customer
///    island field anywhere in this schema — `Island` itself is §Phase 7's
///    seed. Rather than print a placeholder location, the half that can be
///    answered is answered.
///
/// Both are recorded in `docs/decisions/18-phase-6-customer-profile.md`.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    required this.fullName,
    required this.memberSince,
    super.key,
  });

  final String fullName;
  final DateTime memberSince;

  static const avatarSize = 108.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xl,
              AppSpacing.sm + 2,
              AppSpacing.xl,
              AppSpacing.xxs,
            ),
            child: Column(
              children: [
                _AvatarWithPhotoControl(fullName: fullName),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    fullName,
                    textAlign: TextAlign.center,
                    style: type.screenTitle,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Member since ${monthAndYear(memberSince)}',
                  textAlign: TextAlign.center,
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const ProfileWaveBand(),
        ],
      ),
    );
  }
}

class _AvatarWithPhotoControl extends StatelessWidget {
  const _AvatarWithPhotoControl({required this.fullName});

  final String fullName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      // The ring sits 5 dp outside the disc and the control overhangs the
      // trailing-bottom corner, so the box is wider than the avatar itself.
      width: ProfileHero.avatarSize + AppSpacing.xxl,
      height: ProfileHero.avatarSize + AppSpacing.md,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: ProfileHero.avatarSize + 10,
            height: ProfileHero.avatarSize + 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.accentBorder,
                width: AppSizes.selectedStroke,
              ),
            ),
            alignment: Alignment.center,
            // No tier overlay. This is the customer's own profile and
            // `AppAvatar`'s overlay is a pointer to a provider's tier badge,
            // whose words must be reachable on the same screen.
            child: AppAvatar(name: fullName, size: ProfileHero.avatarSize),
          ),
          const PositionedDirectional(
            end: 0,
            bottom: 0,
            child: InertControl(
              label: 'Change photo',
              owedBy: 'Phase 8',
              child: _ChangePhotoButton(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The camera disc. 30 dp of paint inside a 48 dp target, as Round 48 §5
/// requires — but with no handler, because there is nowhere to put a photo
/// until §Phase 8's media upload exists. `Pressable` with `onTap: null`
/// renders it disabled and announces it as such rather than as a live
/// control.
class _ChangePhotoButton extends StatelessWidget {
  const _ChangePhotoButton();

  static const disc = 30.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: null,
      semanticLabel: 'Change photo. Not available yet.',
      focusRadius: AppRadius.pill,
      // No `excludeSemantics`: it returns the child unwrapped, which would
      // drop this label and leave a control that announces nothing at all —
      // the opposite of what an unavailable control should do.
      builder: (context, s) => Center(
        child: Container(
          width: disc,
          height: disc,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface,
            border: Border.all(color: colors.border),
            boxShadow: AppShadows.card(colors.ink),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.photo_camera_outlined,
            size: 14,
            color: colors.textTertiary,
          ),
        ),
      ),
    );
  }
}
