import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/files/share_file.dart';
import 'package:raajjepro/features/billing/data/billing_api.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';
import 'package:share_plus/share_plus.dart';

Duration? _noRetry(int retryCount, Object error) => null;

final invoicesControllerProvider =
    AsyncNotifierProvider<InvoicesController, List<Invoice>>(
      InvoicesController.new,
      retry: _noRetry,
    );

/// §Phase 10a's "invoice list with PDF download per confirmed payment".
class InvoicesController extends AsyncNotifier<List<Invoice>> {
  @override
  Future<List<Invoice>> build() => ref.read(billingApiProvider).invoices();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(billingApiProvider).invoices(),
    );
  }
}

class InvoiceDownloadState {
  const InvoiceDownloadState({this.downloadingId, this.error});

  /// Which row shows its own spinner. One at a time — a PDF is a second.
  final String? downloadingId;
  final String? error;
}

final invoiceDownloadProvider =
    NotifierProvider<InvoiceDownloadController, InvoiceDownloadState>(
      InvoiceDownloadController.new,
    );

/// Fetches the stored PDF from its short-lived signed URL and hands it to the
/// OS share sheet, the way §Phase 3's data export does.
///
/// **Outside [ApiClient], deliberately.** The URL is signed; that *is* the
/// authorization, and a bearer token, an envelope decode and a session refresh
/// have no place on it — the same reasoning as `MediaUploader`. The bytes are
/// written to an app-private temp directory first because the share channel
/// reads the file's name from its path (see `DownloadController`).
class InvoiceDownloadController extends Notifier<InvoiceDownloadState> {
  @override
  InvoiceDownloadState build() => const InvoiceDownloadState();

  Future<void> download(Invoice invoice) async {
    if (state.downloadingId != null) return;
    state = InvoiceDownloadState(downloadingId: invoice.id);
    try {
      final response = await ref
          .read(httpClientProvider)
          .get(Uri.parse(invoice.pdfUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        state = const InvoiceDownloadState(
          error: 'That invoice couldn’t be fetched right now. Try again.',
        );
        return;
      }
      final dir = await ref.read(tempDirProvider)();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        'raajjepro-invoice-${invoice.invoiceNumber}.pdf',
      );
      await file.writeAsBytes(response.bodyBytes);
      await ref.read(shareDocumentProvider)(
        XFile(file.path, mimeType: 'application/pdf'),
        'RaajjePro invoice ${invoice.invoiceNumber}',
      );
      state = const InvoiceDownloadState();
    } on http.ClientException {
      state = const InvoiceDownloadState(
        error:
            'No connection — the invoice is safe, try again when you’re '
            'back online.',
      );
    } on SocketException {
      state = const InvoiceDownloadState(
        error:
            'No connection — the invoice is safe, try again when you’re '
            'back online.',
      );
    } on Object {
      // A timeout, a FileSystemException or a PlatformException from the share
      // channel: none is a billing failure, and the button must leave its
      // loading state either way.
      state = const InvoiceDownloadState(
        error: 'That invoice couldn’t be saved right now. Try again.',
      );
    }
  }

  void clearError() => state = const InvoiceDownloadState();
}
