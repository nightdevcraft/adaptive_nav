import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// One snack bar, in the pane the action came from.
///
/// The root messenger used to draw it in every root `Scaffold` of its set:
/// twice on compact, and stretched under both panes on wide.
void main() {
  /// Opens a detail in the master-detail branch of the demo harness.
  Future<DemoHarness> pump(WidgetTester tester, Size size) async {
    setWindow(tester, size);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final DemoHarness harness = DemoHarness();
    await tester.pumpWidget(harness.app());
    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();
    return harness;
  }

  /// Shows a snack bar exactly the way a screen does: through
  /// `ScaffoldMessenger.of` of its OWN context.
  Future<void> snackFrom(
    WidgetTester tester,
    Finder screenText,
    String message,
  ) async {
    ScaffoldMessenger.of(
      tester.element(screenText),
    ).showSnackBar(SnackBar(content: Text(message)));
    await tester.pumpAndSettle();
  }

  Finder masterScreen() => find.text('List: 0');
  Finder detailScreen() => find.text('Counter: 0');

  /// The PANE bounds, taken from the `Scaffold` of its screen: the exact pane
  /// width arithmetic lives in the layout tests, and all that matters here is
  /// which of the two panes the snack bar ended up in.
  Rect paneOf(WidgetTester tester, Finder screenText) => tester.getRect(
    find.ancestor(of: screenText, matching: find.byType(Scaffold)).first,
  );

  testWidgets('wide: one detail snack bar, inside the DETAIL pane', (
    WidgetTester tester,
  ) async {
    await pump(tester, kWide);
    await snackFrom(tester, detailScreen(), 'from detail');

    expect(find.text('from detail'), findsOneWidget);
    final Rect detail = paneOf(tester, detailScreen());
    final Rect snack = tester.getRect(find.text('from detail'));
    expect(snack.left, greaterThanOrEqualTo(detail.left));
    expect(snack.right, lessThanOrEqualTo(detail.right));
  });

  testWidgets('wide: one master snack bar, inside the MASTER pane', (
    WidgetTester tester,
  ) async {
    await pump(tester, kWide);
    await snackFrom(tester, masterScreen(), 'from master');

    expect(find.text('from master'), findsOneWidget);
    final Rect master = paneOf(tester, masterScreen());
    final Rect snack = tester.getRect(find.text('from master'));
    expect(snack.left, greaterThanOrEqualTo(master.left));
    expect(snack.right, lessThanOrEqualTo(master.right));
    // The point: the bar is NOT stretched under both panes and never touches
    // the detail.
    expect(snack.right, lessThan(paneOf(tester, detailScreen()).left));
  });

  testWidgets('compact: the detail snack bar is shown exactly once', (
    WidgetTester tester,
  ) async {
    await pump(tester, kCompact);
    await snackFrom(tester, detailScreen(), 'from detail');

    expect(find.text('from detail'), findsOneWidget);
  });

  testWidgets('a pane snack bar survives the compact to wide switch', (
    WidgetTester tester,
  ) async {
    await pump(tester, kCompact);
    await snackFrom(tester, detailScreen(), 'from detail');

    // The pane moves between layouts while its messenger holds on to a
    // `GlobalKey` from the delegate, so a visible snack bar must not vanish.
    setWindow(tester, kWide);
    await tester.pumpAndSettle();

    expect(find.text('from detail'), findsOneWidget);
  });
}
