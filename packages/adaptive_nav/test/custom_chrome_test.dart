import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Custom bar, rail and drawer, with the Material default still the default.
void main() {
  testWidgets('a custom barBuilder replaces NavigationBar (compact)', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness(barBuilder: _testChrome('bar'));
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey<String>('bar')), findsOneWidget);
  });

  testWidgets('a tap on a custom destination switches BRANCH by its index', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness(barBuilder: _testChrome('bar'));
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    // The index in the callback is a BRANCH index, not a destination position.
    await tester.tap(find.byKey(const ValueKey<String>('bar-branch-1')));
    await tester.pumpAndSettle();

    expect(harness.delegate.state.activeBranch, 1);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a custom railBuilder replaces NavigationRail (wide)', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness(railBuilder: _testChrome('rail'));
    // Branch 1 (Home) has no master-detail, so there can be only one divider
    // in the tree: the one the package draws after the rail.
    harness.delegate.goBranch(1);
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const ValueKey<String>('rail')), findsOneWidget);
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('railBuilder returned null: no rail and no divider', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness(
      railBuilder: (BuildContext _, int _, ValueChanged<int> _) => null,
    );
    harness.delegate.goBranch(1);
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('drawerBuilder + scaffoldKey: the drawer opens by key', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    final DemoHarness harness = DemoHarness(
      scaffoldKey: scaffoldKey,
      // The drawer is compact-only; in the wide layout it lives in the rail,
      // so the builder answers `null` and the edge swipe goes with it.
      drawerBuilder: (BuildContext _, bool rail) =>
          rail ? null : const Drawer(child: Text('Menu')),
    );
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(scaffoldKey.currentState!.hasDrawer, isTrue);
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets('in the wide layout drawerBuilder receives rail: true', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    final DemoHarness harness = DemoHarness(
      scaffoldKey: scaffoldKey,
      drawerBuilder: (BuildContext _, bool rail) =>
          rail ? null : const Drawer(child: Text('Menu')),
    );
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(scaffoldKey.currentState!.hasDrawer, isFalse);
  });

  testWidgets('showsChrome=false: no builder is called, no drawer', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    int barCalls = 0;
    int drawerCalls = 0;
    final DemoHarness harness = DemoHarness(
      showsChrome: (NavState<DemoRoute> _) => false,
      scaffoldKey: scaffoldKey,
      barBuilder: (BuildContext _, int _, ValueChanged<int> _) {
        barCalls++;
        return const SizedBox.shrink();
      },
      drawerBuilder: (BuildContext _, bool _) {
        drawerCalls++;
        return const Drawer(child: Text('Menu'));
      },
    );
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(barCalls, 0);
    expect(drawerCalls, 0);
    expect(scaffoldKey.currentState!.hasDrawer, isFalse);
  });

  testWidgets('hidden branch: barBuilder is skipped, railBuilder is not', (
    WidgetTester tester,
  ) async {
    int barCalls = 0;
    final List<int> railBranches = <int>[];
    final DemoHarness harness = DemoHarness(
      withHiddenBranch: true,
      barBuilder: (BuildContext _, int _, ValueChanged<int> _) {
        barCalls++;
        return const SizedBox.shrink();
      },
      railBuilder: (BuildContext _, int activeBranch, ValueChanged<int> _) {
        railBranches.add(activeBranch);
        return const SizedBox(width: 80, key: ValueKey<String>('rail'));
      },
    );
    harness.delegate.goBranch(2); // a branch with no chrome destination

    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    // The `showsInChrome` gate is shared between the default and the custom
    // one: `NavigationBar`, and any wrapper over it, has no "nothing
    // selected" state.
    expect(barCalls, 0);

    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    // The rail handles a hidden branch natively — the builder is called with
    // its index.
    expect(railBranches, contains(2));
    expect(find.byKey(const ValueKey<String>('rail')), findsOneWidget);
  });

  testWidgets('no builders: NavigationBar / NavigationRail as before', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}

/// Custom chrome for the tests: one button per BRANCH, keyed by branch index.
ShellChromeBuilder _testChrome(String id) {
  return (BuildContext context, int activeBranch, ValueChanged<int> onSelect) {
    // A `Wrap` rather than a `Row`: the package holds the rail to the declared
    // `railWidth`, and fake chrome has to fit into it like a real rail would.
    return Wrap(
      key: ValueKey<String>(id),
      children: <Widget>[
        for (int branch = 0; branch < 2; branch++)
          TextButton(
            key: ValueKey<String>('$id-branch-$branch'),
            onPressed: () => onSelect(branch),
            child: Text(branch == activeBranch ? '[$branch]' : '$branch'),
          ),
      ],
    );
  };
}
