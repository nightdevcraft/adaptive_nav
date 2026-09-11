import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Immersive mode slides the rail out of the wide layout.
///
/// The invariant is that it changes geometry and nothing else: the layout
/// class stays frozen, `NavState` is the same object, the delegate is not
/// notified and no screen is remounted.
void main() {
  /// Width of the rail region this frame. Zero means the rail is fully gone.
  double regionWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(AdaptiveShell.railRegionKey)).width;

  double masterWidth(WidgetTester tester) =>
      tester.getSize(find.byType(DemoListScreen)).width;

  /// A harness with immersive mode; the notifier lives as long as the test.
  (DemoHarness, ValueNotifier<bool>) harness(WidgetTester tester) {
    final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);
    addTearDown(immersive.dispose);
    return (DemoHarness(immersive: immersive), immersive);
  }

  testWidgets('immersive:true: the rail is gone, the master spans the window', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    // Before entering: the rail is in place (80 + 1 divider), the master takes
    // the content area.
    final double region = regionWidth(tester);
    expect(region, closeTo(kDefaultRailWidth + kDefaultRailDividerWidth, 0.5));
    expect(masterWidth(tester), closeTo(kWide.width - region, 0.5));

    immersive.value = true;
    await tester.pumpAndSettle();

    expect(regionWidth(tester), 0);
    expect(masterWidth(tester), closeTo(kWide.width, 0.5));
    // The rail is not unmounted — it is clipped by a zero-width region and
    // stays alive, so it is not rebuilt on the way out of the mode.
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('immersive:false: the rail is back, widths unchanged', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final double regionBefore = regionWidth(tester);
    final double masterBefore = masterWidth(tester);

    immersive.value = true;
    await tester.pumpAndSettle();
    immersive.value = false;
    await tester.pumpAndSettle();

    expect(regionWidth(tester), closeTo(regionBefore, 0.5));
    expect(masterWidth(tester), closeTo(masterBefore, 0.5));
  });

  testWidgets('the rail leaves with an animation, not an instant swap', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final double full = regionWidth(tester);

    immersive.value = true;
    // A series of frames rather than one `pump`: the first tick of
    // `TweenAnimationBuilder` still reports the initial value, so a check
    // "after one frame" would catch the start rather than the animation.
    final List<double> widths = <double>[];
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      widths.add(regionWidth(tester));
    }
    expect(
      widths.any((double w) => w > 0.5 && w < full - 0.5),
      isTrue,
      reason: 'the rail region must pass through intermediate widths: $widths',
    );

    await tester.pumpAndSettle();
    expect(regionWidth(tester), 0);
  });

  testWidgets(
    'master state is intact, NavState is the same, the delegate is quiet',
    (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setWindow(tester, kWide);

      final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('list-inc')));
      await tester.tap(find.byKey(const ValueKey<String>('list-inc')));
      await tester.pumpAndSettle();
      expect(find.text('List: 2'), findsOneWidget);

      final NavState<DemoRoute> before = h.delegate.state;
      int notifications = 0;
      void onNotify() => notifications++;
      h.delegate.addListener(onNotify);
      addTearDown(() => h.delegate.removeListener(onNotify));

      immersive.value = true;
      await tester.pumpAndSettle();
      immersive.value = false;
      await tester.pumpAndSettle();

      // The counter is intact, so the screen was not remounted; the same state
      // object and zero notifications mean the delegate never heard of the
      // mode.
      expect(find.text('List: 2'), findsOneWidget);
      expect(identical(h.delegate.state, before), isTrue);
      expect(notifications, 0);
    },
  );

  testWidgets('non-empty detail: both panes stay, wider, with no remount', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);
    final double masterBefore = masterWidth(tester);

    immersive.value = true;
    await tester.pumpAndSettle();

    final double master = masterWidth(tester);
    final double detail = tester.getSize(find.byType(DemoDetailScreen)).width;
    expect(
      find.text('Counter: 1'),
      findsOneWidget,
    ); // the detail was not remounted
    expect(master, greaterThan(masterBefore)); // both panes got wider
    expect(master + detail, closeTo(kWide.width, 0.5));
    expect(master / (master + detail), closeTo(0.35, 0.04)); // same fraction
  });

  testWidgets('compact: the flag is ignored, the bar stays put', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    immersive.value = true;
    await tester.pumpAndSettle();

    setWindow(tester, kCompact);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(AdaptiveShell.railRegionKey), findsNothing);
    expect(find.text('List: 0'), findsOneWidget);

    // Back to wide with the flag raised: the mode is already applied, with no
    // animation "out of full width" — the rail would otherwise flash on every
    // resize.
    setWindow(tester, kWide);
    await tester.pump();
    expect(regionWidth(tester), 0);
    expect(masterWidth(tester), closeTo(kWide.width, 0.5));
  });

  testWidgets('the layout class is frozen: below fits, one pane', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    // 720: the panes get 639 < 680 (320 + 360), so one pane. Without the rail
    // it would fit (720 >= 680), but immersive mode does not move the
    // threshold.
    const Size narrowWide = Size(720, 900);
    setWindow(tester, narrowWide);

    final (DemoHarness h, ValueNotifier<bool> immersive) = harness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();

    immersive.value = true;
    await tester.pumpAndSettle();

    // One pane: the detail COVERS the master at full width instead of sitting
    // next to it.
    expect(masterWidth(tester), closeTo(narrowWide.width, 0.5));
    expect(
      tester.getSize(find.byType(DemoDetailScreen)).width,
      closeTo(narrowWide.width, 0.5),
    );
  });

  testWidgets('without immersive in the config there is no extra layer', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    await tester.pumpWidget(DemoHarness().app());
    await tester.pumpAndSettle();

    expect(find.byKey(AdaptiveShell.railRegionKey), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}
