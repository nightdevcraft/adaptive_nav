import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Branches mount on first entry and live from then on.
void main() {
  testWidgets('a branch is not built before its first entry, and lives after', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    // The starting branch is built, the neighbour is not there AT ALL (we look
    // offstage too: an inactive `IndexedStack` branch is normally offstage,
    // and here it is absent from the tree).
    expect(find.byType(DemoListScreen), findsOneWidget);
    expect(find.byType(DemoHomeScreen, skipOffstage: false), findsNothing);
    expect(h.delegate.mountedBranches, <int>{0});

    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.byType(DemoHomeScreen), findsOneWidget);

    // On the way back: the Home branch stays in the tree (its tab state is
    // alive), it simply goes offstage.
    await h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    expect(find.byType(DemoHomeScreen, skipOffstage: false), findsOneWidget);
    expect(h.delegate.mountedBranches, <int>{0, 1});
  });

  testWidgets('tab state survives leaving and coming back, once mounted', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-inc')));
    await tester.pumpAndSettle();
    expect(find.text('Home: 1'), findsOneWidget);

    await h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();

    expect(find.text('Home: 1'), findsOneWidget);
  });
}
