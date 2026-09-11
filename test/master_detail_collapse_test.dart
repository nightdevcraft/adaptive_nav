import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `collapseWhenDetailEmpty`: the list spans the full width until something
/// is selected, and the split arrives with the detail.
void main() {
  /// Width of the content area (after the rail and its divider) — the
  /// reference for "full width", compared against the master width.
  double contentWidth(WidgetTester tester) {
    final double rail = tester.getSize(find.byType(NavigationRail)).width;
    return kWide.width - rail - 1; // 1 — the package's VerticalDivider
  }

  testWidgets('empty detail on wide: master at full width, no placeholder', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    expect(find.text('Select an item'), findsNothing);
    expect(
      tester.getSize(find.byType(DemoListScreen)).width,
      closeTo(contentWidth(tester), 0.5),
    );
  });

  testWidgets('a detail appears: split by paneRatio; gone: full width again', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final double full = tester.getSize(find.byType(DemoListScreen)).width;

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();

    final double masterW = tester.getSize(find.byType(DemoListScreen)).width;
    final double detailW = tester.getSize(find.byType(DemoDetailScreen)).width;
    expect(masterW, lessThan(full));
    expect(masterW / (masterW + detailW), closeTo(0.35, 0.04));

    await h.delegate.pop();
    await tester.pumpAndSettle();

    expect(find.text('Detail 1'), findsNothing);
    expect(
      tester.getSize(find.byType(DemoListScreen)).width,
      closeTo(full, 0.5),
    );
  });

  testWidgets('master state survives the collapse and the expansion', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    // Ephemeral master state (a counter) — what a remount would lose.
    await tester.tap(find.byKey(const ValueKey<String>('list-inc')));
    await tester.tap(find.byKey(const ValueKey<String>('list-inc')));
    await tester.pumpAndSettle();
    expect(find.text('List: 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('item-2')));
    await tester.pumpAndSettle();
    expect(find.text('List: 2'), findsOneWidget); // expanded into a split

    await h.delegate.pop();
    await tester.pumpAndSettle();
    expect(find.text('List: 2'), findsOneWidget); // and collapsed back
  });

  testWidgets(
    'collapseWhenDetailEmpty: false keeps two panes and the placeholder',
    (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setWindow(tester, kWide);

      final DemoHarness h = DemoHarness(collapseWhenDetailEmpty: false);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      expect(find.text('Select an item'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DemoListScreen)).width,
        lessThan(contentWidth(tester)),
      );
    },
  );

  testWidgets('a plain branch (no masterDetail) is untouched by the collapse', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    await h.delegate.goBranch(1); // Home — masterDetail == null
    await tester.pumpAndSettle();

    expect(find.text('Home: 0'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DemoHomeScreen)).width,
      closeTo(contentWidth(tester), 0.5),
    );
  });
}
