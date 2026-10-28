import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Borders on the shell's floating cards: declared, painted over the content
/// and outside the clip, and moving nothing.
void main() {
  const double gutter = 8;
  const double radius = 12;
  const Color line = Color(0xFFD7DFE9);

  BoxBorder border(BuildContext _) => Border.all(color: line);

  RailDecoration railWith({required bool bordered}) => RailDecoration(
    margin: const EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    radius: BorderRadius.circular(radius),
    dividerWidth: 0,
    border: bordered ? border : null,
  );

  PaneDecoration panesWith({required bool bordered}) => PaneDecoration(
    margin: const EdgeInsets.all(gutter),
    gap: gutter,
    radius: BorderRadius.circular(radius),
    border: bordered ? border : null,
  );

  Future<DemoHarness> pumpWide(
    WidgetTester tester, {
    required bool bordered,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(1000, 900));
    final DemoHarness h = DemoHarness(
      rail: railWith(bordered: bordered),
      panes: panesWith(bordered: bordered),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return h;
  }

  /// The border layer: a `DecoratedBox` with a frame OVER the content.
  Finder borderBox() => find.byWidgetPredicate((Widget w) {
    if (w is! DecoratedBox || w.position != DecorationPosition.foreground) {
      return false;
    }
    final Decoration decoration = w.decoration;
    return decoration is BoxDecoration && decoration.border != null;
  });

  Finder borderAround(Finder of) =>
      find.ancestor(of: of, matching: borderBox());

  testWidgets('the rail and both panes get the border', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, bordered: true);

    for (final Finder target in <Finder>[
      find.byType(NavigationRail),
      find.byType(DemoListScreen),
      find.byType(DemoDetailScreen),
    ]) {
      expect(borderAround(target), findsOneWidget);
    }
  });

  // The line has to lie OVER the content: in the background the opaque fill of
  // the screen inside the card would cover it and nothing would be left.
  testWidgets('the line is painted over the content and outside the clip', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, bordered: true);

    final DecoratedBox box = tester.widget<DecoratedBox>(
      borderAround(find.byType(NavigationRail)),
    );
    expect(box.position, DecorationPosition.foreground);

    final BoxDecoration decoration = box.decoration as BoxDecoration;
    expect(decoration.border, Border.all(color: line));
    // The line radius matches the card radius, or the frame would sit as a
    // rectangle over the rounded corners.
    expect(decoration.borderRadius, BorderRadius.circular(radius));

    expect(
      find.descendant(
        of: borderAround(find.byType(NavigationRail)),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is ClipRRect && w.borderRadius == BorderRadius.circular(radius),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no border means no extra layer', (WidgetTester tester) async {
    await pumpWide(tester, bordered: false);

    expect(borderBox(), findsNothing);
  });

  // The border is decoration rather than geometry: it is painted inside the
  // card's bounds and adds no size.
  testWidgets('the border moves neither the rail nor the panes', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, bordered: false);
    final Rect rail = tester.getRect(find.byType(NavigationRail));
    final Rect master = tester.getRect(find.byType(DemoListScreen));
    final Rect detail = tester.getRect(find.byType(DemoDetailScreen));

    await pumpWide(tester, bordered: true);

    expect(tester.getRect(find.byType(NavigationRail)), rail);
    expect(tester.getRect(find.byType(DemoListScreen)), master);
    expect(tester.getRect(find.byType(DemoDetailScreen)), detail);
  });
}
