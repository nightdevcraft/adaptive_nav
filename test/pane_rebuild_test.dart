import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// A drag, the detail reveal and the immersive slide animate geometry every
/// frame; none of it should rebuild the screens.
void main() {
  Future<(DemoHarness, List<DemoRoute>)> pump(
    WidgetTester tester, {
    PaneSplitController? split,
    ValueNotifier<bool>? immersive,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    final List<DemoRoute> built = <DemoRoute>[];
    final DemoHarness h = DemoHarness(
      paneSplit: split,
      immersive: immersive,
      wrapPage: (DemoRoute route, Widget screen) {
        built.add(route);
        return screen;
      },
    );
    await tester.pumpWidget(h.app());
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    return (h, built);
  }

  testWidgets('a drag does not call pageBuilder', (WidgetTester tester) async {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    final (_, List<DemoRoute> built) = await pump(tester, split: split);
    built.clear();

    final TestGesture drag = await tester.startGesture(
      tester.getCenter(find.byKey(AdaptiveShell.paneSplitHandleKey)),
    );
    for (int i = 0; i < 5; i++) {
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(split.fractionOf('staff'), isNotNull);
    expect(built, isEmpty);
  });

  testWidgets('the immersive slide does not call pageBuilder', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);
    addTearDown(immersive.dispose);
    final (_, List<DemoRoute> built) = await pump(tester, immersive: immersive);
    built.clear();

    immersive.value = true;
    await tester.pumpAndSettle();

    expect(built, isEmpty);
  });

  testWidgets('the detail reveal calls pageBuilder once per screen', (
    WidgetTester tester,
  ) async {
    final (DemoHarness h, List<DemoRoute> built) = await pump(tester);
    h.delegate.pop();
    await tester.pumpAndSettle();
    built.clear();

    h.delegate.push(const DemoDetail(2));
    await tester.pumpAndSettle();

    // One state change, so one build of each screen in the branch.
    expect(built, <DemoRoute>[const DemoList(), const DemoDetail(2)]);
  });

  testWidgets('a drag does not build the empty detail again', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);
    int placeholders = 0;
    final DemoHarness h = DemoHarness(
      paneSplit: split,
      collapseWhenDetailEmpty: false,
      detailPlaceholder: (BuildContext context) {
        placeholders++;
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(placeholders, greaterThan(0));
    placeholders = 0;

    final TestGesture drag = await tester.startGesture(
      tester.getCenter(find.byKey(AdaptiveShell.paneSplitHandleKey)),
    );
    for (int i = 0; i < 5; i++) {
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(split.fractionOf('staff'), isNotNull);
    expect(placeholders, 0);
  });
}
