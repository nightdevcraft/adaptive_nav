import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Resizing across a threshold moves the branch navigators by `GlobalKey`.
/// Inside a layout callback that crashed on a device whenever a deferred
/// overlay child reactivated.
///
/// Both thresholds are driven here. The harness screens carry an
/// `OverlayPortal`; without it the hole did not reproduce.
void main() {
  // Demo harness thresholds: the rail from 600 (`defaultShowsRail`), two panes
  // once the content area (window - rail 80 - divider 1) fits 320 + 360 + 1.
  const Size compact = Size(500, 900);
  const Size singlePane = Size(700, 900); // rail, one pane (619 < 681)
  const Size twoPanes = Size(900, 900); // 819 >= 681, two panes

  testWidgets('resizing across the thresholds does not break layout', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, compact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    for (int i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('inc')));
      await tester.pump();
    }
    expect(find.text('Counter: 2'), findsOneWidget);

    // Each transition is a separate check: an exception in layout does not
    // fail pumpAndSettle, it settles into `takeException`.
    for (final Size size in <Size>[
      twoPanes, // compact -> two panes
      singlePane, // two panes -> one (the master-detail threshold)
      twoPanes, // and back
      compact, // wide -> compact (the chrome threshold)
    ]) {
      setWindow(tester, size);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the resize to $size broke layout',
      );
      // Also: moving between layouts does not recreate the detail screen.
      expect(find.text('Counter: 2'), findsOneWidget);
    }
  });
}
