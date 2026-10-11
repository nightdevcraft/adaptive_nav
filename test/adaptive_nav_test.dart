import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `AdaptiveNav`: the router as one plain object that owns its notifiers.
void main() {
  Widget page(DemoRoute route) {
    final String label = switch (route) {
      DemoList() => 'list',
      DemoDetail(:final int id) => 'detail $id',
      DemoEdit(:final int id) => 'edit $id',
      DemoHome() => 'home',
      DemoProfile() => 'profile',
    };
    // Expanded, so a pane's width can be read off its screen.
    return SizedBox.expand(key: ValueKey<String>(label), child: Text(label));
  }

  double widthOf(WidgetTester tester, String label) =>
      tester.getSize(find.byKey(ValueKey<String>(label))).width;

  NavEntry<DemoRoute> root(DemoRoute route) =>
      NavEntry<DemoRoute>(route: route, transition: AppTransition.platform);

  AdaptiveNav<DemoRoute> build({
    RouteCodec<DemoRoute>? codec,
    String? initialLocation,
    bool? immersive,
    bool resizablePanes = false,
    Map<Object, double>? paneFractions,
    void Function(Object branchId, double fraction)? onPaneCommit,
  }) {
    final AdaptiveNav<DemoRoute> nav = AdaptiveNav<DemoRoute>(
      shellConfig: AdaptiveShellConfig<DemoRoute>(
        branches: <BranchConfig<DemoRoute>>[
          BranchConfig<DemoRoute>(
            id: 'staff',
            icon: Icons.people,
            label: 'People',
            masterDetail: const MasterDetailConfig(paneRatio: 0.35),
            pageBuilder: page,
          ),
          BranchConfig<DemoRoute>(
            id: 'home',
            icon: Icons.home,
            label: 'Home',
            pageBuilder: page,
          ),
        ],
      ),
      initialState: NavState<DemoRoute>(
        activeBranch: 0,
        branches: <BranchStack<DemoRoute>>[
          BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoList())]),
          BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoHome())]),
        ],
      ),
      codec: codec,
      initialLocation: initialLocation,
      immersive: immersive,
      resizablePanes: resizablePanes,
      paneFractions: paneFractions,
      onPaneCommit: onPaneCommit,
    );
    addTearDown(nav.dispose);
    return nav;
  }

  Future<void> pump(WidgetTester tester, AdaptiveNav<DemoRoute> nav) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    await tester.pumpWidget(
      MaterialApp.router(debugShowCheckedModeBanner: false, routerConfig: nav),
    );
    await tester.pumpAndSettle();
  }

  test('is not a Listenable', () {
    expect(build(), isNot(isA<Listenable>()));
  });

  testWidgets('navigates through the delegate it owns', (
    WidgetTester tester,
  ) async {
    final AdaptiveNav<DemoRoute> nav = build();
    await pump(tester, nav);
    expect(find.text('list'), findsOneWidget);

    nav.push(const DemoDetail(4));
    await tester.pumpAndSettle();
    expect(find.text('detail 4'), findsOneWidget);
    expect(nav.state.active.top.route, const DemoDetail(4));
    expect(identical(nav.state, nav.routerDelegate.state), isTrue);

    await nav.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the initial location is decoded with the codec', (
    WidgetTester tester,
  ) async {
    final AdaptiveNav<DemoRoute> nav = build(
      codec: const DemoCodec(),
      initialLocation: '/list/detail/3',
    );
    await pump(tester, nav);

    expect(nav.state.activeBranch, 0);
    expect(nav.state.active.top.route, const DemoDetail(3));
    expect(find.text('detail 3'), findsOneWidget);
  });

  testWidgets(
    'without an initial location the platform default route is parsed',
    (WidgetTester tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/list/detail/5';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final AdaptiveNav<DemoRoute> nav = build(codec: const DemoCodec());
      final String location =
          tester.binding.platformDispatcher.defaultRouteName;
      expect(nav.routeInformationProvider!.value.uri, Uri.parse(location));

      final NavState<DemoRoute> state = await nav.routeInformationParser!
          .parseRouteInformation(nav.routeInformationProvider!.value);
      expect(state.active.top.route, const DemoDetail(5));
    },
  );

  test('dispose before the provider is read does not create one', () {
    final List<Object> created = <Object>[];
    void listener(ObjectEvent event) {
      if (event is ObjectCreated &&
          event.object is PlatformRouteInformationProvider) {
        created.add(event.object);
      }
    }

    FlutterMemoryAllocations.instance.addListener(listener);
    addTearDown(
      () => FlutterMemoryAllocations.instance.removeListener(listener),
    );

    final AdaptiveNav<DemoRoute> nav = AdaptiveNav<DemoRoute>(
      shellConfig: AdaptiveShellConfig<DemoRoute>(
        branches: <BranchConfig<DemoRoute>>[
          BranchConfig<DemoRoute>(
            id: 'home',
            icon: Icons.home,
            label: 'Home',
            pageBuilder: page,
          ),
        ],
      ),
      initialState: NavState<DemoRoute>(
        activeBranch: 0,
        branches: <BranchStack<DemoRoute>>[
          BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoHome())]),
        ],
      ),
      codec: const DemoCodec(),
    );
    expect(nav.dispose, returnsNormally);
    expect(created, isEmpty);
  });

  testWidgets('without a codec there is no parser and no URL provider', (
    WidgetTester tester,
  ) async {
    final AdaptiveNav<DemoRoute> nav = build();
    expect(nav.routeInformationParser, isNull);
    expect(nav.routeInformationProvider, isNull);
    expect(nav.backButtonDispatcher, isNotNull);
  });

  testWidgets('immersive: the setter slides the rail out and back', (
    WidgetTester tester,
  ) async {
    double region() =>
        tester.getSize(find.byKey(AdaptiveShell.railRegionKey)).width;

    final AdaptiveNav<DemoRoute> nav = build(immersive: false);
    await pump(tester, nav);
    final double before = region();
    expect(before, greaterThan(0));

    nav.immersive = true;
    await tester.pumpAndSettle();
    expect(nav.immersive, isTrue);
    expect(region(), 0);

    nav.immersive = false;
    await tester.pumpAndSettle();
    expect(region(), closeTo(before, 0.5));
  });

  testWidgets('immersive off: reads false, setting it asserts', (
    WidgetTester tester,
  ) async {
    final AdaptiveNav<DemoRoute> nav = build();
    expect(nav.immersive, isFalse);
    expect(() => nav.immersive = true, throwsAssertionError);
  });

  testWidgets('resizablePanes: the boundary is draggable and committed', (
    WidgetTester tester,
  ) async {
    final List<(Object, double)> commits = <(Object, double)>[];
    final AdaptiveNav<DemoRoute> nav = build(
      resizablePanes: true,
      onPaneCommit: (Object branch, double fraction) =>
          commits.add((branch, fraction)),
    );
    await pump(tester, nav);
    nav.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    final double master = widthOf(tester, 'list');
    await tester.drag(
      find.byKey(AdaptiveShell.paneSplitHandleKey),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();

    expect(nav.paneSplit, isNotNull);
    expect(nav.paneSplit!.fractionOf('staff'), isNotNull);
    expect(commits, hasLength(1));
    expect(commits.single.$1, 'staff');
    expect(widthOf(tester, 'list'), greaterThan(master));
  });

  testWidgets('without resizablePanes there is no handle', (
    WidgetTester tester,
  ) async {
    final AdaptiveNav<DemoRoute> nav = build();
    await pump(tester, nav);
    nav.push(const DemoDetail(1));
    await tester.pumpAndSettle();

    expect(nav.paneSplit, isNull);
    expect(find.byKey(AdaptiveShell.paneSplitHandleKey), findsNothing);
  });

  test('paneFractions without resizablePanes asserts', () {
    expect(
      () => build(paneFractions: <Object, double>{'staff': 0.5}),
      throwsAssertionError,
    );
  });
}
