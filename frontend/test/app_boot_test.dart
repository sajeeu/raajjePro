import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';

void main() {
  testWidgets('the app boots to its root screen', (tester) async {
    await tester.pumpWidget(const RaajjeProApp());

    expect(find.text('RaajjePro'), findsOneWidget);
  });
}
