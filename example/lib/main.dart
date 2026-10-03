import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';
import 'screens.dart';

/// Sections that exist only to fill the chrome, in branch order after People
/// and Settings.
///
/// The labels are deliberately uneven: "Trash" fits a rail on one line and
/// "Recent calls" does not, and the taller one sets the height every
/// destination is counted at when the shell works out how many fit.
///
/// A label with no space in it has nowhere to break, so Material splits it
/// mid-word — "Favourites" becomes "Favourite" and a lone "s". In an 80-point
/// rail that is a reason to keep labels short, which is Apple's advice for the
/// vertical bar too.
const List<(IconData, String)> _placeholderTabs = <(IconData, String)>[
  (Icons.groups_outlined, 'Teams'),
  (Icons.star_outline, 'Starred'),
  (Icons.history, 'Recent'),
  (Icons.inventory_2_outlined, 'Archive'),
  (Icons.insert_chart_outlined, 'Reports'),
  (Icons.delete_outline, 'Trash'),
];

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
            //
            // The minimums are what "wide enough" means, and they are picked
            // for the narrowest display this demo wants two panes on: the
            // inner screen of an iPhone Duo in portrait. It is 669 points
            // across and keeps horizontal bars, so no rail takes a share and
            // 645 are left after the card margins — still under the package's
            // own defaults of 320 + 360, which are a desktop's.
            //
            // They also keep the outer display a single stack, which is what
            // Apple asks for: the widest it ever offers is 489.
            masterDetail: const MasterDetailConfig(
              paneRatio: 0.36,
              masterMinWidth: 300,
              detailMinWidth: 330,
            ),
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
          // Enough sections that the rail runs out of column on a folded
          // iPhone Duo. What does not fit goes behind the menu button at the
          // end of the rail; on a desktop window they all fit and no button
          // appears.
          for (int i = 0; i < _placeholderTabs.length; i++)
            BranchConfig<AppRoute>(
              id: 'tab-$i',
              icon: _placeholderTabs[i].$1,
              label: _placeholderTabs[i].$2,
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
      for (int i = 0; i < _placeholderTabs.length; i++)
        BranchStack<AppRoute>(<NavEntry<AppRoute>>[
          NavEntry<AppRoute>(
            route: PlaceholderTab(i),
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
    PlaceholderTab(:final int index) => PlaceholderTabScreen(
      icon: _placeholderTabs[index].$1,
      label: _placeholderTabs[index].$2,
    ),
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
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        routerDelegate: _delegate,
        routeInformationParser: _parser,
      ),
    );
  }
}
