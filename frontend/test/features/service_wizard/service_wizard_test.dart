import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/features/service_wizard/presentation/service_wizard_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/islands.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 9, step by step.
///
/// The Done-when list is asserted separately in `phase9_done_when_test.dart`;
/// this file is the behaviour underneath it — what each step renders, what it
/// saves, and what it refuses to claim.
void main() {
  late WizardHarness h;

  setUp(() {
    h = WizardHarness();
    h.scriptFreshDraft();
    h.scriptEchoingPatch();
  });

  group('the shell', () {
    testWidgets('leads with required fields, not the step count', (
      tester,
    ) async {
      await h.open(tester);

      // §Phase 9: "N required fields left to publish" alongside or instead of
      // "Step 1 of 7" — leading with the step count overstates the commitment.
      expect(find.text('6 required fields left to publish'), findsOneWidget);
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);
    });

    testWidgets('says so when nothing is left', (tester) async {
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => publishableListingJson(),
      );
      await h.open(tester, listingId: 'listing-1');

      expect(find.text('Ready to publish'), findsOneWidget);
    });

    testWidgets('a dropped connection opens the no-connection state', (
      tester,
    ) async {
      h.api.offline('GET', '/v1/categories');
      await h.open(tester);

      // Not a generic error: the two call for different actions, and this one
      // carries the retry and the list of what still works offline.
      expect(find.byType(NoConnectionView), findsOneWidget);
      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('Saving a step of the service wizard'), findsOneWidget);
    });

    testWidgets('any other failure gets the error state with a retry', (
      tester,
    ) async {
      h.api.fail(
        'POST',
        '/v1/providers/me/listings',
        status: 500,
        code: 'INTERNAL',
      );
      await h.open(tester);

      expect(find.text("We couldn't open your draft"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('step navigation', () {
    testWidgets('review is reachable from step 1 with nothing filled in', (
      tester,
    ) async {
      await h.open(tester);

      await goToStep(tester, 'Review');

      expect(find.text('Review & publish'), findsOneWidget);
      expect(find.byKey(const Key('wizard-missing-fields')), findsOneWidget);
    });

    testWidgets('every step is reachable in any order', (tester) async {
      await h.open(tester);

      for (final label in [
        'Extras',
        'Pricing',
        'Availability',
        'Media',
        'Location',
        'Details',
      ]) {
        await goToStep(tester, label);
        expect(
          find.text('Step ${_stepNumber(label)} of 7 · $label'),
          findsOneWidget,
        );
      }
    });

    testWidgets('a step still missing a required field carries a dot', (
      tester,
    ) async {
      await h.open(tester);
      // Spoken, not colour alone.
      expect(
        find.bySemanticsLabel('Pricing, required fields still empty'),
        findsOneWidget,
      );
    });
  });

  group('step 1 — details', () {
    testWidgets('autosaves the name after the debounce, once', (tester) async {
      await h.open(tester);

      await typeAndSettle(tester, const Key('wizard-name'), 'Wiring');

      expect(h.patchBodies(), [
        {'name': 'Wiring'},
      ]);
    });

    testWidgets('tags are the category’s own suggestions, not a local map', (
      tester,
    ) async {
      await h.open(tester);

      // With no category there is nothing to suggest, and the step says what
      // to do rather than rendering an empty row of chips.
      expect(
        find.text(
          "Choose a category above first — we'll suggest tags customers "
          'actually search for.',
        ),
        findsOneWidget,
      );

      await tapText(tester, 'Electrical');

      // Exactly what `Category.suggestedTags` carried — §Phase 8 seeds them
      // and nothing in Flutter holds a second copy.
      expect(find.text('SUGGESTED FOR ELECTRICAL'), findsOneWidget);
      for (final tag in ['Wiring', 'Fault finding', 'Rewiring', 'Lighting']) {
        expect(find.text(tag), findsOneWidget);
      }
    });

    testWidgets('a suggested chip saves the whole tag set', (tester) async {
      await h.open(tester);
      await tapText(tester, 'Electrical');

      await tapText(tester, 'Fault finding');

      expect(h.patchBodies().last, {
        'tags': ['Fault finding'],
      });
    });

    testWidgets('free text underneath adds anything not covered', (
      tester,
    ) async {
      await h.open(tester);
      await tapText(tester, 'Electrical');

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('wizard-custom-tag')),
          matching: find.byType(TextField),
        ),
        'Solar inverters',
      );
      await tapText(tester, 'Add');

      expect(h.patchBodies().last, {
        'tags': ['Solar inverters'],
      });
    });

    testWidgets('the activity categories get the one-offering guidance', (
      tester,
    ) async {
      await h.open(tester);

      await tapText(tester, 'Photography');

      expect(
        find.text(
          "Name the specific service — 'Fishing Trip', 'Wedding "
          "Photography'. Customers book the offering, not the category.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a trade category keeps the plain helper', (tester) async {
      await h.open(tester);

      await tapText(tester, 'Electrical');

      expect(find.text('What customers see first in results.'), findsOneWidget);
    });
  });

  group('step 2 — location', () {
    testWidgets('embeds Phase 7’s island control and saves ids', (
      tester,
    ) async {
      h.api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
      h.api.on('GET', '/v1/islands?search=meedhoo', (_) {
        return {
          '_list': [
            for (final island in sampleIslands())
              if (island['name'] == 'Meedhoo') island,
          ],
        };
      });
      await h.open(tester);
      await goToStep(tester, 'Location');

      expect(find.byType(IslandMultiSelect), findsOneWidget);
      expect(
        find.text(
          'Pre-filled from your default coverage areas. Edit freely — '
          'changes here apply to this service only.',
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, 'meedhoo');
      await settle(tester);
      // Three Meedhoos, each qualified by its atoll — the name alone is not an
      // identifier (§0.0 item 12).
      expect(find.text('Dh. Meedhoo'), findsOneWidget);
      await tapText(tester, 'Dh. Meedhoo');

      expect(h.patchBodies().last, {
        'serviceAreaIslandIds': ['i-meedhoo-dh'],
      });
    });
  });

  group('step 3 — pricing', () {
    testWidgets('money goes out as integer laari', (tester) async {
      await h.open(tester);
      await goToStep(tester, 'Pricing');
      await tapText(tester, 'Fixed price');

      await typeAndSettle(tester, const Key('wizard-price'), '450');

      // MVR 450 = 45000 laari (invariant 7), never a float and never a
      // decimal string.
      expect(h.patchBodies().last, {'priceLaari': 45000});
    });

    testWidgets('range and quote force request mode in the same write', (
      tester,
    ) async {
      await h.open(tester);
      await goToStep(tester, 'Pricing');

      await tapText(tester, 'Price on request');

      expect(h.patchBodies().last, {
        'pricingModel': 'quote',
        'bookingMode': 'request',
      });
    });

    testWidgets('the card preview says what a customer will read', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => publishableListingJson(),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Pricing');

      expect(
        find.text('On your card, customers see: MVR 450/visit'),
        findsOneWidget,
      );
    });

    testWidgets('there are no Service Packages', (tester) async {
      await h.open(tester);
      await goToStep(tester, 'Pricing');

      // Round 16 removed them; tiers stay post-v1.
      expect(find.textContaining('Package'), findsNothing);
    });
  });

  group('step 5 — availability', () {
    testWidgets('has no Accepting New Customers toggle', (tester) async {
      await h.open(tester);
      await goToStep(tester, 'Availability');

      // Round 16: account-level (§Phase 5), and §Phase 8a's billing pause keys
      // off it — a per-listing copy would be actively wrong.
      expect(find.textContaining('Accepting New Customers'), findsNothing);
      expect(find.textContaining('accepting new customers'), findsNothing);
    });

    testWidgets('a slot listing still needs the provider to accept', (
      tester,
    ) async {
      await h.open(tester);
      await goToStep(tester, 'Availability');

      // Round 56 / §0.0 item 13 — never "Book instantly".
      expect(
        find.text(
          'Customers pick from the times you publish, then you accept.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('slot mode is refused with its reason on quote pricing', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(pricingModel: 'quote', bookingMode: 'request'),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Availability');

      expect(
        find.text(
          'Price on request pricing can’t be booked as a fixed slot — switch '
          'pricing to enable this.',
        ),
        findsOneWidget,
      );

      await tapKey(tester, const Key('booking-mode-slot'));
      expect(
        h.patchBodies().where((b) => b.containsKey('bookingMode')),
        isEmpty,
      );
    });

    testWidgets('the emergency window is the category’s own number', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(categoryId: 'cat-ac', emergencyAllowed: true),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Availability');

      // Read from `emergencyAcceptWindowMinutes` — 30 for every emergency
      // category, Moving included (Round 22), and never written down here.
      expect(
        find.textContaining('Customers expect a response within 30 minutes.'),
        findsOneWidget,
      );
    });
  });

  group('step 6 — extras', () {
    testWidgets('attributes the warranty rather than asserting it', (
      tester,
    ) async {
      await h.open(tester);
      await goToStep(tester, 'Extras');

      expect(
        find.text(
          "RaajjePro doesn't check warranty or insurance details. Customers "
          'see them exactly as you write them, marked "Provider states: …"',
        ),
        findsOneWidget,
      );
      // §1i: never a check mark, a shield, a lock or the word *verified* on
      // either field — those belong to `verificationTier`, which means
      // something because a human checked it.
      expect(find.textContaining('Verified'), findsNothing); // retired-ok:
      expect(find.textContaining('verified'), findsNothing);
    });

    testWidgets('the FAQs accordion appears once', (tester) async {
      await h.open(tester);
      await goToStep(tester, 'Extras');

      // The delivered mockup drew it twice.
      expect(find.text('FAQs'), findsOneWidget);
    });

    testWidgets('an FAQ is saved as the whole list', (tester) async {
      await h.open(tester);
      await goToStep(tester, 'Extras');

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('wizard-faq-question')),
          matching: find.byType(TextField),
        ),
        'Do you supply materials?',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('wizard-faq-answer')),
          matching: find.byType(TextField),
        ),
        'Yes — billed at cost.',
      );
      await settle(tester);
      await tapText(tester, 'Add');

      expect(h.patchBodies().last, {
        'faqs': [
          {
            'question': 'Do you supply materials?',
            'answer': 'Yes — billed at cost.',
          },
        ],
      });
    });

    testWidgets('the callback guarantee is absent on an ineligible category', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(categoryId: 'cat-cleaning'),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Extras');

      // Round 28: absent, not disabled. A promise to redo a house clean for
      // free has no referent.
      expect(find.text('Callback guarantee'), findsNothing);
      expect(find.byKey(const Key('wizard-callback')), findsNothing);
    });

    testWidgets('and present, in its own treatment, on an eligible one', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/listings/listing-1',
        (_) =>
            listingJson(categoryId: 'cat-electrical', callbackAvailable: true),
      );
      await h.open(tester, listingId: 'listing-1');
      await goToStep(tester, 'Extras');

      expect(find.byKey(const Key('wizard-callback')), findsOneWidget);
      // §1i's distinction that must not blur: this one RaajjePro enforces.
      expect(find.text('Enforced by RaajjePro'), findsOneWidget);
    });
  });

  group('step 4 — media', () {
    testWidgets('uploads in three steps and sets the cover', (tester) async {
      h.api.on(
        'POST',
        '/v1/providers/me/listings/listing-1/media',
        (_) => {
          'media': mediaJson(id: 'media-1', status: 'pending'),
          'upload': {
            'url': 'https://store.example/put?token=abc',
            'method': 'PUT',
            'headers': {'content-type': 'image/jpeg'},
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
      h.scriptPatch((_) => listingJson(coverMedia: mediaJson(id: 'media-1')));
      await h.open(tester);
      await goToStep(tester, 'Media');

      await tapKey(tester, const Key('wizard-cover-upload'));

      expect(h.uploader.calls, 1);
      expect(h.patchBodies().last, {'coverMediaId': 'media-1'});
    });

    testWidgets('a failed upload keeps the bytes and offers Retry', (
      tester,
    ) async {
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
      h.uploader.throws = const ApiNetworkException();
      await h.open(tester);
      await goToStep(tester, 'Media');

      await tapKey(tester, const Key('wizard-cover-upload'));

      expect(find.text('Upload failed'), findsOneWidget);
      final pickCalls = h.picker.calls;
      await tapKey(tester, const Key('wizard-upload-retry'));
      // Retry re-sends what was chosen; it does not reopen the picker.
      expect(h.picker.calls, pickCalls);
      expect(h.uploader.calls, 2);
    });

    testWidgets('an unsupported file is refused before any upload starts', (
      tester,
    ) async {
      h.picker.result = const PickedImageResult.failed(
        PickFailure.unsupportedType,
      );
      await h.open(tester);
      await goToStep(tester, 'Media');

      await tapKey(tester, const Key('wizard-cover-upload'));

      expect(
        find.text('That file type is not supported — use a JPG, PNG or WEBP.'),
        findsOneWidget,
      );
      expect(h.uploader.calls, 0);
    });
  });
  group('leaving the wizard', () {
    testWidgets('the header back control walks the steps, then leaves', (
      tester,
    ) async {
      await h.openPushed(tester);
      await goToStep(tester, 'Pricing');

      await tester.tap(find.byType(CircleBackButton));
      await settle(tester);
      expect(find.text('Step 2 of 7 · Location'), findsOneWidget);

      await tester.tap(find.byType(CircleBackButton));
      await settle(tester);
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);

      // From step 1 it leaves the flow rather than sitting there.
      await tester.tap(find.byType(CircleBackButton));
      await settle(tester);
      await settle(tester);
      expect(find.byType(ServiceWizardScreen), findsNothing);
      expect(find.text('Open wizard'), findsOneWidget);
    });

    testWidgets('"Save draft" leaves rather than stepping back', (
      tester,
    ) async {
      await h.openPushed(tester);
      await goToStep(tester, 'Review');

      await tester.tap(find.text('Save draft'));
      await settle(tester);
      await settle(tester);

      // It writes nothing new — every step autosaved on its way past — and it
      // is the way out, not a step backwards.
      expect(find.byType(ServiceWizardScreen), findsNothing);
      expect(find.text('Open wizard'), findsOneWidget);
    });
  });
}

int _stepNumber(String label) => switch (label) {
  'Details' => 1,
  'Location' => 2,
  'Pricing' => 3,
  'Media' => 4,
  'Availability' => 5,
  'Extras' => 6,
  _ => 7,
};
