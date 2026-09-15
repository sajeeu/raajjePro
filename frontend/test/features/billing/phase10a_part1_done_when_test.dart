import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/features/billing/presentation/billing_screen.dart';
import 'package:raajjepro/features/billing/presentation/invoices_screen.dart';
import 'package:raajjepro/features/billing/presentation/pay_by_bank_transfer_screen.dart';
import 'package:raajjepro/features/my_services/presentation/my_services_screen.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/listings.dart' show sampleCategories;
import '../../helpers/pump.dart';
import '../my_services/harness.dart' show providerJson;
import '../profile/helpers.dart';
import 'harness.dart';

/// §Phase 10a's Done-when, the part 1 half, through the **real app and its
/// real route table**:
///
/// > a provider submits with proof and sees pending; … a rejection surfaces
/// > its reason with working resubmit and appeal
///
/// Plus the routing claim: the Billing tab on My Services, which has pointed
/// at `/provider/billing` since §Phase 10, now lands on a real screen rather
/// than the placeholder that owed it.
///
/// The other half — "an admin confirms and the entitlement activates", "CSV
/// import proposes correct matches", the XSS payloads, the aged
/// `payment_unresolved` alert — is part 2's and is not asserted here. The
/// phase stays open until it is.
void main() {
  late FakeApiClient api;
  late InMemoryTokenStore store;
  final picker = FakeReceiptPicker();
  final uploader = FakeReceiptUploader();
  var bootCount = 0;

  setUp(() {
    api = FakeApiClient();
    store = InMemoryTokenStore();
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': <Object>[]});
    api.on(
      'GET',
      '/v1/providers/me',
      (_) => providerJson(verificationTier: 'silver'),
    );
    api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
    api.on(
      'GET',
      '/v1/providers/me/listings?limit=50',
      (_) => {
        '_list': [billingListingJson(id: 'l-1', name: 'AC Service & Repair')],
        '_meta': <String, dynamic>{},
      },
    );
    api.on('GET', '/v1/providers/me/subscription', (_) => statusJson());
  });

  Future<NavigatorState> bootToBilling(WidgetTester tester) async {
    api.on(
      'GET',
      '/v1/users/me/profile-summary',
      (_) => profileSummaryJson(
        isProvider: true,
        providerOnboardingComplete: true,
      ),
    );
    await store.write(TokenPair.fromJson(tokensJson()));
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey(bootCount++),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
          crashReporterProvider.overrideWithValue(NoopCrashReporter()),
          deviceNameProvider.overrideWith((_) async => 'Test'),
          mediaPickerProvider.overrideWithValue(picker),
          mediaUploaderProvider.overrideWithValue(uploader),
        ],
        child: const RaajjeProApp(),
      ),
    );
    await settle(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(nav.pushNamed<void>(ProfileScreen.routeName));
    await settle(tester);
    await tester.ensureVisible(find.text('Switch to providing'));
    await tester.tap(find.text('Switch to providing'));
    await settle(tester);
    await tester.tap(find.text('Provider'));
    await settle(tester);
    expect(find.byType(MyServicesScreen), findsOneWidget);

    // The Billing tab — §Phase 10's nav item, pointing at §Phase 10a's route.
    await tester.tap(find.text('Billing'));
    await settle(tester);
    expect(find.byType(BillingScreen), findsOneWidget);
    expect(find.byType(UnbuiltScreen), findsNothing);
    return nav;
  }

  testWidgets(
    'a provider submits with proof and sees pending — through the real routes',
    (tester) async {
      api.on(
        'GET',
        '/v1/providers/me/subscription',
        (_) => statusJson(trialAvailable: false),
      );
      api.on('POST', '/v1/providers/me/subscription/upgrade-request', (_) {
        api.on(
          'GET',
          '/v1/providers/me/subscription',
          (_) => statusJson(
            trialAvailable: false,
            latestSubmission: submissionJson(),
          ),
        );
        return upgradeRequestJson();
      });
      api.on(
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
      api.on('POST', '/v1/providers/me/payment-submissions/sub-1/submit', (_) {
        api.on(
          'GET',
          '/v1/providers/me/subscription',
          (_) => statusJson(
            trialAvailable: false,
            latestSubmission: submissionJson(
              submittedAt: '2026-09-15T03:00:00.000Z',
              proofUploaded: true,
            ),
          ),
        );
        return submissionJson(submittedAt: '2026-09-15T03:00:00.000Z');
      });

      await bootToBilling(tester);
      await tester.tap(find.text('Pay by bank transfer'));
      await settle(tester);
      expect(find.byType(PayByBankTransferScreen), findsOneWidget);
      expect(find.text('RP-K7M2-9QXA'), findsOneWidget);

      await tester.ensureVisible(
        find.text('Add a photo or screenshot of the receipt'),
      );
      await settle(tester);
      await tester.tap(find.text('Add a photo or screenshot of the receipt'));
      await settle(tester);
      await tester.ensureVisible(find.text('I’ve sent the transfer'));
      await settle(tester);
      await tester.tap(find.text('I’ve sent the transfer'));
      await settle(tester);

      expect(find.text('Pending confirmation'), findsOneWidget);
      expect(find.textContaining('Pending grants nothing yet'), findsOneWidget);
      // §1b: the status the screen renders is still the free tier — a
      // pending submission produced entitlements identical to no payment.
      await tester.tap(find.bySemanticsLabel('Back to Billing'));
      await settle(tester);
      expect(find.byType(BillingScreen), findsOneWidget);
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.textContaining('pending confirmation'), findsWidgets);
    },
  );

  testWidgets(
    'a rejection surfaces its reason with working resubmit and appeal',
    (tester) async {
      Map<String, dynamic> rejected({String? appealedAt}) => statusJson(
        trialAvailable: false,
        latestSubmission: submissionJson(
          status: 'rejected',
          submittedAt: '2026-09-14T09:20:00.000Z',
          rejectionReason: 'MVR 57 arrived — the period costs MVR 75',
          appealedAt: appealedAt,
        ),
      );
      api.on('GET', '/v1/providers/me/subscription', (_) => rejected());
      Object? appealBody;
      api.on('POST', '/v1/providers/me/payment-submissions/sub-1/appeal', (
        body,
      ) {
        appealBody = body;
        api.on(
          'GET',
          '/v1/providers/me/subscription',
          (_) => rejected(appealedAt: '2026-09-15T03:00:00.000Z'),
        );
        return submissionJson(
          status: 'rejected',
          appealedAt: '2026-09-15T03:00:00.000Z',
        );
      });
      api.on('POST', '/v1/providers/me/subscription/upgrade-request', (_) {
        api.on(
          'GET',
          '/v1/providers/me/subscription',
          (_) => statusJson(
            trialAvailable: false,
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

      await bootToBilling(tester);
      // The Billing screen names the rejection and leads to it.
      expect(find.textContaining('wasn’t confirmed'), findsOneWidget);
      await tester.tap(find.text('View'));
      await settle(tester);
      expect(find.byType(PayByBankTransferScreen), findsOneWidget);
      expect(find.textContaining('MVR 57 arrived'), findsOneWidget);

      // Appeal: a re-review request on the same row (P8A-1).
      await tester.tap(find.text('Appeal'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField),
        'Please look at the second line',
      );
      await tester.tap(find.text('Send appeal'));
      await settle(tester);
      expect(appealBody, {'note': 'Please look at the second line'});
      expect(find.text('Appeal sent'), findsOneWidget);

      // Resubmit: a fresh intent, immediately, with a new reference code.
      await tester.tap(find.text('Resubmit now'));
      await settle(tester);
      expect(find.text('RP-B3ND-7WKF'), findsOneWidget);
      expect(find.text('I’ve sent the transfer'), findsOneWidget);
    },
  );

  testWidgets('the invoice list is one action from Billing', (tester) async {
    api.on(
      'GET',
      '/v1/providers/me/invoices?limit=50',
      (_) => {
        '_list': [invoiceJson()],
        '_meta': <String, dynamic>{},
      },
    );
    await bootToBilling(tester);
    await tester.scrollUntilVisible(
      find.text('Invoices'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester);
    await tester.tap(find.text('Invoices'));
    await settle(tester);
    expect(find.byType(InvoicesScreen), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
  });
}
