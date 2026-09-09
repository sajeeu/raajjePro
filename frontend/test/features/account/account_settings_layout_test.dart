import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Geometry, not copy — the axis that let seven defects through on Sign In and
/// a whole ragged grid through on Explore, both behind a perfect string match.
///
/// Numbers read out of `mockups/design-composer/Account Settings.dc.html` with
/// `getComputedStyle()`: the row is `width:100%`, `border-radius:20px`,
/// `padding:12px 15px`, a `46 x 46` circular icon, on a page inset
/// `padding:16px 20px`.
///
/// **Measure the box that paints**, never the widget that wraps it. Explore's
/// tiles were ragged while `find.byType(CategoryTile)` reported a uniform
/// 116 dp, because the grid cell is tight and `Pressable` hands loose
/// constraints to the surface inside it.
void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) async {
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {'_list': <Map<String, dynamic>>[]},
    );
    await pumpScreen(
      tester,
      const AccountSettingsScreen(),
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ],
      routes: {
        for (final r in [
          '/account/password',
          '/account/change-email',
          '/account/phone',
          '/account/sessions',
          '/account/download',
          '/account/delete',
        ])
          r: (_) => Scaffold(body: Text('ROUTE $r')),
      },
    );
    await tester.pumpAndSettle();
  }

  /// The painted surface of a settings row: the `AnimatedContainer` `AppCard`
  /// draws with, not `SettingsRow` and not `AppCard` — those are wrappers, and
  /// a wrapper can report the right width while the surface inside it does not.
  Rect surfaceOf(WidgetTester tester, int i) => tester.getRect(
    find
        .descendant(
          of: find.byType(SettingsRow).at(i),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );

  testWidgets('every row paints the full content width, and one height', (
    tester,
  ) async {
    await pump(tester);

    final count = find.byType(SettingsRow).evaluate().length;
    expect(count, greaterThanOrEqualTo(5), reason: 'the settings list');

    final painted = [for (var i = 0; i < count; i++) surfaceOf(tester, i)];

    // 412 - 20 - 20 = 372. The prototype's row is `width:100%` of that inset.
    for (final r in painted) {
      expect(
        r.width,
        closeTo(372, 1),
        reason: 'a row must span the inset content width, not its own text',
      );
      expect(r.left, closeTo(20, 1));
    }
    expect(
      painted.map((r) => r.width).toSet(),
      hasLength(1),
      reason: 'rows must not be ragged; got ${painted.map((r) => r.width)}',
    );
  });

  testWidgets('the row radius and icon disc are the prototype numbers', (
    tester,
  ) async {
    await pump(tester);

    final decoration =
        tester
                .widgetList<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(SettingsRow).first,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .first
                .decoration
            as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.panel));

    // `width:46px;height:46px;border-radius:50%` in the prototype. Anchored
    // to the glyph it holds — "the first Container under the row" is the
    // painted card, 372 wide, and that finder would have reported it as the
    // disc.
    final disc = tester.getRect(
      find
          .ancestor(
            of: find.descendant(
              of: find.byType(SettingsRow).first,
              matching: find.byType(Icon),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(disc.width, closeTo(AppSizes.iconDisc, 0.01));
    expect(disc.height, closeTo(AppSizes.iconDisc, 0.01));
  });
}
