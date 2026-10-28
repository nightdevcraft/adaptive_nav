import 'dart:math' as math;

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:adaptive_nav/src/column_transition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';
import '_harness/toolbar.dart';

/// The system's column goes with the route transition that changes it: what
/// leaves is gone by the transition's middle, what arrives comes after it,
/// and a back gesture holds the column where the finger holds the screen.
void main() {
  /// The list with a button of its own, as Starred has Filters; a detail
  /// whose pinned action tells it from the next one; a plain tab's root
  /// with one button and a screen pushed over it with another.
  Widget screens(DemoRoute route, Widget screen) => switch (route) {
    DemoList() => ToolbarScreen(
      title: 'List',
      groups: <List<PaneToolbarItem>>[
        <PaneToolbarItem>[toolbarItem(Icons.filter_list)],
      ],
    ),
    DemoDetail(:final int id) => ToolbarScreen(
      title: 'Detail $id',
      pinned: <PaneToolbarItem>[
        toolbarItem(id == 1 ? Icons.edit : Icons.share),
      ],
    ),
    DemoHome() => ToolbarScreen(
      title: 'Home',
      groups: <List<PaneToolbarItem>>[
        <PaneToolbarItem>[toolbarItem(Icons.print)],
      ],
    ),
    DemoProfile() => ToolbarScreen(
      title: 'Profile',
      pinned: <PaneToolbarItem>[toolbarItem(Icons.archive)],
    ),
    _ => screen,
  };

  Future<DemoHarness> pump(
    WidgetTester tester,
    DuoPose pose, {
    DetailChrome detailChrome = DetailChrome.covered,
    TargetPlatform? platform,
    Widget Function(DemoRoute, Widget)? wrapPage,
    VerticalBarCompression compression = VerticalBarCompression.toolbarFirst,
    int extraBranches = 0,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, pose.window, padding: pose.padding, display: pose.display);
    final DemoHarness h = DemoHarness(
      system: pose.system,
      masterMinWidth: 270,
      detailMinWidth: 270,
      detailChrome: detailChrome,
      platform:
          platform ??
          (detailChrome == DetailChrome.kept ? TargetPlatform.iOS : null),
      verticalCompression: compression,
      extraBranches: extraBranches,
      extraLabel: (int i) => 'Tab $i',
      wrapPage: wrapPage ?? screens,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    return h;
  }

  /// How much of [icon] is in view in the system's column, the rail in it
  /// or not: the opacities the column puts above it, multiplied; 0 where it
  /// is not there at all.
  double seen(WidgetTester tester, IconData icon) {
    double most = 0;
    for (final Key area in <Key>[
      AdaptiveShell.systemColumnKey,
      AdaptiveShell.bareColumnKey,
    ]) {
      for (final Element e
          in find
              .descendant(of: find.byKey(area), matching: find.byIcon(icon))
              .evaluate()) {
        double opacity = 1;
        e.visitAncestorElements((Element a) {
          if (a.widget is DrivenBox) {
            opacity *= (a.renderObject! as RenderDrivenBox).opacityNow;
          }
          return true;
        });
        most = math.max(most, opacity);
      }
    }
    return most;
  }

  /// Where each of [icons] stands in the system's column, the first of
  /// each.
  Map<IconData, Rect> where(
    WidgetTester tester,
    List<IconData> icons,
  ) => <IconData, Rect>{
    for (final IconData icon in icons)
      for (final Key area in <Key>[
        AdaptiveShell.systemColumnKey,
        AdaptiveShell.bareColumnKey,
      ])
        if (find
            .descendant(of: find.byKey(area), matching: find.byIcon(icon))
            .evaluate()
            .isNotEmpty)
          icon: tester.getRect(
            find
                .descendant(of: find.byKey(area), matching: find.byIcon(icon))
                .first,
          ),
  };

  double most(WidgetTester tester, List<IconData> icons) => icons.isEmpty
      ? 0
      : icons.map((IconData i) => seen(tester, i)).reduce(math.max);

  /// The route of the screen showing [text].
  ModalRoute<Object?> routeOf(WidgetTester tester, String text) =>
      ModalRoute.of(tester.element(find.text(text)))!;

  /// Pumps the transition [change] starts frame by frame, with [progress]
  /// its progress towards the new screen, and checks every frame: before
  /// the middle nothing of [incoming] is in view, after it nothing of
  /// [outgoing], never both; at the ends only one side. Returns how much of
  /// the outgoing and incoming side was in view, frame by frame.
  Future<List<(double t, double out, double come)>> transition(
    WidgetTester tester,
    VoidCallback change,
    double Function() progress, {
    required List<IconData> outgoing,
    required List<IconData> incoming,
  }) async {
    if (outgoing.isNotEmpty) {
      expect(most(tester, outgoing), 1, reason: 'before: what goes');
    }
    expect(most(tester, incoming), 0, reason: 'before: not what comes');
    final Map<IconData, Rect> stood = where(tester, outgoing);
    change();
    final List<(double, double, double)> frames = <(double, double, double)>[];
    for (int i = 0; i < 60; i++) {
      await tester.pump(
        i == 0 ? Duration.zero : const Duration(milliseconds: 16),
      );
      final double t = progress();
      final double out = most(tester, outgoing);
      final double come = most(tester, incoming);
      frames.add((t, out, come));
      if (t < 0.5) {
        expect(come, 0, reason: 'at $t nothing new yet');
      }
      if (t > 0.5) {
        expect(out, 0, reason: 'at $t nothing old any more');
      }
      expect(out == 0 || come == 0, isTrue, reason: 'at $t one or the other');
      if (out > 0) {
        for (final MapEntry<IconData, Rect> e in where(
          tester,
          outgoing,
        ).entries) {
          if (seen(tester, e.key) > 0) {
            expect(e.value, stood[e.key], reason: 'fading where it stood');
          }
        }
      }
      if (t >= 1) {
        break;
      }
    }
    expect(frames.first.$1, 0, reason: 'the first frame is the start');
    if (outgoing.isNotEmpty) {
      expect(frames.first.$2, 1, reason: 'the first frame shows what goes');
      expect(
        frames.where(((double, double, double) f) => f.$2 > 0 && f.$2 < 1),
        isNotEmpty,
        reason: 'faded out, not cut',
      );
    }
    if (incoming.isNotEmpty) {
      expect(
        frames.where(((double, double, double) f) => f.$3 > 0 && f.$3 < 1),
        isNotEmpty,
        reason: 'faded in, not cut',
      );
    }
    await tester.pumpAndSettle();
    if (incoming.isNotEmpty) {
      expect(most(tester, incoming), 1, reason: 'after: what came');
    }
    expect(most(tester, outgoing), 0, reason: 'after: not what went');
    return frames;
  }

  const List<IconData> tabs = <IconData>[Icons.people, Icons.home];
  const List<IconData> ada = <IconData>[Icons.close, Icons.edit];

  group('no overlap in any frame', () {
    testWidgets('covered, one pane: the tabs and the detail\'s buttons', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      await transition(
        tester,
        () => h.delegate.push(const DemoDetail(1)),
        () => routeOf(tester, 'Detail 1 body').animation!.value,
        outgoing: <IconData>[...tabs, Icons.filter_list],
        incoming: ada,
      );
      final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
      await transition(
        tester,
        () => h.delegate.pop(),
        () => 1 - detail.animation!.value,
        outgoing: ada,
        incoming: <IconData>[...tabs, Icons.filter_list],
      );
    });

    testWidgets('kept, one pane: the tabs stay, the toolbar changes', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        detailChrome: DetailChrome.kept,
      );
      final List<double> tabsSeen = <double>[];
      final List<(double, double, double)> open = await transition(
        tester,
        () => h.delegate.push(const DemoDetail(1)),
        () {
          tabsSeen.add(most(tester, tabs));
          return routeOf(tester, 'Detail 1 body').animation!.value;
        },
        outgoing: <IconData>[Icons.filter_list],
        incoming: ada,
      );
      expect(open, isNotEmpty);
      final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
      await transition(
        tester,
        () => h.delegate.pop(),
        () {
          tabsSeen.add(most(tester, tabs));
          return 1 - detail.animation!.value;
        },
        outgoing: ada,
        incoming: <IconData>[Icons.filter_list],
      );
      expect(tabsSeen.toSet(), <double>{1});
    });

    for (final DetailChrome chrome in DetailChrome.values) {
      testWidgets('two panes, ${chrome.name}: one detail, then another', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await pump(
          tester,
          duoPose(6),
          detailChrome: chrome,
        );
        await transition(
          tester,
          () => h.delegate.push(const DemoDetail(1)),
          () => routeOf(tester, 'Detail 1 body').animation!.value,
          outgoing: const <IconData>[],
          incoming: ada,
        );
        // The list keeps its header beside the detail; the tabs stay.
        expect(most(tester, tabs), 1);
        await transition(
          tester,
          () => h.delegate.resetDetailTo(const DemoDetail(2)),
          () => routeOf(tester, 'Detail 2 body').animation!.value,
          outgoing: const <IconData>[Icons.edit],
          incoming: const <IconData>[Icons.share],
        );
        expect(most(tester, tabs), 1);
        final ModalRoute<Object?> detail = routeOf(tester, 'Detail 2 body');
        await transition(
          tester,
          () => h.delegate.pop(),
          () => 1 - detail.animation!.value,
          outgoing: const <IconData>[Icons.close, Icons.share],
          incoming: const <IconData>[],
        );
      });
    }

    testWidgets('a plain tab: a screen pushed over its root and popped', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(tester, duoPose(2));
      await h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      await transition(
        tester,
        () => h.delegate.push(const DemoProfile()),
        () => routeOf(tester, 'Profile body').animation!.value,
        outgoing: const <IconData>[Icons.print],
        incoming: const <IconData>[Icons.arrow_back, Icons.archive],
      );
      // The tabs are not covered by a screen of the tab itself.
      expect(most(tester, tabs), 1);
      final ModalRoute<Object?> profile = routeOf(tester, 'Profile body');
      await transition(
        tester,
        () => h.delegate.pop(),
        () => 1 - profile.animation!.value,
        outgoing: const <IconData>[Icons.arrow_back, Icons.archive],
        incoming: const <IconData>[Icons.print],
      );
    });

    testWidgets('tabs folded by a push go with it, and unfold with the pop', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        detailChrome: DetailChrome.kept,
        compression: VerticalBarCompression.tabsFirst,
        extraBranches: 3,
        wrapPage: (DemoRoute route, Widget screen) => switch (route) {
          DemoDetail() => ToolbarScreen(
            title: 'Detail',
            groups: <List<PaneToolbarItem>>[
              <PaneToolbarItem>[
                toolbarItem(Icons.share),
                toolbarItem(Icons.print),
                toolbarItem(Icons.archive),
              ],
            ],
          ),
          _ => ToolbarScreen(title: '$route'),
        },
      );
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsNothing);
      // People stays in view and moves; the rest goes.
      const List<IconData> others = <IconData>[Icons.home, Icons.star];
      const List<IconData> toolbar = <IconData>[
        Icons.close,
        Icons.share,
        Icons.print,
      ];
      final List<double> people = <double>[];
      await transition(
        tester,
        () => h.delegate.push(const DemoDetail(1)),
        () {
          people.add(most(tester, const <IconData>[Icons.people]));
          return routeOf(tester, 'Detail body').animation!.value;
        },
        outgoing: others,
        incoming: toolbar,
      );
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsOneWidget);
      final ModalRoute<Object?> detail = routeOf(tester, 'Detail body');
      await transition(
        tester,
        () => h.delegate.pop(),
        () {
          people.add(most(tester, const <IconData>[Icons.people]));
          return 1 - detail.animation!.value;
        },
        outgoing: toolbar,
        incoming: others,
      );
      expect(find.byKey(AdaptiveShell.railCollapsedKey), findsNothing);
      expect(people.toSet(), <double>{1}, reason: 'the selected tab stays');
    });
  });

  testWidgets('AppTransition.none: at once', (WidgetTester tester) async {
    final DemoHarness h = await pump(tester, duoPose(2));
    h.delegate.push(const DemoDetail(1), transition: AppTransition.none);
    await tester.pump();
    expect(most(tester, ada), 1);
    expect(most(tester, tabs), 0);
    h.delegate.pop();
    await tester.pump();
    expect(most(tester, ada), 0);
    expect(most(tester, tabs), 1);
  });

  group('a back gesture leads the column', () {
    /// Checks the column frame by frame as [settle] runs to its end: what
    /// [rises] only rises and what [falls] only falls, by no more than a
    /// frame of the route's own transition.
    Future<void> follow(
      WidgetTester tester, {
      required List<IconData> rises,
      required List<IconData> falls,
    }) async {
      double up = most(tester, rises);
      double down = most(tester, falls);
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final double nowUp = most(tester, rises);
        final double nowDown = most(tester, falls);
        expect(nowUp, greaterThanOrEqualTo(up), reason: 'one way');
        expect(nowDown, lessThanOrEqualTo(down), reason: 'one way');
        expect(nowUp - up, lessThan(0.5), reason: 'no jump');
        expect(down - nowDown, lessThan(0.5), reason: 'no jump');
        up = nowUp;
        down = nowDown;
      }
      await tester.pumpAndSettle();
    }

    testWidgets('iOS: the swipe from the left edge', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = await pump(
        tester,
        duoPose(2),
        platform: TargetPlatform.iOS,
      );
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();
      final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');
      // The detail stands beside the column, and its edge is where the
      // swipe starts.
      final Rect area = tester.getRect(
        find
            .ancestor(
              of: find.text('Detail 1 body'),
              matching: find.byType(Navigator),
            )
            .first,
      );
      final double width = area.width;
      final Offset edge = Offset(area.left + 10, 300);
      Rect close() => tester.getRect(
        find.descendant(
          of: find.byKey(AdaptiveShell.bareColumnKey),
          matching: find.byIcon(Icons.close),
        ),
      );
      final Rect closeAt = close();

      // A third of the way: the detail's buttons on their way out, the tabs
      // not yet back.
      TestGesture swipe = await tester.startGesture(edge);
      await swipe.moveBy(const Offset(20, 0));
      await swipe.moveBy(Offset(width * 0.3, 0));
      await tester.pump();
      final double third = 1 - detail.animation!.value;
      expect(third, closeTo(0.3, 0.05));
      expect(most(tester, ada), closeTo(1 - 2 * third, 0.02));
      expect(most(tester, tabs), 0);
      expect(close(), closeAt, reason: 'fading where it stands');

      // Past the middle: the tabs coming back, the buttons gone.
      await swipe.moveBy(Offset(width * 0.3, 0));
      await tester.pump();
      final double past = 1 - detail.animation!.value;
      expect(past, greaterThan(0.5));
      expect(most(tester, ada), 0);
      expect(most(tester, tabs), closeTo(2 * past - 1, 0.02));

      // Back where it started, then let go: the detail stays, and so does
      // the column, without a jump.
      await swipe.moveBy(Offset(-width * 0.6 + 2, 0));
      await tester.pump();
      final double before = most(tester, ada);
      expect(before, greaterThan(0.9));
      await swipe.up();
      await tester.pump();
      expect(most(tester, ada), closeTo(before, 0.02), reason: 'no jump');
      await follow(tester, rises: ada, falls: tabs);
      expect(h.delegate.state.active.entries, hasLength(2));
      expect(most(tester, ada), 1);
      expect(most(tester, tabs), 0);

      // Most of the way and let go: the detail goes, the column with it.
      swipe = await tester.startGesture(edge);
      await swipe.moveBy(const Offset(20, 0));
      await swipe.moveBy(Offset(width * 0.6, 0));
      await tester.pump();
      final double tabsBefore = most(tester, tabs);
      expect(tabsBefore, greaterThan(0));
      await swipe.up();
      await tester.pump();
      expect(most(tester, tabs), closeTo(tabsBefore, 0.1), reason: 'no jump');
      await follow(tester, rises: tabs, falls: ada);
      expect(h.delegate.state.active.entries, hasLength(1));
      expect(most(tester, tabs), 1);
      expect(most(tester, ada), 0);
    });

    testWidgets(
      'Android: predictive back',
      (WidgetTester tester) async {
        final DemoHarness h = await pump(tester, duoPose(2));
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        final ModalRoute<Object?> detail = routeOf(tester, 'Detail 1 body');

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
          'x': 5 + 300 * progress,
          'y': 300.0,
          'progress': progress,
          'swipeEdge': 0,
        };

        await send('startBackGesture', event(0));
        await tester.pump();
        await send('updateBackGestureProgress', event(0.3));
        await tester.pump();
        expect(1 - detail.animation!.value, closeTo(0.3, 1e-6));
        expect(most(tester, ada), closeTo(0.4, 0.02));
        expect(most(tester, tabs), 0);
        await send('updateBackGestureProgress', event(0.7));
        await tester.pump();
        expect(most(tester, ada), 0);
        expect(most(tester, tabs), closeTo(0.4, 0.02));

        // Cancelled: back to the detail's buttons, without a jump.
        await send('updateBackGestureProgress', event(0.1));
        await tester.pump();
        final double before = most(tester, ada);
        expect(before, closeTo(0.8, 0.02));
        await send('cancelBackGesture');
        await tester.pump();
        expect(most(tester, ada), closeTo(before, 0.05), reason: 'no jump');
        await follow(tester, rises: ada, falls: tabs);
        expect(h.delegate.state.active.entries, hasLength(2));
        expect(most(tester, ada), 1);
        expect(most(tester, tabs), 0);

        // Committed: the detail goes, the column with it.
        await send('startBackGesture', event(0));
        await tester.pump();
        await send('updateBackGestureProgress', event(0.6));
        await tester.pump();
        final double tabsBefore = most(tester, tabs);
        expect(tabsBefore, closeTo(0.2, 0.02));
        await send('commitBackGesture');
        await tester.pump();
        expect(most(tester, tabs), closeTo(tabsBefore, 0.1), reason: 'no jump');
        await follow(tester, rises: tabs, falls: ada);
        expect(h.delegate.state.active.entries, hasLength(1));
        expect(most(tester, tabs), 1);
        expect(most(tester, ada), 0);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'Android: the active tab\'s gesture, with a detail open in another',
      (WidgetTester tester) async {
        // The hidden tab's detail stays out of the gesture
        // (inactive_branch_back_test); the column follows the one in view.
        final DemoHarness h = await pump(tester, duoPose(2));
        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        h.delegate.push(const DemoProfile());
        await tester.pumpAndSettle();
        const List<IconData> profile = <IconData>[
          Icons.arrow_back,
          Icons.archive,
        ];
        expect(most(tester, profile), 1);

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
          'x': 5 + 300 * progress,
          'y': 300.0,
          'progress': progress,
          'swipeEdge': 0,
        };
        await send('startBackGesture', event(0));
        await tester.pump();
        await send('updateBackGestureProgress', event(0.3));
        await tester.pump();
        expect(most(tester, profile), closeTo(0.4, 0.02));
        expect(most(tester, const <IconData>[Icons.print]), 0);
        await send('updateBackGestureProgress', event(0.8));
        await tester.pump();
        expect(most(tester, profile), 0);
        expect(most(tester, const <IconData>[Icons.print]), closeTo(0.6, 0.02));
        await send('cancelBackGesture');
        await tester.pumpAndSettle();
        expect(most(tester, profile), 1);
        expect(most(tester, const <IconData>[Icons.print]), 0);

        // Committed: Home's root and its button; People still has its
        // detail, and its column comes with it.
        await send('startBackGesture', event(0));
        await tester.pump();
        await send('updateBackGestureProgress', event(0.6));
        await tester.pump();
        await send('commitBackGesture');
        await tester.pumpAndSettle();
        expect(most(tester, profile), 0);
        expect(most(tester, const <IconData>[Icons.print]), 1);
        expect(h.delegate.state.branches[0].entries, hasLength(2));
        await h.delegate.goBranch(0);
        await tester.pumpAndSettle();
        expect(most(tester, ada), 1);
        expect(most(tester, tabs), 0);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }),
    );

    for (final bool commit in <bool>[true, false]) {
      testWidgets(
        'Android: a tab switch mid-gesture, then '
        '${commit ? 'committed' : 'cancelled'}: nothing left half-way',
        (WidgetTester tester) async {
          final DemoHarness h = await pump(tester, duoPose(2));
          h.delegate.push(const DemoDetail(1));
          await tester.pumpAndSettle();
          await h.delegate.goBranch(1);
          await tester.pumpAndSettle();
          h.delegate.push(const DemoProfile());
          await tester.pumpAndSettle();
          const List<IconData> profile = <IconData>[
            Icons.arrow_back,
            Icons.archive,
          ];
          const List<IconData> print = <IconData>[Icons.print];

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
          await send('updateBackGestureProgress', event(0.4));
          await tester.pump();
          await h.delegate.goBranch(0);
          await tester.pumpAndSettle();
          // People's detail and its column, whatever the finger does in Home.
          expect(most(tester, ada), 1);
          expect(most(tester, tabs), 0);
          await send('updateBackGestureProgress', event(0.8));
          await tester.pump();
          expect(most(tester, ada), 1);
          await send(commit ? 'commitBackGesture' : 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(most(tester, ada), 1);
          expect(most(tester, tabs), 0);
          expect(most(tester, profile), 0);
          expect(h.delegate.state.branches[0].entries, hasLength(2));

          await h.delegate.goBranch(1);
          await tester.pumpAndSettle();
          expect(
            h.delegate.state.branches[1].entries,
            hasLength(commit ? 1 : 2),
          );
          expect(most(tester, commit ? print : profile), 1);
          expect(most(tester, commit ? profile : print), 0);
          expect(most(tester, ada), 0);
        },
        variant: const TargetPlatformVariant(<TargetPlatform>{
          TargetPlatform.android,
        }),
      );
    }
  });

  testWidgets('the column listens to the transition; the screens do not', (
    WidgetTester tester,
  ) async {
    final List<String> built = <String>[];
    final DemoHarness h = await pump(
      tester,
      duoPose(2),
      platform: TargetPlatform.iOS,
      wrapPage: (DemoRoute route, Widget screen) => ToolbarScreen(
        title: '$route',
        pinned: <PaneToolbarItem>[toolbarItem(Icons.edit)],
        onBuild: () => built.add('$route'),
      ),
    );
    Future<void> frames(VoidCallback change) async {
      change();
      await tester.pump();
      await tester.pump();
      built.clear();
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(built, isEmpty, reason: 'not built frame by frame');
      await tester.pumpAndSettle();
    }

    await frames(() => h.delegate.push(const DemoDetail(1)));
    await frames(() => h.delegate.pop());

    // Nor during a swipe.
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    final TestGesture swipe = await tester.startGesture(const Offset(40, 300));
    await swipe.moveBy(const Offset(20, 0));
    await tester.pump();
    await tester.pump();
    built.clear();
    for (int i = 0; i < 10; i++) {
      await swipe.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    expect(built, isEmpty);
    await swipe.up();
    await tester.pumpAndSettle();
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
