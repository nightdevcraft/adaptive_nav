import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Pane widths follow paneRatio, respecting the minimum widths.
void main() {
  test('masterWidthFor honors ratio and clamps to min widths', () {
    const MasterDetailConfig md = MasterDetailConfig(
      paneRatio: 0.35,
      masterMinWidth: 320,
      detailMinWidth: 360,
    );

    // Within both panes' minimums the ratio applies as is.
    expect(md.masterWidthFor(1400, gap: 1), closeTo(490, 0.5)); // 1400*0.35

    // The ratio would fall below master-min, so it is pulled up to 320.
    expect(md.masterWidthFor(800, gap: 1), 320); // 800*0.35=280 < 320

    // The ratio would eat into detail-min, so it is capped from above.
    const MasterDetailConfig greedy = MasterDetailConfig(
      paneRatio: 0.9,
      masterMinWidth: 320,
      detailMinWidth: 360,
    );
    expect(greedy.masterWidthFor(1000, gap: 1), 639); // 1000-360-1
  });

  testWidgets('wide panes render in ~paneRatio proportion', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(1400, 900));

    final DemoHarness h = DemoHarness(); // staff paneRatio = 0.35
    h.delegate.push(const DemoDetail(1));
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    final double masterW = tester.getSize(find.byType(DemoListScreen)).width;
    final double detailW = tester.getSize(find.byType(DemoDetailScreen)).width;

    final double ratio = masterW / (masterW + detailW);
    expect(ratio, closeTo(0.35, 0.04));
  });
}
