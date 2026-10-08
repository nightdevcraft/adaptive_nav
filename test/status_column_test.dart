import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/pose.dart';
import '_harness/resize.dart';

/// `AdaptiveShellConfig.actionsInStatusColumn` on iPhone Duo's inner display
/// in landscape: the column is 72 wide around a line 48 in, from 106 down to
/// the home indicator.
void main() {
  const Key masterAction = ValueKey<String>('master action');
  const Key detailAction = ValueKey<String>('detail action');
  final double axis = kDuoInnerLandscape.width - 48; // 903

  int masterTaps = 0;

  /// Each demo screen ends up under a header of its own with one action, laid
  /// out by `StatusColumnActions`.
  Widget withActions(DemoRoute route, Widget screen) {
    final bool isMaster = route is DemoList;
    return StatusColumnActions(
      actions: <Widget>[
        IconButton(
          key: isMaster ? masterAction : detailAction,
          icon: const Icon(Icons.filter_list),
          onPressed: isMaster ? () => masterTaps++ : () {},
        ),
      ],
      builder: (BuildContext context, List<Widget> actions) => Scaffold(
        appBar: AppBar(title: const Text('Actions'), actions: actions),
        drawer: const Drawer(),
        body: StatusColumnActions.body(screen),
      ),
    );
  }

  Future<DemoHarness> pump(
    WidgetTester tester, {
    Size size = kDuoInnerLandscape,
    EdgeInsets padding = kDuoInnerLandscapePadding,
    bool option = true,
    TargetPlatform platform = TargetPlatform.iOS,
    bool withDetail = false,
  }) => pumpPose(
    tester,
    DemoHarness(
      actionsInStatusColumn: option,
      platform: platform,
      masterMinWidth: 270,
      detailMinWidth: 270,
      wrapPage: withActions,
    ),
    size,
    padding: padding,
    withDetail: withDetail,
  );

  final Finder master = find.byType(DemoListScreen);
  final Finder detail = find.byType(DemoDetailScreen);

  Rect? columnAt(WidgetTester tester, Finder finder) =>
      StatusColumnScope.of(tester.element(finder));

  bool inHeader(Key key) => find
      .descendant(of: find.byType(AppBar), matching: find.byKey(key))
      .evaluate()
      .isNotEmpty;

  void expectInColumn(WidgetTester tester, Key key) {
    expect(inHeader(key), isFalse);
    final Rect button = tester.getRect(find.byKey(key));
    expect(button.center.dx, closeTo(axis, 0.5));
    expect(button.top, greaterThanOrEqualTo(106));
    expect(
      button.bottom,
      lessThanOrEqualTo(
        kDuoInnerLandscape.height - kDuoInnerLandscapePadding.bottom,
      ),
    );
  }

  group('inner display, landscape', () {
    testWidgets('master alone: the column is the master\'s', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.byType(NavigationRail), findsOneWidget);
      final Rect column = columnAt(tester, master)!;
      // The master starts after the rail and its divider, at 81.
      expect(column.center.dx, closeTo(axis - 81, 0.5));
      expect(column.width, 72);
      expect(column.top, 106);
      expect(column.bottom, kDuoInnerLandscape.height - 34);
      expectInColumn(tester, masterAction);
      // The master spans the width, so its screen insets the column away.
      expect(MediaQuery.paddingOf(tester.element(master)).right, 84);
    });

    testWidgets('a detail takes the column; the master gets its header back', (
      WidgetTester tester,
    ) async {
      await pump(tester, withDetail: true);

      expect(columnAt(tester, master), isNull);
      expect(columnAt(tester, detail), isNotNull);
      expect(inHeader(masterAction), isTrue);
      expectInColumn(tester, detailAction);
      expect(MediaQuery.paddingOf(tester.element(detail)).right, 84);
    });

    testWidgets('the detail closed: the column is the master\'s again', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, withDetail: true);

      h.delegate.pop();
      await tester.pumpAndSettle();

      expect(columnAt(tester, master), isNotNull);
      expectInColumn(tester, masterAction);
    });

    testWidgets('a button in the column is tapped like any other', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      masterTaps = 0;

      await tester.tap(find.byKey(masterAction));
      expect(masterTaps, 1);
    });

    /// Whether a tap at the centre of [button] would reach [over] rather than
    /// the button.
    bool covers(WidgetTester tester, Finder over, Key button) {
      final Offset centre = tester.getCenter(find.byKey(button));
      final HitTestResult result = tester.hitTestOnBinding(centre);
      bool hits(Finder finder) {
        final RenderObject target = tester.renderObject(finder);
        return result.path.any((HitTestEntry entry) => entry.target == target);
      }

      return hits(over) && !hits(find.byKey(button));
    }

    // The drawer opens on the left, and the button on the right is under its
    // scrim.
    testWidgets('the screen\'s drawer covers the column\'s buttons', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      expectInColumn(tester, masterAction);

      Scaffold.of(tester.element(master)).openDrawer();
      await tester.pumpAndSettle();

      expect(
        covers(tester, find.byType(DrawerController), masterAction),
        isTrue,
      );
    });

    testWidgets('a bottom sheet covers the column\'s buttons', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      expectInColumn(tester, masterAction);

      Scaffold.of(tester.element(master)).showBottomSheet(
        (BuildContext context) => const SizedBox.expand(),
        // Material 3 keeps a sheet to 640 across, short of the column.
        constraints: const BoxConstraints(),
      );
      await tester.pumpAndSettle();

      expect(covers(tester, find.byType(BottomSheet), masterAction), isTrue);
    });

    testWidgets('the actions fade across rather than jump', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester);

      h.delegate.push(const DemoDetail(1));
      // The column passes to the detail as it slides over the glyphs' line;
      // the master's action fades out of the column, then into the header.
      final Set<bool> fadedWhereInHeader = <bool>{};
      for (int frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final double opacity = tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.byKey(masterAction),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;
        if (opacity > 0.05 && opacity < 0.95) {
          fadedWhereInHeader.add(inHeader(masterAction));
        }
      }
      expect(fadedWhereInHeader, <bool>{false, true});

      await tester.pumpAndSettle();
      expect(inHeader(masterAction), isTrue);
    });
  });

  final Map<String, (Size, EdgeInsets, TargetPlatform, bool)> unchanged =
      <String, (Size, EdgeInsets, TargetPlatform, bool)>{
        'option off': (
          kDuoInnerLandscape,
          kDuoInnerLandscapePadding,
          TargetPlatform.iOS,
          false,
        ),
        'Android': (
          kDuoInnerLandscape,
          kDuoInnerLandscapePadding,
          TargetPlatform.android,
          true,
        ),
        'outer display, landscape': (
          kDuoOuterLandscape,
          kDuoOuterLandscapePadding,
          TargetPlatform.iOS,
          true,
        ),
        'outer display, portrait': (
          kDuoOuterPortrait,
          kDuoOuterPortraitPadding,
          TargetPlatform.iOS,
          true,
        ),
        'inner display, portrait': (
          kDuoInnerPortrait,
          kDuoInnerPortraitPadding,
          TargetPlatform.iOS,
          true,
        ),
        'iPad, landscape': (
          const Size(1180, 820),
          const EdgeInsets.only(top: 24, bottom: 20),
          TargetPlatform.iOS,
          true,
        ),
        'desktop': (kWide, EdgeInsets.zero, TargetPlatform.macOS, true),
      };
  for (final MapEntry<String, (Size, EdgeInsets, TargetPlatform, bool)> pose
      in unchanged.entries) {
    testWidgets('${pose.key}: the actions stay in the headers', (
      WidgetTester tester,
    ) async {
      final (Size size, EdgeInsets padding, TargetPlatform platform, bool on) =
          pose.value;
      await pump(
        tester,
        size: size,
        padding: padding,
        platform: platform,
        option: on,
        withDetail: true,
      );

      expect(columnAt(tester, master), isNull);
      expect(columnAt(tester, detail), isNull);
      expect(inHeader(detailAction), isTrue);
      expect(inHeader(masterAction), isTrue);
    });
  }
}
