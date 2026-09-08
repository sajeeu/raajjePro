import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/shared/shared.dart';

/// Delete account (`Account Settings.dc.html`, including the frozen card;
/// plan §Phase 3). The request is accepted immediately — deletion is
/// queued, never refused, and no branch here renders a rejection.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  static const routeName = '/account/delete';

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(deleteControllerProvider);
    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Delete account',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: s.result == null
                ? _ConfirmCard(state: s, typed: _typed)
                : _FrozenCard(result: s.result!),
          ),
        ],
      ),
    );
  }
}

Widget _factRow(BuildContext context, String text) {
  final colors = context.colors;
  final type = context.type;
  return Padding(
    padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: type.body.copyWith(color: colors.textSecondary)),
        Expanded(
          child: Text(text, style: type.body.copyWith(color: colors.ink)),
        ),
      ],
    ),
  );
}

class _ConfirmCard extends ConsumerStatefulWidget {
  const _ConfirmCard({required this.state, required this.typed});
  final DeleteState state;
  final TextEditingController typed;

  @override
  ConsumerState<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends ConsumerState<_ConfirmCard> {
  @override
  void initState() {
    super.initState();
    widget.typed.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(_ConfirmCard old) {
    super.didUpdateWidget(old);
    if (old.typed != widget.typed) {
      old.typed.removeListener(_rebuild);
      widget.typed.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.typed.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = widget.state;
    final matches = widget.typed.text.trim().toUpperCase() == 'DELETE';

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSizes.iconDisc,
                height: AppSizes.iconDisc,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.errorTint,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: colors.error,
                  size: AppSizes.iconLg,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Delete your account', style: type.cardTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Your request is accepted immediately — open bookings don't block it. Here's exactly what happens:",
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              _factRow(
                context,
                'Your account freezes at once — no new bookings, no new listings, hidden from search.',
              ),
              _factRow(
                context,
                'Deletion completes when your open bookings finish — and within 30 days regardless.',
              ),
              _factRow(
                context,
                'Reviews you wrote stay, with your name removed.',
              ),
              _factRow(
                context,
                'Identity documents are deleted outright — not anonymised.',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (s.offline)
          InlineNotice.offline(
            onRetry: () =>
                ref.read(deleteControllerProvider.notifier).confirm(),
          ),
        AppTextField(
          key: const Key('delete-confirm'),
          label: 'Type DELETE to confirm',
          controller: widget.typed,
          hint: 'DELETE',
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          enabled: !s.busy,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton.destructive(
          label: 'Delete my account',
          expand: true,
          loading: s.busy,
          onPressed: matches && !s.busy
              ? () => ref.read(deleteControllerProvider.notifier).confirm()
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(
          label: 'Keep my account',
          expand: true,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

class _FrozenCard extends StatelessWidget {
  const _FrozenCard({required this.result});
  final DeletionResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSizes.iconDisc,
                height: AppSizes.iconDisc,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentTint,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: colors.primary,
                  size: AppSizes.iconLg,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Your deletion request is in', style: type.cardTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Your account is frozen as of now — no new bookings, no new listings, and it's hidden from search.",
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              _factRow(
                context,
                'Deletion completes when your open bookings finish — and within 30 days regardless.',
              ),
              _factRow(
                context,
                'Reviews you wrote stay, with your name removed.',
              ),
              _factRow(
                context,
                'Identity documents are deleted outright — not anonymised.',
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Deletion completes by ${shortDate(result.deletionDeadlineAt)} at the latest.',
                style: type.secondary.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton.primary(
          label: 'Done',
          expand: true,
          onPressed: () =>
              Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
        ),
      ],
    );
  }
}
