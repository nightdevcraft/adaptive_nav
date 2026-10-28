import 'dart:math' as math;

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav_ios/adaptive_nav_ios.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';
import 'screens.dart';
import 'sections.dart';

/// Branches after People and Settings, in order, and the root of each. The
/// app takes as many of them as its number of tabs leaves room for.
const List<(String, IconData, String, AppRoute)> _sections =
    <(String, IconData, String, AppRoute)>[
      ('teams', Icons.groups_outlined, 'Teams', TeamsList()),
      ('starred', Icons.star_outline, 'Starred', StarredRoute()),
      ('recent', Icons.history, 'Recent', NotesList()),
      ('archive', Icons.inventory_2_outlined, 'Archive', ArchiveRoute()),
      ('trash', Icons.delete_outline, 'Trash', TrashRoute()),
      ('calendar', Icons.event_outlined, 'Calendar', CalendarRoute()),
      ('files', Icons.folder_outlined, 'Files', FilesRoute()),
      ('tags', Icons.sell_outlined, 'Tags', TagsRoute()),
    ];

/// How many tabs the app has, People and Settings included:
/// `--dart-define=TABS=<n>`, from 2 to 10.
const int kTabs = int.fromEnvironment('TABS', defaultValue: 7);

/// On iPhone Duo the provider tells the shell what UIKit knows: which edge
/// the system wants the bar on, where its status area ends and where the
/// device folds. Everywhere else it provides nothing and the shell reads the
/// window's safe area, as it does without it.
void main() => runApp(const DuoGeometryProvider(child: ExampleApp()));

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.tabs = kTabs});

  /// People, Settings and the first `tabs - 2` sections; from 2 to 10.
  final int tabs;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final PeopleStore _store = PeopleStore();

  /// Stands in for real storage.
  final Map<Object, double> _savedFractions = <Object, double>{};

  AdaptiveShellConfig<AppRoute> _shellConfig(List<String> sections) =>
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
            // The outer display stays a single stack, as Apple asks, because
            // without its 84-point side bar it is at most 594 across: under the
            // 600 below which the package always shows one screen. Its 589
            // points of pane area in landscape would clear these minimums.
            //
            // In portrait the list is a narrow sidebar; in landscape the
            // boundary starts on the window centre — over the hinge, on a Duo;
            // half open, the fold adaptive_nav_ios reports takes it.
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
          // As many sections as `--dart-define=TABS` asks for. On a folded
          // iPhone Duo the system's column has two zones: the screen's
          // toolbar at the top, below the clock, and the tabs at the bottom,
          // within reach of the thumb, with as many places as the column's
          // height allows — the last one More when they are not enough. A
          // screen with buttons and too little room above the tabs folds them
          // to itself and More. On a desktop window the rail holds them all and
          // no button appears.
          for (final (String id, IconData icon, String label, AppRoute _)
              in _sections)
            if (sections.contains(id))
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
        // Back at another tab's root returns to People.
        backToBranch: 0,
        // iPhone Duo, inner display: headers beside the clock in portrait
        // (see `PaneAppBar`). Elsewhere on the Duo the screens' toolbars
        // (`PaneToolbar`, see `PersonDetailScreen`) stand in the system's
        // column, above the tabs and apart from them.
        liftHeadersIntoStatusRow: true,
        // An open detail covers the bar, or the rail beside one pane, as
        // Material does. `--dart-define=DETAIL_CHROME=kept` keeps them in
        // view on iOS, as a tab bar stays beside a pushed screen there; on
        // Android it changes nothing.
        detailChrome: DetailChrome.values.byName(
          const String.fromEnvironment(
            'DETAIL_CHROME',
            defaultValue: 'covered',
          ),
        ),
        // The tabs in the iPhone Duo system column are icons, as Apple draws
        // them. `--dart-define=RAIL_LABELS=all` names every tab, and
        // `selected` the current one, with room kept for a label under every
        // tab so that none moves as you switch.
        railLabelsInColumn: NavigationRailLabelType.values.byName(
          const String.fromEnvironment('RAIL_LABELS', defaultValue: 'none'),
        ),
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

  /// The ids of the sections [tabs] has room for.
  static List<String> _sectionsFor(int tabs) => <String>[
    for (final (String id, IconData _, String _, AppRoute _) in _sections.take(
      tabs.clamp(2, 2 + _sections.length) - 2,
    ))
      id,
  ];

  late List<String> _sectionIds = _sectionsFor(widget.tabs);

  /// The router and the navigation API in one object; it owns and disposes
  /// everything that notifies.
  ///
  /// Dragged pane widths are kept per branch and saved on release. An app
  /// reading storage asynchronously would seed them with `paneSplit.restore`.
  late AdaptiveNav<AppRoute> _nav = _navFor(_sectionIds);

  /// A navigation over People, Settings and [sections], starting with every
  /// tab at its root — or, given the state [from] of one over [previous]
  /// sections, with each tab that stays where it was.
  AdaptiveNav<AppRoute> _navFor(
    List<String> sections, {
    NavState<AppRoute>? from,
    List<String> previous = const <String>[],
  }) {
    final List<String> ids = <String>['people', 'settings', ...sections];
    final List<String> before = <String>['people', 'settings', ...previous];
    BranchStack<AppRoute> stack(String id, AppRoute root) {
      final int i = before.indexOf(id);
      return from != null && i >= 0
          ? from.branches[i]
          : BranchStack<AppRoute>(<NavEntry<AppRoute>>[
              NavEntry<AppRoute>(
                route: root,
                transition: AppTransition.platform,
              ),
            ]);
    }

    final int active = from == null
        ? 0
        : math.max(0, ids.indexOf(before[from.activeBranch]));
    final NavState<AppRoute> state = NavState<AppRoute>(
      activeBranch: active,
      branches: <BranchStack<AppRoute>>[
        stack('people', const PeopleList()),
        stack('settings', const SettingsRoute()),
        for (final (String id, IconData _, String _, AppRoute root)
            in _sections)
          if (sections.contains(id)) stack(id, root),
      ],
    );
    final AppRouteCodec codec = AppRouteCodec(sections: sections);
    return AdaptiveNav<AppRoute>(
      shellConfig: _shellConfig(sections),
      initialState: state,
      // The new router reports a location first, and the platform's default
      // would take the app back to People.
      initialLocation: from == null
          ? null
          : codec.encode(state.active.top.route).toString(),
      codec: codec,
      resizablePanes: true,
      paneFractions: _savedFractions,
      onPaneCommit: (Object branchId, double fraction) =>
          _savedFractions[branchId] = fraction,
    );
  }

  /// The shell's branches are fixed for the life of a navigation, so another
  /// number of tabs is another one: it starts where this one is, every tab
  /// that stays on the screen it showed. The screens are built anew — their
  /// navigators belong to the old one — so what a screen keeps in its own
  /// state, an unsaved edit or a switch, starts over.
  @override
  void didUpdateWidget(ExampleApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final List<String> sections = _sectionsFor(widget.tabs);
    if (listEquals(sections, _sectionIds)) {
      return;
    }
    final AdaptiveNav<AppRoute> old = _nav;
    _nav = _navFor(sections, from: old.state, previous: _sectionIds);
    _sectionIds = sections;
    // The router lets go of it in this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

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
    CalendarRoute() => const CalendarScreen(),
    FilesRoute() => const FilesScreen(),
    TagsRoute() => const TagsScreen(),
  };

  @override
  void dispose() {
    _nav.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      nav: _nav,
      store: _store,
      child: MaterialApp.router(
        title: 'adaptive_nav example',
        debugShowCheckedModeBanner: false,
        // The playground sets the device's platform in a theme above.
        theme: _theme.copyWith(platform: Theme.of(context).platform),
        routerConfig: _nav,
      ),
    );
  }
}
