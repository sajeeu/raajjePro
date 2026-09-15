import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/billing/presentation/invoices_screen.dart';
import 'package:raajjepro/features/billing/presentation/pay_by_bank_transfer_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// `Pay by Bank Transfer.dc.html` — §1b's manual payment, steps 1–3 and 5,
/// as the provider performs them: the form, "pending confirmation",
/// and a rejection with its reason, resubmit and appeal.
void main() {
  late BillingHarness h;

  setUp(() => h = BillingHarness());

  String allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  Future<void> pumpPay(WidgetTester tester) => h.pump(
    tester,
    const PayByBankTransferScreen(),
    routes: {
      InvoicesScreen.routeName: (_) =>
          const Scaffold(body: Text('INVOICES SCREEN')),
      AppRoutes.legal: (_) => const Scaffold(body: Text('LEGAL SCREEN')),
    },
  );

  Iterable<String> posts() => h.calls('POST').map((c) => c.path);

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }

  /// The server after an intent exists: status reads carry it back.
  void scriptOpenIntent({Object? bankTransfer = const Object()}) {
    final bank = bankTransfer == const Object() ? bankJson() : bankTransfer;
    h.script(
      status: statusJson(
        latestSubmission: submissionJson(),
        bankTransfer: bank,
      ),
    );
  }

  group('the form', () {
    testWidgets(
      'with no open intent, one upgrade-request is made and the form renders from the status',
      (tester) async {
        h.script();
        h.api.on('POST', '/v1/providers/me/subscription/upgrade-request', (_) {
          // From here the status read carries the new intent.
          scriptOpenIntent();
          return upgradeRequestJson();
        });
        await pumpPay(tester);
        expect(
          posts().where((p) => p.endsWith('/upgrade-request')),
          hasLength(1),
        );
        expect(find.text('MVR 75'), findsOneWidget);
        expect(find.text('RP-K7M2-9QXA'), findsOneWidget);
        expect(find.text('Bank of Maldives'), findsOneWidget);
        expect(find.text('RaajjePro Pvt Ltd'), findsOneWidget);
        expect(find.text('7730000123456'), findsOneWidget);
        // The period is the server's, not a month.
        expect(
          find.textContaining('Premium · 30-day period · 15 Sep – 15 Oct'),
          findsOneWidget,
        );
        expect(find.textContaining('Your introductory rate.'), findsOneWidget);
      },
    );

    testWidgets(
      'an open intent is resumed, not replaced — no second reference code',
      (tester) async {
        scriptOpenIntent();
        await pumpPay(tester);
        expect(posts().where((p) => p.endsWith('/upgrade-request')), isEmpty);
        expect(find.text('RP-K7M2-9QXA'), findsOneWidget);
      },
    );

    testWidgets(
      'unconfigured bank details: a plain notice, no invented account, submit disabled',
      (tester) async {
        scriptOpenIntent(bankTransfer: null);
        h.picker.result = FakeReceiptPicker.picked();
        await pumpPay(tester);
        expect(
          find.textContaining('Bank details aren’t available yet'),
          findsOneWidget,
        );
        expect(find.textContaining('Bank of Maldives'), findsNothing);
        final text = allText(tester);
        // No digit string that could be read as an account number.
        expect(RegExp(r'\d{7,}').hasMatch(text), isFalse);
        await scrollTo(
          tester,
          find.text('Add a photo or screenshot of the receipt'),
        );
        await tester.tap(find.text('Add a photo or screenshot of the receipt'));
        await settle(tester);
        await scrollTo(tester, find.text('I’ve sent the transfer'));
        final submit = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'I’ve sent the transfer'),
        );
        expect(submit.onPressed, isNull);
      },
    );

    testWidgets(
      'submit is disabled until a receipt is attached, then runs the three steps and lands on pending',
      (tester) async {
        scriptOpenIntent();
        h.api.on(
          'POST',
          '/v1/providers/me/payment-submissions/sub-1/proof',
          (_) => {
            'submission': submissionJson(),
            'upload': {
              'url': 'http://localhost:3000/v1/media/uploads?token=abc',
              'method': 'PUT',
              'headers': {'content-type': 'image/jpeg'},
              'expiresAt': '2026-09-15T04:00:00.000Z',
              'maxBytes': 10485760,
            },
          },
        );
        h.api.on('POST', '/v1/providers/me/payment-submissions/sub-1/submit', (
          _,
        ) {
          h.script(
            status: statusJson(
              latestSubmission: submissionJson(
                submittedAt: '2026-09-15T03:00:00.000Z',
                proofUploaded: true,
              ),
            ),
          );
          return submissionJson(
            submittedAt: '2026-09-15T03:00:00.000Z',
            proofUploaded: true,
          );
        });
        await pumpPay(tester);

        AppButton submitButton() => tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'I’ve sent the transfer'),
        );
        await scrollTo(tester, find.text('I’ve sent the transfer'));
        expect(submitButton().onPressed, isNull);

        await scrollTo(
          tester,
          find.text('Add a photo or screenshot of the receipt'),
        );
        await tester.tap(find.text('Add a photo or screenshot of the receipt'));
        await settle(tester);
        expect(find.text('transfer-receipt.jpg'), findsOneWidget);
        expect(find.textContaining('412 KB'), findsOneWidget);
        expect(submitButton().onPressed, isNotNull);

        await scrollTo(tester, find.text('I’ve sent the transfer'));
        await tester.tap(find.text('I’ve sent the transfer'));
        await settle(tester);

        // §1b step 3, the client's side: target, PUT straight to the store,
        // then submit. The PUT never goes through the API client.
        expect(
          posts(),
          contains('/v1/providers/me/payment-submissions/sub-1/proof'),
        );
        expect(h.uploader.calls, 1);
        expect(h.uploader.lastBytes, isNotNull);
        expect(
          posts(),
          contains('/v1/providers/me/payment-submissions/sub-1/submit'),
        );
        expect(h.calls('PUT'), isEmpty);

        // The submitted state: pending, and honest about what it grants.
        expect(find.text('Pending confirmation'), findsOneWidget);
        expect(
          find.textContaining('Pending grants nothing yet'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Submitted 15 Sep 2026, 08:00'),
          findsOneWidget,
        );
        expect(find.textContaining('RP-K7M2-9QXA'), findsOneWidget);
        final text = allText(tester).toLowerCase();
        expect(text, isNot(contains('activated')));
        expect(text, isNot(contains('verified')));
      },
    );

    testWidgets(
      'offline on submit: the form stays, the receipt stays, nothing is queued',
      (tester) async {
        scriptOpenIntent();
        h.api.offline(
          'POST',
          '/v1/providers/me/payment-submissions/sub-1/proof',
        );
        await pumpPay(tester);
        await scrollTo(
          tester,
          find.text('Add a photo or screenshot of the receipt'),
        );
        await tester.tap(find.text('Add a photo or screenshot of the receipt'));
        await settle(tester);
        await scrollTo(tester, find.text('I’ve sent the transfer'));
        await tester.tap(find.text('I’ve sent the transfer'));
        await settle(tester);

        expect(
          find.textContaining('No connection — nothing was sent'),
          findsOneWidget,
        );
        expect(find.text('transfer-receipt.jpg'), findsOneWidget);
        expect(find.text('I’ve sent the transfer'), findsOneWidget);
        // §0.0 item 14: never "saved on this phone — sends on reconnect".
        final text = allText(tester).toLowerCase();
        expect(text, isNot(contains('sends on reconnect')));
        expect(text, isNot(contains('saved on this phone')));
        expect(find.byType(StatusBadge), findsNothing);
        expect(h.uploader.calls, 0);

        // A live retry, once the connection is back.
        h.api.on(
          'POST',
          '/v1/providers/me/payment-submissions/sub-1/proof',
          (_) => {
            'submission': submissionJson(),
            'upload': {
              'url': 'http://localhost:3000/v1/media/uploads?token=abc',
              'method': 'PUT',
              'headers': <String, String>{},
              'expiresAt': '2026-09-15T04:00:00.000Z',
              'maxBytes': 10485760,
            },
          },
        );
        h.api.on('POST', '/v1/providers/me/payment-submissions/sub-1/submit', (
          _,
        ) {
          h.script(
            status: statusJson(
              latestSubmission: submissionJson(
                submittedAt: '2026-09-15T03:05:00.000Z',
                proofUploaded: true,
              ),
            ),
          );
          return submissionJson(submittedAt: '2026-09-15T03:05:00.000Z');
        });
        await tester.tap(find.text('Try again'));
        await settle(tester);
        expect(find.text('Pending confirmation'), findsOneWidget);
      },
    );

    testWidgets(
      'a server refusal on submit is said inline and keeps the form',
      (tester) async {
        scriptOpenIntent();
        h.api.on(
          'POST',
          '/v1/providers/me/payment-submissions/sub-1/proof',
          (_) => {
            'submission': submissionJson(),
            'upload': {
              'url': 'http://localhost:3000/v1/media/uploads?token=abc',
              'method': 'PUT',
              'headers': <String, String>{},
              'expiresAt': '2026-09-15T04:00:00.000Z',
              'maxBytes': 10485760,
            },
          },
        );
        h.api.fail(
          'POST',
          '/v1/providers/me/payment-submissions/sub-1/submit',
          status: 422,
          code: 'MEDIA_TYPE_NOT_ACCEPTED',
          message: 'That file is not an image we accept',
        );
        await pumpPay(tester);
        await scrollTo(
          tester,
          find.text('Add a photo or screenshot of the receipt'),
        );
        await tester.tap(find.text('Add a photo or screenshot of the receipt'));
        await settle(tester);
        await scrollTo(tester, find.text('I’ve sent the transfer'));
        await tester.tap(find.text('I’ve sent the transfer'));
        await settle(tester);
        expect(
          find.text('That file is not an image we accept'),
          findsOneWidget,
        );
        expect(find.text('transfer-receipt.jpg'), findsOneWidget);
      },
    );

    testWidgets('a refused picker result is said, a cancel says nothing', (
      tester,
    ) async {
      scriptOpenIntent();
      h.picker.result = const PickedImageResult.failed(PickFailure.tooLarge);
      await pumpPay(tester);
      await scrollTo(
        tester,
        find.text('Add a photo or screenshot of the receipt'),
      );
      await tester.tap(find.text('Add a photo or screenshot of the receipt'));
      await settle(tester);
      expect(find.textContaining('over 10 MB'), findsOneWidget);
      h.picker.result = const PickedImageResult.failed(PickFailure.cancelled);
      await tester.tap(find.text('Add a photo or screenshot of the receipt'));
      await settle(tester);
      expect(find.byType(SnackBar), findsOneWidget); // still the earlier one
    });

    testWidgets('copy puts the value on the clipboard and says so', (
      tester,
    ) async {
      scriptOpenIntent();
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      await pumpPay(tester);
      await scrollTo(tester, find.bySemanticsLabel('Copy Reference code'));
      await tester.tap(find.bySemanticsLabel('Copy Reference code'));
      await settle(tester);
      expect(copied, ['RP-K7M2-9QXA']);
      expect(find.text('Reference code copied'), findsOneWidget);
    });

    testWidgets(
      'the Provider Agreement row is marked as a placeholder and reaches Legal',
      (tester) async {
        scriptOpenIntent();
        await pumpPay(tester);
        await scrollTo(
          tester,
          find.textContaining('[placeholder — draft terms, not final policy]'),
        );
        expect(
          find.textContaining('[placeholder — draft terms, not final policy]'),
          findsOneWidget,
        );
        await scrollTo(
          tester,
          find.text('Paying accepts the Provider Agreement'),
        );
        await tester.tap(find.text('Paying accepts the Provider Agreement'));
        await settle(tester);
        expect(find.text('LEGAL SCREEN'), findsOneWidget);
      },
    );

    testWidgets(
      'opening the intent offline shows the no-connection state with a live retry',
      (tester) async {
        h.script();
        h.api.offline('POST', '/v1/providers/me/subscription/upgrade-request');
        await pumpPay(tester);
        expect(find.byType(NoConnectionView), findsOneWidget);
      },
    );
  });

  group('pending', () {
    testWidgets(
      'a submitted payment opens straight onto pending, and reaches Invoices',
      (tester) async {
        h.script(
          status: statusJson(
            latestSubmission: submissionJson(
              submittedAt: '2026-09-14T09:20:00.000Z',
              proofUploaded: true,
            ),
          ),
        );
        await pumpPay(tester);
        expect(posts(), isEmpty);
        expect(find.text('Pending confirmation'), findsOneWidget);
        expect(
          find.textContaining('Submitted 14 Sep 2026, 14:20'),
          findsOneWidget,
        );
        await tester.tap(
          find.text('Once confirmed, the invoice appears in Invoices'),
        );
        await settle(tester);
        expect(find.text('INVOICES SCREEN'), findsOneWidget);
      },
    );
  });

  group('rejected — reason, resubmit, appeal', () {
    Map<String, dynamic> rejected({String? appealedAt}) => statusJson(
      latestSubmission: submissionJson(
        status: 'rejected',
        submittedAt: '2026-09-14T09:20:00.000Z',
        reviewedAt: '2026-09-14T12:00:00.000Z',
        rejectionReason:
            'The transfer received under RP-K7M2-9QXA is MVR 57 — the period '
            'costs MVR 75. Send the remaining MVR 18 and upload the receipt '
            'again.',
        proofUploaded: true,
        appealedAt: appealedAt,
      ),
    );

    testWidgets('the admin’s reason is shown verbatim with both actions', (
      tester,
    ) async {
      h.script(status: rejected());
      await pumpPay(tester);
      expect(
        find.text('Transfer not confirmed — the admin wrote:'),
        findsOneWidget,
      );
      expect(
        find.textContaining('MVR 57 — the period costs MVR 75'),
        findsOneWidget,
      );
      expect(find.text('Resubmit now'), findsOneWidget);
      expect(find.text('Appeal'), findsOneWidget);
      // Root CLAUDE.md: second-admin sign-off is out of scope, so no promise
      // of a second person.
      expect(allText(tester).toLowerCase(), isNot(contains('second person')));
      expect(find.textContaining('no waiting period'), findsOneWidget);
    });

    testWidgets(
      'Resubmit now opens a fresh intent immediately and leaves the rejected row alone',
      (tester) async {
        h.script(status: rejected());
        h.api.on('POST', '/v1/providers/me/subscription/upgrade-request', (_) {
          h.script(
            status: statusJson(
              latestSubmission: submissionJson(
                id: 'sub-2',
                referenceCode: 'RP-B3ND-7WKF',
              ),
            ),
          );
          return upgradeRequestJson(
            submission: submissionJson(
              id: 'sub-2',
              referenceCode: 'RP-B3ND-7WKF',
            ),
          );
        });
        await pumpPay(tester);
        await tester.tap(find.text('Resubmit now'));
        await settle(tester);
        expect(
          posts().where((p) => p.endsWith('/upgrade-request')),
          hasLength(1),
        );
        expect(find.text('RP-B3ND-7WKF'), findsOneWidget);
        expect(find.text('I’ve sent the transfer'), findsOneWidget);
        // Nothing was posted against the rejected submission.
        expect(posts().where((p) => p.contains('/sub-1/')), isEmpty);
      },
    );

    testWidgets(
      'Appeal files a re-review with an optional note and shows it as sent',
      (tester) async {
        h.script(status: rejected());
        Object? appealBody;
        h.api.on('POST', '/v1/providers/me/payment-submissions/sub-1/appeal', (
          body,
        ) {
          appealBody = body;
          h.script(status: rejected(appealedAt: '2026-09-15T03:00:00.000Z'));
          return submissionJson(
            status: 'rejected',
            appealedAt: '2026-09-15T03:00:00.000Z',
            appealNote: 'The second line shows MVR 75',
          );
        });
        await pumpPay(tester);
        await tester.tap(find.text('Appeal'));
        await settle(tester);
        expect(find.text('Appeal this decision'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'The second line shows MVR 75',
        );
        await tester.tap(find.text('Send appeal'));
        await settle(tester);

        expect(appealBody, {'note': 'The second line shows MVR 75'});
        expect(find.text('Appeal sent'), findsOneWidget);
        expect(
          find.textContaining('look at this payment again'),
          findsOneWidget,
        );
        // Once appealed, the appeal button is gone; resubmit stays.
        expect(find.text('Appeal'), findsNothing);
        expect(find.text('Resubmit now'), findsOneWidget);
      },
    );

    testWidgets('an appeal with no note sends no body', (tester) async {
      h.script(status: rejected());
      Object? appealBody = 'unset';
      h.api.on('POST', '/v1/providers/me/payment-submissions/sub-1/appeal', (
        body,
      ) {
        appealBody = body;
        h.script(status: rejected(appealedAt: '2026-09-15T03:00:00.000Z'));
        return submissionJson(
          status: 'rejected',
          appealedAt: '2026-09-15T03:00:00.000Z',
        );
      });
      await pumpPay(tester);
      await tester.tap(find.text('Appeal'));
      await settle(tester);
      await tester.tap(find.text('Send appeal'));
      await settle(tester);
      expect(appealBody, isNull);
      expect(find.text('Appeal sent'), findsOneWidget);
    });

    testWidgets('a refused appeal says the server’s reason', (tester) async {
      h.script(status: rejected());
      h.api.fail(
        'POST',
        '/v1/providers/me/payment-submissions/sub-1/appeal',
        status: 422,
        code: 'PAYMENT_APPEAL_ALREADY_FILED',
        message:
            'You have already asked for this payment to be looked at again',
      );
      await pumpPay(tester);
      await tester.tap(find.text('Appeal'));
      await settle(tester);
      await tester.tap(find.text('Send appeal'));
      await settle(tester);
      expect(
        find.textContaining('already asked for this payment'),
        findsOneWidget,
      );
    });

    testWidgets('a reversal reads as reversed and is appealable', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          latestSubmission: submissionJson(
            status: 'rejected',
            submittedAt: '2026-09-01T09:20:00.000Z',
            reversedAt: '2026-09-14T12:00:00.000Z',
            rejectionReason: 'Bank reversed the transfer three days later',
          ),
        ),
      );
      await pumpPay(tester);
      expect(find.text('Transfer reversed — the admin wrote:'), findsOneWidget);
      expect(find.text('Appeal'), findsOneWidget);
    });
  });

  group('design rules', () {
    testWidgets('no control is swallowed by a tappable wrapper', (
      tester,
    ) async {
      scriptOpenIntent();
      await pumpPay(tester);
      await tester.tap(find.text('Add a photo or screenshot of the receipt'));
      await settle(tester);
      expectNoSwallowedControls(tester);
    });

    testWidgets('the form enters in steps', (tester) async {
      scriptOpenIntent();
      await pumpPay(tester);
      final steps = <int>{};
      for (var i = 0; i < 8; i++) {
        steps.addAll(
          tester.widgetList<FadeUp>(find.byType(FadeUp)).map((f) => f.index),
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await settle(tester);
      }
      expect(steps, containsAll([0, 1, 2, 3, 4]));
    });
  });
}
