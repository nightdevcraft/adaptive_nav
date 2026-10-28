import 'dart:math' as math;

import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav/src/pane_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// How many tabs the system column holds in each posture, the table in the
/// README: worked out by the shell itself, with labels of one line, as the
/// example's are.
///
/// Each row: the posture; tabs with a place with labels `none`, `all` and
/// `selected`; with how many tabs a screen with one button folds them, to
/// two places, the selected tab and More; and what the toolbar has beside
/// those two.
const List<(int, List<int>, List<int?>, List<double>)> _table =
    <(int, List<int>, List<int?>, List<double>)>[
      (1, <int>[8, 6, 6], <int?>[8, 6, 6], <double>[346, 310, 310]),
      (2, <int>[6, 4, 4], <int?>[6, 4, 4], <double>[222, 186, 186]),
      (3, <int>[6, 4, 4], <int?>[6, 4, 4], <double>[222, 186, 186]),
      (5, <int>[9, 6, 6], <int?>[9, null, null], <double>[387, 351, 351]),
      (6, <int>[9, 6, 6], <int?>[9, null, null], <double>[387, 351, 351]),
      (9, <int>[9, 6, 6], <int?>[9, null, null], <double>[387, 351, 351]),
    ];

/// A root with one button on the second tab, as the example's Starred.
Widget _oneButton(DemoRoute route, Widget screen) => switch (route) {
  DemoHome() => ToolbarScreen(
    title: 'Home',
    groups: <List<PaneToolbarItem>>[
      <PaneToolbarItem>[toolbarItem(Icons.filter_list)],
    ],
  ),
  _ => screen,
};

void main() {
  const List<NavigationRailLabelType> modes = <NavigationRailLabelType>[
    NavigationRailLabelType.none,
    NavigationRailLabelType.all,
    NavigationRailLabelType.selected,
  ];

  testWidgets('the README\'s table', (WidgetTester tester) async {
    addTearDown(tester.view.reset);
    final List<String> rows = <String>[];
    for (final (
          int number,
          List<int> fits,
          List<int?> folds,
          List<double> rooms,
        )
        in _table) {
      final DuoPose pose = duoPose(number);
      final ({double top, double end}) column = duoColumn(pose);
      final List<int> placed = <int>[];
      final List<int?> folding = <int?>[];
      final List<double> folded = <double>[];
      for (final NavigationRailLabelType labels in modes) {
        setPose(
          tester,
          pose.window,
          padding: pose.padding,
          display: pose.display,
        );
        DemoHarness harness(int tabs) => DemoHarness(
          system: pose.system,
          extraBranches: tabs - 2,
          peopleLabel: 'Team',
          extraLabel: (int i) => 'T$i',
          masterMinWidth: 270,
          detailMinWidth: 270,
          railLabelsInColumn: labels,
          wrapPage: _oneButton,
        );
        // More tabs than any column holds.
        const int many = 20;
        await tester.pumpWidget(harness(many).app());
        await tester.pumpAndSettle();

        // The tabs with a place; the last place is More.
        final int places = <int>[
          for (int b = 0; b < many; b++)
            if (find.byKey(AdaptiveShell.columnTabKey(b)).evaluate().isNotEmpty)
              b,
        ].length;
        expect(find.byKey(AdaptiveShell.railOverflowKey), findsOneWidget);
        final double extent = tester
            .getSize(find.byKey(AdaptiveShell.columnTabKey(0)))
            .height;
        final double inner = column.end - column.top;
        final int fit = columnTabPlaces(
          inner: inner,
          extent: extent,
          tabs: many,
        );
        expect(places + 1, fit, reason: 'the shell counts as the function');
        placed.add(fit);

        // A screen with one button folds the tabs once they leave it less
        // than the button: the smallest number of tabs that does.
        int? fold;
        for (int n = 2; n <= many && fold == null; n++) {
          final double room =
              inner -
              columnTabsExtent(math.min(n, fit), extent) -
              kPaneToolbarGroupGap;
          if (room < kPaneToolbarItemExtent) {
            fold = n;
          }
        }
        folding.add(fold);
        // Folded, the selected tab and More keep two places: the toolbar has
        // the rest, and there is room in it for the button.
        final double room =
            inner - columnTabsExtent(2, extent) - kPaneToolbarGroupGap;
        expect(room, greaterThanOrEqualTo(kPaneToolbarItemExtent));
        folded.add(room);
        await tester.pumpWidget(const SizedBox());

        // The shell folds there, to two places, and not one tab before.
        if (fold != null) {
          for (final int tabs in <int>[fold - 1, fold]) {
            final DemoHarness h = harness(tabs);
            await tester.pumpWidget(h.app());
            await tester.pumpAndSettle();
            h.delegate.goBranch(1);
            await tester.pumpAndSettle();
            final Finder two = find.byKey(AdaptiveShell.railCollapsedKey);
            if (tabs < fold) {
              expect(two, findsNothing, reason: 'pose $number, $tabs tabs');
            } else {
              expect(
                tester.getSize(two).height,
                columnTabsExtent(2, extent),
                reason: 'pose $number, $tabs tabs',
              );
              expect(
                find.byKey(AdaptiveShell.columnTabKey(1)).hitTestable(),
                findsOneWidget,
              );
            }
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
      rows.add(
        '| $number | ${placed.join(' / ')} | '
        '${placed.map((int p) => p + 1).join(' / ')} | '
        '${folding.map((int? f) => f ?? '—').join(' / ')} | '
        '${folded.map((double r) => r.toStringAsFixed(0)).join(' / ')} |',
      );
      expect(placed, fits, reason: 'pose $number');
      expect(folding, folds, reason: 'pose $number');
      expect(folded, rooms, reason: 'pose $number');
    }
    debugPrint(rows.join('\n'));
  });
}
