import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `redirect` behind a real `Router`, with locations delivered as the platform
/// does: the default route name at start, then `flutter/navigation`.
///
/// While [_Lock.locked] is up, the redirect cuts `DemoDetail(2)` and anything
/// above it out of every stack; a branch that showed it gives way to home.
void main() {
  const DemoRoute lockedRoute = DemoDetail(2);

  // A tap that lands on something else would otherwise pass in silence.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  NavEntry<DemoRoute> entry(DemoRoute route) =>
      NavEntry<DemoRoute>(route: route, transition: AppTransition.platform);

  NavState<DemoRoute> baseState() => NavState<DemoRoute>(
    activeBranch: 0,
    branches: <BranchStack<DemoRoute>>[
      BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[entry(const DemoList())]),
      BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[entry(const DemoHome())]),
    ],
  );

  Widget page(DemoRoute route) => switch (route) {
    DemoList() => const DemoListScreen(),
    DemoDetail(:final int id) => DemoDetailScreen(id: id),
    DemoEdit(:final int id) => DemoEditScreen(id: id),
    DemoHome() => const DemoHomeScreen(),
    DemoProfile() => const DemoProfileScreen(),
  };

  AdaptiveNav<DemoRoute> build(
    _Lock lock, {
    RouteCodec<DemoRoute>? codec = const DemoCodec(),
    String? initialLocation,
    NavState<DemoRoute>? initialState,
  }) {
    NavState<DemoRoute> redirect(NavState<DemoRoute> next) {
      lock.seen.add(next);
      if (!lock.locked) {
        return next;
      }
      NavState<DemoRoute> out = next;
      for (int b = 0; b < next.branches.length; b++) {
        final List<NavEntry<DemoRoute>> entries = next.branches[b].entries;
        final int at = entries.indexWhere(
          (NavEntry<DemoRoute> e) => e.route == lockedRoute,
        );
        if (at <= 0) {
          continue;
        }
        out = out.withBranch(b, BranchStack<DemoRoute>(entries.sublist(0, at)));
        if (b == next.activeBranch) {
          out = out.copyWith(activeBranch: 1);
        }
      }
      return out;
    }

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
        redirect: redirect,
      ),
      initialState: initialState ?? baseState(),
      codec: codec,
      initialLocation: initialLocation,
    );
    addTearDown(nav.dispose);
    return nav;
  }

  Future<void> pump(
    WidgetTester tester,
    AdaptiveNav<DemoRoute> nav, {
    bool settle = true,
  }) async {
    addTearDown(tester.view.reset);
    setWindow(tester, kWide);
    await tester.pumpWidget(
      DemoNav(
        delegate: nav.routerDelegate,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: nav,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  Future<void> openLink(WidgetTester tester, String location) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', <String, dynamic>{
          'location': location,
          'state': null,
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  void setDefaultRoute(WidgetTester tester, String location) {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
  }

  void expectHome(WidgetTester tester, AdaptiveNav<DemoRoute> nav) {
    expect(nav.state.activeBranch, 1);
    expect(find.byType(DemoHomeScreen), findsOneWidget);
    expect(find.byType(DemoDetailScreen), findsNothing);
    expect(find.text('Detail 2'), findsNothing);
  }

  testWidgets('cold start on a locked screen: redirected to home, asked once', (
    WidgetTester tester,
  ) async {
    setDefaultRoute(tester, '/list/detail/2');
    final _Lock lock = _Lock(locked: true);
    final AdaptiveNav<DemoRoute> nav = build(lock);
    await pump(tester, nav);

    expectHome(tester, nav);
    expect(lock.seen, hasLength(1));
    expect(lock.seen.single.active.top.route, lockedRoute);
  });

  testWidgets(
    'cold start on a locked initialLocation: redirected to home, asked once',
    (WidgetTester tester) async {
      final _Lock lock = _Lock(locked: true);
      final AdaptiveNav<DemoRoute> nav = build(
        lock,
        initialLocation: '/list/detail/2',
      );
      await pump(tester, nav);

      expectHome(tester, nav);
      expect(nav.state.branches[0].entries, hasLength(1));
      expect(lock.seen, hasLength(1));
      expect(lock.seen.single.active.top.route, lockedRoute);
    },
  );

  testWidgets('a warm link to a locked screen: home, other stacks kept', (
    WidgetTester tester,
  ) async {
    final _Lock lock = _Lock(locked: true);
    final AdaptiveNav<DemoRoute> nav = build(lock);
    await pump(tester, nav);

    await nav.goBranch(1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-inc')));
    await tester.pumpAndSettle();
    expect(find.text('Home: 1'), findsOneWidget);
    final Element home = tester.element(
      find.byType(DemoHomeScreen, skipOffstage: false),
    );
    final List<NavEntry<DemoRoute>> homeEntries = nav.state.branches[1].entries;

    await nav.goBranch(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('list-inc')));
    await tester.tap(find.byKey(const ValueKey<String>('item-1')));
    await tester.pumpAndSettle();
    expect(find.text('Detail 1'), findsOneWidget);
    final Element list = tester.element(
      find.byType(DemoListScreen, skipOffstage: false),
    );
    final int before = lock.seen.length;

    await openLink(tester, '/list/detail/2');

    expect(lock.seen, hasLength(before + 1));
    expect(lock.seen.last.active.top.route, lockedRoute);
    expectHome(tester, nav);
    expect(find.text('Home: 1'), findsOneWidget);
    expect(
      tester.element(find.byType(DemoHomeScreen, skipOffstage: false)),
      same(home),
    );
    expect(nav.state.branches[1].entries, orderedEquals(homeEntries));
    // The link replaced the detail and the redirect cut the locked one.
    expect(nav.state.branches[0].entries, hasLength(1));
    expect(
      tester.element(find.byType(DemoListScreen, skipOffstage: false)),
      same(list),
    );
    await nav.goBranch(0);
    await tester.pumpAndSettle();
    expect(find.text('List: 1'), findsOneWidget);
  });

  testWidgets('reevaluate after logout leaves the locked screen', (
    WidgetTester tester,
  ) async {
    final _Lock lock = _Lock(locked: false);
    final AdaptiveNav<DemoRoute> nav = build(lock);
    await pump(tester, nav);

    bool completed = false;
    Object? result = 'pending';
    nav.push(lockedRoute).then((Object? value) {
      completed = true;
      result = value;
    });
    await tester.pumpAndSettle();
    expect(find.text('Detail 2'), findsOneWidget);
    expect(completed, isFalse);

    lock.locked = true;
    nav.reevaluate();
    await tester.pumpAndSettle();

    expectHome(tester, nav);
    expect(nav.state.branches[0].entries, hasLength(1));
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('without a codec: the first frame is already home, asked once', (
    WidgetTester tester,
  ) async {
    final _Lock lock = _Lock(locked: true);
    final NavState<DemoRoute> base = baseState();
    final AdaptiveNav<DemoRoute> nav = build(
      lock,
      codec: null,
      initialState: base.withBranch(
        0,
        BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[
          base.branches[0].root,
          entry(lockedRoute),
        ]),
      ),
    );
    await pump(tester, nav, settle: false);

    expect(find.byType(DemoDetailScreen), findsNothing);
    expectHome(tester, nav);
    expect(lock.seen, hasLength(1));

    await tester.pumpAndSettle();
    expectHome(tester, nav);
    expect(lock.seen, hasLength(1));
  });

  testWidgets('with a codec and no link: asked once', (
    WidgetTester tester,
  ) async {
    setDefaultRoute(tester, '/');
    final _Lock lock = _Lock(locked: true);
    final AdaptiveNav<DemoRoute> nav = build(lock);
    await pump(tester, nav);

    expect(lock.seen, hasLength(1));
    // `/` decodes to home.
    expect(lock.seen.single.active.top.route, const DemoHome());
    expect(find.byType(DemoHomeScreen), findsOneWidget);
  });
}

/// The session flag and every state the redirect was shown.
class _Lock {
  _Lock({required this.locked});

  bool locked;
  final List<NavState<DemoRoute>> seen = <NavState<DemoRoute>>[];
}
