import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// [ChromePlacement] is physical, and so is every width the shell computes. A
/// right-to-left locale must not mirror the row they are laid out in.
void main() {
  const double region = kDefaultRailWidth + kDefaultRailDividerWidth;

  for (final bool withImmersive in <bool>[false, true]) {
    testWidgets('right-to-left keeps the rail on the left '
        '${withImmersive ? 'with' : 'without'} immersive', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, kWide);
      final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);
      addTearDown(immersive.dispose);
      final DemoHarness h = DemoHarness(
        immersive: withImmersive ? immersive : null,
      );
      await tester.pumpWidget(h.app(textDirection: TextDirection.rtl));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      final Rect rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0);
      expect(rail.width, kDefaultRailWidth);
      expect(
        tester.getRect(find.byType(VerticalDivider)).left,
        kDefaultRailWidth,
      );

      final Rect master = tester.getRect(find.byType(DemoListScreen));
      final Rect detail = tester.getRect(find.byType(DemoDetailScreen));
      expect(master.left, region);
      expect(detail.right, kWide.width);
      expect(master.right, lessThanOrEqualTo(detail.left));
    });
  }
}
