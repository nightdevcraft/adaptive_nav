import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `DetailEntryScope`: how deep a screen sits in the detail stack, which is
/// what an app bar needs to choose between a close button and a back arrow.
/// `Navigator.canPop()` cannot tell — the base page makes everything
/// poppable.
void main() {
  /// The index the screen at the top of the stack sees.
  int? indexAt(WidgetTester tester, Finder screen) {
    final BuildContext context = tester.element(screen);
    return context
        .dependOnInheritedWidgetOfExactType<DetailEntryScope>()
        ?.index;
  }

  testWidgets('the first detail is 0, one pushed deeper is 1', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(2));
    await tester.pumpAndSettle();
    expect(indexAt(tester, find.text('Detail 2')), 0);
    expect(
      DetailEntryScope.isDetailRoot(tester.element(find.text('Detail 2'))),
      isTrue,
    );

    h.delegate.push(const DemoEdit(3));
    await tester.pumpAndSettle();
    expect(indexAt(tester, find.text('Editing 3').first), 1);
    expect(
      DetailEntryScope.isDetailRoot(
        tester.element(find.text('Editing 3').first),
      ),
      isFalse,
      reason: 'the screen went deeper: back dismisses it, not a close',
    );
  });

  testWidgets('a main-navigator screen does not count as a detail', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    // The branch root (the master pane) is not a detail: index `-1`.
    expect(indexAt(tester, find.text('List')), -1);
    expect(
      DetailEntryScope.isDetailRoot(tester.element(find.text('List'))),
      isFalse,
    );
  });

  testWidgets('the depth is the same on compact: layout does not change it', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(2));
    await tester.pumpAndSettle();
    expect(indexAt(tester, find.text('Detail 2')), 0);

    h.delegate.push(const DemoEdit(3));
    await tester.pumpAndSettle();
    expect(indexAt(tester, find.text('Editing 3').first), 1);
  });
}
