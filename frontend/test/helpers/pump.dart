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
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light(), home: screen, routes: routes),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
