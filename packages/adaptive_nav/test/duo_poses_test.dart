import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// One iPhone Duo posture as measured on the simulator (Xcode 27.1, iOS
/// 27.1): the window, its `MediaQuery.padding`, the display it is on, and
/// what adaptive_nav_ios reports for it — the bar's side from
/// `UITraitCollection.verticalBarEdge`, the status area and the active folds
/// from `UIView.reservedRegions`.
typedef _Pose = ({
  String name,
  Size window,
  EdgeInsets padding,
  Size display,
  SystemGeometry system,
});

/// The postures by their number in the README's iPhone Duo table.
const List<_Pose> _poses = <_Pose>[
  (
    name: '1, outer portrait',
    window: kDuoOuterPortrait,
    padding: kDuoOuterPortraitPadding,
    display: kDuoOuterPortrait,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(382, 0, 466, 170),
    ),
  ),
  (
    name: '2, outer landscape, turned left',
    window: kDuoOuterLandscape,
    padding: kDuoOuterLandscapePadding,
    display: kDuoOuterLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.left,
      statusArea: Rect.fromLTRB(0, 0, 84, 82),
    ),
  ),
  (
    name: '3, outer landscape, turned right',
    window: kDuoOuterLandscape,
    padding: kDuoOuterLandscapeRightPadding,
    display: kDuoOuterLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(594, 384, 678, 466),
    ),
  ),
  (
    name: '4, inner portrait, flat',
    window: kDuoInnerPortrait,
    padding: kDuoInnerPortraitPadding,
    display: kDuoInnerPortrait,
    system: SystemGeometry(statusArea: Rect.fromLTRB(535, 0, 669, 82)),
  ),
  (
    name: '5, inner landscape, flat',
    window: kDuoInnerLandscape,
    padding: kDuoInnerLandscapePadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(867, 0, 951, 120),
    ),
  ),
  (
    name: '6, inner landscape, half open',
    window: kDuoInnerLandscape,
    padding: kDuoInnerLandscapePadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(867, 0, 951, 120),
      folds: <Rect>[Rect.fromLTRB(455.5, 0, 495.5, 669)],
    ),
  ),
  (
    name: '7, inner portrait, half open',
    window: kDuoInnerPortrait,
    padding: kDuoInnerPortraitPadding,
    display: kDuoInnerPortrait,
    system: SystemGeometry(
      statusArea: Rect.fromLTRB(535, 0, 669, 82),
      folds: <Rect>[Rect.fromLTRB(0, 455.5, 669, 495.5)],
    ),
  ),
  (
    name: '8, Split View, left half',
    window: kDuoSplit,
    padding: kDuoSplitLeftPadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(verticalBar: ChromePlacement.left),
  ),
  (
    name: '9, Split View, right half',
    window: kDuoSplit,
    padding: kDuoSplitRightPadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(385, 0, 469, 120),
    ),
  ),
];

_Pose _pose(int number) => _poses[number - 1];

/// What a posture should come out as.
typedef _Expected = ({
  ChromePlacement chrome,
  // How far the rail's destinations are kept from the column's end, and
  // which end; `null` for a bar.
  double? reserve,
  SystemBarEnd end,
  double paneArea,
  bool twoPanes,
  // Where the panes meet when a fold takes the boundary, and what each one
  // keeps clear of it on that side; `null` when the width decides.
  ({double seam, double inset})? fold,
});

/// iPhone Duo: the nine postures measured on the simulator, laid out the way
/// Apple's guidance asks — once from `MediaQuery` alone, the fallback, and
/// once with what adaptive_nav_ios reports.
///
/// The chrome joins the system's own column wherever there is one, on both
/// displays; the inner display in portrait has horizontal bars. See
/// `chrome_layout_test.dart` for the rule and for the devices it may not
/// touch. The rail region is 81 (80 plus its divider); joining the 84-point
/// column it is held 8 off the edge to share the glyphs' axis, which makes
/// the column 89.
void main() {
  const double railRegion = kDefaultRailWidth + kDefaultRailDividerWidth;
  final double column =
      railRegion + SystemBarMetrics.measured.edgeGap(kDefaultRailWidth); // 89

  // Small enough that two panes fit beside a bar on the inner display in
  // portrait, as in the example app; the defaults elsewhere.
  ({double master, double detail}) minimums(_Pose pose) =>
      pose.window == kDuoInnerPortrait
      ? (master: 280, detail: 300)
      : (master: 320, detail: 360);

  Future<DemoHarness> pump(
    WidgetTester tester,
    _Pose pose, {
    bool withSystem = false,
    SystemBarMetrics systemBar = SystemBarMetrics.measured,
    PaneDecoration panes = PaneDecoration.none,
    ChromeLayout chromeLayout = defaultChromeLayout,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, pose.window, padding: pose.padding, display: pose.display);
    final DemoHarness h = DemoHarness(
      masterMinWidth: minimums(pose).master,
      detailMinWidth: minimums(pose).detail,
      system: withSystem ? pose.system : null,
      systemBar: systemBar,
      panes: panes,
      chromeLayout: chromeLayout,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return h;
  }

  /// The rail's column: the system's, with its tabs, wherever there is
  /// one, and the Material rail anywhere else.
  Finder railColumn() {
    final Finder column = find.byKey(AdaptiveShell.systemColumnKey);
    return column.evaluate().isNotEmpty ? column : find.byType(NavigationRail);
  }

  bool split(WidgetTester tester) => !tester
      .getRect(find.byType(DemoDetailScreen))
      .overlaps(tester.getRect(find.byType(DemoListScreen)));

  void check(WidgetTester tester, _Pose pose, _Expected expected) {
    final Size window = pose.window;
    if (expected.chrome == ChromePlacement.bottom) {
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    } else {
      expect(find.byType(NavigationBar), findsNothing);
      final Rect rail = tester.getRect(railColumn());
      expect(rail.width, kDefaultRailWidth);
      final double reserve = expected.reserve!;
      switch (expected.end) {
        case SystemBarEnd.top:
          expect(rail.top, reserve, reason: 'reserve at the top');
          expect(rail.bottom, window.height);
        case SystemBarEnd.bottom:
          // The home indicator's 34 is inside the column; the reserve is
          // measured from the window's edge. At the top, with nothing of the
          // system's there, the column keeps its own inset
          // (`system_column_test.dart`).
          expect(rail.top, 0);
          expect(
            rail.bottom,
            window.height - (reserve - pose.padding.bottom),
            reason: 'reserve at the bottom',
          );
      }
      if (expected.chrome == ChromePlacement.right) {
        expect(rail.right, lessThanOrEqualTo(window.width));
        expect(rail.left, greaterThan(window.width / 2));
      } else {
        expect(rail.left, greaterThanOrEqualTo(0));
        expect(rail.right, lessThan(window.width / 2));
      }
    }
    expect(split(tester), expected.twoPanes);
    final Rect master = tester.getRect(find.byType(DemoListScreen));
    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
    final ({double seam, double inset})? fold = expected.fold;
    if (fold != null) {
      expect(master.right, fold.seam, reason: 'the master reaches the hinge');
      expect(detail.left, fold.seam, reason: 'and so does the detail');
      // The crease is an inset, the way an underlap is: the screens see it
      // as padding and keep their content off it.
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(DemoListScreen))).right,
        fold.inset,
      );
      expect(
        MediaQuery.paddingOf(
          tester.element(find.byType(DemoDetailScreen)),
        ).left,
        fold.inset,
      );
    } else if (expected.twoPanes) {
      // The width decided: the master at its minimum, as the ratio of these
      // pane areas falls short of it.
      expect(master.width, minimums(pose).master);
    }
  }

  double paneArea(_Pose pose, {required bool withSystem}) =>
      PaneMetrics.paneAreaWidth(
        window: pose.window.width,
        padding: pose.padding,
        placement: defaultChromeLayout(
          pose.window,
          pose.padding,
          withSystem ? pose.system : null,
        ),
        railWidth: kDefaultRailWidth,
        panes: PaneDecoration.none,
      );

  // Shared by both groups: the fallback and the provider agree on all of
  // these but 6, 7 and 8, which have a group of their own below.
  final Map<int, _Expected> agreed = <int, _Expected>{
    1: (
      chrome: ChromePlacement.right,
      reserve: 170,
      end: SystemBarEnd.top,
      paneArea: kDuoOuterPortrait.width - column, // 377
      twoPanes: false,
      fold: null,
    ),
    2: (
      chrome: ChromePlacement.left,
      reserve: 82,
      end: SystemBarEnd.top,
      paneArea: kDuoOuterLandscape.width - column, // 589
      twoPanes: false,
      fold: null,
    ),
    3: (
      chrome: ChromePlacement.right,
      reserve: 82,
      end: SystemBarEnd.bottom,
      paneArea: kDuoOuterLandscape.width - column, // 589
      twoPanes: false,
      fold: null,
    ),
    4: (
      chrome: ChromePlacement.bottom,
      reserve: null,
      end: SystemBarEnd.top,
      paneArea: kDuoInnerPortrait.width, // 669
      twoPanes: true,
      fold: null,
    ),
    5: (
      chrome: ChromePlacement.right,
      reserve: 120,
      end: SystemBarEnd.top,
      paneArea: kDuoInnerLandscape.width - column, // 862
      twoPanes: true,
      fold: null,
    ),
    9: (
      chrome: ChromePlacement.right,
      reserve: 120,
      end: SystemBarEnd.top,
      paneArea: kDuoSplit.width - column, // 380
      twoPanes: false,
      fold: null,
    ),
  };

  group('from MediaQuery alone', () {
    final Map<int, _Expected> expected = <int, _Expected>{
      ...agreed,
      // Half open, but nothing says so: the width decides.
      6: agreed[5]!,
      7: agreed[4]!,
      // The fallback's known limit: no side inset, so a narrow window with a
      // bottom bar, though the system wants the bar on the left edge.
      8: (
        chrome: ChromePlacement.bottom,
        reserve: null,
        end: SystemBarEnd.top,
        paneArea: kDuoSplit.width,
        twoPanes: false,
        fold: null,
      ),
    };
    for (final MapEntry<int, _Expected> e in expected.entries) {
      final _Pose pose = _pose(e.key);
      testWidgets(pose.name, (WidgetTester tester) async {
        expect(paneArea(pose, withSystem: false), e.value.paneArea);
        await pump(tester, pose);
        check(tester, pose, e.value);
      });
    }
  });

  group('with the system\'s geometry', () {
    final Map<int, _Expected> expected = <int, _Expected>{
      ...agreed,
      // The fold is active and both panes clear their minimums around it.
      6: (
        chrome: ChromePlacement.right,
        reserve: 120,
        end: SystemBarEnd.top,
        paneArea: kDuoInnerLandscape.width - column,
        twoPanes: true,
        // 455.5…495.5 reported: the middle of it, 20 either side.
        fold: (seam: 475.5, inset: 20),
      ),
      // Active, but horizontal: the panes side by side have nothing to align
      // to it.
      7: agreed[4]!,
      // The left edge, as the system asks; a rail of its own, no column to
      // share, kept out of the rounded corner.
      8: (
        chrome: ChromePlacement.left,
        reserve: SystemBarMetrics.measured.cornerClearance,
        end: SystemBarEnd.top,
        paneArea: kDuoSplit.width - railRegion, // 388
        twoPanes: false,
        fold: null,
      ),
    };
    for (final MapEntry<int, _Expected> e in expected.entries) {
      final _Pose pose = _pose(e.key);
      testWidgets(pose.name, (WidgetTester tester) async {
        expect(paneArea(pose, withSystem: true), e.value.paneArea);
        await pump(tester, pose, withSystem: true);
        check(tester, pose, e.value);
      });
    }

    // Numbers the metrics could not have produced, so the reserve can only
    // have come from the status area.
    const SystemBarMetrics wrong = SystemBarMetrics(
      reserve: 1,
      landscapeReserve: 1,
      innerReserve: 1,
    );
    for (final int number in <int>[1, 3, 5, 9]) {
      final _Pose pose = _pose(number);
      testWidgets('${pose.name}: the status area decides, not the metrics', (
        WidgetTester tester,
      ) async {
        await pump(tester, pose, withSystem: true, systemBar: wrong);
        check(tester, pose, agreed[number]!);
      });
    }

    testWidgets('SystemBarMetrics.none ignores the status area too', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _pose(1),
        withSystem: true,
        systemBar: SystemBarMetrics.none,
      );

      final Rect rail = tester.getRect(railColumn());
      expect(rail.top, 0);
      expect(rail.right, kDuoOuterPortrait.width);
    });

    testWidgets('6: the divider cannot be dragged off the fold', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      final _Pose pose = _pose(6);
      setPose(
        tester,
        pose.window,
        padding: pose.padding,
        display: pose.display,
      );
      final PaneSplitController split = PaneSplitController();
      addTearDown(split.dispose);
      final DemoHarness h = DemoHarness(system: pose.system, paneSplit: split);
      await tester.pumpWidget(h.app());
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
      expect(tester.getRect(find.byType(DemoListScreen)).right, 475.5);
    });
  });

  group('the inner display in landscape, rail on the right', () {
    testWidgets('the rail is in the system\'s column, on its axis', (
      WidgetTester tester,
    ) async {
      await pump(tester, _pose(5));

      final Rect rail = tester.getRect(railColumn());
      expect(rail.center.dx, kDuoInnerLandscape.width - 48);
      // Master on the left, from the window edge; the detail against the
      // column.
      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      expect(master.left, 0);
      expect(detail.right, kDuoInnerLandscape.width - column);
      // The rail has the inset on its side; the detail has nothing to clear.
      expect(
        MediaQuery.paddingOf(
          tester.element(find.byType(DemoDetailScreen)),
        ).right,
        0,
      );
    });

    testWidgets('pane margins come off the same 862', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _pose(5),
        panes: const PaneDecoration(margin: EdgeInsets.all(12), gap: 8),
      );

      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      expect(master.left, 12);
      expect(detail.right, kDuoInnerLandscape.width - column - 12);
      expect(detail.left - master.right, 8);
    });

    testWidgets('the fold in pane coordinates, with pane margins', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _pose(6),
        withSystem: true,
        // On the left only: 12 off the right as well would leave the detail
        // 354.5 past the fold, under its 360, and the width would decide.
        panes: const PaneDecoration(
          margin: EdgeInsets.fromLTRB(12, 12, 0, 12),
          gap: 8,
        ),
      );

      // The cards' 8 of gap is split evenly around the hinge, in window
      // coordinates wherever the pane area starts, and the rest of the
      // crease is each pane's inset: the content still ends at 455.5 and
      // starts at 495.5.
      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      expect(master.right, 471.5);
      expect(detail.left, 479.5);
      expect((master.right + detail.left) / 2, 475.5);
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(DemoListScreen))).right,
        16,
      );
      expect(
        MediaQuery.paddingOf(
          tester.element(find.byType(DemoDetailScreen)),
        ).left,
        16,
      );
    });

    // A custom layout can still put the rail across the window from the
    // bar, as the default used to. No column to share and no inset at the
    // top: the rail only clears the rounded corner, and the detail bleeds
    // under the far bar.
    testWidgets('a layout that keeps the rail on the left', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _pose(5),
        chromeLayout: (Size w, EdgeInsets p, SystemGeometry? s) =>
            ChromePlacement.left,
      );

      final Rect rail = tester.getRect(railColumn());
      expect(rail.left, 0);
      expect(rail.top, SystemBarMetrics.measured.cornerClearance);
      final Finder detail = find.byType(DemoDetailScreen);
      expect(tester.getRect(detail).right, kDuoInnerLandscape.width);
      expect(MediaQuery.paddingOf(tester.element(detail)).right, 84);
    });
  });

  group('the outer display', () {
    testWidgets('a flush rail fills its column to the edge', (
      WidgetTester tester,
    ) async {
      await pump(tester, _pose(1));

      final Rect rail = tester.getRect(railColumn());
      expect(rail.center.dx, kDuoOuterPortrait.width - 48);
      final BuildContext railContext = tester.element(railColumn());
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

    testWidgets('the end is configurable', (WidgetTester tester) async {
      await pump(
        tester,
        _pose(3),
        systemBar: SystemBarMetrics(end: (_, _, _) => SystemBarEnd.top),
      );

      expect(
        tester.getRect(railColumn()).top,
        SystemBarMetrics.measured.landscapeReserve,
      );
    });

    testWidgets('the reserve is configurable, and zero keeps the top', (
      WidgetTester tester,
    ) async {
      await pump(tester, _pose(1), systemBar: SystemBarMetrics.none);

      final Rect rail = tester.getRect(railColumn());
      expect(rail.top, 0);
      expect(rail.right, kDuoOuterPortrait.width);
    });

    testWidgets('the rail never sees the inset on its own edge', (
      WidgetTester tester,
    ) async {
      await pump(tester, _pose(1));

      // Left intact, `NavigationRail`'s own `SafeArea` would eat most of the
      // declared width and squeeze the destinations into what is left.
      expect(MediaQuery.paddingOf(tester.element(railColumn())).right, 0);
      expect(tester.getSize(railColumn()).width, 80);
    });
  });

  group('the inner display in portrait', () {
    // The cards run up under the status bar and the screens inside reserve
    // what is left of it, so the 82-point inset costs no height: leaving the
    // whole of it to the shell would put a band that deep of bare canvas above
    // the panes, and leaving the whole of it to the screens would have each
    // `AppBar` reserve it below the card's margin and sit that much too low.
    testWidgets('the status bar is not wasted twice', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _pose(4),
        panes: const PaneDecoration(margin: EdgeInsets.all(12), gap: 8),
      );

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

    // The bar already clears the home indicator, so the panes get no bottom.
    testWidgets('the home indicator is not cleared twice', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _pose(4),
        panes: const PaneDecoration(margin: EdgeInsets.all(12), gap: 8),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(split(tester), isTrue);
      final Finder master = find.byType(DemoListScreen);
      final Finder detail = find.byType(DemoDetailScreen);
      expect(MediaQuery.paddingOf(tester.element(master)).bottom, 0);
      expect(MediaQuery.paddingOf(tester.element(detail)).bottom, 0);
    });

    testWidgets('the bar is still below the panes', (
      WidgetTester tester,
    ) async {
      await pump(tester, _pose(4));

      final Rect bar = tester.getRect(find.byType(NavigationBar));
      final Rect master = tester.getRect(find.byType(DemoListScreen));
      expect(bar.bottom, kDuoInnerPortrait.height);
      expect(master.bottom, lessThanOrEqualTo(bar.top));
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
      expect(railColumn(), findsOneWidget);
      expect(tester.getRect(railColumn()).left, 0);

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

  group('which end of the column the status area is at, without one', () {
    test('outer, upright: the top', () {
      expect(
        defaultSystemBarEnd(
          kDuoOuterPortrait,
          ChromePlacement.right,
          kDuoOuterPortrait,
        ),
        SystemBarEnd.top,
      );
    });

    test('outer, turned with the column on the left: still the top', () {
      expect(
        defaultSystemBarEnd(
          kDuoOuterLandscape,
          ChromePlacement.left,
          kDuoOuterLandscape,
        ),
        SystemBarEnd.top,
      );
    });

    test('outer, turned with the column on the right: the bottom', () {
      expect(
        defaultSystemBarEnd(
          kDuoOuterLandscape,
          ChromePlacement.right,
          kDuoOuterLandscape,
        ),
        SystemBarEnd.bottom,
      );
    });

    // Postures 5 and 6 are the two landscape orientations of the inner
    // display, and the status area is at the top in both.
    test('inner, landscape, column on the right: the top', () {
      expect(
        defaultSystemBarEnd(
          kDuoInnerLandscape,
          ChromePlacement.right,
          kDuoInnerLandscape,
        ),
        SystemBarEnd.top,
      );
    });

    test('inner, Split View on the right: the top', () {
      expect(
        defaultSystemBarEnd(
          kDuoSplit,
          ChromePlacement.right,
          kDuoInnerLandscape,
        ),
        SystemBarEnd.top,
      );
    });
  });

  group('which reserve, without a status area', () {
    const SystemBarMetrics m = SystemBarMetrics.measured;

    test('the display decides, not the window', () {
      expect(m.reserveFor(kDuoOuterPortrait, outerDisplay: true), 170);
      expect(m.reserveFor(kDuoOuterLandscape, outerDisplay: true), 82);
      expect(m.reserveFor(kDuoInnerLandscape, outerDisplay: false), 120);
      // Narrower than the outer display, but on the inner one.
      expect(m.reserveFor(kDuoSplit, outerDisplay: false), 120);
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
      return tester.getRect(railColumn());
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

  // The detail's toolbar, Close and Edit, in each posture with what
  // adaptive_nav_ios reports: vertical in the system's column beside the one
  // pane, or beside the detail of two on the inner display in landscape; a
  // header on the inner display in portrait, where the bars are horizontal.
  //
  // Twice: with the rail kept beside an open detail (iOS, DetailChrome.kept)
  // the column is status area, Close, Edit, rail; with the detail covering
  // it (the default) the rail's destinations are gone from a single pane's
  // column and the toolbar has it alone. Two panes are the same either way.
  for (final DetailChrome mode in DetailChrome.values) {
    final bool kept = mode == DetailChrome.kept;
    group('the detail\'s toolbar, ${mode.name}', () {
      final Map<int, ChromePlacement?> vertical = <int, ChromePlacement?>{
        1: ChromePlacement.right,
        2: ChromePlacement.left,
        3: ChromePlacement.right,
        4: null,
        5: ChromePlacement.right,
        6: ChromePlacement.right,
        7: null,
        // The rail was the column there: the left-hand window has no inset
        // of its own, so once the detail covers the rail the toolbar is a
        // header.
        8: kept ? ChromePlacement.left : null,
        9: ChromePlacement.right,
      };
      for (final MapEntry<int, ChromePlacement?> e in vertical.entries) {
        final _Pose pose = _pose(e.key);
        testWidgets(pose.name, (WidgetTester tester) async {
          addTearDown(tester.view.reset);
          setPose(
            tester,
            pose.window,
            padding: pose.padding,
            display: pose.display,
          );
          final DemoHarness h = DemoHarness(
            masterMinWidth: minimums(pose).master,
            detailMinWidth: minimums(pose).detail,
            system: pose.system,
            wrapPage: toolbarScreens(),
            detailChrome: mode,
            platform: kept ? TargetPlatform.iOS : null,
          );
          await tester.pumpWidget(h.app());
          h.delegate.push(const DemoDetail(1));
          await tester.pumpAndSettle();

          final Finder column = find.byKey(AdaptiveShell.paneToolbarKey);
          final Finder header = find.byType(AppBar);
          final ChromePlacement? edge = e.value;
          final Element detail = tester.element(find.text('Detail 1 body'));
          expect(PaneBarScope.of(detail), PaneBar(verticalEdge: edge));
          // The master keeps its header wherever there is one beside the
          // detail.
          Rect screen(String body) => tester.getRect(
            find.ancestor(
              of: find.text(body),
              matching: find.byType(ToolbarScreen),
            ),
          );
          final bool twoPanes = !screen(
            'Detail 1 body',
          ).overlaps(screen('List body'));
          if (twoPanes) {
            expect(
              PaneBarScope.of(
                tester.element(find.text('List body')),
              ).isVertical,
              isFalse,
            );
          }
          // Covered: where the system's column stays, the detail has the
          // single pane's area, beside the column rather than under it, and
          // the padding a pane has there. Where the rail was the column (8),
          // it covers the rail and has the whole window.
          final bool covered =
              !kept && !twoPanes && pose.system.verticalBar != null;
          if (covered && edge != null) {
            expect(screen('Detail 1 body'), screen('List body'));
            expect(screen('Detail 1 body').width, lessThan(pose.window.width));
            expect(
              MediaQuery.paddingOf(detail),
              MediaQuery.paddingOf(tester.element(find.text('List body'))),
            );
          } else if (covered) {
            expect(screen('Detail 1 body').width, pose.window.width);
            expect(MediaQuery.paddingOf(detail), pose.padding);
          }
          if (covered) {
            // In the system's column the tabs have gone, under the detail;
            // a rail of its own stays there. Either way, where they were the
            // tap is the detail's.
            final Finder tabs = find.byKey(AdaptiveShell.columnTabsKey);
            if (tabs.evaluate().isEmpty) {
              await tester.tap(find.byIcon(Icons.home), warnIfMissed: false);
            } else {
              expect(find.byIcon(Icons.home), findsNothing);
              await tester.tapAt(tester.getCenter(tabs));
            }
            await tester.pumpAndSettle();
            expect(h.delegate.state.activeBranch, 0);
          }
          if (edge == null) {
            expect(column, findsNothing);
            expect(
              find.descendant(of: header, matching: find.byIcon(Icons.edit)),
              findsOneWidget,
            );
            return;
          }
          final Rect close = tester.getRect(
            find.descendant(of: column, matching: find.byIcon(Icons.close)),
          );
          final Rect edit = tester.getRect(
            find.descendant(of: column, matching: find.byIcon(Icons.edit)),
          );
          // Navigation, then the pinned action, on one axis: the glyphs'
          // where the column is the system's, the rail's in any case.
          expect(edit.top, greaterThanOrEqualTo(close.bottom));
          expect(edit.center.dx, close.center.dx);
          if (covered) {
            expect(
              close.center.dx,
              edge == ChromePlacement.left
                  ? SystemBarMetrics.measured.axisFromEdge
                  : pose.window.width - SystemBarMetrics.measured.axisFromEdge,
            );
          }
          // Room for both: nothing went behind the column's menu.
          expect(
            find.descendant(
              of: column,
              matching: find.byKey(AdaptiveShell.railOverflowKey),
            ),
            covered ? findsNothing : anything,
          );
          if (!covered) {
            // The tabs below them, in the same column, on the same axis.
            final Rect tab = tester.getRect(
              find.byKey(AdaptiveShell.columnTabKey(0)),
            );
            expect(tab.top, greaterThanOrEqualTo(edit.bottom));
            expect(close.center.dx, tab.center.dx);
          }
          // The column's inset below the status area where it is at the top,
          // or below the window's edge; above the status area where it is at
          // the bottom.
          final double inset = SystemBarMetrics.measured.columnInset;
          final Rect? area = pose.system.statusArea;
          final double from = area != null && area.top == 0 ? area.bottom : 0;
          final double button =
              (kPaneToolbarItemExtent -
                  tester.getSize(find.byIcon(Icons.close)).height) /
              2;
          expect(close.top - button, from + inset);
          if (area != null && area.top > 0) {
            expect(edit.bottom, lessThanOrEqualTo(area.top));
          }
          expect(
            find.descendant(of: header, matching: find.byIcon(Icons.close)),
            findsNothing,
          );
        });
      }
    });
  }
}
