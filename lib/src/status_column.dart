import 'package:flutter/material.dart';

import 'nav_config.dart';

/// The empty part of the system's vertical status column, below its glyphs,
/// in the coordinates of the pane it is handed to
/// (`AdaptiveShellConfig.actionsInStatusColumn`).
///
/// It lies inside the pane's right inset, so content within the screen's
/// padding is never under it. It follows the divider and a sliding detail
/// frame by frame.
///
/// `null` for every other pane and posture. Most screens want
/// [StatusColumnActions] instead.
class StatusColumnScope extends InheritedWidget {
  const StatusColumnScope({
    required this.column,
    required super.child,
    super.key,
  });

  final Rect? column;

  /// `null` outside the pane the column is handed to.
  static Rect? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StatusColumnScope>()?.column;

  @override
  bool updateShouldNotify(StatusColumnScope oldWidget) =>
      column != oldWidget.column;
}

/// Builds a screen with its header [actions] in the status column where its
/// pane has one ([StatusColumnScope]), and in the `AppBar` everywhere else:
///
/// ```dart
/// StatusColumnActions(
///   actions: <Widget>[
///     IconButton(icon: const Icon(Icons.filter_list), onPressed: filter),
///   ],
///   builder: (BuildContext context, List<Widget> actions) => Scaffold(
///     appBar: AppBar(title: const Text('Starred'), actions: actions),
///     body: StatusColumnActions.body(list),
///   ),
/// )
/// ```
///
/// While the column is there, [builder] gets an empty list and the actions
/// stand in the column over the body; when it moves or goes away they fade
/// across over [duration]. Drawn in the body, they stay under the drawer,
/// bottom sheets and snack bars.
///
/// The body is assumed to start under a standard `AppBar`; a debug build
/// reports a screen whose header is taller or missing.
class StatusColumnActions extends StatefulWidget {
  const StatusColumnActions({
    required this.actions,
    required this.builder,
    this.duration = kDefaultImmersiveDuration,
    this.spacing = 8,
    super.key,
  });

  final List<Widget> actions;

  /// The screen, with what is left of [actions] for its `AppBar`. Its `body`
  /// goes in [StatusColumnActions.body].
  final Widget Function(BuildContext context, List<Widget> actions) builder;

  final Duration duration;

  /// Between the glyphs and the first action.
  final double spacing;

  /// The screen's `body`, with the actions over it while they are in the
  /// column.
  static Widget body(Widget child) => _StatusColumnBody(child: child);

  @override
  State<StatusColumnActions> createState() => _StatusColumnActionsState();
}

class _StatusColumnActionsState extends State<StatusColumnActions>
    with SingleTickerProviderStateMixin {
  /// 0 in the header, 1 in the column; each half is one fade.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addListener(_onTick);

  late final Animation<double> _inHeader = ReverseAnimation(
    _controller.drive(CurveTween(curve: const Interval(0, 0.5))),
  );
  late final Animation<double> _inColumn = _controller.drive(
    CurveTween(curve: const Interval(0.5, 1)),
  );

  /// The last column seen, kept while the actions fade out of it.
  Rect? _column;
  bool _shownInColumn = false;
  bool _started = false;

  /// To catch a screen without a [StatusColumnActions.body] in debug builds.
  int _bodies = 0;

  void _onTick() {
    final bool inColumn = _controller.value >= 0.5;
    if (inColumn != _shownInColumn) {
      setState(() => _shownInColumn = inColumn);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Rect? column = StatusColumnScope.of(context);
    if (column != null) {
      _column = column;
    }
    if (!_started) {
      // A screen that opens with the column has its actions there at once.
      _started = true;
      _controller.value = column != null ? 1 : 0;
      _shownInColumn = column != null;
    } else if (column != null) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(StatusColumnActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Rect? column = _column;
    final bool inColumn = _shownInColumn && column != null;
    Rect? inBody;
    if (inColumn) {
      // Where the body starts in the pane: under a standard `AppBar`.
      final double top = MediaQuery.paddingOf(context).top + kToolbarHeight;
      assert(
        column.top >= top,
        'The status column starts at ${column.top}, above the screen\'s '
        'body at $top, where StatusColumnActions.body cannot reach.',
      );
      inBody = Rect.fromLTRB(
        column.left,
        column.top + widget.spacing - top,
        column.right,
        column.bottom - top,
      );
      assert(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _shownInColumn && _bodies == 0) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: FlutterError(
                  'StatusColumnActions has its actions in the status column, '
                  'but the screen it builds has no StatusColumnActions.body '
                  'to show them in.',
                ),
                library: 'adaptive_nav',
              ),
            );
          }
        });
        return true;
      }());
    }
    return _StatusColumnActionsScope(
      state: this,
      column: inBody,
      actions: widget.actions,
      child: widget.builder(context, <Widget>[
        if (!inColumn)
          for (final Widget action in widget.actions)
            FadeTransition(opacity: _inHeader, child: action),
      ]),
    );
  }
}

/// [column] is in the body's coordinates, `null` while the actions are in the
/// header.
class _StatusColumnActionsScope extends InheritedWidget {
  const _StatusColumnActionsScope({
    required this.state,
    required this.column,
    required this.actions,
    required super.child,
  });

  final _StatusColumnActionsState state;
  final Rect? column;
  final List<Widget> actions;

  @override
  bool updateShouldNotify(_StatusColumnActionsScope oldWidget) =>
      column != oldWidget.column || actions != oldWidget.actions;
}

class _StatusColumnBody extends StatefulWidget {
  const _StatusColumnBody({required this.child});

  final Widget child;

  @override
  State<_StatusColumnBody> createState() => _StatusColumnBodyState();
}

class _StatusColumnBodyState extends State<_StatusColumnBody> {
  _StatusColumnActionsState? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _StatusColumnActionsState? owner = context
        .dependOnInheritedWidgetOfExactType<_StatusColumnActionsScope>()
        ?.state;
    if (owner != _owner) {
      _owner?._bodies--;
      owner?._bodies++;
      _owner = owner;
    }
  }

  @override
  void dispose() {
    _owner?._bodies--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _StatusColumnActionsScope? scope = context
        .dependOnInheritedWidgetOfExactType<_StatusColumnActionsScope>();
    assert(
      scope != null,
      'StatusColumnActions.body is outside the StatusColumnActions whose '
      'actions it shows.',
    );
    final Rect? column = scope?.column;
    assert(() {
      if (column != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkTop(scope!));
      }
      return true;
    }());
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Always the first child, so the body keeps its state as the actions
        // come and go.
        widget.child,
        if (column != null)
          Positioned.fromRect(
            rect: column,
            child: FadeTransition(
              opacity: scope!.state._inColumn,
              child: Align(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: scope.actions,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Whether the body really starts under a standard `AppBar`.
  void _checkTop(_StatusColumnActionsScope scope) {
    if (!mounted) {
      return;
    }
    final RenderObject? body = context.findRenderObject();
    final RenderObject? screen = scope.state.context.findRenderObject();
    if (body is! RenderBox || screen is! RenderBox || !body.attached) {
      return;
    }
    final double actual = body.localToGlobal(Offset.zero, ancestor: screen).dy;
    final double expected =
        MediaQuery.paddingOf(scope.state.context).top + kToolbarHeight;
    if ((actual - expected).abs() > 0.5) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'StatusColumnActions.body starts $actual down its screen, not '
            '$expected, under a standard AppBar, so the actions in the status '
            'column are out of place.',
          ),
          library: 'adaptive_nav',
        ),
      );
    }
  }
}
