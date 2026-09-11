import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// A window resize has to reach the panes in the same frame; the 240 ms
/// animation belongs to the detail reveal alone.
///
/// Tweening the master width directly meant every resize frame started a new
/// quarter-second journey, and the boundary trailed the window edge. Widths
/// here are measured after a single `pump()`.
void main() {
  const double gutter = 8;
  const double gap = 8;

  // Demo branch: paneRatio 0.35, default minimum widths (320 / 360).
  const double ratio = 0.35;
  const double masterMin = 320;
  const double detailMin = 360;

  const PaneDecoration panes = PaneDecoration(
    margin: EdgeInsets.all(gutter),
    gap: gap,
    radius: BorderRadius.zero,
    splitHandleWidth: 24,
  );
  const RailDecoration rail = RailDecoration(
    margin: EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    dividerWidth: 0,
  );

  const double railRegion = kDefaultRailWidth + gutter;
  double paneArea(double window) => window - railRegion - 2 * gutter;

  /// The final (unanimated) master width for window [window]: a fraction of
  /// the pane area, clamped by both panes' minimum widths.
  double settledMaster(double window) {
    final double area = paneArea(window);
    return (area * ratio).clamp(masterMin, area - detailMin - gap).toDouble();
  }

  double masterWidth(WidgetTester tester) =>
      tester.getRect(find.byType(DemoListScreen)).width;
  double detailWidth(WidgetTester tester) =>
      tester.getRect(find.byType(DemoDetailScreen)).width;

  Future<DemoHarness> pumpShell(
    WidgetTester tester,
    Size size, {
    bool withDetail = true,
    PaneSplitController? split,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, size);
    final DemoHarness h = DemoHarness(
      panes: panes,
      rail: rail,
      paneSplit: split,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    if (withDetail) {
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
    }
    return h;
  }

  testWidgets('resize with an open detail: both panes follow at once', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, const Size(1200, 900));
    expect(masterWidth(tester), closeTo(settledMaster(1200), 0.01));

    // There and back: one pump() is enough for the widths to become final for
    // the NEW window — there must be no intermediate, animated values.
    for (final double window in <double>[1400, 1000, 1400]) {
      setWindow(tester, Size(window, 900));
      await tester.pump();

      final double area = paneArea(window);
      final double master = settledMaster(window);
      expect(
        masterWidth(tester),
        closeTo(master, 0.01),
        reason: 'the master lagged behind the window edge $window',
      );
      expect(
        detailWidth(tester),
        closeTo(area - master - gap, 0.01),
        reason: 'the detail lagged behind the window edge $window',
      );
      // The arithmetic is exact even on the resize frame.
      expect(
        masterWidth(tester) + gap + detailWidth(tester),
        closeTo(area, 0.01),
      );
    }
  });

  testWidgets('resize with a collapsed detail: the master fills the area', (
    WidgetTester tester,
  ) async {
    // An empty detail gives the master the whole pane area, so its width
    // depends ENTIRELY on the window — this is where the lag showed most.
    await pumpShell(tester, const Size(1200, 900), withDetail: false);
    expect(masterWidth(tester), closeTo(paneArea(1200), 0.01));

    for (final double window in <double>[1400, 1000]) {
      setWindow(tester, Size(window, 900));
      await tester.pump();
      expect(
        masterWidth(tester),
        closeTo(paneArea(window), 0.01),
        reason: 'the collapsed master lagged behind the window edge $window',
      );
    }
  });

  /// Master widths frame by frame while the animation runs. Counted in frames
  /// rather than "measured at 120 ms": the first tick of
  /// `TweenAnimationBuilder` after the start is a no-op, and the exact frame
  /// is an implementation detail rather than behaviour.
  Future<List<double>> widthsWhileAnimating(WidgetTester tester) async {
    final List<double> widths = <double>[];
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      widths.add(masterWidth(tester));
    }
    return widths;
  }

  testWidgets('the detail reveal is still animated at an unchanged width', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpShell(
      tester,
      const Size(1200, 900),
      withDetail: false,
    );
    final double area = paneArea(1200);
    final double revealed = settledMaster(1200);

    h.delegate.push(const DemoDetail(1));
    await tester.pump();
    final List<double> widths = await widthsWhileAnimating(tester);

    // The master narrows GRADUALLY: there are frames strictly between the full
    // area and the pane width, rather than one jump to the final value.
    final Iterable<double> mid = widths.where(
      (double w) => w > revealed + 1 && w < area - 1,
    );
    expect(mid.length, greaterThanOrEqualTo(3), reason: 'no reveal animation');
    expect(widths.last, closeTo(revealed, 0.01));
  });

  testWidgets('the detail collapse is animated symmetrically', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpShell(tester, const Size(1200, 900));
    final double area = paneArea(1200);
    final double revealed = settledMaster(1200);

    h.delegate.pop();
    await tester.pump();
    final List<double> widths = await widthsWhileAnimating(tester);

    final Iterable<double> mid = widths.where(
      (double w) => w > revealed + 1 && w < area - 1,
    );
    expect(
      mid.length,
      greaterThanOrEqualTo(3),
      reason: 'the collapse is not animated',
    );
    expect(widths.last, closeTo(area, 0.01));
  });

  // The seam: the divider is grabbed while the detail is still arriving. The
  // reveal progress runs its course, the drag moves the final width, and by
  // the end of the animation the master lands exactly where it was dragged.
  testWidgets('dragging during the reveal lands on the dragged width', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    final DemoHarness h = await pumpShell(
      tester,
      const Size(1200, 900),
      withDetail: false,
      split: split,
    );

    h.delegate.push(const DemoDetail(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80)); // mid-reveal

    await tester.drag(
      find.byKey(AdaptiveShell.paneSplitHandleKey),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();

    expect(masterWidth(tester), closeTo(settledMaster(1200) + 120, 0.01));
    expect(
      masterWidth(tester) + gap + detailWidth(tester),
      closeTo(paneArea(1200), 0.01),
    );
  });
}
