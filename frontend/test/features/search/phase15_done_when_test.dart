import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/location/browsing_island_controller.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/search/controller/search_controller.dart';
import 'package:raajjepro/features/search/presentation/search_copy.dart';
import 'package:raajjepro/features/search/presentation/search_results_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/provider_profile.dart';
import '../../helpers/pump.dart';
import '../../helpers/saved.dart';
import '../bookings/harness.dart' show FixedAuthController;

/// The search endpoint, played from a script. Each request's query string is
/// recorded, so a test asserts what the screen *asked for*. Ordering and
/// membership are the server's job, and `backend/test/phase15-done-when.test.ts`
/// proves them.
class SearchFakeApi extends FavoritesFakeApi {
  final requests = <Map<String, String>>[];

  /// Answers one request. The default is an empty set.
  Map<String, dynamic> Function(Map<String, String> query) answer = (_) =>
      page(const []);

  Object? failWith;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (!path.startsWith('/v1/search/listings')) return super.get(path);
    final query = Uri.parse(path).queryParameters;
    calls.add((method: 'GET', path: path, body: null));
    if (gate != null) await gate!.future;
    final failure = failWith;
    if (failure != null) throw failure;
    requests.add(query);
    return answer(query);
  }
}

Map<String, dynamic> page(
  List<Map<String, dynamic>> items, {
  int? total,
  String? nextCursor,
}) => {
  'total': total ?? items.length,
  'items': items,
  '_meta': {'nextCursor': nextCursor},
};

Map<String, dynamic> result({
  required String id,
  String name = 'Sofa Shampoo',
  String bookingMode = 'request',
  bool sponsored = false,
}) => {
  'listing': listingCardJson(
    id: id,
    name: name,
    bookingMode: bookingMode,
    pricingModel: 'fixed',
    priceLaari: 45000,
    priceMinLaari: null,
    priceUnit: 'visit',
  ),
  'provider': providerProfileJson(
    id: 'prov-$id',
    businessName: 'Biz $id',
  )['provider'],
  'sponsored': sponsored,
};

class _FixedIsland extends BrowsingIslandController {
  _FixedIsland(this._island);
  final Island? _island;
  @override
  Island? build() => _island;
}

const _hulhumale = Island(
  id: 'isl-hulhumale',
  name: "Hulhumale'",
  displayName: 'Hulhumalé',
  atollName: 'Kaafu',
  atollAbbr: 'K',
  nameAmbiguous: false,
);

/// §Phase 15 — **Done when:** "results are correct, paginated, and
/// filtered; priority placement never surfaces an irrelevant listing; every
/// boosted result is labelled; every card states its booking mode."
///
/// This is the client's half of each clause: it asks for what the customer
/// chose, it pages by the server's cursor, it labels what the server says
/// was boosted, and it states every card's mode. "Never surfaces an
/// irrelevant listing" is a membership rule the server holds, and the
/// backend suite tests it.
void main() {
  late SearchFakeApi api;
  late Map<String, Object?> pushed;

  setUp(() {
    api = SearchFakeApi();
    pushed = {};
    api.on('GET', '/v1/categories', (_) => {'_list': <Object>[]});
  });

  List<Override> overrides({Island? island}) => [
    apiClientProvider.overrideWithValue(api),
    clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 15, 3)),
    authControllerProvider.overrideWith(
      () => FixedAuthController(const AuthGuest()),
    ),
    browsingIslandProvider.overrideWith(() => _FixedIsland(island)),
  ];

  Future<void> pump(
    WidgetTester tester, {
    SearchArgs args = const SearchArgs(query: 'sofa'),
    Island? island,
  }) async {
    await pumpScreen(
      tester,
      SearchResultsScreen(args: args),
      overrides: overrides(island: island),
      routes: {
        for (final name in [AppRoutes.listingPreview, AppRoutes.saved])
          name: (context) {
            pushed[name] = ModalRoute.of(context)?.settings.arguments;
            return Scaffold(body: Text('opened $name'));
          },
      },
    );
    await settle(tester);
  }

  /// The result list's own scrollable, not the filter row's.
  Finder resultList() => find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  Future<void> reveal(WidgetTester tester, Finder target) =>
      tester.scrollUntilVisible(target, 300, scrollable: resultList());

  /// The chip sits at the end of a row that scrolls sideways.
  Future<void> tapMaldivianOwned(WidgetTester tester) async {
    final chip = find.bySemanticsLabel(maldivianOwnedTitle);
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await settle(tester);
  }

  // ===========================================================================

  group(
    'every card states its booking mode; every boosted result is labelled',
    () {
      testWidgets(
        'Pick a time / Request a time on every card, Sponsored only where the server said so',
        (tester) async {
          api.answer = (_) => page([
            result(
              id: 'a',
              name: 'Boosted Clean',
              bookingMode: 'slot',
              sponsored: true,
            ),
            result(id: 'b', name: 'Plain Plumbing'),
          ]);
          await pump(tester);

          expect(find.byType(PublicServiceCard), findsNWidgets(2));
          expect(find.text('Pick a time'), findsOneWidget);
          expect(find.text('Request a time'), findsOneWidget);
          expect(find.text('Sponsored'), findsOneWidget);

          final boosted = tester.widget<PublicServiceCard>(
            find.byType(PublicServiceCard).first,
          );
          final plain = tester.widget<PublicServiceCard>(
            find.byType(PublicServiceCard).last,
          );
          expect(boosted.sponsored, isTrue);
          expect(plain.sponsored, isFalse);
          // Spoken too: a visible label must be visible to everyone.
          expect(
            find.bySemanticsLabel(RegExp('^Sponsored, Boosted Clean')),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp('^Sponsored, Plain')),
            findsNothing,
          );
          expectNoSwallowedControls(tester);
        },
      );

      testWidgets(
        'no emergency marker or filter, and no tier filter, anywhere on the screen',
        (tester) async {
          api.answer = (_) => page([result(id: 'a')]);
          await pump(tester);
          expect(find.textContaining('Emergency'), findsNothing);
          // No tier filter: no chip or section names a tier.
          expect(find.bySemanticsLabel(RegExp('^Tier')), findsNothing);
          await tester.tap(find.bySemanticsLabel('All filters'));
          await settle(tester);
          expect(find.textContaining('Emergency'), findsNothing);
          expect(find.text(maldivianOwnedNote), findsOneWidget);
        },
      );

      testWidgets('a card opens its listing page', (tester) async {
        api.answer = (_) => page([result(id: 'a', name: 'Sofa Shampoo')]);
        await pump(tester);
        await tester.tap(find.text('Sofa Shampoo'));
        await settle(tester);
        expect(pushed[AppRoutes.listingPreview], {'listingId': 'a'});
      });
    },
  );

  // ===========================================================================

  group('results are paginated', () {
    testWidgets(
      'Show 12 more asks for the next page by the server’s cursor and appends it',
      (tester) async {
        api.answer = (q) => q['cursor'] == null
            ? page(
                [
                  for (var i = 0; i < 12; i++)
                    result(id: 'p1-$i', name: 'One $i'),
                ],
                total: 14,
                nextCursor: 'CURSOR-2',
              )
            : page([
                result(id: 'p2-0', name: 'Two 0'),
                result(id: 'p2-1', name: 'Two 1'),
              ], total: 14);
        await pump(tester);

        expect(
          find.textContaining('14 services', findRichText: true),
          findsOneWidget,
        );
        expect(api.requests.single['limit'], '12');
        await reveal(tester, find.text('Show 12 more'));
        await tester.tap(find.text('Show 12 more'));
        await settle(tester);

        expect(api.requests.last['cursor'], 'CURSOR-2');
        await reveal(tester, find.text('Two 1'));
        expect(find.text('Two 1'), findsOneWidget);
        expect(find.text('Show 12 more'), findsNothing);
      },
    );

    testWidgets('a failed next page says so inline and the button retries', (
      tester,
    ) async {
      var calls = 0;
      api.answer = (q) {
        calls++;
        if (q['cursor'] != null && calls == 2) {
          throw const ApiNetworkException();
        }
        return q['cursor'] == null
            ? page([result(id: 'a')], total: 2, nextCursor: 'C2')
            : page([result(id: 'b', name: 'Second')], total: 2);
      };
      await pump(tester);
      await tester.tap(find.text('Show 12 more'));
      await settle(tester);
      expect(find.text(loadMoreFailed), findsOneWidget);
      // What was already shown stays.
      expect(find.byType(PublicServiceCard), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text(loadMoreFailed), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  // ===========================================================================

  group('results are filtered — the screen asks for what the customer chose', () {
    testWidgets(
      'opens on Distance, and a sort chip re-reads from the first page',
      (tester) async {
        api.answer = (_) => page([result(id: 'a')]);
        await pump(tester);
        expect(api.requests.single['sort'], 'distance');
        expect(api.requests.single['q'], 'sofa');

        await tester.tap(find.widgetWithText(AppChip, 'Price'));
        await settle(tester);
        expect(api.requests.last['sort'], 'price');
        expect(api.requests.last.containsKey('cursor'), isFalse);
      },
    );

    testWidgets('the browsing island is the gate, sent by id', (tester) async {
      api.answer = (_) => page([result(id: 'a')]);
      await pump(tester, island: _hulhumale);
      expect(api.requests.single['islandId'], 'isl-hulhumale');
      expect(find.text('Hulhumalé'), findsOneWidget);
    });

    testWidgets(
      'Maldivian-owned toggles §1g’s filter, and only `true` is ever sent',
      (tester) async {
        api.answer = (_) => page([result(id: 'a')]);
        await pump(tester);
        expect(api.requests.single.containsKey('maldivianOwned'), isFalse);
        await tapMaldivianOwned(tester);
        expect(api.requests.last['maldivianOwned'], 'true');
        await tapMaldivianOwned(tester);
        expect(api.requests.last.containsKey('maldivianOwned'), isFalse);
      },
    );

    testWidgets(
      'the Filters sheet sends price in laari and the booking mode, applied together',
      (tester) async {
        api.answer = (_) => page([result(id: 'a')], total: 7);
        await pump(tester);
        final before = api.requests.length;

        await tester.tap(find.bySemanticsLabel('Price: any'));
        await settle(tester);
        expect(find.text('Filters'), findsOneWidget);
        await tester.enterText(find.widgetWithText(AppTextField, 'Min'), '100');
        await tester.enterText(find.widgetWithText(AppTextField, 'Max'), '300');
        await tester.ensureVisible(find.text('Pick a time').last);
        await tester.tap(find.text('Pick a time').last);
        await settle(tester);
        // The sheet's own count of what the draft would show.
        expect(find.text('Show 7 services'), findsOneWidget);
        // Nothing applied to the results yet: only the count's one-result asks.
        expect(
          api.requests.skip(before).every((r) => r['limit'] == '1'),
          isTrue,
        );

        await tester.tap(find.text('Show 7 services'));
        await settle(tester);
        final applied = api.requests.last;
        expect(applied['limit'], '12');
        expect(applied['priceMinLaari'], '10000');
        expect(applied['priceMaxLaari'], '30000');
        expect(applied['mode'], 'slot');
        expect(find.text('MVR 100–300'), findsOneWidget);
      },
    );

    testWidgets(
      'an inverted price range is refused under its field and cannot be applied',
      (tester) async {
        api.answer = (_) => page([result(id: 'a')]);
        await pump(tester);
        await tester.tap(find.bySemanticsLabel('All filters'));
        await settle(tester);
        await tester.enterText(find.widgetWithText(AppTextField, 'Min'), '500');
        await tester.enterText(find.widgetWithText(AppTextField, 'Max'), '100');
        await settle(tester);
        expect(find.text('Max must be at least the min'), findsOneWidget);
        final apply = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'Show services'),
        );
        expect(apply.onPressed, isNull);
      },
    );

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      api.answer = (_) => page([result(id: 'a')]);
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('All filters'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(AppTextField, 'Min'), '100');
      await settle(tester);
      await tester.tapAt(const Offset(10, 10)); // the scrim
      await settle(tester);
      expect(find.bySemanticsLabel('Price: any'), findsOneWidget);
      expect(
        api.requests
            .where((r) => r['limit'] == '12')
            .last
            .containsKey('priceMinLaari'),
        isFalse,
      );
    });

    testWidgets('a category’s results send its id and draw no Category chip', (
      tester,
    ) async {
      api.answer = (_) => page([result(id: 'a')], total: 1);
      await pump(
        tester,
        args: const SearchArgs(
          categoryId: 'cat-plumbing',
          categoryName: 'Plumbing',
        ),
        island: _hulhumale,
      );
      expect(api.requests.single['categoryId'], 'cat-plumbing');
      expect(api.requests.single.containsKey('q'), isFalse);
      expect(find.text('Plumbing'), findsWidgets);
      expect(find.text('1 service · Hulhumalé'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Category:')), findsNothing);
    });
  });

  // ===========================================================================

  group('the other three states', () {
    testWidgets('loading is card-shaped skeletons, not a spinner', (
      tester,
    ) async {
      api.gate = Completer<void>();
      await pumpScreen(
        tester,
        const SearchResultsScreen(args: SearchArgs(query: 'x')),
        overrides: overrides(),
      );
      await tester.pump();
      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      api.gate!.complete();
      await settle(tester);
    });

    testWidgets(
      'a dropped connection says nothing was filtered out, and retries',
      (tester) async {
        api.failWith = const ApiNetworkException();
        await pump(tester);
        expect(find.text(errorTitle), findsOneWidget);
        expect(find.text(errorBodyOffline), findsOneWidget);

        api
          ..failWith = null
          ..answer = (_) => page([result(id: 'a', name: 'Back again')]);
        await tester.tap(find.text('Try again'));
        await settle(tester);
        expect(find.text('Back again'), findsOneWidget);
      },
    );

    testWidgets('a server error never leaks its details', (tester) async {
      api.failWith = ApiException(
        status: 500,
        code: 'INTERNAL_ERROR',
        message: 'PrismaClientKnownRequestError',
      );
      await pump(tester);
      expect(find.text(errorBodyServer), findsOneWidget);
      expect(find.textContaining('Prisma'), findsNothing);
    });

    testWidgets(
      'filtered to nothing: names the filters, removes one, or clears them all',
      (tester) async {
        api.answer = (q) => q['maldivianOwned'] == 'true'
            ? page(const [])
            : page([result(id: 'a')]);
        await pump(tester, island: _hulhumale);
        await tapMaldivianOwned(tester);

        expect(find.text(noMatchTitle), findsOneWidget);
        expect(
          find.text(filteredOutBody(['Maldivian-owned', 'Hulhumalé'])),
          findsOneWidget,
        );
        await tester.tap(find.text('Clear filters'));
        await settle(tester);
        expect(api.requests.last.containsKey('maldivianOwned'), isFalse);
        expect(find.byType(PublicServiceCard), findsOneWidget);
      },
    );

    testWidgets(
      'a search that matched nothing says so, by the words searched',
      (tester) async {
        await pump(tester);
        expect(find.text(noMatchTitle), findsOneWidget);
        expect(find.text(unmatchedBody('sofa')), findsOneWidget);
      },
    );

    testWidgets('an empty category names the island and offers to change it', (
      tester,
    ) async {
      await pump(
        tester,
        args: const SearchArgs(categoryId: 'cat-1', categoryName: 'Plumbing'),
        island: _hulhumale,
      );
      expect(
        find.text(categoryEmptyTitle('Plumbing', 'Hulhumalé')),
        findsOneWidget,
      );
      expect(find.text('Change island'), findsOneWidget);
      expect(find.text('Browse all services'), findsOneWidget);
      // The growth claim the prototype makes is not one the product can keep.
      expect(find.textContaining('every week'), findsNothing);
    });
  });

  for (final args in const [
    SearchArgs(query: 'a fairly long search for sofa cleaning'),
    SearchArgs(categoryId: 'cat-1', categoryName: 'Appliance Repair'),
  ]) {
    testWidgets(
      'survives 200% text: ${args.isCategory ? 'category' : 'search'}',
      (tester) async {
        api.answer = (_) => page([
          result(id: 'a', sponsored: true, bookingMode: 'slot'),
        ], nextCursor: 'C2');
        await pumpScreen(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SearchResultsScreen(args: args),
          ),
          overrides: overrides(island: _hulhumale),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(PublicServiceCard), findsOneWidget);
      },
    );
  }

  testWidgets('the query pill goes back to Explore holding the same words', (
    tester,
  ) async {
    api.answer = (_) => page([result(id: 'a')]);
    Object? popped;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<Object?>(
              MaterialPageRoute(
                builder: (_) => const SearchResultsScreen(
                  args: SearchArgs(query: 'sofa clean'),
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
      overrides: overrides(),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Search: sofa clean')));
    await settle(tester);
    expect(popped, 'sofa clean');
  });
}
