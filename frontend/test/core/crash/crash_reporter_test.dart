import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';

void main() {
  test('an empty DSN yields the no-op reporter; a DSN yields Sentry', () {
    expect(crashReporterFor(''), isA<NoopCrashReporter>());
    expect(
      crashReporterFor('https://key@o1.ingest.sentry.io/1'),
      isA<SentryCrashReporter>(),
    );
  });

  test('the no-op reporter accepts every call and never throws', () async {
    final r = NoopCrashReporter();
    await r.init();
    await r.recordError(StateError('x'), StackTrace.current);
    await r.setUserId('u1');
    await r.setUserId(null);
  });

  test(
    'the Sentry reporter attaches only the user id, never email or phone',
    () {
      // SentryCrashReporter.userFor is the one place a user is described to the vendor.
      final user = SentryCrashReporter.userFor('u1');
      expect(user.id, 'u1');
      expect(user.email, isNull);
      expect(user.username, isNull);
      expect(user.data, isNull);
    },
  );
}
