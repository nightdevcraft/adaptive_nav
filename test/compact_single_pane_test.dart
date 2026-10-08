import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/pose.dart';
import '_harness/resize.dart';

/// Below [kCompactWidthBreakpoint] a branch is one pane, whatever its minimums.
///
/// 270 + 270 fit beside a bar but not beside a rail: a narrowing window would
/// go to one pane under the rail and back to two once a bar replaced it.
void main() {
  bool twoPanes(WidgetTester tester) => !tester
      .getRect(find.byType(DemoListScreen))
      .overlaps(tester.getRect(find.byType(DemoDetailScreen)));

  testWidgets('a narrowing window drops to one pane once', (
    WidgetTester tester,
  ) async {
    await pumpPose(
      tester,
      DemoHarness(masterMinWidth: 270, detailMinWidth: 270),
      const Size(1200, 800),
    );
    expect(twoPanes(tester), isTrue);

    final List<int> changes = <int>[];
    bool previous = true;
    for (int width = 1199; width >= 400; width--) {
      setWindow(tester, Size(width.toDouble(), 800));
      await tester.pump();
      final bool now = twoPanes(tester);
      if (now != previous) {
        changes.add(width);
        previous = now;
      }
    }

    expect(changes, hasLength(1), reason: 'changed at $changes');
    expect(previous, isFalse);
    expect(changes.single, greaterThanOrEqualTo(600));
  });

  testWidgets('iPhone Duo inner display in portrait: two panes', (
    WidgetTester tester,
  ) async {
    await pumpPose(
      tester,
      DemoHarness(masterMinWidth: 270, detailMinWidth: 270),
      kDuoInnerPortrait,
      padding: kDuoInnerPortraitPadding,
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(twoPanes(tester), isTrue);
  });

  testWidgets('iPhone Duo outer display: one pane', (
    WidgetTester tester,
  ) async {
    await pumpPose(
      tester,
      DemoHarness(masterMinWidth: 200, detailMinWidth: 200),
      kDuoOuterLandscape,
      padding: kDuoOuterLandscapePadding,
    );

    expect(twoPanes(tester), isFalse);
  });

  test('the breakpoint is measured without the side insets', () {
    expect(
      PaneMetrics.allowsTwoPanes(
        window: 680,
        padding: const EdgeInsets.only(left: 84),
      ),
      isFalse,
    );
    expect(
      PaneMetrics.allowsTwoPanes(window: 600, padding: EdgeInsets.zero),
      isTrue,
    );
  });
}
