import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `MasterDetailConfig.alignToWindowCenter`.
void main() {
  const double gutter = 8;
  const double gap = 8;

  final PaneDecoration cards = PaneDecoration(
    margin: const EdgeInsets.all(gutter),
    gap: gap,
    radius: BorderRadius.circular(12),
  );
  const RailDecoration railCards = RailDecoration(
    margin: EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    dividerWidth: 0,
  );

  Future<DemoHarness> pump(
    WidgetTester tester,
    Size size, {
    EdgeInsets padding = EdgeInsets.zero,
    bool alignToWindowCenter = true,
    PaneDecoration panes = PaneDecoration.none,
    RailDecoration rail = RailDecoration.none,
    double masterMinWidth = 320,
    double detailMinWidth = 360,
    PaneSplitController? split,
    FoldLocator? foldLocator,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, size, padding: padding);
    final DemoHarness h = DemoHarness(
      alignToWindowCenter: alignToWindowCenter,
      panes: panes,
      rail: rail,
      masterMinWidth: masterMinWidth,
      detailMinWidth: detailMinWidth,
      paneSplit: split,
      foldLocator: foldLocator,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return h;
  }

  Rect master(WidgetTester tester) =>
      tester.getRect(find.byType(DemoListScreen));
  Rect detail(WidgetTester tester) =>
      tester.getRect(find.byType(DemoDetailScreen));

  for (final (String name, PaneDecoration panes, RailDecoration rail, double g)
      in <(String, PaneDecoration, RailDecoration, double)>[
        ('flush', PaneDecoration.none, RailDecoration.none, 0),
        ('cards with a gap', cards, railCards, gap),
      ]) {
    testWidgets('rail on the left, $name: the boundary is on the centre', (
      WidgetTester tester,
    ) async {
      await pump(tester, kWide, panes: panes, rail: rail);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(master(tester).right, closeTo(kWide.width / 2 - g / 2, 0.5));
      expect(detail(tester).left, closeTo(kWide.width / 2 + g / 2, 0.5));
    });

    // iPhone Duo inside, portrait: a bar below and no rail, so nothing comes
    // off the left and the master gets exactly half.
    testWidgets('bar below, $name: the boundary is on the centre', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoInnerPortrait,
        padding: kDuoInnerPortraitPadding,
        panes: panes,
        rail: rail,
        masterMinWidth: 270,
        detailMinWidth: 270,
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      final double centre = kDuoInnerPortrait.width / 2;
      expect(master(tester).right, closeTo(centre - g / 2, 0.5));
      expect(detail(tester).left, closeTo(centre + g / 2, 0.5));
    });
  }

  // The rail takes 81 out of the master's half of a 900 window: the centre is
  // 369 into the pane area, which a 400 minimum does not allow.
  testWidgets('the master minimum wins over the centre', (
    WidgetTester tester,
  ) async {
    await pump(tester, const Size(900, 900), masterMinWidth: 400);

    expect(master(tester).width, 400);
    expect(master(tester).right, greaterThan(450));
  });

  testWidgets('a dragged width wins over the centre', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pump(tester, kWide, split: split);
    expect(master(tester).right, closeTo(kWide.width / 2, 0.5));

    // The first drag starts from the centre, not from `paneRatio`.
    await tester.drag(
      find.byKey(AdaptiveShell.paneSplitHandleKey),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(master(tester).right, closeTo(kWide.width / 2 + 60, 0.5));
  });

  testWidgets('a restored width wins over the centre', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController(
      initial: <Object, double>{'staff': 0.6},
    );
    addTearDown(split.dispose);
    await pump(tester, kWide, split: split);

    final double area = kWide.width - kDefaultRailWidth - 1;
    expect(master(tester).width, closeTo(area * 0.6, 0.5));
  });

  testWidgets('a fold wins over the centre', (WidgetTester tester) async {
    await pump(
      tester,
      kWide,
      foldLocator: (Size window, EdgeInsets padding) =>
          Rect.fromLTRB(700, 0, 700, window.height),
    );

    expect(master(tester).right, closeTo(700, 0.5));
  });

  // The example's People branch: 270 + 270 on the Duo.
  testWidgets('Duo inside, portrait: the divider travels both ways', (
    WidgetTester tester,
  ) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    await pump(
      tester,
      kDuoInnerPortrait,
      padding: kDuoInnerPortraitPadding,
      masterMinWidth: 270,
      detailMinWidth: 270,
      split: split,
    );
    expect(master(tester).width, 669 / 2);

    Future<void> dragBy(double dx) async {
      await tester.drag(
        find.byKey(AdaptiveShell.paneSplitHandleKey),
        Offset(dx, 0),
      );
      await tester.pumpAndSettle();
    }

    await dragBy(-200);
    expect(master(tester).width, closeTo(270, 0.01));
    await dragBy(400);
    expect(detail(tester).width, closeTo(270, 0.01));
    expect(master(tester).width, closeTo(399, 0.01));
  });

  testWidgets('Duo outside: still a stack at 270 + 270', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      kDuoOuterPortrait,
      padding: kDuoOuterPortraitPadding,
      masterMinWidth: 270,
      detailMinWidth: 270,
    );

    // A stack: the detail covers the list instead of standing beside it.
    expect(detail(tester).overlaps(master(tester)), isTrue);
  });

  testWidgets('off: paneRatio as before', (WidgetTester tester) async {
    await pump(tester, kWide, alignToWindowCenter: false);

    final double area = kWide.width - kDefaultRailWidth - 1;
    expect(master(tester).width, closeTo(area * 0.35, 0.5));
  });
}
