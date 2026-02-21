import 'package:flutter_test/flutter_test.dart';

import 'package:canvastalk/main.dart';

void main() {
  testWidgets('app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const CanvasTalkApp());
    await tester.pumpAndSettle();

    expect(find.text('CanvasTalk Runtime Studio'), findsOneWidget);
  });
}
