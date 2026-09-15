/// The wire shapes of §Phase 8a's billing endpoints, parsed as the billing
/// screens read them (`backend/src/modules/subscriptions/types.ts`).
///
/// **No rule is computed here.** Round 19 (§Phase 23) requires the billing
/// UI to sit "behind a boundary thin enough to re-render on the web — no
/// billing logic in Flutter widgets", and invariant 4 puts every rule on the
/// server anyway. So the anchor arithmetic, the grace end, the next period,
/// the price cohort and the pause budget all arrive as fields and are
/// rendered as they came. A screen that needs a date the server does not send
/// asks for the field, not for the formula.
library;

import 'package:raajjepro/core/domain/verification_tier.dart';

/// `ProviderSubscription.status` plus `none` for a provider with no row at
/// all — which §Phase 8a answers as the free tier rather than a 404.
enum SubscriptionStatus {
  none('none'),
  trialing('trialing'),
  active('active'),
  paused('paused'),
  expired('expired'),
  free('free');

  const SubscriptionStatus(this.wire);
  final String wire;

  static SubscriptionStatus parse(String? value) =>
      SubscriptionStatus.values.firstWhere(
        (v) => v.wire == value,
        orElse: () => SubscriptionStatus.none,
      );
}

enum PaymentSubmissionStatus {
  pending('pending'),
  confirmed('confirmed'),
  rejected('rejected');

  const PaymentSubmissionStatus(this.wire);
  final String wire;

  static PaymentSubmissionStatus parse(String? value) =>
      PaymentSubmissionStatus.values.firstWhere(
        (v) => v.wire == value,
        orElse: () => PaymentSubmissionStatus.pending,
      );
}

/// One `PaymentSubmission`, as the provider is allowed to see it. There is no
/// field for the admin's identity, the proof's object key or anyone's phone
/// number, because the wire has none.
class PaymentSubmission {
  const PaymentSubmission({
    required this.id,
    required this.purpose,
    required this.amountLaari,
    required this.referenceCode,
    required this.status,
    required this.submittedAt,
    required this.rejectionReason,
    required this.reviewedAt,
    required this.reversedAt,
    required this.appealedAt,
    required this.appealNote,
    required this.proofUploaded,
    required this.createdAt,
  });

  factory PaymentSubmission.fromJson(Map<String, dynamic> json) =>
      PaymentSubmission(
        id: json['id'] as String,
        purpose: json['purpose'] as String? ?? 'subscription',
        amountLaari: (json['amountLaari'] as num).toInt(),
        referenceCode: json['referenceCode'] as String,
        status: PaymentSubmissionStatus.parse(json['status'] as String?),
        submittedAt: _date(json['submittedAt']),
        rejectionReason: json['rejectionReason'] as String?,
        reviewedAt: _date(json['reviewedAt']),
        reversedAt: _date(json['reversedAt']),
        appealedAt: _date(json['appealedAt']),
        appealNote: json['appealNote'] as String?,
        proofUploaded: json['proofUploaded'] as bool? ?? false,
        createdAt: _date(json['createdAt']) ?? DateTime.utc(1970),
      );

  final String id;

  /// `subscription` today, `emergency_dispatch_fee` already on the enum
  /// (§Phase 8a). Carried, not switched on: the pay screen is "built once,
  /// parameterised by purpose" (§Phase 10a), and the purpose decides copy,
  /// never behaviour.
  final String purpose;
  final int amountLaari;
  final String referenceCode;
  final PaymentSubmissionStatus status;

  /// Null until the provider taps "I've sent the transfer" — an intent they
  /// opened and never finished. Not work for an admin, and not "pending
  /// confirmation" on any screen.
  final DateTime? submittedAt;
  final String? rejectionReason;
  final DateTime? reviewedAt;
  final DateTime? reversedAt;

  /// §1b step 5's appeal, filed. The row is still `rejected`; an admin has
  /// been asked to look again.
  final DateTime? appealedAt;
  final String? appealNote;
  final bool proofUploaded;
  final DateTime createdAt;

  /// An intent the provider can still complete: `pending` with nothing sent.
  bool get isOpenIntent =>
      status == PaymentSubmissionStatus.pending && submittedAt == null;

  /// In the admin's queue.
  bool get isAwaitingConfirmation =>
      status == PaymentSubmissionStatus.pending && submittedAt != null;

  bool get isRejected => status == PaymentSubmissionStatus.rejected;
  bool get isAppealed => appealedAt != null;
}

/// RaajjePro's own account (§1b step 2) — from server configuration, never
/// typed in, never a provider's.
class BankTransferDetails {
  const BankTransferDetails({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });

  factory BankTransferDetails.fromJson(Map<String, dynamic> json) =>
      BankTransferDetails(
        bankName: json['bankName'] as String,
        accountName: json['accountName'] as String,
        accountNumber: json['accountNumber'] as String,
      );

  final String bankName;
  final String accountName;
  final String accountNumber;
}

/// A 30-day period from §1b's anchor — never a calendar month, and shifted by
/// pause. Both ends are the server's.
class BillingPeriod {
  const BillingPeriod({required this.start, required this.end});

  factory BillingPeriod.fromJson(Map<String, dynamic> json) => BillingPeriod(
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
  );

  final DateTime start;
  final DateTime end;
}

/// `GET /v1/providers/me/subscription`.
class SubscriptionStatusView {
  const SubscriptionStatusView({
    required this.premium,
    required this.status,
    required this.activeListingCap,
    required this.trialEndsAt,
    required this.trialDaysRemaining,
    required this.trialAvailable,
    required this.currentPeriodEnd,
    required this.nextPaymentAmountLaari,
    required this.priceLaari,
    required this.introductory,
    required this.introductoryConvertsAt,
    required this.graceEndsAt,
    required this.nextPeriod,
    required this.paused,
    required this.cumulativePausedDays,
    required this.remainingPauseAllowanceDays,
    required this.acceptingNewCustomers,
    required this.downgradedAt,
    required this.latestSubmission,
    required this.bankTransfer,
  });

  factory SubscriptionStatusView.fromJson(Map<String, dynamic> json) {
    final trial = json['trial'] as Map<String, dynamic>? ?? const {};
    final billing = json['billing'] as Map<String, dynamic>? ?? const {};
    final pause = json['pause'] as Map<String, dynamic>? ?? const {};
    final entitlements =
        json['entitlements'] as Map<String, dynamic>? ?? const {};
    final latest = json['latestSubmission'];
    final bank = json['bankTransfer'];
    final period = billing['nextPeriod'];
    return SubscriptionStatusView(
      premium: json['tier'] == 'premium',
      status: SubscriptionStatus.parse(json['status'] as String?),
      activeListingCap: (entitlements['activeListingCap'] as num?)?.toInt(),
      trialEndsAt: _date(trial['endsAt']),
      trialDaysRemaining: (trial['daysRemaining'] as num?)?.toInt(),
      trialAvailable: trial['available'] as bool? ?? false,
      currentPeriodEnd: _date(billing['currentPeriodEnd']),
      nextPaymentAmountLaari:
          (billing['nextPaymentAmountLaari'] as num?)?.toInt() ?? 0,
      priceLaari: (billing['priceLaari'] as num?)?.toInt(),
      introductory: billing['introductory'] as bool? ?? false,
      introductoryConvertsAt: _date(billing['introductoryConvertsAt']),
      graceEndsAt: _date(billing['graceEndsAt']),
      nextPeriod: period is Map<String, dynamic>
          ? BillingPeriod.fromJson(period)
          : null,
      paused: pause['paused'] as bool? ?? false,
      cumulativePausedDays:
          (pause['cumulativePausedDays'] as num?)?.toInt() ?? 0,
      remainingPauseAllowanceDays:
          (pause['remainingPauseAllowanceDays'] as num?)?.toInt() ?? 0,
      acceptingNewCustomers: json['acceptingNewCustomers'] as bool? ?? true,
      downgradedAt: _date(json['downgradedAt']),
      latestSubmission: latest is Map<String, dynamic>
          ? PaymentSubmission.fromJson(latest)
          : null,
      bankTransfer: bank is Map<String, dynamic>
          ? BankTransferDetails.fromJson(bank)
          : null,
    );
  }

  /// What a provider with no provider profile reads as: §1b's free tier. The
  /// screen renders the free state and the upgrade CTA; the first action
  /// creates nothing here — §1a's creation moments are onboarding, the first
  /// draft and the profile PATCH.
  const SubscriptionStatusView.free()
    : premium = false,
      status = SubscriptionStatus.none,
      activeListingCap = 1,
      trialEndsAt = null,
      trialDaysRemaining = null,
      trialAvailable = true,
      currentPeriodEnd = null,
      nextPaymentAmountLaari = 0,
      priceLaari = null,
      introductory = false,
      introductoryConvertsAt = null,
      graceEndsAt = null,
      nextPeriod = null,
      paused = false,
      cumulativePausedDays = 0,
      remainingPauseAllowanceDays = 0,
      acceptingNewCustomers = true,
      downgradedAt = null,
      latestSubmission = null,
      bankTransfer = null;

  /// `tier == 'premium'` — what is unlocked. A different axis from [status]:
  /// a paused subscription is still premium, and §1b's `expired` **is** the
  /// grace period and still carries premium.
  final bool premium;
  final SubscriptionStatus status;

  /// Null means no limit, never unknown (§Phase 8a).
  final int? activeListingCap;
  final DateTime? trialEndsAt;
  final int? trialDaysRemaining;

  /// False once a trial has ever run — §1b's one trial per account.
  final bool trialAvailable;
  final DateTime? currentPeriodEnd;

  /// What the next period costs — the provider's own settled price, or §1b's
  /// cohort rule before one is written. Never a platform constant.
  final int nextPaymentAmountLaari;

  /// Their settled price, once a payment has been confirmed. Null before that.
  final int? priceLaari;
  final bool introductory;
  final DateTime? introductoryConvertsAt;

  /// When the 7-day grace runs out — the date the downgrade lands if nothing
  /// is confirmed. The server's, so the expired-state copy quotes it.
  final DateTime? graceEndsAt;

  /// The period the next confirmed payment would buy. The server's.
  final BillingPeriod? nextPeriod;
  final bool paused;
  final int cumulativePausedDays;
  final int remainingPauseAllowanceDays;

  /// §1b: the pause keys off this toggle. Returned so the pause card can say
  /// what it is the same switch as.
  final bool acceptingNewCustomers;

  /// When the grace period ended and the over-cap listings were hidden.
  final DateTime? downgradedAt;
  final PaymentSubmission? latestSubmission;
  final BankTransferDetails? bankTransfer;

  /// `free` with a downgrade stamp: Premium lapsed and the hiding happened.
  bool get downgraded =>
      status == SubscriptionStatus.free && downgradedAt != null;

  /// `none`, or `free` with no lapse behind it: never premium, or lapsed so
  /// long ago the stamps were cleared by a later trial or payment.
  bool get plainFree =>
      status == SubscriptionStatus.none ||
      (status == SubscriptionStatus.free && downgradedAt == null);

  /// Whether a pause could be asked for: §1b's one function covers `trialing`
  /// and `active` identically.
  bool get pausable =>
      status == SubscriptionStatus.trialing ||
      status == SubscriptionStatus.active;
}

/// `POST /v1/providers/me/subscription/upgrade-request`.
class UpgradeRequest {
  const UpgradeRequest({
    required this.submission,
    required this.bankTransfer,
    required this.period,
  });

  factory UpgradeRequest.fromJson(Map<String, dynamic> json) {
    final bank = json['bankTransfer'];
    return UpgradeRequest(
      submission: PaymentSubmission.fromJson(
        json['submission'] as Map<String, dynamic>,
      ),
      bankTransfer: bank is Map<String, dynamic>
          ? BankTransferDetails.fromJson(bank)
          : null,
      period: BillingPeriod.fromJson(json['period'] as Map<String, dynamic>),
    );
  }

  final PaymentSubmission submission;
  final BankTransferDetails? bankTransfer;
  final BillingPeriod period;
}

/// `GET /v1/providers/me/invoices` — one per confirmed payment (§1b step 6).
class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.amountLaari,
    required this.periodStart,
    required this.periodEnd,
    required this.issuedAt,
    required this.pdfUrl,
    required this.voidedAt,
    required this.voidedReason,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: json['id'] as String,
    invoiceNumber: json['invoiceNumber'] as String,
    amountLaari: (json['amountLaari'] as num).toInt(),
    periodStart: DateTime.parse(json['periodStart'] as String),
    periodEnd: DateTime.parse(json['periodEnd'] as String),
    issuedAt: DateTime.parse(json['issuedAt'] as String),
    pdfUrl: json['pdfUrl'] as String,
    voidedAt: _date(json['voidedAt']),
    voidedReason: json['voidedReason'] as String?,
  );

  final String id;
  final String invoiceNumber;
  final int amountLaari;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime issuedAt;

  /// Short-lived and re-issued on every read. Fetched, never stored.
  final String pdfUrl;

  /// Set when the payment behind it was reversed — voided, never deleted
  /// (invariant 8). The document still exists and still downloads.
  final DateTime? voidedAt;
  final String? voidedReason;

  bool get voided => voidedAt != null;
}

/// The one account-level fact the billing screen renders that is not the
/// subscription's: the verification tier, for the "Premium does not include
/// the badge" card. Parsed from `GET /v1/providers/me` as narrowly as
/// §Phase 10's `ProviderWorkspace` does, and for the same reason.
class BillingProviderFacts {
  const BillingProviderFacts({required this.verificationTier});

  const BillingProviderFacts.none() : verificationTier = VerificationTier.none;

  factory BillingProviderFacts.fromJson(Map<String, dynamic> json) =>
      BillingProviderFacts(
        verificationTier: VerificationTier.parse(
          json['verificationTier'] as String?,
        ),
      );

  final VerificationTier verificationTier;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
