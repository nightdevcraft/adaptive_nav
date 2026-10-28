import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_app.dart';
import 'resize.dart';

/// Pumps [h] in [window] with [padding] and, if [withDetail], opens the first
/// detail.
Future<DemoHarness> pumpPose(
  WidgetTester tester,
  DemoHarness h,
  Size window, {
  EdgeInsets padding = EdgeInsets.zero,
  bool withDetail = true,
}) async {
  addTearDown(tester.view.reset);
  setPose(tester, window, padding: padding);
  await tester.pumpWidget(h.app());
  await tester.pumpAndSettle();
  if (withDetail) {
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
  }
  return h;
}
