import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/pose.dart';
import '_harness/resize.dart';

/// The rail grows by a one-sided inset on its edge (Android's buttons, a
/// cutout); a landscape iPhone's symmetric insets leave it against the edge.
/// iPhone Duo's vertical bar is covered in `duo_poses_test.dart`.
void main() {
  // A one-sided inset on the rail's edge, as a notch reports it.
  const double notch = 59;

  void setLeftInset(WidgetTester tester, double left) {
    final FakeViewPadding inset = FakeViewPadding(left: left);
    tester.view.padding = inset;
    tester.view.viewPadding = inset;
  }

  Future<DemoHarness> pump(
    WidgetTester tester, {
    ShellChromeBuilder? railBuilder,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    setLeftInset(tester, notch);
    final DemoHarness h = DemoHarness(railBuilder: railBuilder);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('the default rail does not see the leading inset', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // Left intact, the `SafeArea` inside `NavigationRail` would eat 59 of the
    // 80 and lay the destinations out into the remaining 21.
    expect(
      MediaQuery.paddingOf(tester.element(find.byType(NavigationRail))).left,
      0,
    );
    expect(
      tester.getSize(find.byType(NavigationRail)).width,
      kDefaultRailWidth,
    );
  });

  testWidgets('a custom rail does not see it either', (
    WidgetTester tester,
  ) async {
    const Key custom = ValueKey<String>('custom-rail');
    await pump(
      tester,
      railBuilder:
          (BuildContext context, int branch, ValueChanged<int> select) =>
              const SizedBox.expand(key: custom),
    );

    expect(MediaQuery.paddingOf(tester.element(find.byKey(custom))).left, 0);
  });

  testWidgets('the rail grows by the inset, the panes move with it', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pump(tester);
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(NavigationRail)).left, notch);
    expect(
      tester.getRect(find.byType(DemoListScreen)).left,
      notch + kDefaultRailWidth + AdaptiveShell.dividerWidth,
    );
  });

  /// The first destination's icon, in window coordinates.
  Rect firstDestination(WidgetTester tester) => tester.getRect(
    find
        .descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Icon),
        )
        .first,
  );

  int destinations(WidgetTester tester) => tester
      .widget<NavigationRail>(find.byType(NavigationRail))
      .destinations
      .length;

  Future<void> pumpWithDetail(
    WidgetTester tester,
    Size window,
    EdgeInsets padding, {
    int extraBranches = 0,
  }) => pumpPose(
    tester,
    DemoHarness(extraBranches: extraBranches),
    window,
    padding: padding,
  );

  /// The rail's background boxes around [NavigationRail], in window
  /// coordinates.
  Iterable<Rect> railBackground(WidgetTester tester) {
    final Color rail = Theme.of(
      tester.element(find.byType(NavigationRail)),
    ).colorScheme.surface;
    return tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.byType(NavigationRail),
            matching: find.byType(ColoredBox),
          ),
        )
        .where((ColoredBox b) => b.color == rail)
        .map((ColoredBox b) => tester.getRect(find.byWidget(b)));
  }

  group('iPhone in landscape', () {
    // The Dynamic Island on one side, the same inset mirrored on the other.
    // Which side is not reported, so the rail stays against the edge.
    const Size window = Size(874, 402);
    const EdgeInsets padding = EdgeInsets.only(left: 62, right: 62, bottom: 21);

    testWidgets('the rail stays against the edge', (WidgetTester tester) async {
      await pumpWithDetail(tester, window, padding);

      expect(tester.getRect(find.byType(NavigationRail)).left, 0);
      expect(
        tester.getRect(find.byType(DemoListScreen)).left,
        kDefaultRailWidth + AdaptiveShell.dividerWidth,
      );
    });
  });

  group('Android in landscape', () {
    const Size window = Size(900, 412);

    testWidgets('buttons on the left: the destinations clear them', (
      WidgetTester tester,
    ) async {
      await pumpWithDetail(tester, window, const EdgeInsets.only(left: 48));

      expect(firstDestination(tester).left, greaterThanOrEqualTo(48));
      expect(tester.getRect(find.byType(NavigationRail)).left, 48);
      expect(
        tester.getRect(find.byType(DemoListScreen)).left,
        48 + kDefaultRailWidth + AdaptiveShell.dividerWidth,
      );
      final Finder detail = find.byType(DemoDetailScreen);
      expect(tester.getRect(detail).right, window.width);
      expect(MediaQuery.paddingOf(tester.element(detail)).right, 0);
    });

    testWidgets('buttons on the left: the background reaches the edge', (
      WidgetTester tester,
    ) async {
      await pumpWithDetail(tester, window, const EdgeInsets.only(left: 48));

      expect(
        railBackground(
          tester,
        ).any((Rect r) => r.left == 0 && r.right >= 48 + kDefaultRailWidth),
        isTrue,
      );
    });

    testWidgets('a camera cutout on the left: the destinations clear it', (
      WidgetTester tester,
    ) async {
      await pumpWithDetail(tester, window, const EdgeInsets.only(left: 32));

      expect(firstDestination(tester).left, greaterThanOrEqualTo(32));
      expect(
        tester.getRect(find.byType(DemoListScreen)).left,
        32 + kDefaultRailWidth + AdaptiveShell.dividerWidth,
      );
    });

    testWidgets('buttons on the right: the rail is against the edge', (
      WidgetTester tester,
    ) async {
      await pumpWithDetail(tester, window, const EdgeInsets.only(right: 48));

      expect(tester.getRect(find.byType(NavigationRail)).left, 0);
      expect(
        tester.getRect(find.byType(DemoListScreen)).left,
        kDefaultRailWidth + AdaptiveShell.dividerWidth,
      );
      // The detail bleeds under the buttons and its screen insets it away.
      final Finder detail = find.byType(DemoDetailScreen);
      expect(tester.getRect(detail).right, window.width);
      expect(MediaQuery.paddingOf(tester.element(detail)).right, 48);
    });

    // The rail's height is what its destinations are counted against, and
    // the shift adds width only.
    testWidgets('the overflow count is the same as without the buttons', (
      WidgetTester tester,
    ) async {
      await pumpWithDetail(tester, window, EdgeInsets.zero, extraBranches: 4);
      final int without = destinations(tester);
      await pumpWithDetail(
        tester,
        window,
        const EdgeInsets.only(left: 48),
        extraBranches: 4,
      );

      expect(destinations(tester), without);
      expect(find.byKey(AdaptiveShell.railOverflowKey), findsOneWidget);
    });
  });

  group('railCutoutInset', () {
    double inset(EdgeInsets padding, ChromePlacement placement) =>
        PaneMetrics.railCutoutInset(padding: padding, placement: placement);

    test('the wider side inset on the rail edge', () {
      expect(inset(const EdgeInsets.only(left: 48), ChromePlacement.left), 48);
      expect(
        inset(const EdgeInsets.only(right: 48), ChromePlacement.right),
        48,
      );
      expect(inset(const EdgeInsets.only(right: 48), ChromePlacement.left), 0);
    });

    test('symmetric insets are not a cutout, within a couple of pixels', () {
      expect(
        inset(const EdgeInsets.only(left: 62, right: 62), ChromePlacement.left),
        0,
      );
      expect(
        inset(const EdgeInsets.only(left: 62, right: 61), ChromePlacement.left),
        0,
      );
    });

    test('no side insets, as on an iPad or a desktop', () {
      expect(inset(EdgeInsets.zero, ChromePlacement.left), 0);
      expect(
        inset(const EdgeInsets.only(top: 24, bottom: 20), ChromePlacement.left),
        0,
      );
    });

    // The rail joins the system's column there instead, centred on the
    // glyphs' line: nothing of the cutout rule applies.
    test('a vertical system bar is not a cutout', () {
      for (final (EdgeInsets padding, ChromePlacement placement)
          in <(EdgeInsets, ChromePlacement)>[
            (kDuoOuterPortraitPadding, ChromePlacement.right),
            (kDuoOuterLandscapePadding, ChromePlacement.left),
            (kDuoOuterLandscapeRightPadding, ChromePlacement.right),
          ]) {
        expect(inset(padding, placement), 0);
      }
    });
  });
}
