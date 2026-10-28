import 'dart:async';

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// Every place the shell draws a destination, set up with [branch] active.
/// [tap] taps a branch's destination there, the way a user reaches it.
typedef _Surface = ({
  String name,
  int branch,
  int other,
  Future<DemoHarness> Function(
    WidgetTester tester,
    BranchReselect reselect,
    BranchReselectCallback onReselect,
  )
  pump,
  Future<void> Function(WidgetTester tester, int branch) tap,
});

/// Roots with no buttons, and a detail with Close and Edit, as in
/// `system_column_test.dart`: Close and Edit fit beside five tabs upright on
/// the outer display, not turned.
Widget _bare(DemoRoute route, Widget screen) => switch (route) {
  DemoDetail(:final int id) => ToolbarScreen(
    title: 'Detail $id',
    pinned: <PaneToolbarItem>[toolbarItem(Icons.edit)],
  ),
  _ => ToolbarScreen(title: '$route'),
};

/// [_bare], with a toolbar on People's root that folds the tabs rather than
/// go behind its menu, so that turned the column folds at the root too, not
/// only under a detail.
Widget _heavyRoot(DemoRoute route, Widget screen) => switch (route) {
  DemoList() => ToolbarScreen(
    title: '$route',
    compression: VerticalBarCompression.tabsFirst,
    groups: <List<PaneToolbarItem>>[
      <PaneToolbarItem>[
        toolbarItem(Icons.edit),
        toolbarItem(Icons.share),
        toolbarItem(Icons.print),
        toolbarItem(Icons.archive),
      ],
    ],
  ),
  _ => _bare(route, screen),
};

Future<DemoHarness> _pumpWindow(
  WidgetTester tester,
  Size window,
  DemoHarness h,
  int branch,
) async {
  addTearDown(tester.view.reset);
  setWindow(tester, window);
  await tester.pumpWidget(h.app());
  await tester.pumpAndSettle();
  await h.delegate.goBranch(branch);
  await tester.pumpAndSettle();
  return h;
}

Future<DemoHarness> _pumpDuo(
  WidgetTester tester,
  DuoPose pose,
  int count,
  int branch,
  BranchReselect reselect,
  BranchReselectCallback onReselect, {
  Widget Function(DemoRoute, Widget) screens = _bare,
}) async {
  addTearDown(tester.view.reset);
  setPose(tester, pose.window, padding: pose.padding, display: pose.display);
  final DemoHarness h = DemoHarness(
    system: pose.system,
    extraBranches: count - 2,
    extraLabel: (int i) => 'Tab $i',
    masterMinWidth: 270,
    detailMinWidth: 270,
    detailChrome: DetailChrome.kept,
    platform: TargetPlatform.iOS,
    wrapPage: screens,
    reselect: reselect,
    onReselect: onReselect,
  );
  await tester.pumpWidget(h.app());
  await tester.pumpAndSettle();
  await h.delegate.goBranch(branch);
  await tester.pumpAndSettle();
  return h;
}

Future<void> _tapIn(WidgetTester tester, Type chrome, IconData icon) async {
  await tester.tap(
    find.descendant(of: find.byType(chrome), matching: find.byIcon(icon)),
  );
  await tester.pumpAndSettle();
}

/// Opens a More or overflow menu and picks [label] from it; [ticked] checks
/// first that the item carries More's tick.
Future<void> _pickFromMenu(
  WidgetTester tester,
  String label, {
  bool ticked = false,
}) async {
  await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
  await tester.pumpAndSettle();
  final Finder item = find.widgetWithText(MenuItemButton, label);
  if (ticked) {
    expect(
      find.descendant(of: item, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  }
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

final List<_Surface> _surfaces = <_Surface>[
  (
    name: 'the bottom bar',
    branch: 1,
    other: 0,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpWindow(
          tester,
          kCompact,
          DemoHarness(reselect: r, onReselect: cb),
          1,
        ),
    tap: (WidgetTester tester, int b) =>
        _tapIn(tester, NavigationBar, b == 0 ? Icons.people : Icons.home),
  ),
  (
    name: 'the rail, a master-detail branch',
    branch: 0,
    other: 1,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpWindow(tester, kWide, DemoHarness(reselect: r, onReselect: cb), 0),
    tap: (WidgetTester tester, int b) =>
        _tapIn(tester, NavigationRail, b == 0 ? Icons.people : Icons.home),
  ),
  (
    name: 'the rail\'s overflow menu',
    branch: 11,
    other: 10,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpWindow(
          tester,
          const Size(900, 474),
          DemoHarness(extraBranches: 10, reselect: r, onReselect: cb),
          11,
        ),
    tap: (WidgetTester tester, int b) =>
        _pickFromMenu(tester, 'Extra ${b - 2}'),
  ),
  (
    name: 'the system column, every tab in place',
    branch: 0,
    other: 1,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpDuo(tester, duoPose(1), 5, 0, r, cb),
    tap: (WidgetTester tester, int b) async {
      await tester.tap(find.byKey(AdaptiveShell.columnTabKey(b)));
      await tester.pumpAndSettle();
    },
  ),
  (
    name: 'the system column folded: the selected tab',
    branch: 0,
    other: 1,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpDuo(tester, duoPose(2), 5, 0, r, cb),
    tap: (WidgetTester tester, int b) async {
      if (b != 0 &&
          find.byKey(AdaptiveShell.railCollapsedKey).evaluate().isNotEmpty) {
        // Folded, the other tabs are behind More.
        await _pickFromMenu(tester, 'Home');
        return;
      }
      await tester.tap(find.byKey(AdaptiveShell.columnTabKey(b)));
      await tester.pumpAndSettle();
    },
  ),
  (
    name: 'the system column folded: the ticked tab in More',
    branch: 0,
    other: 1,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpDuo(tester, duoPose(2), 5, 0, r, cb, screens: _heavyRoot),
    tap: (WidgetTester tester, int b) =>
        _pickFromMenu(tester, b == 0 ? 'People' : 'Home', ticked: b == 0),
  ),
  (
    name: 'the system column\'s More, a hidden tab ticked',
    branch: 9,
    other: 8,
    pump: (WidgetTester tester, BranchReselect r, BranchReselectCallback cb) =>
        _pumpDuo(tester, duoPose(1), 10, 9, r, cb),
    tap: (WidgetTester tester, int b) =>
        _pickFromMenu(tester, 'Tab ${b - 2}', ticked: b == 9),
  ),
];

/// Tapping the active destination again goes back to the branch root, as
/// `UITabBarController` does, wherever the shell draws that destination, and
/// tells the app either way.
void main() {
  for (final _Surface s in _surfaces) {
    group(s.name, () {
      late List<(int, bool)> calls;
      late DemoHarness h;

      Future<void> pump(
        WidgetTester tester, {
        BranchReselect reselect = BranchReselect.popToRoot,
      }) async {
        calls = <(int, bool)>[];
        h = await s.pump(
          tester,
          reselect,
          (int branch, bool popped) => calls.add((branch, popped)),
        );
        expect(h.delegate.state.activeBranch, s.branch);
      }

      List<NavEntry<DemoRoute>> entries() =>
          h.delegate.state.branches[s.branch].entries;

      Future<void> open(WidgetTester tester, {NavExitGuard? onExit}) async {
        unawaited(h.delegate.push(const DemoDetail(1), onExit: onExit));
        await tester.pumpAndSettle();
        expect(entries(), hasLength(2));
      }

      testWidgets('with a stack: back to the root, popped', (
        WidgetTester tester,
      ) async {
        await pump(tester);
        await open(tester);
        if (s.name.contains('folded')) {
          expect(
            find.byKey(AdaptiveShell.railCollapsedKey),
            findsOneWidget,
            reason: 'the detail\'s toolbar folds the tabs',
          );
        }

        await s.tap(tester, s.branch);

        expect(h.delegate.state.activeBranch, s.branch);
        expect(entries(), hasLength(1));
        expect(find.text('Detail 1'), findsNothing);
        expect(calls, <(int, bool)>[(s.branch, true)]);
      });

      testWidgets('at the root: nothing changes, not popped', (
        WidgetTester tester,
      ) async {
        await pump(tester);
        final NavState<DemoRoute> before = h.delegate.state;

        await s.tap(tester, s.branch);

        expect(identical(h.delegate.state, before), isTrue);
        expect(calls, <(int, bool)>[(s.branch, false)]);
      });

      testWidgets('a refusing guard: the stack stays, not popped', (
        WidgetTester tester,
      ) async {
        await pump(tester);
        int asked = 0;
        await open(
          tester,
          onExit: () async {
            asked++;
            return false;
          },
        );
        final List<NavEntry<DemoRoute>> before = entries();

        await s.tap(tester, s.branch);

        expect(asked, 1);
        expect(entries(), same(before));
        expect(calls, <(int, bool)>[(s.branch, false)]);
      });

      testWidgets('BranchReselect.none: the stack stays, onReselect called', (
        WidgetTester tester,
      ) async {
        await pump(tester, reselect: BranchReselect.none);
        await open(tester);
        final List<NavEntry<DemoRoute>> before = entries();

        await s.tap(tester, s.branch);

        expect(entries(), same(before));
        expect(calls, <(int, bool)>[(s.branch, false)]);
      });

      testWidgets('another destination: a switch, no onReselect', (
        WidgetTester tester,
      ) async {
        await pump(tester);
        await open(tester);

        await s.tap(tester, s.other);

        expect(h.delegate.state.activeBranch, s.other);
        expect(entries(), hasLength(2));
        expect(calls, isEmpty);
      });
    });
  }

  group('builders', () {
    for (final (String name, Size window, bool rail) in <(String, Size, bool)>[
      ('barBuilder', kCompact, false),
      ('railBuilder', kWide, true),
    ]) {
      testWidgets('$name: onSelectBranch with the active branch reselects', (
        WidgetTester tester,
      ) async {
        final List<(int, bool)> calls = <(int, bool)>[];
        Widget chrome(BuildContext context, int active, ValueChanged<int> on) =>
            SizedBox(
              width: rail ? kDefaultRailWidth : null,
              height: rail ? null : 80,
              child: TextButton(
                key: const ValueKey<String>('custom-active'),
                onPressed: () => on(active),
                child: const Text('again'),
              ),
            );
        final DemoHarness h = DemoHarness(
          barBuilder: rail ? null : chrome,
          railBuilder: rail ? chrome : null,
          onReselect: (int branch, bool popped) => calls.add((branch, popped)),
        );
        await _pumpWindow(tester, window, h, 1);
        unawaited(h.delegate.push(const DemoDetail(1)));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('custom-active')));
        await tester.pumpAndSettle();

        expect(h.delegate.state.branches[1].entries, hasLength(1));
        expect(calls, <(int, bool)>[(1, true)]);
      });
    }
  });

  testWidgets('goBranch with the active branch is not a tap', (
    WidgetTester tester,
  ) async {
    final List<(int, bool)> calls = <(int, bool)>[];
    final DemoHarness h = DemoHarness(
      onReselect: (int branch, bool popped) => calls.add((branch, popped)),
    );
    await _pumpWindow(tester, kCompact, h, 1);
    unawaited(h.delegate.push(const DemoDetail(1)));
    await tester.pumpAndSettle();

    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();

    expect(h.delegate.state.branches[1].entries, hasLength(2));
    expect(calls, isEmpty);
  });
}
