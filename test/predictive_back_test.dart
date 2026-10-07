import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/back_log.dart';
import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// What the app tells the system about back: the last `NavigationNotification`
/// to reach `WidgetsApp`, which with predictive back decides whether Android
/// hands back to Flutter at all.
void main() {
  for (final (String name, Size window) in <(String, Size)>[
    ('compact', kCompact),
    ('wide', kWide),
  ]) {
    group(name, () {
      testWidgets('plain branch: root no, pushed yes, popped no', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        final List<bool> log = await pumpBackLog(tester, h, window);

        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);

        // The empty detail used to report last, and back closed the app.
        h.delegate.push(const DemoHome());
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);
      });

      testWidgets('master-detail branch: detail yes, popped no', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        final List<bool> log = await pumpBackLog(tester, h, window);
        expect(log.last, isFalse);

        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        h.delegate.push(const DemoEdit(1));
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);
      });

      testWidgets('tab switch reports the new branch', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        final List<bool> log = await pumpBackLog(tester, h, window);

        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);

        h.delegate.push(const DemoHome());
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        await h.delegate.goBranch(0);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);

        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(log.last, isTrue);
      });

      testWidgets('a stack in an inactive branch does not count', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        final List<bool> log = await pumpBackLog(tester, h, window);

        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        h.delegate.push(const DemoHome());
        await tester.pumpAndSettle();
        expect(log.last, isTrue);

        await h.delegate.popRoute();
        await tester.pumpAndSettle();
        expect(h.delegate.state.branches[0].hasDetail, isTrue);
        expect(log.last, isFalse);

        await h.delegate.goBranch(0);
        await tester.pumpAndSettle();
        expect(log.last, isTrue);
      });

      testWidgets('a root that blocks pop keeps back in the app', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        await h.delegate.setNewRoutePath(
          h.baseState
              .withBranch(
                1,
                BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[
                  NavEntry<DemoRoute>(
                    route: const DemoHome(),
                    transition: AppTransition.platform,
                    // Any guard blocks pop; this one lets the tab switch go.
                    onExit: () async => true,
                  ),
                ]),
              )
              .copyWith(activeBranch: 1),
        );
        final List<bool> log = await pumpBackLog(tester, h, window);
        expect(h.delegate.state.active.hasDetail, isFalse);
        expect(log.last, isTrue);

        await h.delegate.goBranch(0);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);
      });

      testWidgets('a dialog on the root navigator keeps back in the app', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = DemoHarness();
        final List<bool> log = await pumpBackLog(tester, h, window);
        await h.delegate.goBranch(1);
        await tester.pumpAndSettle();
        expect(log.last, isFalse);

        showDialog<void>(
          context: tester.element(find.text('Home: 0')),
          builder: (BuildContext context) =>
              const AlertDialog(content: Text('dialog')),
        );
        await tester.pumpAndSettle();
        expect(find.text('dialog'), findsOneWidget);
        expect(log.last, isTrue);

        Navigator.of(tester.element(find.text('dialog'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('dialog'), findsNothing);
        expect(log.last, isFalse);
      });
    });
  }

  group('system back serves the root navigator first', () {
    void openDialog(WidgetTester tester, Finder on) {
      showDialog<void>(
        context: tester.element(on),
        builder: (BuildContext context) =>
            const AlertDialog(content: Text('dialog')),
      );
    }

    testWidgets('a dialog over a branch root closes, the app stays', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = DemoHarness();
      final List<bool> log = await pumpBackLog(tester, h, kCompact);
      await h.delegate.goBranch(1);
      await tester.pumpAndSettle();

      openDialog(tester, find.text('Home: 0'));
      await tester.pumpAndSettle();
      expect(log.last, isTrue);

      expect(await h.delegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsNothing);
      expect(find.text('Home: 0'), findsOneWidget);
      expect(log.last, isFalse);
    });

    testWidgets('a dialog over a stack closes before the screen under it', (
      WidgetTester tester,
    ) async {
      final DemoHarness h = DemoHarness();
      final List<bool> log = await pumpBackLog(tester, h, kCompact);
      h.delegate.push(const DemoDetail(1));
      await tester.pumpAndSettle();

      openDialog(tester, find.text('Counter: 0'));
      await tester.pumpAndSettle();

      expect(await h.delegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsNothing);
      expect(find.text('Detail 1'), findsOneWidget);
      expect(h.delegate.state.active.hasDetail, isTrue);
      expect(log.last, isTrue);

      expect(await h.delegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Detail 1'), findsNothing);
      expect(log.last, isFalse);
    });

    testWidgets('the shell drawer closes, the screen and the app stay', (
      WidgetTester tester,
    ) async {
      final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
      final DemoHarness h = DemoHarness(
        scaffoldKey: scaffoldKey,
        drawerBuilder: (BuildContext _, bool rail) =>
            rail ? null : const Drawer(child: Text('Menu')),
      );
      final List<bool> log = await pumpBackLog(tester, h, kCompact);
      await h.delegate.goBranch(1);
      await tester.pumpAndSettle();
      expect(log.last, isFalse);

      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('Menu'), findsOneWidget);

      expect(await h.delegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Menu'), findsNothing);
      expect(find.text('Home: 0'), findsOneWidget);
      expect(log.last, isFalse);
    });
  });

  // The drawer sends no `NavigationNotification`; every shell `Scaffold` has one.
  group('the shell drawer', () {
    for (final (String name, Size window, double paneMin, Type chrome)
        in <(String, Size, double, Type)>[
          ('compact', kCompact, 360, NavigationBar),
          ('compact, two panes over the bar', kCompact, 200, NavigationBar),
          ('rail', kWide, 360, NavigationRail),
        ]) {
      final bool twoPanes = window == kWide || paneMin < 360;
      group(name, () {
        late GlobalKey<ScaffoldState> scaffoldKey;
        late DemoHarness h;

        Future<List<bool>> open(WidgetTester tester) async {
          scaffoldKey = GlobalKey<ScaffoldState>();
          h = DemoHarness(
            scaffoldKey: scaffoldKey,
            masterMinWidth: paneMin,
            detailMinWidth: paneMin,
            collapseWhenDetailEmpty: false,
            detailPlaceholder: (BuildContext _) => const Text('Pick one'),
            drawerBuilder: (BuildContext _, bool rail) =>
                const Drawer(child: Text('Menu')),
          );
          final List<bool> log = await pumpBackLog(tester, h, window);
          expect(find.byType(chrome), findsOneWidget);
          expect(
            find.text('Pick one'),
            twoPanes ? findsOneWidget : findsNothing,
          );
          expect(log.last, isFalse);
          scaffoldKey.currentState!.openDrawer();
          await tester.pumpAndSettle();
          expect(find.text('Menu'), findsOneWidget);
          expect(log.last, isTrue);
          return log;
        }

        testWidgets('open keeps back in the app', (WidgetTester tester) async {
          await open(tester);
        });

        testWidgets('closed by system back hands back to the system', (
          WidgetTester tester,
        ) async {
          final List<bool> log = await open(tester);
          expect(await h.delegate.popRoute(), isTrue);
          await tester.pumpAndSettle();
          expect(find.text('Menu'), findsNothing);
          expect(find.text('List: 0'), findsOneWidget);
          expect(log.last, isFalse);
        });

        testWidgets('closed by closeDrawer hands back to the system', (
          WidgetTester tester,
        ) async {
          final List<bool> log = await open(tester);
          scaffoldKey.currentState!.closeDrawer();
          await tester.pumpAndSettle();
          expect(find.text('Menu'), findsNothing);
          expect(find.text('List: 0'), findsOneWidget);
          expect(log.last, isFalse);
        });
      });
    }
  });

  testWidgets('the system channel hears the shell, not the empty detail', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(tester.view.reset);
    setWindow(tester, kCompact);
    final List<Object?> calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          calls.add(call.arguments);
        }
        return null;
      },
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final DemoHarness h = DemoHarness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);

    h.delegate.push(const DemoHome());
    await tester.pumpAndSettle();
    expect(calls.last, isTrue);

    await h.delegate.popRoute();
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
