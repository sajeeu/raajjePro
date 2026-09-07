import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// Pumps [screen] inside the app theme and a ProviderScope with [overrides].
/// Two frames, never pumpAndSettle — skeletons and loading buttons animate
/// forever by design (frontend/CLAUDE.md).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Map<String, WidgetBuilder> routes = const {},
}) async {
  // `home: screen` also binds `screen` to route "/" internally, which
  // MaterialApp forbids when `routes` has its own "/" entry (a screen under
  // test may need "/" free to navigate to, e.g. after sign-in). Only the
  // colliding case switches to `onGenerateInitialRoutes` — plain `home` stays
  // the default so every existing caller with no (or a "/"-free) routes map
  // keeps building a Navigator the same way it always has.
  final collidesAtRoot = routes.containsKey('/');

  // A mobile viewport, not the 800×600 default: the app is designed at a
  // 412 dp frame (`mockups/design-composer/*.dc.html`), and the default
  // surface is landscape-shaped and too short for a full scrolling screen —
  // a control below the fold is unreachable by `tester.tap` even though it
  // is in the tree and would be reachable on a real phone.
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: collidesAtRoot ? null : screen,
        onGenerateInitialRoutes: collidesAtRoot
            ? (_) => [MaterialPageRoute<void>(builder: (_) => screen)]
            : null,
        routes: routes,
      ),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
