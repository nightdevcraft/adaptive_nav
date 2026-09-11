import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The proof test: a counter in a detail survives compact -> wide -> compact.
/// Same delegate, stable keys, no State recreated.
void main() {
  testWidgets('detail ephemeral state survives compact→wide→compact', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('inc')));
      await tester.pump();
    }
    expect(find.text('Counter: 3'), findsOneWidget);

    // compact -> wide: the state must not reset.
    setWindow(tester, kWide);
    await tester.pumpAndSettle();
    expect(find.text('Counter: 3'), findsOneWidget);

    setWindow(tester, kCompact);
    await tester.pumpAndSettle();
    expect(find.text('Counter: 3'), findsOneWidget);
  });
}
