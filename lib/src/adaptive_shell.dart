import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'entry_page.dart';
import 'nav_config.dart';
import 'nav_state.dart';
import 'pane_split.dart';

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
/// - medium: rail, one pane, the detail covering the master;
/// - expanded: rail, master and detail side by side.
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
    super.key,
  });

  final NavState<R> state;
  final AdaptiveShellConfig<R> shellConfig;
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

  Widget _nav(GlobalKey<NavigatorState> key, List<Page<Object?>> pages) {
    // Several navigators cannot share the `HeroController` from `MaterialApp`.
    return HeroControllerScope.none(
      child: Navigator(
        key: key,
        pages: pages,
        onDidRemovePage: onDidRemovePage,
      ),
    );
  }

  Widget _mastersStackAt(int index) => IndexedStack(
    key: mastersStackKey,
    index: index,
    sizing: StackFit.expand,
    children: <Widget>[
      for (int i = 0; i < shellConfig.branches.length; i++)
        if (mountedBranches.contains(i))
          _nav(branchKeys[i].master, _mainPages(i))
        else
          const SizedBox.shrink(),
    ],
  );

  Widget _mastersStack() {
    final Duration fade = shellConfig.branchFadeDuration;
    if (fade == Duration.zero) {
      return _paneMessenger(
        masterMessengerKey,
        _mastersStackAt(state.activeBranch),
      );
    }
    return _paneMessenger(
      masterMessengerKey,
      _BranchFadeThrough(
        key: branchFadeKey,
        index: state.activeBranch,
        duration: fade,
        builder: _mastersStackAt,
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

  /// [inPane] is the signal [AppTransition.adaptive] pages read. It lives in a
  /// scope rather than in the entry, because the layout changes on resize while
  /// the page has to stay the same one.
  Widget _detailsStack({required bool inPane}) => DetailPaneScope(
    inPane: inPane,
    child: _paneMessenger(
      detailMessengerKey,
      IndexedStack(
        key: detailsStackKey,
        index: state.activeBranch,
        sizing: StackFit.expand,
        children: <Widget>[
          for (int i = 0; i < shellConfig.branches.length; i++)
            if (mountedBranches.contains(i))
              _nav(branchKeys[i].detail, _detailPages(i))
            else
              const SizedBox.shrink(),
        ],
      ),
    ),
  );

  Widget _detailPlaceholder(BuildContext context) {
    final WidgetBuilder? b =
        shellConfig.branches[state.activeBranch].detailPlaceholder;
    return b != null ? Builder(builder: b) : const _DefaultDetailPlaceholder();
  }

  /// What is left to the panes after the rail and its divider.
  ///
  /// Derived from the window width, never measured: the layout has to be known
  /// at build time. The left inset is not subtracted — the rail sits against
  /// the edge and covers a landscape notch instead of growing by it, and the
  /// shell removes that inset for the panes' subtree.
  static double contentWidthFor({
    required double window,
    required bool hasRail,
    required double railWidth,
    RailDecoration rail = RailDecoration.none,
  }) {
    if (!hasRail) {
      return window;
    }
    return window - rail.regionWidth(railWidth);
  }

  /// The content area minus [PaneDecoration.margin]. This is the number that
  /// decides "one pane or two" and that the pane widths are computed from, so
  /// it is also the number an app's own layout formula has to arrive at.
  static double paneAreaWidthFor({
    required double window,
    required bool hasRail,
    required double railWidth,
    required PaneDecoration panes,
    RailDecoration rail = RailDecoration.none,
  }) => panes.paneAreaWidth(
    contentWidthFor(
      window: window,
      hasRail: hasRail,
      railWidth: railWidth,
      rail: rail,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Size window = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    if (!shellConfig.showsRail(window.width, padding)) {
      return _buildCompact(context);
    }
    return _buildRail(context, window: window.width, topInset: padding.top);
  }

  /// compact: bar at the bottom, detail overlaying it.
  ///
  /// The drawer lives on this `Scaffold`, so it is reachable from every screen.
  /// One caveat: the detail layer is a sibling above it, so a non-empty detail
  /// covers an open drawer. In the root states, where a drawer is opened, the
  /// detail is empty and transparent.
  Widget _buildCompact(BuildContext context) {
    return Stack(
      children: <Widget>[
        Scaffold(
          key: shellConfig.scaffoldKey,
          drawer: _drawer(context, rail: false),
          resizeToAvoidBottomInset: false, // see the rail `Scaffold` below
          extendBody: shellConfig.extendBodyBehindBar,
          body: _mastersStack(),
          bottomNavigationBar: _barWidget(context),
        ),
        Positioned.fill(
          child: IgnorePointer(
            // An empty detail is transparent and lets taps through to the bar
            // and the master.
            ignoring: _activeDetailEmpty,
            child: _detailsStack(inPane: false),
          ),
        ),
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
  /// [topInset] is reserved once for the whole layout: on wide there is nobody
  /// else to do it, since `AppBar` lives inside a pane and a pane starts at the
  /// window edge.
  Widget _buildRail(
    BuildContext context, {
    required double window,
    required double topInset,
  }) {
    // The divider after the rail is part of the layout arithmetic, so the
    // package draws it and a custom builder must not.
    final Widget? railWidget = _railWidget(context);
    final PaneDecoration panes = shellConfig.panes;
    final RailDecoration rail = shellConfig.rail;
    final double paneArea = paneAreaWidthFor(
      window: window,
      hasRail: railWidget != null,
      railWidth: shellConfig.railWidth,
      panes: panes,
      rail: rail,
    );
    // What the rail takes while shown. Immersive mode animates this to zero,
    // but `paneArea` above stays computed from it — the layout class is frozen,
    // see `_railRow`.
    final double railRegion = railWidget == null
        ? 0
        : rail.regionWidth(shellConfig.railWidth);
    final MasterDetailConfig? md =
        shellConfig.branches[state.activeBranch].masterDetail;
    return Scaffold(
      key: shellConfig.scaffoldKey,
      drawer: _drawer(context, rail: true),
      // The keyboard belongs to the focused pane, not to the shell. With the
      // default `true` its height was subtracted twice — once here and again by
      // the screen inside a pane, which receives the window's `viewInsets`
      // intact — and on an iPad in landscape that left the panes empty.
      resizeToAvoidBottomInset: false,
      body: _onCanvas(
        context,
        panes: panes,
        // The canvas reaches the window edge and the inset sits inside it, so
        // the strip under the status bar stays background while the rail and
        // the panes start below it.
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            // The row is built below the removed inset, and its own
            // `removePadding` takes its context from there. With the shell's
            // context, which is above the `Scaffold`, it would hand the inset
            // straight back.
            child: Builder(
              builder: (BuildContext inner) => _immersiveRow(
                inner,
                railWidget: railWidget,
                rail: rail,
                panes: panes,
                md: md,
                window: window,
                railRegion: railRegion,
                paneArea: paneArea,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps the row in the immersive listener, or skips it entirely when the
  /// mode is not configured.
  Widget _immersiveRow(
    BuildContext context, {
    required Widget? railWidget,
    required RailDecoration rail,
    required PaneDecoration panes,
    required MasterDetailConfig? md,
    required double window,
    required double railRegion,
    required double paneArea,
  }) {
    final ValueListenable<bool>? immersive = shellConfig.immersive;
    if (immersive == null) {
      return _railRow(
        context,
        railWidget: railWidget,
        rail: rail,
        panes: panes,
        md: md,
        window: window,
        railRegion: railRegion,
        paneArea: paneArea,
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
                  railWidget: railWidget,
                  rail: rail,
                  panes: panes,
                  md: md,
                  window: window,
                  railRegion: railRegion,
                  paneArea: paneArea,
                  progress: progress,
                  immersive: true,
                ),
          ),
    );
  }

  /// The wide layout's row. [context] must sit below a `MediaQuery` with the
  /// top inset removed.
  ///
  /// [paneArea] is frozen, computed with the rail counted as shown, and it
  /// alone decides the layout class. [progress] only affects geometry. The
  /// rail strip is wide enough to carry a branch across the threshold, and
  /// doing that mid-animation would move the branch navigators by `GlobalKey`
  /// and put the app's own layout formula out of step.
  Widget _railRow(
    BuildContext context, {
    required Widget? railWidget,
    required RailDecoration rail,
    required PaneDecoration panes,
    required MasterDetailConfig? md,
    required double window,
    required double railRegion,
    required double paneArea,
    required double progress,
    required bool immersive,
  }) {
    final double livePaneArea = immersive
        ? panes.paneAreaWidth(window - railRegion * progress)
        : paneArea;
    return Row(
      children: <Widget>[
        // The region is fixed at the declared width. Panes are laid out with
        // absolute numbers, so what the rail occupies has to be right by
        // construction: a rail growing with the length of its labels would eat
        // into the panes and push the detail off the edge.
        if (railWidget != null && immersive)
          _railRegion(
            context,
            railWidget: railWidget,
            rail: rail,
            region: railRegion,
            progress: progress,
          )
        else if (railWidget != null) ...<Widget>[
          _railCard(context, railWidget: railWidget, rail: rail),
          if (rail.dividerWidth > 0) VerticalDivider(width: rail.dividerWidth),
        ],
        Expanded(
          // The content area's left edge is the rail divider, not the screen
          // edge, and the rail has already handled that inset. Tied to the
          // presence of the rail rather than to the immersive progress, or
          // padding would appear halfway through the animation.
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: railWidget != null,
            child: _inPaneArea(
              panes: panes,
              // Threshold from the frozen width, widths from the live one.
              child: md != null && md.fits(paneArea, gap: panes.gap)
                  ? _twoPanes(context, md, livePaneArea)
                  : _singlePanel(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _railCard(
    BuildContext context, {
    required Widget railWidget,
    required RailDecoration rail,
  }) {
    return SizedBox(
      // The margin goes outside, so `railWidth` stays the width of the widget.
      width: shellConfig.railWidth + rail.margin.horizontal,
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
          // what is left. The rail covers the notch rather than growing by it,
          // so the inset is not its business.
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            child: railWidget,
          ),
        ),
      ),
    );
  }

  /// The rail is measured at full width and clipped by the shrinking region,
  /// pinned to its right edge, so it slides out whole. Squeezing it is not an
  /// option: its destinations are laid out into the declared width and would
  /// break at 40 px. The subtree stays mounted throughout.
  Widget _railRegion(
    BuildContext context, {
    required Widget railWidget,
    required RailDecoration rail,
    required double region,
    required double progress,
  }) {
    return SizedBox(
      key: railRegionKey,
      width: region * progress,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerRight,
          minWidth: region,
          maxWidth: region,
          child: Row(
            children: <Widget>[
              _railCard(context, railWidget: railWidget, rail: rail),
              if (rail.dividerWidth > 0)
                VerticalDivider(width: rail.dividerWidth),
            ],
          ),
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

  /// medium, and expanded with a collapsed empty detail — there the top layer
  /// is transparent and the master shows through at full width.
  Widget _singlePanel(BuildContext context) {
    return _paneCard(
      context,
      Stack(
        children: <Widget>[
          _mastersStack(),
          IgnorePointer(
            ignoring: _activeDetailEmpty,
            // Same presentation as compact, so the same platform transition.
            child: _detailsStack(inPane: false),
          ),
        ],
      ),
    );
  }

  static const Duration detailRevealDuration = Duration(milliseconds: 240);

  Widget _twoPanes(BuildContext context, MasterDetailConfig md, double width) {
    final PaneSplitController? split = shellConfig.paneSplit;
    if (split == null) {
      return _resizablePanes(context, md, width, null);
    }
    // Only this subtree rebuilds on a drag; the delegate knows nothing about
    // it.
    return ListenableBuilder(
      listenable: split,
      builder: (BuildContext context, Widget? _) =>
          _resizablePanes(context, md, width, split),
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
  Widget _resizablePanes(
    BuildContext context,
    MasterDetailConfig md,
    double width,
    PaneSplitController? split,
  ) {
    final PaneDecoration panes = shellConfig.panes;
    final Object branchId = shellConfig.branches[state.activeBranch].id;
    final double masterWidth = md.masterWidthFor(
      width,
      gap: panes.gap,
      fraction: split?.fractionOf(branchId),
    );
    final bool collapsed = md.collapseWhenDetailEmpty && _activeDetailEmpty;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: detailRevealDuration,
      curve: Curves.easeInOut,
      builder: (BuildContext context, double reveal, Widget? _) => _splitLayout(
        context,
        panes: panes,
        split: width + (masterWidth - width) * reveal,
        detailWidth: width - masterWidth - panes.gap,
        collapsed: collapsed,
        handle: split == null || collapsed
            ? null
            : _splitHandle(
                md: md,
                panes: panes,
                split: split,
                branchId: branchId,
                available: width,
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
  Widget _splitLayout(
    BuildContext context, {
    required PaneDecoration panes,
    required double split,
    required double detailWidth,
    required bool collapsed,
    Widget? handle,
  }) {
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
          // spans the full width.
          child: MediaQuery.removePadding(
            context: context,
            removeRight: !collapsed,
            child: _paneCard(context, _mastersStack()),
          ),
        ),
        Positioned(
          left: split + panes.gap,
          top: 0,
          bottom: 0,
          width: detailWidth,
          child: _paneCard(
            context,
            Stack(
              children: <Widget>[
                if (_activeDetailEmpty && !collapsed)
                  Positioned.fill(child: _detailPlaceholder(context)),
                _detailsStack(inPane: true),
              ],
            ),
          ),
        ),
        if (handle != null)
          Positioned(
            // Centred on the gap and wider than it, so it reaches onto both
            // panes' edges. Last child, over both panes.
            left: split + panes.gap / 2 - panes.splitHandleWidth / 2,
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

  Widget? _railWidget(BuildContext context) {
    // Unlike the bar, the rail handles a hidden branch natively.
    if (!chrome) {
      return null;
    }
    final ShellChromeBuilder? custom = shellConfig.railBuilder;
    if (custom == null) {
      return _rail(context);
    }
    return custom(context, state.activeBranch, onSelectBranch);
  }

  Widget? _drawer(BuildContext context, {required bool rail}) {
    if (!chrome) {
      return null;
    }
    return shellConfig.drawerBuilder?.call(context, rail);
  }

  Widget _bar(BuildContext context) {
    final List<int> items = _chromeBranches;
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

  Widget _rail(BuildContext context) {
    final List<int> items = _chromeBranches;
    final int pos = items.indexOf(state.activeBranch);
    return NavigationRail(
      selectedIndex: pos < 0 ? null : pos,
      onDestinationSelected: (int i) => onSelectBranch(items[i]),
      labelType: NavigationRailLabelType.all,
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
class _PaneSplitHandle extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
        onHorizontalDragStart: (DragStartDetails _) => onStart(),
        onHorizontalDragUpdate: (DragUpdateDetails d) => onUpdate(d.delta.dx),
        onHorizontalDragEnd: (DragEndDetails _) => onEnd(),
        onHorizontalDragCancel: onEnd,
        child: color == null
            ? const SizedBox.expand()
            : Center(child: _PaneSplitDots(color: color!)),
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

class _DefaultDetailPlaceholder extends StatelessWidget {
  const _DefaultDetailPlaceholder();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Select an item')));
}
