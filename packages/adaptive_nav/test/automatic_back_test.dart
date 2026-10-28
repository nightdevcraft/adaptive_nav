import 'dart:math' as math;

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav/src/column_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';

/// A screen without a `PaneToolbar` gets its navigation button in the
/// system's column wherever its pane's toolbar is vertical, as
/// `UINavigationController` puts Back in iPhone Duo's vertical bar, and its
/// `AppBar` draws no arrow meanwhile (`AdaptiveShellConfig.automaticBackInColumn`).
void main() {
  /// A detail with a plain `AppBar` — no `leading`, no toolbar — and the
  /// harness's edit screen, which has none either.
  Widget plain(DemoRoute route, Widget screen) => switch (route) {
    DemoDetail(:final int id) => Scaffold(
      appBar: AppBar(title: Text('Detail $id')),
      body: Center(child: Text('Detail $id body')),
    ),
    _ => screen,
  };

  Future<DemoHarness> pump(
    WidgetTester tester, {
    required Size window,
    EdgeInsets padding = EdgeInsets.zero,
    Size? display,
    SystemGeometry? system,
    Widget Function(DemoRoute, Widget)? wrapPage,
    bool automaticBackInColumn = true,
    TargetPlatform? platform,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, window, padding: padding, display: display);
    final DemoHarness h = DemoHarness(
      system: system,
      wrapPage: wrapPage ?? plain,
      automaticBackInColumn: automaticBackInColumn,
      platform: platform,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    return h;
  }

  Future<DemoHarness> pumpDuo(
    WidgetTester tester,
    DuoPose pose, {
    Widget Function(DemoRoute, Widget)? wrapPage,
    bool automaticBackInColumn = true,
    TargetPlatform? platform,
  }) => pump(
    tester,
    window: pose.window,
    padding: pose.padding,
    display: pose.display,
    system: pose.system,
    wrapPage: wrapPage,
    automaticBackInColumn: automaticBackInColumn,
    platform: platform,
  );

  Finder inColumn(Finder matching) => find.descendant(
    of: find.byKey(AdaptiveShell.paneToolbarKey),
    matching: matching,
  );

  /// The arrows and crosses the `AppBar`s draw, of every pane.
  Finder headerButtons() => find.descendant(
    of: find.byType(AppBar),
    matching: find.byWidgetPredicate(
      (Widget w) => w is BackButton || w is CloseButton,
    ),
  );

  Future<void> open(WidgetTester tester, DemoHarness h, DemoRoute route) async {
    h.delegate.push(route);
    await tester.pumpAndSettle();
  }

  /// How much of [icon] is in view in the system's column: the opacities
  /// the column puts above it, multiplied; 0 where it is not there.
  double seen(WidgetTester tester, IconData icon) {
    double most = 0;
    // Both columns, not the toolbar's zone: the zone's key goes with the
    // toolbar that is there, and a transition has two.
    final Iterable<Element> found =
        <Key>[
          AdaptiveShell.systemColumnKey,
          AdaptiveShell.bareColumnKey,
        ].expand(
          (Key area) => find
              .descendant(of: find.byKey(area), matching: find.byIcon(icon))
              .evaluate(),
        );
    for (final Element e in found) {
      double opacity = 1;
      e.visitAncestorElements((Element a) {
        if (a.widget is DrivenBox) {
          opacity *= (a.renderObject! as RenderDrivenBox).opacityNow;
        }
        return true;
      });
      most = math.max(most, opacity);
    }
    return most;
  }

  group('a vertical bar: the button in the column, none in the header', () {
    for (final DuoPose pose in kDuoColumnPoses) {
      testWidgets('pose ${pose.number}', (WidgetTester tester) async {
        final DemoHarness h = await pumpDuo(tester, pose);
        expect(
          inColumn(find.byIcon(Icons.arrow_back)),
          findsNothing,
          reason: 'a root has nothing to go back to',
        );

        await open(tester, h, const DemoDetail(1));
        expect(
          inColumn(find.byIcon(Icons.close)),
          findsOneWidget,
          reason: "the detail's first screen, as with a PaneToolbar",
        );
        expect(headerButtons(), findsNothing);

        await open(tester, h, const DemoEdit(1));
        expect(inColumn(find.byIcon(Icons.arrow_back)), findsOneWidget);
        expect(inColumn(find.byIcon(Icons.close)), findsNothing);
        expect(headerButtons(), findsNothing);

        // The button pops, as the header's would.
        await tester.tap(inColumn(find.byIcon(Icons.arrow_back)));
        await tester.pumpAndSettle();
        expect(h.delegate.state.active.top.route, const DemoDetail(1));
        await tester.tap(inColumn(find.byIcon(Icons.close)));
        await tester.pumpAndSettle();
        expect(h.delegate.state.active.entries, hasLength(1));
        expect(inColumn(find.byIcon(Icons.close)), findsNothing);
      });
    }
  });

  group('a horizontal bar: the arrow in the header, nothing in a column', () {
    Future<void> check(WidgetTester tester, DemoHarness h) async {
      await open(tester, h, const DemoDetail(1));
      await open(tester, h, const DemoEdit(1));
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(BackButton),
        ),
        findsOneWidget,
      );
      expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);
      expect(inColumn(find.byIcon(Icons.close)), findsNothing);
    }

    testWidgets('a phone', (WidgetTester tester) async {
      await check(tester, await pump(tester, window: kCompact));
    });

    testWidgets('iPhone Duo, inner portrait', (WidgetTester tester) async {
      await check(
        tester,
        await pump(
          tester,
          window: kDuoInnerPortrait,
          padding: kDuoInnerPortraitPadding,
          display: kDuoInnerPortrait,
          system: const SystemGeometry(
            statusArea: Rect.fromLTRB(535, 0, 669, 82),
          ),
        ),
      );
    });
  });

  testWidgets('a change of pose moves the arrow, there and back', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    final DemoHarness h = DemoHarness(wrapPage: plain);
    final Widget app = h.app();
    Future<void> pose({required bool landscape}) async {
      final DuoPose inner = duoPose(5);
      setPose(
        tester,
        landscape ? inner.window : kDuoInnerPortrait,
        padding: landscape ? inner.padding : kDuoInnerPortraitPadding,
        display: landscape ? inner.display : kDuoInnerPortrait,
      );
      await tester.pumpWidget(
        SystemGeometryScope(
          geometry: landscape
              ? inner.system
              : const SystemGeometry(
                  statusArea: Rect.fromLTRB(535, 0, 669, 82),
                ),
          child: app,
        ),
      );
      await tester.pumpAndSettle();
    }

    final Finder headerBack = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(BackButton),
    );
    await pose(landscape: false);
    await open(tester, h, const DemoDetail(1));
    await open(tester, h, const DemoEdit(1));
    expect(headerBack, findsOneWidget);
    expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);

    for (int i = 0; i < 2; i++) {
      await pose(landscape: true);
      expect(headerBack, findsNothing);
      expect(inColumn(find.byIcon(Icons.arrow_back)), findsOneWidget);

      await pose(landscape: false);
      expect(headerBack, findsOneWidget);
      expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);
    }
    expect(h.delegate.state.active.top.route, const DemoEdit(1));
  });

  testWidgets('a header that decides for itself is left alone', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpDuo(
      tester,
      duoPose(1),
      // The harness's own detail, whose `AppBar` has a `BackButton` for a
      // `leading`; the edit screen turns the arrow off.
      wrapPage: (DemoRoute route, Widget screen) => switch (route) {
        DemoEdit(:final int id) => Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text('Editing $id'),
          ),
        ),
        _ => screen,
      },
    );
    await open(tester, h, const DemoDetail(1));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      ),
      findsOneWidget,
    );
    expect(inColumn(find.byIcon(Icons.close)), findsNothing);
    expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);

    await open(tester, h, const DemoEdit(1));
    expect(headerButtons(), findsNothing);
    expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);
    expect(inColumn(find.byIcon(Icons.close)), findsNothing);
  });

  testWidgets('automaticBackInColumn: false keeps the arrow in the header', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpDuo(
      tester,
      duoPose(1),
      automaticBackInColumn: false,
    );
    await open(tester, h, const DemoDetail(1));
    await open(tester, h, const DemoEdit(1));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      ),
      findsOneWidget,
    );
    expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);
    expect(inColumn(find.byIcon(Icons.close)), findsNothing);
  });

  testWidgets('a PaneToolbar keeps the column to itself', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpDuo(
      tester,
      duoPose(1),
      wrapPage: (DemoRoute route, Widget screen) => switch (route) {
        DemoEdit(:final int id) => PaneToolbar(
          pinned: <PaneToolbarItem>[
            PaneToolbarItem(icon: Icons.check, label: 'Save', onPressed: () {}),
          ],
          builder: (BuildContext context, PaneToolbarLayout toolbar) =>
              Scaffold(
                appBar: AppBar(
                  leading: toolbar.leading,
                  automaticallyImplyLeading: toolbar.automaticallyImplyLeading,
                  title: Text('Editing $id'),
                  actions: toolbar.actions,
                ),
              ),
        ),
        _ => plain(route, screen),
      },
    );
    await open(tester, h, const DemoDetail(1));
    await open(tester, h, const DemoEdit(1));
    expect(inColumn(find.byIcon(Icons.arrow_back)), findsOneWidget);
    expect(inColumn(find.byIcon(Icons.check)), findsOneWidget);
    expect(headerButtons(), findsNothing);
  });

  testWidgets("the column's button goes through the exit guard", (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpDuo(tester, duoPose(1));
    await open(tester, h, const DemoDetail(1));
    bool allow = false;
    int asked = 0;
    h.delegate.push(
      const DemoEdit(1),
      onExit: () async {
        asked++;
        return allow;
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(inColumn(find.byIcon(Icons.arrow_back)));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(h.delegate.state.active.top.route, const DemoEdit(1));
    expect(inColumn(find.byIcon(Icons.arrow_back)), findsOneWidget);

    allow = true;
    await tester.tap(inColumn(find.byIcon(Icons.arrow_back)));
    await tester.pumpAndSettle();
    expect(asked, 2);
    expect(h.delegate.state.active.top.route, const DemoDetail(1));
    expect(inColumn(find.byIcon(Icons.close)), findsOneWidget);
  });

  testWidgets('a push and a pop: one button, then the other', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pumpDuo(tester, duoPose(2));
    await open(tester, h, const DemoDetail(1));

    Future<void> frames(
      VoidCallback change, {
      required IconData from,
      required IconData to,
    }) async {
      change();
      bool both = false;
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (seen(tester, from) > 0 && seen(tester, to) > 0) {
          both = true;
        }
      }
      await tester.pumpAndSettle();
      expect(both, isFalse, reason: 'never one over the other');
      expect(seen(tester, from), 0);
      expect(seen(tester, to), 1);
    }

    await frames(
      () => h.delegate.push(const DemoEdit(1)),
      from: Icons.close,
      to: Icons.arrow_back,
    );
    await frames(h.delegate.pop, from: Icons.arrow_back, to: Icons.close);
  });

  testWidgets('the iOS swipe leads the button', (WidgetTester tester) async {
    final DemoHarness h = await pumpDuo(
      tester,
      duoPose(2),
      platform: TargetPlatform.iOS,
    );
    await open(tester, h, const DemoDetail(1));
    await open(tester, h, const DemoEdit(1));
    final ModalRoute<Object?> edit = ModalRoute.of(
      tester.element(find.text('Editing 1').first),
    )!;
    // The detail stands beside the column, and its edge is where the swipe
    // starts.
    final Rect area = tester.getRect(
      find
          .ancestor(
            of: find.text('Editing 1').first,
            matching: find.byType(Navigator),
          )
          .first,
    );
    final double width = area.width;

    final TestGesture swipe = await tester.startGesture(
      Offset(area.left + 10, 300),
    );
    await swipe.moveBy(const Offset(20, 0));
    await swipe.moveBy(Offset(width * 0.3, 0));
    await tester.pump();
    final double third = 1 - edit.animation!.value;
    expect(third, closeTo(0.3, 0.05));
    expect(seen(tester, Icons.arrow_back), closeTo(1 - 2 * third, 0.02));
    expect(seen(tester, Icons.close), 0);

    await swipe.moveBy(Offset(width * 0.3, 0));
    await tester.pump();
    final double past = 1 - edit.animation!.value;
    expect(seen(tester, Icons.arrow_back), 0);
    expect(
      seen(tester, Icons.close),
      closeTo(2 * past - 1, 0.02),
      reason: "what the swipe leads back to: the detail's Close",
    );

    await swipe.up();
    await tester.pumpAndSettle();
    expect(h.delegate.state.active.top.route, const DemoDetail(1));
    expect(seen(tester, Icons.close), 1);
    expect(seen(tester, Icons.arrow_back), 0);
  });
}
