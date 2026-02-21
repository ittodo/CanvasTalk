import 'package:flutter_test/flutter_test.dart';

import 'package:asciipaint/main.dart';

void main() {
  testWidgets('app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AsciiPaintApp());
    await tester.pumpAndSettle();

    expect(find.text('AsciiPaint Runtime Studio'), findsOneWidget);
  });
}
