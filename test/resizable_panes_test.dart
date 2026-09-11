import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Dragging the pane boundary, and the limits it obeys. The pixel-exact sum
/// of panes and gap has to survive a drag too.
void main() {
  const double gutter = 8;
  const double gap = 8;
  const double handle = 24;

  // The numbers below come from the demo branch: 0.35 of the pane area,
  // clamped at 320 and 360.
  const double masterMin = 320;
  const double detailMin = 360;
  const double ratio = 0.35;

  const Color dots = Color(0xFF654321);

  final PaneDecoration panes = PaneDecoration(
    margin: const EdgeInsets.all(gutter),
    gap: gap,
    radius: BorderRadius.circular(12),
    splitHandleWidth: handle,
    splitHandleColor: (BuildContext _) => dots,
  );

  Finder findDots() => find.byWidgetPredicate(
    (Widget w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == dots,
  );
  const RailDecoration rail = RailDecoration(
    margin: EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    dividerWidth: 0,
  );

  const double railRegion = kDefaultRailWidth + gutter;
  double paneArea(double window) => window - railRegion - 2 * gutter;

  Future<DemoHarness> pumpSplit(
    WidgetTester tester,
    Size size, {
    required PaneSplitController split,
    bool withDetail = true,
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

  double masterWidth(WidgetTester tester) =>
      tester.getRect(find.byType(DemoListScreen)).width;
  double detailWidth(WidgetTester tester) =>
      tester.getRect(find.byType(DemoDetailScreen)).width;

  Future<void> dragBy(WidgetTester tester, double dx) async {
    await tester.drag(
      find.byKey(AdaptiveShell.paneSplitHandleKey),
      Offset(dx, 0),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dragging right and left changes the pane widths', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    final double area = paneArea(1200);
    expect(masterWidth(tester), closeTo(area * ratio, 0.01));

    await dragBy(tester, 120);
    expect(masterWidth(tester), closeTo(area * ratio + 120, 0.01));

    await dragBy(tester, -60);
    expect(masterWidth(tester), closeTo(area * ratio + 60, 0.01));
  });

  // The core of the requirement: no pane ever goes below its "mobile"
  // minimum, however far it is dragged.
  testWidgets('clamp: the master never goes below its minimum', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    await dragBy(tester, -1000);
    expect(masterWidth(tester), masterMin);
    // Once more in the same direction: a hard stop rather than a debt — the
    // opposite move responds at once.
    await dragBy(tester, -1000);
    expect(masterWidth(tester), masterMin);
    await dragBy(tester, 40);
    expect(masterWidth(tester), closeTo(masterMin + 40, 0.01));
  });

  testWidgets('clamp: the detail never goes below its minimum', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    await dragBy(tester, 1000);
    expect(masterWidth(tester), paneArea(1200) - detailMin - gap);
    expect(detailWidth(tester), detailMin);
  });

  // After a drag the arithmetic is still EXACT.
  for (final double window in <double>[900, 1024, 1440]) {
    testWidgets('width $window: after a drag, panes + gap == the area', (
      WidgetTester tester,
    ) async {
      final PaneSplitController split = PaneSplitController();
      addTearDown(split.dispose);
      await pumpSplit(tester, Size(window, 900), split: split);

      for (final double dx in <double>[80, -140, 600, -600]) {
        await dragBy(tester, dx);
        expect(
          masterWidth(tester) + gap + detailWidth(tester),
          closeTo(paneArea(window), 0.01),
        );
        expect(
          tester.getRect(find.byType(DemoDetailScreen)).right,
          closeTo(window - gutter, 0.01),
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('the chosen fraction survives a resize and stays within bounds', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1400, 900), split: split);

    await dragBy(tester, 200);
    final double fraction = masterWidth(tester) / paneArea(1400);

    // The window narrows: the same fraction, a recomputed width.
    setWindow(tester, const Size(1100, 900));
    await tester.pumpAndSettle();
    expect(masterWidth(tester), closeTo(paneArea(1100) * fraction, 0.01));
    expect(
      masterWidth(tester) + gap + detailWidth(tester),
      closeTo(paneArea(1100), 0.01),
    );

    // Narrower still: the fraction would give the detail less than its
    // minimum, and the clamp holds it.
    setWindow(tester, const Size(830, 900));
    await tester.pumpAndSettle();
    expect(detailWidth(tester), greaterThanOrEqualTo(detailMin));
    expect(
      masterWidth(tester) + gap + detailWidth(tester),
      closeTo(paneArea(830), 0.01),
    );
  });

  testWidgets('at the threshold width there is no handle: nowhere to drag', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    // Exactly at the two-pane threshold: both panes are already at their
    // minimums.
    const double threshold =
        masterMin + detailMin + gap + 2 * gutter + railRegion;
    await pumpSplit(tester, const Size(threshold, 900), split: split);

    expect(masterWidth(tester), masterMin);
    expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
  });

  testWidgets('empty detail: one pane and no handle', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(
      tester,
      const Size(1200, 900),
      split: split,
      withDetail: false,
    );

    expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
  });

  testWidgets('compact: no divider and no drag', (WidgetTester tester) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, kCompact, split: split);

    expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
  });

  testWidgets('without a controller there is no handle at all', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(1200, 900));
    final DemoHarness h = DemoHarness(panes: panes, rail: rail);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
    expect(masterWidth(tester), closeTo(paneArea(1200) * ratio, 0.01));
  });

  // On desktop the boundary has to announce itself with a cursor: without one
  // the hit area is invisible and unfelt.
  testWidgets('the handle uses a resize cursor', (WidgetTester tester) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    final MouseRegion region = tester.widget<MouseRegion>(
      find.byKey(AdaptiveShell.paneSplitHandleKey),
    );
    expect(region.cursor, SystemMouseCursors.resizeColumn);
    // The area is wider than the gap, or it could not be hit by finger or
    // mouse.
    expect(
      tester.getRect(find.byKey(AdaptiveShell.paneSplitHandleKey)).width,
      handle,
    );
  });

  // The marker is needed exactly where there is no cursor (a tablet): without
  // it, the fact that the boundary can be dragged shows itself no other way.
  testWidgets('a three-dot marker sits inside the gap itself', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    expect(findDots(), findsNWidgets(3));

    // The marker is narrower than the gap: it never reaches the pane cards and
    // changes no geometry.
    final Rect master = tester.getRect(find.byType(DemoListScreen));
    for (int i = 0; i < 3; i++) {
      final Rect dot = tester.getRect(findDots().at(i));
      expect(dot.width, kPaneSplitDotSize);
      expect(dot.left, greaterThanOrEqualTo(master.right));
      expect(dot.right, lessThanOrEqualTo(master.right + gap));
    }
    expect(
      tester.getCenter(findDots().first).dy,
      lessThan(tester.getCenter(findDots().last).dy),
    );
    expect(tester.getCenter(findDots().at(1)).dy, closeTo(900 / 2, 0.01));
  });

  testWidgets('the marker travels with the boundary and goes with the handle', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    final DemoHarness h = await pumpSplit(
      tester,
      const Size(1200, 900),
      split: split,
    );

    final double before = tester.getCenter(findDots().first).dx;
    await dragBy(tester, 120);
    expect(tester.getCenter(findDots().first).dx, closeTo(before + 120, 0.01));

    // The detail was closed, so there is one pane and nothing to drag: no
    // handle and no marker.
    h.delegate.pop();
    await tester.pumpAndSettle();
    expect(findDots(), findsNothing);
  });

  testWidgets('with no marker colour the hit area stays invisible', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(1200, 900));
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    final DemoHarness h = DemoHarness(
      panes: PaneDecoration(
        margin: const EdgeInsets.all(gutter),
        gap: gap,
        splitHandleWidth: handle,
      ),
      rail: rail,
      paneSplit: split,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsOneWidget);
    expect(findDots(), findsNothing);
  });

  // The app's storage is poked on RELEASE, not on every frame.
  testWidgets('onCommit fires once on release, with the final fraction', (
    WidgetTester tester,
  ) async {
    final List<(Object, double)> commits = <(Object, double)>[];
    final PaneSplitController split = PaneSplitController(
      onCommit: (Object branch, double fraction) =>
          commits.add((branch, fraction)),
    );
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    await dragBy(tester, 100);
    expect(commits, hasLength(1));
    expect(commits.single.$1, 'staff');
    expect(
      commits.single.$2,
      closeTo((paneArea(1200) * ratio + 100) / paneArea(1200), 0.001),
    );
  });

  testWidgets('a restored fraction is applied at start-up, per branch', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController(
      initial: <Object, double>{'staff': 0.5},
    );
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    expect(masterWidth(tester), closeTo(paneArea(1200) * 0.5, 0.01));
  });

  // Restoring from storage is asynchronous: while it was on its way the user
  // may already have dragged the divider, and their choice must not be
  // overwritten.
  test('restore does not overwrite a branch already moved by hand', () {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);

    split.beginDrag('staff');
    split.drag('staff', 0.6);
    split.endDrag();

    split.restore(<Object, double>{'staff': 0.3, 'profile': 0.4});
    expect(split.fractionOf('staff'), 0.6);
    expect(split.fractionOf('profile'), 0.4);
  });

  // The drag changes ONLY the width of a `Positioned`: the navigators and
  // their state are intact.
  testWidgets('pane state is intact through a drag and a later resize', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pumpSplit(tester, const Size(1200, 900), split: split);

    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.tap(find.byKey(const ValueKey<String>('list-inc')));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);
    expect(find.text('List: 1'), findsOneWidget);

    await dragBy(tester, 150);
    expect(find.text('Counter: 1'), findsOneWidget);
    expect(find.text('List: 1'), findsOneWidget);

    setWindow(tester, const Size(1000, 900));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);
    expect(find.text('List: 1'), findsOneWidget);
  });
}
