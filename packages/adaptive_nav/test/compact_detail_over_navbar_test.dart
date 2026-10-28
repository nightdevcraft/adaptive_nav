import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The single-pane detail and the chrome. By default the detail layer covers
/// the bar, and the rail beside one pane as well: taps reach the chrome only
/// while the detail is empty, and therefore transparent. With
/// `DetailChrome.kept` on iOS the chrome stays beside an open detail; on
/// Android the value is ignored.
void main() {
  /// [chrome] on the theme's [platform], in [window]: whether the open detail
  /// covers the chrome.
  final List<(DetailChrome, TargetPlatform, bool)> cases =
      <(DetailChrome, TargetPlatform, bool)>[
        (DetailChrome.covered, TargetPlatform.android, true),
        (DetailChrome.covered, TargetPlatform.iOS, true),
        (DetailChrome.kept, TargetPlatform.android, true),
        (DetailChrome.kept, TargetPlatform.iOS, false),
        (DetailChrome.kept, TargetPlatform.macOS, false),
      ];

  for (final (DetailChrome chrome, TargetPlatform platform, bool covers)
      in cases) {
    final String name = '${chrome.name} on ${platform.name}';

    testWidgets('$name: the bar is ${covers ? 'covered' : 'kept'}', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(
        tester,
        kCompact,
        padding: const EdgeInsets.only(top: 47, bottom: 34),
      );

      final DemoHarness h = DemoHarness(
        detailChrome: chrome,
        platform: platform,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      // The detail is empty, so the tap reaches the bar and we switch to Home.
      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);

      h.delegate.goBranch(0);
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expect(find.text('Detail 1'), findsOneWidget);

      final Rect bar = tester.getRect(find.byType(NavigationBar));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      if (covers) {
        expect(detail.bottom, kCompact.height);
        // The detail covers the bar, so the tap is swallowed and the branch
        // does not change.
        await tester.tap(find.byIcon(Icons.home), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 0);
        expect(find.text('Detail 1'), findsOneWidget);
        return;
      }
      // Ends at the bar's top edge, and the bar keeps the home indicator's
      // inset: the detail does not clear it a second time.
      expect(detail.bottom, bar.top);
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(DemoDetailScreen))),
        const EdgeInsets.only(top: 47),
      );
      // A tab from the detail: an ordinary switch, the detail kept in its
      // branch.
      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);
      expect(find.text('Home'), findsWidgets);
      await tester.tap(find.byIcon(Icons.people));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 0);
      expect(h.delegate.state.active.entries, hasLength(2));
      expect(find.text('Detail 1'), findsOneWidget);
    });

    // A tablet in portrait: a rail and one pane.
    testWidgets('$name: the rail beside one pane is '
        '${covers ? 'covered' : 'kept'}', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      const Size window = Size(744, 1133);
      setPose(tester, window, padding: const EdgeInsets.only(top: 24));

      final DemoHarness h = DemoHarness(
        detailChrome: chrome,
        platform: platform,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      if (covers) {
        // The whole window, as over the bar.
        expect(detail, Offset.zero & window);
        await tester.tap(find.byIcon(Icons.home), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 0);
        // Closed, the empty detail lets the taps through again.
        h.delegate.pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.home));
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 1);
        return;
      }
      expect(detail.left, greaterThanOrEqualTo(rail.right));
      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(h.delegate.state.activeBranch, 1);
      h.delegate.goBranch(0);
      await tester.pumpAndSettle();
      expect(find.text('Detail 1'), findsOneWidget);
    });
  }

  testWidgets('two panes keep the rail either way', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(DemoDetailScreen)).left,
      greaterThan(tester.getRect(find.byType(NavigationRail)).right),
    );
    await tester.tap(find.byIcon(Icons.home));
    await tester.pumpAndSettle();
    expect(h.delegate.state.activeBranch, 1);
  });
}
