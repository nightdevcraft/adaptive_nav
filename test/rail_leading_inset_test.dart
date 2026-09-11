import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The rail sits against the window edge and covers a landscape notch rather
/// than growing by it, so the leading inset is stripped from its subtree.
/// Material's `NavigationRail` carries a `SafeArea`, and on a notched phone in
/// landscape that inset is most of the declared width.
void main() {
  // A notched iPhone in landscape reports about this much on the notch side.
  const double notch = 59;

  void setLeftInset(WidgetTester tester, double left) {
    final FakeViewPadding inset = FakeViewPadding(left: left);
    tester.view.padding = inset;
    tester.view.viewPadding = inset;
  }

  Future<DemoHarness> pump(
    WidgetTester tester, {
    ShellChromeBuilder? railBuilder,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    setLeftInset(tester, notch);
    final DemoHarness h = DemoHarness(railBuilder: railBuilder);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('the default rail does not see the leading inset', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // Left intact, the `SafeArea` inside `NavigationRail` would eat 59 of the
    // 80 and lay the destinations out into the remaining 21.
    expect(
      MediaQuery.paddingOf(tester.element(find.byType(NavigationRail))).left,
      0,
    );
    expect(
      tester.getSize(find.byType(NavigationRail)).width,
      kDefaultRailWidth,
    );
  });

  testWidgets('a custom rail does not see it either', (
    WidgetTester tester,
  ) async {
    const Key custom = ValueKey<String>('custom-rail');
    await pump(
      tester,
      railBuilder:
          (BuildContext context, int branch, ValueChanged<int> select) =>
              const SizedBox.expand(key: custom),
    );

    expect(MediaQuery.paddingOf(tester.element(find.byKey(custom))).left, 0);
  });

  testWidgets('the inset does not move the panes', (WidgetTester tester) async {
    final DemoHarness h = await pump(tester);
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    // The arithmetic is untouched: the rail and its divider, and nothing
    // reserved for the notch the rail covers.
    expect(
      tester.getRect(find.byType(DemoListScreen)).left,
      kDefaultRailWidth + AdaptiveShell.dividerWidth,
    );
  });
}
