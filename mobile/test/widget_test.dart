import 'package:flutter_test/flutter_test.dart';

import 'package:zellia/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const ZelliaApp());
    await tester.pump();
    expect(find.byType(ZelliaApp), findsOneWidget);
  });
}
