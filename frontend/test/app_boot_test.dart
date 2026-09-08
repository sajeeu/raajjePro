import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';
import 'package:raajjepro/shared/shared.dart';

import 'helpers/fake_api.dart';
import 'helpers/pump.dart';

Future<void> _boot(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(FakeApiClient()),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        crashReporterProvider.overrideWithValue(NoopCrashReporter()),
        deviceNameProvider.overrideWith((_) async => 'Test'),
      ],
      child: const RaajjeProApp(),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('the app boots to the guest home, themed', (tester) async {
    await _boot(tester);

    // The wordmark in the header and the title in the body.
    expect(find.text('RaajjePro'), findsNWidgets(2));
    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the component gallery is reachable by route', (tester) async {
    await _boot(tester);
    await tester.tap(find.text('Component gallery'));
    // Not pumpAndSettle: the gallery shows a loading spinner that never
    // settles by design. Two frames — start the transition, then finish it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Components'), findsOneWidget);
  });
}
