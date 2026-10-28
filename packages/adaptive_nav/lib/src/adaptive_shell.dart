import 'dart:math' as math;
import 'dart:ui' show Display;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'column_back_gesture.dart';
import 'column_transition.dart';
import 'entry_page.dart';
import 'fold.dart';
import 'nav_config.dart';
import 'nav_state.dart';
import 'pane_metrics.dart';
import 'pane_split.dart';
import 'pane_toolbar.dart';
import 'status_row.dart';
import 'system_geometry.dart';

typedef _Stacks = ({Widget masters, Widget details, Widget placeholder});

/// The system's column on [edge], when there is one beside the panes:
/// whether the rail is in it, the pane whose toolbar stands in it, `null`
/// while every pane keeps a header, and whether that pane is the only one.
typedef _SystemColumn = ({
  ChromePlacement edge,
  bool inRail,
  PaneSlot? slot,
  bool onePane,
});

/// The system's column as the state has it, and as it will be once the
/// active pane's top screen is gone: what a back gesture on that screen
/// leads to.
typedef _Columns = ({_SystemColumn? now, _SystemColumn? afterBack});

/// Stable keys for one branch's navigators, held by the delegate.
///
/// A `Navigator` addressed by a `GlobalKey` moves between the compact, medium
/// and expanded layouts with its whole route stack instead of being remounted.
/// That is the mechanism behind state surviving a rotation.
class BranchNavigatorKeys {
  /// Master (root) of a master-detail branch, or the whole stack of a plain
  /// tab.
  final GlobalKey<NavigatorState> master = GlobalKey<NavigatorState>();

  /// The stack above the root. Always mounted; empty means one transparent
  /// page.
  final GlobalKey<NavigatorState> detail = GlobalKey<NavigatorState>();
}

/// Chrome plus master and detail panes, all built from one state.
///
/// - compact: bar, master in the body, detail overlaying the bar;
/// - medium: rail, one pane, the detail covering the master and the rail;
/// - expanded: rail, master and detail side by side.
///
/// With [DetailChrome.kept] on an Apple platform the one-pane detail leaves
/// the bar or the rail in view instead.
///
/// With [chrome] `false` the layout is the same minus the bar and rail. Only
/// the chrome widget goes; the branch navigators stay where they are.
class AdaptiveShell<R> extends StatelessWidget {
  const AdaptiveShell({
    required this.state,
    required this.shellConfig,
    required this.branchKeys,
    required this.branchFadeKey,
    required this.masterMessengerKey,
    required this.detailMessengerKey,
    required this.mountedBranches,
    required this.chrome,
    required this.onSelectBranch,
    required this.buildPage,
    required this.onDidRemovePage,
    required this.onNavigationNotification,
    required this.onDrawerChanged,
    required this.immersive,
    required this.paneSplit,
    required this.paneToolbars,
    required this.columnTransitions,
    super.key,
  });

  final NavState<R> state;
  final AdaptiveShellConfig<R> shellConfig;

  /// The config's own, or the one `AdaptiveNav` owns.
  final ValueListenable<bool>? immersive;
  final PaneSplitController? paneSplit;

  /// The toolbars of the screens on top of each pane, which the shell draws
  /// in the system's column where a pane's toolbar is vertical.
  final PaneToolbarRegistry paneToolbars;

  /// The navigators' transitions, which the system's column follows.
  final ColumnTransitions columnTransitions;
  final List<BranchNavigatorKeys> branchKeys;
  final Key branchFadeKey;
  final GlobalKey<ScaffoldMessengerState> masterMessengerKey;
  final GlobalKey<ScaffoldMessengerState> detailMessengerKey;

  /// Branches opened at least once; only their navigators are mounted. The set
  /// only grows.
  final Set<int> mountedBranches;

  final bool chrome;

  /// Branch index, not a position among the chrome's destinations.
  final ValueChanged<int> onSelectBranch;

  final Page<Object?> Function(
    BranchConfig<R> config,
    NavEntry<R> entry, {
    int detailIndex,
  })
  buildPage;
  final DidRemovePageCallback onDidRemovePage;

  /// Every branch navigator's `NavigationNotification` goes here instead of
  /// to `WidgetsApp`; the delegate sends one answer for the whole shell.
  final bool Function(
    GlobalKey<NavigatorState> navigator,
    NavigationNotification notification,
  )
  onNavigationNotification;

  /// The shell drawer opened or closed.
  final DrawerCallback onDrawerChanged;

  static const double dividerWidth = kDefaultRailDividerWidth;

  // Keys for the shell's own layers. Tests need to address exactly these: the
  // shell sits inside a page of the root `Navigator`, whose transition is a
  // `FadeTransition` of its own, and there is more than one `IndexedStack`.
  @visibleForTesting
  static const Key mastersStackKey = ValueKey<String>('adaptive-nav.masters');
  @visibleForTesting
  static const Key detailsStackKey = ValueKey<String>('adaptive-nav.details');
  @visibleForTesting
  static const Key branchFadeLayerKey = ValueKey<String>(
    'adaptive-nav.branch-fade',
  );
  @visibleForTesting
  static const Key railRegionKey = ValueKey<String>('adaptive-nav.rail-region');
  @visibleForTesting
  static const Key paneSplitHandleKey = ValueKey<String>(
    'adaptive-nav.pane-split',
  );
  @visibleForTesting
  static const Key railOverflowKey = ValueKey<String>(
    'adaptive-nav.rail-overflow',
  );

  /// The folded tabs of the system's column: the places they keep, the
  /// selected tab's and More's, or More's alone. Present only while folded.
  @visibleForTesting
  static const Key railCollapsedKey = ValueKey<String>(
    'adaptive-nav.rail-collapsed',
  );
  @visibleForTesting
  static const Key paneToolbarKey = ValueKey<String>(
    'adaptive-nav.pane-toolbar',
  );
  @visibleForTesting
  static const Key paneToolbarMenuKey = ValueKey<String>(
    'adaptive-nav.pane-toolbar-menu',
  );

  /// The system's column with the tabs in it. Its toolbar zone is
  /// [paneToolbarKey] while a screen's toolbar may stand there.
  @visibleForTesting
  static const Key systemColumnKey = ValueKey<String>(
    'adaptive-nav.system-column',
  );

  /// The system's column where the rail is not in it: the toolbar the shell
  /// draws over the panes. There whenever the system has a column, empty
  /// while the rail is in it.
  @visibleForTesting
  static const Key bareColumnKey = ValueKey<String>('adaptive-nav.bare-column');

  /// The strip at the window's leading edge where a back swipe in the
  /// system's column starts; there only while a single pane that can go
  /// back stands beside the column there, on iOS.
  @visibleForTesting
  static const Key columnBackGestureKey = ValueKey<String>(
    'adaptive-nav.column-back-gesture',
  );

  /// The tabs' zone of the system's column, as tall as its places.
  @visibleForTesting
  static const Key columnTabsKey = ValueKey<String>('adaptive-nav.column-tabs');

  /// The place of [branch]'s tab in the system's column.
  @visibleForTesting
  static Key columnTabKey(int branch) =>
      ValueKey<String>('adaptive-nav.column-tab.$branch');

  bool get _activeDetailEmpty {
    final BranchConfig<R> cfg = shellConfig.branches[state.activeBranch];
    return cfg.masterDetail == null ||
        state.branches[state.activeBranch].entries.length <= 1;
  }

  List<Page<Object?>> _mainPages(int branch) {
    final BranchConfig<R> cfg = shellConfig.branches[branch];
    final BranchStack<R> stack = state.branches[branch];
    if (cfg.masterDetail != null) {
      return <Page<Object?>>[buildPage(cfg, stack.root)]; // master = the root
    }
    return <Page<Object?>>[
      for (final NavEntry<R> e in stack.entries) buildPage(cfg, e),
    ];
  }

  /// A transparent base page always comes first. It keeps an empty navigator
  /// buildable, and it puts a route below the detail so `AppBar` draws the back
  /// arrow (`impliesAppBarDismissal` looks for one).
  List<Page<Object?>> _detailPages(int branch) {
    final BranchConfig<R> cfg = shellConfig.branches[branch];
    final BranchStack<R> stack = state.branches[branch];
    return <Page<Object?>>[
      emptyDetailPage(),
      if (cfg.masterDetail != null)
        for (int i = 1; i < stack.entries.length; i++)
          buildPage(cfg, stack.entries[i], detailIndex: i - 1),
    ];
  }

  /// [slot] is the pane the navigator fills; its screens register their
  /// toolbars under it, and learn from [column] whether theirs is vertical.
  Widget _nav(
    GlobalKey<NavigatorState> key,
    List<Page<Object?>> pages,
    PaneSlot slot,
    _SystemColumn? column,
  ) {
    // Outside the `Navigator`, which corrects its own report first. Several
    // navigators cannot share the `HeroController` from `MaterialApp`.
    return PaneToolbarHost(
      registry: paneToolbars,
      slot: slot,
      automaticBack: shellConfig.automaticBackInColumn,
      child: PaneBarScope(
        bar: PaneBar(verticalEdge: column?.slot == slot ? column!.edge : null),
        child: NotificationListener<NavigationNotification>(
          onNotification: (NavigationNotification n) =>
              onNavigationNotification(key, n),
          child: BranchActiveScope(
            active: slot.branch == state.activeBranch,
            child: HeroControllerScope.none(
              child: Navigator(
                key: key,
                pages: pages,
                onDidRemovePage: onDidRemovePage,
                observers: <NavigatorObserver>[
                  columnTransitions.observerFor(key),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mastersStackAt(int index, _SystemColumn? column) => IndexedStack(
    key: mastersStackKey,
    index: index,
    sizing: StackFit.expand,
    children: <Widget>[
      for (int i = 0; i < shellConfig.branches.length; i++)
        if (mountedBranches.contains(i))
          _nav(branchKeys[i].master, _mainPages(i), (
            branch: i,
            detail: false,
          ), column)
        else
          const SizedBox.shrink(),
    ],
  );

  Widget _mastersStack(_SystemColumn? column) {
    final Duration fade = shellConfig.branchFadeDuration;
    if (fade == Duration.zero) {
      return _paneMessenger(
        masterMessengerKey,
        _mastersStackAt(state.activeBranch, column),
      );
    }
    return _paneMessenger(
      masterMessengerKey,
      _BranchFadeThrough(
        key: branchFadeKey,
        index: state.activeBranch,
        duration: fade,
        builder: (int index) => _mastersStackAt(index, column),
      ),
    );
  }

  /// One `ScaffoldMessenger` per pane, so a snack bar appears once and in the
  /// pane the action came from.
  ///
  /// The root messenger draws into every root `Scaffold` of its set. On compact
  /// there are two of those, since the detail layer is a sibling of the shell
  /// `Scaffold`, and one message was drawn twice; on wide the shell drew it and
  /// the bar stretched under both panes.
  Widget _paneMessenger(GlobalKey<ScaffoldMessengerState> key, Widget child) =>
      ScaffoldMessenger(key: key, child: child);

  Widget _detailsStack(_SystemColumn? column) => _paneMessenger(
    detailMessengerKey,
    IndexedStack(
      key: detailsStackKey,
      index: state.activeBranch,
      sizing: StackFit.expand,
      children: <Widget>[
        for (int i = 0; i < shellConfig.branches.length; i++)
          if (mountedBranches.contains(i))
            _nav(branchKeys[i].detail, _detailPages(i), (
              branch: i,
              detail: true,
            ), column)
          else
            const SizedBox.shrink(),
      ],
    ),
  );

  /// [inPane] is the signal [AppTransition.adaptive] pages read. It lives in a
  /// scope rather than in the entry, because the layout changes on resize while
  /// the page has to stay the same one.
  Widget _detailsIn(_Stacks stacks, {required bool inPane}) =>
      DetailPaneScope(inPane: inPane, child: stacks.details);

  Widget _detailPlaceholder() {
    final WidgetBuilder? b =
        shellConfig.branches[state.activeBranch].detailPlaceholder;
    // A blank pane, not a caption: the package has no screens of its own and
    // no business shipping a string it cannot localise. Anything to say in an
    // empty pane is [BranchConfig.detailPlaceholder]'s to say.
    return b != null ? Builder(builder: b) : const Scaffold();
  }

  @override
  Widget build(BuildContext context) {
    final Size window = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final SystemGeometry? system = SystemGeometryScope.maybeOf(context);
    final ChromePlacement placement = shellConfig.chromeLayout(
      window,
      padding,
      system,
    );
    // In window coordinates, like a display feature's bounds; converted to
    // pane coordinates once the pane area's origin is known.
    final Rect? foldHint = shellConfig.foldLocator?.call(window, padding);
    final bool covers = _detailCovers(context);
    // Decided before the screens are built: it is part of what they are told.
    final _SystemColumn? column = _systemColumn(
      window,
      padding,
      placement,
      system,
      covers: covers,
    );
    final MasterDetailConfig? md =
        shellConfig.branches[state.activeBranch].masterDetail;
    final int depth = state.active.entries.length;
    final _Columns columns = (
      now: column,
      afterBack: depth <= 1
          ? column
          : _systemColumn(
              window,
              padding,
              placement,
              system,
              covers: covers,
              detailOpen: md != null && depth > 2,
            ),
    );
    // Built once and only placed below, so the per-frame rebuilds of a drag,
    // the detail reveal and the immersive slide leave the screens alone.
    final _Stacks stacks = (
      masters: _mastersStack(column),
      details: _detailsStack(column),
      placeholder: _detailPlaceholder(),
    );
    final Widget layout = placement.isRail
        ? _buildRail(
            context,
            stacks,
            window: window.width,
            padding: padding,
            placement: placement,
            system: system,
            foldHint: foldHint,
            covers: covers,
            railInColumn: column != null && placement == column.edge,
            columns: columns,
          )
        : _buildBar(
            context,
            stacks,
            window: window.width,
            padding: padding,
            statusRow: _statusRow(
              Theme.of(context).platform,
              window,
              padding,
              system,
            ),
            foldHint: foldHint,
            covers: covers,
          );
    // A column without the rail in it, the panes underneath: the shell draws
    // the toolbar over them. Always a `Stack`, so the layout under it is not
    // remounted as the column comes and goes; and there whenever the system
    // has a column, empty while the rail is in it, so a toolbar going with a
    // closing detail still has somewhere to fade out.
    final Rect? bare = column == null
        ? null
        : _bareColumn(context, window, padding, column.edge, system);
    final ChromePlacement? swipeSide = _columnSwipeSide(
      context,
      placement,
      padding,
      column,
    );
    final PaneSlot? swipePane = swipeSide == null ? null : column!.slot;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        layout,
        if (bare != null)
          Positioned.fromRect(
            key: bareColumnKey,
            rect: bare,
            child: _bareToolbar(context, columns, bare.height),
          ),
        // Last, so a finger in the column reaches it whatever is drawn there.
        if (swipeSide != null && swipePane != null)
          Positioned.fill(
            key: columnBackGestureKey,
            child: ColumnBackGesture(
              side: swipeSide,
              inset: swipeSide == ChromePlacement.left
                  ? padding.left
                  : padding.right,
              route: () {
                final BranchNavigatorKeys keys = branchKeys[swipePane.branch];
                final Route<Object?>? top = columnTransitions.topOf(
                  swipePane.detail ? keys.detail : keys.master,
                );
                return top is ModalRoute<Object?> ? top : null;
              },
            ),
          ),
      ],
    );
  }

  /// The side of the window a back swipe in the system's column starts at,
  /// or `null` where the screen's own swipe is enough.
  ///
  /// Only on iOS, over a single pane with the rail's side the column's, and
  /// with the column at the leading edge: there the pane stands beside the
  /// column, whether the rail is in it or a covering detail took the rail
  /// out, and the edge the finger starts at is the column's, not the
  /// screen's. With the column at the trailing edge the screen's own edge is
  /// the window's, as it was; with two panes nothing changes either. And
  /// only while the pane against the column has somewhere to go back to, so
  /// a tab's root has no strip. The column is the system's, its inset on
  /// that side: a rail the trait puts on an edge without one, as in Split
  /// View on the left half, is only the rail, and the screen keeps its own
  /// swipe there as before. The swipe goes to the top route of that
  /// pane, the column's slot: the active branch's, the only one in view.
  ChromePlacement? _columnSwipeSide(
    BuildContext context,
    ChromePlacement placement,
    EdgeInsets padding,
    _SystemColumn? column,
  ) {
    if (!chrome ||
        column == null ||
        (column.edge == ChromePlacement.left ? padding.left : padding.right) <
            kVerticalBarInset ||
        !column.onePane ||
        column.slot == null ||
        placement != column.edge ||
        state.active.entries.length <= 1 ||
        Theme.of(context).platform != TargetPlatform.iOS) {
      return null;
    }
    final ChromePlacement leading = switch (Directionality.of(context)) {
      TextDirection.ltr => ChromePlacement.left,
      TextDirection.rtl => ChromePlacement.right,
    };
    return column.edge == leading ? leading : null;
  }

  /// The side with a one-sided inset of [kVerticalBarInset]: the system's
  /// own vertical bar, as [defaultChromeLayout] reads it.
  static ChromePlacement? _insetSide(EdgeInsets padding) {
    if (padding.left >= kVerticalBarInset &&
        padding.right < kVerticalBarInset) {
      return ChromePlacement.left;
    }
    if (padding.right >= kVerticalBarInset &&
        padding.left < kVerticalBarInset) {
      return ChromePlacement.right;
    }
    return null;
  }

  /// Whether an open detail over a single pane covers the chrome:
  /// [AdaptiveShellConfig.detailChrome], with [DetailChrome.kept] honoured
  /// only on an Apple platform, as the theme names it.
  bool _detailCovers(BuildContext context) =>
      shellConfig.detailChrome == DetailChrome.covered ||
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => false,
        _ => true,
      };

  /// Where the system's vertical column is, whether the rail is in it, and
  /// which pane's toolbar stands there.
  ///
  /// The column is the side the system names, or the side of its one-sided
  /// inset; it exists where the rail joined it or where the inset is wide
  /// enough to hold a toolbar of its own. The pane is the one against it,
  /// never a master beside its detail — Apple keeps the master's header
  /// horizontal: the single pane, or the detail of two while the column is on
  /// the detail's side and the detail is open.
  ///
  /// A detail that [covers] the rail over a single pane takes the rail out of
  /// the column: what is left is the inset, and the toolbar has it alone. The
  /// tabs stay where they were, under the detail.
  ///
  /// Two panes or one is the same arithmetic the layouts below do, from the
  /// same declared numbers.
  ///
  /// [detailOpen] is the state's unless given: the column a back gesture
  /// leads to is worked out before the detail it closes has gone.
  _SystemColumn? _systemColumn(
    Size window,
    EdgeInsets padding,
    ChromePlacement placement,
    SystemGeometry? system, {
    required bool covers,
    bool? detailOpen,
  }) {
    final ChromePlacement? edge = system?.verticalBar ?? _insetSide(padding);
    if (edge == null) {
      return null;
    }
    final MasterDetailConfig? md =
        shellConfig.branches[state.activeBranch].masterDetail;
    final PaneDecoration panes = shellConfig.panes;
    final bool twoPanes =
        md != null &&
        PaneMetrics.allowsTwoPanes(window: window.width, padding: padding) &&
        md.fits(
          PaneMetrics.paneAreaWidth(
            window: window.width,
            padding: padding,
            placement: placement,
            railWidth: shellConfig.railWidth,
            panes: panes,
            rail: shellConfig.rail,
            systemBarMetrics: shellConfig.systemBar,
            hasChrome: chrome,
          ),
          gap: panes.gap,
        );
    detailOpen ??= !_activeDetailEmpty;
    final bool inRail =
        chrome && placement == edge && !(covers && !twoPanes && detailOpen);
    final double inset = edge == ChromePlacement.left
        ? padding.left
        : padding.right;
    if (!inRail && inset < kVerticalBarInset) {
      return null;
    }
    final PaneSlot? slot = !twoPanes
        ? (branch: state.activeBranch, detail: md != null && detailOpen)
        : edge == ChromePlacement.right && detailOpen
        ? (branch: state.activeBranch, detail: true)
        : null;
    return (edge: edge, inRail: inRail, slot: slot, onePane: !twoPanes);
  }

  /// The system's column where the rail is not in it, in window coordinates:
  /// [SystemBarMetrics.statusColumnWidth] across its axis, from the status
  /// area to the home indicator.
  Rect _bareColumn(
    BuildContext context,
    Size window,
    EdgeInsets padding,
    ChromePlacement edge,
    SystemGeometry? system,
  ) {
    final SystemBarMetrics bar = shellConfig.systemBar;
    final (
      reserve: double reserve,
      end: SystemBarEnd end,
      shared: bool shared,
    ) = _systemBarReserve(
      window,
      padding,
      edge,
      system,
      _displaySize(context, window),
    );
    final double axis = edge == ChromePlacement.left
        ? bar.axisFromEdge
        : window.width - bar.axisFromEdge;
    // The same ends as the column with the tabs in it: the inset from the
    // status area or from the window's edge, the home indicator included.
    return Rect.fromLTRB(
      axis - bar.statusColumnWidth / 2,
      (shared && end == SystemBarEnd.top ? reserve : padding.top) +
          bar.columnInset,
      axis + bar.statusColumnWidth / 2,
      window.height -
          (shared && end == SystemBarEnd.bottom
              ? reserve + padding.bottom
              : 0) -
          bar.columnInset,
    );
  }

  /// What the system's column keeps free inside the rail card at its top
  /// and bottom: [SystemBarMetrics.columnInset] from the status area, or
  /// from the window's edge where the status area is not at that end.
  ///
  /// The card already keeps [reserve] at [end] ([_railSurface]); its top is
  /// [boxTop] below the window's, before the reserve. At the bottom it
  /// reaches into the home indicator's inset, which the column does not
  /// keep: Apple's last button stands 24 above the window's edge.
  ({double top, double bottom}) _columnEnds({
    required EdgeInsets padding,
    required double reserve,
    required SystemBarEnd end,
    required bool shared,
    required double boxTop,
  }) {
    final double inset = shellConfig.systemBar.columnInset;
    final double top = boxTop + (end == SystemBarEnd.top ? reserve : 0);
    final double fromBottom =
        shellConfig.rail.margin.bottom +
        (end == SystemBarEnd.bottom ? reserve : 0);
    final double statusTop = shared && end == SystemBarEnd.top
        ? top
        : padding.top;
    final double statusBottom = shared && end == SystemBarEnd.bottom
        ? reserve + padding.bottom
        : 0;
    return (
      top: math.max(0.0, statusTop + inset - top),
      bottom: math.max(0.0, statusBottom + inset - fromBottom),
    );
  }

  /// What the system's column shows: [columns]' `now`, or, while a back
  /// gesture is taking the active pane's top screen away, `afterBack`, with
  /// that pane's toolbar the one of the screen the gesture leads back to.
  /// The column follows the finger to it ([ColumnTransitions]).
  ({_SystemColumn? column, PaneToolbarEntry? Function(PaneSlot slot) entry})
  _columnShown(_Columns columns) {
    final BranchStack<R> stack = state.active;
    final ColumnGesture? gesture = stack.entries.length <= 1
        ? null
        : columnTransitions.gestureOn(stack.top.pageKey);
    if (gesture == null) {
      return (
        column: columns.now,
        entry: (PaneSlot slot) => paneToolbars[slot],
      );
    }
    final PaneSlot top = (
      branch: state.activeBranch,
      detail: shellConfig.branches[state.activeBranch].masterDetail != null,
    );
    return (
      column: columns.afterBack,
      entry: (PaneSlot slot) => slot == top
          ? paneToolbars.ofRoute(gesture.previous)
          : paneToolbars[slot],
    );
  }

  /// Rebuilds the column as screens register their toolbars and as a back
  /// gesture starts and ends.
  Listenable get _columnListenable =>
      Listenable.merge(<Listenable>[paneToolbars, columnTransitions]);

  /// The toolbar of the screen in a column of its own, [height] tall: what
  /// does not fit goes behind the menu at its end. Empty while the rail is in
  /// the column.
  Widget _bareToolbar(BuildContext context, _Columns columns, double height) {
    return ListenableBuilder(
      listenable: _columnListenable,
      builder: (BuildContext _, Widget? _) {
        final (
          column: _SystemColumn? column,
          entry: PaneToolbarEntry? Function(PaneSlot) entryOf,
        ) = _columnShown(
          columns,
        );
        final bool bare = column != null && !column.inRail;
        final PaneSlot? slot = bare ? column.slot : null;
        final PaneToolbarEntry? entry = slot == null ? null : entryOf(slot);
        final List<PaneToolbarSlot> items =
            entry?.vertical ?? const <PaneToolbarSlot>[];
        return Align(
          alignment: Alignment.topCenter,
          child: _toolbarBlock(
            context,
            entry,
            items,
            fitVerticalToolbar(items, room: height),
            marked: bare,
          ),
        );
      },
    );
  }

  /// The items [plan] shows, top to bottom, [kPaneToolbarItemGap] apart
  /// within a group and [kPaneToolbarGroupGap] between groups, and the
  /// toolbar's menu after them. Changes with the screen's route transition
  /// ([_ColumnSwitch]); [marked] puts [paneToolbarKey] on it.
  Widget _toolbarBlock(
    BuildContext context,
    PaneToolbarEntry? entry,
    List<PaneToolbarSlot> items,
    ({List<int> shown, List<int> hidden, bool menu}) plan, {
    required bool marked,
  }) {
    final List<Widget> children = <Widget>[];
    int? last;
    void add(int group, Widget child) {
      if (last != null) {
        children.add(
          SizedBox(
            height: group == last ? kPaneToolbarItemGap : kPaneToolbarGroupGap,
          ),
        );
      }
      last = group;
      children.add(
        SizedBox(
          height: kPaneToolbarItemExtent,
          child: Center(child: child),
        ),
      );
    }

    for (final int i in plan.shown) {
      final PaneToolbarSlot e = items[i];
      add(
        e.group,
        paneToolbarButton(
          e.item,
          prominent: e.group == 0 && !identical(e.item, entry?.navigation),
        ),
      );
    }
    if (plan.menu) {
      add(
        kPaneToolbarMenuGroup,
        _toolbarMenu(context, <PaneToolbarItem>[
          for (final int i in plan.hidden) items[i].item,
        ]),
      );
    }
    return _ColumnSwitch(
      owner: entry?.owner,
      marker: marked ? paneToolbarKey : null,
      branch: state.activeBranch,
      transitions: columnTransitions,
      duration: entry?.duration ?? kDefaultImmersiveDuration,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  /// The toolbar's menu: the items its zone could not hold. Only the
  /// toolbar's — the tabs have a More button of their own.
  Widget _toolbarMenu(BuildContext context, List<PaneToolbarItem> items) {
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final PaneToolbarItem item in items)
          MenuItemButton(
            leadingIcon: item.icon == null ? null : Icon(item.icon),
            onPressed: item.onPressed,
            child: Text(item.label),
          ),
      ],
      builder: (BuildContext context, MenuController c, Widget? _) =>
          IconButton(
            key: paneToolbarMenuKey,
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            icon: const Icon(Icons.more_horiz),
            onPressed: () => c.isOpen ? c.close() : c.open(),
          ),
    );
  }

  /// How close to a window edge a reported status area has to be to count as
  /// lying against it.
  static const double _edgeTolerance = 1;

  /// [SystemGeometry.statusArea], if it lies against [side] of the window —
  /// the edge the rail is on, or the top for a row — and the config follows
  /// it. A camera that stands clear of the edge is not one.
  Rect? _statusArea(SystemGeometry? system, Size window, AxisDirection side) {
    final Rect? area = system?.statusArea;
    if (area == null || !shellConfig.systemBar.followsSystemGeometry) {
      return null;
    }
    final bool against = switch (side) {
      AxisDirection.left => area.left <= _edgeTolerance,
      AxisDirection.right => area.right >= window.width - _edgeTolerance,
      AxisDirection.up => area.top <= _edgeTolerance,
      AxisDirection.down => area.bottom >= window.height - _edgeTolerance,
    };
    return against ? area : null;
  }

  /// The display the window is on, in logical pixels: what tells iPhone
  /// Duo's outer display from a Split View window on the inner one, which is
  /// narrower still. The window itself where the platform reports no display.
  static Size _displaySize(BuildContext context, Size window) {
    final Display? display = View.maybeOf(context)?.display;
    if (display == null || display.size.isEmpty) {
      return window;
    }
    return display.size / display.devicePixelRatio;
  }

  /// The top inset for lifted headers and where the glyphs start across the
  /// window; `null` where headers are not lifted.
  ///
  /// A phone in portrait is narrower than the breakpoint, with its glyphs on
  /// both sides of the cutout. iOS only: Android puts the clock at the left
  /// end of the row, where the master's header would go.
  ({double top, double start})? _statusRow(
    TargetPlatform platform,
    Size window,
    EdgeInsets padding,
    SystemGeometry? system,
  ) {
    if (!shellConfig.liftHeadersIntoStatusRow ||
        platform != TargetPlatform.iOS ||
        padding.top < kPhoneStatusBarInset ||
        padding.left >= kVerticalBarInset ||
        padding.right >= kVerticalBarInset ||
        window.width > window.height ||
        window.width - padding.horizontal < kCompactWidthBreakpoint) {
      return null;
    }
    final SystemBarMetrics bar = shellConfig.systemBar;
    final Rect? area = _statusArea(system, window, AxisDirection.up);
    return (
      top: math.min(padding.top, bar.statusRowTop(kToolbarHeight)),
      start: area?.left ?? window.width - bar.statusRowTrailing,
    );
  }

  /// How much of a pane from [left] to [right] the glyphs from [start] cover.
  /// [end] is as far as any pane reaches, so a pane off screen is not covered.
  static double _statusRowOverlap(
    double left,
    double right, {
    required double start,
    required double end,
  }) => math.max(0.0, math.min(right, end) - math.max(left, start));

  /// Always in the tree, lifted or not, so turning the device keeps the
  /// branch navigators' state.
  Widget _statusRowPane({
    required double? top,
    required double reserve,
    required Widget child,
  }) => StatusRowScope(
    trailingReserve: reserve,
    child: Builder(
      builder: (BuildContext inner) =>
          _paneInsets(inner, top: top, child: child),
    ),
  );

  /// bar: the chrome is a horizontal strip at the bottom.
  ///
  /// Two panes still fit above it when the window is wide enough — an iPhone
  /// Duo's inner display in portrait is 669 points across and Apple asks for
  /// horizontal bars there — so the pane count is decided here the same way it
  /// is under the rail, from [MasterDetailConfig.fits].
  ///
  /// The top inset stays with the screens, unlike the rail layout: on this
  /// side of the threshold every screen still has an `AppBar` to reserve it.
  /// With two panes the shell only takes the card margin off it first, so what
  /// an `AppBar` reserves inside a card is what is left over the card.
  Widget _buildBar(
    BuildContext context,
    _Stacks stacks, {
    required double window,
    required EdgeInsets padding,
    ({double top, double start})? statusRow,
    Rect? foldHint,
    bool covers = true,
  }) {
    final MasterDetailConfig? md =
        PaneMetrics.allowsTwoPanes(window: window, padding: padding)
        ? shellConfig.branches[state.activeBranch].masterDetail
        : null;
    final PaneDecoration panes = shellConfig.panes;
    final double paneArea = PaneMetrics.paneAreaWidth(
      window: window,
      padding: padding,
      placement: ChromePlacement.bottom,
      railWidth: shellConfig.railWidth,
      panes: panes,
    );
    if (md != null && md.fits(paneArea, gap: panes.gap)) {
      final PaneUnderlap underlap = PaneMetrics.underlap(
        padding: padding,
        panes: panes,
        placement: ChromePlacement.bottom,
      );
      return Scaffold(
        key: shellConfig.scaffoldKey,
        drawer: _drawer(context, rail: false),
        onDrawerChanged: onDrawerChanged,
        resizeToAvoidBottomInset: false,
        extendBody: shellConfig.extendBodyBehindBar,
        body: _onCanvas(
          context,
          panes: panes,
          // The cards bleed up under the status bar, the way they bleed under
          // an inset at their side: only the margin is held back from the
          // window's top edge, and what is left of the inset is handed to the
          // screens inside, where each `AppBar` reserves it. So a title lands
          // on the same line as it would with one pane, and the strip under
          // the clock is the card's own background rather than bare canvas.
          //
          // Reserving the whole inset out here instead would be simpler and
          // wrong on the display this layout exists for: iPhone Duo's inner
          // screen in portrait has 82 points of top inset, and a card starting
          // below it *plus* the margin leaves a band that deep unused.
          //
          // Read under the `Scaffold`, which has taken the bar's bottom inset
          // off its body; the shell's context would hand it back to the panes.
          child: Builder(
            builder: (BuildContext body) => _paneInsets(
              body,
              top: math.max(
                0.0,
                (statusRow?.top ?? padding.top) - panes.margin.top,
              ),
              child: Builder(
                builder: (BuildContext inner) => _inPaneArea(
                  panes: panes,
                  child: _twoPanes(
                    inner,
                    stacks,
                    md,
                    paneArea,
                    underlap,
                    underlap.left + panes.margin.left,
                    foldHint,
                    // In the panes' `Stack`, which spans the margins.
                    statusRow: statusRow == null
                        ? null
                        : (
                            start: statusRow.start - panes.margin.left,
                            end: window - panes.margin.horizontal,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _barWidget(context),
      );
    }
    return _buildStack(
      context,
      stacks,
      window: window,
      statusRow: statusRow,
      covers: covers,
    );
  }

  /// bar, one pane: master in the body and the detail overlaying the bar —
  /// or, unless it [covers] the bar, the detail over the master in the body,
  /// ending at the bar's top edge. The `Scaffold` has taken the bar's inset
  /// off the body, so the detail does not clear it again.
  ///
  /// The drawer lives on this `Scaffold`, so it is reachable from every screen.
  /// One caveat: the covering detail layer is a sibling above it, so a
  /// non-empty detail covers an open drawer. In the root states, where a
  /// drawer is opened, the detail is empty and transparent.
  Widget _buildStack(
    BuildContext context,
    _Stacks stacks, {
    required double window,
    ({double top, double start})? statusRow,
    required bool covers,
  }) {
    final double reserve = statusRow == null
        ? 0
        : _statusRowOverlap(0, window, start: statusRow.start, end: window);
    // An empty detail is transparent and lets taps through to the bar and
    // the master.
    final Widget detail = IgnorePointer(
      ignoring: _activeDetailEmpty,
      child: _statusRowPane(
        top: statusRow?.top,
        reserve: reserve,
        child: _detailsIn(stacks, inPane: false),
      ),
    );
    return Stack(
      children: <Widget>[
        Scaffold(
          key: shellConfig.scaffoldKey,
          drawer: _drawer(context, rail: false),
          onDrawerChanged: onDrawerChanged,
          resizeToAvoidBottomInset: false, // see the rail `Scaffold` below
          extendBody: shellConfig.extendBodyBehindBar,
          // Inside the body, so the drawer keeps the whole inset.
          body: covers
              ? _statusRowPane(
                  top: statusRow?.top,
                  reserve: reserve,
                  child: stacks.masters,
                )
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _statusRowPane(
                      top: statusRow?.top,
                      reserve: reserve,
                      child: stacks.masters,
                    ),
                    detail,
                  ],
                ),
          bottomNavigationBar: _barWidget(context),
        ),
        if (covers) Positioned.fill(child: detail),
      ],
    );
  }

  /// rail: one pane or two, decided from the width of the content area.
  ///
  /// The decision is made here, at build time. It used to belong to a
  /// `LayoutBuilder`, and crossing the threshold then moved the branch
  /// navigators by `GlobalKey` from inside the layout callback — which dropped
  /// the frame as soon as a deferred overlay child reactivated.
  ///
  /// The rail and the panes extend under the status bar. The rail reserves
  /// the top inset inside its own surface; each pane passes what is left after
  /// its margin to the screen, where the `AppBar` reserves it. The horizontal
  /// insets come off the pane area instead, because a pane only bleeds under
  /// them; see [PaneUnderlap].
  ///
  /// With one pane, a detail that [covers] the chrome is not in the pane but
  /// over the whole window, rail included, as it is over the bar: the screen
  /// takes the window's insets, which keep its content out of the system's
  /// column on iPhone Duo. The layer is there whether the detail is open or
  /// not, so the detail's own transition is what brings the rail back.
  Widget _buildRail(
    BuildContext context,
    _Stacks stacks, {
    required double window,
    required EdgeInsets padding,
    required ChromePlacement placement,
    SystemGeometry? system,
    Rect? foldHint,
    bool covers = true,
    bool railInColumn = false,
    _Columns columns = (now: null, afterBack: null),
  }) {
    final PaneDecoration panes = shellConfig.panes;
    final RailDecoration rail = shellConfig.rail;
    final Size size = MediaQuery.sizeOf(context);
    // The reserve is needed before the rail is built: it is height the
    // destinations cannot use, so it decides how many of them fit.
    final (
      reserve: double reserveIfShown,
      end: SystemBarEnd reserveEnd,
      shared: bool sharesColumn,
    ) = _systemBarReserve(
      size,
      padding,
      placement,
      system,
      _displaySize(context, size),
    );
    // In a column it shares with the system's bar the rail goes below the
    // clock, as Apple stacks a column: status bar, toolbar, tab bar.
    final RailAlignment alignment =
        shellConfig.railAlignment ??
        (sharesColumn ? RailAlignment.bottom : RailAlignment.top);
    // Where the column shares the window's top, inset or not, with nothing
    // of the system's at that end, what comes first in it starts clear of the
    // rounded corner — see [SystemBarMetrics.cornerClearance].
    final double insetTop = math.max(
      0.0,
      padding.top - shellConfig.rail.margin.top,
    );
    // The system's column keeps its own ends, [SystemBarMetrics.columnInset]
    // from the status area or the window's edge.
    final bool zones = railInColumn && shellConfig.railBuilder == null;
    final double railTop =
        !zones && sharesColumn && reserveEnd == SystemBarEnd.bottom
        ? math.max(insetTop, shellConfig.systemBar.cornerClearance)
        : insetTop;
    // The divider after the rail is part of the layout arithmetic, so the
    // package draws it and a custom builder must not.
    final Widget? railWidget = _railWidget(
      context,
      // The count's column already leaves the top inset out; whatever the
      // corner adds to it is reserved as well.
      reserve: reserveIfShown + railTop - insetTop,
      alignment: alignment,
      labels: sharesColumn || railInColumn
          ? shellConfig.railLabelsInColumn
          : NavigationRailLabelType.all,
      column: railInColumn,
      columns: columns,
      ends: _columnEnds(
        padding: padding,
        reserve: reserveIfShown,
        end: reserveEnd,
        shared: sharesColumn,
        boxTop: shellConfig.rail.margin.top + railTop,
      ),
    );
    final double paneArea = PaneMetrics.paneAreaWidth(
      window: window,
      padding: padding,
      placement: placement,
      railWidth: shellConfig.railWidth,
      panes: panes,
      rail: rail,
      systemBarMetrics: shellConfig.systemBar,
      hasChrome: railWidget != null,
    );
    // Tied to the presence of the rail, not to the immersive progress: the
    // layout class is frozen while the rail slides out, and so is what the
    // panes are allowed to count on.
    final PaneUnderlap underlap = PaneMetrics.underlap(
      padding: padding,
      panes: panes,
      placement: placement,
      hasChrome: railWidget != null,
    );
    // What the rail takes while shown. Immersive mode animates this to zero,
    // but `paneArea` above stays computed from it — the layout class is frozen,
    // see `_railRow`.
    // The rail joins the system's own column where there is one — that is
    // where the camera and the status bar are, and the controls line up with
    // them — so the two do not add up.
    final double systemBar = railWidget == null
        ? 0
        : PaneMetrics.systemBarInset(padding: padding, placement: placement);
    // Held off the edge so the destinations land on the line the system
    // centres its own glyphs on; zero where there is no system bar to match.
    final double edgeGap = systemBar > 0
        ? shellConfig.systemBar.edgeGap(shellConfig.railWidth)
        : 0;
    // Unlike the system's column, a cutout is not joined: the rail grows by
    // it.
    final double cutout = railWidget == null
        ? 0
        : PaneMetrics.railCutoutInset(padding: padding, placement: placement);
    final double railRegion = railWidget == null
        ? 0
        : PaneMetrics.railColumnWidth(
            railWidth: shellConfig.railWidth,
            systemBar: systemBar,
            edgeGap: edgeGap,
            cutout: cutout,
            rail: rail,
          );
    // A side bar or a custom layout can put a rail below the breakpoint.
    final MasterDetailConfig? md =
        PaneMetrics.allowsTwoPanes(window: window, padding: padding)
        ? shellConfig.branches[state.activeBranch].masterDetail
        : null;
    // The same threshold `_railRow` lays the panes out by.
    final bool overRail =
        covers && !(md != null && md.fits(paneArea, gap: panes.gap));
    return Stack(
      children: <Widget>[
        _railScaffold(
          context,
          stacks,
          railWidget: railWidget,
          rail: rail,
          panes: panes,
          md: md,
          window: window,
          railRegion: railRegion,
          paneArea: paneArea,
          underlap: underlap,
          placement: placement,
          systemBar: systemBar,
          edgeGap: edgeGap,
          cutout: cutout,
          reserve: railWidget == null ? 0 : reserveIfShown,
          reserveEnd: reserveEnd,
          railTop: railWidget == null ? 0 : railTop,
          padding: padding,
          foldHint: foldHint,
          detailInPane: !overRail,
        ),
        if (overRail)
          Positioned.fill(
            child: _besideColumn(
              // Over a rail of its own the detail takes the whole window. The
              // system's column stays: the detail stops at it, as a pane
              // does, and only the tabs go.
              side: railInColumn && railWidget != null ? placement : null,
              region: railRegion,
              child: IgnorePointer(
                // Empty, it is transparent: the rail and the master take the
                // taps.
                ignoring: _activeDetailEmpty,
                child: _detailsIn(stacks, inPane: false),
              ),
            ),
          ),
      ],
    );
  }

  /// A covering detail laid out beside the system's column on [side], [region]
  /// wide, the rail's column, as the panes are; `null` for the whole window.
  ///
  /// The detail gets the padding a pane gets, none on the column's side, and
  /// is clipped there, so a swipe back takes it under the column rather than
  /// across it. In immersive mode the column's width follows the rail's, with
  /// the same tween as `_immersiveRow`; the padding, as there, goes with the
  /// rail being there, not with the progress. Always the same widgets, so
  /// the detail navigator is not moved as the column comes and goes.
  Widget _besideColumn({
    required ChromePlacement? side,
    required double region,
    required Widget child,
  }) {
    final bool onLeft = side == ChromePlacement.left;
    final bool onRight = side == ChromePlacement.right;
    Widget at(double progress) => Padding(
      padding: EdgeInsets.only(
        left: onLeft ? region * progress : 0,
        right: onRight ? region * progress : 0,
      ),
      child: Builder(
        builder: (BuildContext context) => ClipRect(
          clipBehavior: side == null ? Clip.none : Clip.hardEdge,
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: onLeft,
            removeRight: onRight,
            child: child,
          ),
        ),
      ),
    );
    final ValueListenable<bool>? immersive = this.immersive;
    if (immersive == null) {
      return at(1);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: immersive,
      builder: (BuildContext context, bool engaged, Widget? _) =>
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: engaged ? 0 : 1),
            duration: shellConfig.immersiveDuration,
            curve: Curves.easeInOut,
            builder: (BuildContext context, double progress, Widget? _) =>
                at(progress),
          ),
    );
  }

  Widget _railScaffold(
    BuildContext context,
    _Stacks stacks, {
    required Widget? railWidget,
    required RailDecoration rail,
    required PaneDecoration panes,
    required MasterDetailConfig? md,
    required double window,
    required double railRegion,
    required double paneArea,
    required PaneUnderlap underlap,
    required ChromePlacement placement,
    required double systemBar,
    required double edgeGap,
    required double cutout,
    required double reserve,
    required SystemBarEnd reserveEnd,
    required double railTop,
    required EdgeInsets padding,
    required Rect? foldHint,
    required bool detailInPane,
  }) {
    return Scaffold(
      key: shellConfig.scaffoldKey,
      drawer: _drawer(context, rail: true),
      onDrawerChanged: onDrawerChanged,
      // The keyboard belongs to the focused pane, not to the shell. With the
      // default `true` its height was subtracted twice — once here and again by
      // the screen inside a pane, which receives the window's `viewInsets`
      // intact — and on an iPad in landscape that left the panes empty.
      resizeToAvoidBottomInset: false,
      body: _onCanvas(
        context,
        panes: panes,
        // Same as the two-pane bar layout: only the margins are kept clear of
        // the top edge, so the status bar shows the rail's colour over the
        // rail and each pane's colour over that pane.
        child: _paneInsets(
          context,
          top: math.max(0.0, padding.top - panes.margin.top),
          // Built below the adjusted inset, so the row's own `removePadding`
          // starts from it. The shell's context is above the `Scaffold` and
          // still has the full inset.
          child: Builder(
            builder: (BuildContext inner) => _immersiveRow(
              inner,
              stacks,
              railWidget: railWidget,
              rail: rail,
              panes: panes,
              md: md,
              window: window,
              railRegion: railRegion,
              paneArea: paneArea,
              underlap: underlap,
              placement: placement,
              systemBar: systemBar,
              edgeGap: edgeGap,
              cutout: cutout,
              reserve: reserve,
              reserveEnd: reserveEnd,
              railTop: railTop,
              foldHint: foldHint,
              detailInPane: detailInPane,
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps the row in the immersive listener, or skips it entirely when the
  /// mode is not configured.
  Widget _immersiveRow(
    BuildContext context,
    _Stacks stacks, {
    required Widget? railWidget,
    required RailDecoration rail,
    required PaneDecoration panes,
    required MasterDetailConfig? md,
    required double window,
    required double railRegion,
    required double paneArea,
    required PaneUnderlap underlap,
    required ChromePlacement placement,
    required double systemBar,
    required double edgeGap,
    required double cutout,
    required double reserve,
    required SystemBarEnd reserveEnd,
    required double railTop,
    required Rect? foldHint,
    required bool detailInPane,
  }) {
    final ValueListenable<bool>? immersive = this.immersive;
    if (immersive == null) {
      return _railRow(
        context,
        stacks,
        railWidget: railWidget,
        rail: rail,
        panes: panes,
        md: md,
        window: window,
        railRegion: railRegion,
        paneArea: paneArea,
        underlap: underlap,
        placement: placement,
        systemBar: systemBar,
        edgeGap: edgeGap,
        cutout: cutout,
        reserve: reserve,
        reserveEnd: reserveEnd,
        railTop: railTop,
        foldHint: foldHint,
        detailInPane: detailInPane,
        progress: 1,
        immersive: false,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: immersive,
      builder: (BuildContext context, bool engaged, Widget? _) =>
          // Animate the progress, recompute the widths from the live window
          // every frame. The tween's target does not depend on the width, so a
          // resize while in the mode does not lag behind.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: engaged ? 0 : 1),
            duration: shellConfig.immersiveDuration,
            curve: Curves.easeInOut,
            builder: (BuildContext context, double progress, Widget? _) =>
                _railRow(
                  context,
                  stacks,
                  railWidget: railWidget,
                  rail: rail,
                  panes: panes,
                  md: md,
                  window: window,
                  railRegion: railRegion,
                  paneArea: paneArea,
                  underlap: underlap,
                  placement: placement,
                  systemBar: systemBar,
                  edgeGap: edgeGap,
                  cutout: cutout,
                  reserve: reserve,
                  reserveEnd: reserveEnd,
                  railTop: railTop,
                  foldHint: foldHint,
                  detailInPane: detailInPane,
                  progress: progress,
                  immersive: true,
                ),
          ),
    );
  }

  /// The wide layout's row. The top inset in [context] is what the panes still
  /// have to clear; the rail clears [railTop] itself.
  ///
  /// [paneArea] is frozen, computed with the rail counted as shown, and it
  /// alone decides the layout class. [progress] only affects geometry. The
  /// rail strip is wide enough to carry a branch across the threshold, and
  /// doing that mid-animation would move the branch navigators by `GlobalKey`
  /// and put the app's own layout formula out of step.
  Widget _railRow(
    BuildContext context,
    _Stacks stacks, {
    required Widget? railWidget,
    required RailDecoration rail,
    required PaneDecoration panes,
    required MasterDetailConfig? md,
    required double window,
    required double railRegion,
    required double paneArea,
    required PaneUnderlap underlap,
    required ChromePlacement placement,
    required double systemBar,
    required double edgeGap,
    required double cutout,
    required double reserve,
    required SystemBarEnd reserveEnd,
    required double railTop,
    required Rect? foldHint,
    required bool detailInPane,
    required double progress,
    required bool immersive,
  }) {
    final double livePaneArea = immersive
        ? math.max(
            0.0,
            panes.paneAreaWidth(window - railRegion * progress) -
                underlap.horizontal,
          )
        : paneArea;
    final bool onLeft = placement == ChromePlacement.left;
    // Where the pane area starts in window coordinates — what a display
    // feature's bounds are measured in. Only a rail on the left moves it, and
    // while the immersive rail slides out it moves with it.
    final double origin =
        (onLeft ? railRegion * (immersive ? progress : 1) : 0) +
        panes.margin.left +
        underlap.left;
    // The region is fixed at the declared width. Panes are laid out with
    // absolute numbers, so what the rail occupies has to be right by
    // construction: a rail growing with the length of its labels would eat
    // into the panes and push the detail off the edge.
    // [edgeGap] holds the rail off the window edge so its destinations land on
    // the same line the system centres its glyphs on. Anything the column has
    // over that goes on the inner side instead, against the panes.
    final double slack = math.max(
      0.0,
      railRegion - rail.regionWidth(shellConfig.railWidth) - edgeGap - cutout,
    );
    // [edgeGap] sits between the rail and the window edge. A flush rail
    // paints it in its own colour, otherwise it shows up as a strip of
    // background. The slack is on the panes' side of the divider and is left
    // alone.
    final Color? columnColor = rail.isFlush ? _railColor(context, rail) : null;
    Widget spacer(double width) {
      final Widget box = SizedBox(width: width, height: double.infinity);
      return columnColor == null
          ? box
          : ColoredBox(color: columnColor, child: box);
    }

    // Shared, so the immersive layer slides out exactly the plain column.
    final List<Widget> railColumn = <Widget>[
      if (railWidget != null) ...<Widget>[
        if (onLeft && edgeGap > 0) spacer(edgeGap),
        if (!onLeft && slack > 0) SizedBox(width: slack),
        if (!onLeft && rail.dividerWidth > 0)
          VerticalDivider(width: rail.dividerWidth),
        _railCard(
          context,
          railWidget: railWidget,
          rail: rail,
          onLeft: onLeft,
          cutout: cutout,
          reserve: reserve,
          reserveEnd: reserveEnd,
          top: railTop,
        ),
        if (onLeft && rail.dividerWidth > 0)
          VerticalDivider(width: rail.dividerWidth),
        if (onLeft && slack > 0) SizedBox(width: slack),
        if (!onLeft && edgeGap > 0) spacer(edgeGap),
      ],
    ];
    final List<Widget> railRegionWidgets = railWidget != null && immersive
        ? <Widget>[
            _railRegion(
              region: railRegion,
              progress: progress,
              onLeft: onLeft,
              children: railColumn,
            ),
          ]
        : railColumn;
    final Widget content = Expanded(
      // The content area stops at the rail divider rather than the window
      // edge on the rail's side, and the rail has already handled that inset.
      // Tied to the presence of the rail rather than to the immersive
      // progress, or padding would appear halfway through the animation.
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: railWidget != null && onLeft,
        removeRight: railWidget != null && !onLeft,
        child: _inPaneArea(
          panes: panes,
          // Threshold from the frozen width, widths from the live one.
          child: md != null && md.fits(paneArea, gap: panes.gap)
              ? _twoPanes(
                  context,
                  stacks,
                  md,
                  livePaneArea,
                  underlap,
                  origin,
                  foldHint,
                )
              : _singlePanel(
                  context,
                  stacks,
                  underlap,
                  withDetail: detailInPane,
                ),
        ),
      ),
    );
    // Physical, like [ChromePlacement]: a right-to-left locale must not mirror.
    return Row(
      textDirection: TextDirection.ltr,
      children: onLeft
          ? <Widget>[...railRegionWidgets, content]
          : <Widget>[content, ...railRegionWidgets],
    );
  }

  /// The column is painted as one piece, including the reserve and the strip
  /// under the status bar.
  ///
  /// `NavigationRail` paints only as far down as it is laid out, so pushing it
  /// below the system bar would leave the top of the column showing the canvas
  /// — and the strip the clock sits in would not read as part of the rail.
  /// Resolved the way `NavigationRail` resolves its own background, so the
  /// default rail joins up seamlessly.
  ///
  /// [top] is the window's top inset minus the card's top margin.
  Widget _railSurface(
    BuildContext context, {
    required RailDecoration rail,
    required double reserve,
    required SystemBarEnd end,
    required double top,
    required Widget child,
    double cutout = 0,
    bool onLeft = true,
  }) {
    if (reserve <= 0 && top <= 0 && cutout <= 0) {
      return child;
    }
    return ColoredBox(
      color: _railColor(context, rail),
      child: Padding(
        padding: EdgeInsets.only(
          left: onLeft ? cutout : 0,
          right: onLeft ? 0 : cutout,
          top: end == SystemBarEnd.top ? top + reserve : top,
          bottom: end == SystemBarEnd.top ? 0 : reserve,
        ),
        child: child,
      ),
    );
  }

  /// Resolved the way `NavigationRail` resolves its own background.
  Color _railColor(BuildContext context, RailDecoration rail) =>
      rail.backgroundColor?.call(context) ??
      NavigationRailTheme.of(context).backgroundColor ??
      Theme.of(context).colorScheme.surface;

  /// [reserve] is kept free at [reserveEnd] for the system's own vertical
  /// bar, where the rail shares a column with one. It is inside the card, so it
  /// moves no geometry: only the destinations move away from that end.
  Widget _railCard(
    BuildContext context, {
    required Widget railWidget,
    required RailDecoration rail,
    required bool onLeft,
    double cutout = 0,
    double reserve = 0,
    SystemBarEnd reserveEnd = SystemBarEnd.top,
    double top = 0,
  }) {
    return SizedBox(
      // The margin goes outside, so `railWidth` stays the width of the widget.
      // A [cutout] goes inside the card, under its background.
      width: shellConfig.railWidth + cutout + rail.margin.horizontal,
      child: Padding(
        padding: rail.margin,
        child: _card(
          context,
          radius: rail.radius,
          shadow: rail.shadow,
          border: rail.border,
          // Material's `NavigationRail` carries a `SafeArea`, and in landscape
          // on a notched phone that inset is most of the declared width: the
          // region keeps its size while the destinations are squeezed into
          // what is left. On iPhone Duo that edge is the system's vertical bar,
          // which the rail joins; a cutout is reserved by `_railSurface`
          // instead, which paints under it. Either way the inset is not the
          // rail's business. The top inset is already reserved by
          // `_railSurface`, so it is removed here too.
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: onLeft,
            removeRight: !onLeft,
            removeTop: true,
            child: _railSurface(
              context,
              rail: rail,
              cutout: cutout,
              onLeft: onLeft,
              reserve: reserve,
              end: reserveEnd,
              top: top,
              child: railWidget,
            ),
          ),
        ),
      ),
    );
  }

  /// The rail is measured at full width and clipped by the shrinking region,
  /// pinned to its right edge, so it slides out whole. Squeezing it is not an
  /// option: its destinations are laid out into the declared width and would
  /// break at 40 px. The subtree stays mounted throughout.
  Widget _railRegion({
    required double region,
    required double progress,
    required bool onLeft,
    required List<Widget> children,
  }) {
    return SizedBox(
      key: railRegionKey,
      width: region * progress,
      child: ClipRect(
        child: OverflowBox(
          // Pinned by its inner edge, so it slides out towards its own side
          // of the window.
          alignment: onLeft ? Alignment.centerRight : Alignment.centerLeft,
          minWidth: region,
          maxWidth: region,
          child: Row(textDirection: TextDirection.ltr, children: children),
        ),
      ),
    );
  }

  Widget _onCanvas(
    BuildContext context, {
    required PaneDecoration panes,
    required Widget child,
  }) {
    final PaneCanvasColor? color = panes.canvasColor;
    if (color == null) {
      return child;
    }
    return ColoredBox(color: color(context), child: child);
  }

  Widget _inPaneArea({required PaneDecoration panes, required Widget child}) {
    if (panes.margin == EdgeInsets.zero) {
      return child;
    }
    return Padding(padding: panes.margin, child: child);
  }

  /// A floating card. Nothing appears unless it was configured, and no layer
  /// changes the geometry.
  ///
  /// The order matters: inside the `ClipRRect` a shadow is cut off with the
  /// corners, and in the background a border is covered by the opaque fill of
  /// the screen inside the card.
  Widget _card(
    BuildContext context, {
    required BorderRadius radius,
    required ShellCardShadow? shadow,
    required ShellCardBorder? border,
    required Widget child,
  }) {
    Widget card = _clip(radius, child);
    if (border != null) {
      card = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: border(context),
        ),
        child: card,
      );
    }
    if (shadow != null) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: shadow(context),
        ),
        child: card,
      );
    }
    return card;
  }

  Widget _clip(BorderRadius radius, Widget child) {
    if (radius == BorderRadius.zero) {
      return child;
    }
    return ClipRRect(borderRadius: radius, child: child);
  }

  Widget _paneCard(BuildContext context, Widget child) {
    final PaneDecoration panes = shellConfig.panes;
    return _card(
      context,
      radius: panes.radius,
      // No shadow on a pane: it is already outlined by its contents. The border
      // is shared with the rail.
      shadow: null,
      border: panes.border,
      child: child,
    );
  }

  /// Cuts a pane's padding down to what it actually reaches under.
  ///
  /// `MediaQuery.removePadding` is all or nothing, and with a
  /// [PaneDecoration.margin] neither answer is right: the card is already held
  /// away from the edge, so the screen inside it has less of the inset left to
  /// clear than the window reports. Shaped after `removePadding`, which also
  /// takes what it drops off `viewPadding`.
  ///
  /// An omitted side is left as the window reports it.
  Widget _paneInsets(
    BuildContext context, {
    double? left,
    double? right,
    double? top,
    required Widget child,
  }) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double dropLeft = left == null ? 0 : mq.padding.left - left;
    final double dropRight = right == null ? 0 : mq.padding.right - right;
    final double dropTop = top == null ? 0 : mq.padding.top - top;
    if (dropLeft == 0 && dropRight == 0 && dropTop == 0) {
      return child;
    }
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(
          left: left ?? mq.padding.left,
          right: right ?? mq.padding.right,
          top: top ?? mq.padding.top,
        ),
        viewPadding: mq.viewPadding.copyWith(
          left: math.max(0.0, mq.viewPadding.left - dropLeft),
          right: math.max(0.0, mq.viewPadding.right - dropRight),
          top: math.max(0.0, mq.viewPadding.top - dropTop),
        ),
      ),
      child: child,
    );
  }

  /// medium, and expanded with a collapsed empty detail — there the top layer
  /// is transparent and the master shows through at full width.
  ///
  /// Without [withDetail] the detail is over the whole window instead, see
  /// [_buildRail].
  Widget _singlePanel(
    BuildContext context,
    _Stacks stacks,
    PaneUnderlap underlap, {
    bool withDetail = true,
  }) {
    return _paneInsets(
      context,
      left: underlap.left,
      right: underlap.right,
      child: _paneCard(
        context,
        Stack(
          children: <Widget>[
            stacks.masters,
            if (withDetail)
              IgnorePointer(
                ignoring: _activeDetailEmpty,
                // Same presentation as compact, so the same platform
                // transition.
                child: _detailsIn(stacks, inPane: false),
              ),
          ],
        ),
      ),
    );
  }

  static const Duration detailRevealDuration = Duration(milliseconds: 240);

  /// [origin] is the pane area's left edge in window coordinates, which is
  /// what a display feature's bounds are measured in.
  Widget _twoPanes(
    BuildContext context,
    _Stacks stacks,
    MasterDetailConfig md,
    double width,
    PaneUnderlap underlap,
    double origin,
    Rect? foldHint, {
    ({double start, double end})? statusRow,
  }) {
    // The framework first, then a platform package's report through
    // [SystemGeometryScope]; the app's own answer only fills the silence.
    final PaneFold? fold = md.alignToFold
        ? FoldMetrics.paneFold(
                features: MediaQuery.displayFeaturesOf(context),
                origin: origin,
                paneArea: width,
              ) ??
              FoldMetrics.fromRects(
                folds:
                    SystemGeometryScope.maybeOf(context)?.folds ??
                    const <Rect>[],
                origin: origin,
                paneArea: width,
              ) ??
              FoldMetrics.fromBounds(
                bounds: foldHint,
                origin: origin,
                paneArea: width,
              )
        : null;
    final Size window = MediaQuery.sizeOf(context);
    final double? centre = md.alignToWindowCenter
        ? window.width / 2 - origin
        : null;
    final bool portrait = window.height > window.width;
    final PaneSplitController? split = paneSplit;
    if (split == null) {
      return _resizablePanes(
        context,
        stacks,
        md,
        width,
        underlap,
        fold,
        centre,
        portrait,
        null,
        statusRow,
      );
    }
    // Only this subtree rebuilds on a drag; the delegate knows nothing about
    // it.
    return ListenableBuilder(
      listenable: split,
      builder: (BuildContext context, Widget? _) => _resizablePanes(
        context,
        stacks,
        md,
        width,
        underlap,
        fold,
        centre,
        portrait,
        split,
        statusRow,
      ),
    );
  }

  /// master | detail, with the detail sliding in from beyond the right edge.
  ///
  /// What animates is the reveal progress, not the width: both endpoints are
  /// recomputed from the live [width] every frame, so a window resize lands in
  /// the same frame instead of trailing a quarter of a second behind. It also
  /// means the divider drag needs no special case — it moves the final width
  /// while the progress stays put.
  ///
  /// The detail is always at its final width and simply waits off screen, so
  /// its own layout constraints are never evaluated at a shrinking width.
  ///
  /// [width] is the *usable* pane area: the insets the panes merely bleed
  /// under are already gone from it, and so every width derived from it —
  /// including [MasterDetailConfig.detailMinWidth] and the drag limits — is a
  /// width the user actually sees. The panes are then laid out across the
  /// physical area, each one wider than its share by the inset on its own
  /// side, which is exactly what its screen insets away again.
  Widget _resizablePanes(
    BuildContext context,
    _Stacks stacks,
    MasterDetailConfig md,
    double width,
    PaneUnderlap underlap,
    PaneFold? fold,
    double? centre,
    bool portrait,
    PaneSplitController? split,
    ({double start, double end})? statusRow,
  ) {
    final PaneDecoration panes = shellConfig.panes;
    final Object branchId = shellConfig.branches[state.activeBranch].id;
    // A fold both panes clear takes the boundary: a pane straddling a crease
    // is bent across two planes, which no ratio or drag is worth. Otherwise
    // the width decides, as everywhere else.
    //
    // The panes meet on the hinge, the cards' gap split evenly around it, and
    // the rest of the crease is an inset each pane reaches under: the
    // backgrounds touch where the device bends, the content stays off it.
    final bool onFold =
        fold != null && md.fitsAround(fold, width, gap: panes.gap);
    final double gap = panes.gap;
    final double foldInset = onFold ? math.max(0.0, (fold.width - gap) / 2) : 0;
    final double masterWidth = onFold
        ? fold.centre - gap / 2
        : md.masterWidthFor(
            width,
            gap: gap,
            fraction: split?.fractionOf(branchId),
            centre: centre,
            portrait: portrait,
          );
    final bool collapsed = md.collapseWhenDetailEmpty && _activeDetailEmpty;
    // Physical: what the `Stack` below actually spans.
    final double area = width + underlap.horizontal;
    final double boundary = underlap.left + masterWidth;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: detailRevealDuration,
      curve: Curves.easeInOut,
      builder: (BuildContext context, double reveal, Widget? _) => _splitLayout(
        context,
        stacks,
        panes: panes,
        underlap: underlap,
        gap: gap,
        foldInset: foldInset,
        split: area + (boundary - area) * reveal,
        detailWidth: area - boundary - gap,
        collapsed: collapsed,
        statusRow: statusRow,
        // While the fold holds the boundary there is nothing to drag: the
        // hinge decided.
        handle: split == null || collapsed || onFold
            ? null
            : _splitHandle(
                md: md,
                panes: panes,
                split: split,
                branchId: branchId,
                available: width,
                centre: centre,
                portrait: portrait,
              ),
      ),
    );
  }

  Widget? _splitHandle({
    required MasterDetailConfig md,
    required PaneDecoration panes,
    required PaneSplitController split,
    required Object branchId,
    required double available,
    required double? centre,
    required bool portrait,
  }) {
    // Nothing to move: at the threshold width both panes are at their minimums.
    if (!md.isResizable(available, gap: panes.gap)) {
      return null;
    }
    // The delta is incremental, so the current width comes from the controller
    // at the time of the event rather than from the last rendered frame — a
    // frame does not necessarily carry one move. Clamping each step means
    // dragging past the limit builds up no debt.
    void resizeBy(double dx) {
      final double current = md.masterWidthFor(
        available,
        gap: panes.gap,
        fraction: split.fractionOf(branchId),
        centre: centre,
        portrait: portrait,
      );
      split.drag(
        branchId,
        md.clampMasterWidth(current + dx, available, gap: panes.gap) /
            available,
      );
    }

    return _PaneSplitHandle(
      color: panes.splitHandleColor,
      onStart: () => split.beginDrag(branchId),
      onUpdate: resizeBy,
      onEnd: split.endDrag,
    );
  }

  /// Master at [split] on the left, detail at its final [detailWidth] beyond
  /// the gap. While [split] is the full width the detail sits past the right
  /// edge and is clipped; that is where it slides in from.
  ///
  /// [foldInset] is what each pane keeps clear on the gap's side while a fold
  /// holds the boundary: the pane reaches the hinge, its screen insets this
  /// much away.
  Widget _splitLayout(
    BuildContext context,
    _Stacks stacks, {
    required PaneDecoration panes,
    required PaneUnderlap underlap,
    required double gap,
    required double foldInset,
    required double split,
    required double detailWidth,
    required bool collapsed,
    ({double start, double end})? statusRow,
    Widget? handle,
  }) {
    // From [split], so the reserve follows a drag and the sliding detail.
    double reserve(double left, double right) => statusRow == null
        ? 0
        : _statusRowOverlap(
            left,
            right,
            start: statusRow.start,
            end: statusRow.end,
          );
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: split,
          // The master's right edge is the gap, not the screen edge, so it does
          // not need the right inset — unless the detail is collapsed and it
          // spans the full width. On a fold that edge is the hinge, and the
          // crease is its inset.
          child: _paneInsets(
            context,
            left: underlap.left,
            right: collapsed ? underlap.right : foldInset,
            child: StatusRowScope(
              trailingReserve: reserve(0, split),
              child: _paneCard(context, stacks.masters),
            ),
          ),
        ),
        Positioned(
          left: split + gap,
          top: 0,
          bottom: 0,
          width: detailWidth,
          // Its left edge is the gap, or the hinge with the crease as its
          // inset; on the right it is the pane that bleeds under the inset,
          // and this is the screen that has to inset it away.
          child: _paneInsets(
            context,
            left: foldInset,
            right: underlap.right,
            child: StatusRowScope(
              trailingReserve: reserve(split + gap, split + gap + detailWidth),
              child: _paneCard(
                context,
                Stack(
                  children: <Widget>[
                    if (_activeDetailEmpty && !collapsed)
                      Positioned.fill(child: stacks.placeholder),
                    _detailsIn(stacks, inPane: true),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (handle != null)
          Positioned(
            // Centred on the gap and wider than it, so it reaches onto both
            // panes' edges. Last child, over both panes.
            left: split + gap / 2 - panes.splitHandleWidth / 2,
            top: 0,
            bottom: 0,
            width: panes.splitHandleWidth,
            child: handle,
          ),
      ],
    );
  }

  List<int> get _chromeBranches => <int>[
    for (int i = 0; i < shellConfig.branches.length; i++)
      if (shellConfig.branches[i].showsInChrome) i,
  ];

  /// `false` renders the rail without a highlight and renders no bar at all:
  /// `NavigationBar.selectedIndex` is not nullable, so Material has no "nothing
  /// selected" state. A hidden branch on compact is therefore full screen.
  bool get _activeInChrome =>
      shellConfig.branches[state.activeBranch].showsInChrome;

  Widget? _barWidget(BuildContext context) {
    if (!chrome || !_activeInChrome) {
      return null;
    }
    final ShellChromeBuilder? custom = shellConfig.barBuilder;
    if (custom == null) {
      return _bar(context);
    }
    return custom(context, state.activeBranch, onSelectBranch);
  }

  /// What the system's vertical bar keeps free in the rail's column, at which
  /// end, and whether the rail shares a column with it at all.
  ///
  /// Zero unless a one-sided vertical bar is on the rail's edge, or the
  /// platform reported a status area against it, so tablets, Android,
  /// desktop windows and notched iPhones never get past the first checks.
  ///
  /// A [SystemGeometry.statusArea] is the reserve itself: down to its bottom
  /// edge at the top of the window, up to its top edge at the bottom. Without
  /// one, [SystemBarMetrics] supplies the numbers, picked by the display the
  /// window is on. At the bottom the rail's own `SafeArea` already keeps the
  /// home indicator's inset, so only the rest of the reserve is added.
  ({double reserve, SystemBarEnd end, bool shared}) _systemBarReserve(
    Size window,
    EdgeInsets padding,
    ChromePlacement placement,
    SystemGeometry? system,
    Size display,
  ) {
    final SystemBarMetrics bar = shellConfig.systemBar;
    final Rect? area = switch (placement) {
      ChromePlacement.left => _statusArea(system, window, AxisDirection.left),
      ChromePlacement.right => _statusArea(system, window, AxisDirection.right),
      ChromePlacement.bottom => null,
    };
    if (area != null ||
        PaneMetrics.systemBarInset(padding: padding, placement: placement) >
            0) {
      final SystemBarEnd end = area == null
          ? bar.end(window, placement, display)
          : area.top <= window.height - area.bottom
          ? SystemBarEnd.top
          : SystemBarEnd.bottom;
      final double reserve = area == null
          ? bar.reserveFor(
              window,
              outerDisplay: display.shortestSide < kCompactDisplayShortSide,
            )
          : end == SystemBarEnd.top
          ? area.bottom
          : window.height - area.top;
      return switch (end) {
        SystemBarEnd.top => (reserve: reserve, end: end, shared: true),
        SystemBarEnd.bottom => (
          reserve: math.max(0.0, reserve - padding.bottom),
          end: end,
          shared: true,
        ),
      };
    }
    // A rail with no column to share and nothing at the top of the window
    // would start in the rounded corner: across the window from the system's
    // bar, or against the edge the system named with no bar there — the
    // left-hand Split View window on iPhone Duo's inner display.
    final ChromePlacement far = switch (placement) {
      ChromePlacement.left => ChromePlacement.right,
      ChromePlacement.right => ChromePlacement.left,
      ChromePlacement.bottom => ChromePlacement.bottom,
    };
    if (padding.top == 0 &&
        placement.isRail &&
        (PaneMetrics.systemBarInset(padding: padding, placement: far) > 0 ||
            system?.verticalBar == placement)) {
      return (
        reserve: bar.cornerClearance,
        end: SystemBarEnd.top,
        shared: false,
      );
    }
    return (reserve: 0.0, end: SystemBarEnd.top, shared: false);
  }

  /// [column] says the rail stands in the system's column, which it then
  /// shares with the toolbar of a screen, in two zones within [ends] — see
  /// [_columnZones] — while [columns] say the rail is in it
  /// ([_columnShown]). The column is rebuilt on its own as screens come and
  /// go.
  Widget? _railWidget(
    BuildContext context, {
    double reserve = 0,
    RailAlignment alignment = RailAlignment.top,
    NavigationRailLabelType labels = NavigationRailLabelType.all,
    bool column = false,
    _Columns columns = (now: null, afterBack: null),
    ({double top, double bottom}) ends = (top: 0, bottom: 0),
  }) {
    // Unlike the bar, the rail handles a hidden branch natively.
    if (!chrome) {
      return null;
    }
    final ShellChromeBuilder? custom = shellConfig.railBuilder;
    if (!column) {
      if (custom == null) {
        return _rail(
          context,
          reserve: reserve,
          alignment: alignment,
          labels: labels,
        );
      }
      return custom(context, state.activeBranch, onSelectBranch);
    }
    // The app's rail is the app's to fit: the toolbar goes above it whole.
    final Widget? customRail = custom?.call(
      context,
      state.activeBranch,
      onSelectBranch,
    );
    if (custom != null && customRail == null) {
      return null;
    }
    // [context] rather than the builder's own: the rail card has taken the
    // insets off the column, and the count needs the window's.
    final double height =
        _railColumn(context, reserve: reserve) +
        MediaQuery.paddingOf(context).bottom;
    return ListenableBuilder(
      listenable: _columnListenable,
      builder: (BuildContext _, Widget? _) {
        final (
          column: _SystemColumn? shown,
          entry: PaneToolbarEntry? Function(PaneSlot) entryOf,
        ) = _columnShown(
          columns,
        );
        // A detail covering the rail takes it out of the column: the tabs
        // go, under the detail, and the toolbar is the column's own.
        final bool inRail = shown?.inRail ?? true;
        final PaneSlot? toolbarSlot = inRail ? shown?.slot : null;
        final PaneToolbarEntry? entry = toolbarSlot == null
            ? null
            : entryOf(toolbarSlot);
        if (customRail != null) {
          final List<PaneToolbarSlot> items =
              entry?.vertical ?? const <PaneToolbarSlot>[];
          return SizedBox(
            key: paneToolbarKey,
            width: shellConfig.railWidth,
            child: Column(
              children: <Widget>[
                _toolbarBlock(
                  context,
                  entry,
                  items,
                  fitVerticalToolbar(items, room: double.infinity),
                  marked: false,
                ),
                Expanded(child: customRail),
              ],
            ),
          );
        }
        return _columnZones(
          context,
          entry: entry,
          toolbar: toolbarSlot != null,
          tabs: inRail,
          height: height,
          ends: ends,
          labels: labels,
        );
      },
    );
  }

  /// The places the tabs of the system's column have, the More button's
  /// included, in a column [inner] tall with tabs [extent] tall each — see
  /// [columnTabPlaces].
  int _columnTabPlaces(double inner, double extent, int tabs) =>
      shellConfig.railOverflow
      ? columnTabPlaces(inner: inner, extent: extent, tabs: tabs)
      : tabs;

  /// Height of one tab of the system's column: [kPaneToolbarItemExtent], and
  /// with [labels] the room for the tallest label below it — for every tab,
  /// [NavigationRailLabelType.selected] included, so a label coming and
  /// going with the selection moves nothing.
  ///
  /// Laid out with a `TextPainter`, like [_destinationExtents].
  double _columnTabExtent(
    BuildContext context,
    List<int> tabs,
    NavigationRailLabelType labels,
  ) {
    final double? declared = shellConfig.railDestinationExtent;
    if (declared != null) {
      return declared;
    }
    if (labels == NavigationRailLabelType.none) {
      return kPaneToolbarItemExtent;
    }
    final TextStyle? style = Theme.of(context).textTheme.labelMedium;
    double label = 0;
    for (final int b in tabs) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: shellConfig.branches[b].label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout(maxWidth: shellConfig.railWidth - kRailLabelInset);
      label = math.max(label, painter.height);
      painter.dispose();
    }
    return kPaneToolbarItemExtent + _columnLabelGap + label;
  }

  /// Between a tab's circle and its label.
  static const double _columnLabelGap = 2;

  /// The system's column as Apple stacks it: the toolbar's zone at the top,
  /// below the status area, and the tabs' zone at the bottom, [ends] keeping
  /// [SystemBarMetrics.columnInset] at both. The two do not share a menu.
  ///
  /// The tabs' places come from the column's height and [labels] alone
  /// ([_columnTabPlaces]): a toolbar the screen does not have keeps no room.
  /// When there are more tabs than places, the last place is the More
  /// button. The toolbar gets what the tabs leave, less
  /// [kPaneToolbarGroupGap], and puts what does not fit behind its own menu,
  /// the last thing in its zone. When that is too little even for the
  /// navigation button and the menu — or for the menu alone, with no
  /// navigation button — the tabs fold, on the spot, and the toolbar gets the
  /// rest, as Apple's tab bar does in a short column. With
  /// [VerticalBarCompression.tabsFirst] they fold as soon as the toolbar does
  /// not fit whole. See [_TabsFold] for what folded leaves.
  ///
  /// A screen change touches only the toolbar's zone: it cross-fades, and
  /// the tabs do not move unless they fold or unfold.
  Widget _columnZones(
    BuildContext context, {
    required PaneToolbarEntry? entry,
    required bool toolbar,
    required bool tabs,
    required double height,
    required ({double top, double bottom}) ends,
    required NavigationRailLabelType labels,
  }) {
    final List<int> branches = _chromeBranches;
    final double inner = height - ends.top - ends.bottom;
    final double extent = _columnTabExtent(context, branches, labels);
    final int places = _columnTabPlaces(inner, extent, branches.length);
    final List<int> hidden = places >= branches.length
        ? const <int>[]
        : _hiddenTabs(branches, branches.length - places + 1);
    final List<PaneToolbarSlot> items =
        entry?.vertical ?? const <PaneToolbarSlot>[];
    final VerticalBarCompression compression =
        entry?.compression ??
        shellConfig.branches[state.activeBranch].verticalCompression;
    // What the toolbar has beside the tabs' zone [n] places tall.
    double besideTabs(int n) =>
        inner - columnTabsExtent(n, extent) - kPaneToolbarGroupGap;
    final _TabsFold fold =
        !tabs ||
            items.isEmpty ||
            !_foldsTabs(
              items,
              room: besideTabs(places),
              compression: compression,
            )
        ? _TabsFold.none
        // Two places only where they are fewer than the full zone's.
        : _activeInChrome &&
              places > _TabsFold.two.places &&
              _leastToolbarExtent(items) <= besideTabs(_TabsFold.two.places)
        ? _TabsFold.two
        : _TabsFold.one;
    final Duration duration = entry?.duration ?? kDefaultImmersiveDuration;
    return ColoredBox(
      color: _railColor(context, shellConfig.rail),
      child: SizedBox(
        key: systemColumnKey,
        width: shellConfig.railWidth,
        height: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              key: const ValueKey<String>('toolbar'),
              top: ends.top,
              left: 0,
              right: 0,
              child: _toolbarBlock(
                context,
                entry,
                items,
                fitVerticalToolbar(
                  items,
                  room: besideTabs(
                    fold == _TabsFold.none ? places : fold.places,
                  ),
                ),
                marked: toolbar,
              ),
            ),
            Positioned(
              // Keyed, as the toolbar's zone is only while there is a slot:
              // the tabs stay the same element as screens come and go.
              key: const ValueKey<String>('tabs'),
              bottom: ends.bottom,
              left: 0,
              right: 0,
              child: _columnTabs(
                context,
                tabs: _chromeBranches,
                shown: tabs,
                hidden: hidden,
                places: places,
                extent: extent,
                labels: labels,
                fold: fold,
                duration: duration,
              ),
            ),
            if (fold != _TabsFold.none)
              Positioned(
                key: railCollapsedKey,
                bottom: ends.bottom,
                left: 0,
                right: 0,
                height: columnTabsExtent(fold.places, extent),
                child: const IgnorePointer(),
              ),
          ],
        ),
      ),
    );
  }

  /// Whether a toolbar of [items] folds the tabs, leaving it [room] beside
  /// them: when it does not fit whole and [compression] is
  /// [VerticalBarCompression.tabsFirst], or when even what stays of it with
  /// everything else in its menu does not fit.
  static bool _foldsTabs(
    List<PaneToolbarSlot> items, {
    required double room,
    required VerticalBarCompression compression,
  }) {
    final double whole = verticalToolbarExtent(<int>[
      for (final PaneToolbarSlot item in items) item.group,
    ]);
    if (whole <= room) {
      return false;
    }
    return compression == VerticalBarCompression.tabsFirst ||
        _leastToolbarExtent(items) > room;
  }

  /// The least a toolbar of [items] takes: the navigation button and the
  /// menu, or the menu alone.
  static double _leastToolbarExtent(List<PaneToolbarSlot> items) {
    final ({List<int> shown, List<int> hidden, bool menu}) least =
        fitVerticalToolbar(items, room: 0);
    return verticalToolbarExtent(<int>[
      for (final int i in least.shown) items[i].group,
      if (least.menu) kPaneToolbarMenuGroup,
    ]);
  }

  /// The [count] tabs that go behind the More button: the lowest
  /// [BranchConfig.visibilityPriority] first, and among equals the last. The
  /// selection plays no part — a selected tab behind the button lights the
  /// button up and leaves the places as they are.
  List<int> _hiddenTabs(List<int> tabs, int count) {
    final List<int> order = List<int>.generate(tabs.length, (int i) => i)
      ..sort((int a, int b) {
        final int byPriority = shellConfig.branches[tabs[a]].visibilityPriority
            .compareTo(shellConfig.branches[tabs[b]].visibilityPriority);
        return byPriority != 0 ? byPriority : b.compareTo(a);
      });
    final Set<int> hidden = <int>{...order.take(count)};
    return <int>[
      for (int i = 0; i < tabs.length; i++)
        if (hidden.contains(i)) tabs[i],
    ];
  }

  /// The tabs' zone, [places] tall: the tabs with a place, in order,
  /// [kPaneToolbarItemGap] apart as one group, and the More button in the
  /// last place when [hidden] is not empty. Folded ([fold]), the other tabs
  /// fade out, the selected one moves to its place above More and More stays
  /// where it is; unfolding is the same backwards. Not [shown], all of them
  /// fade out where they stand: a detail covers the rail.
  ///
  /// Each change goes with the route transition that brings it — see
  /// [_ColumnPlaces] — or, with a tab switch, over [duration].
  Widget _columnTabs(
    BuildContext context, {
    required List<int> tabs,
    required bool shown,
    required List<int> hidden,
    required int places,
    required double extent,
    required NavigationRailLabelType labels,
    required _TabsFold fold,
    required Duration duration,
  }) {
    final int active = state.activeBranch;
    final double step = extent + kPaneToolbarItemGap;
    final List<int> placed = <int>[
      for (final int b in tabs)
        if (!hidden.contains(b)) b,
    ];
    // Below the tabs with a place: More, when there is one.
    final int below = hidden.isEmpty ? 0 : 1;
    final bool more = hidden.isNotEmpty || fold != _TabsFold.none;
    return _ColumnPlaces(
      key: columnTabsKey,
      height: columnTabsExtent(places, extent),
      duration: duration,
      branch: active,
      transitions: columnTransitions,
      shown: shown,
      places: <_ColumnPlace>[
        for (final int b in tabs)
          if (fold == _TabsFold.two && b == active)
            _ColumnPlace(
              columnTabKey(b),
              bottom: step,
              shown: true,
              child: _columnTab(context, b, extent, labels),
            )
          else if (placed.contains(b))
            _ColumnPlace(
              columnTabKey(b),
              bottom: (placed.length - 1 - placed.indexOf(b) + below) * step,
              shown: fold == _TabsFold.none,
              child: _columnTab(context, b, extent, labels),
            )
          else
            // Behind More: out of view, until folded to two places selected.
            _ColumnPlace(
              columnTabKey(b),
              bottom: step,
              shown: false,
              child: _columnTab(context, b, extent, labels),
            ),
        _ColumnPlace(
          railOverflowKey,
          bottom: 0,
          shown: more,
          child: SizedBox(
            height: extent,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: kPaneToolbarItemExtent,
                child: Center(
                  child: switch (fold) {
                    _TabsFold.none => _moreTabs(
                      context,
                      hidden,
                      hidden.contains(active),
                    ),
                    _TabsFold.two => _moreTabs(context, tabs, false),
                    _TabsFold.one => _moreTabs(context, tabs, true),
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One tab: its icon in a circle, filled while selected, and its label
  /// below where [labels] shows it. Without a visible label the label is the
  /// tooltip, and with it the semantic label.
  Widget _columnTab(
    BuildContext context,
    int branch,
    double extent,
    NavigationRailLabelType labels,
  ) {
    final BranchConfig<R> config = shellConfig.branches[branch];
    final bool selected = branch == state.activeBranch;
    final bool labelled =
        labels == NavigationRailLabelType.all ||
        (labels == NavigationRailLabelType.selected && selected);
    final ColorScheme colors = Theme.of(context).colorScheme;
    void select() => onSelectBranch(branch);
    final Widget icon = Icon(config.icon);
    final String? tooltip = labelled ? null : config.label;
    return SizedBox(
      key: columnTabKey(branch),
      height: extent,
      child: Semantics(
        selected: selected,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: kPaneToolbarItemExtent,
              child: Center(
                child: selected
                    ? IconButton.filledTonal(
                        tooltip: tooltip,
                        icon: icon,
                        onPressed: select,
                      )
                    : IconButton(
                        tooltip: tooltip,
                        icon: icon,
                        onPressed: select,
                      ),
              ),
            ),
            if (labelled)
              Padding(
                padding: const EdgeInsets.only(top: _columnLabelGap),
                child: GestureDetector(
                  onTap: select,
                  child: Text(
                    config.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The More button: a menu of the [hidden] tabs — all of them while the
  /// tabs are folded — filled while [active]: the selected tab is one of
  /// them, or folded to More alone. Not an ellipsis, which is the toolbar's
  /// menu; the way `UITabBarController` on iPhone gives its last place to
  /// More. [AdaptiveShellConfig.railOverflowBuilder] replaces it.
  Widget _moreTabs(BuildContext context, List<int> hidden, bool active) {
    final ShellRailOverflowBuilder? custom = shellConfig.railOverflowBuilder;
    if (custom != null) {
      return custom(context, hidden, onSelectBranch, active);
    }
    final String tooltip = MaterialLocalizations.of(context).showMenuTooltip;
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final int b in hidden)
          MenuItemButton(
            leadingIcon: Icon(shellConfig.branches[b].icon),
            trailingIcon: b == state.activeBranch
                ? const Icon(Icons.check)
                : null,
            onPressed: () => onSelectBranch(b),
            child: Text(shellConfig.branches[b].label),
          ),
      ],
      builder: (BuildContext context, MenuController c, Widget? _) => active
          ? IconButton.filledTonal(
              key: railOverflowKey,
              tooltip: tooltip,
              icon: const Icon(Icons.apps),
              onPressed: () => c.isOpen ? c.close() : c.open(),
            )
          : IconButton(
              key: railOverflowKey,
              tooltip: tooltip,
              icon: const Icon(Icons.apps),
              onPressed: () => c.isOpen ? c.close() : c.open(),
            ),
    );
  }

  /// Height of each destination, from its own label, and what the selected
  /// one adds to its own where only that one shows a label.
  ///
  /// A label too wide for the rail takes a second line, and only that
  /// destination grows: Material lays each one out on its own, so a rail of
  /// "Home"s beside one "People" is 64s beside one 80 rather than all 80s.
  /// Counted the same way, or a single long label would push its neighbours
  /// into the menu with the column still half empty.
  ///
  /// With [labels] at [NavigationRailLabelType.selected] every destination
  /// is [kRailDestinationIconExtent], and [selected] is the most any of them
  /// gains with its label: which one is selected changes as you navigate,
  /// and the count should not.
  ///
  /// Laid out with a `TextPainter`, which is arithmetic over a declared width
  /// rather than a measurement of the tree.
  ({List<double> extents, double selected}) _destinationExtents(
    BuildContext context,
    List<int> items,
    NavigationRailLabelType labels,
  ) {
    final double? declared = shellConfig.railDestinationExtent;
    if (declared != null) {
      return (
        extents: List<double>.filled(items.length, declared),
        selected: 0.0,
      );
    }
    if (labels == NavigationRailLabelType.none) {
      return (
        extents: List<double>.filled(items.length, kRailDestinationIconExtent),
        selected: 0.0,
      );
    }
    // The same styles `NavigationRail` resolves for itself, or a themed rail
    // with a larger label would be counted at the wrong height. The selected
    // one can differ from the rest, and a destination is counted at the taller
    // of the two: which one it is changes as you navigate, and a rail whose
    // last destination comes and goes under the tap is worse than one that
    // keeps a line of slack.
    final NavigationRailThemeData railTheme = NavigationRailTheme.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final List<TextStyle?> styles = <TextStyle?>[
      railTheme.unselectedLabelTextStyle ?? text.labelMedium,
      railTheme.selectedLabelTextStyle ?? text.labelMedium,
    ];
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);
    final List<double> extents = <double>[];
    for (final int b in items) {
      double label = 0;
      for (final TextStyle? style in styles) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: shellConfig.branches[b].label, style: style),
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: shellConfig.railWidth - kRailLabelInset);
        label = math.max(label, painter.height);
        painter.dispose();
      }
      extents.add(kRailDestinationBase + label);
    }
    if (labels == NavigationRailLabelType.selected) {
      return (
        extents: List<double>.filled(items.length, kRailDestinationIconExtent),
        selected: extents.fold<double>(
          0,
          (double most, double e) =>
              math.max(most, e - kRailDestinationIconExtent),
        ),
      );
    }
    return (extents: extents, selected: 0.0);
  }

  /// How many of [extents] the rail's column can hold, in order.
  ///
  /// Arithmetic, not measurement: the shell knows the window, the inset it
  /// reserved, the rail card's margin, what the system bar keeps at its end
  /// and how tall every destination is, because every one of those is
  /// declared. A `LayoutBuilder` here is the one place `doc/design.md` warns
  /// about.
  List<int> _railRoom(
    BuildContext context, {
    required double reserve,
    required List<int> items,
    required List<double> extents,
    required bool withButton,
    required RailAlignment alignment,
    double selected = 0,
  }) {
    // With the destinations at the bottom the button is the rail's `leading`,
    // and `NavigationRail` puts a spacer after a `leading` as well as before.
    final double button = !withButton
        ? 0
        : kRailOverflowExtent +
              (_overflowLeads(alignment) ? kRailLeadingSpacer : 0);
    return _fitDestinations(
      items,
      extents,
      _railColumn(context, reserve: reserve) -
          kRailLeadingSpacer -
          selected -
          button,
    );
  }

  /// The height of the rail card's column below [reserve], what the rail's
  /// destinations, its spacer and anything above them share.
  ///
  /// The card is the window height minus its margins. Whatever part of the
  /// top inset the margin does not cover is reserved inside the card. The
  /// rail's own `SafeArea` takes the bottom inset.
  double _railColumn(BuildContext context, {required double reserve}) {
    final Size window = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final RailDecoration rail = shellConfig.rail;
    return window.height -
        math.max(0.0, padding.top - rail.margin.top) -
        rail.margin.vertical -
        reserve -
        padding.bottom;
  }

  /// The [items] whose [extents] fit [column], in their order. The lowest
  /// [BranchConfig.visibilityPriority] goes first, and among equals the last
  /// — with no priorities set, the destinations that fit from the top.
  List<int> _fitDestinations(
    List<int> items,
    List<double> extents,
    double column,
  ) {
    final List<int> order = List<int>.generate(items.length, (int i) => i)
      ..sort((int a, int b) {
        final int byPriority = shellConfig.branches[items[a]].visibilityPriority
            .compareTo(shellConfig.branches[items[b]].visibilityPriority);
        return byPriority != 0 ? byPriority : b.compareTo(a);
      });
    final Set<int> hidden = <int>{};
    double used = extents.fold<double>(0, (double sum, double e) => sum + e);
    for (final int i in order) {
      if (used <= column) {
        break;
      }
      hidden.add(i);
      used -= extents[i];
    }
    return <int>[
      for (int i = 0; i < items.length; i++)
        if (!hidden.contains(i)) items[i],
    ];
  }

  /// The destinations that do not fit, behind a menu at the end of the rail —
  /// or at its top, with [RailAlignment.bottom].
  ///
  /// The order never changes — items overflow from the end, and an active
  /// branch among them does not jump into view, because a destination that
  /// moves is harder to find than one that is simply elsewhere. The button
  /// carries the selection instead.
  ///
  /// The slot is [kRailOverflowExtent] tall whoever fills it. That height is
  /// one of the terms in the count above, so a taller button would overflow
  /// the column it is there to keep from overflowing.
  Widget _railOverflow(BuildContext context, List<int> hidden, bool active) {
    final ShellRailOverflowBuilder? custom = shellConfig.railOverflowBuilder;
    return SizedBox(
      height: kRailOverflowExtent,
      child: Center(
        child: custom == null
            ? _railOverflowButton(context, hidden, active)
            : custom(context, hidden, onSelectBranch, active),
      ),
    );
  }

  /// The package's own button: a menu of what the column could not hold,
  /// filled while the active branch is one of them.
  Widget _railOverflowButton(
    BuildContext context,
    List<int> hidden,
    bool active,
  ) {
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final int b in hidden)
          MenuItemButton(
            leadingIcon: Icon(shellConfig.branches[b].icon),
            onPressed: () => onSelectBranch(b),
            child: Text(shellConfig.branches[b].label),
          ),
      ],
      builder: (BuildContext context, MenuController c, Widget? _) => active
          ? IconButton.filledTonal(
              key: railOverflowKey,
              icon: const Icon(Icons.more_horiz),
              onPressed: () => c.isOpen ? c.close() : c.open(),
            )
          : IconButton(
              key: railOverflowKey,
              icon: const Icon(Icons.more_horiz),
              onPressed: () => c.isOpen ? c.close() : c.open(),
            ),
    );
  }

  /// Whether the overflow button is the rail's `leading` rather than its
  /// `trailing`: with the destinations at the bottom, the end within reach is
  /// theirs and the menu goes to the top.
  static bool _overflowLeads(RailAlignment alignment) =>
      alignment == RailAlignment.bottom;

  /// `NavigationRail.groupAlignment` for [alignment]. `null` at the top, so
  /// that a theme's own alignment still applies.
  static double? _groupAlignment(RailAlignment alignment) =>
      switch (alignment) {
        RailAlignment.top => null,
        RailAlignment.center => 0.0,
        RailAlignment.bottom => 1.0,
      };

  /// The rail with every destination behind the menu: the button alone, where
  /// the first destination would be. No destinations, no button.
  ///
  /// With [RailAlignment.bottom] that is the bottom of the column, above the
  /// bottom inset the way `NavigationRail`'s own `SafeArea` keeps its
  /// destinations above it.
  Widget _menuRail(
    BuildContext context,
    List<int> hidden,
    RailAlignment alignment,
  ) {
    final Widget? button = hidden.isEmpty
        ? null
        : _railOverflow(context, hidden, hidden.contains(state.activeBranch));
    return ColoredBox(
      color: _railColor(context, shellConfig.rail),
      child: SizedBox(
        width: shellConfig.railWidth,
        height: double.infinity,
        child: button == null
            ? null
            : switch (alignment) {
                RailAlignment.top => Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: kRailLeadingSpacer),
                    child: button,
                  ),
                ),
                RailAlignment.center => Center(child: button),
                RailAlignment.bottom => SafeArea(
                  left: false,
                  top: false,
                  right: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: button,
                  ),
                ),
              },
      ),
    );
  }

  Widget? _drawer(BuildContext context, {required bool rail}) {
    if (!chrome) {
      return null;
    }
    return shellConfig.drawerBuilder?.call(context, rail);
  }

  Widget _bar(BuildContext context) {
    final List<int> items = _chromeBranches;
    // Only for the stock bar: one tab is fine with a `barBuilder` or no chrome.
    assert(
      items.length >= 2,
      'NavigationBar needs at least two branches with showsInChrome; with '
      'fewer, give a barBuilder or hide the chrome with showsChrome',
    );
    return NavigationBar(
      selectedIndex: items.indexOf(state.activeBranch),
      onDestinationSelected: (int i) => onSelectBranch(items[i]),
      destinations: <NavigationDestination>[
        for (final int b in items)
          NavigationDestination(
            icon: Icon(shellConfig.branches[b].icon),
            label: shellConfig.branches[b].label,
          ),
      ],
    );
  }

  Widget _rail(
    BuildContext context, {
    double reserve = 0,
    RailAlignment alignment = RailAlignment.top,
    NavigationRailLabelType labels = NavigationRailLabelType.all,
  }) {
    final List<int> all = _chromeBranches;
    List<int> items = all;
    List<int> hidden = const <int>[];
    final (extents: List<double> extents, selected: double selected) =
        _destinationExtents(context, all, labels);
    if (shellConfig.railOverflow &&
        _railRoom(
              context,
              reserve: reserve,
              items: all,
              extents: extents,
              withButton: false,
              alignment: alignment,
              selected: selected,
            ).length <
            all.length) {
      final List<int> room = _railRoom(
        context,
        reserve: reserve,
        items: all,
        extents: extents,
        withButton: true,
        alignment: alignment,
        selected: selected,
      );
      // A column that cannot hold two beside the button holds it alone.
      items = room.length < 2 ? const <int>[] : room;
      hidden = <int>[
        for (final int b in all)
          if (!items.contains(b)) b,
      ];
    }
    // `NavigationRail` needs two destinations; fewer all go behind the menu.
    if (items.length < 2) {
      return _menuRail(context, <int>[...items, ...hidden], alignment);
    }
    final Widget? overflow = hidden.isEmpty
        ? null
        : _railOverflow(context, hidden, hidden.contains(state.activeBranch));
    return _navigationRail(items, alignment, labels, overflow: overflow);
  }

  /// The Material rail of [items], with [overflow] at the end its
  /// [alignment] leaves free.
  Widget _navigationRail(
    List<int> items,
    RailAlignment alignment,
    NavigationRailLabelType labels, {
    Widget? overflow,
  }) {
    final int pos = items.indexOf(state.activeBranch);
    return NavigationRail(
      selectedIndex: pos < 0 ? null : pos,
      onDestinationSelected: (int i) => onSelectBranch(items[i]),
      labelType: labels,
      groupAlignment: _groupAlignment(alignment),
      leading: overflow != null && _overflowLeads(alignment) ? overflow : null,
      trailing: overflow != null && !_overflowLeads(alignment)
          ? overflow
          : null,
      destinations: <NavigationRailDestination>[
        for (final int b in items)
          NavigationRailDestination(
            icon: Icon(shellConfig.branches[b].icon),
            label: Text(shellConfig.branches[b].label),
          ),
      ],
    );
  }
}

/// Material's "fade through" for a branch switch: out, swap, in.
///
/// Not a cross-fade — `IndexedStack` draws exactly one branch, and two rendered
/// at once would overlap two `Scaffold`s. The index in the delegate's state
/// changes immediately, so the chrome highlights the new destination without
/// delay; only the display is held back, and the children are the same
/// throughout.
class _BranchFadeThrough extends StatefulWidget {
  const _BranchFadeThrough({
    required this.index,
    required this.duration,
    required this.builder,
    super.key,
  });

  /// The branch that should be shown.
  final int index;

  /// Fade in; the fade out is half as long.
  final Duration duration;

  final Widget Function(int index) builder;

  @override
  State<_BranchFadeThrough> createState() => _BranchFadeThroughState();
}

class _BranchFadeThroughState extends State<_BranchFadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.duration ~/ 2,
    value: 1,
  );

  /// Currently on screen; lags `widget.index` by the fade out.
  late int _shown = widget.index;

  @override
  void didUpdateWidget(covariant _BranchFadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _shown) {
      // Back on the same branch while it was fading out. Nothing to swap.
      if (_opacity.status != AnimationStatus.completed) {
        _opacity.forward();
      }
      return;
    }
    _fadeOutThenSwap();
  }

  Future<void> _fadeOutThenSwap() async {
    // An interrupted `TickerFuture` never completes, so in a rapid series of
    // switches only the last fade out swaps.
    await _opacity.reverse();
    if (!mounted || widget.index == _shown) {
      return;
    }
    setState(() => _shown = widget.index);
    await _opacity.forward();
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: AdaptiveShell.branchFadeLayerKey,
      opacity: _opacity,
      child: widget.builder(_shown),
    );
  }
}

/// Resize cursor for the mouse, horizontal drag for a finger, and a marker in
/// the gap for everyone else.
///
/// Both layers are `translucent` on purpose: the area is wider than the gap and
/// lies on the panes' edges, so a tap on a list row near the edge and a
/// vertical scroll go to the pane. Only the horizontal drag is claimed.
///
/// A handle that leaves the tree mid-drag ends the drag itself, since its
/// recogniser goes with it and reports nothing more.
class _PaneSplitHandle extends StatefulWidget {
  const _PaneSplitHandle({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.color,
  });

  /// `null` — no marker, and the hit area is invisible.
  final PaneCanvasColor? color;

  final VoidCallback onStart;

  /// Incremental delta of a drag frame, in logical pixels.
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  State<_PaneSplitHandle> createState() => _PaneSplitHandleState();
}

class _PaneSplitHandleState extends State<_PaneSplitHandle> {
  bool _dragging = false;

  void _start() {
    _dragging = true;
    widget.onStart();
  }

  void _end() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.onEnd();
  }

  @override
  void dispose() {
    if (_dragging) {
      _dragging = false;
      // Deferred, as the tree is locked while it unmounts. The frame ends
      // before any next drag can begin.
      final VoidCallback end = widget.onEnd;
      WidgetsBinding.instance.addPostFrameCallback(
        (Duration _) => end(),
        debugLabel: 'PaneSplitHandle.endDrag',
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PaneCanvasColor? color = widget.color;
    return MouseRegion(
      key: AdaptiveShell.paneSplitHandleKey,
      cursor: SystemMouseCursors.resizeColumn,
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // With the default `start` the recogniser eats the 20 px touch slop to
        // confirm the gesture and then reports deltas from the point of
        // acceptance, leaving the divider permanently 20 px behind the cursor.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (DragStartDetails _) => _start(),
        onHorizontalDragUpdate: (DragUpdateDetails d) =>
            widget.onUpdate(d.delta.dx),
        onHorizontalDragEnd: (DragEndDetails _) => _end(),
        onHorizontalDragCancel: _end,
        child: color == null
            ? const SizedBox.expand()
            : Center(child: _PaneSplitDots(color: color)),
      ),
    );
  }
}

class _PaneSplitDots extends StatelessWidget {
  const _PaneSplitDots({required this.color});

  final PaneCanvasColor color;

  @override
  Widget build(BuildContext context) {
    final Widget dot = DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color(context)),
      child: const SizedBox.square(dimension: kPaneSplitDotSize),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        dot,
        const SizedBox(height: kPaneSplitDotGap),
        dot,
        const SizedBox(height: kPaneSplitDotGap),
        dot,
      ],
    );
  }
}

/// What is left of the tabs of the system's column when a screen's toolbar
/// does not fit beside them, in [places] at the bottom of the tabs' zone.
enum _TabsFold {
  /// Every tab with a place, and More with more tabs than places.
  none(0),

  /// The selected tab, as in the full zone, above More, which keeps its
  /// place and opens a menu of every tab: Apple's folded tab bar.
  two(2),

  /// More alone, filled, where not even two places fit beside the least the
  /// toolbar takes, where the full zone has no more than two places anyway,
  /// or where the selected tab is not one of the tabs.
  one(1);

  const _TabsFold(this.places);

  final int places;
}

/// One place of the tabs' zone: [child] [bottom] above the zone's bottom
/// edge, in view while [shown].
class _ColumnPlace {
  const _ColumnPlace(
    this.key, {
    required this.bottom,
    required this.shown,
    required this.child,
  });

  final Key key;
  final double bottom;
  final bool shown;
  final Widget child;
}

/// How the column's content changes: with the route transition behind the
/// change — [ColumnTransitions] — or, when the tab changes, over the
/// column's own [clock] for [duration], or else at once.
///
/// A change made while a tab switch is still fading joins it: a branch
/// opened for the first time registers its toolbar a frame late.
ColumnDrive _columnDrive({
  required ColumnTransitions transitions,
  required ColumnDrive previous,
  required bool branchChanged,
  required AnimationController clock,
  required Duration duration,
}) {
  if (branchChanged || previous.isClockRunning) {
    clock
      ..duration = duration
      ..forward(from: 0);
    return ColumnDrive.clock(clock);
  }
  return transitions.driveForChange();
}

/// The toolbar's zone of a column: the toolbar of [owner]'s screen, and the
/// one before it while it goes.
///
/// A change of screen goes with its route's transition, as the items of
/// `UINavigationBar` go with a push: the old toolbar is gone by the middle
/// of it and the new one comes in after, never one over the other; a back
/// gesture holds both where the finger is. A tab switch cross-fades over
/// [duration], as before; any other change — a transition without
/// animation, a turn of the device — is immediate.
///
/// Only the current toolbar takes taps and carries [marker].
class _ColumnSwitch extends StatefulWidget {
  const _ColumnSwitch({
    required this.owner,
    required this.marker,
    required this.branch,
    required this.transitions,
    required this.duration,
    required this.child,
  });

  /// The screen's toolbar; `null`, nothing.
  final Object? owner;
  final Key? marker;
  final int branch;
  final ColumnTransitions transitions;
  final Duration duration;
  final Widget child;

  @override
  State<_ColumnSwitch> createState() => _ColumnSwitchState();
}

/// One toolbar in the zone, going from [from] to [to] opacity.
class _SwitchLayer {
  _SwitchLayer(this.key, this.child, {required this.from, required this.to});

  final Key key;
  Widget child;
  double from;
  double to;
}

class _ColumnSwitchState extends State<_ColumnSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this);
  ColumnDrive _drive = ColumnDrive.done();
  late final List<_SwitchLayer> _layers = <_SwitchLayer>[
    _SwitchLayer(_keyOf(widget.owner), widget.child, from: 1, to: 1),
  ];

  static Key _keyOf(Object? owner) =>
      owner == null ? const ValueKey<String>('none') : ObjectKey(owner);

  _SwitchLayer get _current => _layers.last;

  @override
  void didUpdateWidget(_ColumnSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Key key = _keyOf(widget.owner);
    if (key == _current.key) {
      _current.child = widget.child;
      _drive.settleIfDone();
      return;
    }
    final double t = _drive.peek;
    final bool sequential = _drive.sequential;
    for (final _SwitchLayer layer in _layers) {
      layer
        ..from = columnOpacity(layer.from, layer.to, t, sequential: sequential)
        ..to = 0;
    }
    final _SwitchLayer? back = _layers
        .where((_SwitchLayer l) => l.key == key)
        .firstOrNull;
    _layers.removeWhere((_SwitchLayer l) => l.from == 0 || l == back);
    _layers.add(
      (back ?? _SwitchLayer(key, widget.child, from: 0, to: 1))
        ..child = widget.child
        ..to = 1,
    );
    final ColumnDrive previous = _drive;
    _drive = _columnDrive(
      transitions: widget.transitions,
      previous: previous,
      branchChanged: widget.branch != oldWidget.branch,
      clock: _clock,
      duration: widget.duration,
    )..onSettled = _settle;
    previous.dispose();
  }

  void _settle() {
    if (!mounted) {
      return;
    }
    setState(() {
      _layers.removeWhere((_SwitchLayer l) => l.to == 0);
      for (final _SwitchLayer layer in _layers) {
        layer.from = layer.to;
      }
    });
  }

  @override
  void dispose() {
    _drive.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColumnDrive drive = _drive;
    Widget layer(_SwitchLayer l) {
      final bool current = identical(l, _current);
      final double from = l.from;
      final double to = l.to;
      final Widget child = current && widget.marker != null
          ? KeyedSubtree(key: widget.marker, child: l.child)
          : l.child;
      return DrivenBox(
        key: l.key,
        drive: drive,
        opacity: (double t) =>
            columnOpacity(from, to, t, sequential: drive.sequential),
        child: IgnorePointer(
          ignoring: !current,
          child: ExcludeSemantics(excluding: !current, child: child),
        ),
      );
    }

    // Every toolbar at the top of the zone, which is as wide as the column:
    // the current one, empty while a toolbar goes, must not narrow it under
    // the one going. The current one gives it its height.
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final _SwitchLayer l in _layers)
            if (identical(l, _current))
              layer(l)
            else
              Positioned(top: 0, left: 0, right: 0, child: layer(l)),
        ],
      ),
    );
  }
}

/// The tabs' zone, [height] tall, its [places] laid out from the bottom.
///
/// When places come into view, go out of it or move, all of it is one
/// change: a place that stays in view moves, one that goes fades out where it
/// stands, and one that comes fades in where it lands. Folding is the last
/// two around a selected tab moving down; nothing is laid out twice, so a
/// place in view at both ends never jumps. Not [shown], every place goes.
///
/// A change goes with the route transition behind it — what goes is gone by
/// its middle, what comes comes after, and a place moves over all of it — or
/// with a tab switch over [duration], all at once, or else at once
/// ([_columnDrive]). Positions and opacities are worked out as the zone is
/// painted ([DrivenBox]): nothing is built frame by frame.
class _ColumnPlaces extends StatefulWidget {
  const _ColumnPlaces({
    super.key,
    required this.height,
    required this.duration,
    required this.branch,
    required this.transitions,
    required this.shown,
    required this.places,
  });

  final double height;
  final Duration duration;
  final int branch;
  final ColumnTransitions transitions;
  final bool shown;
  final List<_ColumnPlace> places;

  @override
  State<_ColumnPlaces> createState() => _ColumnPlacesState();
}

typedef _PlaceValue = ({double bottom, double opacity});

class _ColumnPlacesState extends State<_ColumnPlaces>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this);
  ColumnDrive _drive = ColumnDrive.done();
  final Map<Key, _PlaceValue> _from = <Key, _PlaceValue>{};
  final Map<Key, _PlaceValue> _to = <Key, _PlaceValue>{};

  bool _inView(_ColumnPlace p) => widget.shown && p.shown;

  @override
  void initState() {
    super.initState();
    for (final _ColumnPlace p in widget.places) {
      _from[p.key] = _to[p.key] = (
        bottom: p.bottom,
        opacity: _inView(p) ? 1.0 : 0.0,
      );
    }
  }

  static _PlaceValue _at(
    _PlaceValue from,
    _PlaceValue to,
    double t, {
    required bool sequential,
  }) => (
    bottom:
        from.bottom + (to.bottom - from.bottom) * Curves.easeInOut.transform(t),
    opacity: columnOpacity(
      from.opacity,
      to.opacity,
      sequential ? t : Curves.easeInOut.transform(t),
      sequential: sequential,
    ),
  );

  @override
  void didUpdateWidget(_ColumnPlaces oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double t = _drive.peek;
    final Map<Key, _PlaceValue> from = <Key, _PlaceValue>{};
    final Map<Key, _PlaceValue> to = <Key, _PlaceValue>{};
    bool moves = false;
    for (final _ColumnPlace p in widget.places) {
      final _PlaceValue? before = _to[p.key];
      final bool inView = _inView(p);
      // Out of view, a place stays where it stood.
      final _PlaceValue target = inView || before == null
          ? (bottom: p.bottom, opacity: inView ? 1.0 : 0.0)
          : (bottom: before.bottom, opacity: 0.0);
      to[p.key] = target;
      if (before == null) {
        from[p.key] = target;
        continue;
      }
      final _PlaceValue now = _at(
        _from[p.key]!,
        before,
        t,
        sequential: _drive.sequential,
      );
      // Out of view, it takes its new place at once and only fades in.
      from[p.key] = now.opacity == 0
          ? (bottom: target.bottom, opacity: 0.0)
          : now;
      moves = moves || target != before;
    }
    if (!moves) {
      // Nothing new to go towards: carry on with what is running.
      for (final Key key in to.keys) {
        from[key] = _from[key] ?? to[key]!;
      }
      _drive.settleIfDone();
    }
    _from
      ..clear()
      ..addAll(from);
    _to
      ..clear()
      ..addAll(to);
    if (moves) {
      final ColumnDrive previous = _drive;
      _drive = _columnDrive(
        transitions: widget.transitions,
        previous: previous,
        branchChanged: widget.branch != oldWidget.branch,
        clock: _clock,
        duration: widget.duration,
      )..onSettled = _settle;
      previous.dispose();
    }
  }

  void _settle() {
    if (!mounted) {
      return;
    }
    setState(() => _from.addAll(_to));
  }

  @override
  void dispose() {
    _drive.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColumnDrive drive = _drive;
    return SizedBox(
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final _ColumnPlace p in widget.places)
            if (_from[p.key]! case final _PlaceValue from
                when _inView(p) || from.opacity > 0)
              Positioned(
                key: ValueKey<Key>(p.key),
                left: 0,
                right: 0,
                bottom: _to[p.key]!.bottom,
                child: DrivenBox(
                  drive: drive,
                  opacity: (double t) => _at(
                    from,
                    _to[p.key]!,
                    t,
                    sequential: drive.sequential,
                  ).opacity,
                  // Down the screen as the place's bottom drops.
                  shift: (double t) =>
                      _to[p.key]!.bottom -
                      _at(
                        from,
                        _to[p.key]!,
                        t,
                        sequential: drive.sequential,
                      ).bottom,
                  child: IgnorePointer(
                    ignoring: !_inView(p),
                    child: ExcludeSemantics(
                      excluding: !_inView(p),
                      child: p.child,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
