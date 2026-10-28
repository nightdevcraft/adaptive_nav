import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'nav_config.dart';

/// How far in from the window's edge the iOS back swipe starts where there
/// is no inset: `_kBackGestureWidth` of Flutter's Cupertino route.
const double _kBackGestureWidth = 20;

/// A release at this speed or faster decides the swipe by its direction
/// rather than by how far it got, in widths of the screen per second:
/// `_kMinFlingVelocity` of Flutter's Cupertino route.
const double _kMinFlingVelocity = 1;

/// The iOS back swipe from the window's leading edge, where the system's
/// column stands between that edge and the screen it would take off.
///
/// A single pane stands beside the column — a covering detail beside the
/// bare column, or any screen beside the rail in it — so the swipe the
/// screen's own route listens for starts at the pane's edge, a column's
/// width in. On the device the finger starts at the edge of the glass, in
/// the column, and the screen never saw it. This is the strip the route's own
/// detector would have there, `max(inset, 20)` from the edge on [side], and
/// on to the edge of the pane the route is in, so no finger between the
/// column and the screen is lost: over whatever is below it in the window,
/// and letting the pointer through to it.
///
/// The swipe drives [route] through its predictive back interface, the
/// public one every `TransitionRoute` has: start, progress and cancel move
/// the route's own animation, so the screen moves with the same transition
/// the theme gives it, and the column follows the navigator's user gesture
/// as it does for the route's own swipe. A finished swipe pops the route
/// itself, as Cupertino's does: `handleCommitBackGesture` restarts the
/// animation from the top, for Android's commit, and the screen would jump
/// back before it left. See "A back swipe from the column" in
/// doc/design.md.
///
/// Like Cupertino's, a finger becomes a swipe only once it has moved far
/// enough sideways; a tap on a button in the strip — the toolbar's, a tab,
/// More — stays a tap.
class ColumnBackGesture extends StatefulWidget {
  const ColumnBackGesture({
    required this.side,
    required this.inset,
    required this.route,
    super.key,
  });

  /// The window's edge the swipe starts at, physical: the leading one.
  final ChromePlacement side;

  /// The system's inset on [side].
  final double inset;

  /// The route a swipe starting now would take off, or `null` for none. Read
  /// as a finger lands, and taken only if its gesture is enabled then.
  final ValueGetter<ModalRoute<Object?>?> route;

  @override
  State<ColumnBackGesture> createState() => _ColumnBackGestureState();
}

class _ColumnBackGestureState extends State<ColumnBackGesture> {
  late final HorizontalDragGestureRecognizer _recognizer =
      HorizontalDragGestureRecognizer(debugOwner: this)
        ..onStart = _start
        ..onUpdate = _update
        ..onEnd = _end
        ..onCancel = _cancel;

  /// The route a landed finger may swipe away; the swipe's once it starts.
  ModalRoute<Object?>? _candidate;
  ModalRoute<Object?>? _swiping;

  /// The route's progress the finger holds: 1 open, 0 gone.
  double _value = 1;

  /// The width the screen moves across, as the route's own detector
  /// measures it: the screen's.
  double _width = 1;

  /// Positive towards the screen's way out.
  double get _sign => widget.side == ChromePlacement.left ? 1 : -1;

  void _pointerDown(PointerDownEvent event) {
    if (_swiping != null) {
      return;
    }
    final ModalRoute<Object?>? route = widget.route();
    if (route == null ||
        !route.isCurrent ||
        !route.popGestureEnabled ||
        _fromEdge(event.localPosition) > _reach(route)) {
      return;
    }
    _candidate = route;
    _recognizer.addPointer(event);
  }

  /// How far in from [ColumnBackGesture.side] [position] is.
  double _fromEdge(Offset position) => widget.side == ChromePlacement.left
      ? position.dx
      : context.size!.width - position.dx;

  /// How far in from the edge the strip reaches for [route]: the route's own
  /// strip, `max(inset, 20)`, or the edge of the pane it is in, its
  /// navigator's, if that is further — past the rail's divider and whatever
  /// the column leaves beside it, where the screen's own detector starts.
  double _reach(ModalRoute<Object?> route) {
    final double strip = math.max(widget.inset, _kBackGestureWidth);
    final RenderObject? pane = route.navigator?.context.findRenderObject();
    final RenderObject? self = context.findRenderObject();
    if (pane is! RenderBox ||
        !pane.hasSize ||
        self is! RenderBox ||
        !self.hasSize) {
      return strip;
    }
    final Rect rect = MatrixUtils.transformRect(
      pane.getTransformTo(self),
      Offset.zero & pane.size,
    );
    return math.max(
      strip,
      widget.side == ChromePlacement.left
          ? rect.left
          : self.size.width - rect.right,
    );
  }

  void _start(DragStartDetails details) {
    final ModalRoute<Object?>? route = _candidate;
    _candidate = null;
    // Taken by something else between the finger landing and moving: a
    // push, a pop, the route's own swipe.
    if (route == null || !route.isCurrent || !route.popGestureEnabled) {
      return;
    }
    final Size? size = route.subtreeContext?.size;
    _width = size == null || size.width <= 0
        ? MediaQuery.sizeOf(context).width
        : size.width;
    _value = 1;
    _swiping = route..handleStartBackGesture(progress: _value);
  }

  void _update(DragUpdateDetails details) {
    final ModalRoute<Object?>? route = _swiping;
    if (route == null) {
      return;
    }
    _value = (_value - _sign * details.primaryDelta! / _width).clamp(0.0, 1.0);
    route.handleUpdateBackGestureProgress(progress: _value);
  }

  void _end(DragEndDetails details) =>
      _release(_sign * details.velocity.pixelsPerSecond.dx / _width);

  void _cancel() {
    _candidate = null;
    _release(0);
  }

  /// The finger has let go at [velocity], in widths per second towards the
  /// way out. The same choice as Cupertino's: fast enough, the direction
  /// decides; otherwise the half way.
  void _release(double velocity) {
    final ModalRoute<Object?>? route = _swiping;
    _swiping = null;
    if (route == null) {
      return;
    }
    final bool pop =
        route.isCurrent &&
        (velocity.abs() >= _kMinFlingVelocity ? velocity > 0 : _value <= 0.5);
    if (!pop) {
      // Also where something else has taken the route off meanwhile: that
      // pop runs its own animation, and this only ends the gesture.
      route.handleCancelBackGesture();
      return;
    }
    final NavigatorState navigator = route.navigator!;
    // The pop reverses the route's animation from where the finger left it;
    // the user gesture lasts until it is done, so the transition stays as
    // straight as the finger was.
    navigator.pop();
    final Animation<double> animation = route.animation!;
    if (!animation.isAnimating) {
      navigator.didStopUserGesture();
      return;
    }
    late final AnimationStatusListener done;
    done = (AnimationStatus _) {
      animation.removeStatusListener(done);
      if (navigator.mounted) {
        navigator.didStopUserGesture();
      }
    };
    animation.addStatusListener(done);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // Gone mid-swipe — the posture changed, the column moved — the screen
    // goes back to where it was, after the frame that took this away.
    final ModalRoute<Object?>? route = _swiping;
    if (route != null) {
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        if (route.navigator?.mounted ?? false) {
          route.handleCancelBackGesture();
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Over the window, as the strip's width depends on where the pane is when
    // the finger lands: [_pointerDown] takes only what lands in it.
    // Translucent: what is under the strip, the column's buttons, still gets
    // the pointer, and a tap there is theirs.
    return Listener(
      onPointerDown: _pointerDown,
      behavior: HitTestBehavior.translucent,
      child: const SizedBox.expand(),
    );
  }
}
