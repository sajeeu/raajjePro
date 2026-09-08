import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';

Future<void> main() async {
  final reporter = crashReporterFor(CrashConfig.dsn);
  await reporter.init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      reporter.recordError(details.exception, details.stack, fatal: true),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(reporter.recordError(error, stack, fatal: true));
    return true;
  };
  runZonedGuarded(
    () => runApp(
      ProviderScope(
        overrides: [crashReporterProvider.overrideWithValue(reporter)],
        child: const RaajjeProApp(),
      ),
    ),
    (error, stack) =>
        unawaited(reporter.recordError(error, stack, fatal: true)),
  );
}
