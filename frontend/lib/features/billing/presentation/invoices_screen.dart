import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/billing/controller/billing_controller.dart';
import 'package:raajjepro/features/billing/controller/invoices_controller.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';
import 'package:raajjepro/features/billing/presentation/widgets/billing_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Invoices** (`Invoices.dc.html`) — §1b step 6, "on confirmation, a
/// downloadable PDF invoice is generated", and §Phase 10a's "invoice list
/// with PDF download per confirmed payment".
///
/// Four states, the artboard's own: skeleton, error, empty, populated. A
/// voided invoice — the payment behind it was reversed — stays in the list
/// with its label, because a document that was issued cannot be made never to
/// have existed (invariant 8).
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  static const routeName = '/provider/billing/invoices';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final invoices = ref.watch(invoicesControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Invoices',
            backLabel: 'Back to Billing',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (invoices) {
              AsyncLoading() => SkeletonLoader(
                label: 'Loading your invoices',
                child: ListView(
                  padding: AppSpacing.screenInsets,
                  children: const [
                    SizedBox(height: AppSpacing.lg),
                    SkeletonRow(),
                    SizedBox(height: AppSpacing.md),
                    SkeletonRow(),
                    SizedBox(height: AppSpacing.md),
                    SkeletonRow(),
                  ],
                ),
              ),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load your invoices',
                  body: error is ApiNetworkException
                      ? 'Your payment records are safe. Check your connection '
                            'and try again.'
                      : 'Your payment records are safe. Something went wrong '
                            'fetching them — try again.',
                  onRetry: () =>
                      ref.read(invoicesControllerProvider.notifier).reload(),
                ),
              ),
              AsyncData(:final value) when value.isEmpty => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState(
                  icon: Icons.calendar_today_outlined,
                  title: 'No payments yet',
                  body:
                      'When a bank transfer is confirmed, its invoice appears '
                      'here with a PDF you can download.',
                  actionLabel: 'Go to Billing',
                  onAction: () => Navigator.of(context).maybePop(),
                ),
              ),
              AsyncData(:final value) => _InvoiceList(invoices: value),
            },
          ),
        ],
      ),
    );
  }
}

class _InvoiceList extends ConsumerStatefulWidget {
  const _InvoiceList({required this.invoices});

  final List<Invoice> invoices;

  @override
  ConsumerState<_InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends ConsumerState<_InvoiceList> {
  String? _open;

  @override
  void initState() {
    super.initState();
    _open = widget.invoices.isEmpty ? null : widget.invoices.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final invoices = widget.invoices;
    final download = ref.watch(invoiceDownloadProvider);
    // The cohort chip reads the billing status, which is the one place the
    // provider's rate lives. Absent while that read is out or failed.
    final introductory =
        ref.watch(billingControllerProvider).value?.status.introductory ??
        false;

    ref.listen(invoiceDownloadProvider, (previous, next) {
      final error = next.error;
      if (error != null && previous?.error != error) {
        AppHaptics.refused();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        ref.read(invoiceDownloadProvider.notifier).clearError();
      }
    });

    final counted = invoices.where((i) => !i.voided).toList();
    final total = counted.fold<int>(0, (sum, i) => sum + i.amountLaari);
    final earliest = invoices
        .map((i) => i.issuedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Row(
            children: [
              const RowIcon(icon: Icons.payments_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mvr(total), style: type.stat),
                    Text(
                      '${counted.length} confirmed '
                      '${counted.length == 1 ? 'payment' : 'payments'} since '
                      '${shortDate(maldives(earliest))}',
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (introductory) ...[
                const SizedBox(width: AppSpacing.sm),
                const AppChip.label(label: 'Intro rate'),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final invoice in invoices)
          _InvoiceRow(
            invoice: invoice,
            open: _open == invoice.id,
            downloading: download.downloadingId == invoice.id,
            onToggle: () {
              AppHaptics.selection();
              setState(() => _open = _open == invoice.id ? null : invoice.id);
            },
            onDownload: () =>
                ref.read(invoiceDownloadProvider.notifier).download(invoice),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Amounts are what you actually paid at the time — your rate, not a '
          'list price.',
          style: type.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }
}

/// One invoice: the header row toggles the detail; the controls live in the
/// detail, outside the tappable header, so a screen reader keeps them.
class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.open,
    required this.downloading,
    required this.onToggle,
    required this.onDownload,
  });

  final Invoice invoice;
  final bool open;
  final bool downloading;
  final VoidCallback onToggle;
  final VoidCallback onDownload;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final issued = maldives(invoice.issuedAt);
    final period =
        '${dayAndMonth(maldives(invoice.periodStart))} – '
        '${dayAndMonth(maldives(invoice.periodEnd))}';

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pressable(
              semanticLabel:
                  'Invoice ${invoice.invoiceNumber}, ${mvr(invoice.amountLaari)}, '
                  '${shortDate(issued)}${invoice.voided ? ', voided' : ''}',
              toggled: open,
              focusRadius: AppRadius.panel,
              onTap: onToggle,
              builder: (context, s) => Padding(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md2),
                child: Row(
                  children: [
                    Container(
                      width: AppSizes.iconDisc,
                      height: AppSizes.iconDisc,
                      decoration: BoxDecoration(
                        color: colors.accentTint,
                        borderRadius: BorderRadius.circular(AppRadius.compact),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${issued.day}',
                            style: type.cardTitle.copyWith(
                              color: colors.accentText,
                            ),
                          ),
                          Text(
                            _months[issued.month - 1],
                            style: type.overline.copyWith(
                              color: colors.accentText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shortDate(issued), style: type.bodyStrong),
                          Text(
                            'Covers $period',
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(mvr(invoice.amountLaari), style: type.price),
                        if (invoice.voided)
                          const StatusBadge.custom(
                            label: 'Voided',
                            tone: BadgeTone.grey,
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: context.motion.fast,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md2,
                  0,
                  AppSpacing.md2,
                  AppSpacing.md2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(
                      height: AppSizes.dividerStroke,
                      color: colors.divider,
                    ),
                    const SizedBox(height: AppSpacing.sm2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Premium · 30-day period',
                            style: type.secondary.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        Text(mvr(invoice.amountLaari), style: type.secondary),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Total paid', style: type.bodyStrong),
                        ),
                        Text(mvr(invoice.amountLaari), style: type.bodyStrong),
                      ],
                    ),
                    if (invoice.voided) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Voided${invoice.voidedReason == null ? '' : ' — ${invoice.voidedReason}'}. '
                        'The payment behind this invoice was reversed; the '
                        'document is kept as a record.',
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: FactRow(
                            label: 'Invoice',
                            value: invoice.invoiceNumber,
                          ),
                        ),
                        CopyButton(
                          value: invoice.invoiceNumber,
                          what: 'Invoice number',
                          onCopied: (what) => ScaffoldMessenger.of(context)
                              .showSnackBar(
                                SnackBar(content: Text('$what copied')),
                              ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AppButton.primary(
                          label: 'Download PDF',
                          icon: Icons.download_rounded,
                          size: AppButtonSize.compact,
                          loading: downloading,
                          onPressed: onDownload,
                        ),
                      ],
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
