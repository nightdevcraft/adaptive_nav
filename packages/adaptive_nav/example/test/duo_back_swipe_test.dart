import 'package:adaptive_nav/adaptive_nav.dart';
// ignore: implementation_imports
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav_example/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPhone Duo, outer display turned left (pose 2): the system's column is at
/// the leading edge, with the rail in it beside a team's screen. The iOS back
/// swipe starts at the glass, in the column, and takes the team's screen off
/// as its own swipe would; the column's buttons stay buttons.
void main() {
  Future<void> pump(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    final double dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(678, 466) * dpr;
    tester.view.padding = FakeViewPadding(left: 84 * dpr, bottom: 34 * dpr);
    await tester.pumpWidget(
      SystemGeometryScope(
        geometry: const SystemGeometry(
          verticalBar: ChromePlacement.left,
          statusArea: Rect.fromLTRB(0, 0, 84, 82),
        ),
        child: Theme(
          data: ThemeData(platform: TargetPlatform.iOS),
          child: const ExampleApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final Finder strip = find.byKey(AdaptiveShell.columnBackGestureKey);
  final Finder team = find.widgetWithText(AppBar, 'Compilers');

  /// Teams, then Compilers over it; the strip comes with the team.
  Future<ModalRoute<Object?>> openTeam(WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Teams'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);
    expect(strip, findsNothing, reason: "the tab's root: nowhere back to");
    await tester.tap(find.text('Compilers'));
    await tester.pumpAndSettle();
    expect(team, findsOneWidget);
    expect(strip, findsOneWidget);
    return ModalRoute.of(tester.element(team))!;
  }

  /// The width of the pane the team's screen is in.
  double paneWidth(WidgetTester tester) => tester
      .getRect(find.ancestor(of: team, matching: find.byType(Navigator)).first)
      .width;

  Future<TestGesture> drag(WidgetTester tester, double x, double by) async {
    final TestGesture g = await tester.startGesture(Offset(x, 300));
    Duration t = Duration.zero;
    for (double done = 0; done < by; done += 8) {
      t += const Duration(milliseconds: 40);
      await g.moveBy(const Offset(8, 0), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return g;
  }

  for (final double x in <double>[5, 40]) {
    testWidgets('from x=$x past the middle: back to Teams', (
      WidgetTester tester,
    ) async {
      final ModalRoute<Object?> route = await openTeam(tester);
      final TestGesture g = await drag(tester, x, paneWidth(tester) * 0.6);
      expect(1 - route.animation!.value, closeTo(0.6, 0.03));
      expect(route.navigator!.userGestureInProgress, isTrue);
      await g.up(timeStamp: const Duration(seconds: 100));
      await tester.pumpAndSettle();
      expect(team, findsNothing);
      expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);
      expect(strip, findsNothing);
    });

    testWidgets('from x=$x to 0.3: the team stays', (
      WidgetTester tester,
    ) async {
      final ModalRoute<Object?> route = await openTeam(tester);
      final TestGesture g = await drag(tester, x, paneWidth(tester) * 0.3);
      expect(1 - route.animation!.value, closeTo(0.3, 0.03));
      await g.up(timeStamp: const Duration(seconds: 100));
      await tester.pumpAndSettle();
      expect(team, findsOneWidget);
      expect(route.animation!.value, 1);
      expect(route.navigator!.userGestureInProgress, isFalse);
    });

    testWidgets('from x=$x, a quick flick: back to Teams', (
      WidgetTester tester,
    ) async {
      final ModalRoute<Object?> route = await openTeam(tester);
      final TestGesture g = await tester.startGesture(Offset(x, 300));
      for (int i = 1; i <= 5; i++) {
        await g.moveBy(
          const Offset(16, 0),
          timeStamp: Duration(milliseconds: 8 * i),
        );
        await tester.pump();
      }
      expect(1 - route.animation!.value, lessThan(0.2));
      await g.up(timeStamp: const Duration(milliseconds: 48));
      await tester.pumpAndSettle();
      expect(team, findsNothing);
      expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);
    });
  }

  testWidgets("the column's Back, More and a tab are still taps", (
    WidgetTester tester,
  ) async {
    await openTeam(tester);
    final Rect area = tester.getRect(strip);
    final Finder back = find.byTooltip('Back').hitTestable();
    final Finder more = find.byTooltip('Show menu').hitTestable();
    for (final Finder f in <Finder>[back, more]) {
      expect(area.contains(tester.getCenter(f)), isTrue, reason: '$f');
    }

    // Back, pressed with a finger that moves a little, as fingers do.
    TestGesture g = await tester.startGesture(tester.getCenter(back));
    await g.moveBy(const Offset(kTouchSlop / 2, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(team, findsNothing);
    expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);

    // More, the same way, and People from its menu: another tab.
    await tester.tap(find.text('Compilers'));
    await tester.pumpAndSettle();
    g = await tester.startGesture(tester.getCenter(more));
    await g.moveBy(const Offset(kTouchSlop / 2, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('People').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
    expect(strip, findsNothing);

    // Back to Teams by its tab, in the strip's place, with the team kept.
    final Finder teams = find.byTooltip('Teams').hitTestable();
    expect(area.contains(tester.getCenter(teams)), isTrue);
    g = await tester.startGesture(tester.getCenter(teams));
    await g.moveBy(const Offset(kTouchSlop / 2, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(team, findsOneWidget);
    expect(strip, findsOneWidget);
  });
}
