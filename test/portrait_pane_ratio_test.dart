import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/pose.dart';
import '_harness/resize.dart';

/// `MasterDetailConfig.portraitPaneRatio`, with the example's People branch
/// minimums: 270 + 270.
void main() {
  const Size iPadPortrait = Size(820, 1180);
  const Size iPadLandscape = Size(1180, 820);

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    EdgeInsets padding = EdgeInsets.zero,
    double? portraitPaneRatio = 0.4,
    PaneSplitController? split,
  }) async {
    await pumpPose(
      tester,
      DemoHarness(
        alignToWindowCenter: true,
        portraitPaneRatio: portraitPaneRatio,
        masterMinWidth: 270,
        detailMinWidth: 270,
        paneSplit: split,
      ),
      size,
      padding: padding,
    );
  }

  Rect master(WidgetTester tester) =>
      tester.getRect(find.byType(DemoListScreen));
  Rect detail(WidgetTester tester) =>
      tester.getRect(find.byType(DemoDetailScreen));

  // 669 × 0.4 is under the master minimum, so the minimum decides.
  testWidgets('iPhone Duo in portrait: the master minimum wins', (
    WidgetTester tester,
  ) async {
    await pump(tester, kDuoInnerPortrait, padding: kDuoInnerPortraitPadding);

    expect(master(tester).width, 270);
    expect(detail(tester).width, 399);
  });

  testWidgets('iPad in portrait: the ratio of the pane area', (
    WidgetTester tester,
  ) async {
    await pump(tester, iPadPortrait);

    expect(find.byType(NavigationRail), findsOneWidget);
    final double area = iPadPortrait.width - kDefaultRailWidth - 1;
    expect(master(tester).width, closeTo(area * 0.4, 0.5));
  });

  testWidgets('iPad in landscape: split on the window centre', (
    WidgetTester tester,
  ) async {
    await pump(tester, iPadLandscape);

    expect(master(tester).right, closeTo(iPadLandscape.width / 2, 0.5));
  });

  testWidgets('a dragged width wins over the portrait ratio', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pump(tester, iPadPortrait, split: split);
    final double area = iPadPortrait.width - kDefaultRailWidth - 1;
    expect(master(tester).width, closeTo(area * 0.4, 0.5));

    // The first drag starts from the portrait ratio, not from the centre.
    await tester.drag(
      find.byKey(AdaptiveShell.paneSplitHandleKey),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(master(tester).width, closeTo(area * 0.4 + 60, 0.5));
  });

  testWidgets('a null ratio splits on the window centre in portrait', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      kDuoInnerPortrait,
      padding: kDuoInnerPortraitPadding,
      portraitPaneRatio: null,
    );

    expect(master(tester).width, kDuoInnerPortrait.width / 2);
  });
}
