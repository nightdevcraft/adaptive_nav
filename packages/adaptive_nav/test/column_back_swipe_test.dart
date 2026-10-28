import 'dart:math' as math;

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav/src/column_transition.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// A screen that can go back, beside the rail in the column: `open` puts it
/// there, `text` is in it, `branch` is the tab it is in.
typedef _Beside = ({
  String name,
  DetailChrome chrome,
  int branch,
  Future<void> Function(DemoHarness h) open,
  String text,
});

/// On iPhone Duo a single pane stands beside the system's column: a
/// covering detail beside the bare column, any other screen beside the rail
/// in it. With the column at the leading edge, the iOS back swipe starts
/// there, in the column, a column's width away from the pane's own edge: the
/// shell takes it there and leads the pane's top route with it, as the
/// route's own swipe would.
void main() {
  int saves = 0;
  // Beside the rail the column shows the tabs and the screen's buttons
  // together; a test there says so.
  bool tabsWithButtons = false;
  setUp(() {
    saves = 0;
    tabsWithButtons = false;
  });

  Widget screens(DemoRoute route, Widget screen) => switch (route) {
    DemoList() => const ToolbarScreen(title: 'List'),
    DemoDetail(:final int id) => ToolbarScreen(
      title: 'Detail $id',
      pinned: <PaneToolbarItem>[toolbarItem(Icons.edit)],
    ),
    DemoEdit(:final int id) => ToolbarScreen(
      title: 'Edit $id',
      pinned: <PaneToolbarItem>[
        toolbarItem(Icons.check, onPressed: () => saves++),
      ],
    ),
    _ => screen,
  };

  Future<DemoHarness> pump(
    WidgetTester tester,
    DuoPose pose, {
    TextDirection? textDirection,
    DetailChrome detailChrome = DetailChrome.covered,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, pose.window, padding: pose.padding, display: pose.display);
    // The geometry above the app rather than the harness's, so a test can
    // change the posture under the same app.
    final DemoHarness h = DemoHarness(
      masterMinWidth: 270,
      detailMinWidth: 270,
      detailChrome: detailChrome,
      platform: platform,
      wrapPage: screens,
    );
    await tester.pumpWidget(
      SystemGeometryScope(
        geometry: pose.system,
        child: h.app(textDirection: textDirection),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  ModalRoute<Object?> routeOf(WidgetTester tester, String text) =>
      ModalRoute.of(tester.element(find.text(text)))!;

  /// The navigator the detail stands in: its area beside the column.
  Rect detailArea(WidgetTester tester, String text) => tester.getRect(
    find.ancestor(of: find.text(text), matching: find.byType(Navigator)).first,
  );

  /// The system's column: the inset on its side and the toolbar in it.
  Rect columnOf(WidgetTester tester, DuoPose pose) {
    final Rect toolbar = tester.getRect(
      find.byKey(AdaptiveShell.bareColumnKey),
    );
    final bool left = pose.system.verticalBar == ChromePlacement.left;
    final Size window = pose.window;
    return (left
            ? Rect.fromLTRB(0, 0, pose.padding.left, window.height)
            : Rect.fromLTRB(
                window.width - pose.padding.right,
                0,
                window.width,
                window.height,
              ))
        .expandToInclude(toolbar);
  }

  /// What of [finder] is in view: inside every clip above it, the panes'
  /// stacks' included.
  Rect seen(WidgetTester tester, Finder finder) {
    Rect r = tester.getRect(finder);
    tester.element(finder).visitAncestorElements((Element e) {
      final Widget w = e.widget;
      if (w is ClipRect || w is IndexedStack && w.clipBehavior != Clip.none) {
        r = r.intersect(tester.getRect(find.byElementPredicate((x) => x == e)));
      }
      return true;
    });
    return r;
  }

  /// How much of [icon] the system's column shows: the opacities above it,
  /// multiplied.
  double shown(WidgetTester tester, IconData icon) {
    double most = 0;
    for (final Key area in <Key>[
      AdaptiveShell.systemColumnKey,
      AdaptiveShell.bareColumnKey,
    ]) {
      for (final Element e
          in find
              .descendant(of: find.byKey(area), matching: find.byIcon(icon))
              .evaluate()) {
        double opacity = 1;
        e.visitAncestorElements((Element a) {
          if (a.widget is DrivenBox) {
            opacity *= (a.renderObject! as RenderDrivenBox).opacityNow;
          }
          return true;
        });
        most = math.max(most, opacity);
      }
    }
    return most;
  }

  /// Every frame: no screen in view reaches into the column, and the column
  /// shows the detail's buttons or the tabs, never both.
  void checkFrame(WidgetTester tester, Rect column, String when) {
    final Finder screens = find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) =>
            w.key == AdaptiveShell.mastersStackKey ||
            w.key == AdaptiveShell.detailsStackKey,
      ),
      matching: find.byType(Scaffold),
    );
    for (final Element e in screens.evaluate()) {
      final Rect r = seen(tester, find.byElementPredicate((x) => x == e));
      if (r.isEmpty || r.width <= 0) {
        continue;
      }
      expect(r.overlaps(column), isFalse, reason: '$when: $r');
    }
    final double buttons = math.max(
      shown(tester, Icons.close),
      shown(tester, Icons.edit),
    );
    final double tabs = math.max(
      shown(tester, Icons.people),
      shown(tester, Icons.home),
    );
    if (!tabsWithButtons) {
      expect(
        buttons == 0 || tabs == 0,
        isTrue,
        reason: '$when: $buttons $tabs',
      );
    }
  }

  /// A finger from [from] to [by] further, slowly: 8 points every 40 ms, a
  /// release far below a flick. [sign] is the way out. Checks every frame.
  Future<TestGesture> drag(
    WidgetTester tester,
    Offset from,
    double by,
    Rect column, {
    double sign = 1,
  }) async {
    final TestGesture g = await tester.startGesture(from);
    Duration t = Duration.zero;
    double done = 0;
    while (done < by) {
      final double step = math.min(8, by - done);
      done += step;
      t += const Duration(milliseconds: 40);
      await g.moveBy(Offset(sign * step, 0), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
      checkFrame(tester, column, 'dragging, $done');
    }
    return g;
  }

  /// The frames after a finger has gone, checked.
  Future<void> settle(WidgetTester tester, Rect column) async {
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      checkFrame(tester, column, 'after release, frame $i');
    }
    await tester.pumpAndSettle();
  }

  /// Lets go of [g] where it is, without speed, and runs the frames after.
  Future<void> release(WidgetTester tester, TestGesture g, Rect column) async {
    await g.up(timeStamp: const Duration(seconds: 100));
    await settle(tester, column);
  }

  NavigatorState detailNavigator(WidgetTester tester) => tester.state(
    find
        .descendant(
          of: find.byKey(AdaptiveShell.detailsStackKey),
          matching: find.byType(Navigator),
        )
        .first,
  );

  group('pose 2, the column at the leading edge', () {
    for (final double x in <double>[5, 40]) {
      testWidgets('from x=$x to the middle and let go: the detail goes', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(tester, duoPose(2));
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsOneWidget);
        final Rect column = columnOf(tester, duoPose(2));
        expect(x, lessThan(column.right), reason: 'in the column');
        final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
        final Rect area = detailArea(tester, 'Detail 1 body');
        final double left = tester.getTopLeft(find.text('Detail 1 body')).dx;

        // The finger moves the screen one to one.
        final TestGesture g = await drag(
          tester,
          Offset(x, 300),
          area.width * 0.55,
          column,
        );
        final double progress = 1 - detail.animation!.value;
        expect(progress, closeTo(0.55, 0.03));
        expect(
          tester.getTopLeft(find.text('Detail 1 body')).dx - left,
          closeTo(area.width * progress, 1),
          reason: 'the platform transition, not something of its own',
        );
        expect(detailNavigator(tester).userGestureInProgress, isTrue);
        // Let go: it goes on from where the finger left it, no jump back.
        await g.up(timeStamp: const Duration(seconds: 100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(1 - detail.animation!.value, greaterThanOrEqualTo(progress));
        await settle(tester, column);
        expect(h.delegate.state.active.entries, hasLength(1));
        expect(find.text('Detail 1 body'), findsNothing);
        expect(shown(tester, Icons.people), 1);
        expect(shown(tester, Icons.close), 0);
        expect(detailNavigator(tester).userGestureInProgress, isFalse);
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      });

      testWidgets('from x=$x to 0.3 and let go: the detail stays', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(tester, duoPose(2));
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        final Rect column = columnOf(tester, duoPose(2));
        final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
        final Rect area = detailArea(tester, 'Detail 1 body');
        final Offset at = tester.getTopLeft(find.text('Detail 1 body'));

        final TestGesture g = await drag(
          tester,
          Offset(x, 300),
          area.width * 0.3,
          column,
        );
        expect(1 - detail.animation!.value, closeTo(0.3, 0.03));
        expect(shown(tester, Icons.close), lessThan(1), reason: 'led');
        await release(tester, g, column);
        expect(h.delegate.state.active.entries, hasLength(2));
        expect(detail.animation!.value, 1);
        expect(tester.getTopLeft(find.text('Detail 1 body')), at);
        expect(shown(tester, Icons.close), 1);
        expect(shown(tester, Icons.people), 0);
        expect(detailNavigator(tester).userGestureInProgress, isFalse);
      });

      testWidgets('from x=$x, a quick flick: the detail goes', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(tester, duoPose(2));
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        final Rect column = columnOf(tester, duoPose(2));
        final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
        final TestGesture g = await tester.startGesture(Offset(x, 300));
        for (int i = 1; i <= 5; i++) {
          await g.moveBy(
            const Offset(16, 0),
            timeStamp: Duration(milliseconds: 8 * i),
          );
          await tester.pump();
        }
        // Not a fifth of the way: only the speed takes it.
        expect(1 - detail.animation!.value, lessThan(0.2));
        await g.up(timeStamp: const Duration(milliseconds: 48));
        for (int i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          checkFrame(tester, column, 'flick, frame $i');
        }
        await tester.pumpAndSettle();
        expect(h.delegate.state.active.entries, hasLength(1));
      });
    }

    testWidgets('a quick flick back towards the edge keeps the detail', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Detail 1 body');
      final TestGesture g = await drag(
        tester,
        const Offset(5, 300),
        area.width * 0.7,
        column,
      );
      const Duration t = Duration(seconds: 10);
      for (int i = 1; i <= 5; i++) {
        await g.moveBy(
          const Offset(-16, 0),
          timeStamp: t + Duration(milliseconds: 8 * i),
        );
        await tester.pump();
      }
      await g.up(timeStamp: t + const Duration(milliseconds: 48));
      await tester.pumpAndSettle();
      expect(h.delegate.state.active.entries, hasLength(2));
    });

    testWidgets("a tap on the column's buttons is still a tap", (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      Finder inColumn(IconData icon) => find.descendant(
        of: find.byKey(AdaptiveShell.bareColumnKey),
        matching: find.byIcon(icon),
      );
      final Rect strip = tester.getRect(
        find.byKey(AdaptiveShell.columnBackGestureKey),
      );
      expect(
        strip.contains(tester.getCenter(inColumn(Icons.arrow_back))),
        isTrue,
        reason: 'Back is in the strip',
      );

      // A press that moves a little, less than the slop, as fingers do.
      final TestGesture g = await tester.startGesture(
        tester.getCenter(inColumn(Icons.arrow_back)),
      );
      await g.moveBy(const Offset(kTouchSlop / 2, 0));
      await tester.pump();
      expect(detailNavigator(tester).userGestureInProgress, isFalse);
      await g.up();
      await tester.pumpAndSettle();
      expect(h.delegate.state.active.top.route, const DemoDetail(1));

      // Save, the same way.
      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      expect(
        strip.contains(tester.getCenter(inColumn(Icons.check))),
        isTrue,
        reason: 'Save is in the strip',
      );
      await tester.tap(inColumn(Icons.check));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(h.delegate.state.active.top.route, const DemoEdit(1));
      expect(detailNavigator(tester).userGestureInProgress, isFalse);
    });

    testWidgets('a swipe that starts on Save is a swipe, not a tap', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Edit 1 body');
      final Offset save = tester.getCenter(
        find.descendant(
          of: find.byKey(AdaptiveShell.bareColumnKey),
          matching: find.byIcon(Icons.check),
        ),
      );
      final TestGesture g = await drag(tester, save, area.width * 0.6, column);
      await release(tester, g, column);
      expect(saves, 0);
      expect(h.delegate.state.active.top.route, const DemoDetail(1));
    });

    testWidgets('a guard that says no: the screen stays', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      int asked = 0;
      h.delegate.push(
        const DemoEdit(1),
        onExit: () async {
          asked++;
          return false;
        },
      );
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final ModalRoute<Object?> edit = routeOf(tester, 'Edit 1 body');
      final Rect area = detailArea(tester, 'Edit 1 body');
      final TestGesture g = await drag(
        tester,
        const Offset(5, 300),
        area.width * 0.6,
        column,
      );
      expect(edit.animation!.value, 1, reason: 'not moved');
      expect(detailNavigator(tester).userGestureInProgress, isFalse);
      await release(tester, g, column);
      expect(h.delegate.state.active.top.route, const DemoEdit(1));
      expect(asked, 0, reason: "as the screen's own swipe: none at all");

      // The guard is still there to ask: back by other means asks it.
      h.delegate.pop();
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(h.delegate.state.active.top.route, const DemoEdit(1));
    });

    testWidgets('a screen over the detail goes first, then the detail', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Edit 1 body');
      TestGesture g = await drag(
        tester,
        const Offset(5, 300),
        area.width * 0.6,
        column,
      );
      await release(tester, g, column);
      expect(h.delegate.state.active.top.route, const DemoDetail(1));
      g = await drag(tester, const Offset(5, 300), area.width * 0.6, column);
      await release(tester, g, column);
      expect(h.delegate.state.active.entries, hasLength(1));
    });

    testWidgets("an inactive tab's detail does not take it", (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
      await h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      h.delegate.push(const DemoProfile());
      await tester.pumpAndSettle();
      // Home's screen beside the rail: the swipe is Profile's.
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsOneWidget);
      final TestGesture g = await tester.startGesture(const Offset(5, 300));
      for (int i = 0; i < 30; i++) {
        await g.moveBy(const Offset(10, 0));
        await tester.pump();
        expect(detail.animation!.value, 1, reason: 'not moved');
        expect(detailNavigator(tester).userGestureInProgress, isFalse);
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(h.delegate.state.branches[0].entries, hasLength(2));
      expect(h.delegate.state.branches[1].entries, hasLength(1));
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);

      // Back in People the swipe is its detail's again.
      await h.delegate.goBranch(0);
      await tester.pumpAndSettle();
      expect(identical(routeOf(tester, 'Detail 1 body'), detail), isTrue);
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Detail 1 body');
      final TestGesture again = await drag(
        tester,
        const Offset(5, 300),
        area.width * 0.6,
        column,
      );
      await release(tester, again, column);
      expect(h.delegate.state.branches[0].entries, hasLength(1));
      expect(h.delegate.state.branches[1].entries, hasLength(1));
    });

    testWidgets("the detail's own edge still swipes it", (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Detail 1 body');
      final TestGesture g = await drag(
        tester,
        Offset(area.left + 10, 300),
        area.width * 0.6,
        column,
      );
      await release(tester, g, column);
      expect(h.delegate.state.active.entries, hasLength(1));
    });

    testWidgets('the posture changes mid-swipe: the detail comes back', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
      final Rect area = detailArea(tester, 'Detail 1 body');
      final TestGesture g = await drag(
        tester,
        const Offset(5, 300),
        area.width * 0.4,
        column,
      );
      expect(detailNavigator(tester).userGestureInProgress, isTrue);
      final DuoPose one = duoPose(1);
      setPose(tester, one.window, padding: one.padding, display: one.display);
      await tester.pumpWidget(
        SystemGeometryScope(geometry: one.system, child: h.app()),
      );
      await tester.pump();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      await tester.pumpAndSettle();
      expect(detail.animation!.value, 1);
      expect(detailNavigator(tester).userGestureInProgress, isFalse);
      await g.up();
      await tester.pumpAndSettle();
      expect(h.delegate.state.active.entries, hasLength(2));
      expect(identical(routeOf(tester, 'Detail 1 body'), detail), isTrue);

      // And the next swipe, from the detail's edge now, works.
      final Rect now = detailArea(tester, 'Detail 1 body');
      final TestGesture next = await drag(
        tester,
        Offset(now.left + 5, 300),
        now.width * 0.6,
        columnOf(tester, one),
      );
      await release(tester, next, columnOf(tester, one));
      expect(h.delegate.state.active.entries, hasLength(1));
    });

    testWidgets('only on iOS', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      final DuoPose pose = duoPose(2);
      setPose(
        tester,
        pose.window,
        padding: pose.padding,
        display: pose.display,
      );
      final DemoHarness h = DemoHarness(
        system: pose.system,
        masterMinWidth: 270,
        detailMinWidth: 270,
        platform: TargetPlatform.android,
        wrapPage: screens,
      );
      await tester.pumpWidget(h.app());
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
    });
  });

  final List<_Beside> beside = <_Beside>[
    for (final DetailChrome chrome in DetailChrome.values)
      (
        name: 'Profile over Home, ${chrome.name}',
        chrome: chrome,
        branch: 1,
        open: (DemoHarness h) async {
          await h.delegate.goBranch(1);
          h.delegate.push(const DemoProfile());
        },
        text: 'Profile',
      ),
    (
      name: 'a kept detail',
      chrome: DetailChrome.kept,
      branch: 0,
      // Not awaited: the push's future is the screen's result.
      open: (DemoHarness h) async {
        h.delegate.push(const DemoDetail(1));
      },
      text: 'Detail 1 body',
    ),
  ];

  group('pose 2, a screen beside the rail in the column', () {
    for (final _Beside c in beside) {
      Future<(DemoHarness, Rect, ModalRoute<Object?>, Rect)> open(
        WidgetTester tester,
      ) async {
        tabsWithButtons = true;
        final DemoHarness h = await pump(
          tester,
          duoPose(2),
          detailChrome: c.chrome,
        );
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        await c.open(h);
        await tester.pumpAndSettle();
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsOneWidget);
        expect(h.delegate.state.activeBranch, c.branch);
        expect(h.delegate.state.active.entries, hasLength(2));
        return (
          h,
          columnOf(tester, duoPose(2)),
          routeOf(tester, c.text),
          detailArea(tester, c.text),
        );
      }

      for (final double x in <double>[5, 40]) {
        testWidgets('${c.name}: from x=$x to the middle and let go: it goes', (
          WidgetTester tester,
        ) async {
          final (
            DemoHarness h,
            Rect column,
            ModalRoute<Object?> top,
            Rect area,
          ) = await open(
            tester,
          );
          expect(x, lessThan(column.right), reason: 'in the column');
          final NavigatorState navigator = top.navigator!;
          final double left = tester.getTopLeft(find.text(c.text)).dx;
          final TestGesture g = await drag(
            tester,
            Offset(x, 300),
            area.width * 0.55,
            column,
          );
          final double progress = 1 - top.animation!.value;
          expect(progress, closeTo(0.55, 0.03));
          expect(
            tester.getTopLeft(find.text(c.text)).dx - left,
            closeTo(area.width * progress, 1),
          );
          expect(top.navigator!.userGestureInProgress, isTrue);
          await release(tester, g, column);
          expect(h.delegate.state.active.entries, hasLength(1));
          expect(h.delegate.state.activeBranch, c.branch);
          expect(find.text(c.text), findsNothing);
          expect(navigator.userGestureInProgress, isFalse);
          expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        });

        testWidgets('${c.name}: from x=$x to 0.3 and let go: it stays', (
          WidgetTester tester,
        ) async {
          final (
            DemoHarness h,
            Rect column,
            ModalRoute<Object?> top,
            Rect area,
          ) = await open(
            tester,
          );
          final Offset at = tester.getTopLeft(find.text(c.text));
          final TestGesture g = await drag(
            tester,
            Offset(x, 300),
            area.width * 0.3,
            column,
          );
          expect(1 - top.animation!.value, closeTo(0.3, 0.03));
          await release(tester, g, column);
          expect(h.delegate.state.active.entries, hasLength(2));
          expect(top.animation!.value, 1);
          expect(tester.getTopLeft(find.text(c.text)), at);
          expect(top.navigator!.userGestureInProgress, isFalse);
          expect(
            find.byKey(AdaptiveShell.columnBackGestureKey),
            findsOneWidget,
          );
        });

        testWidgets('${c.name}: from x=$x, a quick flick: it goes', (
          WidgetTester tester,
        ) async {
          final (DemoHarness h, Rect column, ModalRoute<Object?> top, Rect _) =
              await open(tester);
          final TestGesture g = await tester.startGesture(Offset(x, 300));
          for (int i = 1; i <= 5; i++) {
            await g.moveBy(
              const Offset(16, 0),
              timeStamp: Duration(milliseconds: 8 * i),
            );
            await tester.pump();
          }
          expect(1 - top.animation!.value, lessThan(0.2));
          await g.up(timeStamp: const Duration(milliseconds: 48));
          await settle(tester, column);
          expect(h.delegate.state.active.entries, hasLength(1));
        });
      }

      testWidgets('${c.name}: from x=86, past the column, short of the '
          'screen: it goes', (WidgetTester tester) async {
        final (DemoHarness h, Rect column, ModalRoute<Object?> top, Rect area) =
            await open(tester);
        // Between the inset and the screen: the rail's divider and the gap
        // beside it, which neither the column nor the screen covered.
        expect(column.right, lessThan(86));
        expect(area.left, greaterThan(86));
        final TestGesture g = await drag(
          tester,
          const Offset(86, 300),
          area.width * 0.55,
          column,
        );
        expect(1 - top.animation!.value, closeTo(0.55, 0.03));
        expect(top.navigator!.userGestureInProgress, isTrue);
        await release(tester, g, column);
        expect(h.delegate.state.active.entries, hasLength(1));
        expect(find.text(c.text), findsNothing);
      });

      testWidgets('${c.name}: a tap on a tab is still a tap', (
        WidgetTester tester,
      ) async {
        final (DemoHarness h, Rect _, ModalRoute<Object?> top, Rect _) =
            await open(tester);
        final int other = 1 - c.branch;
        // The tab's icon, in the rail, in the column.
        final Finder tab = find
            .byIcon(other == 0 ? Icons.people : Icons.home)
            .hitTestable();
        expect(tab, findsOneWidget);
        final Rect strip = tester.getRect(
          find.byKey(AdaptiveShell.columnBackGestureKey),
        );
        final Offset center = tester.getCenter(tab);
        expect(
          Rect.fromLTRB(
            strip.left,
            strip.top,
            math.min(strip.right, 84),
            strip.bottom,
          ).contains(center),
          isTrue,
          reason: 'the tab is in the strip',
        );
        // A press that moves a little, less than the slop, as fingers do.
        final TestGesture g = await tester.startGesture(center);
        await g.moveBy(const Offset(kTouchSlop / 2, 0));
        await tester.pump();
        expect(top.navigator!.userGestureInProgress, isFalse);
        await g.up();
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, other);
        expect(h.delegate.state.branches[c.branch].entries, hasLength(2));
        expect(top.animation!.value, 1);
      });

      testWidgets("${c.name}: an inactive tab's screen does not take it", (
        WidgetTester tester,
      ) async {
        final (DemoHarness h, Rect _, ModalRoute<Object?> top, Rect _) =
            await open(tester);
        final int other = 1 - c.branch;
        await h.delegate.goBranch(other);
        await tester.pumpAndSettle();
        // The other tab at its root: nowhere to go back to, no strip.
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        final TestGesture g = await tester.startGesture(const Offset(5, 300));
        for (int i = 0; i < 30; i++) {
          await g.moveBy(const Offset(10, 0));
          await tester.pump();
          expect(top.animation!.value, 1, reason: 'not moved');
          expect(top.navigator!.userGestureInProgress, isFalse);
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(h.delegate.state.branches[c.branch].entries, hasLength(2));
        expect(h.delegate.state.activeBranch, other);

        // Something to go back to in the other tab: the swipe is its own.
        h.delegate.push(other == 0 ? const DemoDetail(1) : const DemoProfile());
        await tester.pumpAndSettle();
        final Rect column = columnOf(tester, duoPose(2));
        final TestGesture again = await drag(
          tester,
          const Offset(5, 300),
          300,
          column,
        );
        await release(tester, again, column);
        expect(h.delegate.state.branches[other].entries, hasLength(1));
        expect(h.delegate.state.branches[c.branch].entries, hasLength(2));
        expect(top.animation!.value, 1);
      });
    }

    testWidgets('kept: a screen over the detail goes first, then the detail', (
      WidgetTester tester,
    ) async {
      tabsWithButtons = true;
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        detailChrome: DetailChrome.kept,
      );
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Edit 1 body');
      TestGesture g = await drag(
        tester,
        const Offset(40, 300),
        area.width * 0.6,
        column,
      );
      await release(tester, g, column);
      expect(h.delegate.state.active.top.route, const DemoDetail(1));
      g = await drag(tester, const Offset(5, 300), area.width * 0.6, column);
      await release(tester, g, column);
      expect(h.delegate.state.active.entries, hasLength(1));
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
    });

    testWidgets("kept: a tap on the column's Save is still a tap", (
      WidgetTester tester,
    ) async {
      tabsWithButtons = true;
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        detailChrome: DetailChrome.kept,
      );
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      final Finder save = find.byIcon(Icons.check).hitTestable();
      expect(save, findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(AdaptiveShell.columnBackGestureKey))
            .contains(tester.getCenter(save)),
        isTrue,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(h.delegate.state.active.top.route, const DemoEdit(1));
    });

    for (final DetailChrome chrome in DetailChrome.values) {
      testWidgets("${chrome.name}: a tab's root has no strip", (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(
          tester,
          duoPose(2),
          detailChrome: chrome,
        );
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        // A swipe from the column there moves nothing and opens nothing.
        final TestGesture g = await tester.startGesture(const Offset(5, 300));
        for (int i = 0; i < 30; i++) {
          await g.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 1);
        expect(h.delegate.state.active.entries, hasLength(1));
      });
    }

    testWidgets('a guard that says no: the screen stays', (
      WidgetTester tester,
    ) async {
      tabsWithButtons = true;
      final DemoHarness h = await pump(tester, duoPose(2));
      await h.delegate.goBranch(1);
      int asked = 0;
      h.delegate.push(
        const DemoProfile(),
        onExit: () async {
          asked++;
          return false;
        },
      );
      await tester.pumpAndSettle();
      final ModalRoute<Object?> top = routeOf(tester, 'Profile');
      final TestGesture g = await tester.startGesture(const Offset(5, 300));
      for (int i = 0; i < 30; i++) {
        await g.moveBy(const Offset(10, 0));
        await tester.pump();
        expect(top.animation!.value, 1, reason: 'not moved');
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(h.delegate.state.active.top.route, const DemoProfile());
      expect(asked, 0);
    });

    testWidgets('Android: no strip beside the rail', (
      WidgetTester tester,
    ) async {
      for (final DetailChrome chrome in DetailChrome.values) {
        final DemoHarness h = await pump(
          tester,
          duoPose(2),
          detailChrome: chrome,
          platform: TargetPlatform.android,
        );
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
        await h.delegate.goBranch(1);
        h.delegate.push(const DemoProfile());
        await tester.pumpAndSettle();
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      }
    });
  });

  for (final int number in <int>[1, 3]) {
    for (final DetailChrome chrome in DetailChrome.values) {
      testWidgets(
        'pose $number, ${chrome.name}: Profile over Home, as before',
        (WidgetTester tester) async {
          tabsWithButtons = true;
          final DuoPose pose = duoPose(number);
          final DemoHarness h = await pump(tester, pose, detailChrome: chrome);
          await h.delegate.goBranch(1);
          h.delegate.push(const DemoProfile());
          await tester.pumpAndSettle();
          expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
          final Rect column = columnOf(tester, pose);
          final Rect area = detailArea(tester, 'Profile');
          expect(area.left, 0, reason: "the screen's edge is the window's");
          TestGesture g = await drag(
            tester,
            Offset(pose.window.width - 5, 300),
            area.width * 0.6,
            column,
            sign: -1,
          );
          await release(tester, g, column);
          expect(h.delegate.state.active.entries, hasLength(2));
          g = await drag(
            tester,
            const Offset(5, 300),
            area.width * 0.6,
            column,
          );
          await release(tester, g, column);
          expect(h.delegate.state.active.entries, hasLength(1));
        },
      );
    }
  }

  testWidgets('pose 8, Split View on the left: as before', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setPose(
      tester,
      kDuoSplit,
      padding: kDuoSplitLeftPadding,
      display: kDuoInnerLandscape,
    );
    for (final DetailChrome chrome in DetailChrome.values) {
      final DemoHarness h = DemoHarness(
        masterMinWidth: 270,
        detailMinWidth: 270,
        detailChrome: chrome,
        platform: TargetPlatform.iOS,
        wrapPage: screens,
      );
      await tester.pumpWidget(
        SystemGeometryScope(
          geometry: const SystemGeometry(verticalBar: ChromePlacement.left),
          child: h.app(),
        ),
      );
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      await h.delegate.goBranch(1);
      h.delegate.push(const DemoProfile());
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      // The rail is on the left without a system column there: a finger
      // on it is the rail's, as before, and the screen's own edge swipes it.
      final double edge = detailArea(tester, 'Profile').left;
      expect(edge, greaterThan(40));
      for (final double x in <double>[5, edge + 5]) {
        final TestGesture g = await tester.startGesture(Offset(x, 300));
        for (int i = 0; i < 30; i++) {
          await g.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(
          h.delegate.state.active.entries,
          hasLength(x == 5 ? 2 : 1),
          reason: 'from x=$x',
        );
      }
    }
  });

  testWidgets('two panes, the column at the leading edge: as before', (
    WidgetTester tester,
  ) async {
    // Pose 5 right to left: the column on the right is the leading edge.
    final DemoHarness h = await pump(
      tester,
      duoPose(5),
      textDirection: TextDirection.rtl,
    );
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget, reason: 'two panes');
    expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
    await h.delegate.goBranch(1);
    h.delegate.push(const DemoProfile());
    await tester.pumpAndSettle();
    expect(
      find.byKey(AdaptiveShell.columnBackGestureKey),
      findsOneWidget,
      reason: 'one pane in Home',
    );
  });

  for (final int number in <int>[1, 3]) {
    testWidgets('pose $number, the column at the trailing edge: as before', (
      WidgetTester tester,
    ) async {
      final DuoPose pose = duoPose(number);
      final DemoHarness h = await pump(tester, pose);
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      final Rect column = columnOf(tester, pose);
      final Rect area = detailArea(tester, 'Detail 1 body');
      expect(area.left, 0, reason: "the detail's edge is the window's");

      // From the column, at the trailing edge, towards the screen: nothing.
      TestGesture g = await drag(
        tester,
        Offset(pose.window.width - 5, 300),
        area.width * 0.6,
        column,
        sign: -1,
      );
      await release(tester, g, column);
      expect(h.delegate.state.active.entries, hasLength(2));

      // From the window's leading edge, the detail's own: it goes.
      g = await drag(tester, const Offset(5, 300), area.width * 0.6, column);
      await release(tester, g, column);
      expect(h.delegate.state.active.entries, hasLength(1));
    });
  }

  group('RTL: the leading edge is the right one', () {
    for (final int number in <int>[1, 3]) {
      testWidgets('pose $number: from the column on the right', (
        WidgetTester tester,
      ) async {
        final DuoPose pose = duoPose(number);
        final DemoHarness h = await pump(
          tester,
          pose,
          textDirection: TextDirection.rtl,
        );
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsOneWidget);
        final Rect column = columnOf(tester, pose);
        final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
        final Rect area = detailArea(tester, 'Detail 1 body');
        for (final double x in <double>[5, 40]) {
          expect(x, lessThan(column.width), reason: 'in the column');
        }

        // Below the column's buttons: a finger on one gives the button its
        // slop first, as at the screen's own edge.
        final double below = pose.window.height * 0.6;

        // To 0.3: stays.
        TestGesture g = await drag(
          tester,
          Offset(pose.window.width - 5, below),
          area.width * 0.3,
          column,
          sign: -1,
        );
        expect(1 - detail.animation!.value, closeTo(0.3, 0.03));
        await release(tester, g, column);
        expect(h.delegate.state.active.entries, hasLength(2));

        // Past the middle: goes.
        g = await drag(
          tester,
          Offset(pose.window.width - 40, below),
          area.width * 0.55,
          column,
          sign: -1,
        );
        await release(tester, g, column);
        expect(h.delegate.state.active.entries, hasLength(1));
      });
    }

    testWidgets('pose 2: the column on the left is trailing, as before', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        textDirection: TextDirection.rtl,
      );
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnBackGestureKey), findsNothing);
      final Rect column = columnOf(tester, duoPose(2));
      final Rect area = detailArea(tester, 'Detail 1 body');
      final TestGesture g = await drag(
        tester,
        const Offset(5, 300),
        area.width * 0.6,
        column,
      );
      await release(tester, g, column);
      expect(h.delegate.state.active.entries, hasLength(2));
    });
  });

  testWidgets('the top route is tracked as pages come and go', (
    WidgetTester tester,
  ) async {
    final ColumnTransitions transitions = ColumnTransitions();
    addTearDown(transitions.dispose);
    final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
    List<Page<Object?>> pages(List<String> names) => <Page<Object?>>[
      for (final String n in names)
        MaterialPage<void>(key: ValueKey<String>(n), name: n, child: Text(n)),
    ];
    Future<void> show(List<String> names) => tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          key: key,
          pages: pages(names),
          onDidRemovePage: (Page<Object?> _) {},
          observers: <NavigatorObserver>[transitions.observerFor(key)],
        ),
      ),
    );
    await show(<String>['a', 'b']);
    expect(transitions.topOf(key)?.settings.name, 'b');
    await show(<String>['a', 'b', 'c']);
    await tester.pumpAndSettle();
    expect(transitions.topOf(key)?.settings.name, 'c');
    await show(<String>['a', 'c']);
    await tester.pumpAndSettle();
    expect(transitions.topOf(key)?.settings.name, 'c');
    await show(<String>['a']);
    await tester.pumpAndSettle();
    expect(transitions.topOf(key)?.settings.name, 'a');
  });
}
