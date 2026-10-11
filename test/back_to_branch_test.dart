import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/back_log.dart';
import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `backToBranch`: back at another branch's root leads to the start branch.
void main() {
  NavState<DemoRoute> guardedHome(
    NavState<DemoRoute> base,
    NavExitGuard onExit,
  ) => base
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

  /// Counts `SystemNavigator.pop` calls: what the framework does when
  /// `popRoute` gives back to the system.
  List<int> interceptSystemPop(WidgetTester tester) {
    final List<int> calls = <int>[0];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemNavigator.pop') {
          calls[0]++;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

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
        int asked = 0;
        final DemoHarness h = DemoHarness(
          backToBranch: 0,
          start: (NavState<DemoRoute> base) => guardedHome(base, () async {
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
        int asked = 0;
        final DemoHarness h = DemoHarness(
          backToBranch: 0,
          start: (NavState<DemoRoute> base) => guardedHome(base, () async {
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

      testWidgets('the app popping a guarded root does not switch', (
        WidgetTester tester,
      ) async {
        final List<int> systemPops = interceptSystemPop(tester);
        int asked = 0;
        final DemoHarness h = DemoHarness(
          backToBranch: 0,
          start: (NavState<DemoRoute> base) => guardedHome(base, () async {
            asked++;
            return true;
          }),
        );
        await pumpBackLog(tester, h, window);
        final NavState<DemoRoute> before = h.delegate.state;

        // A "Cancel" button in the app, not system back.
        await Navigator.of(
          tester.element(find.byType(DemoHomeScreen)),
        ).maybePop();
        await tester.pumpAndSettle();
        expect(asked, 1);
        expect(systemPops.single, 0);
        expect(h.delegate.state.activeBranch, 1);
        expect(h.delegate.state.active, same(before.active));
      });

      for (final (String where, int? backToBranch, int branch)
          in <(String, int?, int)>[
            ('without the setting', null, 1),
            ('on the start branch', 1, 1),
          ]) {
        NavState<DemoRoute> guardedRoot(
          NavState<DemoRoute> base,
          NavExitGuard onExit,
        ) => guardedHome(base, onExit).copyWith(activeBranch: branch);

        testWidgets('$where a guarded root that agrees leaves the app', (
          WidgetTester tester,
        ) async {
          final List<int> systemPops = interceptSystemPop(tester);
          int asked = 0;
          final DemoHarness h = DemoHarness(
            backToBranch: backToBranch,
            start: (NavState<DemoRoute> base) => guardedRoot(base, () async {
              asked++;
              return true;
            }),
          );
          await pumpBackLog(tester, h, window);
          final NavState<DemoRoute> before = h.delegate.state;

          expect(await h.delegate.popRoute(), isTrue);
          await tester.pumpAndSettle();
          expect(asked, 1);
          expect(systemPops.single, 1);
          expect(h.delegate.state.activeBranch, branch);
          expect(h.delegate.state.active, same(before.active));
        });

        testWidgets('$where the app popping a guarded root does not leave', (
          WidgetTester tester,
        ) async {
          final List<int> systemPops = interceptSystemPop(tester);
          int asked = 0;
          final DemoHarness h = DemoHarness(
            backToBranch: backToBranch,
            start: (NavState<DemoRoute> base) => guardedRoot(base, () async {
              asked++;
              return true;
            }),
          );
          await pumpBackLog(tester, h, window);
          final NavState<DemoRoute> before = h.delegate.state;

          // A "Cancel" button in the app, not system back.
          await Navigator.of(
            tester.element(find.byType(DemoHomeScreen)),
          ).maybePop();
          await tester.pumpAndSettle();
          expect(asked, 1);
          expect(systemPops.single, 0);
          expect(h.delegate.state.active, same(before.active));
        });

        testWidgets('$where a guarded root that refuses stays', (
          WidgetTester tester,
        ) async {
          final List<int> systemPops = interceptSystemPop(tester);
          int asked = 0;
          final DemoHarness h = DemoHarness(
            backToBranch: backToBranch,
            start: (NavState<DemoRoute> base) => guardedRoot(base, () async {
              asked++;
              return false;
            }),
          );
          final List<bool> log = await pumpBackLog(tester, h, window);
          final NavState<DemoRoute> before = h.delegate.state;

          expect(await h.delegate.popRoute(), isTrue);
          await tester.pumpAndSettle();
          expect(asked, 1);
          expect(systemPops.single, 0);
          expect(h.delegate.state.activeBranch, branch);
          expect(h.delegate.state.active, same(before.active));
          expect(log.last, isTrue);
        });
      }

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
