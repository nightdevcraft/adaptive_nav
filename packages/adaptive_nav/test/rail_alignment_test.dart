import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `AdaptiveShellConfig.railAlignment`: the destinations at the bottom of the
/// column, within reach of the thumb, and the overflow button at the top.
void main() {
  /// A window as short as the column the rail had on a folded iPhone Duo.
  const Size short = Size(900, 474);

  Future<List<String>> errorsDuring(Future<void> Function() body) async {
    final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
    final List<String> errors = <String>[];
    FlutterError.onError = (FlutterErrorDetails d) =>
        errors.add(d.exception.toString().split('\n').first);
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Finder inRail(Finder matching) =>
      find.descendant(of: find.byType(NavigationRail), matching: matching);

  List<String> labels(WidgetTester tester) => tester
      .widget<NavigationRail>(find.byType(NavigationRail))
      .destinations
      .map((NavigationRailDestination d) => (d.label as Text).data!)
      .toList();

  group('unset, the column decides', () {
    // A column of the rail's own: Material's top, the theme left to decide.
    testWidgets('a desktop window: top, the button after the last one', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, const Size(1200, 500));
      final DemoHarness h = DemoHarness(extraBranches: 10);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      final NavigationRail rail = tester.widget<NavigationRail>(
        find.byType(NavigationRail),
      );
      expect(rail.groupAlignment, isNull, reason: 'the theme still decides');
      expect(rail.leading, isNull);
      expect(rail.trailing, isNotNull);
      final Rect button = tester.getRect(
        find.byKey(AdaptiveShell.railOverflowKey),
      );
      final Rect last = tester.getRect(inRail(find.byIcon(Icons.star)).last);
      expect(button.top, greaterThan(last.bottom));
    });

    // In iPhone Duo's system column there is no `NavigationRail` to align:
    // the tabs have a zone of their own at the bottom of the column, whatever
    // the setting — see `system_column_test.dart`.
    for (final RailAlignment? alignment in <RailAlignment?>[
      null,
      ...RailAlignment.values,
    ]) {
      testWidgets('the system\'s column keeps its tabs at the bottom '
          '($alignment)', (WidgetTester tester) async {
        addTearDown(tester.view.reset);
        setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
        final DemoHarness h = DemoHarness(
          extraBranches: 10,
          railAlignment: alignment,
        );
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsNothing);
        final Rect more = tester.getRect(
          find.byKey(AdaptiveShell.railOverflowKey),
        );
        expect(
          more.center.dy,
          kDuoOuterPortrait.height -
              SystemBarMetrics.measured.columnInset -
              kPaneToolbarItemExtent / 2,
        );
      });
    }
  });

  group('bottom', () {
    testWidgets('a short window: the destinations at the bottom, the button '
        'above them', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setWindow(tester, short);
      final DemoHarness top = DemoHarness(
        extraBranches: 10,
        railAlignment: RailAlignment.top,
      );
      await tester.pumpWidget(top.app());
      await tester.pumpAndSettle();
      final List<String> atTop = labels(tester);
      final double lastAtTop = tester
          .getRect(inRail(find.byIcon(Icons.star)).last)
          .bottom;

      final DemoHarness h = DemoHarness(
        extraBranches: 10,
        railAlignment: RailAlignment.bottom,
      );
      final List<String> errors = await errorsDuring(() async {
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty, reason: 'the rail must never overflow');
      final NavigationRail rail = tester.widget<NavigationRail>(
        find.byType(NavigationRail),
      );
      expect(rail.groupAlignment, 1.0);
      expect(rail.trailing, isNull);
      expect(rail.leading, isNotNull);

      // The same destinations, in the same order: the last ones still go
      // behind the button. 410 of column less the 8 after the `leading` is
      // 402, and the five that fit take 384.
      expect(labels(tester), atTop);
      expect(labels(tester), hasLength(5));

      final Rect button = tester.getRect(
        find.byKey(AdaptiveShell.railOverflowKey),
      );
      final Rect first = tester.getRect(inRail(find.byIcon(Icons.people)));
      final Rect last = tester.getRect(inRail(find.byIcon(Icons.star)).last);
      expect(button.bottom, lessThan(first.top));
      expect(last.bottom, greaterThan(lastAtTop), reason: 'moved down');
      expect(last.bottom, lessThanOrEqualTo(short.height));
    });

    // Priorities pick which ones give way, not where the rest stand: the
    // same arithmetic, the same order, still gathered at the bottom.
    testWidgets('visibilityPriority: the order holds at the bottom too', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, short);
      final DemoHarness h = DemoHarness(
        extraBranches: 10,
        railAlignment: RailAlignment.bottom,
        visibilityPriorities: <int>[0, 0, for (int i = 0; i < 9; i++) 0, 1],
      );
      final List<String> errors = await errorsDuring(() async {
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty);
      expect(labels(tester), <String>[
        'People',
        'Home',
        'Extra 0',
        'Extra 1',
        'Extra 9',
      ]);
      final Rect button = tester.getRect(
        find.byKey(AdaptiveShell.railOverflowKey),
      );
      expect(
        button.bottom,
        lessThan(tester.getRect(inRail(find.byIcon(Icons.people))).top),
      );
    });

    testWidgets('the button still opens the hidden destinations', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, short);
      final DemoHarness h = DemoHarness(
        extraBranches: 10,
        railAlignment: RailAlignment.bottom,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extra 9'));
      await tester.pumpAndSettle();

      expect(h.delegate.state.activeBranch, 11);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        isNull,
      );
    });

    // The spacer `NavigationRail` adds after its `leading` is the one term the
    // top layout does not have. Forget it and this fails by exactly 8.
    testWidgets('no height overflows, at any count', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      for (final double height in <double>[
        400,
        466,
        500,
        678,
        700,
        951,
        1200,
      ]) {
        for (final int extra in <int>[0, 3, 10, 30]) {
          for (final bool short in <bool>[false, true]) {
            setWindow(tester, Size(900, height));
            final DemoHarness h = DemoHarness(
              extraBranches: extra,
              extraLabel: short ? (int i) => 'E$i' : null,
              railAlignment: RailAlignment.bottom,
            );
            final List<String> errors = await errorsDuring(() async {
              await tester.pumpWidget(h.app());
              await tester.pumpAndSettle();
            });
            expect(
              errors,
              isEmpty,
              reason:
                  'height $height with ${extra + 2} destinations, '
                  '${short ? 'short' : 'wrapping'} labels',
            );
          }
        }
      }
    });

    // Every pose of the outer display, the one with the camera at the bottom
    // of the column included: the reserve is at that end then, and the
    // destinations stop above it.
    testWidgets('every folded pose fits, the system bar at either end', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      for (final (Size size, EdgeInsets padding) in <(Size, EdgeInsets)>[
        (kDuoOuterPortrait, kDuoOuterPortraitPadding),
        (kDuoOuterLandscape, kDuoOuterLandscapePadding),
        (kDuoOuterLandscape, kDuoOuterLandscapeRightPadding),
      ]) {
        setPose(tester, size, padding: padding);
        final DemoHarness h = DemoHarness(
          extraBranches: 10,
          railAlignment: RailAlignment.bottom,
        );
        final List<String> errors = await errorsDuring(() async {
          await tester.pumpWidget(h.app());
          await tester.pumpAndSettle();
        });
        expect(errors, isEmpty, reason: '$size $padding');
        expect(find.byKey(AdaptiveShell.railOverflowKey), findsOneWidget);
      }
    });

    // Too short for two: the button alone, where the first destination would
    // be — the bottom of the column.
    testWidgets('a column too short for two keeps the button at the bottom', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, const Size(900, 200));
      final DemoHarness h = DemoHarness(
        extraBranches: 3,
        railAlignment: RailAlignment.bottom,
      );
      final List<String> errors = await errorsDuring(() async {
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty);
      expect(find.byType(NavigationRail), findsNothing);
      final Rect button = tester.getRect(
        find.byKey(AdaptiveShell.railOverflowKey),
      );
      expect(button.center.dy, greaterThan(100));
      expect(button.bottom, lessThanOrEqualTo(200));
    });
  });

  testWidgets('center: the button follows the group, nothing overflows', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, short);
    final DemoHarness h = DemoHarness(
      extraBranches: 10,
      railAlignment: RailAlignment.center,
    );
    final List<String> errors = await errorsDuring(() async {
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
    });

    expect(errors, isEmpty);
    final NavigationRail rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(rail.groupAlignment, 0.0);
    expect(rail.leading, isNull);
    expect(rail.trailing, isNotNull);
  });
}
