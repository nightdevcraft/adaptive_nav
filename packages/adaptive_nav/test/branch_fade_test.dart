import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `branchFadeDuration`: the display lags the state while the old branch
/// fades out, and tab state is untouched either way.
void main() {
  const Duration fade = Duration(milliseconds: 200);

  /// Index of the masters `IndexedStack` — the branch that is SHOWN.
  int mastersIndex(WidgetTester tester) => tester
      .widget<IndexedStack>(find.byKey(AdaptiveShell.mastersStackKey))
      .index!;

  /// Index of the detail `IndexedStack`. It changes AT ONCE, so the gap against
  /// the masters is what shows the master display being held back by the fade.
  int detailsIndex(WidgetTester tester) => tester
      .widget<IndexedStack>(find.byKey(AdaptiveShell.detailsStackKey))
      .index!;

  /// Opacity of the masters layer, addressed by key: there is more than one
  /// `FadeTransition` in the tree (the root `Navigator` page transition, page
  /// transitions inside branches), so "the first one by type" would point at
  /// the wrong layer.
  double mastersOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find.byKey(AdaptiveShell.branchFadeLayerKey))
      .opacity
      .value;

  testWidgets('compact: a tab switch fades instead of swapping', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness(branchFadeDuration: fade);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(mastersIndex(tester), 0);
    expect(mastersOpacity(tester), 1);

    h.delegate.goBranch(1);
    await tester.pump(); // the frame where the state is already new
    await tester.pump(const Duration(milliseconds: 40));

    // The branch in the state has already changed (the detail is on the new
    // one), while the master display still holds the old one and fades out.
    expect(detailsIndex(tester), 1);
    expect(mastersIndex(tester), 0);
    expect(mastersOpacity(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(mastersIndex(tester), 1);
    expect(mastersOpacity(tester), 1);
    expect(find.text('Home: 0'), findsOneWidget);
  });

  testWidgets('wide: the left (master) pane fades too', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness(branchFadeDuration: fade);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);

    h.delegate.goBranch(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(mastersIndex(tester), 0);
    expect(mastersOpacity(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(mastersIndex(tester), 1);
  });

  testWidgets(
    'the transition leaves tab state alone (no navigator is recreated)',
    (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setWindow(tester, kCompact);

      final DemoHarness h = DemoHarness(branchFadeDuration: fade);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home-inc')));
      await tester.pump();
      expect(find.text('Home: 1'), findsOneWidget);

      h.delegate.goBranch(0);
      await tester.pumpAndSettle();
      h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      expect(find.text('Home: 1'), findsOneWidget);
    },
  );

  testWidgets('returning to the same branch mid-fade fades it back in', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness(branchFadeDuration: fade);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.goBranch(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    // Changed our mind while the branch was fading out.
    h.delegate.goBranch(0);
    await tester.pumpAndSettle();

    expect(mastersIndex(tester), 0);
    expect(mastersOpacity(tester), 1);
  });

  testWidgets('by default (zero) the swap is instant, with no fade layer', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.goBranch(1);
    await tester.pump();

    expect(mastersIndex(tester), 1);
    expect(find.byKey(AdaptiveShell.branchFadeLayerKey), findsNothing);
  });
}
