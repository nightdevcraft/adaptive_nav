import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ----------------------------------------------------------------- routes

/// Fake routes for the demo harness (list -> detail -> editor, plus a home
/// tab).
@immutable
sealed class DemoRoute {
  const DemoRoute();
}

class DemoList extends DemoRoute {
  const DemoList();
  @override
  bool operator ==(Object other) => other is DemoList;
  @override
  int get hashCode => (DemoList).hashCode;
}

class DemoDetail extends DemoRoute {
  const DemoDetail(this.id);
  final int id;
  @override
  bool operator ==(Object other) => other is DemoDetail && other.id == id;
  @override
  int get hashCode => Object.hash(DemoDetail, id);
}

class DemoEdit extends DemoRoute {
  const DemoEdit(this.id);
  final int id;
  @override
  bool operator ==(Object other) => other is DemoEdit && other.id == id;
  @override
  int get hashCode => Object.hash(DemoEdit, id);
}

class DemoHome extends DemoRoute {
  const DemoHome();
  @override
  bool operator ==(Object other) => other is DemoHome;
  @override
  int get hashCode => (DemoHome).hashCode;
}

/// Root of the HIDDEN branch (no bar or rail destination), like a profile or
/// auth branch in an app: it can only be entered programmatically.
class DemoProfile extends DemoRoute {
  const DemoProfile();
  @override
  bool operator ==(Object other) => other is DemoProfile;
  @override
  int get hashCode => (DemoProfile).hashCode;
}

// ------------------------------------------------------------------ codec

class DemoCodec extends RouteCodec<DemoRoute> {
  const DemoCodec();

  @override
  Uri encode(DemoRoute route) => switch (route) {
    DemoList() => Uri.parse('/list'),
    DemoDetail(:final int id) => Uri.parse('/list/detail/$id'),
    DemoEdit(:final int id) => Uri.parse('/list/detail/$id/edit'),
    DemoHome() => Uri.parse('/home'),
    DemoProfile() => Uri.parse('/profile'),
  };

  @override
  DemoRoute decode(Uri uri) {
    final List<String> seg = uri.pathSegments;
    if (seg.isEmpty || seg.first == 'home') {
      return const DemoHome();
    }
    if (seg.first == 'profile') {
      return const DemoProfile();
    }
    if (seg.first == 'list') {
      if (seg.length >= 4 && seg[1] == 'detail' && seg[3] == 'edit') {
        final int? id = int.tryParse(seg[2]);
        if (id != null) {
          return DemoEdit(id);
        }
      }
      if (seg.length >= 3 && seg[1] == 'detail') {
        final int? id = int.tryParse(seg[2]);
        if (id != null) {
          return DemoDetail(id);
        }
      }
      return const DemoList();
    }
    return const DemoList();
  }

  @override
  int branchOf(DemoRoute route) => switch (route) {
    DemoHome() => 1,
    DemoProfile() => 2,
    DemoList() || DemoDetail() || DemoEdit() => 0,
  };
}

// --------------------------------------------------------------- nav scope

/// Passes the delegate down to the screens (an app would use a context
/// extension for this).
class DemoNav extends InheritedWidget {
  const DemoNav({required this.delegate, required super.child, super.key});

  final AdaptiveRouterDelegate<DemoRoute> delegate;

  static AdaptiveRouterDelegate<DemoRoute> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoNav>()!.delegate;

  @override
  bool updateShouldNotify(DemoNav oldWidget) => oldWidget.delegate != delegate;
}

// ------------------------------------------------------------------ screens

/// A widget with a DEFERRED overlay child (`OverlayPortal`) plus a `Tooltip`.
/// In a real app almost every screen carries something like it (rail
/// tooltips, menus, popovers), and without one the harness did not reproduce
/// the resize crash: reactivating the deferred child while the navigator
/// moved called `markNeedsLayout` on an ancestor, and if the layout was
/// decided inside a `LayoutBuilder` that failed the assertion
/// "_RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout".
class DemoOverlayBadge extends StatefulWidget {
  const DemoOverlayBadge({super.key});

  @override
  State<DemoOverlayBadge> createState() => _DemoOverlayBadgeState();
}

class _DemoOverlayBadgeState extends State<DemoOverlayBadge> {
  final OverlayPortalController _controller = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // Shown AFTER the first frame: the overlay has to be alive by the time of
    // the resize, or there is no deferred child to reactivate.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _controller.show();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately the ROOT overlay, like Material tooltips and menus: it
    // lives ABOVE the shell layout, so reactivating a deferred child while a
    // navigator moves touches somebody else's layout scope — which is what
    // brought the old `LayoutBuilder` down.
    return OverlayPortal(
      controller: _controller,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (BuildContext context) => const Positioned(
        left: 0,
        top: 0,
        child: IgnorePointer(child: SizedBox(width: 8, height: 8)),
      ),
      child: const Tooltip(message: 'tooltip', child: Icon(Icons.info_outline)),
    );
  }
}

/// A master screen with EPHEMERAL state (a counter): it has to survive not
/// only a rotation but the detail pane collapsing and expanding — the master
/// changes width rather than being remounted.
class DemoListScreen extends StatefulWidget {
  const DemoListScreen({super.key});

  @override
  State<DemoListScreen> createState() => _DemoListScreenState();
}

class _DemoListScreenState extends State<DemoListScreen> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List')),
      body: Column(
        children: <Widget>[
          const DemoOverlayBadge(),
          Text('List: $_counter'),
          ElevatedButton(
            key: const ValueKey<String>('list-inc'),
            onPressed: () => setState(() => _counter++),
            child: const Text('+'),
          ),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (int id = 1; id <= 3; id++)
                  ListTile(
                    key: ValueKey<String>('item-$id'),
                    title: Text('Item $id'),
                    onTap: () => DemoNav.of(context).push(DemoDetail(id)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A detail with EPHEMERAL state (a counter) — the thing that has to survive
/// a rotation.
class DemoDetailScreen extends StatefulWidget {
  const DemoDetailScreen({required this.id, super.key});

  final int id;

  @override
  State<DemoDetailScreen> createState() => _DemoDetailScreenState();
}

class _DemoDetailScreenState extends State<DemoDetailScreen> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detail ${widget.id}'),
        leading: BackButton(onPressed: () => DemoNav.of(context).pop()),
      ),
      body: Column(
        children: <Widget>[
          const DemoOverlayBadge(),
          Text('Counter: $_counter'),
          ElevatedButton(
            key: const ValueKey<String>('inc'),
            onPressed: () => setState(() => _counter++),
            child: const Text('+'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('open-edit'),
            onPressed: () => DemoNav.of(context).push(DemoEdit(widget.id)),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

class DemoEditScreen extends StatelessWidget {
  const DemoEditScreen({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No `leading` of its own: the `AppBar` has to supply the back arrow
      // itself, the way app screens do (see detail_back_button_test).
      appBar: AppBar(title: Text('Editing $id')),
      body: Center(child: Text('Editing $id')),
    );
  }
}

/// A Home tab with state of its own, to check that an inactive tab keeps it.
class DemoHomeScreen extends StatefulWidget {
  const DemoHomeScreen({super.key});

  @override
  State<DemoHomeScreen> createState() => _DemoHomeScreenState();
}

class _DemoHomeScreenState extends State<DemoHomeScreen> {
  int _tapped = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        children: <Widget>[
          Text('Home: $_tapped'),
          ElevatedButton(
            key: const ValueKey<String>('home-inc'),
            onPressed: () => setState(() => _tapped++),
            child: const Text('+'),
          ),
        ],
      ),
    );
  }
}

/// Root of the hidden branch (no chrome destination).
class DemoProfileScreen extends StatelessWidget {
  const DemoProfileScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Profile')));
}

// ------------------------------------------------------------------ harness

/// Builds the delegate, the parser and the app for the tests. `staff`
/// (branch 0) is master-detail, `home` (branch 1) is a plain tab, and
/// `profile` (branch 2, only with [withHiddenBranch]) is a branch with NO
/// chrome destination.
///
/// [showsChrome] and [redirect] are unset by default, as are the chrome and
/// drawer builders and [scaffoldKey] — so the defaults are plain Material.
class DemoHarness {
  DemoHarness({
    ChromeVisibility<DemoRoute>? showsChrome,
    RedirectHook<DemoRoute>? redirect,
    bool withHiddenBranch = false,
    ShellChromeBuilder? barBuilder,
    ShellChromeBuilder? railBuilder,
    ShellDrawerBuilder? drawerBuilder,
    GlobalKey<ScaffoldState>? scaffoldKey,
    bool collapseWhenDetailEmpty = true,
    bool extendBodyBehindBar = false,
    Duration branchFadeDuration = Duration.zero,
    PaneDecoration panes = PaneDecoration.none,
    RailDecoration rail = RailDecoration.none,
    PaneSplitController? paneSplit,
    ValueListenable<bool>? immersive,
    Duration immersiveDuration = kDefaultImmersiveDuration,
  }) {
    NavEntry<DemoRoute> root(DemoRoute route) =>
        NavEntry<DemoRoute>(route: route, transition: AppTransition.platform);

    baseState = NavState<DemoRoute>(
      activeBranch: 0,
      branches: <BranchStack<DemoRoute>>[
        BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoList())]),
        BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[root(const DemoHome())]),
        if (withHiddenBranch)
          BranchStack<DemoRoute>(<NavEntry<DemoRoute>>[
            root(const DemoProfile()),
          ]),
      ],
    );

    delegate = AdaptiveRouterDelegate<DemoRoute>(
      shellConfig: AdaptiveShellConfig<DemoRoute>(
        branches: <BranchConfig<DemoRoute>>[
          BranchConfig<DemoRoute>(
            id: 'staff',
            icon: Icons.people,
            label: 'People',
            masterDetail: MasterDetailConfig(
              paneRatio: 0.35,
              collapseWhenDetailEmpty: collapseWhenDetailEmpty,
            ),
            pageBuilder: _buildPage,
          ),
          BranchConfig<DemoRoute>(
            id: 'home',
            icon: Icons.home,
            label: 'Home',
            pageBuilder: _buildPage,
          ),
          if (withHiddenBranch)
            BranchConfig<DemoRoute>(
              id: 'profile',
              icon: Icons.person,
              label: 'Profile',
              pageBuilder: _buildPage,
              showsInChrome: false,
            ),
        ],
        showsChrome: showsChrome,
        redirect: redirect,
        barBuilder: barBuilder,
        railBuilder: railBuilder,
        drawerBuilder: drawerBuilder,
        scaffoldKey: scaffoldKey,
        extendBodyBehindBar: extendBodyBehindBar,
        branchFadeDuration: branchFadeDuration,
        panes: panes,
        rail: rail,
        paneSplit: paneSplit,
        immersive: immersive,
        immersiveDuration: immersiveDuration,
      ),
      initialState: baseState,
    );

    parser = AdaptiveRouteInformationParser<DemoRoute>(
      codec: const DemoCodec(),
      baseState: baseState,
    );
  }

  late final NavState<DemoRoute> baseState;
  late final AdaptiveRouterDelegate<DemoRoute> delegate;
  late final AdaptiveRouteInformationParser<DemoRoute> parser;

  Widget _buildPage(DemoRoute route) => switch (route) {
    DemoList() => const DemoListScreen(),
    DemoDetail(:final int id) => DemoDetailScreen(id: id),
    DemoEdit(:final int id) => DemoEditScreen(id: id),
    DemoHome() => const DemoHomeScreen(),
    DemoProfile() => const DemoProfileScreen(),
  };

  Widget app() => DemoNav(
    delegate: delegate,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerDelegate: delegate,
    ),
  );
}
