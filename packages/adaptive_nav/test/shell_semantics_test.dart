import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';

/// What a screen reader is given: the final semantics tree, not the widgets.
///
/// Every route's barrier blocks the semantics painted before it, up to the
/// nearest container. The detail navigator is over the master and the chrome
/// and always has a route, its transparent base page, so the block used to
/// reach the whole shell: with a detail open only the detail was read, and
/// with none nothing was.
///
/// `find.bySemanticsLabel` is no use here: it also finds the nodes the block
/// dropped. The labels come from a walk of the tree the platform gets.
void main() {
  /// The labels and tooltips of the nodes in the tree, a label of several
  /// lines as one (a bar's tab reads "People\nTab 1 of 2").
  List<String> spoken(WidgetTester tester) {
    final List<String> out = <String>[];
    bool visit(SemanticsNode node) {
      if (!node.isInvisible && !node.isMergedIntoParent) {
        final SemanticsData data = node.getSemanticsData();
        for (final String s in <String>[data.label, data.tooltip]) {
          if (s.isNotEmpty) {
            out.add(s.replaceAll('\n', ' '));
          }
        }
      }
      node.visitChildren(visit);
      return true;
    }

    visit(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    return out;
  }

  /// A node reads [text], whole or as the start of a tab's label.
  Matcher reads(String text) => anyElement(
    predicate<String>(
      (String s) => s == text || s.startsWith('$text '),
      'reads "$text"',
    ),
  );

  // What each part of the shell reads.
  const String master = 'Item 1';
  const String detail = 'Counter: 0';
  const String people = 'People';
  const String home = 'Home';
  const String homeScreen = 'Home: 0';
  const String placeholder = 'Nobody selected';

  void expectReads(
    WidgetTester tester, {
    List<String> shown = const <String>[],
    List<String> hidden = const <String>[],
  }) {
    final List<String> tree = spoken(tester);
    for (final String s in shown) {
      expect(tree, reads(s), reason: '"$s" in $tree');
    }
    for (final String s in hidden) {
      expect(tree, isNot(reads(s)), reason: '"$s" in $tree');
    }
  }

  Future<DemoHarness> pump(
    WidgetTester tester,
    Size window, {
    DemoHarness? harness,
    bool withDetail = false,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, window);
    final DemoHarness h = harness ?? DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    if (withDetail) {
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
    }
    return h;
  }

  /// A tablet in portrait: a rail and a single pane.
  const Size onePaneWithRail = Size(700, 900);

  group('compact', () {
    testWidgets('no detail: the master and every tab', (
      WidgetTester tester,
    ) async {
      await pump(tester, kCompact);
      expectReads(tester, shown: <String>[master, people, home]);
    });

    testWidgets('a detail: the detail alone, over the master and the bar', (
      WidgetTester tester,
    ) async {
      await pump(tester, kCompact, withDetail: true);
      expectReads(
        tester,
        shown: <String>[detail],
        hidden: <String>[master, people, home],
      );
    });

    testWidgets('a detail that keeps the bar: the detail and the tabs', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kCompact,
        harness: DemoHarness(
          detailChrome: DetailChrome.kept,
          platform: TargetPlatform.iOS,
        ),
        withDetail: true,
      );
      expectReads(
        tester,
        shown: <String>[detail, people, home],
        hidden: <String>[master],
      );
    });
  });

  group('two panes', () {
    testWidgets('no detail, collapsed: the rail and the master', (
      WidgetTester tester,
    ) async {
      await pump(tester, kWide);
      expectReads(tester, shown: <String>[people, home, master]);
    });

    testWidgets('no detail, a placeholder: the rail, master and placeholder', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        kWide,
        harness: DemoHarness(
          collapseWhenDetailEmpty: false,
          detailPlaceholder: (BuildContext _) =>
              const Center(child: Text(placeholder)),
        ),
      );
      expect(find.text(placeholder), findsOneWidget);
      expectReads(tester, shown: <String>[people, home, master, placeholder]);
    });

    testWidgets('a detail: the rail, the master and the detail', (
      WidgetTester tester,
    ) async {
      await pump(tester, kWide, withDetail: true);
      expectReads(tester, shown: <String>[people, home, master, detail]);
    });
  });

  group('one pane beside a rail', () {
    testWidgets('no detail: the rail and the master', (
      WidgetTester tester,
    ) async {
      await pump(tester, onePaneWithRail);
      expectReads(tester, shown: <String>[people, home, master]);
    });

    testWidgets('a detail: the detail alone, as on compact', (
      WidgetTester tester,
    ) async {
      await pump(tester, onePaneWithRail, withDetail: true);
      expectReads(
        tester,
        shown: <String>[detail],
        hidden: <String>[master, people, home],
      );
    });

    testWidgets('a detail that keeps the rail: the detail and the rail', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        onePaneWithRail,
        harness: DemoHarness(
          detailChrome: DetailChrome.kept,
          platform: TargetPlatform.iOS,
        ),
        withDetail: true,
      );
      expectReads(
        tester,
        shown: <String>[detail, people, home],
        hidden: <String>[master],
      );
    });

    // In a wide window: the branch has one pane wherever it is.
    testWidgets('a branch without master-detail: its top screen and the rail', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, kWide);
      await h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      expectReads(tester, shown: <String>[people, home, homeScreen]);
      // Pushed in the branch's own navigator: the screen under it is not
      // read, the rail is.
      h.delegate.push(const DemoHome());
      await tester.pumpAndSettle();
      expect(h.delegate.state.branches[1].entries, hasLength(2));
      expectReads(tester, shown: <String>[people, home, homeScreen]);
      expect(
        spoken(tester).where((String s) => s == homeScreen),
        hasLength(1),
        reason: 'the Home under it is not read',
      );
    });
  });

  for (final (String name, Size window) in <(String, Size)>[
    ('compact', kCompact),
    ('two panes', kWide),
  ]) {
    testWidgets('$name: a branch switch reads the active branch only', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, window, withDetail: true);
      await h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      expectReads(
        tester,
        shown: <String>[homeScreen, people, home],
        hidden: <String>[master, detail],
      );

      await h.delegate.goBranch(0);
      await tester.pumpAndSettle();
      expectReads(
        tester,
        shown: <String>[detail],
        hidden: <String>[homeScreen],
      );
    });
  }

  testWidgets('a dialog on the root navigator: the dialog alone', (
    WidgetTester tester,
  ) async {
    await pump(tester, kWide, withDetail: true);
    showDialog<void>(
      context: tester.element(find.byType(DemoListScreen)),
      builder: (BuildContext _) =>
          const AlertDialog(content: Text('Root dialog')),
    );
    await tester.pumpAndSettle();
    expectReads(
      tester,
      shown: <String>['Root dialog'],
      hidden: <String>[master, detail, people, home],
    );
  });

  // A modal of the detail pane belongs to the pane: it covers the detail,
  // and the master and the rail beside it stay readable, as they stay
  // tappable.
  for (final (String name, Future<void> Function(BuildContext) open)
      in <(String, Future<void> Function(BuildContext))>[
        (
          'dialog',
          (BuildContext context) => showDialog<void>(
            context: context,
            useRootNavigator: false,
            builder: (BuildContext _) =>
                const AlertDialog(content: Text('Pane modal')),
          ),
        ),
        (
          'bottom sheet',
          (BuildContext context) => showModalBottomSheet<void>(
            context: context,
            builder: (BuildContext _) => const Text('Pane modal'),
          ),
        ),
      ]) {
    testWidgets('a $name in the detail pane: it covers the detail only', (
      WidgetTester tester,
    ) async {
      await pump(tester, kWide, withDetail: true);
      open(tester.element(find.byType(DemoDetailScreen)));
      await tester.pumpAndSettle();
      expectReads(
        tester,
        shown: <String>['Pane modal', master, people, home],
        hidden: <String>[detail],
      );
    });
  }

  group('mid-transition', () {
    for (final (String name, Size window) in <(String, Size)>[
      ('compact', kCompact),
      ('two panes', kWide),
    ]) {
      testWidgets('$name: a closing detail gives the master back at once', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(tester, window, withDetail: true);
        h.delegate.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(DemoDetailScreen), findsOneWidget);
        expectReads(tester, shown: <String>[master, people, home]);
        await tester.pumpAndSettle();
        expectReads(
          tester,
          shown: <String>[master, people, home],
          hidden: <String>[detail],
        );
      });
    }

    for (final (String name, Size window, List<String> mid)
        in <(String, Size, List<String>)>[
          // The detail is still the screen: back has not happened yet.
          ('compact', kCompact, <String>[detail]),
          ('two panes', kWide, <String>[detail, master, people, home]),
        ]) {
      testWidgets('$name: predictive back mid-gesture, then committed', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(
          tester,
          window,
          harness: DemoHarness(platform: TargetPlatform.android),
          withDetail: true,
        );
        Future<void> send(String method, [Map<String, Object?>? args]) =>
            tester.binding.defaultBinaryMessenger.handlePlatformMessage(
              'flutter/backgesture',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(method, args),
              ),
              (ByteData? _) {},
            );
        Map<String, Object?> event(double progress) => <String, Object?>{
          'touchOffset': <double>[5, 300],
          'progress': progress,
          'swipeEdge': 0,
        };

        await send('startBackGesture', event(0));
        await tester.pump();
        await send('updateBackGestureProgress', event(0.5));
        await tester.pump();
        final NavigatorState detailNav = Navigator.of(
          tester.element(find.byType(DemoDetailScreen)),
        );
        expect(detailNav.userGestureInProgress, isTrue);
        expect(spoken(tester), isNotEmpty);
        expectReads(tester, shown: mid);

        await send('commitBackGesture');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectReads(tester, shown: <String>[master, people, home]);
        await tester.pumpAndSettle();
        expect(h.delegate.state.active.entries, hasLength(1));
        expectReads(
          tester,
          shown: <String>[master, people, home],
          hidden: <String>[detail],
        );
      });
    }
  });

  group('iPhone Duo, the system column', () {
    // Ten tabs: more than the column has places for, so some fold into More,
    // and their places stay in the tree, left out of the semantics.
    Future<DemoHarness> pumpDuo(WidgetTester tester, DuoPose pose) async {
      addTearDown(tester.view.reset);
      setPose(
        tester,
        pose.window,
        padding: pose.padding,
        display: pose.display,
      );
      final DemoHarness h = DemoHarness(
        system: pose.system,
        extraBranches: 8,
        extraLabel: (int i) => 'Tab $i',
        masterMinWidth: 270,
        detailMinWidth: 270,
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      return h;
    }

    /// The tabs with a place in the column are read; the folded ones are not.
    void expectPlacedTabs(WidgetTester tester) {
      final List<String> labels =
          <String>['People', 'Home'] +
          <String>[for (int i = 0; i < 8; i++) 'Tab $i'];
      final List<int> placed = <int>[
        for (int b = 0; b < 10; b++)
          if (find.byKey(AdaptiveShell.columnTabKey(b)).evaluate().isNotEmpty)
            b,
      ];
      expect(placed.length, inInclusiveRange(2, 9));
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsNothing);
      for (int b = 0; b < 10; b++) {
        final Matcher m = reads(labels[b]);
        expect(
          spoken(tester),
          placed.contains(b) ? m : isNot(m),
          reason: 'tab $b, placed: $placed',
        );
      }
    }

    testWidgets('outer portrait, one pane: tabs, then the detail alone', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pumpDuo(tester, duoPose(1));
      expectReads(tester, shown: <String>[master]);
      expectPlacedTabs(tester);

      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expectReads(
        tester,
        shown: <String>[detail],
        hidden: <String>[master, people, home],
      );
    });

    testWidgets('inner landscape, two panes: tabs, master and detail', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pumpDuo(tester, duoPose(5));
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      expectReads(tester, shown: <String>[master, detail]);
      expectPlacedTabs(tester);
    });
  });
}
