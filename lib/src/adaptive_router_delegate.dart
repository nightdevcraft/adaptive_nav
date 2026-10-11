import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adaptive_route_information_parser.dart';
import 'adaptive_shell.dart';
import 'entry_page.dart';
import 'nav_config.dart';
import 'nav_state.dart';
import 'pane_split.dart';

/// Holds the [NavState] and exposes the navigation API.
///
/// One instance for the whole app, never recreated on resize. Together with the
/// stable navigator keys it holds for every branch, that is what preserves the
/// screens when the layout changes.
///
/// Every way out of a screen goes through one [NavExitGuard] gate, tab switches
/// included.
class AdaptiveRouterDelegate<R> extends RouterDelegate<NavState<R>>
    with ChangeNotifier {
  AdaptiveRouterDelegate({
    required this.shellConfig,
    required NavState<R> initialState,
  }) : assert(shellConfig.branches.isNotEmpty, 'branches is empty'),
       assert(
         shellConfig.backToBranch == null ||
             shellConfig.backToBranch! < shellConfig.branches.length,
         'backToBranch is out of range of branches',
       ),
       _state = initialState {
    _branchKeys = <BranchNavigatorKeys>[
      for (int i = 0; i < shellConfig.branches.length; i++)
        BranchNavigatorKeys(),
    ];
  }

  final AdaptiveShellConfig<R> shellConfig;
  NavState<R> _state;
  late final List<BranchNavigatorKeys> _branchKeys;

  // Set by [AdaptiveNav], which owns them. Otherwise the config's are used.
  ValueListenable<bool>? _ownedImmersive;
  PaneSplitController? _ownedPaneSplit;

  /// Root `Navigator` with a single shell page: it provides the `Overlay` the
  /// chrome needs and keeps the app's `HeroController` off the branches.
  final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

  // Keys below live here, not in the shell, because the layout moves their
  // widgets between a `Stack` and a `Row`. Without a `GlobalKey` a running
  // fade would be recreated mid-animation and a visible snack bar would vanish
  // on resize.
  final GlobalKey _branchFadeKey = GlobalKey();
  final GlobalKey<ScaffoldMessengerState> _masterMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<ScaffoldMessengerState> _detailMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Messenger of the active branch's master pane, `null` until the shell has
  /// been built.
  ScaffoldMessengerState? get masterMessenger =>
      _masterMessengerKey.currentState;

  /// Messenger of the active branch's detail pane.
  ScaffoldMessengerState? get detailMessenger =>
      _detailMessengerKey.currentState;

  /// Branches opened at least once. A branch mounts on first entry and lives
  /// from then on; until then it is an empty slot, so start-up does not build
  /// every tab's screens with their subscriptions and animations.
  final Set<int> _mountedBranches = <int>{};

  /// Without a codec, not redirected until the first frame.
  NavState<R> get state => _state;

  @visibleForTesting
  Set<int> get mountedBranches => UnmodifiableSetView<int>(_mountedBranches);

  @override
  NavState<R> get currentConfiguration => _state;

  /// A gate can still answer after the app is gone; its answer is dropped.
  bool _disposed = false;

  /// `redirect` has not seen the start yet. A codec's first location goes
  /// through it anyway; without a codec the first [build] applies it.
  bool _initialRedirectPending = true;

  /// Every `push` still waiting completes with `null`.
  @override
  void dispose() {
    _disposed = true;
    for (final BranchStack<R> stack in _state.branches) {
      for (final NavEntry<R> e in stack.entries) {
        _completeEntry(e, null);
      }
    }
    super.dispose();
  }

  /// The one way the state changes. Any screen it drops has its `push` future
  /// completed here, with `null` unless [popWithResult] got there first.
  void _apply(NavState<R> next) {
    if (_disposed) {
      return;
    }
    final NavState<R> previous = _state;
    _state = next;
    _mountedBranches.add(next.activeBranch);
    _completeDropped(previous, next);
    notifyListeners();
  }

  void _completeDropped(NavState<R> previous, NavState<R> next) {
    final Set<NavEntry<R>> kept = Set<NavEntry<R>>.identity();
    for (final BranchStack<R> stack in next.branches) {
      kept.addAll(stack.entries);
    }
    for (final BranchStack<R> stack in previous.branches) {
      for (final NavEntry<R> e in stack.entries) {
        if (!kept.contains(e)) {
          _completeEntry(e, null);
        }
      }
    }
  }

  // ---------------------------------------------------------------- API

  /// Pushes a screen onto the active branch. The future completes with the
  /// value from [popWithResult], or `null` on a plain pop.
  Future<Object?> push(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) {
    assert(!_disposed, 'push on a disposed AdaptiveRouterDelegate');
    if (_disposed) {
      return Future<Object?>.value();
    }
    final BranchConfig<R> cfg = shellConfig.branches[_state.activeBranch];
    final Completer<Object?> completer = Completer<Object?>();
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: transition ?? cfg.transition,
      onExit: onExit,
      completer: completer,
    );
    _apply(_state.withActiveStack(_state.active.push(entry)));
    return completer.future;
  }

  /// Pops the top screen through the gate. `false` — refused, already at the
  /// root, or gone when the gate answered. Unguarded, it applies at once (as do
  /// all gated mutations), so a `push` right after lands on top.
  Future<bool> pop() async {
    final int branch = _state.activeBranch;
    final BranchStack<R> stack = _state.branches[branch];
    if (stack.entries.length <= 1) {
      return false;
    }
    final NavEntry<R> top = stack.top;
    if (top.onExit != null && !await _guard(top)) {
      return false;
    }
    final int at = stack.entries.length - 1;
    return _splice(branch, at, <NavEntry<R>>[top], <NavEntry<R>>[]);
  }

  /// The screen leaves with a result. No gate: the screen has already decided.
  void popWithResult<T extends Object?>(T result) {
    final BranchStack<R> stack = _state.active;
    if (stack.entries.length <= 1) {
      return;
    }
    final NavEntry<R> top = stack.top;
    _completeEntry(top, result);
    _apply(_state.withActiveStack(stack.pop()));
  }

  /// Replaces the top screen, gating the old one unless it is the root.
  Future<void> replace(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) async {
    final int branch = _state.activeBranch;
    final BranchStack<R> stack = _state.branches[branch];
    final NavEntry<R> top = stack.top;
    final int at = stack.entries.length - 1;
    if (at > 0 && top.onExit != null && !await _guard(top)) {
      return;
    }
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: transition ?? shellConfig.branches[branch].transition,
      onExit: onExit,
    );
    _splice(branch, at, <NavEntry<R>>[top], <NavEntry<R>>[entry]);
  }

  /// Resets the active branch to [route] as its only screen, gating everything
  /// removed.
  Future<void> resetTo(R route) async {
    final int branch = _state.activeBranch;
    final List<NavEntry<R>> removed = _state.branches[branch].entries;
    if (_anyGuarded(removed) && !await _guardAll(removed)) {
      return;
    }
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: shellConfig.branches[branch].transition,
    );
    _splice(branch, 0, removed, <NavEntry<R>>[entry]);
  }

  /// Leaves the branch as `[root, route]`: the lateral move of a master-detail
  /// list, where picking another item drops a detail of any depth.
  ///
  /// A primitive rather than `popToRoot()` + `push()`, because `popToRoot` does
  /// not report the gate's verdict and two mutations flash an empty pane
  /// between them. Everything removed is gated.
  Future<void> resetDetailTo(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) async {
    // Capture the branch before the gate: while a dialog is up another branch
    // may become active, and the answer belongs to the one that was asked
    // about.
    final int branch = _state.activeBranch;
    final List<NavEntry<R>> removed = _state.branches[branch].entries.sublist(
      1,
    );
    if (_anyGuarded(removed) && !await _guardAll(removed)) {
      return;
    }
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: transition ?? shellConfig.branches[branch].transition,
      onExit: onExit,
    );
    _splice(branch, 1, removed, <NavEntry<R>>[entry]);
  }

  /// Back to the branch root, gating everything above it.
  Future<void> popToRoot() async {
    final int branch = _state.activeBranch;
    final BranchStack<R> stack = _state.branches[branch];
    if (stack.entries.length <= 1) {
      return;
    }
    final List<NavEntry<R>> removed = stack.entries.sublist(1);
    if (_anyGuarded(removed) && !await _guardAll(removed)) {
      return;
    }
    _splice(branch, 1, removed, <NavEntry<R>>[]);
  }

  /// Swaps [removed], found at [start] when the gate was asked, for [inserted].
  /// Screens pushed above meanwhile stay; if [removed] is gone (by identity),
  /// the answer is stale and nothing happens.
  bool _splice(
    int branch,
    int start,
    List<NavEntry<R>> removed,
    List<NavEntry<R>> inserted,
  ) {
    final List<NavEntry<R>> entries = _state.branches[branch].entries;
    final int end = start + removed.length;
    if (_disposed ||
        end > entries.length ||
        !_sameEntries(entries.getRange(start, end), removed)) {
      return false;
    }
    _apply(
      _state.withBranch(
        branch,
        BranchStack<R>(<NavEntry<R>>[
          ...entries.take(start),
          ...inserted,
          ...entries.skip(end),
        ]),
      ),
    );
    return true;
  }

  /// Switches the active branch.
  ///
  /// A tab switch is an ordinary way out of a screen, so the current branch's
  /// top entry is gated before the tab changes; a refusal leaves the tab where
  /// it was. [resetToRoot] additionally enters the branch at its root, which
  /// destroys the target branch's stack and gates that too — in the opposite
  /// order, so the dialog appears over the screen it asks about.
  ///
  /// With no guards anywhere in play the whole thing happens synchronously, in
  /// the same frame. `doc/design.md` has the reasoning.
  ///
  /// Throws an [ArgumentError] for an [index] outside the branches.
  Future<void> goBranch(int index, {bool resetToRoot = false}) {
    RangeError.checkValidIndex(
      index,
      shellConfig.branches,
      'index',
      shellConfig.branches.length,
    );
    return _goBranch(index, resetToRoot: resetToRoot);
  }

  Future<void> _goBranch(int index, {required bool resetToRoot}) async {
    // Re-tapping the active tab does not come through here: there is nothing to
    // leave, and unsaved work is covered by the reset gate below.
    if (index != _state.activeBranch) {
      final NavEntry<R> leaving = _state.active.top;
      if (leaving.onExit != null && !await _guard(leaving)) {
        return;
      }
    }
    if (!resetToRoot) {
      // The tab may have changed while the gate was up.
      if (index != _state.activeBranch) {
        _apply(_state.copyWith(activeBranch: index));
      }
      return;
    }
    final List<NavEntry<R>> removed = _state.branches[index].entries.length > 1
        ? _state.branches[index].entries.sublist(1)
        : <NavEntry<R>>[];
    if (index != _state.activeBranch) {
      _apply(_state.copyWith(activeBranch: index));
    }
    if (removed.isEmpty) {
      return;
    }
    // Nothing to ask, so reset in the same frame: an ordinary tab switch should
    // not wait for a microtask and leave a window for re-entry.
    if (removed.every((NavEntry<R> e) => e.onExit == null)) {
      _resetGuardedBranch(index, removed);
      return;
    }
    if (!await _guardAll(removed)) {
      return;
    }
    _resetGuardedBranch(index, removed);
  }

  /// Collapses branch [index] to its root, but only if its stack is still the
  /// one that passed the gate — a push or a deep link may have arrived while
  /// the gate was up, and that entry was never asked about.
  void _resetGuardedBranch(int index, List<NavEntry<R>> guarded) {
    final BranchStack<R> stack = _state.branches[index];
    if (!_sameEntries(stack.entries.skip(1), guarded)) {
      return;
    }
    _apply(_state.withBranch(index, stack.resetToRoot()));
  }

  /// Identity, not value equality: two entries with the same route are
  /// different screens with their own state and their own guard.
  bool _sameEntries(Iterable<NavEntry<R>> a, List<NavEntry<R>> b) {
    final List<NavEntry<R>> left = a.toList();
    if (left.length != b.length) {
      return false;
    }
    for (int i = 0; i < left.length; i++) {
      if (!identical(left[i], b[i])) {
        return false;
      }
    }
    return true;
  }

  Future<void> _guardedPop(NavEntry<R> entry) async {
    // Read before the gate: the flag is down by the time it answers.
    final bool systemBack = _inSystemBack;
    if (!await _guard(entry)) {
      return;
    }
    // A guarded root is never removed. On system back the gate stands for the
    // switch to `backToBranch` or, with none, for leaving the app: the root's
    // `PopScope` took that decision from the framework.
    final BranchStack<R> active = _state.active;
    if (active.entries.length == 1 && identical(active.root, entry)) {
      if (!systemBack) {
        return;
      }
      if (_backLeadsToBranch()) {
        _apply(_state.copyWith(activeBranch: shellConfig.backToBranch));
      } else {
        await SystemNavigator.pop();
      }
      return;
    }
    _removeEntry(entry);
  }

  void _removeEntry(NavEntry<R> entry) {
    for (int b = 0; b < _state.branches.length; b++) {
      final BranchStack<R> stack = _state.branches[b];
      final int idx = stack.entries.indexWhere(
        (NavEntry<R> e) => identical(e, entry) || e.pageKey == entry.pageKey,
      );
      if (idx <= 0) {
        continue;
      }
      final List<NavEntry<R>> next = List<NavEntry<R>>.of(stack.entries)
        ..removeAt(idx);
      _apply(_state.withBranch(b, BranchStack<R>(next)));
      return;
    }
  }

  // --------------------------------------------------------- guard/util

  /// `false` also when the guard throws, since a screen that cannot answer is
  /// not left on a guess, and when the delegate was disposed meanwhile.
  Future<bool> _guard(NavEntry<R> entry) async {
    final NavExitGuard? guard = entry.onExit;
    if (guard == null) {
      return true;
    }
    bool ok;
    try {
      ok = await guard();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'adaptive_nav',
          context: ErrorDescription('while asking a screen to leave (onExit)'),
        ),
      );
      ok = false;
    }
    return ok && !_disposed;
  }

  bool _anyGuarded(Iterable<NavEntry<R>> entries) =>
      entries.any((NavEntry<R> e) => e.onExit != null);

  Future<bool> _guardAll(Iterable<NavEntry<R>> entries) async {
    // No await for unguarded entries: the first dialog goes up in this call.
    for (final NavEntry<R> e in entries) {
      if (e.onExit != null && !await _guard(e)) {
        return false;
      }
    }
    return true;
  }

  void _completeEntry(NavEntry<R> entry, Object? result) {
    final Completer<Object?>? c = entry.completer;
    if (c != null && !c.isCompleted) {
      c.complete(result);
    }
  }

  // ------------------------------------------------- Router integration

  /// The navigator holding the active branch's top screen.
  GlobalKey<NavigatorState> _topNavigatorKey() {
    final BranchNavigatorKeys keys = _branchKeys[_state.activeBranch];
    final bool inDetail =
        shellConfig.branches[_state.activeBranch].masterDetail != null &&
        _state.active.entries.length > 1;
    return inDetail ? keys.detail : keys.master;
  }

  // ------------------------------------------------- Predictive back

  /// The last `canHandlePop` each navigator reported. Inactive ones are kept
  /// too: a tab switch makes a navigator the top one without a report.
  final Map<GlobalKey<NavigatorState>, bool> _canHandlePop =
      <GlobalKey<NavigatorState>, bool>{};

  final GlobalKey<_BackReporterState> _backReporterKey =
      GlobalKey<_BackReporterState>();

  /// Whether [popRoute] would claim system back, checked in the same order.
  ///
  /// `canPop()` sees local history entries (the drawer, `showBottomSheet`),
  /// which send no notification; the reported value sees a blocking `PopScope`,
  /// which `canPop()` does not.
  bool _frameworkHandlesBack() =>
      _navigatorHandlesBack(_rootKey) ||
      _navigatorHandlesBack(_topNavigatorKey()) ||
      _state.active.hasDetail ||
      _backLeadsToBranch();

  bool _backLeadsToBranch() =>
      shellConfig.backToBranch != null &&
      _state.activeBranch != shellConfig.backToBranch;

  bool _navigatorHandlesBack(GlobalKey<NavigatorState> key) =>
      (key.currentState?.canPop() ?? false) || (_canHandlePop[key] ?? false);

  /// Swallows a navigator's report. `WidgetsApp` passes the last one on to
  /// Android, and with several navigators mounted the last one is often wrong:
  /// an empty detail says "no" and back closes the app.
  bool _handleNavigationNotification(
    GlobalKey<NavigatorState> navigator,
    NavigationNotification notification,
  ) {
    _canHandlePop[navigator] = notification.canHandlePop;
    // A `Navigator` dispatches after the frame, so no need to schedule.
    _backReporterKey.currentState?.report();
    return true;
  }

  /// System back.
  ///
  /// The root navigator goes first: a dialog or the shell drawer sits over
  /// every branch.
  ///
  /// Then the branch's own `Navigator`, or we would remove the top
  /// screen behind its `PopScope` — and a screen may intercept back for a
  /// reason. `maybePop` also serves guarded entries, whose `PopScope` routes
  /// the decision back here, and it returns `true` even when the screen refused
  /// the pop: back counts as handled and the app is not backgrounded.
  ///
  /// Last, at another branch's root, the switch to
  /// [AdaptiveShellConfig.backToBranch], gated like a tab tap.
  @override
  Future<bool> popRoute() async {
    final NavigatorState? root = _rootKey.currentState;
    if (root != null && root.canPop()) {
      await root.maybePop();
      return true;
    }
    final NavigatorState? nav = _topNavigatorKey().currentState;
    if (nav != null && await _systemMaybePop(nav)) {
      return true;
    }
    if (_state.active.entries.length > 1) {
      await pop();
      return true; // back handled, even if the gate refused
    }
    if (_backLeadsToBranch()) {
      await goBranch(shellConfig.backToBranch!);
      return true; // handled, even if the gate refused
    }
    return false; // nothing to pop — hand it to the system
  }

  /// Up during system back's `maybePop`, which reaches [_guardedPop] before it
  /// completes. Only system back may leave the app from there.
  bool _inSystemBack = false;

  Future<bool> _systemMaybePop(NavigatorState nav) async {
    _inSystemBack = true;
    try {
      return await nav.maybePop();
    } finally {
      _inSystemBack = false;
    }
  }

  /// A location names one screen, so only its branch changes. A screen already
  /// in the stack is cut back to and keeps its page and `push` future; any
  /// other goes on the root. Cut screens are not gated, as a link is not a
  /// request to leave them. `redirect` sees the merged state.
  @override
  Future<void> setNewRoutePath(NavState<R> configuration) async {
    _initialRedirectPending = false;
    final int branch = configuration.activeBranch;
    final NavEntry<R> located = configuration.branches[branch].top;
    final List<NavEntry<R>> current = _state.branches[branch].entries;
    final int at = located.route == current.first.route
        ? 0
        : current.lastIndexWhere((NavEntry<R> e) => e.route == located.route);
    final NavState<R> merged = _state
        .copyWith(activeBranch: branch)
        .withBranch(
          branch,
          BranchStack<R>(
            at < 0
                ? <NavEntry<R>>[current.first, located]
                : current.sublist(0, at + 1),
          ),
        );
    _apply(shellConfig.redirect?.call(merged) ?? merged);
  }

  /// Re-runs `redirect` against the current state. Call it when the session
  /// changes; this is the equivalent of `refreshListenable`.
  ///
  /// A state that did not change does not wake listeners, or every hiccup of a
  /// session provider would rebuild the `Router`.
  void reevaluate() {
    final NavState<R>? next = shellConfig.redirect?.call(_state);
    if (next != null) {
      _initialRedirectPending = false;
    }
    if (next == null || next == _state) {
      return;
    }
    _apply(next);
  }

  /// Only fires for an imperative pop inside a `Navigator`; declarative
  /// removals never reach here. Idempotent, and the root is never removed this
  /// way.
  void _handleDidRemovePage(Page<Object?> page) {
    for (int b = 0; b < _state.branches.length; b++) {
      final BranchStack<R> stack = _state.branches[b];
      final int idx = stack.entries.indexWhere(
        (NavEntry<R> e) => e.pageKey == page.key,
      );
      if (idx <= 0) {
        continue;
      }
      final List<NavEntry<R>> next = List<NavEntry<R>>.of(stack.entries)
        ..removeAt(idx);
      _apply(_state.withBranch(b, BranchStack<R>(next)));
      return;
    }
  }

  /// The start's `redirect`, mid-build: this build shows it, no one notified.
  void _applyInitialRedirect() {
    _initialRedirectPending = false;
    final NavState<R>? next = shellConfig.redirect?.call(_state);
    if (next == null || _disposed) {
      return;
    }
    final NavState<R> previous = _state;
    _state = next;
    _completeDropped(previous, next);
  }

  @override
  Widget build(BuildContext context) {
    if (_initialRedirectPending) {
      _applyInitialRedirect();
    }
    // After the start's `redirect`, so a branch it leaves is never built.
    _mountedBranches.add(_state.activeBranch);
    return _BackReporter(
      key: _backReporterKey,
      frameworkHandlesBack: _frameworkHandlesBack,
      child: NotificationListener<NavigationNotification>(
        onNotification: (NavigationNotification n) =>
            _handleNavigationNotification(_rootKey, n),
        child: _buildRootNavigator(),
      ),
    );
  }

  Widget _buildRootNavigator() {
    return Navigator(
      key: _rootKey,
      onDidRemovePage: (_) {}, // a single page, which is never removed
      pages: <Page<Object?>>[
        MaterialPage<Object?>(
          key: const ValueKey<String>('adaptive-nav.root-shell'),
          child: AdaptiveShell<R>(
            state: _state,
            shellConfig: shellConfig,
            branchKeys: _branchKeys,
            branchFadeKey: _branchFadeKey,
            masterMessengerKey: _masterMessengerKey,
            detailMessengerKey: _detailMessengerKey,
            mountedBranches: _mountedBranches,
            chrome: shellConfig.showsChrome?.call(_state) ?? true,
            onSelectBranch: goBranch,
            buildPage:
                (
                  BranchConfig<R> config,
                  NavEntry<R> entry, {
                  int detailIndex = -1,
                }) => buildEntryPage<R>(
                  config,
                  entry,
                  onGuardedPop: _guardedPop,
                  detailIndex: detailIndex,
                ),
            onDidRemovePage: _handleDidRemovePage,
            onNavigationNotification: _handleNavigationNotification,
            // The drawer's local history entry sends no notification.
            onDrawerChanged: (_) => _backReporterKey.currentState?.schedule(),
            immersive: _ownedImmersive ?? shellConfig.immersive,
            paneSplit: _ownedPaneSplit ?? shellConfig.paneSplit,
          ),
        ),
      ],
    );
  }
}

/// The whole router as one object: the [RouterConfig] for
/// `MaterialApp.router(routerConfig: nav)` and the navigation API.
///
/// It is not a `Listenable`, so it can live in a Riverpod provider checked by
/// `riverpod_lint`. It creates everything that notifies and releases it in
/// [dispose]. An app that builds the `Router` itself can still use
/// [AdaptiveRouterDelegate] and [AdaptiveRouteInformationParser].
class AdaptiveNav<R> implements RouterConfig<NavState<R>> {
  /// [codec] enables URLs and deep links; without it the platform's location
  /// is ignored. [initialLocation] overrides the platform's default route.
  /// [immersive] is the initial [AdaptiveNav.immersive]; `null` turns the mode
  /// off. [resizablePanes] makes the pane boundary draggable: [paneFractions]
  /// seeds saved widths, [onPaneCommit] fires on release, and a later async
  /// read goes to `paneSplit.restore`.
  AdaptiveNav({
    required AdaptiveShellConfig<R> shellConfig,
    required NavState<R> initialState,
    RouteCodec<R>? codec,
    String? initialLocation,
    bool? immersive,
    bool resizablePanes = false,
    Map<Object, double>? paneFractions,
    void Function(Object branchId, double fraction)? onPaneCommit,
  }) : assert(
         immersive == null || shellConfig.immersive == null,
         'immersive is given both here and in shellConfig',
       ),
       assert(
         !resizablePanes || shellConfig.paneSplit == null,
         'resizablePanes is set while shellConfig has its own paneSplit',
       ),
       assert(
         resizablePanes || (paneFractions == null && onPaneCommit == null),
         'paneFractions and onPaneCommit need resizablePanes: true',
       ),
       assert(
         codec != null || initialLocation == null,
         'initialLocation needs a codec',
       ),
       routerDelegate = AdaptiveRouterDelegate<R>(
         shellConfig: shellConfig,
         initialState: initialState,
       ),
       routeInformationParser = codec == null
           ? null
           : AdaptiveRouteInformationParser<R>(
               codec: codec,
               baseState: initialState,
               shellConfig: shellConfig,
             ),
       _codec = codec,
       _initialLocation = initialLocation,
       _immersive = immersive == null ? null : ValueNotifier<bool>(immersive),
       _paneSplit = resizablePanes
           ? PaneSplitController(initial: paneFractions, onCommit: onPaneCommit)
           : null {
    routerDelegate
      .._ownedImmersive = _immersive
      .._ownedPaneSplit = _paneSplit;
  }

  @override
  final AdaptiveRouterDelegate<R> routerDelegate;

  @override
  final AdaptiveRouteInformationParser<R>? routeInformationParser;

  final RouteCodec<R>? _codec;
  final String? _initialLocation;
  PlatformRouteInformationProvider? _provider;

  /// `WidgetsApp` makes none for a `RouterConfig`. Created on first read, as
  /// the constructor may run before `runApp` and the binding.
  @override
  PlatformRouteInformationProvider? get routeInformationProvider {
    if (_codec == null) return null;
    return _provider ??= PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(
        uri: Uri.parse(
          _initialLocation ??
              WidgetsBinding.instance.platformDispatcher.defaultRouteName,
        ),
      ),
    );
  }

  /// What `WidgetsApp` gives a bare delegate; `Router.withConfig` has none.
  @override
  final BackButtonDispatcher backButtonDispatcher = RootBackButtonDispatcher();

  final ValueNotifier<bool>? _immersive;
  final PaneSplitController? _paneSplit;

  NavState<R> get state => routerDelegate.state;

  /// Messenger of the active branch's master pane, `null` until the shell has
  /// been built.
  ScaffoldMessengerState? get masterMessenger => routerDelegate.masterMessenger;

  /// Messenger of the active branch's detail pane.
  ScaffoldMessengerState? get detailMessenger => routerDelegate.detailMessenger;

  /// See [AdaptiveRouterDelegate.push].
  Future<Object?> push(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) => routerDelegate.push(route, transition: transition, onExit: onExit);

  /// See [AdaptiveRouterDelegate.pop].
  Future<bool> pop() => routerDelegate.pop();

  /// See [AdaptiveRouterDelegate.popWithResult].
  void popWithResult<T extends Object?>(T result) =>
      routerDelegate.popWithResult<T>(result);

  /// See [AdaptiveRouterDelegate.replace].
  Future<void> replace(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) => routerDelegate.replace(route, transition: transition, onExit: onExit);

  /// See [AdaptiveRouterDelegate.resetTo].
  Future<void> resetTo(R route) => routerDelegate.resetTo(route);

  /// See [AdaptiveRouterDelegate.resetDetailTo].
  Future<void> resetDetailTo(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) => routerDelegate.resetDetailTo(
    route,
    transition: transition,
    onExit: onExit,
  );

  /// See [AdaptiveRouterDelegate.popToRoot].
  Future<void> popToRoot() => routerDelegate.popToRoot();

  /// See [AdaptiveRouterDelegate.goBranch].
  Future<void> goBranch(int index, {bool resetToRoot = false}) =>
      routerDelegate.goBranch(index, resetToRoot: resetToRoot);

  /// See [AdaptiveRouterDelegate.reevaluate].
  void reevaluate() => routerDelegate.reevaluate();

  /// Whether the rail is slid out of the wide layout; always `false` with the
  /// mode off. Setting it needs `immersive:` in the constructor.
  bool get immersive => _immersive?.value ?? false;

  set immersive(bool value) {
    final ValueNotifier<bool>? notifier = _immersive;
    assert(
      notifier != null,
      'Immersive mode is off: pass immersive: to the AdaptiveNav constructor',
    );
    notifier?.value = value;
  }

  /// The pane widths with `resizablePanes: true`. Owned here; do not dispose.
  PaneSplitController? get paneSplit => _paneSplit;

  /// Releases everything created here, once the app showing it is gone.
  void dispose() {
    routerDelegate.dispose();
    _provider?.dispose();
    _immersive?.dispose();
    _paneSplit?.dispose();
  }
}

/// Tells `WidgetsApp` whether the shell handles system back, for all of its
/// navigators at once.
///
/// Every report is a full recount, so whichever runs last is right. Equal
/// values are sent again: `WidgetsApp` drops reports until it has a lifecycle
/// state.
class _BackReporter extends StatefulWidget {
  const _BackReporter({
    required this.frameworkHandlesBack,
    required this.child,
    super.key,
  });

  final bool Function() frameworkHandlesBack;
  final Widget child;

  @override
  State<_BackReporter> createState() => _BackReporterState();
}

class _BackReporterState extends State<_BackReporter> {
  bool _scheduled = false;

  /// Reports once the current frame is done, and makes sure there is one.
  void schedule() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _scheduled = false;
      report();
    }, debugLabel: 'AdaptiveRouterDelegate.reportBack');
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void report() {
    if (!mounted) {
      return;
    }
    NavigationNotification(
      canHandlePop: widget.frameworkHandlesBack(),
    ).dispatch(context);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt on every state change; a tab switch makes no navigator report.
    schedule();
    return widget.child;
  }
}
