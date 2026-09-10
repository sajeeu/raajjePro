import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/islands.dart';
import '../../helpers/pump.dart';

/// The island control (§Phase 7's third bullet, §0.0 item 12).
///
/// The *matching* rules — anywhere in the name, atoll code, case, accents,
/// apostrophes, ranking, no cap — are the server's and are asserted against
/// the real endpoint in `backend/test/islands-search.test.ts`. What is
/// asserted here is everything the client is responsible for: that it sends
/// what was typed, draws what came back without re-ordering or trimming it,
/// never chooses for the customer, and never prints a total.
void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient()
      ..on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
  });

  Future<void> pumpList(
    WidgetTester tester, {
    Set<String> selected = const {},
    void Function(Island)? onSelected,
    IslandRowIndicator indicator = IslandRowIndicator.checkbox,
  }) => pumpScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(
        child: IslandSearchList(
          selectedIds: selected,
          indicator: indicator,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  /// Types [term] and waits past the debounce.
  Future<void> type(WidgetTester tester, String term) async {
    await tester.enterText(find.byType(TextField), term);
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
  }

  group('states', () {
    testWidgets('shows a skeleton before the first results land', (
      tester,
    ) async {
      api.gate = Completer<void>();
      await pumpList(tester);
      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      api.gate!.complete();
      await settle(tester);
      expect(find.byType(SkeletonLoader), findsNothing);
    });

    testWidgets('offers a retry when the list fails, and recovers', (
      tester,
    ) async {
      api.offline('GET', '/v1/islands');
      await pumpList(tester);
      expect(find.text('You’re offline'), findsOneWidget);

      api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Kulhudhuffushi'), findsOneWidget);
    });

    testWidgets('a term that matches nothing names the term and what to try', (
      tester,
    ) async {
      api.on('GET', '/v1/islands?search=zzz', (_) => {'_list': <Object>[]});
      await pumpList(tester);
      await type(tester, 'zzz');

      expect(find.text('No island matches “zzz”'), findsOneWidget);
      // An empty state names what to do next (frontend/CLAUDE.md). The atoll
      // code is the useful hint, because it is the second thing search matches.
      expect(find.textContaining('search by atoll code'), findsOneWidget);
    });

    testWidgets('lists every island the endpoint returned', (tester) async {
      await pumpList(tester);
      expect(find.text('Kulhudhuffushi'), findsOneWidget);
      expect(find.text('Dh. Meedhoo'), findsOneWidget);
      expect(find.text('R. Meedhoo'), findsOneWidget);
      expect(find.text('S. Meedhoo'), findsOneWidget);
    });
  });

  group('the rules that are this widget’s to keep', () {
    testWidgets('sends the term as typed, once the typing stops', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/islands?search=mee',
        (_) => {'_list': sampleIslands()},
      );
      await pumpList(tester);
      api.calls.clear();
      await type(tester, 'mee');

      expect(api.calls.map((c) => c.path), contains('/v1/islands?search=mee'));
      // Folding case, accents and apostrophes is the server's rule; a second
      // implementation here is exactly what §0.0 item 12 must not have.
      expect(api.calls.every((c) => !c.path.contains('search=MEE')), isTrue);
    });

    testWidgets('debounces — one request for a word, not one per keystroke', (
      tester,
    ) async {
      for (final term in ['m', 'me', 'mee']) {
        api.on('GET', '/v1/islands?search=$term', (_) => {'_list': <Object>[]});
      }
      await pumpList(tester);
      api.calls.clear();

      await tester.enterText(find.byType(TextField), 'm');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'me');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'mee');
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      expect(api.calls.map((c) => c.path), ['/v1/islands?search=mee']);
    });

    testWidgets('draws the server’s order, and does not re-sort it', (
      tester,
    ) async {
      // Deliberately not alphabetical: the server ranks prefix matches first,
      // and a client that sorted would undo that.
      api.on(
        'GET',
        '/v1/islands?search=mee',
        (_) => {
          '_list': [
            islandJson(
              id: 'i-s',
              name: 'Meedhoo',
              atollName: 'Seenu',
              atollAbbr: 'S',
              nameAmbiguous: true,
            ),
            islandJson(
              id: 'i-dh',
              name: 'Meedhoo',
              atollName: 'Dhaalu',
              atollAbbr: 'Dh',
              nameAmbiguous: true,
            ),
            islandJson(
              id: 'i-hangnaa',
              name: 'Hangnaameedhoo',
              atollName: 'Alifu Dhaalu',
              atollAbbr: 'ADh',
            ),
          ],
        },
      );
      await pumpList(tester);
      await type(tester, 'mee');

      final order = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where(
            (d) =>
                d == 'S. Meedhoo' ||
                d == 'Dh. Meedhoo' ||
                d == 'Hangnaameedhoo',
          )
          .toList();
      expect(order, ['S. Meedhoo', 'Dh. Meedhoo', 'Hangnaameedhoo']);
    });

    testWidgets('never auto-selects, even when exactly one island matches', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/islands?search=kulhu',
        (_) => {
          '_list': [
            islandJson(
              id: 'i-k',
              name: 'Kulhudhuffushi',
              atollName: 'Haa Dhaalu',
              atollAbbr: 'HDh',
            ),
          ],
        },
      );
      var chosen = 0;
      await pumpList(tester, onSelected: (_) => chosen++);
      await type(tester, 'kulhu');

      expect(find.text('Kulhudhuffushi'), findsOneWidget);
      expect(chosen, 0, reason: 'a lone match is offered, never taken');

      final row = tester.widget<Pressable>(
        find.ancestor(
          of: find.text('Kulhudhuffushi'),
          matching: find.byType(Pressable),
        ),
      );
      expect(row.selected, isFalse);
    });

    testWidgets(
      'shows the atoll on every row, so three Meedhoos are told apart',
      (tester) async {
        await pumpList(tester);
        for (final atoll in ['Dhaalu', 'Raa', 'Seenu']) {
          expect(find.text(atoll), findsWidgets, reason: atoll);
        }
        // And the qualifier is the server's `displayName`, not one built here:
        // the bare name never appears for an ambiguous island.
        expect(find.text('Meedhoo'), findsNothing);
      },
    );

    testWidgets('prints no island total anywhere', (tester) async {
      await pumpList(tester);
      final printed = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      // §0.0 item 12: no denominator. 192 today, 187 in the prototypes, and a
      // number that goes stale silently is worth less than the search.
      expect(
        RegExp(r'\d+\s+(inhabited\s+)?islands').hasMatch(printed),
        isFalse,
      );
      expect(printed.contains('192'), isFalse);
      expect(printed.contains('187'), isFalse);
    });

    testWidgets('reports the chosen island by identity, never by name', (
      tester,
    ) async {
      Island? picked;
      await pumpList(tester, onSelected: (i) => picked = i);
      await tester.tap(find.text('R. Meedhoo'));
      await settle(tester);
      expect(picked?.id, 'i-meedhoo-r');
      expect(picked?.atollName, 'Raa');
    });
  });
}
