import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/theme/category_icons.dart';
import 'package:raajjepro/features/explore/presentation/explore_screen.dart';
import 'package:raajjepro/features/explore/presentation/widgets/category_tile.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'helpers.dart';

/// §Phase 4's frontend Done-when: **the grid is driven entirely by the live
/// endpoint.** Every test here proves that by giving the endpoint something
/// other than the seeded twelve and watching the grid follow it — a screen
/// with a compiled-in list would pass a "twelve tiles render" test and fail
/// every one of these.
void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const ExploreScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  group('populated', () {
    testWidgets('draws one tile per category the endpoint returned', (
      tester,
    ) async {
      api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
      await pump(tester);

      expect(find.byType(CategoryTile), findsNWidgets(12));
      expect(find.text('Boat Charter'), findsOneWidget);
      expect(find.text('Home Repairs'), findsOneWidget);
    });

    testWidgets('follows the cursor to a second page', (tester) async {
      // The loop in `CategoryApi` existed from the start and was unreachable:
      // it read the cursor from a key the client does not produce. Nothing
      // exercised paging, so a catalogue past the first page would simply
      // have gone missing from the grid.
      api.on(
        'GET',
        '/v1/categories',
        (_) => {
          '_list': [categoryJson(id: 'p1', name: 'Page One', sortOrder: 1)],
          '_meta': {'nextCursor': 'cur-2'},
        },
      );
      api.on(
        'GET',
        '/v1/categories?cursor=cur-2',
        (_) => {
          '_list': [categoryJson(id: 'p2', name: 'Page Two', sortOrder: 2)],
        },
      );
      await pump(tester);

      expect(find.text('Page One'), findsOneWidget);
      expect(find.text('Page Two'), findsOneWidget);
      expect(find.byType(CategoryTile), findsNWidgets(2));
    });

    testWidgets('shows a thirteenth with no rebuild — the Done-when line', (
      tester,
    ) async {
      api.on('GET', '/v1/categories', (_) {
        return {
          '_list': [
            ...seededTwelve(),
            categoryJson(
              id: 'cat-13',
              name: 'Kayak Hire',
              // Neither token exists in this build.
              iconIdentifier: 'kayak',
              colorToken: 'teal',
              sortOrder: 13,
            ),
          ],
        };
      });
      await pump(tester);

      expect(find.byType(CategoryTile), findsNWidgets(13));
      expect(find.text('Kayak Hire'), findsOneWidget);
      // The unknown glyph falls back rather than leaving a hole.
      final tile = tester.widget<CategoryTile>(
        find.ancestor(
          of: find.text('Kayak Hire'),
          matching: find.byType(CategoryTile),
        ),
      );
      expect(
        CategoryIcons.resolve(tile.category.iconIdentifier),
        CategoryIcons.fallback,
      );
    });

    testWidgets('renders whatever names the endpoint sends, not a known set', (
      tester,
    ) async {
      api.on('GET', '/v1/categories', (_) {
        return {
          '_list': [
            categoryJson(id: 'a', name: 'Falana Repairs', sortOrder: 1),
            categoryJson(id: 'b', name: 'Dhoni Maintenance', sortOrder: 2),
          ],
        };
      });
      await pump(tester);

      expect(find.byType(CategoryTile), findsNWidgets(2));
      expect(find.text('Falana Repairs'), findsOneWidget);
      // A category the seed does have is absent, because the endpoint omitted it.
      expect(find.text('Plumbing'), findsNothing);
    });

    testWidgets('keeps the endpoint’s order rather than re-sorting', (
      tester,
    ) async {
      api.on('GET', '/v1/categories', (_) {
        return {
          '_list': [
            categoryJson(id: 'z', name: 'Zebra', sortOrder: 1),
            categoryJson(id: 'a', name: 'Apple', sortOrder: 2),
          ],
        };
      });
      await pump(tester);

      final names = tester
          .widgetList<CategoryTile>(find.byType(CategoryTile))
          .map((t) => t.category.name)
          .toList();
      expect(names, ['Zebra', 'Apple']);
    });

    testWidgets(
      'carries no emergency marker on any tile, capable or not (Round 23)',
      (tester) async {
        api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
        await pump(tester);

        for (final word in ['Emergency', 'emergency', 'Urgent', '24/7']) {
          expect(find.textContaining(word), findsNothing);
        }
      },
    );

    testWidgets('shows Boat Charter as an ordinary request-based tile', (
      tester,
    ) async {
      api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
      await pump(tester);

      final tile = tester.widget<CategoryTile>(
        find.ancestor(
          of: find.text('Boat Charter'),
          matching: find.byType(CategoryTile),
        ),
      );
      expect(tile.category.bookingMode.name, 'request');
      expect(tile.category.emergencyCapable, isFalse);
    });
  });

  group('the other three states', () {
    testWidgets('loading is a tile-shaped skeleton, not a spinner', (
      tester,
    ) async {
      api.gate = Completer<void>();
      api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
      await pump(tester);

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CategoryTile), findsNothing);

      api.gate!.complete();
      await settle(tester);
      expect(find.byType(CategoryTile), findsNWidgets(12));
    });

    testWidgets('empty names what happens next and offers a retry', (
      tester,
    ) async {
      api.on('GET', '/v1/categories', (_) => {'_list': <Object>[]});
      await pump(tester);

      expect(find.text('Nothing to explore yet'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CategoryTile), findsNothing);
    });

    testWidgets('offline says the connection dropped and retries', (
      tester,
    ) async {
      api.offline('GET', '/v1/categories');
      await pump(tester);

      expect(find.text("Categories didn't load"), findsOneWidget);
      expect(
        find.text('Your connection dropped while loading.'),
        findsOneWidget,
      );

      // The retry is real: the second call succeeds and the grid appears.
      api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.byType(CategoryTile), findsNWidgets(12));
    });

    testWidgets('a server error never shows a code or a stack trace', (
      tester,
    ) async {
      api.fail(
        'GET',
        '/v1/categories',
        status: 500,
        code: 'INTERNAL_ERROR',
        message: 'PrismaClientKnownRequestError: P2002',
      );
      await pump(tester);

      expect(find.text("Categories didn't load"), findsOneWidget);
      expect(find.textContaining('INTERNAL_ERROR'), findsNothing);
      expect(find.textContaining('Prisma'), findsNothing);
      expect(find.textContaining('500'), findsNothing);
    });

    testWidgets(
      'the error state never claims search still works, because it does not',
      (tester) async {
        api.offline('GET', '/v1/categories');
        await pump(tester);
        // The prototype's copy ends "Search still works." The field above is
        // inert until Phase 15; restoring that sentence belongs with it.
        expect(find.textContaining('Search still works'), findsNothing);
      },
    );
  });
}
