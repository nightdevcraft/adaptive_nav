import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// An inactive tab keeps its state (`IndexedStack` keeps it alive).
void main() {
  testWidgets('inactive branch keeps its ephemeral state', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-inc')));
    await tester.pump();
    expect(find.text('Home: 1'), findsOneWidget);

    // There and back: the tab state is where we left it.
    h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.text('Home: 1'), findsOneWidget);
  });
}
