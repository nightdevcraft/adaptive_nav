import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
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

  // The system column's tabs gave up their reserve for a toolbar and moved 6
  // apart; the bar and the rail everywhere else are not that code, and keep
  // every destination where it was.
  group('the bar and the rail, with two and ten tabs', () {
    final List<(String, Size, EdgeInsets, TargetPlatform)> devices =
        <(String, Size, EdgeInsets, TargetPlatform)>[
          (
            'phone',
            const Size(402, 874),
            const EdgeInsets.only(top: 62, bottom: 34),
            TargetPlatform.iOS,
          ),
          (
            'tablet',
            const Size(1180, 820),
            const EdgeInsets.only(top: 24, bottom: 20),
            TargetPlatform.iOS,
          ),
          (
            'desktop',
            const Size(1440, 900),
            EdgeInsets.zero,
            TargetPlatform.macOS,
          ),
        ];
    for (final (
          String name,
          Size window,
          EdgeInsets padding,
          TargetPlatform platform,
        )
        in devices) {
      for (final int count in <int>[2, 10]) {
        testWidgets('$name, $count tabs', (WidgetTester tester) async {
          addTearDown(tester.view.reset);
          setPose(tester, window, padding: padding);
          final DemoHarness h = DemoHarness(
            extraBranches: count - 2,
            platform: platform,
          );
          await tester.pumpWidget(h.app());
          await tester.pumpAndSettle();

          expect(find.byKey(AdaptiveShell.systemColumnKey), findsNothing);
          final Finder chrome = find.byWidgetPredicate(
            (Widget w) => w is NavigationBar || w is NavigationRail,
          );
          expect(chrome, findsOneWidget);
          String rect(Rect r) =>
              '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},'
              '${r.width.toStringAsFixed(1)},${r.height.toStringAsFixed(1)}';
          final List<String> seen = <String>[
            tester.widget(chrome).runtimeType.toString(),
            rect(tester.getRect(chrome)),
            for (final Element e
                in find
                    .descendant(of: chrome, matching: find.byType(Icon))
                    .evaluate())
              rect(
                (e.renderObject! as RenderBox).localToGlobal(Offset.zero) &
                    (e.renderObject! as RenderBox).size,
              ),
          ];
          expect(seen.join(' '), _chrome['$name $count']);
        });
      }
    }
  });
}

/// What the bar or the rail looked like before the column changed: its type,
/// its rect and each icon's, left, top, width and height.
const Map<String, String> _chrome = <String, String>{
  'phone 2':
      'NavigationBar 0.0,760.0,402.0,114.0 88.5,778.0,24.0,24.0 289.5,778.0,24.0,24.0',
  'phone 10':
      'NavigationBar 0.0,760.0,402.0,114.0 8.1,770.0,24.0,24.0 48.3,770.0,24.0,24.0 88.5,762.0,24.0,24.0 128.7,762.0,24.0,24.0 168.9,762.0,24.0,24.0 209.1,762.0,24.0,24.0 249.3,762.0,24.0,24.0 289.5,762.0,24.0,24.0 329.7,762.0,24.0,24.0 369.9,762.0,24.0,24.0',
  'tablet 2':
      'NavigationRail 0.0,24.0,80.0,796.0 28.0,36.0,24.0,24.0 28.0,116.0,24.0,24.0',
  'tablet 10':
      'NavigationRail 0.0,24.0,80.0,796.0 28.0,36.0,24.0,24.0 28.0,116.0,24.0,24.0 28.0,180.0,24.0,24.0 28.0,260.0,24.0,24.0 28.0,340.0,24.0,24.0 28.0,420.0,24.0,24.0 28.0,500.0,24.0,24.0 28.0,580.0,24.0,24.0 28.0,660.0,24.0,24.0 28.0,752.0,24.0,24.0',
  'desktop 2':
      'NavigationRail 0.0,0.0,80.0,900.0 28.0,12.0,24.0,24.0 28.0,92.0,24.0,24.0',
  'desktop 10':
      'NavigationRail 0.0,0.0,80.0,900.0 28.0,12.0,24.0,24.0 28.0,92.0,24.0,24.0 28.0,156.0,24.0,24.0 28.0,236.0,24.0,24.0 28.0,316.0,24.0,24.0 28.0,396.0,24.0,24.0 28.0,476.0,24.0,24.0 28.0,556.0,24.0,24.0 28.0,636.0,24.0,24.0 28.0,716.0,24.0,24.0',
};
