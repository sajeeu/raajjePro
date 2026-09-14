import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/shared/shared.dart';

import '../helpers/pump.dart';

/// Haptics — owner's decision, 2026-09-14. The plan specifies none.
///
/// Worth testing precisely because a haptic is invisible *and* silent: it
/// leaves no pixel to assert and no exception when it stops firing, so it is
/// the easiest thing in the app to break without anyone noticing. The
/// platform channel is the only witness.
void main() {
  late List<String> fired;

  setUp(() {
    fired = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            fired.add(call.arguments as String? ?? 'default');
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  group('the vocabulary is three distinguishable events', () {
    test('each one plays something different', () async {
      AppHaptics.selection();
      AppHaptics.commit();
      AppHaptics.refused();
      await Future<void>.delayed(Duration.zero);

      expect(fired, hasLength(3));
      // Distinctness is the property that matters: a refusal that feels like
      // a success is worse than no haptic at all.
      expect(fired.toSet(), hasLength(3));
      expect(fired.first, contains('selectionClick'));
    });
  });

  group('the shared controls speak it', () {
    testWidgets('a toggle ticks when the choice changes', (tester) async {
      var value = false;
      await pumpScreen(
        tester,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppToggle(
              value: value,
              label: 'Accepting new customers',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();

      expect(value, isTrue);
      expect(fired, hasLength(1));
      expect(fired.single, contains('selectionClick'));
    });

    testWidgets('a disabled toggle stays silent', (tester) async {
      // The other half: feedback for something that did not happen teaches
      // people to distrust it.
      await pumpScreen(
        tester,
        const Scaffold(
          body: AppToggle(
            value: false,
            label: 'Accepting new customers',
            onChanged: null,
          ),
        ),
      );

      await tester.tap(find.byType(AppToggle), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fired, isEmpty);
    });
  });
}
