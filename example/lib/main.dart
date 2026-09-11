import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';
import 'screens.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final PeopleStore _store = PeopleStore();

  /// Stands in for real storage.
  final Map<Object, double> _savedFractions = <Object, double>{};

  /// Pane widths the user dragged, kept per branch. `onCommit` fires on release
  /// rather than on every drag frame; an app reading storage asynchronously
  /// would seed the controller later with `restore` instead of `initial`.
  late final PaneSplitController _paneSplit = PaneSplitController(
    initial: _savedFractions,
    onCommit: (Object branchId, double fraction) =>
        _savedFractions[branchId] = fraction,
  );

  late final AdaptiveShellConfig<AppRoute> _shellConfig =
      AdaptiveShellConfig<AppRoute>(
        branches: <BranchConfig<AppRoute>>[
          BranchConfig<AppRoute>(
            id: 'people',
            icon: Icons.people_outline,
            label: 'People',
            // With a master-detail config the branch splits into two panes
            // once the window is wide enough; below that it is a plain stack.
            masterDetail: const MasterDetailConfig(paneRatio: 0.36),
            // Details fade when they swap the contents of a pane and slide
            // when they take the whole screen, decided as the animation runs.
            transition: AppTransition.adaptive,
            pageBuilder: _buildPage,
          ),
          BranchConfig<AppRoute>(
            id: 'settings',
            icon: Icons.settings_outlined,
            label: 'Settings',
            pageBuilder: _buildPage,
          ),
        ],
        // Floating rounded panes on a canvas. The margins and the gap are part
        // of the width arithmetic, not an ornament, so the package needs them
        // here rather than in a theme.
        panes: PaneDecoration(
          margin: const EdgeInsets.all(12),
          gap: 8,
          radius: BorderRadius.circular(16),
          canvasColor: (BuildContext context) =>
              Theme.of(context).colorScheme.surfaceContainerHighest,
          splitHandleColor: (BuildContext context) =>
              Theme.of(context).colorScheme.outlineVariant,
        ),
        paneSplit: _paneSplit,
      );

  late final AdaptiveRouterDelegate<AppRoute> _delegate =
      AdaptiveRouterDelegate<AppRoute>(
        shellConfig: _shellConfig,
        initialState: _initialState,
      );

  static final NavState<AppRoute> _initialState = NavState<AppRoute>(
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
  );

  late final AdaptiveRouteInformationParser<AppRoute> _parser =
      AdaptiveRouteInformationParser<AppRoute>(
        codec: const AppRouteCodec(),
        baseState: _initialState,
      );

  Widget _buildPage(AppRoute route) => switch (route) {
    PeopleList() => const PeopleListScreen(),
    PersonDetail(:final int id) => PersonDetailScreen(id: id),
    PersonEdit(:final int id) => PersonEditScreen(id: id),
    SettingsRoute() => const SettingsScreen(),
  };

  @override
  void dispose() {
    _paneSplit.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      delegate: _delegate,
      store: _store,
      child: MaterialApp.router(
        title: 'adaptive_nav example',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        routerDelegate: _delegate,
        routeInformationParser: _parser,
      ),
    );
  }
}
