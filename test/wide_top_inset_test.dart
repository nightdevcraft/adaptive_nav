import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The top system inset in the wide layout. The rail and the panes run up
/// under the status bar, as the cards do above a bottom bar: only their
/// margins are held back from the window's top edge, so the strip under the
/// clock takes the colour of whatever is below it. The rail reserves the rest
/// of the inset inside its own surface; each pane hands it to its screen,
/// where the `AppBar` reserves it.
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

  testWidgets('wide: the rail and the panes run up UNDER the status bar', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    final Rect master = tester.getRect(find.byType(DemoListScreen));
    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));

    // Only the card's own margin is held back from the window's top edge.
    expect(master.top, gutter);
    expect(detail.top, gutter);
    // The rail's destinations still start below the clock: the rest of the
    // inset is reserved inside the rail's card.
    expect(tester.getRect(find.byType(NavigationRail)).top, statusBar);
    // The inset does not move the bottom of the layout.
    expect(master.bottom, window.height - gutter);
    expect(
      tester.getRect(find.byType(NavigationRail)).bottom,
      window.height - gutter,
    );
  });

  testWidgets('wide: the strip under the clock is the rail\'s own colour', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    // Resolved the way `NavigationRail` resolves its own background.
    final BuildContext railContext = tester.element(
      find.byType(NavigationRail),
    );
    final Color railColor =
        NavigationRailTheme.of(railContext).backgroundColor ??
        Theme.of(railContext).colorScheme.surface;
    final Finder surface = find.ancestor(
      of: find.byType(NavigationRail),
      matching: find.byWidgetPredicate(
        (Widget w) => w is ColoredBox && w.color == railColor,
      ),
    );
    expect(surface, findsOneWidget);
    // From the card's top margin down, the reserve included.
    expect(tester.getRect(surface).top, gutter);
  });

  testWidgets('wide: the canvas still reaches the very edge', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    final Finder canvasBox = find.byWidgetPredicate(
      (Widget w) => w is ColoredBox && w.color == canvas,
    );
    expect(canvasBox, findsOneWidget);
    // Behind everything; it shows only in the margins.
    expect(tester.getRect(canvasBox), Offset.zero & window);
  });

  testWidgets('wide: the panes see what their margin leaves of the inset', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    // The screen's `AppBar` reserves it, so its title lands below the clock.
    expect(
      paddingAt(tester, find.byType(DemoListScreen)).top,
      statusBar - gutter,
    );
    expect(
      paddingAt(tester, find.byType(DemoDetailScreen)).top,
      statusBar - gutter,
    );
    expect(
      tester.getRect(find.byType(AppBar).first).top + (statusBar - gutter),
      statusBar,
    );
  });

  testWidgets('wide: the rail does NOT see the top inset', (
    WidgetTester tester,
  ) async {
    await pump(tester, size: window, top: statusBar);

    // Its surface already reserved it; left in, the `SafeArea` inside
    // `NavigationRail` would take it a second time.
    expect(paddingAt(tester, find.byType(NavigationRail)).top, 0);
  });

  testWidgets('flush panes: each pane runs to the window edge', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, window);
    setTopInset(tester, statusBar);
    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(DemoListScreen)).top, 0);
    expect(tester.getRect(find.byType(DemoDetailScreen)).top, 0);
    expect(paddingAt(tester, find.byType(DemoListScreen)).top, statusBar);
    expect(tester.getRect(find.byType(NavigationRail)).top, statusBar);
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
