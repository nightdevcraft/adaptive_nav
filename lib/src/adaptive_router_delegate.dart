import 'dart:async';

import 'package:flutter/material.dart';

import 'adaptive_shell.dart';
import 'entry_page.dart';
import 'nav_config.dart';
import 'nav_state.dart';

/// Holds the [NavState] and exposes the navigation API.
///
/// One instance for the whole app, never recreated on resize. Together with the
/// stable navigator keys in [BranchNavigatorKeys] that is what preserves the
/// screens when the layout changes.
///
/// Every way out of a screen goes through one [NavExitGuard] gate, tab switches
/// included.
class AdaptiveRouterDelegate<R> extends RouterDelegate<NavState<R>>
    with ChangeNotifier {
  AdaptiveRouterDelegate({
    required this.shellConfig,
    required NavState<R> initialState,
  }) : _state = initialState {
    _branchKeys = <BranchNavigatorKeys>[
      for (int i = 0; i < shellConfig.branches.length; i++)
        BranchNavigatorKeys(),
    ];
    _mountedBranches.add(initialState.activeBranch);
  }

  final AdaptiveShellConfig<R> shellConfig;
  NavState<R> _state;
  late final List<BranchNavigatorKeys> _branchKeys;

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

  NavState<R> get state => _state;

  Set<int> get mountedBranches => _mountedBranches;

  @override
  NavState<R> get currentConfiguration => _state;

  void _apply(NavState<R> next) {
    _state = next;
    _mountedBranches.add(next.activeBranch);
    notifyListeners();
  }

  // ---------------------------------------------------------------- API

  /// Pushes a screen onto the active branch. The future completes with the
  /// value from [popWithResult], or `null` on a plain pop.
  Future<Object?> push(
    R route, {
    AppTransition? transition,
    NavExitGuard? onExit,
  }) {
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

  /// Pops the top screen through the gate. `false` — refused, or already at the
  /// root.
  Future<bool> pop() async {
    final BranchStack<R> stack = _state.active;
    if (stack.entries.length <= 1) {
      return false;
    }
    final NavEntry<R> top = stack.top;
    if (!await _guard(top)) {
      return false;
    }
    _completeEntry(top, null);
    _apply(_state.withActiveStack(stack.pop()));
    return true;
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
    final BranchStack<R> stack = _state.active;
    final NavEntry<R> top = stack.top;
    if (stack.entries.length > 1 && !await _guard(top)) {
      return;
    }
    final BranchConfig<R> cfg = shellConfig.branches[_state.activeBranch];
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: transition ?? cfg.transition,
      onExit: onExit,
    );
    _completeEntry(top, null);
    _apply(_state.withActiveStack(stack.replaceTop(entry)));
  }

  /// Resets the active branch to [route] as its only screen, gating everything
  /// removed.
  Future<void> resetTo(R route) async {
    final BranchStack<R> stack = _state.active;
    if (!await _guardAll(stack.entries)) {
      return;
    }
    for (final NavEntry<R> e in stack.entries) {
      _completeEntry(e, null);
    }
    final BranchConfig<R> cfg = shellConfig.branches[_state.activeBranch];
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: cfg.transition,
    );
    _apply(_state.withActiveStack(BranchStack<R>(<NavEntry<R>>[entry])));
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
    final BranchStack<R> stack = _state.branches[branch];
    final List<NavEntry<R>> removed = stack.entries.sublist(1);
    if (!await _guardAll(removed)) {
      return;
    }
    for (final NavEntry<R> e in removed) {
      _completeEntry(e, null);
    }
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: transition ?? shellConfig.branches[branch].transition,
      onExit: onExit,
    );
    _apply(
      _state.withBranch(
        branch,
        BranchStack<R>(<NavEntry<R>>[_state.branches[branch].root, entry]),
      ),
    );
  }

  /// Back to the branch root, gating everything above it.
  Future<void> popToRoot() async {
    final BranchStack<R> stack = _state.active;
    if (stack.entries.length <= 1) {
      return;
    }
    final List<NavEntry<R>> removed = stack.entries.sublist(1);
    if (!await _guardAll(removed)) {
      return;
    }
    for (final NavEntry<R> e in removed) {
      _completeEntry(e, null);
    }
    _apply(_state.withActiveStack(stack.resetToRoot()));
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
  Future<void> goBranch(int index, {bool resetToRoot = false}) async {
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
    for (final NavEntry<R> e in guarded) {
      _completeEntry(e, null);
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

  void _guardedPop(NavEntry<R> entry) {
    _guard(entry).then((bool ok) {
      if (ok) {
        _removeEntry(entry);
      }
    });
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
      _completeEntry(stack.entries[idx], null);
      _apply(_state.withBranch(b, BranchStack<R>(next)));
      return;
    }
  }

  // --------------------------------------------------------- guard/util

  Future<bool> _guard(NavEntry<R> entry) async {
    final NavExitGuard? guard = entry.onExit;
    if (guard == null) {
      return true;
    }
    return guard();
  }

  Future<bool> _guardAll(Iterable<NavEntry<R>> entries) async {
    for (final NavEntry<R> e in entries) {
      if (!await _guard(e)) {
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
  NavigatorState? _topNavigator() {
    final BranchNavigatorKeys keys = _branchKeys[_state.activeBranch];
    final bool inDetail =
        shellConfig.branches[_state.activeBranch].masterDetail != null &&
        _state.active.entries.length > 1;
    return (inDetail ? keys.detail : keys.master).currentState;
  }

  /// System back.
  ///
  /// The branch's own `Navigator` gets it first, or we would remove the top
  /// screen behind its `PopScope` — and a screen may intercept back for a
  /// reason. `maybePop` also serves guarded entries, whose `PopScope` routes
  /// the decision back here, and it returns `true` even when the screen refused
  /// the pop: back counts as handled and the app is not backgrounded.
  @override
  Future<bool> popRoute() async {
    final NavigatorState? nav = _topNavigator();
    if (nav != null && await nav.maybePop()) {
      return true;
    }
    if (_state.active.entries.length > 1) {
      await pop();
      return true; // back handled, even if the gate refused
    }
    return false; // nothing to pop — hand it to the system
  }

  @override
  Future<void> setNewRoutePath(NavState<R> configuration) async {
    final NavState<R> next =
        shellConfig.redirect?.call(configuration) ?? configuration;
    _apply(next);
  }

  /// Re-runs `redirect` against the current state. Call it when the session
  /// changes; this is the equivalent of `refreshListenable`.
  ///
  /// A state that did not change does not wake listeners, or every hiccup of a
  /// session provider would rebuild the `Router`.
  void reevaluate() {
    final NavState<R>? next = shellConfig.redirect?.call(_state);
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
      final NavEntry<R> removed = stack.entries[idx];
      final List<NavEntry<R>> next = List<NavEntry<R>>.of(stack.entries)
        ..removeAt(idx);
      _completeEntry(removed, null);
      _apply(_state.withBranch(b, BranchStack<R>(next)));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          ),
        ),
      ],
    );
  }
}
