import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/shared/shared.dart';

void main() {
  testWidgets('the app boots to its root screen, themed', (tester) async {
    await tester.pumpWidget(const RaajjeProApp());

    // The wordmark in the header and the title in the body.
    expect(find.text('RaajjePro'), findsNWidgets(2));
    expect(find.byType(AppHeader), findsOneWidget);
  });

  testWidgets('the component gallery is reachable by route', (tester) async {
    await tester.pumpWidget(const RaajjeProApp());
    await tester.tap(find.text('Component gallery'));
    // Not pumpAndSettle: the gallery shows a loading spinner that never
    // settles by design. Two frames — start the transition, then finish it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Components'), findsOneWidget);
  });
}
