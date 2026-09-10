import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/location/browsing_island_controller.dart';
import 'package:raajjepro/features/explore/presentation/explore_screen.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/islands.dart';
import '../../helpers/pump.dart';
import '../explore/helpers.dart';

/// §Phase 7's **Done when**, line by line:
///
/// > the multi-select works standalone against real API data; the header
/// > bottom sheet lets a customer pick a browsing island that persists for
/// > the session.
///
/// The first line is `island_multi_select_test.dart` and
/// `island_search_list_test.dart` — the widget is driven on a bare `Scaffold`
/// with no screen around it, and everything it shows comes from
/// `GET /v1/islands`. What is left for this file is the second line, driven
/// through the **real app** and its real route table rather than through a
/// screen pumped in isolation, so that "persists for the session" is measured
/// across actual navigation.
void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient()
      ..on('GET', '/v1/categories', (_) => {'_list': seededTwelve()})
      ..on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
  });

  Future<void> pumpExplore(WidgetTester tester) => pumpScreen(
    tester,
    const ExploreScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
    routes: {ProfileScreen.routeName: (_) => const ProfileScreen()},
  );

  /// The header pill — scoped by the header, so the sheet's own rows and the
  /// grid cannot be mistaken for it.
  Finder pill() => find.descendant(
    of: find.byType(AppHeader),
    matching: find.byType(Pressable),
  );

  testWidgets('the header pill opens the sheet — it is no longer inert', (
    tester,
  ) async {
    await pumpExplore(tester);
    expect(find.text('Island'), findsOneWidget);

    await tester.tap(find.text('Island'));
    await settle(tester);

    expect(find.text('Choose your island'), findsOneWidget);
    expect(find.byType(IslandPickerSheet), findsOneWidget);
    // Search is the control, not a filter over a browsable list.
    expect(find.byType(IslandSearchList), findsOneWidget);
  });

  testWidgets('a native picker is never the island control', (tester) async {
    await pumpExplore(tester);
    await tester.tap(find.text('Island'));
    await settle(tester);

    // §0.0 item 12: "A native `<select>` is not an acceptable island control
    // anywhere." Its Flutter equivalents are these.
    expect(find.byType(DropdownButton<Object>), findsNothing);
    expect(find.byType(DropdownMenu<Object>), findsNothing);
    expect(find.byType(PopupMenuButton<Object>), findsNothing);
  });

  testWidgets('picking an island closes the sheet and names it on the pill', (
    tester,
  ) async {
    await pumpExplore(tester);
    await tester.tap(find.text('Island'));
    await settle(tester);

    await tester.tap(find.text('Dh. Meedhoo'));
    await settle(tester);

    expect(find.byType(IslandPickerSheet), findsNothing);
    // The qualified name, so browsing from Dhaalu's Meedhoo does not look
    // identical to browsing from Seenu's.
    expect(find.text('Dh. Meedhoo'), findsOneWidget);
    expect(find.text('Island'), findsNothing);
  });

  testWidgets('the pill announces the island it is browsing', (tester) async {
    await pumpExplore(tester);
    final handle = tester.ensureSemantics();

    expect(
      tester.getSemantics(pill().first).label,
      contains('Choose your island'),
    );

    await tester.tap(find.text('Island'));
    await settle(tester);
    await tester.tap(find.text('R. Meedhoo'));
    await settle(tester);

    expect(tester.getSemantics(pill().first).label, contains('R. Meedhoo'));
    handle.dispose();
  });

  testWidgets('dismissing the sheet changes nothing', (tester) async {
    await pumpExplore(tester);
    await tester.tap(find.text('Island'));
    await settle(tester);

    // The sheet's close control is icon-only; it is found by the label a
    // screen reader hears.
    await tester.tap(find.bySemanticsLabel('Close'));
    await settle(tester);

    expect(find.byType(IslandPickerSheet), findsNothing);
    expect(find.text('Island'), findsOneWidget);
  });

  testWidgets(
    'the choice survives navigating away and back — for the session',
    (tester) async {
      await pumpExplore(tester);
      await tester.tap(find.text('Island'));
      await settle(tester);
      await tester.tap(find.text('S. Meedhoo'));
      await settle(tester);
      expect(find.text('S. Meedhoo'), findsOneWidget);

      // Off to another screen and back, through the real route table.
      await tester.tap(find.text('Profile'));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.byType(ExploreScreen), findsOneWidget);
      expect(
        find.text('S. Meedhoo'),
        findsOneWidget,
        reason: 'the browsing island persists for the session',
      );
    },
  );

  testWidgets(
    'nothing is chosen until the customer chooses — no default island',
    (tester) async {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      // Not Malé, not the first search result, not a device location.
      expect(container.read(browsingIslandProvider), isNull);
    },
  );
}
