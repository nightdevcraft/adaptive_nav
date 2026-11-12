import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// iPhone Duo with an app's `railBuilder` that returns `null`: there is no
/// rail, so the system's column has no tabs, whatever the placement says.
/// The column follows the layout that was built. The detail beside it hands
/// its toolbar to the column, and the column shows it; it used to count the
/// rail as being there, kept the toolbar out of it, and Edit was nowhere.
void main() {
  for (final DuoPose pose in kDuoColumnPoses) {
    testWidgets('posture ${pose.number}: the detail toolbar is in the column', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(
        tester,
        pose.window,
        padding: pose.padding,
        display: pose.display,
      );
      final DemoHarness h = DemoHarness(
        system: pose.system,
        platform: TargetPlatform.iOS,
        masterMinWidth: 270,
        detailMinWidth: 270,
        wrapPage: toolbarScreens(),
        railBuilder: (BuildContext _, int _, ValueChanged<int> _) => null,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byKey(AdaptiveShell.columnTabsKey), findsNothing);

      final Element screen = tester.element(find.text('Detail 1').first);
      final ShellLayoutScope scope = ShellLayoutScope.of(screen);
      // The panes as laid out without a rail; the column takes the toolbar
      // of the detail that stands beside it.
      expect(PaneBarScope.of(screen).verticalEdge, pose.system.verticalBar);
      expect(
        find.descendant(
          of: find.byKey(AdaptiveShell.bareColumnKey),
          matching: find.byKey(AdaptiveShell.paneToolbarKey),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(AdaptiveShell.paneToolbarKey),
          matching: find.byIcon(Icons.edit),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(scope.detailInOwnPane, scope.pane == ShellPane.detail);
    });
  }
}
