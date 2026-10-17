// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:nhatro_kieugiang/main.dart';

void main() {
  testWidgets('SplashScreen smoke test', (WidgetTester tester) async {
    // Build app and trigger frame
    await tester.pumpWidget(const MyApp());

    // Verify SplashScreen titles exist
    expect(find.text('Nhà Trọ'), findsOneWidget);
    expect(find.text('Kiêu Giang'), findsOneWidget);

    // Advance time past splash duration
    await tester.pump(const Duration(milliseconds: 5600));
    await tester.pumpAndSettle();
  });
}


