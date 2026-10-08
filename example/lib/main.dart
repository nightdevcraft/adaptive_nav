import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';
import 'screens.dart';
import 'sections.dart';

/// Branches after People and Settings, in order.
const List<(String, IconData, String)> _sections = <(String, IconData, String)>[
  ('teams', Icons.groups_outlined, 'Teams'),
  ('starred', Icons.star_outline, 'Starred'),
  ('recent', Icons.history, 'Recent'),
  ('archive', Icons.inventory_2_outlined, 'Archive'),
  ('trash', Icons.delete_outline, 'Trash'),
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
            // the panes get all 669 — still under the package's own defaults
            // of 320 + 360, which are a desktop's.
            //
            // They also keep the outer display a single stack, which is what
            // Apple asks for: the widest it ever offers is 489.
            //
            // In portrait the list is a narrow sidebar; in landscape the
            // boundary starts on the window centre — the hinge, on a Duo.
            masterDetail: const MasterDetailConfig(
              masterMinWidth: 270,
              detailMinWidth: 270,
              alignToWindowCenter: true,
              portraitPaneRatio: 0.4,
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
          for (final (String id, IconData icon, String label) in _sections)
            BranchConfig<AppRoute>(
              id: id,
              icon: icon,
              label: label,
              pageBuilder: _buildPage,
            ),
        ],
        // Flush panes with no margins. Set `margin`, `gap`, `radius` and
        // `canvasColor` to get floating cards instead; margins and the gap
        // count towards the pane widths.
        //
        // The marker colour makes the draggable boundary visible. On a
        // touch screen there is no resize cursor to show it.
        panes: PaneDecoration(
          splitHandleColor: (BuildContext context) =>
              Theme.of(context).colorScheme.outline,
        ),
        paneSplit: _paneSplit,
        // Back at another tab's root returns to People.
        backToBranch: 0,
        // iPhone Duo, inner display: headers beside the clock in portrait
        // (see `PeopleListScreen`), actions in the status column in landscape
        // (see `StarredScreen`).
        liftHeadersIntoStatusRow: true,
        actionsInStatusColumn: true,
      );

  /// The rail (or bar), the master and the detail each get their own shade of
  /// the same seed colour.
  static final ThemeData _theme = () {
    final ThemeData base = ThemeData(colorSchemeSeed: Colors.indigo);
    final Color chrome = base.colorScheme.surfaceContainer;
    return base.copyWith(
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: chrome,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: chrome,
      ),
    );
  }();

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
      for (final AppRoute root in const <AppRoute>[
        TeamsList(),
        StarredRoute(),
        NotesList(),
        ArchiveRoute(),
        TrashRoute(),
      ])
        BranchStack<AppRoute>(<NavEntry<AppRoute>>[
          NavEntry<AppRoute>(route: root, transition: AppTransition.platform),
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
    TeamsList() => const TeamsListScreen(),
    TeamDetail(:final int id) => TeamDetailScreen(id: id),
    StarredRoute() => const StarredScreen(),
    NotesList() => const NotesListScreen(),
    NoteDetail(:final int id) => NoteDetailScreen(id: id),
    ArchiveRoute() => const ArchiveScreen(),
    TrashRoute() => const TrashScreen(),
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
        // The playground sets the device's platform in a theme above.
        theme: _theme.copyWith(platform: Theme.of(context).platform),
        routerDelegate: _delegate,
        routeInformationParser: _parser,
      ),
    );
  }
}
