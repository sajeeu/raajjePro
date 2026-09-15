import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/my_services/presentation/widgets/service_card.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 10's My Services dashboard: the states it renders, the two controls
/// that change a listing's visibility, and the two entry points that hang off
/// a listing rather than sitting inside it.
///
/// The Done-when list is asserted separately, in
/// `phase10_done_when_test.dart`, through the real route table.
void main() {
  late MyServicesHarness h;

  setUp(() => h = MyServicesHarness());

  /// The filter pill, not the status badge — "Draft" and "Published" are both
  /// a filter and a listing state on this screen, which is exactly why the
  /// stats tile above them says "Live" rather than a third reading of the
  /// same two words.
  Finder pill(String label) =>
      find.descendant(of: find.byType(AppChip), matching: find.text(label));

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  Map<String, dynamic> livePublished({
    String id = 'listing-1',
    String name = 'AC Service & Repair',
    String categoryId = 'cat-ac',
    int viewCount = 784,
    int bookingCount = 64,
    String visibility = 'active',
    String updatedAt = '2026-09-14T06:00:00.000Z',
  }) =>
      publishableListingJson(
          id: id,
          categoryId: categoryId,
          status: 'published',
        ).cast<String, dynamic>()
        ..['name'] = name
        ..['visibility'] = visibility
        ..['viewCount'] = viewCount
        ..['bookingCount'] = bookingCount
        ..['updatedAt'] = updatedAt
        ..['publishedAt'] = '2026-09-01T06:00:00.000Z'
        ..['missingRequiredFields'] = const <Map<String, dynamic>>[];

  group('the four states every screen owes', () {
    testWidgets('a skeleton while the four reads are in flight', (
      tester,
    ) async {
      h.api.gate = Completer<void>();
      h.script(listings: [livePublished()], categories: sampleCategories());
      await h.pump(tester);

      expect(find.byType(SkeletonLoader), findsWidgets);
      expect(find.byType(ServiceCard), findsNothing);

      h.api.gate!.complete();
      await settle(tester);
      expect(find.byType(ServiceCard), findsOneWidget);
    });

    testWidgets('an error state that says the listings are safe, and retries', (
      tester,
    ) async {
      h.script(listings: const [], categories: sampleCategories());
      h.api.offline('GET', '/v1/providers/me/listings?limit=50');
      await h.pump(tester);

      expect(find.text('Couldn’t load your services'), findsOneWidget);
      expect(find.textContaining('Your listings are safe'), findsOneWidget);

      // Retrying re-reads rather than leaving the provider on a dead screen.
      h.script(listings: [livePublished()], categories: sampleCategories());
      await tapVisible(tester, find.text('Try again'));
      expect(find.byType(ServiceCard), findsOneWidget);
    });

    testWidgets('a provider with nothing at all is told what to do next', (
      tester,
    ) async {
      h.script(listings: const [], categories: sampleCategories());
      await h.pump(tester);

      expect(find.text('No services yet'), findsOneWidget);
      expect(find.text('Create service'), findsOneWidget);
      // No filter pills over an empty list — there is nothing to filter.
      expect(find.text('Published'), findsNothing);
    });

    testWidgets('a populated dashboard totals what the server rolled up', (
      tester,
    ) async {
      h.script(
        listings: [
          livePublished(viewCount: 300, bookingCount: 20),
          livePublished(
            id: 'listing-2',
            name: 'Home Deep Cleaning',
            categoryId: 'cat-cleaning',
            viewCount: 12,
            bookingCount: 3,
          ),
        ],
        categories: sampleCategories(),
      );
      await h.pump(tester);

      expect(find.byType(ServiceCard), findsNWidgets(2));
      expect(find.text('Live'), findsWidgets);
      expect(find.text('312'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
    });
  });

  group('the card', () {
    testWidgets('is a container, so the controls on it still exist', (
      tester,
    ) async {
      // The regression this screen was built through: a tappable card excludes
      // its descendants from the semantics tree, which erased the overflow
      // menu, the live toggle and Finish & publish in one go. `AppCard` with
      // an `onTap` here would put them back out of reach.
      h.script(listings: [livePublished()], categories: sampleCategories());
      await h.pump(tester);

      expectNoSwallowedControls(tester);
    });

    testWidgets('prints the category, the status and the price a customer '
        'will read', (tester) async {
      h.script(listings: [livePublished()], categories: sampleCategories());
      await h.pump(tester);

      expect(find.text('AC Repair'), findsOneWidget);
      expect(find.text('Published'), findsWidgets);
      // `customerPricePreview` — the wizard's own string, not a second one.
      expect(find.textContaining('MVR'), findsWidgets);
      expect(find.text('Updated 2 days ago'), findsOneWidget);
    });

    testWidgets('a draft offers Finish & publish rather than a live toggle', (
      tester,
    ) async {
      h.script(
        listings: [listingJson(categoryId: 'cat-ac', name: 'Half-typed')],
        categories: sampleCategories(),
      );
      await h.pump(tester);

      expect(find.text('Finish & publish'), findsOneWidget);
      expect(find.byType(AppToggle), findsNothing);
      expect(find.text('Draft'), findsWidgets);
    });

    testWidgets('an over-cap listing explains the limit and never offers a '
        'toggle that would be refused', (tester) async {
      h.script(
        listings: [
          livePublished(),
          livePublished(
            id: 'listing-2',
            name: 'Home Deep Cleaning',
            categoryId: 'cat-cleaning',
            visibility: 'hidden_over_cap',
          ),
        ],
        categories: sampleCategories(),
      );
      await h.pump(tester);

      expect(
        find.textContaining('Your free plan includes 1 live service'),
        findsOneWidget,
      );
      expect(find.text('Upgrade'), findsOneWidget);
      expect(find.text('Make this one live instead'), findsOneWidget);
      // One toggle, on the listing that is actually the provider's to pause.
      expect(find.byType(AppToggle), findsOneWidget);
    });
  });

  group('filters and layout', () {
    testWidgets('the pills switch over what is already loaded, without a '
        'second read', (tester) async {
      h.script(
        listings: [
          livePublished(),
          listingJson(categoryId: 'cat-ac', name: 'Half-typed'),
        ],
        categories: sampleCategories(),
      );
      await h.pump(tester);
      final readsBefore = h.listingCalls.length;

      await tapVisible(tester, pill('Draft'));
      expect(find.byType(ServiceCard), findsOneWidget);
      expect(find.text('Half-typed'), findsOneWidget);

      await tapVisible(tester, pill('Published'));
      expect(find.text('AC Service & Repair'), findsOneWidget);
      expect(find.text('Half-typed'), findsNothing);

      // Filtering is not a fetch: the totals above the list would otherwise
      // disagree with the list under them.
      expect(h.listingCalls.length, readsBefore);
    });

    testWidgets('an empty filter names what to do rather than reporting '
        'emptiness', (tester) async {
      h.script(listings: [livePublished()], categories: sampleCategories());
      await h.pump(tester);

      await tapVisible(tester, pill('Draft'));

      expect(find.text('No drafts'), findsOneWidget);
      expect(find.byType(ServiceCard), findsNothing);
    });

    testWidgets('the grid toggle swaps the card, keeping the same listings', (
      tester,
    ) async {
      h.script(
        listings: [
          livePublished(),
          livePublished(id: 'listing-2'),
        ],
        categories: sampleCategories(),
      );
      await h.pump(tester);
      expect(find.byType(ServiceCard), findsNWidgets(2));

      await tapVisible(tester, find.bySemanticsLabel('Grid view'));

      expect(find.byType(ServiceCard), findsNothing);
      expect(find.byType(ServiceGridCard), findsNWidgets(2));
    });
  });

  group('the live toggle', () {
    testWidgets('pauses through the visibility endpoint and updates in place', (
      tester,
    ) async {
      h.script(listings: [livePublished()], categories: sampleCategories());
      h.api.on(
        'PATCH',
        '/v1/providers/me/listings/listing-1/visibility',
        (_) => livePublished(visibility: 'hidden_by_provider'),
      );
      await h.pump(tester);

      await tapVisible(tester, find.byType(AppToggle));

      final patch = h.listingCalls.last;
      expect(patch.method, 'PATCH');
      expect(patch.body, {'visibility': 'hidden_by_provider'});
      // The card now reads Hidden, and nothing re-listed to find that out.
      expect(find.text('Hidden'), findsWidgets);
      expect(
        h.listingCalls.where((c) => c.method == 'GET').length,
        1,
        reason: 'the opening read, and no refresh after the mutation',
      );
    });

    testWidgets('a refusal puts the card back and says why', (tester) async {
      h.script(
        listings: [livePublished(visibility: 'hidden_by_provider')],
        categories: sampleCategories(),
      );
      h.api.fail(
        'PATCH',
        '/v1/providers/me/listings/listing-1/visibility',
        status: 422,
        code: 'LISTING_CAP_REACHED',
        message: 'Your plan allows 1 live service',
      );
      await h.pump(tester);

      await tapVisible(tester, find.byType(AppToggle));

      expect(find.text('Your plan allows 1 live service'), findsOneWidget);
      // Rolled back visibly: still Hidden, not optimistically Published.
      expect(find.text('Hidden'), findsWidgets);
    });
  });

  group('§1b’s over-cap override', () {
    testWidgets('"Make this one live instead" sets the pin and re-reads, '
        'because a second listing changed too', (tester) async {
      h.script(
        listings: [
          livePublished(),
          livePublished(
            id: 'listing-2',
            name: 'Home Deep Cleaning',
            categoryId: 'cat-cleaning',
            visibility: 'hidden_over_cap',
          ),
        ],
        categories: sampleCategories(),
      );
      h.api.on(
        'POST',
        '/v1/providers/me/listings/listing-2/keep-visible',
        (_) => livePublished(id: 'listing-2', name: 'Home Deep Cleaning'),
      );
      await h.pump(tester);

      // After the pin the server has swapped which one is hidden.
      h.api.on(
        'GET',
        '/v1/providers/me/listings?limit=50',
        (_) => {
          '_list': [
            livePublished(visibility: 'hidden_over_cap'),
            livePublished(
              id: 'listing-2',
              name: 'Home Deep Cleaning',
              categoryId: 'cat-cleaning',
            ),
          ],
          '_meta': <String, dynamic>{},
        },
      );

      await tapVisible(tester, find.text('Make this one live instead'));

      final pin = h.listingCalls.firstWhere((c) => c.method == 'POST');
      expect(pin.path, '/v1/providers/me/listings/listing-2/keep-visible');
      // **No `PATCH …/visibility` anywhere.** The two-step hide-then-activate
      // would write `hidden_by_provider` onto a listing the entitlement
      // system hid, and §1b's restore depends on it not being written
      // (`docs/decisions/25-phase-10-two-questions-answered.md`).
      expect(
        h.listingCalls.map((c) => c.path),
        isNot(contains(contains('/visibility'))),
      );
      expect(find.textContaining('the other is hidden'), findsOneWidget);
    });
  });

  group('the entry points that hang off a listing', () {
    testWidgets('availability appears only where a listing has a slot grid', (
      tester,
    ) async {
      // Request-mode only: §Phase 9a's screen would have nothing to draw.
      h.script(listings: [livePublished()], categories: sampleCategories());
      await h.pump(tester);
      expect(find.text('Availability & time slots'), findsNothing);
      // Absent, not disabled — and My Calendar is account-wide, so it stays.
      expect(find.text('My Calendar'), findsOneWidget);
    });

    testWidgets('and names the service when there is exactly one', (
      tester,
    ) async {
      h.script(
        listings: [
          livePublished(
            id: 'listing-2',
            name: 'Home Deep Cleaning',
            categoryId: 'cat-cleaning',
          ),
        ],
        categories: sampleCategories(),
      );
      await h.pump(tester);

      expect(find.text('Availability & time slots'), findsOneWidget);
      expect(find.text('Home Deep Cleaning'), findsWidgets);
    });

    testWidgets('verification is a real row, owed by the phase that builds '
        'the evidence flow', (tester) async {
      h.script(listings: const [], categories: sampleCategories());
      await h.pump(tester);

      await tapVisible(tester, find.text('Verification'));

      expect(find.byType(UnbuiltScreen), findsOneWidget);
      expect(find.textContaining('Phase 23'), findsWidgets);
    });
  });
}
