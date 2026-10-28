import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// Material's `NavigationRail` and `NavigationBar` both need two destinations.
/// A column too short for two puts all of them behind the menu instead.
void main() {
  for (final (String name, Size window, double scale, int extra)
      in <(String, Size, double, int)>[
        ('a low window', const Size(900, 200), 1, 0),
        ('large text in a low window', const Size(900, 250), 2, 0),
        ('large text, many branches', const Size(900, 250), 2, 3),
      ]) {
    testWidgets('$name: no rail with fewer than two destinations', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      setWindow(tester, window);
      tester.platformDispatcher.textScaleFactorTestValue = scale;

      final DemoHarness h = DemoHarness(extraBranches: extra);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      // Taking the exceptions also clears them, so look once.
      final List<Object> errors = <Object>[];
      for (Object? e = tester.takeException(); e != null;) {
        errors.add(e);
        e = tester.takeException();
      }
      expect(errors, isEmpty);

      final Iterable<NavigationRail> rails = tester.widgetList(
        find.byType(NavigationRail),
      );
      for (final NavigationRail rail in rails) {
        expect(rail.destinations.length, greaterThanOrEqualTo(2));
      }
      if (rails.isEmpty) {
        await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNWidgets(2 + extra));
        await tester.tap(find.widgetWithText(MenuItemButton, 'Home'));
        await tester.pumpAndSettle();
        expect(h.delegate.state.activeBranch, 1);
      }
    });
  }

  /// [shown] — one branch per entry, with its `showsInChrome`.
  AdaptiveRouterDelegate<int> delegate(
    List<bool> shown, {
    ChromeVisibility<int>? showsChrome,
    ShellChromeBuilder? barBuilder,
  }) => AdaptiveRouterDelegate<int>(
    shellConfig: AdaptiveShellConfig<int>(
      showsChrome: showsChrome,
      barBuilder: barBuilder,
      branches: <BranchConfig<int>>[
        for (int i = 0; i < shown.length; i++)
          BranchConfig<int>(
            id: i,
            icon: Icons.circle,
            label: '$i',
            showsInChrome: shown[i],
            pageBuilder: (_) => const SizedBox(),
          ),
      ],
    ),
    initialState: NavState<int>(
      activeBranch: 0,
      branches: <BranchStack<int>>[
        for (int i = 0; i < shown.length; i++)
          BranchStack<int>(<NavEntry<int>>[
            NavEntry<int>(route: i, transition: AppTransition.platform),
          ]),
      ],
    ),
  );

  Future<Object?> pump(
    WidgetTester tester,
    AdaptiveRouterDelegate<int> d,
    Size window,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, window);
    await tester.pumpWidget(MaterialApp.router(routerDelegate: d));
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  test('a config needs branches', () {
    expect(() => delegate(<bool>[]), throwsAssertionError);
    expect(delegate(<bool>[true]), isNotNull);
    expect(delegate(<bool>[true, false]), isNotNull);
  });

  for (final (String name, Size window) in <(String, Size)>[
    ('compact', kCompact),
    ('wide', kWide),
  ]) {
    testWidgets('$name: a single branch without chrome is fine', (
      WidgetTester tester,
    ) async {
      final AdaptiveRouterDelegate<int> d = delegate(<bool>[
        true,
      ], showsChrome: (_) => false);
      expect(await pump(tester, d, window), isNull);
    });
  }

  testWidgets('one tab with a bar of its own is fine on a phone', (
    WidgetTester tester,
  ) async {
    final AdaptiveRouterDelegate<int> d = delegate(
      <bool>[true, false],
      barBuilder: (BuildContext context, int active, ValueChanged<int> go) =>
          const SizedBox(height: 56),
    );
    expect(await pump(tester, d, kCompact), isNull);
  });

  testWidgets('one tab in the stock bar asserts', (WidgetTester tester) async {
    final AdaptiveRouterDelegate<int> d = delegate(<bool>[true, false]);
    final Object? error = await pump(tester, d, kCompact);
    expect(error, isAssertionError);
    expect('$error', contains('showsInChrome'));
  });

  testWidgets('one tab in the stock rail goes behind the menu', (
    WidgetTester tester,
  ) async {
    final AdaptiveRouterDelegate<int> d = delegate(<bool>[true, false]);
    expect(await pump(tester, d, kWide), isNull);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsOneWidget);
  });
}
