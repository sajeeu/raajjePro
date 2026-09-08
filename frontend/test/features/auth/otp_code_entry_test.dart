import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/presentation/widgets/otp_code_entry.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  testWidgets(
    'pasting a six-digit string into the first box fills all six and fires onCompleted once',
    (tester) async {
      String? changed;
      var completedCount = 0;
      String? completed;
      await tester.pumpWidget(
        host(
          OtpCodeEntry(
            onChanged: (c) => changed = c,
            onCompleted: (c) {
              completedCount++;
              completed = c;
            },
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('otp-0')), '482913');
      await tester.pump();

      for (var i = 0; i < 6; i++) {
        expect(
          tester.widget<TextField>(find.byKey(Key('otp-$i'))).controller!.text,
          '482913'[i],
        );
      }
      expect(changed, '482913');
      expect(completedCount, 1);
      expect(completed, '482913');
    },
  );
}
