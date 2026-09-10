import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/islands.dart';
import '../../helpers/pump.dart';

/// The reusable island multi-select (§Phase 7's third bullet).
///
/// **Standalone, not screen-specific**: everything below drives the widget on
/// a bare `Scaffold`, which is the same way §Phase 6a's onboarding and
/// §Phase 9's wizard step 2 will drive it. Nothing here belongs to a screen.
void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient()
      ..on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
  });

  Island island(String id) =>
      Island.fromJson(sampleIslands().firstWhere((i) => i['id'] == id));

  /// The row in the result list, not the chip above it — a selected island's
  /// display name is on screen twice, and both are supposed to be tappable.
  Finder row(String displayName) => find.descendant(
    of: find.byType(IslandSearchList),
    matching: find.text(displayName),
  );

  /// Pumps the widget standalone with a mutable selection, exactly as a
  /// screen would own it: the widget never writes, so the harness holds the
  /// list and feeds it back in.
  Future<_Selection> pumpSelect(
    WidgetTester tester, {
    List<Island> initial = const [],
  }) async {
    final selection = _Selection(initial);
    await pumpScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: SingleChildScrollView(
            child: IslandMultiSelect(
              selected: selection.islands,
              onChanged: (next) => setState(() => selection.islands = next),
            ),
          ),
        ),
      ),
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    return selection;
  }

  testWidgets(
    'an empty selection says what it costs, not just that it is empty',
    (tester) async {
      final selection = await pumpSelect(tester);

      expect(find.text('No islands selected yet'), findsOneWidget);
      expect(
        find.textContaining('won’t see you'),
        findsOneWidget,
        reason: 'an empty state names the consequence, not the absence',
      );
      expect(selection.islands, isEmpty);
    },
  );

  testWidgets(
    'tapping a row adds it, and the chip carries the qualified name',
    (tester) async {
      final selection = await pumpSelect(tester);

      await tester.tap(find.text('Dh. Meedhoo'));
      await settle(tester);

      expect(selection.islands.map((i) => i.id), ['i-meedhoo-dh']);
      expect(find.byType(AppChip), findsOneWidget);
      // The chip must not read "Meedhoo" — there are three, and a chip that
      // dropped the qualifier would leave the provider unable to tell which one
      // they picked.
      final chip = tester.widget<AppChip>(find.byType(AppChip));
      expect(chip.label, 'Dh. Meedhoo');
      expect(find.text('No islands selected yet'), findsNothing);
    },
  );

  testWidgets('the row and the chip remove the same island', (tester) async {
    final selection = await pumpSelect(
      tester,
      initial: [island('i-meedhoo-dh')],
    );
    expect(selection.islands, hasLength(1));

    // Off by the chip's ×.
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);
    expect(selection.islands, isEmpty);

    // Back on, then off by the row.
    await tester.tap(row('Dh. Meedhoo'));
    await settle(tester);
    expect(selection.islands, hasLength(1));
    await tester.tap(row('Dh. Meedhoo'));
    await settle(tester);
    expect(selection.islands, isEmpty);
  });

  testWidgets('holds several islands at once, each shown selected', (
    tester,
  ) async {
    final selection = await pumpSelect(tester);

    await tester.tap(find.text('Dh. Meedhoo'));
    await settle(tester);
    await tester.tap(find.text('Kulhudhuffushi'));
    await settle(tester);

    expect(selection.islands.map((i) => i.id), [
      'i-meedhoo-dh',
      'i-kulhudhuffushi',
    ]);
    for (final name in ['Dh. Meedhoo', 'Kulhudhuffushi']) {
      final pressable = tester.widget<Pressable>(
        find.ancestor(of: row(name), matching: find.byType(Pressable)).first,
      );
      expect(pressable.selected, isTrue, reason: name);
    }
  });

  testWidgets('tells the two Vilingilis apart on the chips', (tester) async {
    final selection = await pumpSelect(tester);

    await tester.tap(find.text('K. Vilingili'));
    await settle(tester);
    await tester.tap(find.text("GA. Vilin'gili"));
    await settle(tester);

    expect(selection.islands, hasLength(2));
    final labels = tester
        .widgetList<AppChip>(find.byType(AppChip))
        .map((c) => c.label)
        .toList();
    expect(labels, ['K. Vilingili', "GA. Vilin'gili"]);
  });
}

/// The selection a screen would own. The widget is deliberately stateless
/// about it — §Phase 6a stores it on the provider profile and §Phase 9 on the
/// listing, and neither is this widget's business.
class _Selection {
  _Selection(this.islands);
  List<Island> islands;
}
