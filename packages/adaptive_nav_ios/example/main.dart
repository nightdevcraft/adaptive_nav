// An adaptive_nav app with iPhone Duo's geometry from UIKit.
//
// adaptive_nav alone reads the posture off `MediaQuery`. Wrapped in a
// DuoGeometryProvider, its shell takes three things from UIKit instead: the
// edge the system wants the vertical bar on (the left window of Split View
// included, which `MediaQuery` cannot tell), the system's status area at the
// top of that bar, and the fold while the device is half open.
//
// The package calls APIs of the iOS 27.1 SDK, so the app builds with Xcode
// 27.1 or later. Below iOS 27.1 at run time, and on every platform but iOS,
// the provider has nothing to say and the shell reads `MediaQuery` as it
// would without it — so this file runs anywhere Flutter does.
//
// For a full app, see adaptive_nav's example.

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav_ios/adaptive_nav_ios.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DuoGeometryProvider(child: App()));

// To see what UIKit reports, run this instead: the probe draws the fold, the
// cameras and the safe area over the app, and prints a `duo_probe` line on
// every change.
//
// void main() => runApp(
//   const DuoGeometryProvider(child: DuoGeometryProbe(child: App())),
// );

@immutable
sealed class AppRoute {
  const AppRoute();
}

class PeopleList extends AppRoute {
  const PeopleList();

  @override
  bool operator ==(Object other) => other is PeopleList;

  @override
  int get hashCode => (PeopleList).hashCode;
}

class PersonDetail extends AppRoute {
  const PersonDetail(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is PersonDetail && other.id == id;

  @override
  int get hashCode => Object.hash(PersonDetail, id);
}

class SettingsRoute extends AppRoute {
  const SettingsRoute();

  @override
  bool operator ==(Object other) => other is SettingsRoute;

  @override
  int get hashCode => (SettingsRoute).hashCode;
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AdaptiveNav<AppRoute> _nav = AdaptiveNav<AppRoute>(
    shellConfig: AdaptiveShellConfig<AppRoute>(
      branches: <BranchConfig<AppRoute>>[
        BranchConfig<AppRoute>(
          id: 'people',
          icon: Icons.people_outline,
          label: 'People',
          // Two panes where there is room. Half open, the boundary between
          // them goes on the fold UIKit reports.
          masterDetail: const MasterDetailConfig(alignToWindowCenter: true),
          pageBuilder: _page,
        ),
        BranchConfig<AppRoute>(
          id: 'settings',
          icon: Icons.settings_outlined,
          label: 'Settings',
          pageBuilder: _page,
        ),
      ],
    ),
    initialState: NavState<AppRoute>(
      activeBranch: 0,
      branches: <BranchStack<AppRoute>>[
        BranchStack<AppRoute>(<NavEntry<AppRoute>>[
          NavEntry<AppRoute>(
            route: const PeopleList(),
            transition: AppTransition.platform,
          ),
        ]),
        BranchStack<AppRoute>(<NavEntry<AppRoute>>[
          NavEntry<AppRoute>(
            route: const SettingsRoute(),
            transition: AppTransition.platform,
          ),
        ]),
      ],
    ),
  );

  Widget _page(AppRoute route) => switch (route) {
    PeopleList() => Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: ListView(
        children: <Widget>[
          for (int id = 1; id <= 20; id++)
            ListTile(
              title: Text('Person $id'),
              onTap: () => _nav.resetDetailTo(PersonDetail(id)),
            ),
        ],
      ),
    ),
    PersonDetail(:final int id) => Scaffold(
      appBar: AppBar(title: Text('Person $id')),
      body: Center(child: Text('Person $id')),
    ),
    SettingsRoute() => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const _GeometryInfo(),
    ),
  };

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(routerConfig: _nav);
}

/// The rest of what UIKit reports is in [DuoGeometryScope].
class _GeometryInfo extends StatelessWidget {
  const _GeometryInfo();

  @override
  Widget build(BuildContext context) {
    final DuoGeometry? geometry = DuoGeometryScope.maybeOf(context);
    if (geometry == null) {
      return const Center(child: Text('Nothing from UIKit'));
    }
    return ListView(
      children: <Widget>[
        ListTile(
          title: const Text('Vertical bar'),
          trailing: Text(geometry.verticalBarSide?.name ?? 'none'),
        ),
        ListTile(
          title: const Text('Hinge'),
          trailing: Text(geometry.hingeStatus?.name ?? 'none'),
        ),
        ListTile(
          title: const Text('Active folds'),
          trailing: Text('${geometry.activeDivisions.length}'),
        ),
      ],
    );
  }
}
