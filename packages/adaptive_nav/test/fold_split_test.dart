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
/// yet on iOS; on iPhone Duo the fold comes from adaptive_nav_ios through
/// [SystemGeometryScope] instead. The tests inject both directly.
void main() {
  const Size window = Size(1000, 800);
  // A crease 40 wide down the middle, the width the Duo's division region is
  // reported at. The panes meet on its middle, each 20 clear of it.
  const double creaseStart = 480;
  const double creaseEnd = 520;
  const double hinge = 500;

  DisplayFeature fold({
    DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
    DisplayFeatureType type = DisplayFeatureType.fold,
    Rect? bounds,
  }) => DisplayFeature(
    bounds: bounds ?? const Rect.fromLTRB(creaseStart, 0, creaseEnd, 800),
    type: type,
    state: state,
  );

  Future<DemoHarness> pump(
    WidgetTester tester, {
    List<DisplayFeature> features = const <DisplayFeature>[],
    bool alignToFold = true,
    PaneSplitController? split,
    PaneDecoration panes = PaneDecoration.none,
    FoldLocator? foldLocator,
    Size size = window,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, size);
    tester.view.displayFeatures = features;
    final DemoHarness h = DemoHarness(
      alignToFold: alignToFold,
      paneSplit: split,
      panes: panes,
      foldLocator: foldLocator,
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
  // What each screen keeps clear on the hinge's side.
  double masterInset(WidgetTester tester) =>
      MediaQuery.paddingOf(tester.element(find.byType(DemoListScreen))).right;
  double detailInset(WidgetTester tester) =>
      MediaQuery.paddingOf(tester.element(find.byType(DemoDetailScreen))).left;

  group('the crease takes the boundary', () {
    testWidgets('the panes meet on it, and the crease is their inset', (
      WidgetTester tester,
    ) async {
      await pump(tester, features: <DisplayFeature>[fold()]);

      // The backgrounds reach the hinge, so the seam is where the device
      // bends rather than 20 past it.
      expect(master(tester).right, hinge);
      expect(detail(tester).left, hinge);
      // The content is kept off the crease the way it is kept off a safe-area
      // inset: through the padding the screens see.
      expect(masterInset(tester), 20);
      expect(detailInset(tester), 20);
    });

    testWidgets('and the divider cannot be dragged off it', (
      WidgetTester tester,
    ) async {
      final PaneSplitController split = PaneSplitController();
      addTearDown(split.dispose);
      await pump(tester, features: <DisplayFeature>[fold()], split: split);

      // The hinge decided; a handle would be a lie.
      expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
      expect(master(tester).right, hinge);
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
      expect(master(tester).right, hinge);

      // Flat again: the user's width comes back, so the boundary moved once
      // and once back rather than settling somewhere new, and the inset goes
      // with the fold.
      tester.view.displayFeatures = const <DisplayFeature>[];
      await tester.pumpAndSettle();
      expect(master(tester).right, dragged);
      expect(masterInset(tester), 0);
      expect(detailInset(tester), 0);
    });

    // Android reports a hinge with the width of the gap between the two
    // screens, and a fold on a continuous display as a line. Both meet on the
    // middle; only the hinge has anything to keep the content off.
    testWidgets('a hinge with width: the same rule', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(
            type: DisplayFeatureType.hinge,
            bounds: const Rect.fromLTRB(485, 0, 515, 800),
          ),
        ],
      );

      expect(master(tester).right, hinge);
      expect(detail(tester).left, hinge);
      expect(masterInset(tester), 15);
      expect(detailInset(tester), 15);
    });

    testWidgets('a fold as a line: the seam on it, nothing to clear', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(bounds: const Rect.fromLTRB(hinge, 0, hinge, 800)),
        ],
      );

      expect(master(tester).right, hinge);
      expect(detail(tester).left, hinge);
      expect(masterInset(tester), 0);
      expect(detailInset(tester), 0);
    });
  });

  group('cards around the hinge', () {
    const PaneDecoration cards = PaneDecoration(
      margin: EdgeInsets.all(12),
      gap: 8,
      radius: BorderRadius.all(Radius.circular(16)),
    );

    testWidgets('the gap is split evenly around it, the rest is inset', (
      WidgetTester tester,
    ) async {
      await pump(tester, features: <DisplayFeature>[fold()], panes: cards);

      expect(master(tester).right, hinge - 4);
      expect(detail(tester).left, hinge + 4);
      // 4 of gap and 16 of inset on either side: the content is off the
      // whole crease, as without cards.
      expect(masterInset(tester), 16);
      expect(detailInset(tester), 16);
      expect(master(tester).right - masterInset(tester), creaseStart);
      expect(detail(tester).left + detailInset(tester), creaseEnd);
    });

    testWidgets('a line: only the gap, centred on it', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(bounds: const Rect.fromLTRB(hinge, 0, hinge, 800)),
        ],
        panes: cards,
      );

      expect(master(tester).right, hinge - 4);
      expect(detail(tester).left, hinge + 4);
      expect(masterInset(tester), 0);
      expect(detailInset(tester), 0);
    });

    testWidgets('a gap wider than the crease leaves no inset', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        features: <DisplayFeature>[fold()],
        panes: const PaneDecoration(margin: EdgeInsets.all(12), gap: 48),
      );

      expect(master(tester).right, hinge - 24);
      expect(detail(tester).left, hinge + 24);
      expect(masterInset(tester), 0);
      expect(detailInset(tester), 0);
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
      expect(master(tester).right, isNot(hinge));
    });

    testWidgets('a horizontal fold: wrong axis', (WidgetTester tester) async {
      await pump(
        tester,
        features: <DisplayFeature>[
          fold(bounds: const Rect.fromLTRB(0, 380, 1000, 420)),
        ],
      );
      expect(master(tester).right, isNot(hinge));
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
      expect(master(tester).right, isNot(hinge));
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
      expect(master(tester).right, isNot(hinge));
    });
  });

  group('an app can say where the crease is', () {
    // `windowCentre` is deprecated — it has no posture — but it is still a
    // locator, and these pin what any locator does.
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
      // A line: nothing to keep the content off.
      expect(masterInset(tester), 0);
      expect(detailInset(tester), 0);
    });

    testWidgets('a real fold still wins over it', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setPose(tester, window);
      tester.view.displayFeatures = <DisplayFeature>[
        fold(bounds: const Rect.fromLTRB(520, 0, 560, 800)),
      ];
      final DemoHarness h = DemoHarness(foldLocator: FoldMetrics.windowCentre);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      // 540, the middle of the reported crease — not 500, the guess.
      expect(tester.getRect(find.byType(DemoListScreen)).right, 540);
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

  group('a platform package reports the fold', () {
    Future<void> pumpWith(
      WidgetTester tester,
      List<Rect> folds, {
      List<DisplayFeature> features = const <DisplayFeature>[],
      FoldLocator? foldLocator,
    }) async {
      addTearDown(tester.view.reset);
      setPose(tester, window);
      tester.view.displayFeatures = features;
      final DemoHarness h = DemoHarness(
        system: SystemGeometry(folds: folds),
        foldLocator: foldLocator,
      );
      await tester.pumpWidget(h.app());
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
    }

    const Rect crease = Rect.fromLTRB(creaseStart, 0, creaseEnd, 800);

    testWidgets('an active fold takes the boundary', (
      WidgetTester tester,
    ) async {
      await pumpWith(tester, const <Rect>[crease]);

      expect(master(tester).right, hinge);
      expect(detail(tester).left, hinge);
      expect(masterInset(tester), 20);
      expect(detailInset(tester), 20);
    });

    testWidgets('displayFeatures comes first', (WidgetTester tester) async {
      await pumpWith(
        tester,
        const <Rect>[crease],
        features: <DisplayFeature>[
          fold(bounds: const Rect.fromLTRB(500, 0, 540, 800)),
        ],
      );

      expect(master(tester).right, 520);
    });

    testWidgets('and the app\'s locator comes last', (
      WidgetTester tester,
    ) async {
      await pumpWith(
        tester,
        const <Rect>[crease],
        foldLocator: (Size window, EdgeInsets padding) =>
            const Rect.fromLTRB(560, 0, 560, 800),
      );

      expect(master(tester).right, hinge);
    });

    testWidgets('a horizontal fold is not a boundary', (
      WidgetTester tester,
    ) async {
      await pumpWith(tester, const <Rect>[Rect.fromLTRB(0, 380, 1000, 420)]);

      expect(master(tester).right, isNot(hinge));
    });

    test('in pane coordinates, inside the pane area only', () {
      expect(
        FoldMetrics.fromRects(
          folds: const <Rect>[crease],
          origin: 81,
          paneArea: 919,
        ),
        const PaneFold(start: creaseStart - 81, end: creaseEnd - 81),
      );
      expect(
        FoldMetrics.fromRects(
          folds: const <Rect>[Rect.fromLTRB(20, 0, 60, 800)],
          origin: 81,
          paneArea: 919,
        ),
        isNull,
      );
      // A horizontal one first does not hide a vertical one after it.
      expect(
        FoldMetrics.fromRects(
          folds: const <Rect>[Rect.fromLTRB(0, 380, 1000, 420), crease],
          origin: 0,
          paneArea: 1000,
        ),
        const PaneFold(start: creaseStart, end: creaseEnd),
      );
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
      expect(f.centre, hinge - 81);
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

    testWidgets('a fold that would squeeze the detail past the gap is '
        'ignored', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      // Pane area 659, the window centre at 289 in it: 370 is left for the
      // detail, 354 once the 16 of gap comes off.
      setPose(tester, const Size(740, 800));
      final DemoHarness h = DemoHarness(
        masterMinWidth: 200,
        foldLocator: FoldMetrics.windowCentre,
        panes: const PaneDecoration(gap: 16),
      );
      await tester.pumpWidget(h.app());
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(detail(tester).width, greaterThanOrEqualTo(360));
    });

    test('the pane gap counts against the detail around a fold', () {
      const MasterDetailConfig md = MasterDetailConfig(
        masterMinWidth: 320,
        detailMinWidth: 360,
      );
      const PaneFold line = PaneFold(start: 360, end: 360);
      expect(md.fitsAround(line, 720), isTrue);
      expect(md.fitsAround(line, 720, gap: 16), isFalse);
      // A crease wider than the gap is the gap.
      const PaneFold crease = PaneFold(start: 340, end: 360);
      expect(md.fitsAround(crease, 720, gap: 16), isTrue);
    });

    test('the minimums are the content, the crease\'s inset off', () {
      const MasterDetailConfig md = MasterDetailConfig(
        masterMinWidth: 320,
        detailMinWidth: 360,
      );
      // Meeting on 350, each pane has 20 of it to keep clear: 330 and 350
      // to show, and the detail is short.
      expect(md.fitsAround(const PaneFold(start: 330, end: 370), 720), isFalse);
      // On 340 the detail shows 360 and the master 320, both just enough.
      expect(md.fitsAround(const PaneFold(start: 320, end: 360), 720), isTrue);
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
