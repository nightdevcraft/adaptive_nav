import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// There must be no `LayoutBuilder` between the shell and the branch screens.
///
/// With one there, crossing a threshold moved the branch navigators by
/// `GlobalKey` from inside the layout callback, and a device crashed with
/// "_RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout"
/// the moment a deferred overlay child reactivated. None of the attempts to
/// reproduce that in `flutter test` worked, so this locks down the cause
/// instead. Red on the old code, in both layouts.
void main() {
  /// Widget types between [screen] and the app root. We walk up to
  /// `MaterialApp` rather than to `AdaptiveShell`: the `LayoutBuilder` used to
  /// be in TWO places — around the panes inside the shell, and around the
  /// shell itself in the delegate.
  List<String> ancestorsUpToApp(WidgetTester tester, Finder screen) {
    final List<String> types = <String>[];
    bool reachedApp = false;
    tester.element(screen).visitAncestorElements((Element e) {
      if (e.widget.runtimeType.toString().startsWith('MaterialApp')) {
        reachedApp = true;
        return false;
      }
      types.add(e.widget.runtimeType.toString());
      return true;
    });
    expect(reachedApp, isTrue, reason: 'the screen is not under MaterialApp');
    return types;
  }

  // The layout is computed FROM THE DECLARED rail width, so the package has to
  // hold the actual widget to it. Otherwise a rail growing with the length of
  // its labels would quietly eat into the panes and push the detail off the
  // edge of the screen.
  testWidgets('the rail is held to the declared railWidth', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(900, 900));

    final DemoHarness h = DemoHarness(
      railBuilder: (BuildContext _, int _, ValueChanged<int> _) =>
          const SizedBox(
            width: 300,
            key: ValueKey<String>('greedy-rail'),
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('greedy-rail'))).width,
      kDefaultRailWidth,
    );
  });

  // `contentWidth` is no longer measured but COMPUTED, so it has to match the
  // actual area to the pixel: the panes are laid out with absolute widths, and
  // an error would leave either a gap on the right or a detail past the edge.
  for (final double width in <double>[900, 1000, 1234, 1600]) {
    testWidgets('width $width: the panes fill the area with no gap', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, Size(width, 900));

      final DemoHarness h = DemoHarness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      // The master starts right after the rail and its divider, the detail
      // reaches the right window edge, and between the panes there is exactly
      // the decoration gap (none here: `PaneDecoration.none`, panes flush).
      expect(master.left, kDefaultRailWidth + 1);
      expect(detail.left, master.right);
      expect(detail.right, width);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (String label, Size size) in <(String, Size)>[
    ('compact (bar)', Size(500, 900)),
    ('wide, one pane', Size(700, 900)),
    ('wide, two panes', Size(900, 900)),
  ]) {
    testWidgets('$label: there is no LayoutBuilder above the branch screens', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, size);

      final DemoHarness h = DemoHarness();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      for (final Finder screen in <Finder>[
        find.byType(DemoListScreen),
        find.byType(DemoDetailScreen),
      ]) {
        expect(
          ancestorsUpToApp(
            tester,
            screen,
          ).where((String t) => t.startsWith('LayoutBuilder')),
          isEmpty,
          reason: 'the layout is decided inside a LayoutBuilder',
        );
      }
    });
  }
}
