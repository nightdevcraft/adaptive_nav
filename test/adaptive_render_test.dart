import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Chrome and pane count are derived separately, which is what makes three
/// layouts out of two breakpoints.
void main() {
  testWidgets('compact bar / medium rail+single / expanded rail+two panes', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);

    final DemoHarness h = DemoHarness();
    h.delegate.push(const DemoDetail(1)); // a detail makes the panes meaningful

    // compact: a bar and no rail.
    setWindow(tester, const Size(500, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    // medium: rail, one pane — master and detail overlap (same left).
    setWindow(tester, const Size(700, 900));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final double mMaster = tester.getTopLeft(find.byType(DemoListScreen)).dx;
    final double mDetail = tester.getTopLeft(find.byType(DemoDetailScreen)).dx;
    expect(mDetail, closeTo(mMaster, 0.5));

    // expanded: rail, two panes — the detail sits to the RIGHT of the master.
    setWindow(tester, const Size(1200, 900));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    final double eMaster = tester.getTopLeft(find.byType(DemoListScreen)).dx;
    final double eDetail = tester.getTopLeft(find.byType(DemoDetailScreen)).dx;
    expect(eDetail, greaterThan(eMaster + 100));
  });
}
