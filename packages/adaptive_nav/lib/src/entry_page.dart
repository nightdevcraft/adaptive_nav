import 'package:flutter/material.dart';

import 'nav_config.dart';
import 'nav_state.dart';
import 'pane_toolbar.dart';

/// The framework wants a guarded screen gone (system back, a gesture, the app
/// bar). The delegate awaits `onExit` and only then removes the entry.
typedef GuardedPopHandler<R> = void Function(NavEntry<R> entry);

/// Builds the `Page` for [entry].
///
/// [detailIndex] is the screen's position in the branch's detail stack: `0` is
/// the first detail, `1+` is pushed on top of it, `-1` is a page of the main
/// navigator. It travels into [DetailEntryScope].
Page<Object?> buildEntryPage<R>(
  BranchConfig<R> config,
  NavEntry<R> entry, {
  required GuardedPopHandler<R> onGuardedPop,
  int detailIndex = -1,
}) {
  final Widget content = _EntryPopScope<R>(
    entry: entry,
    onGuardedPop: onGuardedPop,
    child: DetailEntryScope(
      index: detailIndex,
      child: AutomaticPaneBack(child: config.pageBuilder(entry.route)),
    ),
  );
  switch (entry.transition) {
    case AppTransition.platform:
      return _MaterialPage<Object?>(key: entry.pageKey, child: content);
    case AppTransition.modal:
      return _MaterialPage<Object?>(
        key: entry.pageKey,
        fullscreenDialog: true,
        child: content,
      );
    case AppTransition.fade:
      return _FadePage<Object?>(key: entry.pageKey, child: content);
    case AppTransition.none:
      return _NoTransitionPage<Object?>(key: entry.pageKey, child: content);
    case AppTransition.adaptive:
      return _AdaptivePage<Object?>(key: entry.pageKey, child: content);
  }
}

/// The entry's own `PopScope`.
///
/// A guarded entry blocks the pop here and hands the decision to the delegate;
/// an unguarded one is synchronised by `onDidRemovePage`.
///
/// A screen of a branch that is not active blocks it too. Inactive branches
/// stay mounted, and Android's predictive back goes to every current route
/// whose `popGestureEnabled` is true — one per navigator, not one per app — so
/// a single gesture used to close the top screen of every branch. A route
/// with a pop entry that cannot pop turns its gesture off, the same switch a
/// screen's own `PopScope` uses. See "One answer for system back" in
/// doc/design.md.
class _EntryPopScope<R> extends StatelessWidget {
  const _EntryPopScope({
    required this.entry,
    required this.onGuardedPop,
    required this.child,
  });

  final NavEntry<R> entry;
  final GuardedPopHandler<R> onGuardedPop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool guarded = entry.onExit != null;
    return PopScope<Object?>(
      canPop: !guarded && BranchActiveScope.of(context),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // Also called when the screen's own `PopScope` or the inactive branch
        // blocks pop; an unguarded entry then stays.
        if (didPop || !guarded) {
          return;
        }
        onGuardedPop(entry);
      },
      child: child,
    );
  }
}

/// Whether the branch whose navigator is below is the active one.
///
/// The shell puts it above every branch navigator; the screens' pop scopes
/// read it, so only the active branch takes system back.
class BranchActiveScope extends InheritedWidget {
  const BranchActiveScope({
    required this.active,
    required super.child,
    super.key,
  });

  final bool active;

  /// `true` outside the scope: a screen rendered without the shell pops as
  /// usual.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BranchActiveScope>()?.active ??
      true;

  @override
  bool updateShouldNotify(BranchActiveScope oldWidget) =>
      oldWidget.active != active;
}

/// How the branch's detail is presented: in its own pane next to the master
/// (`true`) or across the whole available area (`false`).
///
/// The shell puts it above the detail navigators, so screens read the layout
/// the shell actually chose instead of recomputing it from `MediaQuery` and
/// disagreeing at the boundary.
class DetailPaneScope extends InheritedWidget {
  const DetailPaneScope({
    required this.inPane,
    required super.child,
    super.key,
  });

  final bool inPane;

  /// `false` outside the scope, where a screen fills the whole area anyway.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailPaneScope>()?.inPane ??
      false;

  /// A detail shown across the whole area rather than in a pane.
  ///
  /// Not the same as `!of(context)`, which is also true outside the scope. A
  /// screen needs this when it has to lay itself out differently: in the
  /// compact layout a detail covers the navigation bar, so its bottom edge
  /// becomes its own business.
  static bool isFullScreen(BuildContext context) {
    final DetailPaneScope? scope = context
        .dependOnInheritedWidgetOfExactType<DetailPaneScope>();
    return scope != null && !scope.inPane;
  }

  @override
  bool updateShouldNotify(DetailPaneScope oldWidget) =>
      oldWidget.inPane != inPane;
}

/// The screen's position in the branch's detail stack. An app bar reads it to
/// choose between a close button and a back arrow.
///
/// `Navigator.canPop()` cannot answer that: a transparent base page always sits
/// under the detail, so it is poppable whether it is the first screen or the
/// tenth. The depth is known only to the shell, which is what spreads the
/// branch stack across two navigators.
class DetailEntryScope extends InheritedWidget {
  const DetailEntryScope({
    required this.index,
    required super.child,
    super.key,
  });

  /// `-1` — not a detail; `0` — the first detail; `1+` — pushed deeper.
  final int index;

  /// The branch's first detail: in the wide layout it fills the pane, and a
  /// close button dismisses it.
  ///
  /// `false` outside the scope, so a screen rendered without the shell gets its
  /// back arrow from the `AppBar` as usual.
  static bool isDetailRoot(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailEntryScope>()?.index ==
      0;

  @override
  bool updateShouldNotify(DetailEntryScope oldWidget) =>
      oldWidget.index != index;
}

/// Whether [route] has something to dismiss to, for a navigation button the
/// shell or a [PaneToolbar] draws: `impliesAppBarDismissal` as the framework
/// has it, before a route of this package withholds it from the `AppBar`.
bool routeImpliesDismissal(ModalRoute<Object?> route) =>
    route is _AutomaticBackRoute<Object?>
    ? route._impliesDismissal
    : route.impliesAppBarDismissal;

/// Keeps the `AppBar` of a screen from drawing a back arrow while the pane's
/// toolbar is vertical: the shell stands the screen's navigation button in
/// the system's column then ([AutomaticPaneBack]), and an arrow in the header
/// would be a second one.
///
/// `impliesAppBarDismissal` is the framework's own switch for it, read by
/// the `AppBar` through `ModalRoute.of`. Whenever the shell rebuilds a
/// pane's navigator — a change of pose is one — the navigator has its
/// routes rebuild their scopes (`changedExternalState`), which read it
/// again; the header follows the bar without a frame's delay. An `AppBar`
/// with a `leading` of its own does not look at it.
mixin _AutomaticBackRoute<T> on ModalRoute<T> {
  bool get _impliesDismissal => super.impliesAppBarDismissal;

  // No dependency registered, as with `_inPane`: the navigator is rebuilt
  // with the bar, and that rebuilds the route's scope.
  bool get _backInColumn {
    final BuildContext? nav = navigator?.context;
    if (nav == null ||
        !(nav.getInheritedWidgetOfExactType<PaneToolbarHost>()?.automaticBack ??
            false)) {
      return false;
    }
    return nav.getInheritedWidgetOfExactType<PaneBarScope>()?.bar.isVertical ??
        false;
  }

  @override
  bool get impliesAppBarDismissal => _impliesDismissal && !_backInColumn;
}

/// `MaterialPage`, with a route that withholds its arrow from the `AppBar`
/// while the column has it ([_AutomaticBackRoute]).
///
/// A subclass of the framework's page and route rather than one of their own,
/// so `page is MaterialPage` and `ModalRoute.of(context) is MaterialPageRoute`
/// hold as they did, and the theme's `pageTransitionsTheme` applies.
class _MaterialPage<T> extends MaterialPage<T> {
  const _MaterialPage({
    required LocalKey super.key,
    required super.child,
    super.fullscreenDialog,
  });

  @override
  Route<T> createRoute(BuildContext context) => _MaterialRoute<T>(this);
}

/// Builds nothing: the routes below take their content from their page in
/// `buildContent`, as the framework's page-based route does, so that an
/// updated page is shown without a new route.
Widget _fromPage(BuildContext context) =>
    throw StateError('The content is the page\'s child.');

class _MaterialRoute<T> extends MaterialPageRoute<T>
    with _AutomaticBackRoute<T> {
  _MaterialRoute(MaterialPage<T> page)
    : super(
        builder: _fromPage,
        settings: page,
        maintainState: page.maintainState,
        fullscreenDialog: page.fullscreenDialog,
        allowSnapshotting: page.allowSnapshotting,
      );

  // `Navigator` swaps the route's settings when a page is updated, so read the
  // current ones rather than caching a field.
  MaterialPage<T> get _page => settings as MaterialPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;
}

/// `PageRouteBuilder`, with [_AutomaticBackRoute].
class _BuiltRoute<T> extends PageRouteBuilder<T> with _AutomaticBackRoute<T> {
  _BuiltRoute({
    required super.settings,
    required super.pageBuilder,
    super.transitionsBuilder,
    super.transitionDuration,
    super.reverseTransitionDuration,
  });
}

/// Base page of an empty detail navigator. A `Navigator` cannot exist without
/// pages, and `opaque: false` lets the master show through.
Page<Object?> emptyDetailPage() => const _EmptyDetailPage();

class _EmptyDetailPage extends Page<Object?> {
  const _EmptyDetailPage()
    : super(key: const ValueKey<String>('adaptive-nav.detail-empty'));

  @override
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
    settings: this,
    opaque: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => const SizedBox.expand(),
  );
}

class _FadePage<T> extends Page<T> {
  const _FadePage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _BuiltRoute<T>(
    settings: this,
    pageBuilder: (_, _, _) => child,
    transitionsBuilder: (_, Animation<double> animation, _, Widget c) =>
        FadeTransition(opacity: animation, child: c),
  );
}

/// A detail page whose transition follows the current layout.
///
/// One page type at every width, which is the point: `Navigator` compares pages
/// by type and key, so a resize updates the mounted route instead of recreating
/// it. `transitionsBuilder` does the rest.
class _AdaptivePage<T> extends MaterialPage<T> {
  const _AdaptivePage({required LocalKey super.key, required super.child});

  @override
  Route<T> createRoute(BuildContext context) => _AdaptiveRoute<T>(this);
}

/// Full screen this is a `MaterialPageRoute` like any other — the platform
/// transition, the iOS back gesture and the synchronised exit of the screen
/// below. In a pane it fades.
class _AdaptiveRoute<T> extends _MaterialRoute<T> {
  _AdaptiveRoute(_AdaptivePage<T> super.page);

  /// Shorter than the platform transition (450 ms on Android, 500 on iOS): a
  /// pane swapping its contents should read together with its reveal.
  static const Duration paneFadeDuration = Duration(milliseconds: 300);

  // No dependency registered: this is read by the duration getters, not by
  // build, and there is no reason to subscribe the navigator to the layout.
  bool get _inPane {
    final BuildContext? nav = navigator?.context;
    return nav?.getInheritedWidgetOfExactType<DetailPaneScope>()?.inPane ??
        false;
  }

  // The mixin refreshes durations in didPush/didPop too, so a dismissal uses
  // the duration of the current layout.
  @override
  Duration get transitionDuration =>
      _inPane ? paneFadeDuration : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _inPane ? paneFadeDuration : super.reverseTransitionDuration;

  /// Called on every frame of a transition, the reverse one included, so the
  /// decision follows the current layout rather than the one at push time.
  /// Swapping the wrapper does not recreate the content; it is cached under the
  /// route's own key.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!DetailPaneScope.of(context)) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    // `secondaryAnimation` ignored on purpose: going deeper must not push the
    // card away, the arriving screen fades in over it.
    return FadeTransition(opacity: animation, child: child);
  }
}

class _NoTransitionPage<T> extends Page<T> {
  const _NoTransitionPage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _BuiltRoute<T>(
    settings: this,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => child,
  );
}
