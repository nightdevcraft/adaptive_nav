import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'nav_config.dart';

/// What the platform says about the window's own chrome, where
/// `MediaQuery` does not: which side its vertical bar belongs on, where the
/// system keeps its status glyphs, and where the window folds.
///
/// The shell reads it from a [SystemGeometryScope] and falls back to
/// `MediaQuery.padding` without one, which is the case everywhere but an app
/// that put a provider above itself. On iPhone Duo that provider is
/// `DuoGeometryProvider` from adaptive_nav_ios, which fills this in from
/// UIKit; nothing in this package knows about UIKit.
///
/// The fallback reads the same postures off the safe area and gets all but
/// one right. The exception is Split View: the window on the left has no side
/// inset, so the padding cannot say that the system wants its bar on the left
/// edge, and that window gets a bottom bar.
@immutable
class SystemGeometry {
  const SystemGeometry({
    this.verticalBar,
    this.statusArea,
    this.folds = const <Rect>[],
  }) : assert(
         verticalBar != ChromePlacement.bottom,
         'verticalBar is a side of the window: left, right or null',
       );

  /// Side the system wants the app's vertical bar on; `null` when bars are
  /// horizontal or the platform has no opinion.
  ///
  /// It is the window's edge, not the side the status bar is on. iPhone Duo
  /// under Split View gives both windows the outer edge of the display,
  /// though only the right one has the status bar
  /// (`UITraitCollection.verticalBarEdge`, simulator, iOS 27.1). Only
  /// [ChromePlacement.left] and [ChromePlacement.right].
  final ChromePlacement? verticalBar;

  /// The system's own reserved area at the bar's end — the clock, the
  /// glyphs, the camera beside them — in window coordinates. `null` when
  /// there is none.
  ///
  /// With a vertical bar it lies against that edge, at the top or the bottom
  /// of the column; with horizontal bars it is against the top edge. The
  /// shell keeps the rail's destinations out of it and lines lifted headers
  /// and status column actions up with it.
  final Rect? statusArea;

  /// Active folds, in window coordinates.
  ///
  /// A fold is active only while the device is partly open: flat, a crease
  /// on a continuous display occludes nothing, and the platform should leave
  /// it out.
  final List<Rect> folds;

  @override
  bool operator ==(Object other) =>
      other is SystemGeometry &&
      other.verticalBar == verticalBar &&
      other.statusArea == statusArea &&
      listEquals(other.folds, folds);

  @override
  int get hashCode =>
      Object.hash(verticalBar, statusArea, Object.hashAll(folds));

  @override
  String toString() =>
      'SystemGeometry(verticalBar: ${verticalBar?.name}, statusArea: '
      '$statusArea, folds: $folds)';
}

/// Carries a [SystemGeometry] to the shell.
///
/// Put one above the app — or let a platform package do it — and the shell
/// takes the side of the bar, the status area and the folds from it instead
/// of reading them off `MediaQuery`. A `null` geometry is the same as no
/// scope at all.
class SystemGeometryScope extends InheritedWidget {
  const SystemGeometryScope({
    required this.geometry,
    required super.child,
    super.key,
  });

  final SystemGeometry? geometry;

  /// The nearest geometry, or `null` with no scope above or nothing reported
  /// yet.
  static SystemGeometry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SystemGeometryScope>()
      ?.geometry;

  @override
  bool updateShouldNotify(SystemGeometryScope oldWidget) =>
      geometry != oldWidget.geometry;
}
