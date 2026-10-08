import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/pose.dart';
import '_harness/resize.dart';

/// `AdaptiveShellConfig.liftHeadersIntoStatusRow` on iPhone Duo's inner
/// display in portrait: a top inset of 20 instead of 82 centres a toolbar on
/// the glyphs 48 down, and the pane under the right 120 is told so.
void main() {
  const double lifted = 48 - kToolbarHeight / 2; // 20
  const double glyphs = 120;
  final double start = kDuoInnerPortrait.width - glyphs; // 549

  EdgeInsets paddingAt(WidgetTester tester, Finder finder) =>
      MediaQuery.paddingOf(tester.element(finder));

  double reserveAt(WidgetTester tester, Finder finder) =>
      StatusRowScope.trailingReserveOf(tester.element(finder));

  /// Both panes fit in 669 at these minimums, as in the example app.
  Future<DemoHarness> pump(
    WidgetTester tester, {
    Size size = kDuoInnerPortrait,
    EdgeInsets padding = kDuoInnerPortraitPadding,
    bool lift = true,
    TargetPlatform platform = TargetPlatform.iOS,
    bool withDetail = true,
    double masterMinWidth = 270,
    double detailMinWidth = 270,
    PaneDecoration panes = PaneDecoration.none,
    PaneSplitController? paneSplit,
    Widget Function(DemoRoute route, Widget screen)? wrapPage,
  }) => pumpPose(
    tester,
    DemoHarness(
      liftHeadersIntoStatusRow: lift,
      platform: platform,
      masterMinWidth: masterMinWidth,
      detailMinWidth: detailMinWidth,
      panes: panes,
      paneSplit: paneSplit,
      wrapPage: wrapPage,
    ),
    size,
    padding: padding,
    withDetail: withDetail,
  );

  final Finder master = find.byType(DemoListScreen);
  final Finder detail = find.byType(DemoDetailScreen);

  group('inner display, portrait', () {
    testWidgets('two panes: both lifted, only the detail is under the glyphs', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(paddingAt(tester, master).top, lifted);
      expect(paddingAt(tester, detail).top, lifted);
      expect(reserveAt(tester, master), 0);
      expect(reserveAt(tester, detail), glyphs);
      // The bottom is the bar's business and does not move.
      expect(
        tester.getRect(find.byType(NavigationBar)).bottom,
        kDuoInnerPortrait.height,
      );
    });

    testWidgets('the toolbar is centred on the glyphs\' line', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      final Rect bar = tester.getRect(
        find.descendant(of: detail, matching: find.byType(AppBar)),
      );
      expect(bar.top, 0);
      expect(bar.bottom, lifted + kToolbarHeight);
      expect((lifted + bar.bottom) / 2, 48);
    });

    testWidgets('an empty detail collapsed: the master is under the glyphs', (
      WidgetTester tester,
    ) async {
      await pump(tester, withDetail: false);

      expect(paddingAt(tester, master).top, lifted);
      expect(reserveAt(tester, master), glyphs);
    });

    testWidgets('a pane margin comes off the inset and off the reserve', (
      WidgetTester tester,
    ) async {
      const double gutter = 12;
      await pump(
        tester,
        panes: const PaneDecoration(margin: EdgeInsets.all(gutter), gap: 8),
      );

      // The card starts 12 down, so 8 of the 20 are left to its screen.
      expect(paddingAt(tester, master).top, lifted - gutter);
      expect(paddingAt(tester, detail).top, lifted - gutter);
      // And it stops 12 short of the right edge, under the glyphs.
      expect(reserveAt(tester, master), 0);
      expect(reserveAt(tester, detail), glyphs - gutter);
    });

    testWidgets('one pane: the tab is lifted and under the glyphs', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, withDetail: false);
      h.delegate.goBranch(1);
      await tester.pumpAndSettle();

      final Finder home = find.byType(DemoHomeScreen);
      expect(paddingAt(tester, home).top, lifted);
      expect(reserveAt(tester, home), glyphs);
    });

    testWidgets('one pane: a detail over the master is lifted too', (
      WidgetTester tester,
    ) async {
      // Too wide a minimum for two panes: the detail covers the window.
      await pump(tester, masterMinWidth: 400, detailMinWidth: 400);

      expect(tester.getRect(detail), Offset.zero & kDuoInnerPortrait);
      expect(paddingAt(tester, detail).top, lifted);
      expect(reserveAt(tester, detail), glyphs);
    });

    testWidgets('the drawer keeps the whole inset', (
      WidgetTester tester,
    ) async {
      await pump(tester, masterMinWidth: 400, detailMinWidth: 400);

      expect(
        MediaQuery.paddingOf(
          tester.element(find.byKey(AdaptiveShell.mastersStackKey)),
        ).top,
        lifted,
      );
      final ScaffoldState shell = tester.firstState<ScaffoldState>(
        find.ancestor(
          of: find.byKey(AdaptiveShell.mastersStackKey),
          matching: find.byType(Scaffold),
        ),
      );
      expect(MediaQuery.paddingOf(shell.context).top, 82);
    });

    testWidgets('dragging the divider into the glyphs moves the reserve', (
      WidgetTester tester,
    ) async {
      final PaneSplitController split = PaneSplitController();
      addTearDown(split.dispose);
      // A detail narrow enough to be dragged under the glyphs entirely.
      await pump(tester, detailMinWidth: 60, paneSplit: split);

      expect(reserveAt(tester, master), 0);
      expect(reserveAt(tester, detail), glyphs);

      final Offset handle = tester.getCenter(
        find.byKey(AdaptiveShell.paneSplitHandleKey),
      );
      await tester.drag(
        find.byKey(AdaptiveShell.paneSplitHandleKey),
        Offset(kDuoInnerPortrait.width - handle.dx, 0),
      );
      await tester.pumpAndSettle();

      // At its minimum the detail starts at 609, inside the glyphs: the
      // master's end is now under them as well.
      final double boundary = tester.getRect(detail).left;
      expect(boundary, kDuoInnerPortrait.width - 60);
      expect(reserveAt(tester, master), boundary - start);
      expect(reserveAt(tester, detail), 60);

      await tester.drag(
        find.byKey(AdaptiveShell.paneSplitHandleKey),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(detail).left, lessThan(start));
      expect(reserveAt(tester, master), 0);
      expect(reserveAt(tester, detail), glyphs);
    });

    // A `Scaffold` scrolls to the top on a status bar tap only if a hit test
    // at the window's origin finds its status bar slot, 20 deep when lifted.
    testWidgets('a status bar tap still scrolls the master to the top', (
      WidgetTester tester,
    ) async {
      const Key scrolling = ValueKey<String>('scrolling master');
      await pump(
        tester,
        wrapPage: (DemoRoute route, Widget screen) => route is DemoList
            ? Scaffold(
                key: scrolling,
                appBar: AppBar(title: const Text('List')),
                body: ListView.builder(
                  primary: true,
                  itemCount: 100,
                  itemBuilder: (BuildContext _, int i) =>
                      SizedBox(height: 50, child: Text('row $i')),
                ),
              )
            : screen,
      );
      final Finder list = find.descendant(
        of: find.byKey(scrolling),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final ScrollPosition position = tester
          .state<ScrollableState>(list)
          .position;
      expect(position.pixels, greaterThan(0));
      expect(paddingAt(tester, find.byKey(scrolling)).top, lifted);

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.statusBar.name,
        SystemChannels.statusBar.codec.encodeMethodCall(
          const MethodCall('handleScrollToTop'),
        ),
        (ByteData? _) {},
      );
      await tester.pumpAndSettle();

      expect(position.pixels, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('option off, inner display in portrait', () {
    testWidgets('two panes', (WidgetTester tester) async {
      await pump(tester, lift: false);

      expect(paddingAt(tester, master).top, 82);
      expect(paddingAt(tester, detail).top, 82);
      expect(reserveAt(tester, master), 0);
      expect(reserveAt(tester, detail), 0);
    });

    testWidgets('one pane', (WidgetTester tester) async {
      await pump(tester, lift: false, masterMinWidth: 400);

      expect(paddingAt(tester, detail).top, 82);
      expect(reserveAt(tester, detail), 0);
    });
  });

  // Android puts the clock at the left end of the row, under the master's
  // header, so nothing is lifted.
  testWidgets('Android, inner display in portrait: unchanged', (
    WidgetTester tester,
  ) async {
    Future<List<Object>> seen({required bool lift}) async {
      await pump(tester, lift: lift, platform: TargetPlatform.android);
      return <Object>[
        paddingAt(tester, master),
        paddingAt(tester, detail),
        reserveAt(tester, master),
        reserveAt(tester, detail),
      ];
    }

    final List<Object> off = await seen(lift: false);
    await tester.pumpWidget(const SizedBox.shrink());
    final List<Object> on = await seen(lift: true);
    expect(on, off);
    expect(paddingAt(tester, master).top, 82);
    expect(paddingAt(tester, detail).top, 82);
    expect(reserveAt(tester, detail), 0);
  });

  // Each pose is pumped with the option and without; the screens must see the
  // same.
  group('option on, other poses unchanged', () {
    final Map<String, (Size, EdgeInsets)> poses = <String, (Size, EdgeInsets)>{
      'Duo inner, landscape': (kDuoInnerLandscape, kDuoInnerLandscapePadding),
      'Duo outer, portrait': (kDuoOuterPortrait, kDuoOuterPortraitPadding),
      'Duo outer, landscape': (kDuoOuterLandscape, kDuoOuterLandscapePadding),
      // Glyphs on both sides of the island; too narrow to count as a corner.
      'iPhone 18 Pro, portrait': (
        const Size(402, 874),
        const EdgeInsets.only(top: 62, bottom: 34),
      ),
      'iPhone 18 Pro, landscape': (
        const Size(874, 402),
        const EdgeInsets.only(left: 62, right: 62, bottom: 20),
      ),
      'iPad, portrait': (
        const Size(834, 1194),
        const EdgeInsets.only(top: 24, bottom: 20),
      ),
      'desktop window': (const Size(1200, 900), EdgeInsets.zero),
    };
    for (final MapEntry<String, (Size, EdgeInsets)> pose in poses.entries) {
      testWidgets(pose.key, (WidgetTester tester) async {
        final (Size size, EdgeInsets padding) = pose.value;
        Future<List<Object>> seen({required bool lift}) async {
          await pump(tester, size: size, padding: padding, lift: lift);
          return <Object>[
            paddingAt(tester, detail),
            tester.getRect(detail),
            reserveAt(tester, detail),
            if (master.evaluate().isNotEmpty) ...<Object>[
              paddingAt(tester, master),
              tester.getRect(master),
              reserveAt(tester, master),
            ],
          ];
        }

        final List<Object> off = await seen(lift: false);
        await tester.pumpWidget(const SizedBox.shrink());
        final List<Object> on = await seen(lift: true);
        expect(on, off);
        expect(reserveAt(tester, detail), 0);
      });
    }
  });

  test('the geometry is SystemBarMetrics\'s', () {
    const SystemBarMetrics measured = SystemBarMetrics.measured;
    expect(measured.statusRowAxis, 48);
    expect(measured.statusRowTrailing, glyphs);
    expect(measured.statusRowTop(kToolbarHeight), lifted);
    // Never into the rounded corner, however tall the header.
    expect(measured.statusRowTop(200), measured.cornerClearance);
  });

  testWidgets('outside a lifted pane the reserve is zero', (
    WidgetTester tester,
  ) async {
    late double reserve;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          reserve = StatusRowScope.trailingReserveOf(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(reserve, 0);
  });

  // The pose is read off `MediaQuery`, not the device, so custom metrics
  // apply to the same window.
  testWidgets('the numbers come from the config', (WidgetTester tester) async {
    await pumpPose(
      tester,
      DemoHarness(
        liftHeadersIntoStatusRow: true,
        platform: TargetPlatform.iOS,
        masterMinWidth: 270,
        detailMinWidth: 270,
        systemBar: const SystemBarMetrics(
          statusRowAxis: 52,
          statusRowTrailing: 90,
        ),
      ),
      kDuoInnerPortrait,
      padding: kDuoInnerPortraitPadding,
    );

    expect(paddingAt(tester, detail).top, 52 - kToolbarHeight / 2);
    expect(reserveAt(tester, detail), 90);
  });
}
