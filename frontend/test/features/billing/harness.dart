import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';

/// Everything a billing test drives: the three reads the screens open with
/// (status, provider facts, listings), the picker and the presigned PUT.
class BillingHarness {
  BillingHarness() : api = FakeApiClient();

  final FakeApiClient api;
  final picker = FakeReceiptPicker();
  final uploader = FakeReceiptUploader();

  /// A fixed clock. 2026-09-15, 08:00 Malé.
  static final DateTime now = DateTime.utc(2026, 9, 15, 3);

  void script({
    Map<String, dynamic>? status,
    String verificationTier = 'silver',
    List<Map<String, dynamic>> listings = const [],
    List<Map<String, dynamic>>? invoices,
  }) {
    api.on(
      'GET',
      '/v1/providers/me/subscription',
      (_) => status ?? statusJson(),
    );
    api.on(
      'GET',
      '/v1/providers/me',
      (_) => {
        'id': 'provider-1',
        'userId': 'user-1',
        'businessName': 'Rasheed Home Services',
        'verificationTier': verificationTier,
        'verificationStatus': 'unverified',
        'acceptingNewCustomers': true,
        'suspended': false,
        'suspendedReason': null,
        'serviceAreas': const <Map<String, dynamic>>[],
        'onboardingComplete': true,
      },
    );
    api.on(
      'GET',
      '/v1/providers/me/listings?limit=50',
      (_) => {'_list': listings, '_meta': <String, dynamic>{}},
    );
    if (invoices != null) {
      api.on(
        'GET',
        '/v1/providers/me/invoices?limit=50',
        (_) => {'_list': invoices, '_meta': <String, dynamic>{}},
      );
    }
  }

  List<Override> get overrides => [
    apiClientProvider.overrideWithValue(api),
    clockProvider.overrideWithValue(() => now),
    mediaPickerProvider.overrideWithValue(picker),
    mediaUploaderProvider.overrideWithValue(uploader),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Map<String, WidgetBuilder> routes = const {},
  }) => pumpScreen(tester, screen, overrides: overrides, routes: routes);

  Iterable<({String method, String path, Object? body})> calls(String method) =>
      api.calls.where((c) => c.method == method);
}

/// `GET /v1/providers/me/subscription`, every field the server's
/// `toSubscriptionStatusDto` writes. Defaults to §1b's free tier for a
/// provider who has never trialled.
Map<String, dynamic> statusJson({
  String tier = 'free',
  String status = 'none',
  int? activeListingCap = 1,
  String? trialEndsAt,
  int? trialDaysRemaining,
  bool trialAvailable = true,
  String? anchorAt,
  String? currentPeriodEnd,
  int? billingDaysRemaining,
  int nextPaymentAmountLaari = 7500,
  int? priceLaari,
  bool introductory = true,
  String? introductoryConvertsAt,
  String? graceEndsAt,
  String nextPeriodStart = '2026-09-15T03:00:00.000Z',
  String nextPeriodEnd = '2026-10-15T03:00:00.000Z',
  bool paused = false,
  String? pausedAt,
  int cumulativePausedDays = 0,
  int remainingPauseAllowanceDays = 10,
  bool acceptingNewCustomers = true,
  String? downgradedAt,
  Map<String, dynamic>? latestSubmission,
  Object? bankTransfer = _defaultBank,
}) => {
  'tier': tier,
  'status': status,
  'entitlements': {
    'activeListingCap': activeListingCap,
    'analytics': tier == 'premium',
    'priorityPlacement': tier == 'premium',
  },
  'trial': {
    'startedAt': null,
    'endsAt': trialEndsAt,
    'daysRemaining': trialDaysRemaining,
    'available': trialAvailable,
  },
  'billing': {
    'anchorAt': anchorAt,
    'currentPeriodEnd': currentPeriodEnd,
    'daysRemaining': billingDaysRemaining,
    'nextPaymentAmountLaari': nextPaymentAmountLaari,
    'priceLaari': priceLaari,
    'introductory': introductory,
    'introductoryConvertsAt': introductoryConvertsAt,
    'graceEndsAt': graceEndsAt,
    'nextPeriod': {'start': nextPeriodStart, 'end': nextPeriodEnd},
  },
  'pause': {
    'paused': paused,
    'pausedAt': pausedAt,
    'cumulativePausedDays': cumulativePausedDays,
    'remainingPauseAllowanceDays': remainingPauseAllowanceDays,
    'forcedResumeDueAt': null,
  },
  'acceptingNewCustomers': acceptingNewCustomers,
  'downgradedAt': downgradedAt,
  'latestSubmission': latestSubmission,
  'bankTransfer': bankTransfer == _defaultBank ? bankJson() : bankTransfer,
};

const _defaultBank = Object();

Map<String, dynamic> bankJson() => {
  'bankName': 'Bank of Maldives',
  'accountName': 'RaajjePro Pvt Ltd',
  'accountNumber': '7730000123456',
};

/// One `PaymentSubmissionDto`.
Map<String, dynamic> submissionJson({
  String id = 'sub-1',
  int amountLaari = 7500,
  String referenceCode = 'RP-K7M2-9QXA',
  String status = 'pending',
  String? submittedAt,
  String? rejectionReason,
  String? reviewedAt,
  String? reversedAt,
  String? appealedAt,
  String? appealNote,
  bool proofUploaded = false,
  String createdAt = '2026-09-14T05:00:00.000Z',
}) => {
  'id': id,
  'purpose': 'subscription',
  'amountLaari': amountLaari,
  'referenceCode': referenceCode,
  'status': status,
  'submittedAt': submittedAt,
  'rejectionReason': rejectionReason,
  'reviewedAt': reviewedAt,
  'reversedAt': reversedAt,
  'appealedAt': appealedAt,
  'appealNote': appealNote,
  'proofUploaded': proofUploaded,
  'proofUrl': null,
  'createdAt': createdAt,
};

/// `POST …/upgrade-request`'s answer.
Map<String, dynamic> upgradeRequestJson({
  Map<String, dynamic>? submission,
  Object? bankTransfer = _defaultBank,
}) => {
  'submission': submission ?? submissionJson(),
  'bankTransfer': bankTransfer == _defaultBank ? bankJson() : bankTransfer,
  'period': {
    'start': '2026-09-15T03:00:00.000Z',
    'end': '2026-10-15T03:00:00.000Z',
  },
};

Map<String, dynamic> invoiceJson({
  String id = 'inv-1',
  String invoiceNumber = 'RP-000042',
  int amountLaari = 7500,
  String periodStart = '2026-08-13T03:00:00.000Z',
  String periodEnd = '2026-09-12T03:00:00.000Z',
  String issuedAt = '2026-08-12T05:30:00.000Z',
  String? voidedAt,
  String? voidedReason,
}) => {
  'id': id,
  'invoiceNumber': invoiceNumber,
  'amountLaari': amountLaari,
  'periodStart': periodStart,
  'periodEnd': periodEnd,
  'issuedAt': issuedAt,
  'pdfUrl': 'http://localhost:3000/v1/media/read/$id.pdf?sig=x',
  'voidedAt': voidedAt,
  'voidedReason': voidedReason,
};

Map<String, dynamic> billingListingJson({
  required String id,
  required String name,
  String visibility = 'active',
}) =>
    publishableListingJson(
        id: id,
        categoryId: 'cat-ac',
        status: 'published',
      ).cast<String, dynamic>()
      ..['name'] = name
      ..['visibility'] = visibility
      ..['missingRequiredFields'] = const <Map<String, dynamic>>[];

class FakeReceiptPicker implements MediaPicker {
  PickedImageResult? result;
  int calls = 0;

  static PickedImageResult picked() => PickedImageResult.picked(
    PickedImage(
      fileName: 'transfer-receipt.jpg',
      contentType: 'image/jpeg',
      bytes: Uint8List.fromList(List<int>.filled(412 * 1024, 7)),
    ),
  );

  @override
  Future<PickedImageResult> pickImage() async {
    calls++;
    return result ?? picked();
  }
}

class FakeReceiptUploader implements MediaUploader {
  int calls = 0;
  Object? throws;
  Uint8List? lastBytes;

  @override
  Future<void> put({
    required String url,
    required Map<String, String> headers,
    required Uint8List bytes,
  }) async {
    calls++;
    lastBytes = bytes;
    final failure = throws;
    if (failure != null) throw failure;
  }
}
