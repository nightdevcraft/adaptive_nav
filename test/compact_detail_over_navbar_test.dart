import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The compact detail layer covers the bar. Taps reach the bar only while the
/// detail is empty, and therefore transparent.
void main() {
  testWidgets(
    'navbar clickable when detail empty, covered when detail present',
    (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setWindow(tester, kCompact);

      final DemoHarness h = DemoHarness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      // The detail is empty, so the tap reaches the bar and we switch to Home.
      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);

      h.delegate.goBranch(0);
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(find.text('Detail 1'), findsOneWidget);

      // The detail covers the bar, so the tap is swallowed and the branch
      // does not change.
      await tester.tap(find.byIcon(Icons.home), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 0);
      expect(find.text('Detail 1'), findsOneWidget);
    },
  );
}
