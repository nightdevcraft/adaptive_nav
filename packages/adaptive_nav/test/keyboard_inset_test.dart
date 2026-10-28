import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The keyboard belongs to the focused pane, not to the shell.
///
/// With the shell `Scaffold` squeezing itself, the keyboard height was
/// subtracted twice — once by the shell for the whole body, then again by the
/// screen inside a pane, which gets the window's `viewInsets` intact. On an
/// iPad in landscape that left the panes as empty rectangles.
void main() {
  const double keyboard = 400;
  const Size wide = Size(1200, 800);

  /// The body of the screen inside a pane — the `Column` of its `Scaffold`.
  /// That is what has to shrink for the keyboard: exactly once, and not to
  /// zero.
  double bodyHeight(WidgetTester tester, Finder screen) => tester
      .getSize(find.descendant(of: screen, matching: find.byType(Column)).first)
      .height;

  void openKeyboard(WidgetTester tester) {
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
  }

  testWidgets('wide: the keyboard does not squeeze the shell', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    harness.delegate.push(const DemoDetail(1));
    setWindow(tester, wide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    final Rect rail = tester.getRect(find.byType(NavigationRail));
    final Rect master = tester.getRect(find.byType(DemoListScreen));
    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
    expect(detail.height, wide.height);

    openKeyboard(tester);
    await tester.pumpAndSettle();

    // Neither the rail nor the panes move: the keyboard is not their business.
    expect(tester.getRect(find.byType(NavigationRail)), rail);
    expect(tester.getRect(find.byType(DemoListScreen)), master);
    expect(tester.getRect(find.byType(DemoDetailScreen)), detail);
  });

  testWidgets('wide: the keyboard is subtracted once, by the pane screen', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    harness.delegate.push(const DemoDetail(1));
    setWindow(tester, wide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    final Finder screen = find.byType(DemoDetailScreen);
    final double before = bodyHeight(tester, screen);

    openKeyboard(tester);
    await tester.pumpAndSettle();

    // Exactly ONE subtraction: the body is shorter by the keyboard height.
    // With a double one it would go to zero (the pane is already squeezed by
    // the shell) — the empty rectangles seen on an iPad.
    expect(bodyHeight(tester, screen), before - keyboard);
  });

  testWidgets('compact: the shell body is not squeezed, the screen takes it', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> key = GlobalKey<ScaffoldState>();
    final DemoHarness harness = DemoHarness(scaffoldKey: key);
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    final Finder screen = find.byType(DemoListScreen);
    final Rect shellBody = tester.getRect(screen);
    final double before = bodyHeight(tester, screen);

    openKeyboard(tester);
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byKey(key)).resizeToAvoidBottomInset,
      isFalse,
    );
    // The branch screen takes the same area, and the keyboard is handled by
    // its own `Scaffold`, just as it is for a detail overlay above the shell.
    expect(tester.getRect(screen), shellBody);
    expect(bodyHeight(tester, screen), before - keyboard);
  });
}
