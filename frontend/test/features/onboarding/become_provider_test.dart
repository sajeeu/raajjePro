import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/onboarding/presentation/become_provider_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/islands.dart';
import '../../helpers/pump.dart';

/// §Phase 6a's flow — **Become a Provider**
/// (`mockups/design-composer/Become a Provider.dc.html`).
///
/// Driven as a screen, against a scripted API. Every assertion below is a
/// §Phase 6a rule rather than a layout detail: which step opens, what blocks
/// Continue, which endpoint each half of step 2 goes to, and where the flow
/// hands off.
void main() {
  late FakeApiClient api;
  late InMemoryTokenStore store;

  /// Owned by the test so the draft §Phase 6a saves before leaving to verify
  /// an email can be inspected. It is the same in-memory store Phase 3 uses.
  late FormDraftStore drafts;

  setUp(() {
    api = FakeApiClient();
    store = InMemoryTokenStore();
    drafts = FormDraftStore();
    api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
  });

  /// A provider profile as `GET /v1/providers/me` returns it. Defaults are a
  /// completed step 2 with no service areas; pass nulls to unwind it.
  Map<String, dynamic> profileJson({
    Object? businessName = "Hassan's Repairs",
    Object? providerType = 'individual',
    Object? bankName = 'Bank of Maldives (BML)',
    Object? bankAccountName = 'Hassan Ibrahim',
    Object? bankAccountNumber = '7730000123456',
    List<Map<String, dynamic>> serviceAreas = const [],
    bool onboardingComplete = false,
    bool acceptingNewCustomers = true,
    Object? bio,
  }) => {
    'businessName': businessName,
    'providerType': providerType,
    'bio': bio,
    'acceptingNewCustomers': acceptingNewCustomers,
    'paymentDetails': {
      'bankName': bankName,
      'bankAccountName': bankAccountName,
      'bankAccountNumber': bankAccountNumber,
      'transferInstructions': null,
    },
    'serviceAreas': serviceAreas,
    'onboardingComplete': onboardingComplete,
  };

  void noProfile() => api.fail(
    'GET',
    '/v1/providers/me',
    status: 404,
    code: 'PROVIDER_PROFILE_NOT_FOUND',
  );

  /// Pumps the screen with the account already signed in.
  ///
  /// The screen takes the phone and the email from `AuthController` — §Phase 6a
  /// asks for neither again — and in the real app `RaajjeProApp` restores that
  /// state on boot. Here it is seeded directly, so a test sets an account's
  /// email verification and phone as a precondition rather than by scripting a
  /// restore.
  Future<void> pump(
    WidgetTester tester, {
    bool emailVerified = true,
    String? phone = '7771234',
    Map<String, WidgetBuilder> routes = const {},
  }) async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on(
      'GET',
      '/v1/auth/me',
      (_) => {
        ...userJson(verified: emailVerified),
        'phone': phone == null ? null : {'dialCode': '+960', 'number': phone},
      },
    );
    final user = UserAccount.fromJson({
      ...userJson(verified: emailVerified),
      'phone': phone == null ? null : {'dialCode': '+960', 'number': phone},
    });
    await pumpScreen(
      tester,
      const BecomeProviderScreen(),
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
        crashReporterProvider.overrideWithValue(NoopCrashReporter()),
        formDraftStoreProvider.overrideWithValue(drafts),
        authControllerProvider.overrideWith(() => _SignedInController(user)),
      ],
      routes: routes,
    );
    await settle(tester);
  }

  final pumpSignedIn = pump;

  group('§Phase 6a Done-when — a brand-new user lands on the intro', () {
    testWidgets('opens on step 1, not the wizard and not the form', (
      tester,
    ) async {
      noProfile();
      await pumpSignedIn(tester);

      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Offer your services on RaajjePro'), findsOneWidget);
      // Never straight into the account form, and never the wizard.
      expect(find.text('Tell us about you'), findsNothing);
      expect(find.byType(AppTextField), findsNothing);
    });

    testWidgets('the intro states the four mechanics, and no price', (
      tester,
    ) async {
      // §Phase 6a: "subscription-only monetization stays invisible here
      // (that's Phase 8a/10a's job, later), this screen is about the
      // mechanics". A price on this screen answers a question nobody asked.
      noProfile();
      await pumpSignedIn(tester);

      expect(find.text('List your services'), findsOneWidget);
      expect(find.text('Receive bookings & interest'), findsOneWidget);
      expect(find.text('Agree on the job in chat'), findsOneWidget);
      expect(find.text('Get paid directly'), findsOneWidget);
      for (final banned in ['MVR', 'subscription', 'Subscription', 'trial']) {
        expect(
          find.textContaining(banned, findRichText: true),
          findsNothing,
          reason: banned,
        );
      }
    });

    testWidgets('"Not right now" leaves, and writes nothing at all', (
      tester,
    ) async {
      // §Phase 6a: it "returns the user to customer mode cleanly, leaving no
      // orphaned draft and no resume prompt". Clean by construction — step 1
      // has no write to undo.
      noProfile();
      await pumpSignedIn(tester);
      await tester.tap(find.text('Not right now'));
      await settle(tester);

      expect(
        api.calls.where((c) => c.method != 'GET'),
        isEmpty,
        reason: 'the intro must not write',
      );
    });

    testWidgets('Continue moves to step 2 without writing either', (
      tester,
    ) async {
      noProfile();
      await pumpSignedIn(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Tell us about you'), findsOneWidget);
      // The profile is created by step 2's Continue, not by arriving at it —
      // `isProvider` is permanent (invariant 8), so a customer who looked at
      // the form is still a customer.
      expect(api.calls.where((c) => c.method == 'PATCH'), isEmpty);
    });
  });

  group('step 2 — the three sections, and what blocks Continue', () {
    Future<void> toStepTwo(
      WidgetTester tester, {
      bool emailVerified = true,
      String? phone = '7771234',
      Map<String, WidgetBuilder> routes = const {},
    }) async {
      noProfile();
      await pumpSignedIn(
        tester,
        emailVerified: emailVerified,
        phone: phone,
        routes: routes,
      );
      await tester.tap(find.text('Continue'));
      await settle(tester);
    }

    testWidgets('renders Round 21’s three groups, in order', (tester) async {
      await toStepTwo(tester);
      // §Phase 6a: "grouped into three sections — About you · Getting paid ·
      // Availability (Round 21) — because the delivered design showed the
      // ungrouped list reads as a wall".
      for (final section in ['About you', 'Getting paid', 'Availability']) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
    });

    testWidgets('states §1c’s off-platform payment rule where it matters', (
      tester,
    ) async {
      await toStepTwo(tester);
      expect(
        find.textContaining(
          'RaajjePro never collects or holds your payments',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('the availability toggle is on, and says it is account-level', (
      tester,
    ) async {
      await toStepTwo(tester);
      await tester.ensureVisible(find.text('Accepting new customers'));
      final toggle = tester.widget<AppToggle>(find.byType(AppToggle));
      expect(toggle.value, isTrue, reason: '§Phase 6a defaults it on');
      expect(
        find.textContaining('hides all your services at once'),
        findsOneWidget,
      );
    });

    testWidgets('an empty form fails per field, not as one banner', (
      tester,
    ) async {
      await toStepTwo(tester);
      await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await settle(tester);

      // frontend/CLAUDE.md: a field error belongs under its field.
      expect(find.text('Please enter your provider name.'), findsOneWidget);
      expect(find.text("Choose how you'll offer services."), findsOneWidget);
      expect(find.text("Enter the account holder's name."), findsOneWidget);
      expect(find.text('Enter your account number.'), findsOneWidget);
      expect(find.text('Select your bank.'), findsOneWidget);
      // Nothing was sent.
      expect(api.calls.where((c) => c.method == 'PATCH'), isEmpty);
    });

    testWidgets('an unverified email blocks Continue with its own message', (
      tester,
    ) async {
      // §Phase 6a: "Unverified blocks Continue with its own message, since
      // booking notifications go there."
      await toStepTwo(tester, emailVerified: false);
      await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await settle(tester);

      expect(
        find.textContaining('Verify your email before continuing'),
        findsOneWidget,
      );
      expect(api.calls.where((c) => c.method == 'PATCH'), isEmpty);
    });

    testWidgets('a fields-complete but unverified account resumes at step 2', (
      tester,
    ) async {
      // The hole judgment call (b) creates, and the reason step 2 is the only
      // screen that enforces the email: resuming past it would show a
      // "you're all set" sheet and hand off to the wizard while the server
      // said the flow was unfinished, then route the provider back here with
      // nothing on screen explaining why.
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      await pumpSignedIn(tester, emailVerified: false);

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsNothing);
      expect(
        find.textContaining('Verify your email to continue'),
        findsOneWidget,
      );
    });

    testWidgets('the same account resumes at step 3 once verified', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      await pumpSignedIn(tester);
      expect(find.text('Step 3 of 3'), findsOneWidget);
    });

    testWidgets('leaving to verify the email keeps what was typed', (
      tester,
    ) async {
      // Phase 3's Verify Email screen finishes with `pushNamedAndRemoveUntil`
      // back to the root, so this flow is gone by the time the address is
      // confirmed. frontend/CLAUDE.md: never silently discard user input.
      await toStepTwo(
        tester,
        emailVerified: false,
        routes: {
          // A marker for Phase 3's screen. Its real destructive behaviour —
          // `pushNamedAndRemoveUntil` back to the root on success — is what
          // makes the draft necessary, and is that screen's own to test.
          AppRoutes.verifyEmail: (_) => const Scaffold(body: Text('VERIFY')),
        },
      );
      await tester.enterText(
        find.byKey(const Key('onboarding-name')),
        "Hassan's Repairs",
      );
      await tester.ensureVisible(find.byKey(const Key('onboarding-holder')));
      await tester.enterText(
        find.byKey(const Key('onboarding-holder')),
        'Hassan Ibrahim',
      );

      expect(drafts.peek(AppRoutes.becomeProvider), isNull);

      await tester.ensureVisible(find.text('Verify email'));
      await tester.tap(find.text('Verify email'));
      await settle(tester);

      final draft = drafts.peek(AppRoutes.becomeProvider);
      expect(draft, isNotNull);
      expect(draft!['businessName'], "Hassan's Repairs");
      expect(draft['bankAccountName'], 'Hassan Ibrahim');
    });

    testWidgets('an account number with spaces and 20 digits is accepted', (
      tester,
    ) async {
      // The server takes 4–40 characters of digits, spaces and dashes; a
      // client stricter than that blocks a real foreign account, which is the
      // case Round 17 protected on the phone field.
      await toStepTwo(tester);
      await tester.ensureVisible(find.byKey(const Key('onboarding-account')));
      await tester.enterText(
        find.byKey(const Key('onboarding-account')),
        '7730 0001 2345 6789 01',
      );
      final field = tester.widget<AppTextField>(
        find.byKey(const Key('onboarding-account')),
      );
      expect(field.controller!.text, '7730 0001 2345 6789 01');
    });

    testWidgets('a verified email is stated as such, never as a bare badge', (
      tester,
    ) async {
      await toStepTwo(tester);
      // The one honest check mark on this step. §1e's tier badge is three
      // treatments with their own copy and must never be confused with it.
      expect(find.text('Email verified'), findsOneWidget);
      // retired-ok: asserting the ABSENCE of the retired bare badge.
      expect(find.text('Verified'), findsNothing); // retired-ok:
    });

    testWidgets('the phone is pre-filled and confirmed, never re-typed', (
      tester,
    ) async {
      // §Phase 6a: "pre-filled from Phase 3 and confirmed, never re-typed —
      // an `editingPhone` state reveals the input only on request".
      await toStepTwo(tester);
      await tester.ensureVisible(find.text('+960 7771234'));
      expect(find.text('+960 7771234'), findsOneWidget);
      expect(find.byKey(const Key('reg-phone')), findsNothing);

      await tester.tap(find.text('Change'));
      await settle(tester);
      expect(find.byKey(const Key('reg-phone')), findsOneWidget);
      expect(find.byKey(const Key('reg-dial')), findsOneWidget);
    });

    testWidgets('an account with no number on file opens the input', (
      tester,
    ) async {
      // Nothing to confirm, so the "never re-typed" rule has nothing to
      // apply to.
      await toStepTwo(tester, phone: null);
      await tester.ensureVisible(find.byKey(const Key('reg-phone')));
      expect(find.byKey(const Key('reg-phone')), findsOneWidget);
    });

    testWidgets('accepts a foreign number — no Maldivian pattern (Round 17)', (
      tester,
    ) async {
      // "Do not restrict to the 7-digit 7-or-9 Maldivian pattern (Round 17) —
      // expatriate residents hold foreign numbers." 6 to 15 digits.
      await toStepTwo(tester, phone: null);
      api.on('PATCH', '/v1/users/me/phone', (_) => userJson(verified: true));
      api.on('PATCH', '/v1/providers/me', (_) => profileJson());

      await tester.enterText(find.byKey(const Key('reg-dial')), '+44');
      await tester.enterText(find.byKey(const Key('reg-phone')), '7700900123');
      await _fillDetails(tester);
      await settle(tester);

      expect(
        find.textContaining('Enter a valid mobile number'),
        findsNothing,
        reason: 'a UK number is valid',
      );
      expect(find.text('Step 3 of 3'), findsOneWidget);
    });

    testWidgets('rejects fewer than six digits', (tester) async {
      await toStepTwo(tester, phone: null);
      await tester.enterText(find.byKey(const Key('reg-phone')), '12345');
      await _fillDetails(tester);
      await settle(tester);

      expect(
        find.textContaining('Enter a valid mobile number'),
        findsOneWidget,
      );
      expect(find.text('Step 3 of 3'), findsNothing);
    });

    testWidgets('the photo control is drawn and does nothing (Phase 8)', (
      tester,
    ) async {
      // The Phase 6 precedent for the same control: no avatar or logo column
      // exists and media upload is §Phase 8's, so it is inert rather than
      // absent — §Phase 6a marks it optional, so nothing is blocked.
      await toStepTwo(tester);
      final inert = tester.widget<InertControl>(
        find.ancestor(
          of: find.text('Photo or logo'),
          matching: find.byType(InertControl),
        ),
      );
      expect(inert.owedBy, 'Phase 8');
      expect(inert.label, 'Add photo');
    });

    testWidgets('caps the introduction at 160 characters', (tester) async {
      await toStepTwo(tester);
      final field = tester.widget<AppTextField>(
        find.byKey(const Key('onboarding-intro')),
      );
      expect(field.maxLength, 160);
    });
  });

  group('step 2 — where each half of the write goes', () {
    testWidgets('payment details to Phase 5, phone to Phase 3', (tester) async {
      // §Phase 6a's Done-when routes both through `PATCH /v1/providers/me`
      // and cannot: there is no phone column on `ProviderProfile`
      // (`docs/decisions/17-phase-5-provider-profiles.md`, disagreement 2).
      noProfile();
      await pumpSignedIn(tester, phone: '7771234');
      await tester.tap(find.text('Continue'));
      await settle(tester);

      api.on('PATCH', '/v1/providers/me', (_) => profileJson());
      await _fillDetails(tester);
      await settle(tester);

      final patches = api.calls.where((c) => c.method == 'PATCH').toList();
      expect(patches.map((c) => c.path), ['/v1/providers/me']);
      final body = patches.single.body! as Map<String, Object?>;
      expect(body['providerType'], 'individual');
      expect(body['bankName'], 'Bank of Maldives (BML)');
      expect(body['bankAccountName'], 'Hassan Ibrahim');
      expect(body['bankAccountNumber'], '7730000123456');
      // The phone was untouched, so it was not re-sent anywhere.
      expect(body.containsKey('phone'), isFalse);
    });

    testWidgets('an edited phone goes to Phase 3 first, then the profile', (
      tester,
    ) async {
      // Phone first: a taken number must leave nothing else written, and a
      // provider profile created ahead of a failed phone change would be a
      // permanent flip for a step that did not complete.
      noProfile();
      await pumpSignedIn(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      await tester.ensureVisible(find.text('Change'));
      await tester.tap(find.text('Change'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('reg-phone')), '9991234');

      api.on('PATCH', '/v1/users/me/phone', (_) => userJson(verified: true));
      api.on('PATCH', '/v1/providers/me', (_) => profileJson());
      await _fillDetails(tester);
      await settle(tester);

      expect(api.calls.where((c) => c.method == 'PATCH').map((c) => c.path), [
        '/v1/users/me/phone',
        '/v1/providers/me',
      ]);
    });

    testWidgets('a taken number stops the step and creates no profile', (
      tester,
    ) async {
      // §Phase 3, Round 15: a number held at Bronze or above is taken, and
      // the message names the field.
      noProfile();
      await pumpSignedIn(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.ensureVisible(find.text('Change'));
      await tester.tap(find.text('Change'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('reg-phone')), '9991234');

      api.fail(
        'PATCH',
        '/v1/users/me/phone',
        status: 409,
        code: 'PHONE_IN_USE',
      );
      await _fillDetails(tester);
      await settle(tester);

      expect(
        find.textContaining('belongs to a verified provider account'),
        findsOneWidget,
      );
      expect(find.text('Step 3 of 3'), findsNothing);
      expect(
        api.calls.where(
          (c) => c.path == '/v1/providers/me' && c.method == 'PATCH',
        ),
        isEmpty,
        reason: 'nothing else may be written when the phone half fails',
      );
    });

    testWidgets('an offline Continue says so and discards nothing', (
      tester,
    ) async {
      noProfile();
      await pumpSignedIn(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      api.offline('PATCH', '/v1/providers/me');
      await _fillDetails(tester);
      await settle(tester);

      expect(find.textContaining("You're offline"), findsOneWidget);
      // Still on step 2, with what was typed still in the fields.
      expect(find.text('Step 2 of 3'), findsOneWidget);
      final name = tester.widget<AppTextField>(
        find.byKey(const Key('onboarding-name')),
      );
      expect(name.controller!.text, "Hassan's Repairs");
    });
  });

  group('step 3 — the default service areas', () {
    Future<void> toStepThree(WidgetTester tester) async {
      api.on('GET', '/v1/providers/me', (_) => profileJson());
      await pumpSignedIn(tester);
    }

    testWidgets('resumes here when step 2 is done and step 3 is not', (
      tester,
    ) async {
      // §Phase 6a: "A provider who abandons onboarding after step 1 or 2
      // (backs out, closes the app) and returns later resumes from wherever
      // they left off."
      await toStepThree(tester);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Where do you usually work?'), findsOneWidget);
    });

    testWidgets('says these are defaults that a listing can narrow', (
      tester,
    ) async {
      // §Phase 6a: "This is a default, not a constraint; per-listing service
      // areas remain authoritative for discovery."
      await toStepThree(tester);
      expect(
        find.textContaining('pre-fill every new service you create'),
        findsOneWidget,
      );
      expect(
        find.textContaining('narrow them down for any single service'),
        findsOneWidget,
      );
    });

    testWidgets('uses §Phase 7’s multi-select, and never a native picker', (
      tester,
    ) async {
      await toStepThree(tester);
      expect(find.byType(IslandMultiSelect), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      // §0.0 item 12: no island total in UI copy.
      expect(find.textContaining('192'), findsNothing);
    });

    testWidgets('the CTA is disabled until an island is chosen', (
      tester,
    ) async {
      await toStepThree(tester);
      final before = tester.widget<AppButton>(
        find.byKey(const Key('onboarding-finish')),
      );
      expect(before.onPressed, isNull);

      api.on(
        'POST',
        '/v1/providers/me/service-areas',
        (_) => {
          '_list': [sampleIslands().first],
        },
      );
      await tester.ensureVisible(find.text("Male'"));
      await tester.tap(find.text("Male'"));
      await settle(tester);

      final after = tester.widget<AppButton>(
        find.byKey(const Key('onboarding-finish')),
      );
      expect(after.onPressed, isNotNull);
      expect(find.text('1 island selected'), findsOneWidget);
    });

    testWidgets('each pick writes immediately, so nothing is lost on exit', (
      tester,
    ) async {
      // What makes resuming at this step work with nothing cached on device.
      await toStepThree(tester);
      api.on(
        'POST',
        '/v1/providers/me/service-areas',
        (_) => {
          '_list': [sampleIslands().first],
        },
      );
      await tester.ensureVisible(find.text("Male'"));
      await tester.tap(find.text("Male'"));
      await settle(tester);

      final posts = api.calls.where((c) => c.method == 'POST').toList();
      expect(posts.single.path, '/v1/providers/me/service-areas');
      expect(posts.single.body, {'islandId': 'i-male'});
    });

    testWidgets('an ambiguous island keeps its atoll code on the chip', (
      tester,
    ) async {
      // §0.0 item 12: `Dh. Meedhoo` qualified, and the qualifying is the
      // server's — nothing here rebuilds it.
      final dhMeedhoo = sampleIslands().firstWhere(
        (i) => i['id'] == 'i-meedhoo-dh',
      );
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [dhMeedhoo]),
      );
      await pumpSignedIn(tester);

      expect(find.text('Dh. Meedhoo'), findsWidgets);
      expect(find.text('Meedhoo'), findsNothing);
    });

    testWidgets('removing the only island disables the CTA again', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      await pumpSignedIn(tester);
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('onboarding-finish')))
            .onPressed,
        isNotNull,
      );

      api.on(
        'DELETE',
        '/v1/providers/me/service-areas/i-male',
        (_) => {'_list': <Object>[]},
      );
      // The chip's × — `AppChip.input` announces it as "Remove <island>".
      await tester.tap(find.bySemanticsLabel("Remove Male'"));
      await settle(tester);

      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('onboarding-finish')))
            .onPressed,
        isNull,
      );
    });
  });

  group('§Phase 6a Done-when — the handoff into a fresh wizard draft', () {
    testWidgets('finishing reaches the wizard, not the dashboard', (
      tester,
    ) async {
      // §Phase 6a step 4: "Hand off directly into the Phase 9 wizard's Step 1,
      // pre-populated with nothing (a fresh draft)."
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      // A marker rather than the app's own builder: which SCREEN sits behind
      // `/services/new` is asserted against the real route table in
      // `phase6a_done_when_test.dart`. What this test owns is that the flow
      // pushes that name and not another.
      await pumpSignedIn(
        tester,
        routes: {
          AppRoutes.createService: (_) =>
              const Scaffold(body: Text('WIZARD STEP 1')),
          AppRoutes.providerDashboard: (_) =>
              const Scaffold(body: Text('DASHBOARD')),
        },
      );

      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await settle(tester);

      // The artboard's confirmation, naming where the handoff goes.
      expect(find.textContaining("You're all set"), findsOneWidget);
      expect(
        find.textContaining("customers on Male' can find you"),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboarding-start-service')));
      await settle(tester);

      expect(find.text('WIZARD STEP 1'), findsOneWidget);
      expect(find.text('DASHBOARD'), findsNothing);
      // Replaced, not stacked: Back from the wizard must not land on a
      // finished onboarding flow.
      expect(find.byType(BecomeProviderScreen), findsNothing);
    });

    testWidgets('"Back to service area" returns to step 3 unchanged', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      await pumpSignedIn(tester);
      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await settle(tester);
      await tester.tap(find.text('Back to service area'));
      await settle(tester);

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.byType(UnbuiltScreen), findsNothing);
    });
  });

  group('the four screen states', () {
    testWidgets('loading draws a skeleton, not a spinner or a blank', (
      tester,
    ) async {
      api.gate = Completer<void>();
      api.on('GET', '/v1/providers/me', (_) => profileJson());
      await pump(tester);

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      api.gate!.complete();
      await settle(tester);
    });

    testWidgets('an unexpected failure offers a retry that re-reads', (
      tester,
    ) async {
      api.fail('GET', '/v1/providers/me', status: 500, code: 'INTERNAL_ERROR');
      await pumpSignedIn(tester);

      expect(find.text("Couldn't load your details"), findsOneWidget);
      expect(find.textContaining('Nothing has been saved'), findsOneWidget);

      noProfile();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('a 404 is the first-time state, not an error', (tester) async {
      // §Phase 5 moved profile creation onto the write, so a customer opening
      // this flow gets a 404 by design.
      noProfile();
      await pumpSignedIn(tester);
      expect(find.text("Couldn't load your details"), findsNothing);
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });
  });

  group('nothing here exposes a phone number to anyone else', () {
    testWidgets('the number rendered is the account holder’s own', (
      tester,
    ) async {
      // §1c: exactly one endpoint in the system returns a phone number to
      // ANOTHER user. This screen shows the signed-in provider their own,
      // read from the account — the provider profile carries none.
      noProfile();
      await pumpSignedIn(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(
        api.calls.map((c) => c.path),
        isNot(contains('/v1/bookings/1/contact-info')),
      );
      // And it is never presented as a verified fact (§0.0 item 6).
      await tester.ensureVisible(find.text('+960 7771234'));
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('+960 7771234'),
            matching: find.byType(Row),
          ),
          matching: find.text('Verified'), // retired-ok: absence, not use
        ),
        findsNothing,
      );
    });
  });
}

/// Fills step 2's required fields and presses Continue. Leaves the phone and
/// the provider type alone where a test has already set them.
Future<void> _fillDetails(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('onboarding-name')),
    "Hassan's Repairs",
  );
  await tester.ensureVisible(find.text('Individual'));
  await tester.tap(find.text('Individual'));
  await settle(tester);

  await tester.ensureVisible(find.byKey(const Key('onboarding-holder')));
  await tester.enterText(
    find.byKey(const Key('onboarding-holder')),
    'Hassan Ibrahim',
  );
  await tester.enterText(
    find.byKey(const Key('onboarding-account')),
    '7730000123456',
  );

  await tester.ensureVisible(find.text('Select your bank'));
  await tester.tap(find.text('Select your bank'));
  await settle(tester);
  await tester.tap(find.text('Bank of Maldives (BML)').last);
  await settle(tester);

  await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
  await tester.tap(find.byKey(const Key('onboarding-continue')));
}

/// `AuthController` with the account already restored — the state the real app
/// reaches on boot, without scripting the boot.
class _SignedInController extends AuthController {
  _SignedInController(this._user);
  final UserAccount _user;

  @override
  AuthState build() => AuthSignedIn(_user);
}
