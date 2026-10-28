import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/entry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/duo_column.dart';
import '_harness/resize.dart';

/// The pages and routes the package builds are subclasses of the framework's
/// — `MaterialPage` and `MaterialPageRoute` for `platform`, `modal` and
/// `adaptive`, `PageRouteBuilder` for `fade` and `none` — with only
/// `impliesAppBarDismissal` added, so a check of their type, the theme's
/// `pageTransitionsTheme`, `fullscreenDialog` and `Hero` behave as with the
/// framework's own.
void main() {
  /// The route every screen is in, by route, as the screen sees it.
  Future<Map<DemoRoute, ModalRoute<Object?>?>> routesOf(
    WidgetTester tester, {
    required Size window,
    EdgeInsets padding = EdgeInsets.zero,
    Size? display,
    SystemGeometry? system,
    required AppTransition transition,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, window, padding: padding, display: display);
    final Map<DemoRoute, ModalRoute<Object?>?> seen =
        <DemoRoute, ModalRoute<Object?>?>{};
    final DemoHarness h = DemoHarness(
      system: system,
      wrapPage: (DemoRoute route, Widget screen) => Builder(
        builder: (BuildContext context) {
          seen[route] = ModalRoute.of(context);
          return screen;
        },
      ),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1), transition: transition);
    await tester.pumpAndSettle();
    h.delegate.push(const DemoEdit(1), transition: transition);
    await tester.pumpAndSettle();
    return seen;
  }

  final DuoPose pose1 = kDuoColumnPoses.first;
  final Map<
    String,
    Future<Map<DemoRoute, ModalRoute<Object?>?>> Function(
      WidgetTester,
      AppTransition,
    )
  >
  layouts =
      <
        String,
        Future<Map<DemoRoute, ModalRoute<Object?>?>> Function(
          WidgetTester,
          AppTransition,
        )
      >{
        'phone': (WidgetTester t, AppTransition tr) =>
            routesOf(t, window: const Size(390, 844), transition: tr),
        'two panes': (WidgetTester t, AppTransition tr) =>
            routesOf(t, window: const Size(1200, 800), transition: tr),
        'iPhone Duo, pose 1': (WidgetTester t, AppTransition tr) => routesOf(
          t,
          window: pose1.window,
          padding: pose1.padding,
          display: pose1.display,
          system: pose1.system,
          transition: tr,
        ),
      };

  for (final MapEntry<
        String,
        Future<Map<DemoRoute, ModalRoute<Object?>?>> Function(
          WidgetTester,
          AppTransition,
        )
      >
      layout
      in layouts.entries) {
    group(layout.key, () {
      testWidgets('platform: master and detail are MaterialPageRoutes', (
        WidgetTester tester,
      ) async {
        final Map<DemoRoute, ModalRoute<Object?>?> seen = await layout.value(
          tester,
          AppTransition.platform,
        );
        for (final DemoRoute r in <DemoRoute>[
          const DemoList(),
          const DemoDetail(1),
          const DemoEdit(1),
        ]) {
          expect(seen[r], isA<MaterialPageRoute<Object?>>(), reason: '$r');
          expect(seen[r]!.settings, isA<MaterialPage<Object?>>());
          expect((seen[r]! as PageRoute<Object?>).fullscreenDialog, isFalse);
        }
      });

      testWidgets('modal: a MaterialPageRoute and a full-screen dialog', (
        WidgetTester tester,
      ) async {
        final Map<DemoRoute, ModalRoute<Object?>?> seen = await layout.value(
          tester,
          AppTransition.modal,
        );
        for (final DemoRoute r in <DemoRoute>[
          const DemoDetail(1),
          const DemoEdit(1),
        ]) {
          expect(seen[r], isA<MaterialPageRoute<Object?>>(), reason: '$r');
          expect((seen[r]! as PageRoute<Object?>).fullscreenDialog, isTrue);
        }
      });

      testWidgets('adaptive: a MaterialPageRoute', (WidgetTester tester) async {
        final Map<DemoRoute, ModalRoute<Object?>?> seen = await layout.value(
          tester,
          AppTransition.adaptive,
        );
        expect(seen[const DemoDetail(1)], isA<MaterialPageRoute<Object?>>());
        expect(seen[const DemoEdit(1)], isA<MaterialPageRoute<Object?>>());
      });

      for (final AppTransition t in <AppTransition>[
        AppTransition.fade,
        AppTransition.none,
      ]) {
        testWidgets('${t.name}: a PageRouteBuilder', (
          WidgetTester tester,
        ) async {
          final Map<DemoRoute, ModalRoute<Object?>?> seen = await layout.value(
            tester,
            t,
          );
          expect(seen[const DemoDetail(1)], isA<PageRouteBuilder<Object?>>());
          expect(seen[const DemoEdit(1)], isA<PageRouteBuilder<Object?>>());
          expect(
            seen[const DemoEdit(1)],
            isNot(isA<MaterialPageRoute<Object?>>()),
          );
        });
      }
    });
  }

  // The routes alone, in a navigator of their own: what the theme, a
  // full-screen dialog and a hero see of them.
  BranchConfig<String> config(Widget Function(String) build) =>
      BranchConfig<String>(
        id: 'b',
        icon: Icons.home,
        label: 'B',
        pageBuilder: build,
      );

  Page<Object?> page(
    BranchConfig<String> c,
    String route,
    AppTransition transition,
  ) => buildEntryPage<String>(
    c,
    NavEntry<String>(route: route, transition: transition),
    onGuardedPop: (_) {},
  );

  testWidgets("the theme's pageTransitionsTheme builds the transition", (
    WidgetTester tester,
  ) async {
    final BranchConfig<String> c = config((String r) => Text(r));
    for (final AppTransition t in <AppTransition>[
      AppTransition.platform,
      AppTransition.modal,
      AppTransition.adaptive,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: _MarkedTransitions(),
                TargetPlatform.iOS: _MarkedTransitions(),
              },
            ),
          ),
          // No `home`: the only navigator is this one.
          builder: (_, _) => Navigator(
            key: UniqueKey(),
            pages: <Page<Object?>>[page(c, 'a', t), page(c, 'b', t)],
            onDidRemovePage: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('b'),
          matching: find.byKey(_MarkedTransitions.marker),
        ),
        findsOneWidget,
        reason: t.name,
      );
    }
  });

  testWidgets('a hero flies between two of them', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    const Key shuttle = ValueKey<String>('shuttle');
    List<Page<Object?>> pages = <Page<Object?>>[];
    late StateSetter setPages;
    final BranchConfig<String> c = config(
      (String r) => Align(
        alignment: r == 'a' ? Alignment.topLeft : Alignment.bottomRight,
        child: Hero(
          tag: 'h',
          flightShuttleBuilder: (_, _, _, _, _) =>
              const SizedBox.expand(key: shuttle),
          child: SizedBox.square(dimension: r == 'a' ? 40 : 120),
        ),
      ),
    );
    pages = <Page<Object?>>[page(c, 'a', AppTransition.platform)];
    await tester.pumpWidget(
      MaterialApp(
        // No `home`: the only navigator is this one, with a hero controller,
        // as the app's root navigator has.
        builder: (_, _) => HeroControllerScope(
          controller: MaterialApp.createMaterialHeroController(),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter set) {
              setPages = set;
              return Navigator(key: nav, pages: pages, onDidRemovePage: (_) {});
            },
          ),
        ),
      ),
    );
    setPages(() {
      pages = <Page<Object?>>[...pages, page(c, 'b', AppTransition.platform)];
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // In flight, between the two heroes' sizes.
    final Size mid = tester.getSize(find.byKey(shuttle));
    expect(mid.width, greaterThan(40));
    expect(mid.width, lessThan(120));
    await tester.pumpAndSettle();
    expect(find.byKey(shuttle), findsNothing);
  });
}

class _MarkedTransitions extends PageTransitionsBuilder {
  const _MarkedTransitions();

  static const Key marker = ValueKey<String>('theme transition');

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => KeyedSubtree(key: marker, child: child);
}
