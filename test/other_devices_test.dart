import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// What the foldable work changed for everything that is not a foldable.
///
/// `chrome_layout_test.dart` holds the line on *where the chrome goes* — every
/// phone, tablet and desktop still decides by the width breakpoint alone. This
/// file is the other half: the two places where behaviour deliberately did
/// change, so that neither is a surprise found on a device.
void main() {
  group('a notched phone in landscape', () {
    // iPhone 18 Pro, measured: 62 on each side.
    const Size window = Size(874, 402);
    const EdgeInsets padding = EdgeInsets.only(left: 62, right: 62, bottom: 20);

    // The rail covers the inset on its own edge, as it always did. The one on
    // the far edge used to be counted as pane width and is not any more: the
    // detail bleeds under it, so it was never width the screen could use.
    test('the trailing inset comes off the pane area', () {
      expect(
        PaneMetrics.paneAreaWidth(
          window: window.width,
          padding: padding,
          placement: defaultChromeLayout(window, padding),
          railWidth: kDefaultRailWidth,
          panes: PaneDecoration.none,
        ),
        window.width - kDefaultRailWidth - kDefaultRailDividerWidth - 62,
      );
    });

    testWidgets('the detail still reaches the window edge', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, window, padding: padding);
      final DemoHarness h = DemoHarness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      final Finder detail = find.byType(DemoDetailScreen);
      expect(tester.getRect(detail).right, window.width);
      expect(MediaQuery.of(tester.element(detail)).padding.right, 62);
    });
  });

  // A bottom bar no longer implies a single pane. On every stock device the
  // width decides as before — a phone is far under the default minimums — but
  // an app that lowered them gets the split it asked for where it used to get
  // a stack.
  group('a bar with two panes above it', () {
    const Size phone = Size(402, 874);
    const EdgeInsets padding = EdgeInsets.only(top: 62, bottom: 34);

    testWidgets('the package defaults still give a stack', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, phone, padding: padding);
      final DemoHarness h = DemoHarness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester
            .getRect(find.byType(DemoDetailScreen))
            .overlaps(tester.getRect(find.byType(DemoListScreen))),
        isTrue,
        reason: 'the detail covers the master, as it always did',
      );
    });

    // Below the compact breakpoint a phone is one screen, however low the
    // minimums: the split over a bar is for a window at least 600 across.
    testWidgets('minimums small enough still give a stack', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, phone, padding: padding);
      final DemoHarness h = DemoHarness(
        masterMinWidth: 180,
        detailMinWidth: 180,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester
            .getRect(find.byType(DemoDetailScreen))
            .overlaps(tester.getRect(find.byType(DemoListScreen))),
        isTrue,
      );
    });
  });

  // The rail's destination height is computed from the label, and Material
  // takes its style from the rail's own theme before the text theme. Reading
  // only the latter counted a themed rail at the wrong height and overflowed
  // it by hundreds of pixels.
  testWidgets('a themed rail label is counted at its real height', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
    final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
    final List<String> errors = <String>[];
    FlutterError.onError = (FlutterErrorDetails d) =>
        errors.add(d.exception.toString().split('\n').first);
    final DemoHarness h = DemoHarness(
      extraBranches: 10,
      railLabelStyle: const TextStyle(fontSize: 28),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    FlutterError.onError = previous;

    expect(errors, isEmpty);
  });
}
