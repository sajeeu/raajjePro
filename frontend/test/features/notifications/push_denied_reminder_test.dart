import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/push/push_controller.dart';
import 'package:raajjepro/core/push/push_messaging.dart';
import 'package:raajjepro/features/notifications/presentation/push_denied_reminder.dart';

import '../../helpers/pump.dart';

/// Holds a fixed [PushState] so the reminder's rendering rule can be tested
/// without driving a whole registration flow.
class _FixedPushController extends PushController {
  _FixedPushController(this._state);
  final PushState _state;
  @override
  PushState build() => _state;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    PushState state, {
    VoidCallback? onOpen,
  }) => pumpScreen(
    tester,
    Scaffold(body: PushDeniedReminder(onOpenSettings: onOpen)),
    overrides: [
      pushControllerProvider.overrideWith(() => _FixedPushController(state)),
    ],
  );

  testWidgets(
    'shows the plan’s exact wording when the OS permission is denied',
    (tester) async {
      await pump(
        tester,
        const PushState(available: true, permission: PushPermission.denied),
      );
      expect(
        find.text('You may miss booking requests — enable notifications.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders nothing once notifications are granted', (tester) async {
    await pump(
      tester,
      const PushState(available: true, permission: PushPermission.granted),
    );
    expect(find.byType(PushDeniedReminder), findsOneWidget);
    expect(find.textContaining('may miss booking requests'), findsNothing);
  });

  testWidgets('renders nothing when no push vendor is wired in', (
    tester,
  ) async {
    // Telling someone to enable notifications that nothing is sending would
    // be untrue (docs/decisions/15-phase-3c-push.md).
    await pump(
      tester,
      const PushState(available: false, permission: PushPermission.denied),
    );
    expect(find.textContaining('may miss booking requests'), findsNothing);
  });

  testWidgets('is not dismissible — a transactional gap is not a preference', (
    tester,
  ) async {
    await pump(
      tester,
      const PushState(available: true, permission: PushPermission.denied),
    );
    // No close affordance of any kind.
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('the settings action is reachable and announced', (tester) async {
    var opened = 0;
    await pump(
      tester,
      const PushState(available: true, permission: PushPermission.denied),
      onOpen: () => opened += 1,
    );
    await tester.tap(find.text('Open settings'));
    expect(opened, 1);

    final semantics = tester.getSemantics(find.text('Open settings'));
    expect(semantics.label, contains('Open settings'));
  });
}
