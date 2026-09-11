import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Pane decoration geometry: margins, the gap that replaced the divider, the
/// radius, and the threshold arithmetic it all feeds into.
void main() {
  const double gutter = 8;
  const double gap = 8;
  const double radius = 12;
  const Color canvas = Color(0xFF123456);

  final PaneDecoration panes = PaneDecoration(
    margin: const EdgeInsets.all(gutter),
    gap: gap,
    radius: BorderRadius.circular(radius),
    canvasColor: (BuildContext _) => canvas,
  );

  // The rail is the same kind of card: margin on the left, top and bottom, a
  // radius, and NO divider after it.
  const RailDecoration rail = RailDecoration(
    margin: EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    radius: BorderRadius.all(Radius.circular(radius)),
    dividerWidth: 0,
  );

  /// The region the rail plus its margin takes on the left.
  const double railRegion = kDefaultRailWidth + gutter;

  const double paneThreshold = 320 + 360 + gap;
  const double windowThreshold = paneThreshold + 2 * gutter + railRegion;

  /// Width left to the panes at window width [window].
  double paneArea(double window) => window - railRegion - 2 * gutter;

  Future<DemoHarness> pumpWide(WidgetTester tester, Size size) async {
    addTearDown(tester.view.reset);
    setWindow(tester, size);
    final DemoHarness h = DemoHarness(panes: panes, rail: rail);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('panes are cards inset from the rail and edges, with a gap', (
    WidgetTester tester,
  ) async {
    const Size window = Size(1000, 900);
    await pumpWide(tester, window);

    final Rect master = tester.getRect(find.byType(DemoListScreen));
    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));

    // On the left: the rail region (the rail plus its card margin) and the
    // pane margin.
    expect(master.left, railRegion + gutter);
    // Between the panes: exactly the gap (no divider between them any more).
    expect(detail.left, master.right + gap);
    // On the right, top and bottom: the same margin from the window edges.
    expect(detail.right, window.width - gutter);
    expect(master.top, gutter);
    expect(master.bottom, window.height - gutter);
    expect(detail.top, gutter);
    expect(detail.bottom, window.height - gutter);
  });

  testWidgets('the rail is the same card: margin, radius, no divider', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, const Size(1000, 900));

    final Finder railWidget = find.byType(NavigationRail);
    final Rect railRect = tester.getRect(railWidget);

    // Margin on the left, top and bottom; the width of the rail ITSELF is
    // unchanged — the margin was added outside, not taken from the
    // destinations.
    expect(railRect.left, gutter);
    expect(railRect.top, gutter);
    expect(railRect.bottom, 900 - gutter);
    expect(railRect.width, kDefaultRailWidth);

    // There is no divider after the rail: the gap up to the master pane took
    // its place.
    expect(find.byType(VerticalDivider), findsNothing);
    expect(
      tester.getRect(find.byType(DemoListScreen)).left,
      railRegion + gutter,
    );

    expect(
      find.ancestor(
        of: railWidget,
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is ClipRRect && w.borderRadius == BorderRadius.circular(radius),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('every pane is clipped to its radius', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, const Size(1000, 900));

    for (final Finder screen in <Finder>[
      find.byType(DemoListScreen),
      find.byType(DemoDetailScreen),
    ]) {
      expect(
        find.ancestor(
          of: screen,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is ClipRRect &&
                w.borderRadius == BorderRadius.circular(radius),
          ),
        ),
        findsOneWidget,
      );
    }
  });

  // The canvas lies under the WHOLE wide layout, including the margin around
  // the rail capsule. While it was confined to the content area, the rail
  // floated on the `Scaffold` background — the same colour as the capsule.
  testWidgets('the canvas is painted from the config, under the rail too', (
    WidgetTester tester,
  ) async {
    const Size window = Size(1000, 900);
    await pumpWide(tester, window);

    final Finder canvasBox = find.byWidgetPredicate(
      (Widget w) => w is ColoredBox && w.color == canvas,
    );
    expect(canvasBox, findsOneWidget);
    expect(tester.getRect(canvasBox), Offset.zero & window);
  });

  // Pane widths are ABSOLUTE numbers from the arithmetic: an error in
  // accounting for the margins or the gap leaves either a hole on the right or
  // a detail past the edge.
  for (final double width in <double>[windowThreshold, 800, 1024, 1440]) {
    testWidgets('width $width: panes + gap == the area, with no overflow', (
      WidgetTester tester,
    ) async {
      await pumpWide(tester, Size(width, 900));

      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));

      expect(master.width + gap + detail.width, paneArea(width));
      expect(detail.right, width - gutter);
      expect(tester.takeException(), isNull);
    });
  }

  // Margins and the gap TAKE space from the panes, so they move the "two
  // panes" threshold as well.
  testWidgets('the two-pane threshold accounts for the margins and the gap', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, const Size(windowThreshold, 900));
    expect(find.byType(DemoListScreen), findsOneWidget);
    expect(find.byType(DemoDetailScreen), findsOneWidget);

    // One pixel narrower and the detail covers the master (one pane) instead
    // of being squeezed.
    setWindow(tester, const Size(windowThreshold - 1, 900));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(DemoDetailScreen)).width,
      paneArea(windowThreshold - 1),
    );
  });

  testWidgets('compact gets no decoration: the screen spans the full width', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);
    final DemoHarness h = DemoHarness(panes: panes);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
    expect(detail.left, 0);
    expect(detail.width, kCompact.width);
  });

  // The decoration is a wrapper around the same navigators, not a rebuild.
  // Screen state has to survive both a resize within wide and a crossing of
  // the threshold.
  testWidgets('detail state survives a resize across the threshold', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, const Size(1200, 900));

    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);

    setWindow(tester, const Size(windowThreshold - 1, 900));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);

    setWindow(tester, const Size(1400, 900));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);
  });
}
