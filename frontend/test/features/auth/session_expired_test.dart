import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/auth/presentation/session_expired_screen.dart';

import '../../helpers/pump.dart';

void main() {
  testWidgets('one action, one promise, nothing about lost work', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const SessionExpiredScreen(),
      routes: {'/sign-in': (_) => const Scaffold(body: Text('SIGNIN'))},
    );
    expect(find.text('Signed out for your security'), findsOneWidget);
    expect(find.textContaining('What you were typing is kept'), findsOneWidget);
    expect(find.textContaining('lost'), findsNothing);
    await tester.tap(find.text('Sign In Again'));
    await settle(tester);
    expect(find.text('SIGNIN'), findsOneWidget);
  });
}
