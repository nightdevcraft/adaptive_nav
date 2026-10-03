import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Parting the panes around a half-opened device's crease.
///
/// The framework fills `MediaQuery.displayFeatures` on Android today and not
/// yet on iOS, so on iPhone Duo none of this fires — the tests inject the
/// feature directly, which is also the only way to reach a half-opened posture
/// at all: Xcode 27.1's simulator offers open, closed and rotate, and nothing
/// in between.
void main() {
  const Size window = Size(1000, 800);
  // A crease 40 wide down the middle, the width the Duo's division region is
  // reported at.
  const double creaseStart = 480;
  const double creaseEnd = 520;

  DisplayFeature fold({
    DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
    Rect? bounds,
  }) => DisplayFeature(
    bounds: bounds ?? const Rect.fromLTRB(creaseStart, 0, creaseEnd, 800),
    type: DisplayFeatureType.fold,
    state: state,
  );

  Future<DemoHarness> pump(
    WidgetTester tester, {
    List<DisplayFeature> features = const <DisplayFeature>[],
    bool alignToFold = true,
    PaneSplitController? split,
    Size size = window,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, size);
    tester.view.displayFeatures = features;
    final DemoHarness h = DemoHarness(
      alignToFold: alignToFold,
      paneSplit: split,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return h;
  }

  Rect master(WidgetTester tester) =>
      tester.getRect(find.byType(DemoListScreen));
  Rect detail(WidgetTester tester) =>
      tester.getRect(find.byType(DemoDetailScreen));

  group('the crease takes the boundary', () {
    testWidgets('the panes sit either side of it, not across it', (
      WidgetTester tester,
    ) async {
      await pump(tester, features: <DisplayFeature>[fold()]);

      expect(master(tester).right, creaseStart);
      expect(detail(tester).left, creaseEnd);
      // Nothing is drawn in the crease itself.
      expect(
        detail(tester).left - master(tester).right,
        creaseEnd - creaseStart,
      );
    });

    testWidgets('and the divider cannot be dragged off it', (
      WidgetTester tester,
    ) async {
      final PaneSplitController split = PaneSplitController();
      addTearDown(split.dispose);
      await pump(tester, features: <DisplayFeature>[fold()], split: split);

      // The hinge decided; a handle would be a lie.
      expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
      expect(master(tester).right, creaseStart);
    });

    testWidgets('a drag from before the fold is overridden while it lasts', (
      WidgetTester tester,
    ) async {
      final PaneSplitController split = PaneSplitController(
        initial: <Object, double>{'staff': 0.7},
      );
      addTearDown(split.dispose);

      await pump(tester, split: split);
      final double dragged = master(tester).right;
      expect(dragged, greaterThan(creaseEnd));

      // Half open: the crease wins.
      tester.view.displayFeatures = <DisplayFeature>[fold()];
      await tester.pumpAndSettle();
      expect(master(tester).right, creaseStart);

      // Flat again: the user's width comes back, so the boundary moved once
      // and once back rather than settling somewhere new.
      tester.view.displayFeatures = const <DisplayFeature>[];
      await tester.pumpAndSettle();
      expect(master(tester).right, dragged);
    });
  });

  group('what is not a boundary', () {
    testWidgets('a flat posture: a crease on a continuous display', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(state: DisplayFeatureState.postureFlat),
        ],
      );
      expect(master(tester).right, isNot(creaseStart));
    });

    testWidgets('a horizontal fold: wrong axis', (WidgetTester tester) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(bounds: const Rect.fromLTRB(0, 380, 1000, 420)),
        ],
      );
      expect(master(tester).right, isNot(creaseStart));
    });

    // An under-display camera is reported the same way a fold is. The
    // framework will not even let one carry a posture — `DisplayFeature`
    // asserts on it — which is the same reasoning: a cutout does not divide
    // the display, it only occludes part of it.
    testWidgets('a cutout is not a fold', (WidgetTester tester) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          const DisplayFeature(
            bounds: Rect.fromLTRB(creaseStart, 0, creaseEnd, 200),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ],
      );
      expect(master(tester).right, isNot(creaseStart));
    });

    // 120 from the left of a 919-wide pane area leaves the master under its
    // 320 minimum, so the width decides after all rather than squeezing it.
    testWidgets('a fold too near one edge for both minimums', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(bounds: const Rect.fromLTRB(120, 0, 160, 800)),
        ],
      );
      expect(master(tester).right, isNot(120));
      expect(master(tester).width, greaterThanOrEqualTo(320));
    });

    testWidgets('alignToFold: false leaves the ratio alone', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[fold()],
        alignToFold: false,
      );
      expect(master(tester).right, isNot(creaseStart));
    });
  });

  group('an app can say where the crease is', () {
    // On iOS there is nothing to read, so the app asserts it. The Duo's hinge
    // is a centre one, which is what `windowCentre` says.
    testWidgets('a locator fills the silence displayFeatures leaves', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, window);
      final DemoHarness h = DemoHarness(foldLocator: FoldMetrics.windowCentre);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(DemoListScreen)).right, 500);
      expect(tester.getRect(find.byType(DemoDetailScreen)).left, 500);
    });

    testWidgets('a real fold still wins over it', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setPose(tester, window);
      tester.view.displayFeatures = <DisplayFeature>[fold()];
      final DemoHarness h = DemoHarness(foldLocator: FoldMetrics.windowCentre);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      // 480, the reported crease — not 500, the guess.
      expect(tester.getRect(find.byType(DemoListScreen)).right, creaseStart);
    });

    testWidgets('and alignToFold: false silences it too', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, window);
      final DemoHarness h = DemoHarness(
        foldLocator: FoldMetrics.windowCentre,
        alignToFold: false,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(DemoListScreen)).right, isNot(500));
    });
  });

  group('FoldMetrics reads the feature list', () {
    test('bounds arrive in pane-area coordinates', () {
      final PaneFold? f = FoldMetrics.paneFold(
        features: <DisplayFeature>[fold()],
        origin: 81,
        paneArea: 919,
      );
      expect(f, const PaneFold(start: creaseStart - 81, end: creaseEnd - 81));
      expect(f!.width, 40);
    });

    test('a fold outside the pane area is none of its business', () {
      expect(
        FoldMetrics.paneFold(
          features: <DisplayFeature>[
            fold(bounds: const Rect.fromLTRB(20, 0, 60, 800)),
          ],
          origin: 81,
          paneArea: 919,
        ),
        isNull,
      );
    });

    test('an empty list is the iOS case, and says nothing', () {
      expect(
        FoldMetrics.paneFold(
          features: const <DisplayFeature>[],
          origin: 0,
          paneArea: 919,
        ),
        isNull,
      );
    });
  });
}
