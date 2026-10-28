import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `DetailPaneScope.isFullScreen` against `of`. The two differ on a branch's
/// main navigator, where there is no scope at all: `of` says `false` there,
/// which would make a master indistinguishable from a full-screen detail.
void main() {
  /// Both checks, read from inside the screen.
  ({bool inPane, bool fullScreen}) probe(WidgetTester tester, String text) {
    final BuildContext context = tester.element(find.text(text));
    return (
      inPane: DetailPaneScope.of(context),
      fullScreen: DetailPaneScope.isFullScreen(context),
    );
  }

  testWidgets('compact: the master is no detail, the detail is full screen', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    expect(probe(tester, 'Item 1'), (inPane: false, fullScreen: false));

    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    // The detail: no pane, so it spans the whole area.
    expect(probe(tester, 'Detail 1'), (inPane: false, fullScreen: true));
  });

  testWidgets('wide: a detail in a PANE is not full screen', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(probe(tester, 'Detail 1'), (inPane: true, fullScreen: false));
  });

  testWidgets('a resize changes the flag on the SAME page', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    expect(probe(tester, 'Detail 1').fullScreen, isFalse);

    // The window got narrower: there are no panes any more and the detail is
    // full screen — and the screen has to see that WITHOUT being recreated.
    setWindow(tester, kCompact);
    await tester.pumpAndSettle();

    expect(probe(tester, 'Detail 1').fullScreen, isTrue);
  });
}
