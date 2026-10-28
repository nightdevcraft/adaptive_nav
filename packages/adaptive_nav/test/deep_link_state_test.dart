import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';

/// What an incoming location and a redirect do to the stacks they do not
/// target, and to the screens they remove.
void main() {
  NavState<DemoRoute> parse(DemoHarness h, String location) =>
      _sync(h.parser, location);

  test('a deep link replaces its own branch and keeps the others', () async {
    final DemoHarness h = DemoHarness();
    h.delegate.push(const DemoDetail(1));
    await h.delegate.goBranch(1);
    h.delegate.push(const DemoHome());
    final BranchStack<DemoRoute> home = h.delegate.state.branches[1];

    await h.delegate.setNewRoutePath(parse(h, '/list/detail/3'));

    expect(h.delegate.state.activeBranch, 0);
    expect(h.delegate.state.active.top.route, const DemoDetail(3));
    expect(h.delegate.state.branches[1], same(home));
  });

  test('a deep link keeps the root the branch was reset to', () async {
    final DemoHarness h = DemoHarness();
    await h.delegate.resetTo(const DemoEdit(1));
    final NavEntry<DemoRoute> root = h.delegate.state.active.root;

    await h.delegate.setNewRoutePath(parse(h, '/list/detail/3'));
    expect(h.delegate.state.active.root, same(root));
    expect(h.delegate.state.active.top.route, const DemoDetail(3));

    await h.delegate.setNewRoutePath(parse(h, '/list/detail/1/edit'));
    expect(h.delegate.state.active.entries, hasLength(1));
    expect(h.delegate.state.active.root, same(root));
  });

  test('a deep link to an open screen reuses it', () async {
    final DemoHarness h = DemoHarness();
    bool firstDone = false;
    h.delegate.push(const DemoDetail(1)).then((_) => firstDone = true);
    final Future<Object?> second = h.delegate.push(const DemoDetail(2));
    bool secondDone = false;
    second.then((_) => secondDone = true);
    final NavEntry<DemoRoute> top = h.delegate.state.active.top;
    final NavEntry<DemoRoute> below = h.delegate.state.active.entries[1];

    await h.delegate.setNewRoutePath(parse(h, '/list/detail/2'));
    await Future<void>.delayed(Duration.zero);
    expect(h.delegate.state.active.top, same(top));
    expect(h.delegate.state.active.top.pageKey, top.pageKey);
    expect(h.delegate.state.active.entries, hasLength(3));
    expect(secondDone, isFalse);

    await h.delegate.setNewRoutePath(parse(h, '/list/detail/1'));
    expect(h.delegate.state.active.top, same(below));
    expect(h.delegate.state.active.entries, hasLength(2));
    expect(await second.timeout(const Duration(seconds: 1)), isNull);
    expect(firstDone, isFalse);
  });

  test('a screen a deep link removes completes its push with null', () async {
    final DemoHarness h = DemoHarness();
    final Future<Object?> detail = h.delegate.push(const DemoDetail(1));

    await h.delegate.setNewRoutePath(parse(h, '/list/detail/3'));

    expect(await detail.timeout(const Duration(seconds: 1)), isNull);
  });

  test('a screen redirect removes completes its push with null', () async {
    bool signedIn = true;
    final DemoHarness h = DemoHarness(
      redirect: (NavState<DemoRoute> next) =>
          signedIn ? next : next.withBranch(0, next.branches[0].resetToRoot()),
    );
    final Future<Object?> detail = h.delegate.push(const DemoDetail(1));

    signedIn = false;
    h.delegate.reevaluate();

    expect(h.delegate.state.active.hasDetail, isFalse);
    expect(await detail.timeout(const Duration(seconds: 1)), isNull);
  });

  test('the constructor does not call redirect', () {
    int calls = 0;
    final DemoHarness h = DemoHarness(
      redirect: (NavState<DemoRoute> next) {
        calls++;
        return next.copyWith(activeBranch: 1);
      },
    );
    expect(calls, 0);
    expect(h.delegate.state.activeBranch, 0);
  });

  testWidgets('without a codec redirect applies to the first frame', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final DemoHarness h = DemoHarness(
      redirect: (NavState<DemoRoute> next) {
        calls++;
        return next.copyWith(activeBranch: 1);
      },
    );
    int notified = 0;
    h.delegate.addListener(() => notified++);

    await tester.pumpWidget(h.app());
    expect(calls, 1);
    expect(notified, 0);
    expect(h.delegate.state.activeBranch, 1);
    expect(h.delegate.mountedBranches, <int>{1});
    expect(find.byType(DemoHomeScreen), findsOneWidget);
    expect(find.byType(DemoListScreen), findsNothing);

    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('with a codec redirect runs once at start', (
    WidgetTester tester,
  ) async {
    final List<DemoRoute> seen = <DemoRoute>[];
    final DemoHarness template = DemoHarness();
    final AdaptiveNav<DemoRoute> nav = AdaptiveNav<DemoRoute>(
      shellConfig: AdaptiveShellConfig<DemoRoute>(
        branches: template.delegate.shellConfig.branches,
        redirect: (NavState<DemoRoute> next) {
          seen.add(next.active.top.route);
          return next;
        },
      ),
      initialState: template.baseState,
      codec: const DemoCodec(),
      initialLocation: '/list/detail/3',
    );
    addTearDown(nav.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: nav));
    await tester.pumpAndSettle();
    expect(seen, <DemoRoute>[const DemoDetail(3)]);
    expect(nav.state.active.top.route, const DemoDetail(3));
  });

  testWidgets('a deep-linked screen gets its branch transition', (
    WidgetTester tester,
  ) async {
    NavEntry<DemoRoute> root(DemoRoute route) =>
        NavEntry<DemoRoute>(route: route, transition: AppTransition.platform);
    final AdaptiveShellConfig<DemoRoute> config =
        AdaptiveShellConfig<DemoRoute>(
          branches: <BranchConfig<DemoRoute>>[
            BranchConfig<DemoRoute>(
              id: 'staff',
              icon: Icons.people,
              label: 'People',
              transition: AppTransition.adaptive,
              pageBuilder: (_) => const SizedBox(),
            ),
            BranchConfig<DemoRoute>(
              id: 'home',
              icon: Icons.home,
              label: 'Home',
              pageBuilder: (_) => const SizedBox(),
            ),
          ],
        );
    final AdaptiveNav<DemoRoute> nav = AdaptiveNav<DemoRoute>(
      shellConfig: config,
      initialState: NavState<DemoRoute>(
        activeBranch: 0,
        branches: <BranchStack<DemoRoute>>[
          BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoList())]),
          BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoHome())]),
        ],
      ),
      codec: const DemoCodec(),
    );
    addTearDown(nav.dispose);

    final NavState<DemoRoute> parsed = _sync(
      nav.routeInformationParser!,
      '/list/detail/3',
    );
    expect(parsed.active.top.transition, AppTransition.adaptive);
  });
}

/// The parser answers with a `SynchronousFuture`.
NavState<DemoRoute> _sync(
  AdaptiveRouteInformationParser<DemoRoute> parser,
  String location,
) {
  late NavState<DemoRoute> result;
  parser
      .parseRouteInformation(RouteInformation(uri: Uri.parse(location)))
      .then((NavState<DemoRoute> s) => result = s);
  return result;
}
