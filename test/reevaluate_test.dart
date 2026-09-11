import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `redirect` is applied to the CURRENT state on an external signal from the
/// app (a session change) — the equivalent of `refreshListenable` in go_router.
void main() {
  /// Branch 1, with a single root, plays the auth state.
  NavState<DemoRoute> authState(NavState<DemoRoute> s) => s
      .copyWith(activeBranch: 1)
      .withBranch(
        1,
        BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[
          NavEntry<DemoRoute>(
            route: const DemoHome(),
            transition: AppTransition.platform,
          ),
        ]),
      );

  testWidgets('reevaluate() moves the current state through redirect', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);

    bool signedIn = true;
    final DemoHarness h = DemoHarness(
      redirect: (NavState<DemoRoute> next) => signedIn ? next : authState(next),
      showsChrome: (NavState<DemoRoute> s) => s.activeBranch != 1,
    );

    setWindow(tester, const Size(500, 900));
    await tester.pumpWidget(h.app());
    h.delegate.push(const DemoDetail(2));
    await tester.pumpAndSettle();
    expect(find.byType(DemoDetailScreen), findsOneWidget);

    // The session is gone: the app pokes the delegate, the state moves to
    // auth, and the auth area is drawn WITHOUT chrome.
    signedIn = false;
    h.delegate.reevaluate();
    await tester.pumpAndSettle();

    expect(h.delegate.state.activeBranch, 1);
    expect(find.byType(DemoHomeScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // The session is back: the same call restores the state (redirect passes
    // it through); branch 0's stack with its detail is unharmed.
    signedIn = true;
    h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    expect(find.byType(DemoDetailScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  test('reevaluate() is a no-op without redirect and on unchanged state', () {
    // With no hook, listeners are not woken.
    final DemoHarness plain = DemoHarness();
    int plainNotifications = 0;
    plain.delegate.addListener(() => plainNotifications++);
    plain.delegate.reevaluate();
    expect(plainNotifications, 0);

    // With a hook: the first call moves the state, the second does not
    // (value equality).
    final DemoHarness h = DemoHarness(redirect: authState);
    int notifications = 0;
    h.delegate.addListener(() => notifications++);

    h.delegate.reevaluate();
    expect(notifications, 1);
    expect(h.delegate.state.activeBranch, 1);

    h.delegate.reevaluate();
    expect(notifications, 1);
  });
}
