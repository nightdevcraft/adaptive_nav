import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:adaptive_nav/adaptive_nav.dart'
    show SystemGeometry, SystemGeometryScope;

import 'geometry.dart';
import 'system_geometry.dart';

const EventChannel _channel = EventChannel('adaptive_nav_ios/geometry');

/// The plugin's stream, or an empty one where there is no plugin to ask.
Stream<DuoGeometry?> _platformGeometry() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return const Stream<DuoGeometry?>.empty();
  }
  return _channel.receiveBroadcastStream().map(
    (Object? event) =>
        event is Map<Object?, Object?> ? DuoGeometry.fromMap(event) : null,
  );
}

/// Listens to UIKit for as long as it is mounted and provides the latest
/// [DuoGeometry] to [child] — and, through a `SystemGeometryScope`, what
/// adaptive_nav's shell takes from it: the side of the system's vertical bar,
/// its status area and the active folds ([systemGeometryOf]).
///
/// Put it above the app, where it costs one listener:
///
/// ```dart
/// runApp(const DuoGeometryProvider(child: MyApp()));
/// ```
///
/// Away from iOS — and in widget tests, which run as Android unless told
/// otherwise — it provides `null` and listens to nothing, and the shell falls
/// back to `MediaQuery`.
class DuoGeometryProvider extends StatefulWidget {
  /// Provides UIKit's geometry to [child], or that of [source] when given.
  const DuoGeometryProvider({super.key, required this.child, this.source});

  /// The app.
  final Widget child;

  /// Replaces the plugin, for tests and for previewing a posture.
  final Stream<DuoGeometry?>? source;

  @override
  State<DuoGeometryProvider> createState() => _DuoGeometryProviderState();
}

class _DuoGeometryProviderState extends State<DuoGeometryProvider> {
  StreamSubscription<DuoGeometry?>? _subscription;
  DuoGeometry? _geometry;
  SystemGeometry? _system;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(DuoGeometryProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _subscription?.cancel();
      _geometry = null;
      _system = null;
      _listen();
    }
  }

  void _listen() {
    _subscription = (widget.source ?? _platformGeometry()).listen(
      (DuoGeometry? next) {
        if (next != _geometry) {
          setState(() {
            _geometry = next;
            _system = systemGeometryOf(next);
          });
        }
      },
      // No plugin registered — an add-to-app host that skipped it — means no
      // geometry, not a broken app.
      onError: (Object error) {
        if (_geometry != null) {
          setState(() {
            _geometry = null;
            _system = null;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DuoGeometryScope(
    geometry: _geometry,
    child: SystemGeometryScope(geometry: _system, child: widget.child),
  );
}

/// Carries a [DuoGeometry] down the tree. [DuoGeometryProvider] puts one in;
/// a test can put one in directly.
class DuoGeometryScope extends InheritedWidget {
  /// Provides [geometry] to [child].
  const DuoGeometryScope({
    super.key,
    required this.geometry,
    required super.child,
  });

  /// The geometry, or `null` where there is none: no window yet, or not
  /// on iOS.
  final DuoGeometry? geometry;

  /// The nearest geometry, or `null` with no provider above or nothing
  /// reported yet.
  static DuoGeometry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DuoGeometryScope>()?.geometry;

  @override
  bool updateShouldNotify(DuoGeometryScope oldWidget) =>
      geometry != oldWidget.geometry;
}
