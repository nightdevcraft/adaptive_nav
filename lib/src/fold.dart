import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Where a fold crosses the pane area, in pane-area coordinates.
///
/// [start] is the master's right edge and [end] the detail's left one, so a
/// crease with width to it — a hinge, or a display that curves away — leaves a
/// gap rather than a line, and neither pane is bent across it.
@immutable
class PaneFold {
  const PaneFold({required this.start, required this.end});

  final double start;
  final double end;

  double get width => end - start;

  @override
  bool operator ==(Object other) =>
      other is PaneFold && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'PaneFold(start: $start, end: $end)';
}

/// Where an app says the crease is, when the platform will not.
///
/// Returns the crease's bounds in window coordinates, or `null` for "no fold".
/// A zero-width rect is a line, which is all that is needed to place a
/// boundary; give it width to keep the panes clear of a region as well.
typedef FoldLocator = Rect? Function(Size window, EdgeInsets padding);

/// Reads `MediaQuery.displayFeatures` for a fold the panes should part around.
///
/// **Where this works.** The framework populates `displayFeatures` on Android,
/// so a book-style foldable gets this today. On iOS the list is still empty —
/// nothing maps Apple's `reservedRegions` onto it yet — so on iPhone Duo every
/// function here returns `null` and the layout is decided by width alone, as
/// it was. Nothing needs to change here when that lands.
abstract final class FoldMetrics {
  /// The fold to part the panes around, or `null`.
  ///
  /// Only a feature that is **vertical**, **active** and **inside** the pane
  /// area counts:
  ///
  /// - A horizontal fold divides top from bottom and says nothing about where
  ///   a vertical boundary belongs.
  /// - A flat posture reports the fold with
  ///   [DisplayFeatureState.postureFlat], and a crease on a continuous display
  ///   occludes nothing: aligning to it would move the boundary for no reason
  ///   and against the guidance to keep folding calm.
  /// - A fold outside the pane area — behind the rail, or past the far edge —
  ///   is not a boundary either pane could sit against.
  ///
  /// [origin] is where the pane area starts in window coordinates, so the
  /// result is already in the same coordinates as the pane widths.
  static PaneFold? paneFold({
    required List<DisplayFeature> features,
    required double origin,
    required double paneArea,
  }) {
    for (final DisplayFeature f in features) {
      if (f.type != DisplayFeatureType.fold &&
          f.type != DisplayFeatureType.hinge) {
        continue;
      }
      if (f.state != DisplayFeatureState.postureHalfOpened) {
        continue;
      }
      final Rect b = f.bounds;
      if (b.height < b.width) {
        continue; // horizontal: not our axis
      }
      final double start = b.left - origin;
      final double end = b.right - origin;
      if (start <= 0 || end >= paneArea) {
        continue;
      }
      return PaneFold(start: start, end: end);
    }
    return null;
  }

  /// The same conversion for a fold the app supplied through a [FoldLocator],
  /// which has no posture and no type to check — the app is asserting it.
  static PaneFold? fromBounds({
    required Rect? bounds,
    required double origin,
    required double paneArea,
  }) {
    if (bounds == null) {
      return null;
    }
    final double start = bounds.left - origin;
    final double end = bounds.right - origin;
    if (start <= 0 || end >= paneArea) {
      return null;
    }
    return PaneFold(start: start, end: end);
  }

  /// A [FoldLocator] that puts the crease down the middle of the window.
  ///
  /// That is where a centre hinge is, and on iPhone Duo it is the only answer
  /// available: the framework does not fill `displayFeatures` on iOS, and no
  /// other API reports the fold. So this is the app asserting what the
  /// hardware is, not the package detecting it — which is why it is opt-in and
  /// why the package ships no default locator.
  ///
  /// It is a line, not a region: flat, a crease on a continuous display
  /// occludes nothing, and the panes only need to meet on it.
  static Rect? windowCentre(Size window, EdgeInsets padding) =>
      Rect.fromLTRB(window.width / 2, 0, window.width / 2, window.height);
}
