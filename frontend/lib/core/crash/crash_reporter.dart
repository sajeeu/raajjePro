import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

abstract final class CrashConfig {
  /// Empty by default: no account is needed to build (plan §4 pulls crash
  /// reporting forward to Phase 3; the vendor DSN arrives at deployment —
  /// docs/deferred-verification.md L9).
  static const dsn = String.fromEnvironment('SENTRY_DSN');
}

/// The seam over the crash vendor (spec §8). Domain code never imports Sentry.
abstract class CrashReporter {
  Future<void> init();
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  });

  /// The user id only — never an email or phone (root CLAUDE.md 1d: no PII
  /// in event logs).
  Future<void> setUserId(String? id);
}

class NoopCrashReporter implements CrashReporter {
  @override
  Future<void> init() async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    if (kDebugMode) debugPrint('crash (unreported, no DSN): $error');
  }

  @override
  Future<void> setUserId(String? id) async {}
}

class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter(this.dsn);
  final String dsn;

  static SentryUser userFor(String id) => SentryUser(id: id);

  @override
  Future<void> init() => SentryFlutter.init((options) {
    options.dsn = dsn;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
  });

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    await Sentry.captureException(error, stackTrace: stack);
  }

  @override
  Future<void> setUserId(String? id) async {
    // sentry's configureScope returns FutureOr<void>, not Future<void> — the
    // brief's arrow form fails analysis, so this awaits it in a body instead.
    await Sentry.configureScope(
      (scope) => scope.setUser(id == null ? null : userFor(id)),
    );
  }
}

CrashReporter crashReporterFor(String dsn) =>
    dsn.isEmpty ? NoopCrashReporter() : SentryCrashReporter(dsn);

final crashReporterProvider = Provider<CrashReporter>(
  (_) => crashReporterFor(CrashConfig.dsn),
);
