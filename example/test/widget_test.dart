import 'package:adaptive_nav_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the example starts on the people list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
  });

  testWidgets('system back from a team returns to Teams', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);

    await tester.tap(find.text('Compilers'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Compilers'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Compilers'), findsNothing);
  });
}
