import 'package:flutter/widgets.dart';

/// How much of a pane's trailing end the status glyphs cover where
/// `AdaptiveShellConfig.liftHeadersIntoStatusRow` has lifted its header.
///
/// The shell cannot keep an `AppBar`'s actions clear of the glyphs, so the
/// screen does:
///
/// ```dart
/// AppBar(
///   title: const Text('People'),
///   actions: <Widget>[
///     IconButton(icon: const Icon(Icons.search), onPressed: search),
///     SizedBox(width: StatusRowScope.trailingReserveOf(context)),
///   ],
/// )
/// ```
///
/// Zero for every other pane and posture, so the box can stay in
/// unconditionally.
class StatusRowScope extends InheritedWidget {
  const StatusRowScope({
    required this.trailingReserve,
    required super.child,
    super.key,
  });

  /// In logical pixels, from the pane's trailing edge.
  final double trailingReserve;

  /// Zero outside a lifted pane.
  static double trailingReserveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<StatusRowScope>()
          ?.trailingReserve ??
      0;

  @override
  bool updateShouldNotify(StatusRowScope oldWidget) =>
      trailingReserve != oldWidget.trailingReserve;
}
