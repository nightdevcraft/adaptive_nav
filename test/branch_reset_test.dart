import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `goBranch(index, resetToRoot: true)` enters a branch at its root. That
/// destroys the target branch's screens, so it goes through `onExit` — it
/// used to reset silently and lose an unclosed editor.
void main() {
  testWidgets('resetToRoot collapses the target branch to its root', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();
    expect(harness.delegate.state.branches[0].entries.length, 2);

    await harness.delegate.goBranch(1); // left for Home, detail is parked
    await tester.pumpAndSettle();
    expect(harness.delegate.state.branches[0].entries.length, 2);

    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    expect(harness.delegate.state.activeBranch, 0);
    expect(harness.delegate.state.branches[0].entries.length, 1);
    expect(find.text('Detail 1'), findsNothing);
    expect(find.text('List'), findsOneWidget);
  });

  testWidgets('clean stack: resetToRoot resets WITHOUT calling the gate', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    int guardCalls = 0;
    harness.delegate.push(const DemoDetail(7)); // no onExit, nothing to lose
    await tester.pumpAndSettle();

    await harness.delegate.goBranch(1);
    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    // A normal branch entry shows no dialogs: there is nothing to ask about.
    expect(guardCalls, 0);
    expect(harness.delegate.state.branches[0].entries.length, 1);
  });

  testWidgets('dirty stack: resetToRoot runs onExit of the removed screens', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    int guardCalls = 0;
    unawaited(
      harness.delegate.push(
        const DemoEdit(7),
        onExit: () async {
          guardCalls++;
          return true; // "discard" — the screen gives itself up
        },
      ),
    );
    await tester.pumpAndSettle();

    await harness.delegate.goBranch(1);
    // The tab switch itself is gated too; what is checked here is the RESET,
    // so the calls are counted from a clean slate.
    guardCalls = 0;
    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    // The reset DESTROYS a screen with an unsaved edit, and that must not
    // happen silently.
    expect(guardCalls, 1);
    expect(harness.delegate.state.activeBranch, 0);
    expect(harness.delegate.state.branches[0].entries.length, 1);
  });

  testWidgets('gate cancelled: we enter the branch but do NOT reset it', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    bool allowLeave = true;
    unawaited(
      harness.delegate.push(const DemoEdit(7), onExit: () async => allowLeave),
    );
    await tester.pumpAndSettle();

    await harness.delegate.goBranch(1); // left for another tab, allowing it
    await tester.pumpAndSettle();
    allowLeave = false; // "stay on the screen" — refused at the reset
    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    // The branch is shown (or the dialog would ask about an invisible
    // screen), but the edit stays on top: the user sees exactly what they
    // kept.
    expect(harness.delegate.state.activeBranch, 0);
    expect(harness.delegate.state.branches[0].entries.length, 2);
    expect(find.text('Editing 7'), findsWidgets); // the title and the body
  });

  testWidgets('the gate is asked while already in the target branch', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    int branchWhenAsked = -1;
    unawaited(
      harness.delegate.push(
        const DemoEdit(7),
        onExit: () async {
          branchWhenAsked = harness.delegate.state.activeBranch;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await harness.delegate.goBranch(1);
    branchWhenAsked = -1; // the tab-exit gate answer is not measured here
    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    // Enter first, gate second: a "save the edit?" dialog must not pop up
    // while the user is looking at another tab.
    expect(branchWhenAsked, 0);
  });

  testWidgets('completers of removed screens resolve, so no await leaks', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    Object? result = 'never resolved';
    final Future<Object?> pending = harness.delegate.push(const DemoDetail(2));
    unawaited(pending.then((Object? value) => result = value));
    await tester.pumpAndSettle();

    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('the default (resetToRoot: false) keeps the branch stack', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-3')));
    await tester.pumpAndSettle();

    await harness.delegate.goBranch(1);
    await tester.pumpAndSettle();
    await harness.delegate.goBranch(0);
    await tester.pumpAndSettle();

    expect(harness.delegate.state.branches[0].entries.length, 2);
    expect(find.text('Detail 3'), findsOneWidget);
  });

  testWidgets('resetToRoot on an ALREADY active branch clears its stack', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-2')));
    await tester.pumpAndSettle();

    // Re-tapping the active tab: the index is the same, but the stack still
    // has to collapse — an early "the index did not change" return must not
    // drop this path.
    await harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pumpAndSettle();

    expect(harness.delegate.state.branches[0].entries.length, 1);
    expect(find.text('List'), findsOneWidget);
  });

  testWidgets('the stack changed while the gate was up: no reset happens', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kCompact);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    final Completer<bool> answer = Completer<bool>();
    unawaited(
      harness.delegate.push(const DemoEdit(7), onExit: () => answer.future),
    );
    await tester.pumpAndSettle();

    final Future<void> reset = harness.delegate.goBranch(0, resetToRoot: true);
    await tester.pump();

    // While the user was thinking about the dialog, a new screen arrived in
    // the branch (a push or a deep link). It never passed the gate, so it must
    // not be destroyed.
    unawaited(harness.delegate.push(const DemoDetail(9)));
    await tester.pumpAndSettle();

    answer.complete(true);
    await reset;
    await tester.pumpAndSettle();

    expect(harness.delegate.state.branches[0].entries.length, 3);
    expect(find.text('Detail 9'), findsOneWidget);
  });
}
