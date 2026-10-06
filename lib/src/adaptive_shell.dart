import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'entry_page.dart';
import 'fold.dart';
import 'nav_config.dart';
import 'nav_state.dart';
import 'pane_metrics.dart';
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
  @visibleForTesting
  static const Key railOverflowKey = ValueKey<String>(
    'adaptive-nav.rail-overflow',
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
    // A blank pane, not a caption: the package has no screens of its own and
    // no business shipping a string it cannot localise. Anything to say in an
    // empty pane is [BranchConfig.detailPlaceholder]'s to say.
    return b != null ? Builder(builder: b) : const Scaffold();
  }

  @override
  Widget build(BuildContext context) {
    final Size window = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final ChromePlacement placement = shellConfig.chromeLayout(window, padding);
    // In window coordinates, like a display feature's bounds; converted to
    // pane coordinates once the pane area's origin is known.
    final Rect? foldHint = shellConfig.foldLocator?.call(window, padding);
    if (placement.isRail) {
      return _buildRail(
        context,
        window: window.width,
        padding: padding,
        placement: placement,
        foldHint: foldHint,
      );
    }
    return _buildBar(
      context,
      window: window.width,
      padding: padding,
      foldHint: foldHint,
    );
  }

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
    BuildContext context, {
    required double window,
    required EdgeInsets padding,
    Rect? foldHint,
  }) {
    final MasterDetailConfig? md =
        shellConfig.branches[state.activeBranch].masterDetail;
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
          child: _paneInsets(
            context,
            top: math.max(0.0, padding.top - panes.margin.top),
            child: Builder(
              builder: (BuildContext inner) => _inPaneArea(
                panes: panes,
                child: _twoPanes(
                  inner,
                  md,
                  paneArea,
                  underlap,
                  underlap.left + panes.margin.left,
                  foldHint,
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _barWidget(context),
      );
    }
    return _buildStack(context);
  }

  /// bar, one pane: master in the body and the detail overlaying the bar.
  ///
  /// The drawer lives on this `Scaffold`, so it is reachable from every screen.
  /// One caveat: the detail layer is a sibling above it, so a non-empty detail
  /// covers an open drawer. In the root states, where a drawer is opened, the
  /// detail is empty and transparent.
  Widget _buildStack(BuildContext context) {
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
  /// The rail and the panes extend under the status bar. The rail reserves
  /// the top inset inside its own surface; each pane passes what is left after
  /// its margin to the screen, where the `AppBar` reserves it. The horizontal
  /// insets come off the pane area instead, because a pane only bleeds under
  /// them; see [PaneUnderlap].
  Widget _buildRail(
    BuildContext context, {
    required double window,
    required EdgeInsets padding,
    required ChromePlacement placement,
    Rect? foldHint,
  }) {
    final PaneDecoration panes = shellConfig.panes;
    final RailDecoration rail = shellConfig.rail;
    // The reserve is needed before the rail is built: it is height the
    // destinations cannot use, so it decides how many of them fit.
    final (double reserveIfShown, SystemBarEnd reserveEnd) = _systemBarReserve(
      MediaQuery.sizeOf(context),
      padding,
      placement,
    );
    // The divider after the rail is part of the layout arithmetic, so the
    // package draws it and a custom builder must not.
    final Widget? railWidget = _railWidget(context, reserve: reserveIfShown);
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
    final double railRegion = railWidget == null
        ? 0
        : PaneMetrics.railColumnWidth(
            railWidth: shellConfig.railWidth,
            systemBar: systemBar,
            edgeGap: edgeGap,
            rail: rail,
          );
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
              reserve: railWidget == null ? 0 : reserveIfShown,
              reserveEnd: reserveEnd,
              railTop: railWidget == null
                  ? 0
                  : math.max(0.0, padding.top - rail.margin.top),
              foldHint: foldHint,
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
    required PaneUnderlap underlap,
    required ChromePlacement placement,
    required double systemBar,
    required double edgeGap,
    required double reserve,
    required SystemBarEnd reserveEnd,
    required double railTop,
    required Rect? foldHint,
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
        underlap: underlap,
        placement: placement,
        systemBar: systemBar,
        edgeGap: edgeGap,
        reserve: reserve,
        reserveEnd: reserveEnd,
        railTop: railTop,
        foldHint: foldHint,
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
                  underlap: underlap,
                  placement: placement,
                  systemBar: systemBar,
                  edgeGap: edgeGap,
                  reserve: reserve,
                  reserveEnd: reserveEnd,
                  railTop: railTop,
                  foldHint: foldHint,
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
    BuildContext context, {
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
    required double reserve,
    required SystemBarEnd reserveEnd,
    required double railTop,
    required Rect? foldHint,
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
      railRegion - rail.regionWidth(shellConfig.railWidth) - edgeGap,
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

    final List<Widget> railRegionWidgets = <Widget>[
      if (railWidget != null && immersive)
        _railRegion(
          context,
          railWidget: railWidget,
          rail: rail,
          region: railRegion,
          progress: progress,
          onLeft: onLeft,
          reserve: reserve,
          reserveEnd: reserveEnd,
          top: railTop,
        )
      else if (railWidget != null) ...<Widget>[
        if (onLeft && edgeGap > 0) spacer(edgeGap),
        if (!onLeft && slack > 0) SizedBox(width: slack),
        if (!onLeft && rail.dividerWidth > 0)
          VerticalDivider(width: rail.dividerWidth),
        _railCard(
          context,
          railWidget: railWidget,
          rail: rail,
          onLeft: onLeft,
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
              ? _twoPanes(context, md, livePaneArea, underlap, origin, foldHint)
              : _singlePanel(context, underlap),
        ),
      ),
    );
    return Row(
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
  }) {
    if (reserve <= 0 && top <= 0) {
      return child;
    }
    return ColoredBox(
      color: _railColor(context, rail),
      child: Padding(
        padding: end == SystemBarEnd.top
            ? EdgeInsets.only(top: top + reserve)
            : EdgeInsets.only(top: top, bottom: reserve),
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
    double reserve = 0,
    SystemBarEnd reserveEnd = SystemBarEnd.top,
    double top = 0,
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
          // what is left. The rail covers what is on its own edge rather than
          // growing by it — on iPhone Duo that edge is the system's vertical
          // bar — so the inset is not its business. The top inset is already
          // reserved by `_railSurface`, so it is removed here too.
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: onLeft,
            removeRight: !onLeft,
            removeTop: true,
            child: _railSurface(
              context,
              rail: rail,
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
  Widget _railRegion(
    BuildContext context, {
    required Widget railWidget,
    required RailDecoration rail,
    required double region,
    required double progress,
    required bool onLeft,
    double reserve = 0,
    SystemBarEnd reserveEnd = SystemBarEnd.top,
    double top = 0,
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
          child: Row(
            children: <Widget>[
              if (!onLeft && rail.dividerWidth > 0)
                VerticalDivider(width: rail.dividerWidth),
              _railCard(
                context,
                railWidget: railWidget,
                rail: rail,
                onLeft: onLeft,
                reserve: reserve,
                reserveEnd: reserveEnd,
                top: top,
              ),
              if (onLeft && rail.dividerWidth > 0)
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
  Widget _singlePanel(BuildContext context, PaneUnderlap underlap) {
    return _paneInsets(
      context,
      left: underlap.left,
      right: underlap.right,
      child: _paneCard(
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
      ),
    );
  }

  static const Duration detailRevealDuration = Duration(milliseconds: 240);

  /// [origin] is the pane area's left edge in window coordinates, which is
  /// what a display feature's bounds are measured in.
  Widget _twoPanes(
    BuildContext context,
    MasterDetailConfig md,
    double width,
    PaneUnderlap underlap,
    double origin,
    Rect? foldHint,
  ) {
    // The platform first; the app's own answer only fills the silence.
    final PaneFold? fold = md.alignToFold
        ? FoldMetrics.paneFold(
                features: MediaQuery.displayFeaturesOf(context),
                origin: origin,
                paneArea: width,
              ) ??
              FoldMetrics.fromBounds(
                bounds: foldHint,
                origin: origin,
                paneArea: width,
              )
        : null;
    final PaneSplitController? split = shellConfig.paneSplit;
    if (split == null) {
      return _resizablePanes(context, md, width, underlap, fold, null);
    }
    // Only this subtree rebuilds on a drag; the delegate knows nothing about
    // it.
    return ListenableBuilder(
      listenable: split,
      builder: (BuildContext context, Widget? _) =>
          _resizablePanes(context, md, width, underlap, fold, split),
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
    MasterDetailConfig md,
    double width,
    PaneUnderlap underlap,
    PaneFold? fold,
    PaneSplitController? split,
  ) {
    final PaneDecoration panes = shellConfig.panes;
    final Object branchId = shellConfig.branches[state.activeBranch].id;
    // A fold both panes clear takes the boundary: a pane straddling a crease
    // is bent across two planes, which no ratio or drag is worth. Otherwise
    // the width decides, as everywhere else.
    final bool onFold = fold != null && md.fitsAround(fold, width);
    final double gap = onFold ? math.max(panes.gap, fold.width) : panes.gap;
    final double masterWidth = onFold
        ? fold.start
        : md.masterWidthFor(
            width,
            gap: gap,
            fraction: split?.fractionOf(branchId),
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
        panes: panes,
        underlap: underlap,
        gap: gap,
        split: area + (boundary - area) * reveal,
        detailWidth: area - boundary - gap,
        collapsed: collapsed,
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
    required PaneUnderlap underlap,
    required double gap,
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
          child: _paneInsets(
            context,
            left: underlap.left,
            right: collapsed ? underlap.right : 0,
            child: _paneCard(context, _mastersStack()),
          ),
        ),
        Positioned(
          left: split + gap,
          top: 0,
          bottom: 0,
          width: detailWidth,
          // Its left edge is the gap; on the right it is the pane that bleeds
          // under the inset, and this is the screen that has to inset it away.
          child: _paneInsets(
            context,
            left: 0,
            right: underlap.right,
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

  /// What the system's vertical bar keeps free in the rail's column, and at
  /// which end.
  ///
  /// Zero unless a one-sided vertical bar is on one of the window's edges, so
  /// tablets, Android, desktop windows and notched iPhones never get past the
  /// first checks. At the bottom the rail's own `SafeArea` already keeps the
  /// home indicator's inset, so only the rest of the reserve is added.
  (double, SystemBarEnd) _systemBarReserve(
    Size window,
    EdgeInsets padding,
    ChromePlacement placement,
  ) {
    final SystemBarMetrics bar = shellConfig.systemBar;
    if (PaneMetrics.systemBarInset(padding: padding, placement: placement) >
        0) {
      final double reserve = window.width > window.height
          ? bar.landscapeReserve
          : bar.reserve;
      final SystemBarEnd end = bar.end(window, placement);
      return switch (end) {
        SystemBarEnd.top => (reserve, end),
        SystemBarEnd.bottom => (math.max(0.0, reserve - padding.bottom), end),
      };
    }
    final ChromePlacement far = switch (placement) {
      ChromePlacement.left => ChromePlacement.right,
      ChromePlacement.right => ChromePlacement.left,
      ChromePlacement.bottom => ChromePlacement.bottom,
    };
    if (padding.top == 0 &&
        PaneMetrics.systemBarInset(padding: padding, placement: far) > 0) {
      return (bar.cornerClearance, SystemBarEnd.top);
    }
    return (0.0, SystemBarEnd.top);
  }

  Widget? _railWidget(BuildContext context, {double reserve = 0}) {
    // Unlike the bar, the rail handles a hidden branch natively.
    if (!chrome) {
      return null;
    }
    final ShellChromeBuilder? custom = shellConfig.railBuilder;
    if (custom == null) {
      return _rail(context, reserve: reserve);
    }
    return custom(context, state.activeBranch, onSelectBranch);
  }

  /// Height of each destination, from its own label.
  ///
  /// A label too wide for the rail takes a second line, and only that
  /// destination grows: Material lays each one out on its own, so a rail of
  /// "Home"s beside one "People" is 64s beside one 80 rather than all 80s.
  /// Counted the same way, or a single long label would push its neighbours
  /// into the menu with the column still half empty.
  ///
  /// Laid out with a `TextPainter`, which is arithmetic over a declared width
  /// rather than a measurement of the tree.
  List<double> _destinationExtents(BuildContext context, List<int> items) {
    final double? declared = shellConfig.railDestinationExtent;
    if (declared != null) {
      return List<double>.filled(items.length, declared);
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
    return extents;
  }

  /// How many of [extents] the rail's column can hold, in order.
  ///
  /// Arithmetic, not measurement: the shell knows the window, the inset it
  /// reserved, the rail card's margin, what the system bar keeps at its end
  /// and how tall every destination is, because every one of those is
  /// declared. A `LayoutBuilder` here is the one place `doc/design.md` warns
  /// about.
  int _railRoom(
    BuildContext context, {
    required double reserve,
    required List<double> extents,
    required bool withButton,
  }) {
    final Size window = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    // The card is the window height minus its margins. Whatever part of the
    // top inset the margin does not cover is reserved inside the card. The
    // rail's own `SafeArea` takes the bottom inset.
    final RailDecoration rail = shellConfig.rail;
    final double column =
        window.height -
        math.max(0.0, padding.top - rail.margin.top) -
        rail.margin.vertical -
        reserve -
        padding.bottom -
        kRailLeadingSpacer -
        (withButton ? kRailOverflowExtent : 0);
    double used = 0;
    int room = 0;
    for (final double extent in extents) {
      if (used + extent > column) {
        break;
      }
      used += extent;
      room++;
    }
    return room;
  }

  /// The destinations that do not fit, behind a menu at the end of the rail.
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

  Widget _rail(BuildContext context, {double reserve = 0}) {
    List<int> items = _chromeBranches;
    List<int> hidden = const <int>[];
    final List<double> extents = _destinationExtents(context, items);
    if (shellConfig.railOverflow &&
        _railRoom(
              context,
              reserve: reserve,
              extents: extents,
              withButton: false,
            ) <
            items.length) {
      final int room = _railRoom(
        context,
        reserve: reserve,
        extents: extents,
        withButton: true,
      );
      hidden = items.sublist(room);
      items = items.sublist(0, room);
    }
    final int pos = items.indexOf(state.activeBranch);
    return NavigationRail(
      selectedIndex: pos < 0 ? null : pos,
      onDestinationSelected: (int i) => onSelectBranch(items[i]),
      labelType: NavigationRailLabelType.all,
      trailing: hidden.isEmpty
          ? null
          : _railOverflow(context, hidden, hidden.contains(state.activeBranch)),
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
