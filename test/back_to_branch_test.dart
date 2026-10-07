import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/back_log.dart';
import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `backToBranch`: back at another branch's root leads to the start branch.
void main() {
  NavState<DemoRoute> guardedHome(DemoHarness h, NavExitGuard onExit) => h
      .baseState
      .withBranch(
        1,
        BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[
          NavEntry<DemoRoute>(
            route: const DemoHome(),
            transition: AppTransition.platform,
            onExit: onExit,
          ),
        ]),
      )
      .copyWith(activeBranch: 1);

  for (final (String name, Size window) in <(String, Size)>[
    ('compact', kCompact),
    ('wide', kWide),
  ]) {
    group(name, () {
      testWidgets('back at another branch root leads to the start branch', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness(backToBranch: 0);
        final List<bool> log = await pumpBackLog(tester, h, window);
        expect(log.last, isFalse);

        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(log.last, isTrue);
        final BranchStack<DemoRoute> home = h.delegate.state.branches[1];

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 0);
        expect(h.delegate.state.branches[1], same(home));
        expect(log.last, isFalse);

        expect(await h.delegate.popRoute(), isFalse);
      });

      testWidgets('the branch stack goes first, then the switch', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness(backToBranch: 0);
        final List<bool> log = await pumpBackLog(tester, h, window);
        await h.delegate.goBranch(1);
        h.delegate.push(const DemoHome());
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 1);
        expect(h.delegate.state.active.entries, hasLength(1));
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 0);
        expect(log.last, isFalse);
      });

      testWidgets('a hidden branch leads there too', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness(
          backToBranch: 0,
          withHiddenBranch: true,
        );
        final List<bool> log = await pumpBackLog(tester, h, window);
        await h.delegate.goBranch(2);
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 0);
      });

      testWidgets('a guarded root that refuses keeps the tab', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness(backToBranch: 0);
        int asked = 0;
        await h.delegate.setNewRoutePath(
          guardedHome(h, () async {
            asked++;
            return false;
          }),
        );
        final List<bool> log = await pumpBackLog(tester, h, window);
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(asked, 1);
        expect(h.delegate.state.activeBranch, 1);
        expect(log.last, isTrue);
      });

      testWidgets('a guarded root that agrees is asked once', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness(backToBranch: 0);
        int asked = 0;
        await h.delegate.setNewRoutePath(
          guardedHome(h, () async {
            asked++;
            return true;
          }),
        );
        await pumpBackLog(tester, h, window);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(asked, 1);
        expect(h.delegate.state.activeBranch, 0);
      });

      testWidgets('without the setting back at a root goes to the system', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        final List<bool> log = await pumpBackLog(tester, h, window);
        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);

        expect(await h.delegate.popRoute(), isFalse);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 1);
      });
    });
  }
}
