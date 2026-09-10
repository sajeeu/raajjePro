import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/onboarding/data/provider_onboarding_api.dart';
import 'package:raajjepro/features/onboarding/presentation/widgets/account_email_row.dart';
import 'package:raajjepro/features/onboarding/presentation/widgets/bank_field.dart';
import 'package:raajjepro/features/onboarding/presentation/widgets/provider_type_choice.dart';
import 'package:raajjepro/features/onboarding/presentation/widgets/registered_phone_row.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 6a step 2 — account details (`Become a Provider.dc.html`,
/// "2 · Provider basics").
///
/// Three sections, in the artboard's order and Round 21's grouping: **About
/// you · Getting paid · Availability**. The plan is explicit about why they
/// are grouped — "because the delivered design showed the ungrouped list
/// reads as a wall".
///
/// **A standalone widget with its own text controllers**, seeded from
/// [profile] once. It reads no provider and writes nothing: the submission
/// goes out through [onSubmit] and every error comes back in [errors], so the
/// step can be pumped on its own in a test (`wizard-step-pattern`).
///
/// Two things it deliberately does not do:
///
///  - **It does not autosave.** See `ProviderOnboardingController` — the
///    first write creates the provider profile, and that flip is permanent.
///  - **It does not upload the photo.** The control is drawn to the artboard
///    and wired to nothing ([InertControl], owed by §Phase 8): `User` has no
///    avatar column, `ProviderProfile` has no logo column, and media upload
///    via presigned URL with content-type validation and EXIF stripping is
///    §Phase 8's deliverable. Phase 6 set this precedent for the same control
///    on Profile. §Phase 6a marks the photo optional, so nothing is blocked
///    by its absence.
class AccountDetailsStep extends StatefulWidget {
  const AccountDetailsStep({
    required this.profile,
    required this.account,
    required this.errors,
    required this.editingPhone,
    required this.onEditPhone,
    required this.onClearError,
    required this.onVerifyEmail,
    super.key,
    this.draft,
  });

  /// The server's current values — the pre-fill, and what makes resuming here
  /// work without a local draft.
  final ProviderOnboardingState profile;

  /// The signed-in account. §Phase 6a takes the phone and the email from
  /// Phase 3 rather than asking for either again.
  final UserAccount account;

  final Map<String, String> errors;
  final bool editingPhone;
  final VoidCallback onEditPhone;
  final ValueChanged<String> onClearError;

  /// Routes to Phase 3's Verify Email screen. §Phase 6a blocks Continue on an
  /// unverified address, so the block has to carry the way out of it — and
  /// that screen tears this stack down on success, which is what [draft] is
  /// for.
  final VoidCallback onVerifyEmail;

  /// What was typed before the provider left to verify their email. Wins over
  /// [profile], on the same precedent Change phone sets for a draft saved by a
  /// dead session: a value the user was actively editing beats the stored one.
  final Map<String, String>? draft;

  @override
  AccountDetailsStepState createState() => AccountDetailsStepState();
}

class AccountDetailsStepState extends State<AccountDetailsStep> {
  late final TextEditingController _name;
  late final TextEditingController _intro;
  late final TextEditingController _holder;
  late final TextEditingController _account;
  late final TextEditingController _dial;
  late final TextEditingController _phone;

  ProviderType? _type;
  String? _bank;
  late bool _accepting;

  /// The number as it stood when the step opened, so an unedited phone is not
  /// re-sent to `PATCH /v1/users/me/phone` on every Continue.
  late final String _originalPhone;
  late final String _originalDial;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    final phone = widget.account.phone;
    final d = widget.draft ?? const <String, String>{};
    _name = TextEditingController(
      text: d['businessName'] ?? p.businessName ?? '',
    );
    _intro = TextEditingController(text: d['bio'] ?? p.bio ?? '');
    _holder = TextEditingController(
      text: d['bankAccountName'] ?? p.bankAccountName ?? '',
    );
    _account = TextEditingController(
      text: d['bankAccountNumber'] ?? p.bankAccountNumber ?? '',
    );
    _originalDial = phone?.dialCode ?? '+960';
    _originalPhone = phone?.number ?? '';
    _dial = TextEditingController(text: _originalDial);
    _phone = TextEditingController(text: _originalPhone);
    _type = ProviderType.fromWire(d['providerType']) ?? p.providerType;
    _bank = d['bankName']?.isEmpty ?? true ? p.bankName : d['bankName'];
    _accepting = p.acceptingNewCustomers;
  }

  @override
  void dispose() {
    for (final c in [_name, _intro, _holder, _account, _dial, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Read by the footer's Continue, which lives outside this widget because
  /// the artboard pins it to the bottom of the screen rather than the end of
  /// the form.
  AccountDetailsInput collect() => (
    businessName: _name.text.trim(),
    providerType: _type,
    bio: _intro.text.trim(),
    bankName: _bank ?? '',
    bankAccountName: _holder.text.trim(),
    bankAccountNumber: _account.text.trim(),
    acceptingNewCustomers: _accepting,
    dialCode: _dial.text.trim(),
    phoneNumber: _phone.text.trim(),
    phoneChanged:
        _dial.text.trim() != _originalDial ||
        _phone.text.trim() != _originalPhone,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final errors = widget.errors;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xxl + AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tell us about you', style: type.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Who you are, how you get paid, and when you're available.",
            style: type.body.copyWith(color: colors.textSecondary),
          ),

          const _SectionRule(label: 'About you'),
          const _PhotoRow(),

          const SizedBox(height: AppSpacing.xxl - 2),
          AppTextField(
            key: const Key('onboarding-name'),
            label: 'Provider or business name',
            controller: _name,
            hint: "e.g. Hassan's Repairs",
            textCapitalization: TextCapitalization.words,
            errorText: errors['businessName'],
            helper: 'Shown to customers on your profile and services.',
            onChanged: (_) => widget.onClearError('businessName'),
            requirement: FieldRequirement.mandatory,
          ),

          const SizedBox(height: AppSpacing.xxl - 2),
          ProviderTypeChoice(
            value: _type,
            errorText: errors['providerType'],
            onChanged: (value) {
              setState(() => _type = value);
              widget.onClearError('providerType');
            },
          ),

          const SizedBox(height: AppSpacing.xxl - 2),
          RegisteredPhoneRow(
            editing: widget.editingPhone,
            dial: _dial,
            number: _phone,
            display: widget.account.phone?.display,
            errorText: errors['phone'],
            onEdit: widget.onEditPhone,
            onChanged: () => widget.onClearError('phone'),
          ),

          const SizedBox(height: AppSpacing.xxl - 2),
          AccountEmailRow(
            email: widget.account.email,
            verified: widget.account.emailVerified,
            errorText: errors['email'],
            onVerify: widget.onVerifyEmail,
          ),

          const SizedBox(height: AppSpacing.xxl - 2),
          AppTextField(
            key: const Key('onboarding-intro'),
            label: 'Short introduction',
            controller: _intro,
            hint:
                'e.g. AC repair and servicing in Malé for 8 years. Fast, tidy '
                'and reliable.',
            maxLines: 3,
            // §Phase 6a's 160-character cap. The counter is the courtesy; the
            // rule is the server's (invariant 4) and `updateOwnProviderBody`
            // holds the same number.
            maxLength: 160,
            textCapitalization: TextCapitalization.sentences,
            helper: 'A sentence or two about what you do.',
            requirement: FieldRequirement.optional,
          ),

          const _SectionRule(label: 'Getting paid'),
          const _DirectPaymentNotice(),

          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            key: const Key('onboarding-holder'),
            label: 'Account holder name',
            controller: _holder,
            hint: 'As printed on your bank account',
            textCapitalization: TextCapitalization.words,
            errorText: errors['bankAccountName'],
            helper: 'Must match your bank records exactly.',
            onChanged: (_) => widget.onClearError('bankAccountName'),
            requirement: FieldRequirement.mandatory,
          ),

          const SizedBox(height: AppSpacing.xxl - 2),
          AppTextField(
            key: const Key('onboarding-account'),
            label: 'Account number',
            controller: _account,
            hint: 'e.g. 7730000123456',
            keyboardType: TextInputType.number,
            inputFormatters: [
              // 🔧 **The server's bounds, not the artboard's.** The artboard
              // forces digits only and caps at 16; `updateOwnProviderBody`
              // accepts 4–40 characters of digits, spaces and dashes, and a
              // client stricter than the server blocks a legitimate account —
              // the same expatriate case Round 17 protected on the phone
              // field, where a foreign account number is longer and often
              // written in groups.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]')),
              LengthLimitingTextInputFormatter(40),
            ],
            errorText: errors['bankAccountNumber'],
            // §Phase 5's payment details are shown to a customer only at a
            // booking's payment step, and this says so without overclaiming:
            // it is not private, and it is not published either.
            helper: 'Only you and paying customers see this.',
            onChanged: (_) => widget.onClearError('bankAccountNumber'),
            requirement: FieldRequirement.mandatory,
          ),

          const SizedBox(height: AppSpacing.xxl - 2),
          BankField(
            value: _bank,
            errorText: errors['bankName'],
            onChanged: (value) {
              setState(() => _bank = value);
              widget.onClearError('bankName');
            },
          ),

          const _SectionRule(label: 'Availability'),
          AppCard(
            child: AppToggle(
              value: _accepting,
              label: 'Accepting new customers',
              description:
                  "Turn this off when you're fully booked. It hides all your "
                  'services at once — this is an account-level switch, not '
                  'per service — and you can turn it back on anytime.',
              onChanged: (value) => setState(() => _accepting = value),
            ),
          ),
        ],
      ),
    );
  }
}

/// The uppercase rule between sections (Round 21's grouping).
class _SectionRule extends StatelessWidget {
  const _SectionRule({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: AppSpacing.xxl,
        bottom: AppSpacing.lg,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: context.type.overline.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(child: Divider(height: 1, color: colors.border)),
        ],
      ),
    );
  }
}

/// The photo or logo control — drawn, and wired to nothing.
///
/// See [AccountDetailsStep]'s note: no avatar or logo column exists and media
/// upload is §Phase 8's. Wrapped in [InertControl] so the test that asserts it
/// does nothing fails the day §Phase 8 wires it, which is the point.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return InertControl(
      label: 'Add photo',
      owedBy: 'Phase 8',
      child: AppCard(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.lg + 2,
          vertical: AppSpacing.lg,
        ),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.neutralBorder,
                  width: AppSizes.selectedStroke,
                ),
              ),
              child: Icon(
                Icons.photo_camera_outlined,
                size: AppSizes.iconLg + 6,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Photo or logo', style: type.bodyStrong),
                      const SizedBox(width: AppSpacing.sm),
                      const FieldRequirementPill(FieldRequirement.optional),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs / 2),
                  Text(
                    'Profiles with a photo get noticed more by customers.',
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §1c's off-platform payment rule, said plainly where the provider is typing
/// their account number. §Phase 6a calls this "context, not fine print", and
/// it is the sentence most likely to correct a wrong assumption.
class _DirectPaymentNotice extends StatelessWidget {
  const _DirectPaymentNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      decoration: BoxDecoration(
        color: colors.successTint,
        borderRadius: AppRadius.circular(AppRadius.card),
        border: Border.all(color: colors.successBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: AppSizes.iconLg + 1,
            color: colors.successText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Customers pay you directly into this account. RaajjePro never '
              'collects or holds your payments.',
              style: context.type.secondary.copyWith(color: colors.successText),
            ),
          ),
        ],
      ),
    );
  }
}
