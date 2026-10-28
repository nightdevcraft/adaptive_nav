import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A back gesture under way: [route] is being taken off, [previous] is what
/// it leads back to.
typedef ColumnGesture = ({Route<Object?> route, Route<Object?>? previous});

/// The route transitions of the shell's navigators, for the system's column
/// to follow.
///
/// What the column shows changes with a screen, and a screen comes and goes
/// with its route's transition. So the column's content goes with that
/// transition, as the items of `UINavigationBar` go with a push: what leaves
/// fades out over the first half of it, what arrives fades in over the
/// second, and a back gesture holds the column where the finger holds the
/// screen.
///
/// Every navigator of the shell reports here through its own observer
/// ([observerFor]). A change of the column takes a [ColumnDrive]
/// ([driveForChange]) and settles on the transition behind it only when the
/// column is painted: the column is built before some of the navigators are,
/// and by paint every one of them has reported.
class ColumnTransitions extends ChangeNotifier {
  final Map<GlobalKey<NavigatorState>, _ColumnObserver> _observers =
      <GlobalKey<NavigatorState>, _ColumnObserver>{};

  /// The transition reported during the current frame, or `null` for a
  /// change without one — `AppTransition.none`, a removal, the end of a back
  /// gesture.
  ({_Transition? transition})? _thisFrame;

  /// The last transition with a progress, which a change can still join
  /// while it runs.
  _Transition? _running;

  /// The drives a finger holds: they go on from where it left them once the
  /// gesture pops its route.
  final Set<ColumnDrive> _held = <ColumnDrive>{};
  bool _disposed = false;

  /// The back gesture under way on the screen of the page keyed [page]. One
  /// gesture may start on several navigators at once — every route whose
  /// predictive back is enabled takes it, an inactive tab's detail as well —
  /// so each navigator's is kept apart, and the shell asks for the active
  /// pane's top screen.
  ColumnGesture? gestureOn(LocalKey page) {
    for (final _ColumnObserver observer in _observers.values) {
      final ColumnGesture? gesture = observer.gesture;
      final Object? settings = gesture?.route.settings;
      if (settings is Page<Object?> && settings.key == page) {
        return gesture;
      }
    }
    return null;
  }

  /// The route on top of [navigator], as its observer has seen the routes
  /// come and go; `null` before it has built. A navigator has no public way
  /// to name it.
  Route<Object?>? topOf(GlobalKey<NavigatorState> navigator) {
    final List<Route<Object?>>? routes = _observers[navigator]?.routes;
    return routes == null || routes.isEmpty ? null : routes.last;
  }

  /// The observer for [navigator]; one each, as a `NavigatorObserver` serves
  /// one navigator.
  NavigatorObserver observerFor(GlobalKey<NavigatorState> navigator) =>
      _observers.putIfAbsent(navigator, () => _ColumnObserver(this));

  /// The drive of a change made now. It settles on this frame's transition,
  /// or on one still running, the first time it is read; with neither, the
  /// change is immediate.
  ColumnDrive driveForChange() => ColumnDrive._pending(this);

  bool _isGesture(Animation<double>? progress) =>
      progress != null &&
      _observers.values.any(
        (_ColumnObserver o) => identical(o.gestureProgress, progress),
      );

  /// This frame's transition, or the one still running. A change that joins
  /// a running one late — a screen registers its toolbar a frame after its
  /// route is pushed — keeps to it from where it started, so the column's
  /// halves stay the transition's halves.
  _Transition? _transitionForChange() {
    final ({_Transition? transition})? frame = _thisFrame;
    if (frame != null) {
      return frame.transition;
    }
    final _Transition? running = _running;
    return running != null &&
            (running.progress.isAnimating || _isGesture(running.progress))
        ? running
        : null;
  }

  void _routeChanged(
    _ColumnObserver observer,
    Route<Object?>? route, {
    required bool forward,
  }) {
    final Animation<double>? held = observer.gestureProgress;
    if (!forward && held != null && identical(route, observer.gesture?.route)) {
      _gestureCommitted(held);
      return;
    }
    final Animation<double>? animation = route is TransitionRoute<Object?>
        ? route.animation
        : null;
    _report(
      animation == null || !animation.isAnimating
          ? null
          : forward
          ? animation
          : ReverseAnimation(animation),
    );
  }

  /// The finger has let go past the point of no return and the route pops.
  /// The pop may start its animation over — predictive back runs it again
  /// from the top — so the column goes on from where the finger left it.
  void _gestureCommitted(Animation<double> held) {
    final double from = held.value;
    final _Resumed rest = _Resumed(held, from: from);
    for (final ColumnDrive drive in <ColumnDrive>[..._held]) {
      if (identical(drive._source, held)) {
        drive._rebind(rest);
        _held.remove(drive);
      }
    }
    _report(rest, start: from);
  }

  /// One frame may report several transitions — a push and the removal
  /// below it, a pop to the root. The one with a progress is the one the
  /// screen shows.
  void _report(Animation<double>? progress, {double? start}) {
    if (_thisFrame == null) {
      SchedulerBinding.instance
        ..addPostFrameCallback(
          (Duration _) => _thisFrame = null,
          debugLabel: 'ColumnTransitions.frame',
        )
        ..ensureVisualUpdate();
    }
    final _Transition? transition = progress == null
        ? null
        : (progress: progress, start: start ?? progress.value);
    if (transition != null || _thisFrame == null) {
      _thisFrame = (transition: transition);
    }
    if (transition != null) {
      _running = transition;
    }
  }

  void _gestureStarted(
    _ColumnObserver observer,
    Route<Object?> route,
    Route<Object?>? previous,
  ) {
    final Animation<double>? animation = route is TransitionRoute<Object?>
        ? route.animation
        : null;
    if (animation == null) {
      return;
    }
    final Animation<double> progress = ReverseAnimation(animation);
    observer
      ..gesture = (route: route, previous: previous)
      ..gestureProgress = progress;
    _report(progress);
    _notify();
  }

  void _gestureStopped(_ColumnObserver observer) {
    final Animation<double>? progress = observer.gestureProgress;
    if (progress == null) {
      return;
    }
    observer
      ..gesture = null
      ..gestureProgress = null;
    _held.removeWhere((ColumnDrive d) => identical(d._source, progress));
    // Cancelled, the column goes back at once: the finger has already
    // brought it there. Completed, the pop has reported its own transition.
    _report(null);
    _notify();
  }

  void _notify() => runOutsideBuild(() {
    if (!_disposed) {
      notifyListeners();
    }
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A route's progress towards what its navigator shows now, and where it
/// stood when the transition began.
typedef _Transition = ({Animation<double> progress, double start});

/// Runs [callback] now, or after the frame where widgets are being built,
/// laid out or painted and must not be marked.
void runOutsideBuild(VoidCallback callback) {
  final SchedulerBinding binding = SchedulerBinding.instance;
  if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
    callback();
    return;
  }
  binding
    ..addPostFrameCallback(
      (Duration _) => callback(),
      debugLabel: 'ColumnTransitions.notify',
    )
    ..ensureVisualUpdate();
}

class _ColumnObserver extends NavigatorObserver {
  _ColumnObserver(this._owner);

  final ColumnTransitions _owner;

  /// The back gesture under way on this navigator, and its progress.
  ColumnGesture? gesture;
  Animation<double>? gestureProgress;

  /// The navigator's routes, bottom to top. A page's route is pushed as the
  /// navigator first builds it, so the first pages are here too.
  final List<Route<Object?>> routes = <Route<Object?>>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    routes.add(route);
    _owner._routeChanged(this, route, forward: true);
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    routes.remove(route);
    _owner._routeChanged(this, route, forward: false);
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    routes.remove(route);
    _owner._report(null);
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    final int at = routes.indexOf(oldRoute!);
    if (at < 0) {
      routes.add(newRoute!);
    } else {
      routes[at] = newRoute!;
    }
    _owner._routeChanged(this, newRoute, forward: true);
  }

  @override
  void didStartUserGesture(
    Route<Object?> route,
    Route<Object?>? previousRoute,
  ) => _owner._gestureStarted(this, route, previousRoute);

  @override
  void didStopUserGesture() => _owner._gestureStopped(this);
}

/// The progress of one change of the system's column, from what it showed
/// to what it shows now: 0 to 1.
///
/// A route's ([ColumnTransitions.driveForChange]) is [sequential]: what goes
/// fades out by its middle, what comes fades in after it, and nothing is
/// seen together. Read linearly — the route's animation is the transition's
/// progress before its curve, and a finger's position during a back
/// gesture. It starts from wherever the transition stands when the change
/// joins it, so the column never jumps.
///
/// A clock's ([ColumnDrive.clock]) is the column's own, for a tab switch,
/// which no route transition carries: both at once, as before.
class ColumnDrive extends Animation<double>
    with
        AnimationLocalListenersMixin,
        AnimationLocalStatusListenersMixin,
        AnimationEagerListenerMixin {
  ColumnDrive._pending(this._transitions) : sequential = true;

  /// Over [clock], already running.
  ColumnDrive.clock(Animation<double> clock)
    : _transitions = null,
      sequential = false,
      _resolved = true {
    _attach(clock);
  }

  /// A change already made.
  ColumnDrive.done() : _transitions = null, sequential = true, _resolved = true;

  final ColumnTransitions? _transitions;

  /// Whether what goes and what comes take a half each.
  final bool sequential;

  bool _resolved = false;
  Animation<double>? _source;
  double _start = 0;
  bool _settled = false;

  /// Called once the change is over for good, outside a build.
  VoidCallback? onSettled;

  /// The progress so far, without settling a change not yet painted: one
  /// that has not been is still where it started.
  double get peek => _resolved ? value : 0;

  /// Whether this change runs on the column's own clock and has not
  /// finished.
  bool get isClockRunning => !sequential && !_settled && _source != null;

  @override
  double get value {
    _resolve();
    final Animation<double>? source = _source;
    if (source == null) {
      return 1;
    }
    if (_start >= 1) {
      return 1;
    }
    return ((source.value - _start) / (1 - _start)).clamp(0.0, 1.0);
  }

  @override
  AnimationStatus get status => switch (value) {
    1 => AnimationStatus.completed,
    0 => AnimationStatus.dismissed,
    _ => AnimationStatus.forward,
  };

  void _resolve() {
    if (_resolved) {
      return;
    }
    _resolved = true;
    final _Transition? transition = _transitions?._transitionForChange();
    if (transition == null || transition.progress.value >= 1) {
      _settle();
      return;
    }
    _start = transition.start;
    _attach(transition.progress);
    if (_transitions!._isGesture(transition.progress)) {
      _transitions._held.add(this);
    }
  }

  void _attach(Animation<double> source) {
    _source = source;
    source.addListener(_tick);
  }

  /// Follows [source] instead, from the same start: it stands where the
  /// one before did.
  void _rebind(Animation<double> source) {
    _source?.removeListener(_tick);
    _attach(source);
  }

  void _tick() {
    notifyListeners();
    settleIfDone();
  }

  /// Settles a change that has reached its end and is not held there by a
  /// finger.
  void settleIfDone() {
    if (!_resolved || _settled || value < 1) {
      return;
    }
    if (_transitions?._isGesture(_source) ?? false) {
      return;
    }
    _settle();
  }

  void _settle() {
    if (_settled) {
      return;
    }
    _settled = true;
    _transitions?._held.remove(this);
    _source?.removeListener(_tick);
    _source = null;
    runOutsideBuild(() => onSettled?.call());
  }

  @override
  void dispose() {
    onSettled = null;
    _transitions?._held.remove(this);
    _source?.removeListener(_tick);
    _source = null;
    _settled = true;
    clearListeners();
    clearStatusListeners();
    super.dispose();
  }
}

/// What is left of a back gesture's progress once its route pops: from
/// [from], where the finger let go, to 1, over the pop's own animation from
/// wherever it starts.
class _Resumed extends Animation<double> with AnimationWithParentMixin<double> {
  _Resumed(this.parent, {required this.from});

  @override
  final Animation<double> parent;
  final double from;

  /// Where the pop's animation started: read once it has, after the pop.
  double? _start;

  @override
  double get value {
    final double start = _start ??= parent.value;
    if (start >= 1) {
      return 1;
    }
    final double rest = ((parent.value - start) / (1 - start)).clamp(0.0, 1.0);
    return from + (1 - from) * rest;
  }
}

/// [child] at [opacity] and moved down by [shift], both of [drive]'s
/// progress and both worked out as it is painted: a change of the column
/// does not rebuild anything frame by frame, and its drive settles once
/// every navigator has built.
class DrivenBox extends SingleChildRenderObjectWidget {
  const DrivenBox({
    required this.drive,
    required this.opacity,
    this.shift,
    super.child,
    super.key,
  });

  final Animation<double> drive;
  final double Function(double t) opacity;
  final double Function(double t)? shift;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDrivenBox(drive, opacity, shift);

  @override
  void updateRenderObject(BuildContext context, RenderDrivenBox renderObject) {
    renderObject
      ..drive = drive
      ..opacity = opacity
      ..shift = shift;
  }
}

class RenderDrivenBox extends RenderProxyBox {
  RenderDrivenBox(this._drive, this._opacity, this._shift);

  Animation<double> _drive;
  set drive(Animation<double> value) {
    if (identical(value, _drive)) {
      return;
    }
    if (attached) {
      _drive.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _drive = value;
    markNeedsPaint();
  }

  double Function(double t) _opacity;
  set opacity(double Function(double t) value) {
    _opacity = value;
    markNeedsPaint();
  }

  double Function(double t)? _shift;
  set shift(double Function(double t)? value) {
    _shift = value;
    markNeedsPaint();
  }

  /// Where the child was last painted, for hit tests and semantics.
  double _dy = 0;

  /// How much of the child is in view at the drive's progress now.
  double get opacityNow => _opacity(_drive.value);

  /// How far down the child is moved at the drive's progress now.
  double get shiftNow => _shift?.call(_drive.value) ?? 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _drive.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _drive.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    final double t = _drive.value;
    final double opacity = _opacity(t);
    _dy = _shift?.call(t) ?? 0;
    if (child == null || opacity <= 0) {
      layer = null;
      return;
    }
    final Offset at = offset + Offset(0, _dy);
    if (opacity >= 1) {
      layer = null;
      context.paintChild(child, at);
      return;
    }
    layer = context.pushOpacity(
      at,
      (opacity * 255).round(),
      (PaintingContext context, Offset offset) =>
          context.paintChild(child, offset),
      oldLayer: layer as OpacityLayer?,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: Offset(0, _dy),
        position: position,
        hitTest: (BoxHitTestResult result, Offset position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _dy, 0, 1);
  }
}

/// Opacity of something going from [from] to [to] at [t] of a change:
/// [sequential], what goes is gone by the middle and what comes starts
/// there; otherwise both at once.
double columnOpacity(
  double from,
  double to,
  double t, {
  required bool sequential,
}) {
  if (!sequential || from == to) {
    return from + (to - from) * t;
  }
  final double phase = to < from
      ? (2 * t).clamp(0.0, 1.0)
      : (2 * t - 1).clamp(0.0, 1.0);
  return from + (to - from) * phase;
}
