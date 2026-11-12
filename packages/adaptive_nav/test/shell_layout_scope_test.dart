import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `ShellLayoutScope`: which pane a screen is in and whether its branch's
/// detail has a pane of its own — the same decision the shell lays the panes
/// out by, not a second formula in the app.
void main() {
  ShellLayoutScope? scopeOf(WidgetTester tester, Finder screen) =>
      ShellLayoutScope.maybeOf(tester.element(screen));

  Future<DemoHarness> pump(WidgetTester tester, Size window) async {
    addTearDown(tester.view.reset);
    setWindow(tester, window);
    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('compact: a single pane under a bottom bar', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pump(tester, kCompact);

    final ShellLayoutScope master = scopeOf(
      tester,
      find.byType(DemoListScreen),
    )!;
    expect(master.pane, ShellPane.single);
    expect(master.detailInOwnPane, isFalse);
    expect(master.placement, ChromePlacement.bottom);

    // The detail navigator covers the same single pane.
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    final ShellLayoutScope detail = scopeOf(
      tester,
      find.byType(DemoDetailScreen),
    )!;
    expect(detail.pane, ShellPane.single);
    expect(detail.detailInOwnPane, isFalse);
    expect(detail.placement, ChromePlacement.bottom);
  });

  testWidgets('wide, master-detail that fits: master and detail panes', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pump(tester, kWide);
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    final ShellLayoutScope master = scopeOf(
      tester,
      find.byType(DemoListScreen),
    )!;
    expect(master.pane, ShellPane.master);
    expect(master.detailInOwnPane, isTrue);
    expect(master.placement, ChromePlacement.left);

    final ShellLayoutScope detail = scopeOf(
      tester,
      find.byType(DemoDetailScreen),
    )!;
    expect(detail.pane, ShellPane.detail);
    expect(detail.detailInOwnPane, isTrue);
    expect(detail.placement, ChromePlacement.left);
  });

  testWidgets('wide, master-detail that does not fit beside the rail', (
    WidgetTester tester,
  ) async {
    // A rail (600 and up), but 700 - 80 is short of 320 + 360.
    final DemoHarness h = await pump(tester, const Size(700, 900));
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    for (final Type screen in <Type>[DemoListScreen, DemoDetailScreen]) {
      final ShellLayoutScope scope = scopeOf(tester, find.byType(screen))!;
      expect(scope.placement, ChromePlacement.left);
      expect(scope.detailInOwnPane, isFalse, reason: '$screen');
      expect(scope.pane, ShellPane.single, reason: '$screen');
    }
    // Agrees with what the shell built: one pane, the detail over it.
    expect(
      DetailPaneScope.of(tester.element(find.byType(DemoDetailScreen))),
      isFalse,
    );
  });

  testWidgets('wide, a branch without master-detail', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pump(tester, kWide);
    h.delegate.goBranch(1);
    await tester.pumpAndSettle();

    final ShellLayoutScope home = scopeOf(tester, find.byType(DemoHomeScreen))!;
    expect(home.detailInOwnPane, isFalse);
    expect(home.pane, ShellPane.single);
    expect(home.placement, ChromePlacement.left);

    // The inactive master-detail branch keeps values of its own.
    final ShellLayoutScope list = scopeOf(
      tester,
      find.byType(DemoListScreen, skipOffstage: false),
    )!;
    expect(list.pane, ShellPane.master);
    expect(list.detailInOwnPane, isTrue);
  });

  testWidgets('a resize there and back changes the values, not the screen', (
    WidgetTester tester,
  ) async {
    final DemoHarness h = await pump(tester, kWide);
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    final State<StatefulWidget> listState = tester.state(
      find.byType(DemoListScreen),
    );
    final State<StatefulWidget> detailState = tester.state(
      find.byType(DemoDetailScreen),
    );
    expect(
      scopeOf(tester, find.byType(DemoListScreen))!.pane,
      ShellPane.master,
    );

    setWindow(tester, kCompact);
    await tester.pumpAndSettle();
    final ShellLayoutScope compact = scopeOf(
      tester,
      find.byType(DemoListScreen, skipOffstage: false),
    )!;
    expect(compact.pane, ShellPane.single);
    expect(compact.detailInOwnPane, isFalse);
    expect(compact.placement, ChromePlacement.bottom);
    expect(
      identical(
        tester.state(find.byType(DemoListScreen, skipOffstage: false)),
        listState,
      ),
      isTrue,
    );

    setWindow(tester, kWide);
    await tester.pumpAndSettle();
    final ShellLayoutScope wide = scopeOf(tester, find.byType(DemoListScreen))!;
    expect(wide.pane, ShellPane.master);
    expect(wide.detailInOwnPane, isTrue);
    expect(wide.placement, ChromePlacement.left);
    expect(
      identical(tester.state(find.byType(DemoListScreen)), listState),
      isTrue,
    );
    expect(
      identical(tester.state(find.byType(DemoDetailScreen)), detailState),
      isTrue,
    );
  });

  testWidgets('a dependent rebuilds when the values change', (
    WidgetTester tester,
  ) async {
    final List<ShellPane> seen = <ShellPane>[];
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    final DemoHarness h = DemoHarness(
      wrapPage: (DemoRoute route, Widget screen) => route is DemoList
          ? Builder(
              builder: (BuildContext context) {
                seen.add(ShellLayoutScope.of(context).pane);
                return screen;
              },
            )
          : screen,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(seen.last, ShellPane.master);

    setWindow(tester, kCompact);
    await tester.pumpAndSettle();
    expect(seen.last, ShellPane.single);
  });

  testWidgets('outside the shell: maybeOf is null, of asserts', (
    WidgetTester tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    expect(ShellLayoutScope.maybeOf(context), isNull);
    expect(() => ShellLayoutScope.of(context), throwsAssertionError);
  });
}
