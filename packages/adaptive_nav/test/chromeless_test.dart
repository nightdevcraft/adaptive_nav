import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `showsChrome`: the bar and rail go, the branch navigators stay.
void main() {
  testWidgets('showsChrome=false renders the branch full-screen, no bar/rail', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);

    // Branch 1 (Home) plays the auth area here — it has no chrome.
    final DemoHarness h = DemoHarness(
      showsChrome: (NavState<DemoRoute> s) => s.activeBranch != 1,
    );

    setWindow(tester, const Size(500, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget); // branch 0 has chrome

    h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.getSize(find.byType(DemoHomeScreen)), const Size(500, 900));

    // In the wide layout a chromeless screen is full width too: no rail.
    setWindow(tester, const Size(1200, 900));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.getSize(find.byType(DemoHomeScreen)), const Size(1200, 900));
  });

  testWidgets('chrome flip does not remount branches (state survives)', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);

    final DemoHarness h = DemoHarness(
      showsChrome: (NavState<DemoRoute> s) => s.activeBranch != 1,
    );

    setWindow(tester, const Size(500, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(3));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 2'), findsOneWidget);

    h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Counter: 2'), findsOneWidget);
  });

  testWidgets('branch with showsInChrome=false has no item and no highlight', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);

    final DemoHarness h = DemoHarness(withHiddenBranch: true);

    // The rail has 2 destinations, not 3: a hidden branch gets no button.
    setWindow(tester, const Size(1200, 900));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    NavigationRail rail() =>
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail().destinations.length, 2);
    expect(rail().selectedIndex, 0);

    // A hidden branch is active: the rail is there with nothing highlighted.
    h.delegate.goBranch(2);
    await tester.pumpAndSettle();
    expect(find.byType(DemoProfileScreen), findsOneWidget);
    expect(rail().selectedIndex, isNull);

    // `NavigationBar` has no "nothing selected" state, so on compact a hidden
    // branch renders full screen; back on a visible one, the bar has 2
    // destinations again.
    setWindow(tester, const Size(500, 900));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(bar.destinations.length, 2);
    expect(bar.selectedIndex, 1);
  });
}
