import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/explore/presentation/explore_screen.dart';
import 'package:raajjepro/features/explore/presentation/widgets/category_tile.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'helpers.dart';

/// Geometry, not copy — the same axis `sign_in_layout_test.dart` exists for,
/// and for the same reason: Sign In matched its prototype string for string
/// while carrying seven layout defects that no copy comparison and no
/// `flutter analyze` could see.
///
/// Measured against `mockups/design-composer/Discovery.dc.html` → Explore.
/// `pumpScreen` pumps the prototype's own 412 x 915 frame at DPR 1, so every
/// number below is the prototype's number.
///
/// This is deliberately written **now**, while the chrome is inert and this
/// session still holds the screen's context. Phases 7, 15 and 19 each replace
/// one control here, in a session that will not — and a measurement taken
/// before they touch it is the only thing that tells them whether they moved
/// something.
///
/// One pre-existing divergence is recorded rather than asserted: the
/// prototype's header action disc is 44 dp and Phase 1's `AppHeader` draws
/// 40. That is `AppHeader`'s number across every screen, not Explore's, so it
/// is logged in `docs/design/explore-corrections.md` for the design project
/// instead of being fixed here.
void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient();
    api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
  });

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const ExploreScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  /// Reads the live theme the same way a widget does.
  BuildContext context(WidgetTester tester) =>
      tester.element(find.byType(ExploreScreen));

  /// The prototype's frame width, matching `pumpScreen`.
  const frame = 412.0;

  /// `padding: 0 20px` on every block of the Explore screen.
  const screenInset = 20.0;

  group('the category grid', () {
    testWidgets('is three columns inset 20 with a 12 dp gutter', (
      tester,
    ) async {
      await pump(tester);
      final tiles = find.byType(CategoryTile);
      final first = tester.getRect(tiles.at(0));
      final second = tester.getRect(tiles.at(1));
      final third = tester.getRect(tiles.at(2));
      final fourth = tester.getRect(tiles.at(3));

      expect(first.left, screenInset);
      expect(third.right, frame - screenInset);
      // (412 - 40 - 24) / 3
      expect(first.width, closeTo(116, 0.01));
      expect(second.left - first.right, closeTo(12, 0.01));
      expect(third.left - second.right, closeTo(12, 0.01));
      // Row 2 starts one 12 dp gutter below row 1.
      expect(fourth.top - first.bottom, closeTo(12, 0.01));
      expect(fourth.left, screenInset);
    });

    testWidgets('draws the 56 dp icon chip the prototype draws', (
      tester,
    ) async {
      await pump(tester);
      // The box holding the glyph, named through the glyph rather than as
      // "the first SizedBox under the tile" — that finder silently moved onto
      // the tile's own `SizedBox.expand` the moment one was added, and
      // reported the chip as 116 dp.
      final chip = tester.getRect(
        find
            .ancestor(
              of: find.descendant(
                of: find.byType(CategoryTile).first,
                matching: find.byType(Icon),
              ),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(chip.width, CategoryTile.chip);
      expect(chip.height, CategoryTile.chip);
    });

    testWidgets('gives the tile a 20 dp radius and a 1 dp card border', (
      tester,
    ) async {
      await pump(tester);
      // Not simply the first DecoratedBox under the tile — that one is
      // Pressable's focus ring. The tile's own surface is the one that paints
      // a background.
      final decoration = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(CategoryTile).first,
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppRadius.panel), // 20
      );
      expect(decoration.border?.top.width, AppSizes.dividerStroke);
    });

    testWidgets('keeps every tile the same size — no ragged rows', (
      tester,
    ) async {
      await pump(tester);

      // Measure the box that PAINTS the tile, not `CategoryTile`. The grid
      // constrains each cell tightly to 116 dp, so the widget reports 116
      // however the surface inside it behaves — an earlier version of this
      // test measured that and passed while the rendered tiles were visibly
      // ragged, "Appliance Repair" drawing wider than "Fitness". `Pressable`
      // wraps its child in `Center(widthFactor: 1, heightFactor: 1)`, which
      // hands loose constraints down, so the surface shrink-wrapped its label
      // until `SizedBox.expand` made it fill the cell.
      Rect surfaceOf(int i) => tester.getRect(
        find
            .descendant(
              of: find.byType(CategoryTile).at(i),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).border != null,
              ),
            )
            .first,
      );

      final count = find.byType(CategoryTile).evaluate().length;
      expect(count, 12);
      final painted = [for (var i = 0; i < count; i++) surfaceOf(i)];

      expect(
        painted.map((r) => r.width).toSet(),
        hasLength(1),
        reason:
            'every painted tile must be one width; got '
            '${painted.map((r) => r.width).toList()}',
      );
      expect(painted.map((r) => r.height).toSet(), hasLength(1));

      // And that one width is the cell's, so the surface fills it rather than
      // merely being consistent with itself.
      final cell = tester.getRect(find.byType(CategoryTile).first);
      expect(painted.first.width, closeTo(cell.width, 0.01));
      expect(painted.first.height, closeTo(cell.height, 0.01));
      expect(painted.first.width, closeTo(116, 0.01));
    });

    testWidgets('the skeleton occupies the same grid as the populated one', (
      tester,
    ) async {
      // Held open so the screen stays in its loading state. A second
      // `pumpScreen` in one test would not re-enter it — Riverpod keeps the
      // container across an override swap and the provider stays resolved.
      api.gate = Completer<void>();
      await pump(tester);

      final bone = tester.getRect(find.byType(SkeletonBox).first);
      // The bone is the icon chip: 56 wide, centred in a 116 dp cell that
      // starts at the 20 dp screen inset — the same place the real chip sits.
      expect(bone.width, CategoryTile.chip);
      expect(bone.height, CategoryTile.chip);
      expect(bone.left - screenInset, closeTo(30, 0.5)); // (116 - 56) / 2
      // Twelve bones, one per tile the populated grid would draw.
      expect(
        find.byType(SkeletonBox),
        findsNWidgets(24), // chip + label line, twelve times
      );
      api.gate!.complete();
    });
  });

  group('the chrome above it', () {
    testWidgets('the search field is 52 high, inset 20, radius 16', (
      tester,
    ) async {
      await pump(tester);
      final field = tester.getRect(find.text('What service do you need?'));
      // Its container, not the label: walk up to the sized box.
      final container = tester.getRect(
        find
            .ancestor(
              of: find.text('What service do you need?'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.height, AppSizes.inputHeight); // 52
      expect(container.left, screenInset);
      expect(container.right, frame - screenInset);
      expect(field.left, greaterThan(container.left));
    });

    testWidgets('the island pill is 38 high and never wider than 130', (
      tester,
    ) async {
      await pump(tester);
      final pill = tester.getRect(
        find
            .ancestor(of: find.text('Island'), matching: find.byType(Container))
            .first,
      );
      expect(pill.height, AppSizes.chipHeight); // 38
      expect(pill.width, lessThanOrEqualTo(130));
    });

    testWidgets('the account disc is the header size, 36', (tester) async {
      await pump(tester);
      // A guest sees a generic disc rather than initials for a name the app
      // does not have — `explore_chrome_test.dart` covers the signed-in
      // branch. Either way it is 36, which is what the geometry asserts.
      //
      // 🔧 Scoped by the icon rather than by the `InertControl` Phase 6
      // removed when it wired the control. The *painted* disc is still 36;
      // its tap target is 48, which `explore_chrome_test.dart` asserts by
      // tapping off-centre.
      final headerDisc = find.descendant(
        of: find.ancestor(
          of: find.byIcon(Icons.person_outline_rounded),
          matching: find.byType(Pressable),
        ),
        matching: find.byType(SizedBox),
      );
      final square = tester.getRect(headerDisc.first);
      expect(square.width, AppSizes.avatarMedium); // 36
      expect(square.height, AppSizes.avatarMedium);
    });

    testWidgets('the screen title is the 25/800 screen title role', (
      tester,
    ) async {
      await pump(tester);
      final title = tester.widget<Text>(find.text('Explore Services'));
      expect(title.style?.fontSize, 25);
      expect(title.style?.fontWeight, FontWeight.w800);
    });

    testWidgets('the title row sits at the 20 dp inset', (tester) async {
      await pump(tester);
      expect(tester.getRect(find.text('Explore Services')).left, screenInset);
    });

    testWidgets('the page draws on the app background, not white', (
      tester,
    ) async {
      await pump(tester);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, context(tester).colors.background);
    });
  });

  group('accessibility floors hold at the geometry', () {
    testWidgets('every inert control still clears the 48 dp touch floor', (
      tester,
    ) async {
      await pump(tester);
      // The heart's disc is 28; Pressable carries the 48 dp hit area.
      final heartHit = tester.getRect(
        find
            .descendant(
              of: find.byType(SaveHeartToggle),
              matching: find.byType(Pressable),
            )
            .first,
      );
      expect(heartHit.width, greaterThanOrEqualTo(AppSizes.touchTarget));
      expect(heartHit.height, greaterThanOrEqualTo(AppSizes.touchTarget));
    });

    testWidgets('the grid does not clip a label at 200% text', (tester) async {
      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ExploreScreen(),
        ),
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CategoryTile), findsWidgets);
    });
  });
}
