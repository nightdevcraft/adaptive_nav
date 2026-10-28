import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The rail card's shadow: outside the clip, and changing no geometry.
void main() {
  const double gutter = 8;
  const double radius = 12;
  const Color shadowColor = Color(0xFF163C74);

  RailDecoration railWith({required bool shadow}) => RailDecoration(
    margin: const EdgeInsets.only(left: gutter, top: gutter, bottom: gutter),
    radius: BorderRadius.circular(radius),
    dividerWidth: 0,
    shadow: shadow
        ? (BuildContext _) => const <BoxShadow>[
            BoxShadow(color: shadowColor, blurRadius: 24),
          ]
        : null,
  );

  Future<void> pumpWide(WidgetTester tester, RailDecoration rail) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(1000, 900));
    await tester.pumpWidget(DemoHarness(rail: rail).app());
    await tester.pumpAndSettle();
  }

  /// The `DecoratedBox` with a non-empty shadow around the rail.
  Finder shadowBox() => find.ancestor(
    of: find.byType(NavigationRail),
    matching: find.byWidgetPredicate((Widget w) {
      if (w is! DecoratedBox) {
        return false;
      }
      final Decoration decoration = w.decoration;
      return decoration is BoxDecoration &&
          (decoration.boxShadow?.isNotEmpty ?? false);
    }),
  );

  testWidgets('a declared shadow wraps the rail in a DecoratedBox', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, railWith(shadow: true));

    expect(shadowBox(), findsOneWidget);

    final BoxDecoration decoration =
        tester.widget<DecoratedBox>(shadowBox()).decoration as BoxDecoration;
    expect(decoration.boxShadow!.single.color, shadowColor);
    // The shadow radius matches the card radius, or the shadow would show as
    // a rectangle from under the rounded corners.
    expect(decoration.borderRadius, BorderRadius.circular(radius));
  });

  // The shadow is painted AROUND the clip rather than inside it: `ClipRRect`
  // would cut away everything past the radius, the shadow included.
  testWidgets('the shadow DecoratedBox is OUTSIDE the card ClipRRect', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, railWith(shadow: true));

    expect(
      find.descendant(
        of: shadowBox(),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is ClipRRect && w.borderRadius == BorderRadius.circular(radius),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no shadow means no extra layer', (WidgetTester tester) async {
    await pumpWide(tester, railWith(shadow: false));

    expect(shadowBox(), findsNothing);
  });

  // The shadow is decoration rather than geometry: neither the rail region nor
  // the space for the panes moves by a pixel.
  testWidgets('the shadow moves neither the rail nor the panes', (
    WidgetTester tester,
  ) async {
    await pumpWide(tester, railWith(shadow: false));
    final Rect railWithout = tester.getRect(find.byType(NavigationRail));
    final Rect masterWithout = tester.getRect(find.byType(DemoListScreen));

    await pumpWide(tester, railWith(shadow: true));

    expect(tester.getRect(find.byType(NavigationRail)), railWithout);
    expect(tester.getRect(find.byType(DemoListScreen)), masterWithout);
  });
}
