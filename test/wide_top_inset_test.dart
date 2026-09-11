import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The top system inset in the wide layout, where a pane starts at the window
/// edge and no `AppBar` reserves it. The shell does it once for the whole
/// layout and removes it for the subtree.
void main() {
  const double statusBar = 40;
  const double gutter = 8;
  const double gap = 8;
  const Color canvas = Color(0xFF123456);
  const Size window = Size(1200, 900);

  final PaneDecoration panes = PaneDecoration(
    margin: const EdgeInsets.all(gutter),
    gap: gap,
    radius: BorderRadius.circular(12),
    canvasColor: (BuildContext _) => canvas,
  );
  const RailDecoration rail = RailDecoration(
    margin: EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    radius: BorderRadius.all(Radius.circular(12)),
    dividerWidth: 0,
  );

  /// Sets the window top system inset (no keyboard, so `padding` matches
  /// `viewPadding`).
  void setTopInset(WidgetTester tester, double top) {
    final FakeViewPadding inset = FakeViewPadding(top: top);
    tester.view.padding = inset;
    tester.view.viewPadding = inset;
  }

  Future<DemoHarness> pump(
    WidgetTester tester, {
    required Size size,
    required double top,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, size);
    setTopInset(tester, top);
    final DemoHarness h = DemoHarness(panes: panes, rail: rail);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return h;
  }

  EdgeInsets paddingAt(WidgetTester tester, Finder finder) =>
      MediaQuery.of(tester.element(finder)).padding;

  testWidgets('wide: the rail and the panes start BELOW the status bar', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    final Rect railRect = tester.getRect(find.byType(NavigationRail));
    final Rect master = tester.getRect(find.byType(DemoListScreen));
    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));

    // The inset plus the card's own margin: under the clock there is neither
    // rail nor pane, only the canvas.
    expect(railRect.top, statusBar + gutter);
    expect(master.top, statusBar + gutter);
    expect(detail.top, statusBar + gutter);
    // The inset does not move the bottom of the layout: the reserve is at the
    // top only.
    expect(master.bottom, window.height - gutter);
    expect(railRect.bottom, window.height - gutter);
  });

  testWidgets('wide: the canvas reaches the very edge', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    final Finder canvasBox = find.byWidgetPredicate(
      (Widget w) => w is ColoredBox && w.color == canvas,
    );
    expect(canvasBox, findsOneWidget);
    // The status bar strip is painted with the canvas, not with a white pane
    // card.
    expect(tester.getRect(canvasBox), Offset.zero & window);
  });

  testWidgets('wide: the panes and rail subtree does NOT see the top inset', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    // Otherwise the `AppBar`/`SafeArea` of a screen inside a pane would inset
    // for the status bar a SECOND time — the canvas is already under it.
    expect(paddingAt(tester, find.byType(DemoListScreen)).top, 0);
    expect(paddingAt(tester, find.byType(DemoDetailScreen)).top, 0);
    expect(paddingAt(tester, find.byType(NavigationRail)).top, 0);
  });

  // A macOS-shaped window: there is no status bar (`padding.top == 0`), so
  // there is nothing to reserve and the layout is unchanged. Room for the
  // traffic lights is made by the rail inside its own card, which has nothing
  // to do with the system inset.
  testWidgets('padding.top == 0 (macOS): no extra padding appears', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: 0);

    expect(tester.getRect(find.byType(NavigationRail)).top, gutter);
    expect(tester.getRect(find.byType(DemoListScreen)).top, gutter);
    expect(tester.getRect(find.byType(DemoDetailScreen)).top, gutter);
  });

  // Compact is unaffected: there the top is reserved by the screen's own
  // `AppBar`, so the inset has to reach it untouched.
  testWidgets('compact: the inset is untouched, the screen handles it', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: kCompact, top: statusBar);

    final Finder screen = find.byType(DemoDetailScreen);
    expect(tester.getRect(screen).top, 0);
    expect(paddingAt(tester, screen).top, statusBar);
  });
}
