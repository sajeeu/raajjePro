import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/files/share_file.dart';
import 'package:raajjepro/features/billing/controller/invoices_controller.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';
import 'package:raajjepro/features/billing/presentation/invoices_screen.dart';
import 'package:raajjepro/shared/shared.dart';
import 'package:share_plus/share_plus.dart';

import '../../helpers/a11y.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// `Invoices.dc.html` — one per confirmed payment, with a PDF each.
void main() {
  late BillingHarness h;

  setUp(() => h = BillingHarness());

  List<Map<String, dynamic>> four() => [
    invoiceJson(
      id: 'inv-4',
      invoiceNumber: 'RP-000042',
      periodStart: '2026-08-13T03:00:00.000Z',
      periodEnd: '2026-09-12T03:00:00.000Z',
      issuedAt: '2026-08-12T05:30:00.000Z',
    ),
    invoiceJson(
      id: 'inv-3',
      invoiceNumber: 'RP-000031',
      periodStart: '2026-07-14T03:00:00.000Z',
      periodEnd: '2026-08-13T03:00:00.000Z',
      issuedAt: '2026-07-13T05:30:00.000Z',
    ),
    invoiceJson(
      id: 'inv-2',
      invoiceNumber: 'RP-000019',
      periodStart: '2026-06-14T03:00:00.000Z',
      periodEnd: '2026-07-14T03:00:00.000Z',
      issuedAt: '2026-06-13T05:30:00.000Z',
    ),
    invoiceJson(
      id: 'inv-1',
      invoiceNumber: 'RP-000007',
      periodStart: '2026-05-15T03:00:00.000Z',
      periodEnd: '2026-06-14T03:00:00.000Z',
      issuedAt: '2026-05-14T05:30:00.000Z',
    ),
  ];

  group('the four states', () {
    testWidgets('a skeleton, then the list', (tester) async {
      h.script(invoices: four());
      h.api.gate = Completer<void>();
      await h.pump(tester, const InvoicesScreen());
      expect(find.bySemanticsLabel('Loading your invoices'), findsOneWidget);
      h.api.gate!.complete();
      await settle(tester);
      expect(find.text('MVR 300'), findsOneWidget);
    });

    testWidgets('an error keeps the records safe and retries', (tester) async {
      h.script();
      h.api.fail(
        'GET',
        '/v1/providers/me/invoices?limit=50',
        status: 500,
        code: 'INTERNAL',
      );
      await h.pump(tester, const InvoicesScreen());
      expect(find.text('Couldn’t load your invoices'), findsOneWidget);
      expect(find.textContaining('payment records are safe'), findsOneWidget);
      h.script(invoices: four());
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('MVR 300'), findsOneWidget);
    });

    testWidgets('empty names what happens next and goes back to Billing', (
      tester,
    ) async {
      h.script(invoices: const []);
      await h.pump(tester, const InvoicesScreen());
      expect(find.text('No payments yet'), findsOneWidget);
      expect(
        find.textContaining('When a bank transfer is confirmed'),
        findsOneWidget,
      );
      expect(find.text('Go to Billing'), findsOneWidget);
    });

    testWidgets(
      'populated: the total, the count since the first, and the rows',
      (tester) async {
        h.script(
          status: statusJson(introductory: true, priceLaari: 7500),
          invoices: four(),
        );
        await h.pump(tester, const InvoicesScreen());
        expect(find.text('MVR 300'), findsOneWidget);
        expect(
          find.text('4 confirmed payments since 14 May 2026'),
          findsOneWidget,
        );
        expect(find.text('Intro rate'), findsOneWidget);
        expect(find.text('12 Aug 2026'), findsOneWidget);
        expect(find.text('Covers 13 Aug – 12 Sep'), findsOneWidget);
        // The first row opens by default, with its number and download.
        expect(find.text('RP-000042'), findsOneWidget);
        expect(find.text('Download PDF'), findsOneWidget);
        expect(
          find.textContaining('your rate, not a list price'),
          findsOneWidget,
        );
      },
    );
  });

  group('rows', () {
    testWidgets('tapping a row opens it and closes the other', (tester) async {
      h.script(invoices: four());
      await h.pump(tester, const InvoicesScreen());
      expect(find.text('RP-000042'), findsOneWidget);
      await tester.tap(find.text('13 Jul 2026'));
      await settle(tester);
      expect(find.text('RP-000031'), findsOneWidget);
      expect(find.text('RP-000042'), findsNothing);
    });

    testWidgets('a voided invoice stays listed, says so, and is not counted', (
      tester,
    ) async {
      h.script(
        invoices: [
          invoiceJson(
            id: 'inv-2',
            invoiceNumber: 'RP-000031',
            issuedAt: '2026-07-13T05:30:00.000Z',
            voidedAt: '2026-07-16T05:30:00.000Z',
            voidedReason: 'Bank reversed the transfer',
          ),
          invoiceJson(id: 'inv-1', invoiceNumber: 'RP-000007'),
        ],
      );
      await h.pump(tester, const InvoicesScreen());
      expect(find.text('Voided'), findsOneWidget);
      expect(find.textContaining('Bank reversed the transfer'), findsOneWidget);
      expect(find.text('MVR 75'), findsWidgets);
      expect(
        find.text('1 confirmed payment since 13 Jul 2026'),
        findsOneWidget,
      );
    });

    testWidgets('a failed download is said, and the button comes back', (
      tester,
    ) async {
      h.script(invoices: four());
      final client = MockClient((_) async => http.Response('gone', 410));
      await pumpScreen(
        tester,
        const InvoicesScreen(),
        overrides: [
          ...h.overrides,
          httpClientProvider.overrideWithValue(client),
        ],
      );
      await tester.tap(find.text('Download PDF'));
      await tester.pump();
      // The fetch and the file write are real async work; let them finish
      // under real time, then return to the fake clock to settle.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await settle(tester);
      expect(find.textContaining('couldn’t be fetched'), findsOneWidget);
      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Download PDF'),
      );
      expect(button.loading, isFalse);
    });
  });

  group('design rules', () {
    testWidgets('the row header is tappable and its controls live outside it', (
      tester,
    ) async {
      h.script(invoices: four());
      await h.pump(tester, const InvoicesScreen());
      expectNoSwallowedControls(tester);
      expect(find.bySemanticsLabel('Copy Invoice number'), findsOneWidget);
    });

    testWidgets('the list enters in steps', (tester) async {
      h.script(invoices: four());
      await h.pump(tester, const InvoicesScreen());
      final indices = tester
          .widgetList<FadeUp>(find.byType(FadeUp))
          .map((f) => f.index)
          .toSet();
      expect(indices.length, greaterThanOrEqualTo(4));
    });
  });

  /// The download itself, through a real [ProviderContainer].
  ///
  /// Not a widget test: it writes a real file, and `dart:io` work started
  /// inside a widget test's fake-async zone never completes — the same
  /// reason §Phase 3's data export exercises `request()` here rather than
  /// through a tap (`test/features/account/download_data_test.dart`).
  group('the download itself', () {
    test(
      'fetches the signed URL outside the API client and shares the file',
      () async {
        final api = FakeApiClient();
        final fetched = <Uri>[];
        final shared = <(XFile, String)>[];
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            httpClientProvider.overrideWithValue(
              MockClient((request) async {
                fetched.add(request.url);
                return http.Response.bytes(
                  [0x25, 0x50, 0x44, 0x46],
                  200,
                  headers: {'content-type': 'application/pdf'},
                );
              }),
            ),
            tempDirProvider.overrideWithValue(() async => Directory.systemTemp),
            shareDocumentProvider.overrideWithValue((file, subject) async {
              shared.add((file, subject));
            }),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(invoiceDownloadProvider.notifier)
            .download(Invoice.fromJson(invoiceJson()));

        // The signed URL is fetched as it stands, and never through
        // `ApiClient` — no bearer token, no envelope decode and no session
        // refresh on a URL whose signature *is* the authorization.
        expect(fetched.single.path, endsWith('/inv-1.pdf'));
        expect(fetched.single.queryParameters['sig'], 'x');
        expect(api.calls, isEmpty);

        expect(shared, hasLength(1));
        expect(
          shared.single.$1.path,
          endsWith('raajjepro-invoice-RP-000042.pdf'),
        );
        expect(shared.single.$1.mimeType, 'application/pdf');
        expect(shared.single.$2, 'RaajjePro invoice RP-000042');
        expect(await File(shared.single.$1.path).readAsBytes(), [
          0x25,
          0x50,
          0x44,
          0x46,
        ]);
        expect(container.read(invoiceDownloadProvider).downloadingId, isNull);
        expect(container.read(invoiceDownloadProvider).error, isNull);
      },
    );

    test('a refused fetch is reported and nothing is shared', () async {
      var shares = 0;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(FakeApiClient()),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('gone', 410)),
          ),
          tempDirProvider.overrideWithValue(() async => Directory.systemTemp),
          shareDocumentProvider.overrideWithValue((_, _) async => shares++),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(invoiceDownloadProvider.notifier)
          .download(Invoice.fromJson(invoiceJson()));

      expect(shares, 0);
      expect(container.read(invoiceDownloadProvider).error, isNotNull);
      expect(container.read(invoiceDownloadProvider).downloadingId, isNull);
    });

    test('a filesystem failure leaves no row spinning forever', () async {
      // The same class of defect §Phase 3's final review #7 found: a failure
      // from a seam that is neither an API error nor a network error must
      // still clear the loading state.
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(FakeApiClient()),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response.bytes([0x25], 200)),
          ),
          tempDirProvider.overrideWithValue(
            () async => throw const FileSystemException('No space left'),
          ),
          shareDocumentProvider.overrideWithValue((_, _) async {}),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(invoiceDownloadProvider.notifier)
          .download(Invoice.fromJson(invoiceJson()));

      expect(container.read(invoiceDownloadProvider).downloadingId, isNull);
      expect(container.read(invoiceDownloadProvider).error, isNotNull);
    });
  });
}
