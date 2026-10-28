import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// The split itself: master is the branch root, detail is the top of the
/// stack. Collapsing an empty detail is `master_detail_collapse_test.dart`.
void main() {
  testWidgets('master shows root, detail shows top', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    expect(find.text('List'), findsOneWidget);
    expect(find.text('Detail 2'), findsNothing);

    h.delegate.push(const DemoDetail(2));
    await tester.pumpAndSettle();
    expect(find.text('Detail 2'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
  });
}
