import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav/src/column_transition.dart';
import 'package:adaptive_nav/src/pane_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// A screen whose toolbar depends on its branch, so that every tab brings a
/// toolbar of a different length into the column: none on the first, then
/// one item more on each.
class _BranchToolbar extends StatelessWidget {
  const _BranchToolbar({required this.title});

  final String title;

  static const List<IconData> _icons = <IconData>[
    Icons.share,
    Icons.print,
    Icons.archive,
    Icons.delete,
    Icons.label,
    Icons.flag,
  ];

  @override
  Widget build(BuildContext context) {
    final int branch = PaneToolbarHost.maybeOf(context)?.slot.branch ?? 0;
    return ToolbarScreen(
      title: title,
      groups: <List<PaneToolbarItem>>[
        for (int i = 0; i < branch % (_icons.length + 1); i++)
          <PaneToolbarItem>[toolbarItem(_icons[i])],
      ],
    );
  }
}

/// The example's roots: one button on the second tab, as Starred has
/// Filters, and one on the last, as Trash has Empty; none on the rest.
class _OneButton extends StatelessWidget {
  const _OneButton({required this.title, required this.count, this.onBuild});

  final String title;
  final int count;
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild?.call();
    final int branch = PaneToolbarHost.maybeOf(context)?.slot.branch ?? 0;
    final IconData? icon = branch == 1
        ? Icons.filter_list
        : branch == count - 1
        ? Icons.delete_sweep
        : null;
    return ToolbarScreen(
      title: title,
      groups: <List<PaneToolbarItem>>[
        if (icon != null) <PaneToolbarItem>[toolbarItem(icon)],
      ],
    );
  }
}

/// How many places the tabs had in a column [inner] tall with tabs [extent]
/// tall each while the toolbar's zone kept room for two buttons and the tabs
/// were 12 apart.
int _reservedPlaces(double inner, double extent, int tabs) {
  final double room = inner - (48 + 12 + 48) - 12;
  return ((room + 12) / (extent + 12)).floor().clamp(1, tabs);
}

/// iPhone Duo's system column in two zones: the toolbar's at the top and the
/// tabs' at the bottom, with places that come from the column alone.
void main() {
  Future<List<String>> errorsDuring(Future<void> Function() body) async {
    final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
    final List<String> errors = <String>[];
    FlutterError.onError = (FlutterErrorDetails d) =>
        errors.add(d.exception.toString().split('\n').first);
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  /// The example's seven tabs: People, Home and five more.
  const int tabs = 7;

  /// The numbers of tabs every arrangement is checked at.
  const List<int> counts = <int>[2, 3, 5, 7, 10];

  /// Roots with no buttons, and a detail with Close and Edit.
  Widget bare(DemoRoute route, Widget screen) => switch (route) {
    DemoDetail(:final int id) => ToolbarScreen(
      title: 'Detail $id',
      pinned: <PaneToolbarItem>[toolbarItem(Icons.edit)],
    ),
    _ => ToolbarScreen(title: '$route'),
  };

  Future<DemoHarness> pump(
    WidgetTester tester,
    DuoPose pose, {
    NavigationRailLabelType labels = NavigationRailLabelType.none,
    Widget Function(DemoRoute, Widget)? screens,
    List<int> priorities = const <int>[],
    DetailChrome detailChrome = DetailChrome.covered,
    int count = tabs,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, pose.window, padding: pose.padding, display: pose.display);
    final DemoHarness h = DemoHarness(
      system: pose.system,
      extraBranches: count - 2,
      // One line each, as the example's labels.
      extraLabel: (int i) => 'Tab $i',
      // The example's minimums, so the inner display in landscape has two
      // panes.
      masterMinWidth: 270,
      detailMinWidth: 270,
      railLabelsInColumn: labels,
      visibilityPriorities: priorities,
      detailChrome: detailChrome,
      platform: detailChrome == DetailChrome.kept ? TargetPlatform.iOS : null,
      wrapPage:
          screens ??
          (DemoRoute route, Widget screen) => switch (route) {
            DemoDetail(:final int id) => ToolbarScreen(
              title: 'Detail $id',
              pinned: <PaneToolbarItem>[toolbarItem(Icons.edit)],
            ),
            _ => _BranchToolbar(title: '$route'),
          },
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    return h;
  }

  /// Every place of the tabs' zone: each tab with one, and the More button.
  Map<Key, Rect> places(WidgetTester tester, [int count = tabs]) => <Key, Rect>{
    for (int b = 0; b < count; b++)
      if (find.byKey(AdaptiveShell.columnTabKey(b)).evaluate().isNotEmpty)
        AdaptiveShell.columnTabKey(b): tester.getRect(
          find.byKey(AdaptiveShell.columnTabKey(b)),
        ),
    if (find.byKey(AdaptiveShell.railOverflowKey).evaluate().isNotEmpty)
      AdaptiveShell.railOverflowKey: tester.getRect(
        find.byKey(AdaptiveShell.railOverflowKey),
      ),
  };

  /// Whether the tabs are folded.
  bool folded(WidgetTester tester) =>
      find.byKey(AdaptiveShell.railCollapsedKey).evaluate().isNotEmpty;

  /// The tabs' zone.
  Rect zone(WidgetTester tester) =>
      tester.getRect(find.byKey(AdaptiveShell.columnTabsKey));

  /// How much of the place keyed [key] is in view.
  double opacity(WidgetTester tester, Key key) => tester
      .renderObject<RenderDrivenBox>(
        find
            .ancestor(of: find.byKey(key), matching: find.byType(DrivenBox))
            .first,
      )
      .opacityNow;

  /// Whether a place of the tabs' zone is fading in or out.
  bool fading(WidgetTester tester) => tester
      .renderObjectList<RenderDrivenBox>(
        find.descendant(
          of: find.byKey(AdaptiveShell.columnTabsKey),
          matching: find.byType(DrivenBox),
        ),
      )
      .any((RenderDrivenBox o) => o.opacityNow < 1);

  /// The button of the bottom place of the tabs' zone: More's, or the last
  /// tab's when every tab has a place.
  Rect bottomButton(WidgetTester tester, Map<Key, Rect> places) {
    final Key last = places.keys.last;
    return last == AdaptiveShell.railOverflowKey
        ? places[last]!
        : tester.getRect(
            find.descendant(
              of: find.byKey(last),
              matching: find.byType(IconButton),
            ),
          );
  }

  /// Where a folded zone puts the selected tab: the place above the bottom
  /// one, in a column ending at [end].
  Rect abovePlace(Map<Key, Rect> places, double end) {
    final Rect tab = places[AdaptiveShell.columnTabKey(0)]!;
    return Rect.fromLTWH(
      tab.left,
      end - 2 * tab.height - kPaneToolbarItemGap,
      tab.width,
      tab.height,
    );
  }

  /// The tab [b] of [count]'s label in the harness.
  String label(int b) => switch (b) {
    0 => 'People',
    1 => 'Home',
    _ => 'Tab ${b - 2}',
  };

  /// Pumps the animation that [change] starts frame by frame, calling
  /// [frame] after each.
  Future<void> frames(
    WidgetTester tester,
    void Function() change,
    void Function() frame,
  ) async {
    change();
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frame();
    }
    await tester.pumpAndSettle();
    frame();
  }

  /// The fill of the button under [finder]: a selected tab's, or a More
  /// button carrying the selection, is filled.
  Color? fill(WidgetTester tester, Finder finder) => tester
      .widget<Material>(
        find.descendant(of: finder, matching: find.byType(Material)).first,
      )
      .color;

  bool lit(WidgetTester tester, Finder finder) {
    final Color? color = fill(tester, finder);
    return color != null && color != Colors.transparent;
  }

  /// Pumps the folding or unfolding [change] starts frame by frame, from
  /// the full zone [full] with tab [selected] selected, and checks every
  /// frame: More's button stays at [more], the full zone's last place, the
  /// selected tab moves only down to fold and up to unfold, along the
  /// column, and the other tabs only fade, where they stand. Returns the
  /// selected tab's place and the others' opacity in every frame.
  Future<({List<Rect> people, List<double> others})> folding(
    WidgetTester tester,
    void Function() change,
    Map<Key, Rect> full, {
    required Rect more,
    required int selected,
  }) async {
    final bool folding = !folded(tester);
    final Key tab = AdaptiveShell.columnTabKey(selected);
    final List<Rect> moving = <Rect>[];
    final List<double> others = <double>[];
    await frames(tester, change, () {
      final Finder button = find.byKey(AdaptiveShell.railOverflowKey);
      if (button.evaluate().isNotEmpty) {
        final Rect now = tester.getRect(button);
        expect((now.center - more.center).distance, lessThanOrEqualTo(0.5));
        expect(now.size, more.size);
      }
      final Rect place = tester.getRect(find.byKey(tab));
      expect(place.left, full[tab]!.left);
      if (moving.isNotEmpty) {
        expect(
          folding ? place.top >= moving.last.top : place.top <= moving.last.top,
          isTrue,
          reason: 'one way',
        );
      }
      moving.add(place);
      final List<Key> rest = <Key>[
        for (final Key k in full.keys)
          if (k != tab && k != AdaptiveShell.railOverflowKey) k,
      ];
      final List<double> faded = <double>[
        for (final Key k in rest)
          if (find.byKey(k).evaluate().isNotEmpty) ...<double>[
            opacity(tester, k),
          ] else
            0,
      ];
      for (final Key k in rest) {
        if (find.byKey(k).evaluate().isNotEmpty) {
          expect(tester.getRect(find.byKey(k)), full[k], reason: 'in place');
        }
      }
      others.add(faded.isEmpty ? 0 : faded.first);
    });
    final List<double> tops = <double>[for (final Rect r in moving) r.top];
    expect(
      tops.where((double t) => t != tops.first && t != tops.last),
      isNotEmpty,
      reason: 'moved, not a jump',
    );
    expect(
      others.where((double o) => o > 0 && o < 1),
      isNotEmpty,
      reason: 'faded, not a cut',
    );
    return (people: moving, others: others);
  }

  group('roots without buttons: the tabs do not move', () {
    for (final int count in counts) {
      for (final DuoPose pose in kDuoColumnPoses) {
        for (final NavigationRailLabelType labels
            in NavigationRailLabelType.values) {
          testWidgets('$count tabs, pose ${pose.number}, ${labels.name}: '
              'every tab, a detail opened and closed', (
            WidgetTester tester,
          ) async {
            late final DemoHarness h;
            final List<Map<Key, Rect>> seen = <Map<Key, Rect>>[];
            // Roots only: the detail's toolbar may fold the tabs where they
            // leave it too little (see 'a root with a button').
            bool rootFolded = false;
            bool roots = true;
            final List<(int, bool, bool)> selections = <(int, bool, bool)>[];
            void record() {
              if (roots) {
                rootFolded = rootFolded || folded(tester);
              } else if (folded(tester) || fading(tester)) {
                // Folded, folding or unfolding, or going and coming with a
                // detail that covers the rail.
                return;
              }
              final Map<Key, Rect> now = places(tester, count);
              if (now.isEmpty) {
                // Under a detail that covers the rail: no tabs to move.
                return;
              }
              seen.add(now);
            }

            final List<String> errors = await errorsDuring(() async {
              h = await pump(
                tester,
                pose,
                labels: labels,
                count: count,
                screens: bare,
              );
              record();
              // Down the tabs and back up, each one selected in turn.
              for (final int b in <int>[
                for (int b = 0; b < count; b++) b,
                for (int b = count - 1; b >= 0; b--) b,
              ]) {
                await frames(tester, () => h.delegate.goBranch(b), record);
                final Finder more = find.byKey(AdaptiveShell.railOverflowKey);
                selections.add((
                  b,
                  more.evaluate().isNotEmpty && lit(tester, more),
                  seen.first.containsKey(AdaptiveShell.columnTabKey(b)) &&
                      lit(
                        tester,
                        find.descendant(
                          of: find.byKey(AdaptiveShell.columnTabKey(b)),
                          matching: find.byType(IconButton),
                        ),
                      ),
                ));
              }
              roots = false;
              await frames(
                tester,
                () => h.delegate.push(const DemoDetail(1)),
                record,
              );
              await frames(tester, h.delegate.pop, record);
            });

            expect(errors, isEmpty);
            expect(rootFolded, isFalse);
            expect(folded(tester), isFalse, reason: 'back on People');
            for (final Map<Key, Rect> state in seen) {
              expect(state, seen.first);
            }

            // The zone against the column's end, and as many places as the
            // column holds: one more would not fit.
            final ({double top, double end}) c = duoColumn(pose);
            final Rect tabsZone = zone(tester);
            final double extent = tester
                .getSize(find.byKey(AdaptiveShell.columnTabKey(0)))
                .height;
            final int shown = seen.first.length;
            final bool more = seen.first.containsKey(
              AdaptiveShell.railOverflowKey,
            );
            expect(tabsZone.bottom, c.end);
            expect(
              tabsZone.height,
              moreOrLessEquals(
                shown * extent + (shown - 1) * kPaneToolbarItemGap,
              ),
            );
            expect(
              tabsZone.top - kPaneToolbarGroupGap,
              greaterThanOrEqualTo(c.top),
              reason: 'the zone fits the column',
            );
            if (more) {
              expect(count, greaterThan(3), reason: 'two or three always fit');
              expect(
                tabsZone.top -
                    kPaneToolbarGroupGap -
                    kPaneToolbarItemGap -
                    extent,
                lessThan(c.top),
                reason: 'a place more would not fit',
              );
            } else {
              expect(shown, count, reason: 'every tab has a place');
            }
            if (count == tabs) {
              expect(
                shown,
                greaterThan(_reservedPlaces(c.end - c.top, extent, count)),
                reason: 'more than with room kept for a toolbar',
              );
            }

            // The selected tab is lit in its place; a selected tab without
            // one lights More, and nothing else.
            for (final (int b, bool moreLit, bool tabLit) in selections) {
              final bool placed = seen.first.containsKey(
                AdaptiveShell.columnTabKey(b),
              );
              expect(tabLit, placed, reason: 'tab $b');
              expect(moreLit, !placed, reason: 'More, tab $b');
            }
          });
        }
      }
    }
  });

  group('a root with a button', () {
    for (final int count in counts) {
      for (final DuoPose pose in kDuoColumnPoses) {
        for (final NavigationRailLabelType labels
            in NavigationRailLabelType.values) {
          testWidgets('$count tabs, pose ${pose.number}, ${labels.name}: '
              'the tabs stay, or fold to the selected one above More', (
            WidgetTester tester,
          ) async {
            final DemoHarness h = await pump(
              tester,
              pose,
              labels: labels,
              count: count,
              screens: (DemoRoute route, Widget screen) => switch (route) {
                DemoDetail() => bare(route, screen),
                _ => _OneButton(title: '$route', count: count),
              },
            );
            final Map<Key, Rect> before = places(tester, count);
            final Rect more = bottomButton(tester, before);
            final ({double top, double end}) c = duoColumn(pose);
            final Rect tabsZone = zone(tester);
            // What the tabs leave the toolbar, less the gap between them.
            final bool folds =
                tabsZone.top - kPaneToolbarGroupGap - c.top <
                kPaneToolbarItemExtent;
            if (count <= 3) {
              expect(folds, isFalse, reason: 'two or three tabs leave room');
            }
            if (count == tabs && labels == NavigationRailLabelType.none) {
              expect(folds, pose.number == 2 || pose.number == 3);
            }

            Future<void> check(int b, IconData icon) async {
              final Finder button = find.descendant(
                of: find.byKey(AdaptiveShell.paneToolbarKey),
                matching: find.byIcon(icon),
              );
              expect(button, findsOneWidget);
              expect(
                find.byKey(AdaptiveShell.paneToolbarMenuKey),
                findsNothing,
              );
              expect(
                tester.getCenter(button).dy - kPaneToolbarItemExtent / 2,
                c.top,
              );
              expect(folded(tester), folds);
              if (!folds) {
                expect(places(tester, count), before);
                expect(
                  tester.getRect(button).bottom,
                  lessThanOrEqualTo(tabsZone.top - kPaneToolbarGroupGap),
                );
                return;
              }
              // Two buttons at the bottom: the selected tab, lit, above More,
              // which is where the full zone has its last place.
              final Map<Key, Rect> two = places(tester, count);
              expect(two.keys, <Key>[
                AdaptiveShell.columnTabKey(b),
                AdaptiveShell.railOverflowKey,
              ]);
              expect(two[AdaptiveShell.railOverflowKey], more);
              expect(
                two[AdaptiveShell.columnTabKey(b)],
                abovePlace(before, c.end),
              );
              expect(
                lit(
                  tester,
                  find.descendant(
                    of: find.byKey(AdaptiveShell.columnTabKey(b)),
                    matching: find.byType(IconButton),
                  ),
                ),
                isTrue,
              );
              expect(
                lit(tester, find.byKey(AdaptiveShell.railOverflowKey)),
                isFalse,
              );
              expect(
                tester.getRect(button).bottom,
                lessThanOrEqualTo(two.values.first.top - kPaneToolbarGroupGap),
              );
            }

            // Folded, More's menu has every tab, the current one ticked, and
            // switches the tab.
            Future<void> select(int b) async {
              if (!folded(tester)) {
                h.delegate.goBranch(b);
                await tester.pumpAndSettle();
                return;
              }
              final int current = h.delegate.state.activeBranch;
              await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
              await tester.pumpAndSettle();
              expect(find.byType(MenuItemButton), findsNWidgets(count));
              expect(
                find.descendant(
                  of: find.widgetWithText(MenuItemButton, label(current)),
                  matching: find.byIcon(Icons.check),
                ),
                findsOneWidget,
              );
              expect(find.byIcon(Icons.check), findsOneWidget);
              // Ten tabs make a menu taller than the outer display turned.
              await tester.ensureVisible(
                find.widgetWithText(MenuItemButton, label(b)),
              );
              await tester.tap(find.widgetWithText(MenuItemButton, label(b)));
              await tester.pumpAndSettle();
              expect(h.delegate.state.activeBranch, b);
            }

            await select(1);
            await check(1, Icons.filter_list);
            if (count > 2) {
              await select(count - 1);
              await check(count - 1, Icons.delete_sweep);
            }

            await select(0);
            expect(folded(tester), isFalse);
            expect(places(tester, count), before);
            expect(zone(tester), tabsZone);
          });
        }
      }
    }

    testWidgets('the selected tab tapped again does what it does unfolded', (
      WidgetTester tester,
    ) async {
      // The package's tabs, folded or not, pass the tab to
      // AdaptiveShell.onSelectBranch: a tap on the selected tab is a
      // reselect, back to the root. The same detail in the outer display
      // upright, where nothing folds, and turned, where it folds the tabs;
      // the root unfolds them again.
      Future<List<DemoRoute>> tapPeople(
        DuoPose pose, {
        required bool folds,
      }) async {
        final DemoHarness h = await pump(
          tester,
          pose,
          detailChrome: DetailChrome.kept,
          screens: bare,
          // Close and Edit fit beside five upright, not turned.
          count: 5,
        );
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        expect(folded(tester), folds);
        await tester.tap(find.byKey(AdaptiveShell.columnTabKey(0)));
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 0);
        expect(folded(tester), isFalse);
        final List<DemoRoute> routes = <DemoRoute>[
          for (final NavEntry<DemoRoute> e
              in h.delegate.state.branches[0].entries)
            e.route,
        ];
        await tester.pumpWidget(const SizedBox());
        return routes;
      }

      final List<DemoRoute> unfolded = await tapPeople(
        duoPose(1),
        folds: false,
      );
      expect(unfolded, <DemoRoute>[const DemoList()]);
      expect(await tapPeople(duoPose(2), folds: true), unfolded);
    });

    testWidgets('a column too short for two places: More alone, lit', (
      WidgetTester tester,
    ) async {
      // The outer display turned, 300 tall: 300 − 82 − 24 − 24 = 170 between
      // the ends, three places. Close and the menu, 108, need more than the
      // 170 − 102 − 12 = 56 that two places leave; one leaves 110, enough
      // for Close and Edit.
      final DuoPose pose = duoPose(2);
      final DemoHarness h = await pump(
        tester,
        pose,
        detailChrome: DetailChrome.kept,
        screens: bare,
      );
      setPose(
        tester,
        const Size(678, 300),
        padding: pose.padding,
        display: pose.display,
      );
      await tester.pumpAndSettle();
      final Map<Key, Rect> before = places(tester);
      expect(before, hasLength(3));
      final Rect more = before[AdaptiveShell.railOverflowKey]!;
      expect(more.bottom, 300 - 24);

      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(folded(tester), isTrue);
      expect(places(tester), <Key, Rect>{AdaptiveShell.railOverflowKey: more});
      expect(lit(tester, find.byKey(AdaptiveShell.railOverflowKey)), isTrue);
      expect(
        find.descendant(
          of: find.byKey(AdaptiveShell.paneToolbarKey),
          matching: find.byIcon(Icons.close),
        ),
        findsOneWidget,
      );
      final Finder edit = find.descendant(
        of: find.byKey(AdaptiveShell.paneToolbarKey),
        matching: find.byIcon(Icons.edit),
      );
      expect(edit, findsOneWidget);
      expect(
        tester.getCenter(edit).dy + kPaneToolbarItemExtent / 2,
        lessThanOrEqualTo(more.top - kPaneToolbarGroupGap),
      );

      await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(tabs));
      expect(
        find.descendant(
          of: find.widgetWithText(MenuItemButton, 'People'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(MenuItemButton, 'Home'));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);
      expect(folded(tester), isFalse);
      expect(places(tester), before);
    });
  });

  group('more tabs than places', () {
    testWidgets('pose 1, ten tabs: seven and More, the last place', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(1),
        count: 10,
        screens: bare,
      );

      // 678 − 170 − 24 − 24 = 460, less 12 from the toolbar's zone: 448 for
      // places of 48, 6 apart — eight.
      final Map<Key, Rect> before = places(tester, 10);
      expect(before.keys, <Key>[
        for (int b = 0; b < 7; b++) AdaptiveShell.columnTabKey(b),
        AdaptiveShell.railOverflowKey,
      ]);
      expect(
        before[AdaptiveShell.railOverflowKey]!.bottom,
        kDuoOuterPortrait.height - 24,
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(AdaptiveShell.railOverflowKey),
          matching: find.byIcon(Icons.apps),
        ),
        findsOneWidget,
        reason: 'not an ellipsis: that is the toolbar\'s menu',
      );
      final Finder people = find.descendant(
        of: find.byKey(AdaptiveShell.columnTabKey(0)),
        matching: find.byType(IconButton),
      );
      final Color? selected = fill(tester, people);
      expect(selected, isNot(Colors.transparent));
      expect(
        fill(tester, find.byKey(AdaptiveShell.railOverflowKey)),
        isNot(selected),
      );

      // A hidden tab selected: the places stay, More carries the selection.
      await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tab 7'));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 9);
      expect(places(tester, 10), before);
      expect(fill(tester, find.byKey(AdaptiveShell.railOverflowKey)), selected);
      expect(fill(tester, people), isNot(selected));
      // It is ticked in the menu.
      await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.widgetWithText(MenuItemButton, 'Tab 7'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pose 1, seven tabs: all of them, no More', (
      WidgetTester tester,
    ) async {
      await pump(tester, duoPose(1));

      expect(places(tester).keys, <Key>[
        for (int b = 0; b < tabs; b++) AdaptiveShell.columnTabKey(b),
      ]);
    });

    testWidgets('visibilityPriority picks the hidden ones, not the order', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        duoPose(1),
        count: 10,
        priorities: <int>[0, -1, 0, 0, 0, 0, 0, 0, 0, 1],
      );

      // Home goes first, then the last of equals: Tab 6, Tab 5. Tab 7 keeps
      // its place, and the order holds.
      expect(places(tester, 10).keys, <Key>[
        AdaptiveShell.columnTabKey(0),
        for (int b = 2; b < 7; b++) AdaptiveShell.columnTabKey(b),
        AdaptiveShell.columnTabKey(9),
        AdaptiveShell.railOverflowKey,
      ]);
    });

    testWidgets('railOverflowBuilder draws More', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      final DuoPose pose = duoPose(1);
      setPose(
        tester,
        pose.window,
        padding: pose.padding,
        display: pose.display,
      );
      final DemoHarness h = DemoHarness(
        system: pose.system,
        extraBranches: 8,
        railOverflowBuilder:
            (
              BuildContext context,
              List<int> hidden,
              ValueChanged<int> onSelectBranch,
              bool active,
            ) => TextButton(
              key: const ValueKey<String>('mine'),
              onPressed: () => onSelectBranch(hidden.last),
              child: Text('+${hidden.length}'),
            ),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      expect(find.text('+3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('mine')));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 9);
    });
  });

  group('labels', () {
    testWidgets('none: icons, the label as the tooltip', (
      WidgetTester tester,
    ) async {
      await pump(tester, duoPose(1));

      expect(find.text('People'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(AdaptiveShell.columnTabKey(0)),
                matching: find.byType(IconButton),
              ),
            )
            .tooltip,
        'People',
      );
      expect(
        tester.getSize(find.byKey(AdaptiveShell.columnTabKey(0))).height,
        kPaneToolbarItemExtent,
      );
    });

    testWidgets('selected: one label, every tab the same height', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(5),
        labels: NavigationRailLabelType.selected,
      );

      Finder inTabs(Finder f) => find.descendant(
        of: find.byKey(AdaptiveShell.systemColumnKey),
        matching: f,
      );
      expect(inTabs(find.text('People')), findsOneWidget);
      expect(inTabs(find.text('Home')), findsNothing);
      final double people = tester
          .getSize(find.byKey(AdaptiveShell.columnTabKey(0)))
          .height;
      expect(people, greaterThan(kPaneToolbarItemExtent));
      expect(
        tester.getSize(find.byKey(AdaptiveShell.columnTabKey(1))).height,
        people,
        reason: 'the room for a label is kept by every tab',
      );

      h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      expect(inTabs(find.text('People')), findsNothing);
      expect(inTabs(find.text('Home')), findsOneWidget);
    });

    testWidgets('all: every label', (WidgetTester tester) async {
      await pump(tester, duoPose(5), labels: NavigationRailLabelType.all);

      for (final String label in <String>['People', 'Home', 'Tab 0']) {
        expect(
          find.descendant(
            of: find.byKey(AdaptiveShell.systemColumnKey),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
    });
  });

  group('the toolbar\'s zone', () {
    testWidgets('tabs one group, 6 apart: four are 48 × 210', (
      WidgetTester tester,
    ) async {
      await pump(tester, duoPose(1), count: 4, screens: bare);

      final Map<Key, Rect> four = places(tester, 4);
      expect(
        four.values.last.bottom - four.values.first.top,
        4 * kPaneToolbarItemExtent + 3 * kPaneToolbarItemGap,
      );
      expect(
        four.values.elementAt(1).top - four.values.first.bottom,
        kPaneToolbarItemGap,
      );
    });

    testWidgets('toolbarFirst: a long toolbar goes behind its menu, the tabs '
        'stay', (WidgetTester tester) async {
      final DemoHarness h = await pump(tester, duoPose(1));
      final Map<Key, Rect> before = places(tester);

      // Six groups on the last tab, 348: more than the 460 − 372 − 12 = 76
      // that seven tabs leave, which still holds the menu.
      h.delegate.goBranch(tabs - 1);
      await tester.pumpAndSettle();
      expect(places(tester), before);
      expect(folded(tester), isFalse);
      expect(find.byKey(AdaptiveShell.paneToolbarMenuKey), findsOneWidget);
      // The menu is the last thing in the toolbar's zone, above the tabs.
      final Rect menu = tester.getRect(
        find.byKey(AdaptiveShell.paneToolbarMenuKey),
      );
      expect(
        menu.bottom,
        lessThanOrEqualTo(
          before.values
                  .map((Rect r) => r.top)
                  .reduce((double a, double b) => a < b ? a : b) -
              kPaneToolbarGroupGap,
        ),
      );
    });

    testWidgets('toolbarFirst: items go from the bottom up by priority', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        count: 2,
        detailChrome: DetailChrome.kept,
        screens: (DemoRoute route, Widget screen) => switch (route) {
          DemoDetail() => ToolbarScreen(
            title: 'Detail',
            groups: <List<PaneToolbarItem>>[
              <PaneToolbarItem>[toolbarItem(Icons.print)],
              <PaneToolbarItem>[toolbarItem(Icons.archive, priority: 1)],
              <PaneToolbarItem>[toolbarItem(Icons.delete)],
              <PaneToolbarItem>[toolbarItem(Icons.share, priority: 2)],
            ],
          ),
          _ => screen,
        },
      );
      final Map<Key, Rect> before = places(tester, 2);
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      // Two tabs, 102, leave the toolbar 336 − 102 − 12 = 222. Close, two
      // items and the menu, 12 apart, are 228; Close, one and the menu 168.
      // Delete goes, then Print, then Archive: Share stays, last as it is.
      Finder inToolbar(IconData icon) => find.descendant(
        of: find.byKey(AdaptiveShell.paneToolbarKey),
        matching: find.byIcon(icon),
      );
      expect(inToolbar(Icons.close), findsOneWidget);
      expect(inToolbar(Icons.share), findsOneWidget);
      for (final IconData gone in <IconData>[
        Icons.print,
        Icons.archive,
        Icons.delete,
      ]) {
        expect(inToolbar(gone), findsNothing);
      }
      expect(
        tester.getRect(inToolbar(Icons.share)).bottom,
        lessThan(
          tester.getRect(find.byKey(AdaptiveShell.paneToolbarMenuKey)).top,
        ),
      );
      expect(places(tester, 2), before);
      expect(folded(tester), isFalse);
    });

    testWidgets('toolbarFirst folds the tabs when not even Close and the menu '
        'fit, on the spot, and back', (WidgetTester tester) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        detailChrome: DetailChrome.kept,
        screens: bare,
      );
      final Map<Key, Rect> before = places(tester);
      final double bottom = duoColumn(duoPose(2)).end;
      final Rect more = bottomButton(tester, before);
      // 336 for the column; six places, 318, and the gap leave 6.
      final ({List<Rect> people, List<double> others}) fold = await folding(
        tester,
        () => h.delegate.push(const DemoDetail(1)),
        before,
        more: more,
        selected: 0,
      );
      // Close and Edit, 108, stand in the 336 − 102 − 12 = 222 left.
      for (final IconData icon in <IconData>[Icons.close, Icons.edit]) {
        expect(
          find.descendant(
            of: find.byKey(AdaptiveShell.paneToolbarKey),
            matching: find.byIcon(icon),
          ),
          findsOneWidget,
        );
      }
      expect(find.byKey(AdaptiveShell.paneToolbarMenuKey), findsNothing);
      expect(folded(tester), isTrue);
      expect(places(tester).keys, <Key>[
        AdaptiveShell.columnTabKey(0),
        AdaptiveShell.railOverflowKey,
      ]);
      expect(fold.people.last, abovePlace(before, bottom));
      expect(fold.others.last, 0);

      // Back the same way: People up to its place, the rest fading in.
      final ({List<Rect> people, List<double> others}) unfold = await folding(
        tester,
        h.delegate.pop,
        before,
        more: more,
        selected: 0,
      );
      expect(unfold.people.last, before[AdaptiveShell.columnTabKey(0)]);
      expect(unfold.others.last, 1);
      expect(places(tester), before);
      expect(folded(tester), isFalse);
    });

    testWidgets('tabsFirst folds the tabs on the spot, and back', (
      WidgetTester tester,
    ) async {
      final List<PaneToolbarItem> many = <PaneToolbarItem>[
        for (final IconData icon in <IconData>[
          Icons.share,
          Icons.print,
          Icons.archive,
        ])
          toolbarItem(icon),
      ];
      final DemoHarness h = await pump(
        tester,
        duoPose(5),
        detailChrome: DetailChrome.kept,
        screens: (DemoRoute route, Widget screen) => switch (route) {
          DemoDetail() => ToolbarScreen(
            title: 'Detail',
            groups: <List<PaneToolbarItem>>[many],
            compression: VerticalBarCompression.tabsFirst,
          ),
          _ => _BranchToolbar(title: '$route'),
        },
      );
      final Map<Key, Rect> before = places(tester);
      final double bottom = duoColumn(duoPose(5)).end;
      // Seven tabs, all with a place: More comes in where the last is.
      expect(before.keys, isNot(contains(AdaptiveShell.railOverflowKey)));
      final Rect more = bottomButton(tester, before);
      final ({List<Rect> people, List<double> others}) fold = await folding(
        tester,
        () => h.delegate.push(const DemoDetail(1)),
        before,
        more: more,
        selected: 0,
      );
      // Seven tabs, 372, leave 501 − 372 − 12 = 117: room for Close and the
      // menu, which toolbarFirst would take, but not for Close and three
      // items (48 + 12 + 48 + 6 + 48 + 6 + 48 = 216); two places leave
      // 501 − 102 − 12 = 387.
      for (final IconData icon in <IconData>[
        Icons.close,
        Icons.share,
        Icons.print,
        Icons.archive,
      ]) {
        expect(
          find.descendant(
            of: find.byKey(AdaptiveShell.paneToolbarKey),
            matching: find.byIcon(icon),
          ),
          findsOneWidget,
        );
      }
      expect(folded(tester), isTrue);
      expect(fold.people.last, abovePlace(before, bottom));
      expect(places(tester)[AdaptiveShell.railOverflowKey], more);

      await folding(tester, h.delegate.pop, before, more: more, selected: 0);
      expect(places(tester), before);
      expect(folded(tester), isFalse);
    });

    testWidgets('a tab switch cross-fades the toolbar, on its own clock', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(1));
      h.delegate.goBranch(1);
      await tester.pump();
      await tester.pump();
      await tester.pump(kDefaultImmersiveDuration ~/ 2);
      // Both toolbars, the outgoing one fading out over the incoming one:
      // no route transition carries a tab switch.
      final Finder tabs = find.byKey(AdaptiveShell.columnTabsKey);
      final Iterable<double> fades = tester
          .renderObjectList<RenderDrivenBox>(
            find.descendant(
              of: find.byKey(AdaptiveShell.systemColumnKey),
              matching: find.byType(DrivenBox),
            ),
          )
          .where(
            (RenderDrivenBox b) => find
                .descendant(
                  of: tabs,
                  matching: find.byElementPredicate(
                    (Element e) => e.renderObject == b,
                  ),
                )
                .evaluate()
                .isEmpty,
          )
          .map((RenderDrivenBox b) => b.opacityNow)
          .where((double o) => o > 0 && o < 1);
      expect(fades, hasLength(2));
      await tester.pumpAndSettle();
    });
  });

  group('a new window size', () {
    testWidgets('changes the places at once, about the bottom edge', (
      WidgetTester tester,
    ) async {
      await pump(tester, duoPose(1), count: 10, screens: bare);
      expect(places(tester, 10), hasLength(8));
      final double top = places(tester, 10).values.first.top;

      // 120 points shorter: 340 − 12 for the tabs is six places. No route
      // transition carries a turn of the device or a new window size, so
      // the column takes it at once.
      setPose(
        tester,
        const Size(466, 558),
        padding: kDuoOuterPortraitPadding,
        display: kDuoOuterPortrait,
      );
      await tester.pump();
      final List<double> tops = <double>[];
      for (int i = 0; i < 30; i++) {
        expect(zone(tester).bottom, 558 - 24);
        expect(
          tester.getRect(find.byKey(AdaptiveShell.railOverflowKey)).bottom,
          558 - 24,
          reason: 'More stays at the bottom',
        );
        tops.add(tester.getRect(find.byKey(AdaptiveShell.columnTabKey(0))).top);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(places(tester, 10), hasLength(6));
      final double after = places(tester, 10).values.first.top;
      expect(after, isNot(top));
      expect(tops.toSet(), <double>{after}, reason: 'at once');
    });
  });

  group('the column\'s ends', () {
    // Safari on the simulator: the first button 24 below the status area,
    // or below the window's edge where the status area is at the bottom;
    // Settings: the last 24 above the window's edge, the home indicator's
    // inset included.
    for (final DuoPose pose in kDuoColumnPoses) {
      testWidgets('pose ${pose.number}', (WidgetTester tester) async {
        final DemoHarness h = await pump(
          tester,
          pose,
          count: 3,
          detailChrome: DetailChrome.kept,
        );
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();

        final ({double top, double end}) c = duoColumn(pose);
        expect(folded(tester), isFalse);
        final Rect close = tester.getRect(
          find.descendant(
            of: find.byKey(AdaptiveShell.paneToolbarKey),
            matching: find.byIcon(Icons.close),
          ),
        );
        expect(close.center.dy - kPaneToolbarItemExtent / 2, c.top);
        final double last = places(tester, 3).values
            .map((Rect r) => r.bottom)
            .reduce((double a, double b) => a > b ? a : b);
        expect(last, c.end);
        // On the glyphs' axis.
        expect(
          close.center.dx,
          pose.system.verticalBar == ChromePlacement.left
              ? 48
              : pose.window.width - 48,
        );
      });
    }
  });

  group('screens are not built for the column', () {
    for (final VerticalBarCompression compression
        in VerticalBarCompression.values) {
      testWidgets('${compression.name}: switching tabs, opening and closing '
          'a detail, folding', (WidgetTester tester) async {
        final List<DemoRoute> built = <DemoRoute>[];
        // tabsFirst folds for a long toolbar where there is room for Close
        // and the menu; toolbarFirst for any button in a short column.
        final bool tall = compression == VerticalBarCompression.tabsFirst;
        final DemoHarness h = await pump(
          tester,
          duoPose(tall ? 5 : 2),
          detailChrome: DetailChrome.kept,
          screens: (DemoRoute route, Widget screen) => switch (route) {
            DemoDetail(:final int id) => ToolbarScreen(
              title: 'Detail $id',
              groups: <List<PaneToolbarItem>>[
                <PaneToolbarItem>[
                  for (final IconData icon in <IconData>[
                    Icons.share,
                    Icons.print,
                    Icons.archive,
                    Icons.delete,
                  ])
                    toolbarItem(icon),
                ],
              ],
              compression: compression,
              onBuild: () => built.add(route),
            ),
            _ => _OneButton(
              title: '$route',
              count: tabs,
              onBuild: () => built.add(route),
            ),
          },
        );
        // Every tab once, so that each branch's screen exists.
        for (int b = 0; b < tabs; b++) {
          h.delegate.goBranch(b);
          await tester.pumpAndSettle();
        }
        h.delegate.goBranch(0);
        await tester.pumpAndSettle();

        Future<void> quiet(void Function() change) async {
          change();
          // The frame of the change builds what changed, and the next one
          // what registered after it; nothing after that.
          await tester.pump();
          await tester.pump();
          built.clear();
          for (int i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pumpAndSettle();
          expect(built, isEmpty);
        }

        for (int b = 1; b < tabs; b++) {
          await quiet(() => h.delegate.goBranch(b));
          if (!tall && (b == 1 || b == tabs - 1)) {
            expect(folded(tester), isTrue, reason: 'tab $b');
          }
        }
        await quiet(() => h.delegate.goBranch(0));
        expect(folded(tester), isFalse);
        // The detail's toolbar folds the tabs, and closing it unfolds them.
        await quiet(() => h.delegate.push(const DemoDetail(1)));
        expect(folded(tester), isTrue);
        await quiet(h.delegate.pop);
        expect(folded(tester), isFalse);
      });
    }
  });
}
