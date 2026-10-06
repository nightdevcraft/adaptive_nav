import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// iPhone Duo: the four postures, laid out the way Apple's guidance asks.
///
/// On the outer display the chrome joins the system's own column — the one
/// with the camera at the end of it — and on the inner display it keeps the
/// arrangement it has everywhere else. See `chrome_layout_test.dart` for the
/// rule and for the devices it may not touch. The rail region is 81 (80 plus
/// its divider) and the system column 84.
void main() {
  const double railRegion = kDefaultRailWidth + kDefaultRailDividerWidth;
  const double statusBar = 84;
  // The rail joins the system's column and is held off the edge to share its
  // axis, so the column is a little wider than the bare 84.
  final double column =
      railRegion + SystemBarMetrics.measured.edgeGap(kDefaultRailWidth);

  double paneArea(Size size, EdgeInsets padding) => PaneMetrics.paneAreaWidth(
    window: size.width,
    padding: padding,
    placement: defaultChromeLayout(size, padding),
    railWidth: kDefaultRailWidth,
    panes: PaneDecoration.none,
  );

  group('what each posture leaves to the panes', () {
    // One column, not two: the rail is inside the 84 the system reserved, so
    // only 84 comes off — the rail's own 81 is already in there.
    test('outer portrait: one column comes off, not two', () {
      expect(
        paneArea(kDuoOuterPortrait, kDuoOuterPortraitPadding),
        kDuoOuterPortrait.width - column, // 377
      );
    });

    test('outer landscape: the same, on the other side', () {
      expect(
        paneArea(kDuoOuterLandscape, kDuoOuterLandscapePadding),
        kDuoOuterLandscape.width - column, // 589
      );
    });

    // Horizontal bars, so no rail region at all and the whole width is usable:
    // the inner display in portrait is the roomiest posture for panes.
    test('inner portrait: the full width', () {
      expect(
        paneArea(kDuoInnerPortrait, kDuoInnerPortraitPadding),
        kDuoInnerPortrait.width, // 669
      );
    });

    // The rail leads and the system bar is on the far edge, so both come off
    // — the bar as an inset the detail merely bleeds under.
    test('inner landscape: the rail leads, the bar is opposite', () {
      expect(
        paneArea(kDuoInnerLandscape, kDuoInnerLandscapePadding),
        kDuoInnerLandscape.width - railRegion - statusBar, // 786
      );
    });
  });

  group('what each posture renders', () {
    Future<DemoHarness> pump(
      WidgetTester tester,
      Size size,
      EdgeInsets padding, {
      double masterMinWidth = 320,
      double detailMinWidth = 360,
      bool withDetail = true,
    }) async {
      addTearDown(tester.view.reset);
      setPose(tester, size, padding: padding);
      final DemoHarness h = DemoHarness(
        masterMinWidth: masterMinWidth,
        detailMinWidth: detailMinWidth,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      if (withDetail) {
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
      }
      return h;
    }

    bool split(WidgetTester tester) => !tester
        .getRect(find.byType(DemoDetailScreen))
        .overlaps(tester.getRect(find.byType(DemoListScreen)));

    testWidgets('outer portrait: the rail is in the camera column', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoOuterPortrait, kDuoOuterPortraitPadding);

      expect(find.byType(NavigationBar), findsNothing);
      final Rect rail = tester.getRect(find.byType(NavigationRail));
      // Centred on the line the system centres its own glyphs on, inside the
      // column the bar stands in.
      expect(rail.center.dx, kDuoOuterPortrait.width - 48);
      expect(rail.width, kDefaultRailWidth);
      // And below the camera and the clock, not beside them.
      expect(rail.top, SystemBarMetrics.measured.reserve);
      // Too narrow for two panes, as Apple asks of the outer display.
      expect(split(tester), isFalse);
    });

    testWidgets('outer portrait: a flush rail fills its column to the edge', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoOuterPortrait, kDuoOuterPortraitPadding);

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      final BuildContext railContext = tester.element(
        find.byType(NavigationRail),
      );
      final Color railColor =
          NavigationRailTheme.of(railContext).backgroundColor ??
          Theme.of(railContext).colorScheme.surface;
      // The gap that centres the rail on the system's axis is the rail's
      // colour, not a strip of background against the window edge.
      final Iterable<Rect> gaps = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((ColoredBox b) => b.color == railColor)
          .map((ColoredBox b) => tester.getRect(find.byWidget(b)))
          .where((Rect r) => r.left == rail.right);
      expect(gaps, hasLength(1));
      expect(gaps.single.right, kDuoOuterPortrait.width);
      expect(gaps.single.top, 0);
      expect(gaps.single.bottom, kDuoOuterPortrait.height);
    });

    testWidgets('outer landscape: the column moves with the bar', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoOuterLandscape, kDuoOuterLandscapePadding);

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.center.dx, 48);
      expect(rail.width, kDefaultRailWidth);
      // No clock in landscape, only the camera, so the reserve is shorter.
      expect(rail.top, SystemBarMetrics.measured.landscapeReserve);
    });

    testWidgets('outer landscape turned the other way: camera at the bottom', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoOuterLandscape, kDuoOuterLandscapeRightPadding);

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.center.dx, kDuoOuterLandscape.width - 48);
      // The destinations start at the top, and the reserve is at the bottom,
      // where the camera and the clock are. The home indicator's 34 is part
      // of it: the rail's own `SafeArea` keeps that inside the rail.
      expect(rail.top, 0);
      expect(
        rail.bottom,
        kDuoOuterLandscape.height -
            (SystemBarMetrics.measured.landscapeReserve -
                kDuoOuterLandscapeRightPadding.bottom),
      );
    });

    testWidgets('the end is configurable', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setPose(
        tester,
        kDuoOuterLandscape,
        padding: kDuoOuterLandscapeRightPadding,
      );
      final DemoHarness h = DemoHarness(
        systemBar: SystemBarMetrics(end: (_, _) => SystemBarEnd.top),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(NavigationRail)).top,
        SystemBarMetrics.measured.landscapeReserve,
      );
    });

    testWidgets('the reserve is configurable, and zero keeps the top', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
      final DemoHarness h = DemoHarness(systemBar: SystemBarMetrics.none);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.top, 0);
      expect(rail.right, kDuoOuterPortrait.width);
    });

    // Apple's exception, and the posture the package used to get most wrong:
    // it showed a rail and a single pane.
    testWidgets('inner portrait: a bottom bar, with two panes above it', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoInnerPortrait,
        kDuoInnerPortraitPadding,
        masterMinWidth: 280,
        detailMinWidth: 300,
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(split(tester), isTrue);
      // The master is at its minimum and the detail takes the rest.
      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      expect(master.left, 0);
      expect(master.width, 280);
      expect(detail.right, kDuoInnerPortrait.width);
    });

    // The cards run up under the status bar and the screens inside reserve
    // what is left of it, so the 82-point inset costs no height: leaving the
    // whole of it to the shell would put a band that deep of bare canvas above
    // the panes, and leaving the whole of it to the screens would have each
    // `AppBar` reserve it below the card's margin and sit that much too low.
    testWidgets('inner portrait: the status bar is not wasted twice', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoInnerPortrait, padding: kDuoInnerPortraitPadding);
      final DemoHarness h = DemoHarness(
        masterMinWidth: 280,
        detailMinWidth: 300,
        panes: const PaneDecoration(margin: EdgeInsets.all(12), gap: 8),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      final Finder master = find.byType(DemoListScreen);
      final Finder detail = find.byType(DemoDetailScreen);
      // The card stops at its own margin, not below the inset...
      expect(tester.getRect(master).top, 12);
      expect(tester.getRect(detail).top, 12);
      // ...and the screen inside clears what is left of the inset over it, so
      // its `AppBar` title still lands below the status bar, at 82.
      expect(MediaQuery.of(tester.element(master)).padding.top, 82 - 12);
      expect(MediaQuery.of(tester.element(detail)).padding.top, 82 - 12);
      expect(tester.getRect(find.byType(AppBar).first).top + (82 - 12), 82.0);
    });

    testWidgets('inner portrait: the bar is still below the panes', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoInnerPortrait,
        kDuoInnerPortraitPadding,
        masterMinWidth: 280,
        detailMinWidth: 300,
      );

      final Rect bar = tester.getRect(find.byType(NavigationBar));
      final Rect master = tester.getRect(find.byType(DemoListScreen));
      expect(bar.bottom, kDuoInnerPortrait.height);
      expect(master.bottom, lessThanOrEqualTo(bar.top));
    });

    testWidgets('inner landscape: the rail leads, as everywhere else', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoInnerLandscape, kDuoInnerLandscapePadding);

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0);
      // No column to share and no inset at the top, so the rail only clears
      // the rounded corner.
      expect(rail.top, SystemBarMetrics.measured.cornerClearance);
      expect(split(tester), isTrue);
      // Rail, then master, then detail.
      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      expect(master.left, greaterThanOrEqualTo(rail.right));
      expect(detail.left, greaterThan(master.left));
    });

    testWidgets('inner landscape: the detail bleeds under the far bar', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoInnerLandscape, kDuoInnerLandscapePadding);

      // The card reaches the window edge; the screen inside insets itself.
      expect(
        tester.getRect(find.byType(DemoDetailScreen)).right,
        kDuoInnerLandscape.width,
      );
      expect(
        MediaQuery.paddingOf(
          tester.element(find.byType(DemoDetailScreen)),
        ).right,
        statusBar,
      );
    });

    testWidgets('the rail never sees the inset on its own edge', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoOuterPortrait, kDuoOuterPortraitPadding);

      // Left intact, `NavigationRail`'s own `SafeArea` would eat most of the
      // declared width and squeeze the destinations into what is left.
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(NavigationRail))).right,
        0,
      );
      expect(tester.getSize(find.byType(NavigationRail)).width, 80);
    });
  });

  group('a detail keeps the width it promises', () {
    // The pane arithmetic still has to subtract an inset nothing covers. On
    // Duo the rail covers the only large one, so this exercises the general
    // path: a window whose trailing inset is too small to be a system bar.
    const EdgeInsets smallTrailing = EdgeInsets.only(right: 40, bottom: 20);
    const Size window = Size(1000, 700);

    testWidgets('dragged to the stop, it is still its minimum', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, window, padding: smallTrailing);
      final PaneSplitController split = PaneSplitController();
      addTearDown(split.dispose);
      final DemoHarness h = DemoHarness(paneSplit: split);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      // The rail is on the left here, so the trailing 40 is the detail's to
      // bleed under.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.getRect(find.byType(NavigationRail)).left, 0);

      await tester.drag(
        find.byKey(AdaptiveShell.paneSplitHandleKey),
        const Offset(2000, 0),
      );
      await tester.pumpAndSettle();

      final Finder screen = find.byType(DemoDetailScreen);
      final double usable =
          tester.getSize(screen).width -
          MediaQuery.of(tester.element(screen)).padding.horizontal;
      expect(usable, greaterThanOrEqualTo(360));
      // And the card itself still reaches the window edge.
      expect(tester.getRect(screen).right, window.width);
    });

    testWidgets('a pane margin is not counted twice', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, window, padding: smallTrailing);
      final DemoHarness h = DemoHarness(
        panes: const PaneDecoration(margin: EdgeInsets.all(12), gap: 8),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      // The card stops 12 short of the edge, so 28 of the inset is left over
      // it — not the whole 40.
      expect(
        MediaQuery.of(
          tester.element(find.byType(DemoDetailScreen)),
        ).padding.right,
        28,
      );
    });
  });

  group('which end of the column the camera is at', () {
    test('upright, at the top', () {
      expect(
        defaultSystemBarEnd(kDuoOuterPortrait, ChromePlacement.right),
        SystemBarEnd.top,
      );
    });

    test('turned with the column on the left, still at the top', () {
      expect(
        defaultSystemBarEnd(kDuoOuterLandscape, ChromePlacement.left),
        SystemBarEnd.top,
      );
    });

    test('turned with the column on the right, at the bottom', () {
      expect(
        defaultSystemBarEnd(kDuoOuterLandscape, ChromePlacement.right),
        SystemBarEnd.bottom,
      );
    });
  });

  // The end only matters where the rail shares its edge with a system bar.
  // Everywhere else the rail spans the window below the top inset, as before.
  group('no system bar on the rail\'s edge, nothing moves', () {
    Future<Rect> railIn(
      WidgetTester tester,
      Size size,
      EdgeInsets padding,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, size, padding: padding);
      final DemoHarness h = DemoHarness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      return tester.getRect(find.byType(NavigationRail));
    }

    final Map<String, (Size, EdgeInsets)> windows =
        <String, (Size, EdgeInsets)>{
          'iPad in landscape': (
            const Size(1180, 820),
            const EdgeInsets.only(top: 24, bottom: 20),
          ),
          'Android phone in landscape, buttons on the right': (
            const Size(800, 360),
            const EdgeInsets.only(top: 24, right: 48),
          ),
          'Android tablet in landscape': (
            const Size(1280, 800),
            const EdgeInsets.only(top: 24, bottom: 48),
          ),
          'desktop window': (const Size(1200, 800), EdgeInsets.zero),
          'iPhone in landscape, notch on the left': (
            const Size(852, 393),
            const EdgeInsets.only(left: 59, right: 59, bottom: 21),
          ),
        };
    for (final MapEntry<String, (Size, EdgeInsets)> w in windows.entries) {
      testWidgets(w.key, (WidgetTester tester) async {
        final (Size size, EdgeInsets padding) = w.value;
        final Rect rail = await railIn(tester, size, padding);
        expect(rail.top, padding.top);
        expect(rail.bottom, size.height);
      });
    }
  });
}
