import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `resetDetailTo` is the lateral move: a detail of any depth goes, one new
/// screen takes its place. `replaceTop` would leave the old card underneath.
void main() {
  testWidgets('depth 2: a detail reset leaves [root, new]', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('open-edit')));
    await tester.pumpAndSettle();
    expect(harness.delegate.state.active.entries, hasLength(3));

    await harness.delegate.resetDetailTo(const DemoDetail(2));
    await tester.pumpAndSettle();

    expect(harness.delegate.state.active.entries, hasLength(2));
    expect(harness.delegate.state.active.root.route, const DemoList());
    expect(harness.delegate.state.active.top.route, const DemoDetail(2));
    expect(find.text('Detail 2'), findsOneWidget);
    expect(find.text('Detail 1'), findsNothing);
  });

  testWidgets('the removal gate: a refusal keeps the previous detail', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();

    int guardCalls = 0;
    unawaited(
      harness.delegate.push(
        const DemoEdit(1),
        onExit: () async {
          guardCalls++;
          return false; // "cancel" — the screen does not give itself up
        },
      ),
    );
    await tester.pumpAndSettle();

    await harness.delegate.resetDetailTo(const DemoDetail(2));
    await tester.pumpAndSettle();

    expect(guardCalls, 1);
    expect(harness.delegate.state.active.entries, hasLength(3));
    expect(harness.delegate.state.active.top.route, const DemoEdit(1));
  });

  testWidgets('completers of removed screens resolve, so no await leaks', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    bool resolved = false;
    unawaited(
      harness.delegate.push(const DemoDetail(1)).then((Object? _) {
        resolved = true;
      }),
    );
    await tester.pumpAndSettle();

    await harness.delegate.resetDetailTo(const DemoDetail(2));
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
  });

  testWidgets('the detail does not collapse for a frame in between', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();
    final double masterWidth = tester.getSize(find.text('List')).width;

    // Swapping the detail is ONE state mutation: there must be no frame with
    // an empty pane between the old and the new detail, or
    // `collapseWhenDetailEmpty` starts a reverse reveal and the master
    // flinches on every selection.
    await harness.delegate.resetDetailTo(const DemoDetail(2));
    await tester.pump();

    expect(harness.delegate.state.active.entries, hasLength(2));
    expect(tester.getSize(find.text('List')).width, masterWidth);
  });
}
