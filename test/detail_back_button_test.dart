import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// A compact detail is an ordinary pushed screen and its `AppBar` draws the
/// back arrow itself. That rests on the transparent base page — `AppBar` only
/// draws an arrow when another route sits below.
void main() {
  testWidgets('compact: the detail gets a back arrow, and it pops', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    // The editor screen has no `BackButton` of its own in `leading` (unlike
    // the harness detail), so the `AppBar` has to supply the arrow itself.
    h.delegate.push(const DemoEdit(3));
    await tester.pumpAndSettle();
    expect(find.text('Editing 3'), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Editing 3'), findsNothing);
    expect(h.delegate.state.active.entries.length, 1);
  });
}
