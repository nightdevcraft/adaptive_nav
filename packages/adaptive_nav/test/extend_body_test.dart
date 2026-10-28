import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `extendBodyBehindBar`, for apps with a floating bar. Off by default, and
/// never applied to the rail.
void main() {
  /// The SHELL `Scaffold` (screens have their own) — fetched by config key.
  Scaffold shellScaffold(WidgetTester tester, GlobalKey<ScaffoldState> key) =>
      tester.widget<Scaffold>(find.byKey(key));

  testWidgets('flag on: the compact shell extends the body under the bar', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> key = GlobalKey<ScaffoldState>();
    final DemoHarness harness = DemoHarness(
      scaffoldKey: key,
      extendBodyBehindBar: true,
    );
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(shellScaffold(tester, key).extendBody, isTrue);

    // The observable effect rather than the flag value: the branch screen
    // takes the full window height, its bottom running UNDER the bar.
    final Rect bar = tester.getRect(find.byType(NavigationBar));
    expect(
      tester.getRect(find.byType(DemoListScreen)).bottom,
      closeTo(kCompact.height, 0.5),
    );
    expect(bar.top, lessThan(kCompact.height));
  });

  testWidgets('by default the body ends ABOVE the bar', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> key = GlobalKey<ScaffoldState>();
    final DemoHarness harness = DemoHarness(scaffoldKey: key);
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(shellScaffold(tester, key).extendBody, isFalse);
    expect(
      tester.getRect(find.byType(DemoListScreen)).bottom,
      closeTo(tester.getRect(find.byType(NavigationBar)).top, 0.5),
    );
  });

  testWidgets('the flag does nothing in the wide layout', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> key = GlobalKey<ScaffoldState>();
    final DemoHarness harness = DemoHarness(
      scaffoldKey: key,
      extendBodyBehindBar: true,
    );
    // Branch 1 (Home) has no master-detail: on wide it is one pane plus rail.
    harness.delegate.goBranch(1);
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(shellScaffold(tester, key).extendBody, isFalse);
  });
}
