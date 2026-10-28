import 'package:adaptive_nav/adaptive_nav.dart';
// ignore: implementation_imports
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A detail covering the single pane on iPhone Duo stands beside the
/// system's column, not under it: the column keeps its status area, its
/// background and the screen's toolbar, and only the tabs go. Postures 1–3,
/// as adaptive_nav_ios reports them on the simulator.
void main() {
  const List<
    ({int pose, Size window, EdgeInsets padding, SystemGeometry system})
  >
  poses =
      <({int pose, Size window, EdgeInsets padding, SystemGeometry system})>[
        (
          pose: 1,
          window: Size(466, 678),
          padding: EdgeInsets.only(right: 84, bottom: 34),
          system: SystemGeometry(
            verticalBar: ChromePlacement.right,
            statusArea: Rect.fromLTRB(382, 0, 466, 170),
          ),
        ),
        (
          pose: 2,
          window: Size(678, 466),
          padding: EdgeInsets.only(left: 84, bottom: 34),
          system: SystemGeometry(
            verticalBar: ChromePlacement.left,
            statusArea: Rect.fromLTRB(0, 0, 84, 82),
          ),
        ),
        (
          pose: 3,
          window: Size(678, 466),
          padding: EdgeInsets.only(right: 84, bottom: 34),
          system: SystemGeometry(
            verticalBar: ChromePlacement.right,
            statusArea: Rect.fromLTRB(594, 384, 678, 466),
          ),
        ),
      ];

  for (final (
        pose: int number,
        window: Size window,
        padding: EdgeInsets padding,
        system: SystemGeometry system,
      )
      in poses) {
    testWidgets('pose $number: Ada and her editor stay out of the column', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      final double dpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = window * dpr;
      tester.view.padding = FakeViewPadding(
        left: padding.left * dpr,
        right: padding.right * dpr,
        bottom: padding.bottom * dpr,
      );
      await tester.pumpWidget(
        SystemGeometryScope(
          geometry: system,
          child: Theme(
            data: ThemeData(platform: TargetPlatform.iOS),
            child: const ExampleApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bool onLeft = system.verticalBar == ChromePlacement.left;
      // The system's column: its inset and the toolbar standing in it.
      final Rect toolbar = tester.getRect(
        find.byKey(AdaptiveShell.bareColumnKey),
      );
      final Rect inset = onLeft
          ? Rect.fromLTRB(0, 0, padding.left, window.height)
          : Rect.fromLTRB(
              window.width - padding.right,
              0,
              window.width,
              window.height,
            );
      final Rect column = inset.expandToInclude(toolbar);
      // The people list, the single pane beside the column.
      final Finder people = find.ancestor(
        of: find.widgetWithText(AppBar, 'People'),
        matching: find.byType(Scaffold),
      );
      final Rect pane = tester.getRect(people.first);
      expect(pane.overlaps(column), isFalse);

      /// What of [finder] is in view: inside every clip above it.
      Rect seen(Finder finder) {
        Rect r = tester.getRect(finder);
        tester.element(finder).visitAncestorElements((Element e) {
          if (e.widget is ClipRect) {
            r = r.intersect(
              tester.getRect(find.byElementPredicate((x) => x == e)),
            );
          }
          return true;
        });
        return r;
      }

      bool clear(Rect r) => r.isEmpty || !r.overlaps(column);

      /// Runs a transition frame by frame, checking that what [finder]
      /// finds never reaches into the column.
      Future<void> frames(Finder finder, String what) async {
        for (int i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          for (final Element e in finder.evaluate()) {
            final Rect r = seen(find.byElementPredicate((x) => x == e));
            expect(clear(r), isTrue, reason: '$what, frame $i: $r');
          }
        }
        await tester.pumpAndSettle();
      }

      // Her screen's own scaffold and the one of the editor above it.
      final Finder adaScreens = find.ancestor(
        of: find.widgetWithText(AppBar, 'Ada Lovelace'),
        matching: find.byType(Scaffold),
      );
      final Finder adaBody = adaScreens.first;
      await tester.tap(find.text('Ada Lovelace'));
      await frames(adaScreens, 'opening Ada');
      expect(tester.getRect(adaBody), pane, reason: "the pane's area");
      expect(
        MediaQuery.paddingOf(tester.element(adaBody)),
        MediaQuery.paddingOf(tester.element(people.first)),
      );
      // The tabs have gone; the toolbar stays.
      expect(find.byTooltip('Starred').hitTestable(), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(AdaptiveShell.bareColumnKey),
          matching: find.byTooltip('Edit'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Edit'));
      await frames(find.byType(TextField), 'opening the editor');
      for (final Element e in find.byType(TextField).evaluate()) {
        final Rect field = tester.getRect(
          find.byElementPredicate((x) => x == e),
        );
        expect(field.overlaps(column), isFalse, reason: '$field');
        expect(pane.contains(field.topLeft), isTrue);
        expect(pane.contains(field.bottomRight), isTrue);
      }

      // Back to Ada, past the editor's guard, and to the list.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await frames(adaScreens, 'back to Ada');
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await frames(adaScreens, 'closing Ada');
      expect(find.byTooltip('Starred').hitTestable(), findsOneWidget);
    });
  }
}
