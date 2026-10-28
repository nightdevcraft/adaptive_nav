import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// `PaneToolbar`: a header everywhere, and on iPhone Duo a column beside the
/// system's bar — the shell's to draw, in the order Apple gives it: status
/// area, navigation, the pinned action, the other groups, the rail.
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

  Finder inColumn(Finder matching) => find.descendant(
    of: find.byKey(AdaptiveShell.paneToolbarKey),
    matching: matching,
  );

  Finder inHeader(Finder matching) =>
      find.descendant(of: find.byType(AppBar), matching: matching);

  Future<DemoHarness> pump(
    WidgetTester tester,
    Size window,
    EdgeInsets padding, {
    Size? display,
    SystemGeometry? system,
    Widget Function(DemoRoute, Widget)? screens,
    int extraBranches = 0,
    String Function(int i)? extraLabel,
    bool withDetail = true,
    ChromeLayout chromeLayout = defaultChromeLayout,
    DetailChrome detailChrome = DetailChrome.kept,
    NavigationRailLabelType railLabelsInColumn = NavigationRailLabelType.none,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, window, padding: padding, display: display);
    // The tabs kept beside the open detail, on iOS, so that the toolbar and
    // the tabs share the column. `DetailChrome.covered` has a group of its
    // own.
    final DemoHarness h = DemoHarness(
      system: system,
      wrapPage: screens ?? toolbarScreens(),
      extraBranches: extraBranches,
      extraLabel: extraLabel,
      chromeLayout: chromeLayout,
      detailChrome: detailChrome,
      platform: detailChrome == DetailChrome.kept ? TargetPlatform.iOS : null,
      railLabelsInColumn: railLabelsInColumn,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    if (withDetail) {
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
    }
    return h;
  }

  group('the column, top to bottom', () {
    testWidgets('outer display: status area, Close, Edit, then the rail', (
      WidgetTester tester,
    ) async {
      await pump(tester, kDuoOuterPortrait, kDuoOuterPortraitPadding);

      final Rect close = tester.getRect(inColumn(find.byIcon(Icons.close)));
      final Rect edit = tester.getRect(inColumn(find.byIcon(Icons.edit)));
      final Rect tabs = tester.getRect(
        find.byKey(AdaptiveShell.columnTabKey(0)),
      );
      expect(close.top, greaterThanOrEqualTo(170), reason: 'below the clock');
      expect(edit.top, greaterThanOrEqualTo(close.bottom));
      expect(tabs.top, greaterThanOrEqualTo(edit.bottom));
      // On the column's axis, 48 in from the edge.
      expect(close.center.dx, kDuoOuterPortrait.width - 48);
      expect(edit.center.dx, kDuoOuterPortrait.width - 48);
      // And not in the header.
      expect(inHeader(find.byIcon(Icons.close)), findsNothing);
      expect(inHeader(find.byIcon(Icons.edit)), findsNothing);
      expect(inHeader(find.byType(BackButton)), findsNothing);
    });

    // Safari's buttons on the simulator: circles of 48, 12 apart, 6 within
    // a group; the first 24 below the status area.
    testWidgets('one item every 48, 6 within a group and 12 between', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoOuterPortrait,
        kDuoOuterPortraitPadding,
        screens: toolbarScreens(
          detailPinned: <PaneToolbarItem>[
            toolbarItem(Icons.edit),
            toolbarItem(Icons.check),
          ],
          detailGroups: <List<PaneToolbarItem>>[
            <PaneToolbarItem>[toolbarItem(Icons.share)],
          ],
        ),
      );

      double centre(IconData icon) =>
          tester.getCenter(inColumn(find.byIcon(icon))).dy;
      expect(
        centre(Icons.close),
        170 +
            SystemBarMetrics.measured.columnInset +
            kPaneToolbarItemExtent / 2,
      );
      expect(
        centre(Icons.edit) - centre(Icons.close),
        kPaneToolbarItemExtent + kPaneToolbarGroupGap,
        reason: 'the navigation button is a group of its own',
      );
      expect(
        centre(Icons.check) - centre(Icons.edit),
        kPaneToolbarItemExtent + kPaneToolbarItemGap,
      );
      expect(
        centre(Icons.share) - centre(Icons.check),
        kPaneToolbarItemExtent + kPaneToolbarGroupGap,
      );
    });

    testWidgets('Split View, left: at the top, out of the rounded corner', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoSplit,
        kDuoSplitLeftPadding,
        display: kDuoInnerLandscape,
        system: const SystemGeometry(verticalBar: ChromePlacement.left),
      );

      final Rect close = tester.getRect(inColumn(find.byIcon(Icons.close)));
      expect(close.top, greaterThanOrEqualTo(24));
      expect(close.center.dx, lessThan(kDefaultRailWidth));
      expect(
        tester.getRect(find.byKey(AdaptiveShell.columnTabKey(0))).top,
        greaterThanOrEqualTo(
          tester.getRect(inColumn(find.byIcon(Icons.edit))).bottom,
        ),
      );
    });

    testWidgets('the screen on top of the pane is the one in the column', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        kDuoOuterPortrait,
        kDuoOuterPortraitPadding,
        screens: (DemoRoute route, Widget screen) => switch (route) {
          DemoEdit() => ToolbarScreen(
            title: 'Edit',
            pinned: <PaneToolbarItem>[toolbarItem(Icons.check)],
          ),
          _ => toolbarScreens()(route, screen),
        },
      );

      h.delegate.push(const DemoEdit(1));
      await tester.pumpAndSettle();
      // The editor's Back and Done; the detail's Edit is gone with it.
      expect(inColumn(find.byIcon(Icons.arrow_back)), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.check)), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.edit)), findsNothing);

      // Back pops the pane's navigator, as an `AppBar`'s would.
      await tester.tap(inColumn(find.byIcon(Icons.arrow_back)));
      await tester.pumpAndSettle();
      expect(h.delegate.state.active.entries.length, 2);
      expect(inColumn(find.byIcon(Icons.close)), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.edit)), findsOneWidget);

      await tester.tap(inColumn(find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(h.delegate.state.active.entries.length, 1);
      // The list is a root: nothing to go back to, and only the tabs in the
      // column.
      expect(inColumn(find.byIcon(Icons.close)), findsNothing);
      expect(inColumn(find.byIcon(Icons.arrow_back)), findsNothing);
      expect(
        inColumn(find.byKey(AdaptiveShell.paneToolbarMenuKey)),
        findsNothing,
      );
    });

    testWidgets('a word stays in the header, and so does horizontalOnly', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoOuterPortrait,
        kDuoOuterPortraitPadding,
        screens: toolbarScreens(
          detailPinned: <PaneToolbarItem>[
            PaneToolbarItem(label: 'Save', onPressed: () {}),
            toolbarItem(Icons.share, horizontalOnly: true),
            toolbarItem(Icons.edit),
          ],
        ),
      );

      expect(inHeader(find.text('Save')), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.share)), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.edit)), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.edit)), findsNothing);
    });

    testWidgets('the rail is not in the column: the toolbar has it alone', (
      WidgetTester tester,
    ) async {
      // A layout that keeps the rail on the left of the inner display, away
      // from the system's column.
      await pump(
        tester,
        kDuoInnerLandscape,
        kDuoInnerLandscapePadding,
        system: const SystemGeometry(
          verticalBar: ChromePlacement.right,
          statusArea: Rect.fromLTRB(867, 0, 951, 120),
        ),
        chromeLayout: (Size _, EdgeInsets _, SystemGeometry? _) =>
            ChromePlacement.left,
      );

      expect(tester.getRect(find.byType(NavigationRail)).left, 0);
      final Rect close = tester.getRect(find.byIcon(Icons.close).last);
      expect(close.center.dx, kDuoInnerLandscape.width - 48);
      expect(close.top, greaterThanOrEqualTo(120));
      expect(inHeader(find.byIcon(Icons.close)), findsNothing);
      expect(inHeader(find.byIcon(Icons.edit)), findsNothing);
    });
  });

  group('who gives way on a short column', () {
    // Outer display turned left: 466 tall less 82 of status area is a column
    // of 384, and its inset of 24 at either end leaves 336. People and Home
    // take 48 + 6 + 48 = 102 at the bottom, and 12 more apart from the
    // toolbar: 222 for it. Close, Edit, then Share, Print and Archive in one
    // group: 48 + 12 + 48 + 12 + 48 + 6 + 48 + 6 + 48 = 276.
    final List<List<PaneToolbarItem>> groups = <List<PaneToolbarItem>>[
      <PaneToolbarItem>[
        toolbarItem(Icons.share, priority: 1),
        toolbarItem(Icons.print),
        toolbarItem(Icons.archive),
      ],
    ];
    const SystemGeometry outerLeft = SystemGeometry(
      verticalBar: ChromePlacement.left,
      statusArea: Rect.fromLTRB(0, 0, 84, 82),
    );

    testWidgets('toolbarFirst: items go behind the toolbar\'s menu, the tabs '
        'stay', (WidgetTester tester) async {
      final List<String> errors = await errorsDuring(() async {
        await pump(
          tester,
          kDuoOuterLandscape,
          kDuoOuterLandscapePadding,
          system: outerLeft,
          screens: toolbarScreens(detailGroups: groups),
        );
      });

      expect(errors, isEmpty);
      // Archive goes, then Print (the last of equals first), then Edit:
      // Share has the higher priority. Close, Share and the menu, 12 apart:
      // 168.
      expect(inColumn(find.byIcon(Icons.close)), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.share)), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.edit)), findsNothing);
      expect(inColumn(find.byIcon(Icons.print)), findsNothing);
      expect(inColumn(find.byIcon(Icons.archive)), findsNothing);
      for (final int tab in <int>[0, 1]) {
        expect(find.byKey(AdaptiveShell.columnTabKey(tab)), findsOneWidget);
      }
      expect(find.byKey(AdaptiveShell.railOverflowKey), findsNothing);
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsNothing);

      // The toolbar's menu has the toolbar's items, and nothing else.
      await tester.tap(find.byKey(AdaptiveShell.paneToolbarMenuKey));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('item ${Icons.print.codePoint}'), findsOneWidget);
      expect(find.text('item ${Icons.archive.codePoint}'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
      expect(find.byType(MenuItemButton), findsNWidgets(3));
    });

    testWidgets('tabsFirst: two tabs fold to More alone, the toolbar stays', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        kDuoOuterLandscape,
        kDuoOuterLandscapePadding,
        system: outerLeft,
        screens: toolbarScreens(
          detailGroups: groups,
          compression: VerticalBarCompression.tabsFirst,
        ),
      );

      // Two places folded to two would leave the toolbar nothing more: More
      // alone does. 336 less its 48 and the gap: 276 holds all 276.
      for (final IconData icon in <IconData>[
        Icons.close,
        Icons.edit,
        Icons.share,
        Icons.print,
        Icons.archive,
      ]) {
        expect(inColumn(find.byIcon(icon)), findsOneWidget);
      }
      expect(find.byKey(AdaptiveShell.paneToolbarMenuKey), findsNothing);
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsOneWidget);
      expect(find.byKey(AdaptiveShell.columnTabKey(0)), findsNothing);
      final Finder more = find.byKey(AdaptiveShell.railOverflowKey);
      // At the bottom of the column, where the last tab was.
      expect(
        tester.getCenter(more).dy,
        kDuoOuterLandscape.height -
            SystemBarMetrics.measured.columnInset -
            kPaneToolbarItemExtent / 2,
      );

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);
    });

    testWidgets('tabsFirst folds only when the toolbar does not fit', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoOuterLandscape,
        kDuoOuterLandscapePadding,
        system: outerLeft,
        screens: toolbarScreens(compression: VerticalBarCompression.tabsFirst),
      );

      // Close and Edit, 108, fit beside the tabs.
      expect(
        find.byKey(AdaptiveShell.columnTabKey(0)).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsNothing);
    });

    testWidgets('the branch decides unless the screen says otherwise', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterLandscape, padding: kDuoOuterLandscapePadding);
      final DemoHarness h = DemoHarness(
        system: outerLeft,
        verticalCompression: VerticalBarCompression.tabsFirst,
        wrapPage: toolbarScreens(detailGroups: groups),
        detailChrome: DetailChrome.kept,
        platform: TargetPlatform.iOS,
      );
      await tester.pumpWidget(h.app());
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsOneWidget);
      expect(inColumn(find.byIcon(Icons.print)), findsOneWidget);
    });

    testWidgets('no height overflows the column, either way', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      for (final double height in <double>[300, 400, 466, 678, 951]) {
        for (final int extra in <int>[0, 3, 10]) {
          for (final (VerticalBarCompression compression, DetailChrome mode)
              in <(VerticalBarCompression, DetailChrome)>[
                for (final VerticalBarCompression c
                    in VerticalBarCompression.values)
                  for (final DetailChrome m in DetailChrome.values) (c, m),
              ]) {
            setPose(
              tester,
              Size(678, height),
              padding: kDuoOuterLandscapePadding,
              display: kDuoOuterLandscape,
            );
            final DemoHarness h = DemoHarness(
              extraBranches: extra,
              wrapPage: toolbarScreens(
                detailGroups: groups,
                compression: compression,
              ),
              detailChrome: mode,
              platform: TargetPlatform.iOS,
            );
            final List<String> errors = await errorsDuring(() async {
              await tester.pumpWidget(h.app());
              h.delegate.push(const DemoDetail(1));
              await tester.pumpAndSettle();
            });
            expect(
              errors,
              isEmpty,
              reason:
                  'height $height, ${extra + 2} destinations, $compression, '
                  '${mode.name}',
            );
          }
        }
      }
    });
  });

  // The default: an open detail over the single pane covers the rail. On
  // the outer display the column keeps the status area and the detail's
  // toolbar, which then has all of it.
  group('a detail that covers the rail', () {
    const SystemGeometry outerRight = SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(594, 384, 678, 466),
    );
    final List<List<PaneToolbarItem>> groups = <List<PaneToolbarItem>>[
      <PaneToolbarItem>[toolbarItem(Icons.share), toolbarItem(Icons.print)],
      <PaneToolbarItem>[toolbarItem(Icons.archive), toolbarItem(Icons.delete)],
    ];

    testWidgets('outer display: status area, then the toolbar, alone', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        kDuoOuterPortrait,
        kDuoOuterPortraitPadding,
        detailChrome: DetailChrome.covered,
      );

      final Rect close = tester.getRect(inColumn(find.byIcon(Icons.close)));
      final Rect edit = tester.getRect(inColumn(find.byIcon(Icons.edit)));
      // The first 24 below the status area, the next after a gap.
      expect(close.center.dy, 170 + 24 + kPaneToolbarItemExtent / 2);
      expect(
        edit.center.dy - close.center.dy,
        kPaneToolbarItemExtent + kPaneToolbarGroupGap,
      );
      expect(close.center.dx, kDuoOuterPortrait.width - 48);
      expect(inColumn(find.byKey(AdaptiveShell.columnTabKey(1))), findsNothing);
      expect(inHeader(find.byIcon(Icons.edit)), findsNothing);

      // The tabs have gone, under the detail; where they were, the detail
      // takes the tap.
      expect(find.byIcon(Icons.home), findsNothing);
      final Offset tabs = tester.getCenter(
        find.byKey(AdaptiveShell.columnTabsKey),
      );
      expect(tabs.dx, greaterThan(kDuoOuterPortrait.width - 89));
      await tester.tapAt(tabs);
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 0);

      // Closed, the tabs are back in the column and in use.
      await tester.tap(inColumn(find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(find.byKey(AdaptiveShell.columnTabKey(1)), findsOneWidget);
      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);
    });

    testWidgets('the whole column: what toolbarFirst hid beside the rail '
        'fits', (WidgetTester tester) async {
      await pump(
        tester,
        kDuoOuterLandscape,
        kDuoOuterLandscapePadding,
        system: const SystemGeometry(
          verticalBar: ChromePlacement.left,
          statusArea: Rect.fromLTRB(0, 0, 84, 82),
        ),
        screens: toolbarScreens(detailGroups: groups),
        detailChrome: DetailChrome.covered,
      );

      // 336 of toolbar in 466 − 82 − 24 − 24 = 336.
      for (final IconData icon in <IconData>[
        Icons.close,
        Icons.edit,
        Icons.share,
        Icons.print,
        Icons.archive,
        Icons.delete,
      ]) {
        expect(inColumn(find.byIcon(icon)), findsOneWidget);
      }
      expect(find.byKey(AdaptiveShell.railOverflowKey), findsNothing);
    });

    testWidgets('status area at the bottom: 24 from the top, above it', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoOuterLandscape,
        kDuoOuterLandscapeRightPadding,
        system: outerRight,
        detailChrome: DetailChrome.covered,
      );

      final Rect close = tester.getRect(inColumn(find.byIcon(Icons.close)));
      final Rect edit = tester.getRect(inColumn(find.byIcon(Icons.edit)));
      expect(
        close.center.dy,
        SystemBarMetrics.measured.columnInset + kPaneToolbarItemExtent / 2,
      );
      expect(
        edit.center.dy + kPaneToolbarItemExtent / 2,
        lessThanOrEqualTo(384 - 24),
      );
      expect(close.center.dx, kDuoOuterLandscape.width - 48);
    });
  });

  // Nothing of the system's at the top of the column (the status area at its
  // bottom): the first item is held 24 from the window's edge, as a bare
  // column's is. Where the status area is at the top it is 24 below it — Safari
  // on the simulator.
  group('the column\'s first item', () {
    testWidgets('3: 24 down, the tabs kept', (WidgetTester tester) async {
      await pump(
        tester,
        kDuoOuterLandscape,
        kDuoOuterLandscapeRightPadding,
        system: const SystemGeometry(
          verticalBar: ChromePlacement.right,
          statusArea: Rect.fromLTRB(594, 384, 678, 466),
        ),
      );

      expect(
        tester.getCenter(inColumn(find.byIcon(Icons.close))).dy,
        24 + kPaneToolbarItemExtent / 2,
      );
      // The tabs end 24 above the status area.
      expect(
        tester.getRect(find.byKey(AdaptiveShell.columnTabKey(1))).bottom,
        384 - 24,
      );
    });

    testWidgets('2, the mirror: 24 below the status area', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kDuoOuterLandscape,
        kDuoOuterLandscapePadding,
        system: const SystemGeometry(
          verticalBar: ChromePlacement.left,
          statusArea: Rect.fromLTRB(0, 0, 84, 82),
        ),
      );

      expect(
        tester.getCenter(inColumn(find.byIcon(Icons.close))).dy,
        82 + 24 + kPaneToolbarItemExtent / 2,
      );
      // The tabs end 24 above the window's edge, inside the home indicator.
      expect(
        tester.getRect(find.byKey(AdaptiveShell.columnTabKey(1))).bottom,
        466 - 24,
      );
    });
  });

  group('the pinned action', () {
    void expectTinted(WidgetTester tester, Finder icon) {
      final Finder button = find.ancestor(
        of: icon,
        matching: find.byType(IconButton),
      );
      final ColorScheme scheme = Theme.of(tester.element(button)).colorScheme;
      final Color? fill = tester
          .widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)).first,
          )
          .color;
      expect(fill == null || fill.a == 0, isTrue, reason: 'no fill');
      expect(
        tester
            .widget<RichText>(
              find.descendant(of: icon, matching: find.byType(RichText)),
            )
            .text
            .style
            ?.color,
        scheme.primary,
      );
    }

    testWidgets('in the column', (WidgetTester tester) async {
      await pump(tester, kDuoOuterPortrait, kDuoOuterPortraitPadding);

      expectTinted(tester, inColumn(find.byIcon(Icons.edit)));
      // Close is not an action of the screen's: plain.
      final Finder close = inColumn(find.byIcon(Icons.close));
      expect(
        tester
            .widget<RichText>(
              find.descendant(of: close, matching: find.byType(RichText)),
            )
            .text
            .style
            ?.color,
        isNot(Theme.of(tester.element(close)).colorScheme.primary),
      );
    });

    testWidgets('in the header, the same', (WidgetTester tester) async {
      await pump(tester, kWide, EdgeInsets.zero);

      expectTinted(tester, inHeader(find.byIcon(Icons.edit)));
    });
  });

  group('screens are not built for the animation', () {
    testWidgets('a new screen in the column', (WidgetTester tester) async {
      int builds = 0;
      final DemoHarness h = await pump(
        tester,
        kDuoOuterPortrait,
        kDuoOuterPortraitPadding,
        screens: toolbarScreens(onDetailBuild: () => builds++),
      );
      h.delegate.resetDetailTo(const DemoDetail(2));
      await tester.pump();
      builds = 0;

      await tester.pumpAndSettle();
      expect(builds, 0);
    });

    testWidgets('from the header to the column', (WidgetTester tester) async {
      int builds = 0;
      await pump(
        tester,
        kDuoInnerPortrait,
        kDuoInnerPortraitPadding,
        screens: toolbarScreens(onDetailBuild: () => builds++),
      );
      expect(inHeader(find.byIcon(Icons.edit)), findsOneWidget);

      setPose(tester, kDuoInnerLandscape, padding: kDuoInnerLandscapePadding);
      await tester.pump();
      await tester.pump();
      builds = 0;
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(builds, 0);
      expect(inColumn(find.byIcon(Icons.edit)), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.edit)), findsNothing);
    });
  });

  group('everywhere else it is a header, as before', () {
    for (final (String name, Size size, EdgeInsets padding)
        in <(String, Size, EdgeInsets)>[
          ('phone', kCompact, const EdgeInsets.only(top: 47, bottom: 34)),
          ('tablet', const Size(1024, 768), const EdgeInsets.only(top: 24)),
          ('desktop', kWide, EdgeInsets.zero),
          ('Duo, inner portrait', kDuoInnerPortrait, kDuoInnerPortraitPadding),
        ]) {
      testWidgets(name, (WidgetTester tester) async {
        await pump(tester, size, padding);

        expect(find.byKey(AdaptiveShell.paneToolbarKey), findsNothing);
        expect(inHeader(find.byIcon(Icons.close)), findsOneWidget);
        expect(inHeader(find.byIcon(Icons.edit)), findsOneWidget);
        final Element detail = tester.element(find.text('Detail 1 body'));
        expect(PaneBarScope.of(detail).isVertical, isFalse);
      });
    }

    testWidgets('the header shows three and puts the rest behind a menu', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kWide,
        EdgeInsets.zero,
        screens: toolbarScreens(
          detailGroups: <List<PaneToolbarItem>>[
            <PaneToolbarItem>[
              toolbarItem(Icons.share),
              toolbarItem(Icons.print, priority: 1),
              toolbarItem(Icons.archive),
            ],
          ],
        ),
      );

      // Edit and Print by priority, then Share, the first of the rest.
      expect(inHeader(find.byIcon(Icons.share)), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.print)), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.edit)), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.archive)), findsNothing);
      await tester.tap(inHeader(find.byIcon(Icons.more_horiz)));
      await tester.pumpAndSettle();
      expect(find.text('item ${Icons.archive.codePoint}'), findsOneWidget);
    });
  });
}
