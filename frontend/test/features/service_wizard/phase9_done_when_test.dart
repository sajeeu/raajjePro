import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_chrome.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/islands.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 9's Done-when list, line by line:
///
/// > a service can be created end-to-end; the app can be killed mid-wizard
/// > and resumed; airplane-mode transitions queue and replay correctly;
/// > publish is blocked with the exact missing-field list; the emergency
/// > toggle is unavailable and explained on an ineligible category or
/// > unverified provider.
///
/// Plus the bullet that sits with them: *"Over-cap new-draft attempt shows an
/// upgrade prompt, not a generic error."*
void main() {
  late WizardHarness h;

  setUp(() {
    h = WizardHarness();
    h.api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
  });

  group('a service can be created end-to-end', () {
    testWidgets('from an empty draft to a published listing', (tester) async {
      // A server that applies what it is sent, including the two fields whose
      // shape differs between the request and the response.
      var listing = listingJson();
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on('GET', '/v1/providers/me', (_) => {'serviceAreas': <Object>[]});
      h.api.on('POST', '/v1/providers/me/listings', (_) => listing);
      h.api.on('PATCH', '/v1/providers/me/listings/listing-1', (body) {
        final patch = body is Map<String, dynamic>
            ? body
            : const <String, dynamic>{};
        final next = Map<String, dynamic>.of(listing);
        for (final entry in patch.entries) {
          switch (entry.key) {
            case 'serviceAreaIslandIds':
              final ids = (entry.value as List).cast<String>();
              next['serviceAreas'] = [
                for (final island in sampleIslands())
                  if (ids.contains(island['id'])) island,
              ];
            case 'coverMediaId':
              next['coverMedia'] = mediaJson(id: entry.value as String);
            default:
              if (next.containsKey(entry.key)) next[entry.key] = entry.value;
          }
        }
        listing = next;
        return next;
      });
      h.api.on(
        'POST',
        '/v1/providers/me/listings/listing-1/media',
        (_) => {
          'media': mediaJson(id: 'media-1', status: 'pending'),
          'upload': {
            'url': 'https://store.example/put?token=abc',
            'method': 'PUT',
            'headers': <String, String>{},
            'expiresAt': '2026-09-14T06:30:00.000Z',
            'maxBytes': 10485760,
          },
        },
      );
      h.api.on(
        'POST',
        '/v1/providers/me/listings/listing-1/media/media-1/complete',
        (_) => mediaJson(id: 'media-1'),
      );
      h.api.on('POST', '/v1/providers/me/listings/listing-1/publish', (_) {
        listing = Map<String, dynamic>.of(listing)..['status'] = 'published';
        return listing;
      });

      await h.open(tester);
      expect(find.text('6 required fields left to publish'), findsOneWidget);

      // Step 1 — name, category, short description.
      await typeAndSettle(
        tester,
        const Key('wizard-name'),
        'Wiring & Fault Repair',
      );
      await tapText(tester, 'Electrical');
      await typeAndSettle(
        tester,
        const Key('wizard-short-description'),
        'Fault finding, rewiring and new installations.',
      );
      expect(find.text('3 required fields left to publish'), findsOneWidget);

      // Step 2 — one island, chosen by search and saved by id.
      await goToStep(tester, 'Location');
      await tester.enterText(find.byType(TextField).first, 'kulhudhuffushi');
      await settle(tester);
      await tapText(tester, 'Kulhudhuffushi');

      // Step 3 — a pricing model and its price.
      await goToStep(tester, 'Pricing');
      await tapText(tester, 'Fixed price');
      await typeAndSettle(tester, const Key('wizard-price'), '450');

      // Step 4 — the cover image, the sixth required field (§0.2 item 4).
      await goToStep(tester, 'Media');
      await tapKey(tester, const Key('wizard-cover-upload'));

      expect(find.text('Ready to publish'), findsOneWidget);

      await goToStep(tester, 'Review');
      expect(find.byKey(const Key('wizard-ready')), findsOneWidget);
      await tapKey(tester, const Key('wizard-publish'));
      await settle(tester);

      expect(find.text('Your service is live'), findsOneWidget);
      expect(
        h.api.calls.map((c) => '${c.method} ${c.path}'),
        contains('POST /v1/providers/me/listings/listing-1/publish'),
      );
    });
  });

  group('the app can be killed mid-wizard and resumed', () {
    testWidgets('what was typed is on the server, not on the device', (
      tester,
    ) async {
      h.scriptFreshDraft();
      h.scriptEchoingPatch();
      await h.open(tester);
      await typeAndSettle(tester, const Key('wizard-name'), 'Wiring');

      // The step persisted before anything was "killed" — that is what makes
      // resume work without a local draft.
      expect(h.patchBodies().last, {'name': 'Wiring'});

      // The app comes back: a new widget tree, a new container, nothing
      // carried over. §Phase 10's dashboard is what will pass the id.
      final resumed = WizardHarness();
      resumed.api.on(
        'GET',
        '/v1/categories',
        (_) => {'_list': sampleCategories()},
      );
      resumed.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(name: 'Wiring', categoryId: 'cat-electrical'),
      );
      await resumed.open(tester, listingId: 'listing-1');

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('wizard-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, 'Wiring');
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);
    });
  });

  group('airplane-mode transitions queue and replay correctly', () {
    testWidgets('the step is kept, said to be kept, and sent on reconnect', (
      tester,
    ) async {
      h.scriptFreshDraft();
      h.scriptEchoingPatch();
      await h.open(tester);

      // Airplane mode on.
      h.api.offline('PATCH', '/v1/providers/me/listings/listing-1');
      await typeAndSettle(tester, const Key('wizard-name'), 'Wiring');

      // It says what is true: the change is on the device and will send.
      expect(
        find.text(
          "You're offline — changes are queued and will sync automatically.",
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<SavePill>(find.byType(SavePill)).state,
        SaveState.offline,
      );
      expect(h.store.saved.single.body, {'name': 'Wiring'});

      // Still offline, still editable, and the queue does not grow per
      // keystroke — one PATCH holds the latest of everything.
      await typeAndSettle(
        tester,
        const Key('wizard-short-description'),
        'Fault finding and rewiring.',
      );
      expect(h.store.saved, hasLength(1));
      expect(h.store.saved.single.body, {
        'name': 'Wiring',
        'shortDescription': 'Fault finding and rewiring.',
      });

      // Navigation is not blocked by being offline: the queue accepting the
      // write *is* persistence.
      await goToStep(tester, 'Pricing');
      expect(find.text('Step 3 of 7 · Pricing'), findsOneWidget);

      // Airplane mode off. The banner carries no button of its own — it says
      // the queue syncs automatically, and it does: the wizard replays when
      // the app comes back to the foreground, which is the most likely moment
      // a provider has regained a signal.
      h.scriptEchoingPatch();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(h.store.saved, isEmpty);
      expect(h.patchBodies().last, {
        'name': 'Wiring',
        'shortDescription': 'Fault finding and rewiring.',
      });
    });
  });

  group('publish is blocked with the exact missing-field list', () {
    testWidgets('every missing field gets its own row and its own Fix', (
      tester,
    ) async {
      h.scriptFreshDraft();
      h.scriptEchoingPatch();
      await h.open(tester);
      await goToStep(tester, 'Review');

      await tapKey(tester, const Key('wizard-publish'));

      // Not a generic "form invalid": a row per field, each naming the step
      // that owns it, so fixing it is one tap rather than a hunt.
      final card = find.byKey(const Key('wizard-missing-fields'));
      expect(find.text('6 required fields missing'), findsOneWidget);
      for (final label in [
        'Service name',
        'Category',
        'Short description',
        'At least one island',
        'How the price works',
        'Cover image',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
        );
      }

      // And nothing was sent — the client does not ask the server to refuse
      // something it can already see is incomplete.
      expect(
        h.api.calls.map((c) => c.path),
        isNot(contains('/v1/providers/me/listings/listing-1/publish')),
      );

      await tester.tap(
        find.descendant(of: card, matching: find.text('At least one island')),
      );
      await settle(tester);
      expect(find.text('Location & service area'), findsOneWidget);
    });

    testWidgets('the server’s own list wins when it refuses', (tester) async {
      // A listing the client believes is complete — the server disagrees,
      // because the cover upload never finished (invariant 4).
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => publishableListingJson(),
      );
      h.api.fail(
        'POST',
        '/v1/providers/me/listings/listing-1/publish',
        status: 422,
        code: 'LISTING_INCOMPLETE',
        message: 'One required field is still empty',
        details: const [
          {
            'field': 'coverMediaId',
            'step': 'media',
            'message': 'Cover image (the upload did not finish)',
          },
        ],
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Review');

      await tapKey(tester, const Key('wizard-publish'));

      expect(find.text('1 required field missing'), findsOneWidget);
      expect(
        find.text('Cover image (the upload did not finish)'),
        findsOneWidget,
      );
    });
  });

  group('over-cap shows an upgrade prompt, not a generic error', () {
    testWidgets('it names the live listing and says the draft is safe', (
      tester,
    ) async {
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => publishableListingJson(),
      );
      h.api.fail(
        'POST',
        '/v1/providers/me/listings/listing-1/publish',
        status: 409,
        code: 'LISTING_CAP_REACHED',
        message: 'Your plan publishes one service at a time',
        details: const {
          'activeListingCap': 1,
          'activeListingCount': 1,
          'liveListings': [
            {'id': 'listing-0', 'name': 'Emergency Plumbing & Pipe Repair'},
          ],
        },
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Review');

      await tapKey(tester, const Key('wizard-publish'));
      await settle(tester);

      // The two refusals are different codes for exactly this reason: one is
      // a list of fields to fix, and this one is a choice about a plan.
      expect(
        find.text('Your plan publishes one service at a time'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Emergency Plumbing & Pipe Repair is already live'),
        findsOneWidget,
      );
      expect(
        find.textContaining("This draft is saved and isn't going anywhere"),
        findsOneWidget,
      );
      expect(find.text('See what upgrading allows'), findsOneWidget);
      expect(
        find.text('Drafts stay in My Services — nothing is lost.'),
        findsOneWidget,
      );
      // Not the missing-field card, and not a generic failure.
      expect(find.byKey(const Key('wizard-missing-fields')), findsNothing);
      expect(find.byType(NoticeBanner), findsNothing);
    });
  });

  group('the emergency toggle', () {
    testWidgets('is unavailable and explained on an ineligible tier', (
      tester,
    ) async {
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(
          categoryId: 'cat-electrical',
          emergencyAllowed: false,
          emergencyReason:
              'Emergency Electrical work needs gold verification; this '
              'account is silver',
          emergencyRequiredTier: 'gold',
          emergencyCurrentTier: 'silver',
        ),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Availability');

      // The **server's** sentence, naming the bar and the current tier.
      // Nothing in the app compares a tier to a bar (§1c, invariant 4).
      expect(
        find.text(
          'Emergency Electrical work needs gold verification; this account '
          'is silver',
        ),
        findsOneWidget,
      );

      await tapKey(tester, const Key('wizard-emergency'));
      expect(
        h.patchBodies().where((b) => b.containsKey('isEmergency')),
        isEmpty,
      );
    });

    testWidgets('is unavailable and explained on an ineligible category', (
      tester,
    ) async {
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(
          categoryId: 'cat-cleaning',
          emergencyAllowed: false,
          emergencyReason: 'Cleaning does not offer emergency callouts',
        ),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Availability');

      expect(
        find.text('Cleaning does not offer emergency callouts'),
        findsOneWidget,
      );
    });

    testWidgets('and works where the server says it is allowed', (
      tester,
    ) async {
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(categoryId: 'cat-ac', emergencyAllowed: true),
      );
      h.scriptEchoingPatch(
        base: listingJson(categoryId: 'cat-ac', emergencyAllowed: true),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Availability');

      await tapKey(tester, const Key('wizard-emergency'));

      expect(h.patchBodies().last, {'isEmergency': true});
    });
  });

  group('step navigation waits for persistence, never for validation', () {
    testWidgets('Continue says so while the step is still saving', (
      tester,
    ) async {
      h.scriptFreshDraft();
      h.scriptEchoingPatch();
      await h.open(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('wizard-name')),
          matching: find.byType(TextField),
        ),
        'Wiring',
      );
      await tester.pump();

      // The save is still behind its debounce when Continue is tapped.
      h.api.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('wizard-continue')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Saving this step…'), findsOneWidget);
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);

      h.api.gate!.complete();
      h.api.gate = null;
      await settle(tester);

      expect(find.text('Step 2 of 7 · Location'), findsOneWidget);
      expect(h.patchBodies().last, {'name': 'Wiring'});
    });
  });
}
