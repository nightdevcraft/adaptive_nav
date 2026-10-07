import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_app.dart';
import 'resize.dart';

/// Pumps [h] in [window] and records every `canHandlePop` that reaches the
/// app — what it would tell the system about back.
Future<List<bool>> pumpBackLog(
  WidgetTester tester,
  DemoHarness h,
  Size window,
) async {
  addTearDown(tester.view.reset);
  setWindow(tester, window);
  final List<bool> log = <bool>[];
  await tester.pumpWidget(
    h.app(
      onNavigationNotification: (NavigationNotification n) {
        log.add(n.canHandlePop);
        return true;
      },
    ),
  );
  await tester.pumpAndSettle();
  return log;
}
