import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/billing/presentation/billing_screen.dart';
import 'package:raajjepro/features/billing/presentation/invoices_screen.dart';
import 'package:raajjepro/features/billing/presentation/pay_by_bank_transfer_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// `Billing.dc.html` — §Phase 10a part 1's subscription status screen: the
/// five server states, the two different CTAs for two different providers
/// (§0.4), the pause, the badge sentence, and the copy ledger row P8A-4 owes.
void main() {
  late BillingHarness h;

  setUp(() => h = BillingHarness());

  String allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  /// The body is a lazy `ListView`: a row below the fold is not built until
  /// it is scrolled to, so a finder for it has to be brought into view first.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }

  /// Every `Text` on the page, walking the lazy list to the end so rows
  /// below the fold count too.
  Future<String> allTextScrolled(WidgetTester tester) async {
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      seen.addAll(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? t.textSpan?.toPlainText() ?? ''),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    return seen.join(' | ');
  }

  /// Every `FadeUp` step on the page, walking the list to the end so the
  /// lazily built rows count too.
  Future<Set<int>> allSteps(WidgetTester tester) async {
    final steps = <int>{};
    for (var i = 0; i < 12; i++) {
      steps.addAll(
        tester.widgetList<FadeUp>(find.byType(FadeUp)).map((f) => f.index),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    return steps;
  }

  Future<void> pumpBilling(WidgetTester tester) => h.pump(
    tester,
    const BillingScreen(),
    routes: {
      PayByBankTransferScreen.routeName: (_) =>
          const Scaffold(body: Text('PAY SCREEN')),
      InvoicesScreen.routeName: (_) =>
          const Scaffold(body: Text('INVOICES SCREEN')),
    },
  );

  group('the four states every screen owes', () {
    testWidgets('a skeleton while the reads are in flight', (tester) async {
      h.script();
      h.api.gate = Completer<void>();
      await pumpBilling(tester);
      expect(find.bySemanticsLabel('Loading your billing'), findsOneWidget);
      h.api.gate!.complete();
      await settle(tester);
      expect(find.text('Free plan'), findsOneWidget);
    });

    testWidgets('an error names the retry, and the retry re-reads', (
      tester,
    ) async {
      h.script();
      h.api.fail(
        'GET',
        '/v1/providers/me/subscription',
        status: 500,
        code: 'INTERNAL',
      );
      await pumpBilling(tester);
      expect(find.text('Couldn’t load your billing'), findsOneWidget);
      h.script();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Free plan'), findsOneWidget);
    });

    testWidgets('offline reads as a connection problem, not a plan problem', (
      tester,
    ) async {
      h.script();
      h.api.offline('GET', '/v1/providers/me/subscription');
      await pumpBilling(tester);
      expect(find.textContaining('couldn’t reach them'), findsOneWidget);
    });

    testWidgets('a provider with no profile reads as the free tier', (
      tester,
    ) async {
      h.script();
      h.api.fail(
        'GET',
        '/v1/providers/me/subscription',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      h.api.fail(
        'GET',
        '/v1/providers/me',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      await pumpBilling(tester);
      expect(find.text('Free plan'), findsOneWidget);
    });
  });

  group('five plan states, all the server’s', () {
    testWidgets('free, never trialled: the Try Premium CTA and no pay CTA', (
      tester,
    ) async {
      h.script();
      await pumpBilling(tester);
      expect(find.text('Try Premium free for 30 days'), findsOneWidget);
      expect(find.text('Pay by bank transfer'), findsNothing);
      expect(find.textContaining('never tried Premium'), findsOneWidget);
      // No pause card on a free plan: nothing to pause.
      await scrollTo(tester, find.text('Invoices'));
      expect(find.text('Pause Premium'), findsNothing);
    });

    testWidgets('free, trial used: the pay CTA and no trial CTA', (
      tester,
    ) async {
      h.script(status: statusJson(status: 'free', trialAvailable: false));
      await pumpBilling(tester);
      expect(find.text('Pay by bank transfer'), findsOneWidget);
      expect(find.text('Try Premium free for 30 days'), findsNothing);
    });

    testWidgets('trialing: the countdown, the end date, pay, and pause', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'trialing',
          activeListingCap: null,
          trialEndsAt: '2026-10-03T03:00:00.000Z',
          trialDaysRemaining: 18,
          trialAvailable: false,
        ),
      );
      await pumpBilling(tester);
      expect(find.text('Trial · 18 days left'), findsOneWidget);
      expect(find.textContaining('Your trial ends 3 Oct 2026'), findsOneWidget);
      expect(find.text('Pay by bank transfer'), findsOneWidget);
      // §1b: one pause function, applied identically during the trial.
      await scrollTo(tester, find.text('Pause Premium'));
      expect(find.text('Pause Premium'), findsOneWidget);
    });

    testWidgets('premium: next payment date, anchor copy, pay and pause', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'active',
          activeListingCap: null,
          trialAvailable: false,
          anchorAt: '2026-08-13T03:00:00.000Z',
          currentPeriodEnd: '2026-10-12T03:00:00.000Z',
          priceLaari: 7500,
          introductoryConvertsAt: '2027-08-13T03:00:00.000Z',
        ),
      );
      await pumpBilling(tester);
      expect(find.text('Premium'), findsWidgets);
      expect(find.textContaining('Next payment 12 Oct 2026'), findsOneWidget);
      expect(find.textContaining('not calendar months'), findsOneWidget);
      expect(find.text('YOUR RATE'), findsOneWidget);
      expect(find.text('MVR 75'), findsOneWidget);
      expect(find.textContaining('until 13 Aug 2027'), findsOneWidget);
      await scrollTo(tester, find.text('Pause Premium'));
      expect(find.text('Pause Premium'), findsOneWidget);
    });

    testWidgets(
      'paused: the bar, the moved date, and resume with the unused days',
      (tester) async {
        h.script(
          status: statusJson(
            tier: 'premium',
            status: 'paused',
            activeListingCap: null,
            trialAvailable: false,
            currentPeriodEnd: '2026-09-18T03:00:00.000Z',
            paused: true,
            cumulativePausedDays: 6,
            remainingPauseAllowanceDays: 4,
          ),
        );
        await pumpBilling(tester);
        expect(find.text('Paused · 6 days of 10 used'), findsOneWidget);
        expect(find.text('Premium, paused'), findsOneWidget);
        expect(find.textContaining('currently 18 Sep 2026'), findsOneWidget);
        expect(find.textContaining('6 of 10 pause days used'), findsOneWidget);
        expect(
          find.text('Resume now — keep the 4 unused days'),
          findsOneWidget,
        );
        // Paused is not pausable again, and not payable from this card.
        expect(find.text('Pause Premium'), findsNothing);
      },
    );

    testWidgets('expired: the grace end is the server’s date', (tester) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'expired',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-08-30T03:00:00.000Z',
          graceEndsAt: '2026-09-06T03:00:00.000Z',
        ),
      );
      await pumpBilling(tester);
      expect(find.text('Premium expired 30 Aug 2026'), findsOneWidget);
      expect(find.textContaining('by 6 Sep 2026'), findsOneWidget);
      expect(find.text('Pay by bank transfer'), findsOneWidget);
    });

    testWidgets(
      'downgraded: the hidden listings are the server’s, with the override',
      (tester) async {
        h.script(
          status: statusJson(
            status: 'free',
            trialAvailable: false,
            downgradedAt: '2026-09-07T03:00:00.000Z',
          ),
          listings: [
            billingListingJson(id: 'l-1', name: 'Home Deep Cleaning'),
            billingListingJson(
              id: 'l-2',
              name: 'Sunset Fishing Charter',
              visibility: 'hidden_over_cap',
            ),
          ],
        );
        h.api.on(
          'POST',
          '/v1/providers/me/listings/l-2/keep-visible',
          (_) => billingListingJson(id: 'l-2', name: 'Sunset Fishing Charter'),
        );
        await pumpBilling(tester);
        expect(find.text('Premium lapsed'), findsOneWidget);
        await scrollTo(tester, find.text('If Premium lapses'));
        expect(find.text('Home Deep Cleaning'), findsOneWidget);
        expect(find.text('Stays live'), findsOneWidget);
        expect(
          find.textContaining('Hidden until a confirmed payment'),
          findsOneWidget,
        );

        // §1b's override goes through the pin endpoint and re-reads.
        h.script(
          status: statusJson(
            status: 'free',
            trialAvailable: false,
            downgradedAt: '2026-09-07T03:00:00.000Z',
          ),
          listings: [
            billingListingJson(
              id: 'l-1',
              name: 'Home Deep Cleaning',
              visibility: 'hidden_over_cap',
            ),
            billingListingJson(id: 'l-2', name: 'Sunset Fishing Charter'),
          ],
        );
        await scrollTo(tester, find.text('Keep this one instead'));
        await tester.tap(find.text('Keep this one instead'));
        await settle(tester);
        expect(
          h.calls('POST').map((c) => c.path),
          contains('/v1/providers/me/listings/l-2/keep-visible'),
        );
        expect(find.textContaining('will stay live instead'), findsOneWidget);
      },
    );
  });

  group('actions write through the server and adopt its answer', () {
    testWidgets(
      'Try Premium calls start-trial once and renders the returned state',
      (tester) async {
        h.script();
        h.api.on(
          'POST',
          '/v1/providers/me/subscription/start-trial',
          (_) => statusJson(
            tier: 'premium',
            status: 'trialing',
            activeListingCap: null,
            trialEndsAt: '2026-10-15T03:00:00.000Z',
            trialDaysRemaining: 30,
            trialAvailable: false,
          ),
        );
        await pumpBilling(tester);
        await tester.tap(find.text('Try Premium free for 30 days'));
        await settle(tester);
        final starts = h
            .calls('POST')
            .where((c) => c.path.endsWith('/start-trial'));
        expect(starts, hasLength(1));
        expect(find.text('Trial · 30 days left'), findsOneWidget);
        expect(find.text('Try Premium free for 30 days'), findsNothing);
      },
    );

    testWidgets('a refused trial says the server’s reason', (tester) async {
      h.script();
      h.api.fail(
        'POST',
        '/v1/providers/me/subscription/start-trial',
        status: 422,
        code: 'TRIAL_ALREADY_USED',
        message:
            'This account has already had its free trial — one per account',
      );
      await pumpBilling(tester);
      await tester.tap(find.text('Try Premium free for 30 days'));
      await settle(tester);
      expect(find.textContaining('already had its free trial'), findsOneWidget);
    });

    testWidgets('pause opens the card, carries P8A-4’s sentence, and pauses', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'active',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-10-12T03:00:00.000Z',
        ),
      );
      h.api.on(
        'POST',
        '/v1/providers/me/subscription/pause',
        (_) => statusJson(
          tier: 'premium',
          status: 'paused',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-10-12T03:00:00.000Z',
          paused: true,
          cumulativePausedDays: 0,
          remainingPauseAllowanceDays: 10,
        ),
      );
      await pumpBilling(tester);
      await scrollTo(tester, find.text('Pause Premium'));
      await tester.tap(find.text('Pause Premium'));
      await settle(tester);

      // Ledger row P8A-4: the toggle's billing consequence, in the card.
      final text = allText(tester);
      expect(text, contains('Accepting new customers'));
      expect(text, contains('don’t refill'));
      expect(text, contains('billing anchor'));

      await scrollTo(tester, find.text('Pause now — 10 days available'));
      await tester.tap(find.text('Pause now — 10 days available'));
      await settle(tester);
      expect(
        h.calls('POST').map((c) => c.path),
        contains('/v1/providers/me/subscription/pause'),
      );
      expect(find.text('Premium, paused'), findsOneWidget);
    });

    testWidgets('resume calls the endpoint and renders the returned state', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'paused',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-09-18T03:00:00.000Z',
          paused: true,
          cumulativePausedDays: 6,
          remainingPauseAllowanceDays: 4,
        ),
      );
      h.api.on(
        'POST',
        '/v1/providers/me/subscription/resume',
        (_) => statusJson(
          tier: 'premium',
          status: 'active',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-09-18T03:00:00.000Z',
          cumulativePausedDays: 6,
          remainingPauseAllowanceDays: 4,
        ),
      );
      await pumpBilling(tester);
      await tester.tap(find.text('Resume now — keep the 4 unused days'));
      await settle(tester);
      expect(find.text('Premium, paused'), findsNothing);
      expect(find.textContaining('Next payment 18 Sep 2026'), findsOneWidget);
    });
  });

  group('the submission notice', () {
    testWidgets(
      'a submitted payment reads as pending, and leads to the pay screen',
      (tester) async {
        h.script(
          status: statusJson(
            latestSubmission: submissionJson(
              submittedAt: '2026-09-14T09:20:00.000Z',
              proofUploaded: true,
            ),
          ),
        );
        await pumpBilling(tester);
        expect(find.textContaining('pending confirmation'), findsOneWidget);
        expect(
          find.textContaining('Nothing changes until then'),
          findsOneWidget,
        );
        await tester.tap(find.text('View'));
        await settle(tester);
        expect(find.text('PAY SCREEN'), findsOneWidget);
      },
    );

    testWidgets('an open, unsubmitted intent is not "pending"', (tester) async {
      h.script(status: statusJson(latestSubmission: submissionJson()));
      await pumpBilling(tester);
      expect(find.textContaining('pending'), findsNothing);
    });

    testWidgets('a rejection is named, and an appeal is named as sent', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          latestSubmission: submissionJson(
            status: 'rejected',
            submittedAt: '2026-09-14T09:20:00.000Z',
            rejectionReason: 'MVR 57 arrived, not MVR 75',
          ),
        ),
      );
      await pumpBilling(tester);
      expect(find.textContaining('wasn’t confirmed'), findsOneWidget);
    });

    testWidgets('an appealed rejection is named as sent', (tester) async {
      h.script(
        status: statusJson(
          latestSubmission: submissionJson(
            status: 'rejected',
            submittedAt: '2026-09-14T09:20:00.000Z',
            rejectionReason: 'MVR 57 arrived, not MVR 75',
            appealedAt: '2026-09-15T01:00:00.000Z',
          ),
        ),
      );
      await pumpBilling(tester);
      expect(find.textContaining('Appeal sent'), findsOneWidget);
    });
  });

  group('the rules the copy carries', () {
    testWidgets(
      'the badge sentence: gated by verification alone, on neither plan',
      (tester) async {
        h.script(verificationTier: 'silver');
        await pumpBilling(tester);
        final text = allText(tester);
        expect(
          text,
          contains('Premium does not include the verification badge'),
        );
        expect(text, contains('Silver badge'));
        expect(text, contains('on neither list'));
        // §1e: never a bare "Verified".
        expect(
          text.split(' | '),
          isNot(contains('Verified')), // retired-ok: asserting its absence
        );
      },
    );

    testWidgets(
      'a tier-none provider gets the sentence without a badge to name',
      (tester) async {
        h.script(verificationTier: 'none');
        await pumpBilling(tester);
        expect(find.byType(VerificationBadge), findsNothing);
        expect(
          find.textContaining('can’t be bought on any plan'),
          findsWidgets,
        );
      },
    );

    testWidgets('never "monthly", never a global price, no web-page claim', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'active',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-10-12T03:00:00.000Z',
          priceLaari: 7500,
        ),
      );
      await pumpBilling(tester);
      final text = (await allTextScrolled(tester)).toLowerCase();
      expect(text, isNot(contains('per month')));
      expect(text, isNot(contains('/month')));
      expect(text, isNot(contains('monthly')));
      expect(text, contains('per 30-day period'));
      // §1b: the standard rate is not a platform constant, so it is not
      // printed as one — and no "same page on the web" (§Phase 23's
      // contingency is not a thing that exists).
      expect(text, isNot(contains('mvr 150')));
      expect(text, isNot(contains('on the web')));
      // Nothing on the screen is drawn from a listing's phone or bank field.
      expect(text, isNot(contains('+960')));
    });

    testWidgets('the Invoices row reaches the invoices screen', (tester) async {
      h.script();
      await pumpBilling(tester);
      await scrollTo(tester, find.text('Invoices'));
      await tester.tap(find.text('Invoices'));
      await settle(tester);
      expect(find.text('INVOICES SCREEN'), findsOneWidget);
    });
  });

  group('design rules', () {
    testWidgets('every card is a container and every control survives', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          status: 'free',
          trialAvailable: false,
          downgradedAt: '2026-09-07T03:00:00.000Z',
        ),
        listings: [
          billingListingJson(id: 'l-1', name: 'A'),
          billingListingJson(
            id: 'l-2',
            name: 'B',
            visibility: 'hidden_over_cap',
          ),
        ],
      );
      await pumpBilling(tester);
      await scrollTo(tester, find.text('Keep this one instead'));
      expectNoSwallowedControls(tester);
    });

    testWidgets('the rows enter one step behind another, not as one block', (
      tester,
    ) async {
      h.script(
        status: statusJson(
          tier: 'premium',
          status: 'active',
          activeListingCap: null,
          trialAvailable: false,
          currentPeriodEnd: '2026-10-12T03:00:00.000Z',
        ),
      );
      await pumpBilling(tester);
      final steps = await allSteps(tester);
      // The state card, the badge card, the plan table, the pause card, the
      // lapse card, the Invoices row and the footer: seven rows, a step each.
      expect(steps.length, greaterThanOrEqualTo(6));
      expect(steps, containsAll([0, 1, 2, 3, 4, 5]));
    });
  });
}
