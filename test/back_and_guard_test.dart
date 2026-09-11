import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Back handling and the onExit guard on every way out.
void main() {
  testWidgets('pop removes top entry', (WidgetTester tester) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsOneWidget);

    final bool popped = await h.delegate.pop();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.text('Detail 1'), findsNothing);
    expect(find.text('List'), findsOneWidget);
  });

  testWidgets('system back (popRoute) pops detail, then yields at root', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    final bool handled = await h.delegate.popRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('Detail 1'), findsNothing);

    // At the active branch root, popRoute hands back to the system.
    final bool atRoot = await h.delegate.popRoute();
    expect(atRoot, isFalse);
  });

  testWidgets('onExit=false blocks pop / replace / system back', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1), onExit: () async => false);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsOneWidget);

    expect(await h.delegate.pop(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsOneWidget);

    await h.delegate.replace(const DemoDetail(9));
    await tester.pumpAndSettle();
    expect(find.text('Detail 9'), findsNothing);
    expect(find.text('Detail 1'), findsOneWidget);

    // System back was handled (true), but the screen stayed.
    expect(await h.delegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsOneWidget);
  });

  testWidgets('onExit=true lets navigation through', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1), onExit: () async => true);
    await tester.pumpAndSettle();

    expect(await h.delegate.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsNothing);
  });

  // A tab switch is gated just like back and replace: the user is asked about
  // an unsaved edit, even though the screen is only parked rather than
  // destroyed.
  testWidgets('switching tab asks the exit guard of the current top', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    int guardCalls = 0;
    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(
      const DemoDetail(1),
      onExit: () async {
        guardCalls++;
        return true;
      },
    );
    await tester.pumpAndSettle();

    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();

    expect(guardCalls, 1);
    expect(h.delegate.state.activeBranch, 1);
  });

  testWidgets('exit guard refusal keeps the current tab and the edit', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    int guardCalls = 0;
    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(
      const DemoDetail(1),
      onExit: () async {
        guardCalls++;
        return false;
      },
    );
    await tester.pumpAndSettle();

    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();

    expect(guardCalls, 1);
    expect(h.delegate.state.activeBranch, 0); // still on our own tab
    expect(find.text('Detail 1'), findsOneWidget); // the edit is untouched
  });

  testWidgets('allowed tab switch parks the screen (entry survives)', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1), onExit: () async => true);
    await tester.pumpAndSettle();

    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsNothing);

    await h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsOneWidget); // the screen is alive
  });

  testWidgets('clean branch switches synchronously, without a prompt', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1)); // no onExit, nobody to ask
    await tester.pumpAndSettle();

    h.delegate.goBranch(1); // no await: it must go through in the same frame
    expect(h.delegate.state.activeBranch, 1);
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsNothing);
  });
}
