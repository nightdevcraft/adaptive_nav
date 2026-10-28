import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Where a fold crosses the pane area, in pane-area coordinates.
///
/// The panes meet on [centre], the hinge itself. A crease with width to it —
/// a hinge, or a display that curves away — is an inset rather than a gap:
/// each pane reaches the hinge and holds its content [width] / 2 clear of it,
/// the way a pane reaches under a safe-area inset, so the backgrounds meet
/// where the device bends and no content is bent across it.
@immutable
class PaneFold {
  const PaneFold({required this.start, required this.end});

  final double start;
  final double end;

  double get width => end - start;

  /// Where the panes meet: the middle of the crease, or the line itself when
  /// it has no width.
  double get centre => (start + end) / 2;

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

/// Reads `MediaQuery.displayFeatures` for a fold the panes should meet on.
///
/// **Where this works.** The framework populates `displayFeatures` on Android,
/// so a book-style foldable gets this today. On iOS the list is still empty —
/// it was in every posture measured on iPhone Duo, half open included — until
/// the framework maps Apple's `reservedRegions` onto it (flutter/flutter
/// #193025). Meanwhile adaptive_nav_ios reads them itself and hands the
/// active folds over as `SystemGeometry.folds`, which [fromRects] converts.
/// The shell asks `displayFeatures` first, so nothing needs to change here
/// when the framework catches up.
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

  /// The fold to part the panes around among [folds] — the active ones a
  /// platform reported through `SystemGeometry.folds`, in window coordinates
  /// — or `null`.
  ///
  /// The same rules as [paneFold], less the posture, which the platform has
  /// already applied by leaving inactive folds out: only a **vertical** fold
  /// **inside** the pane area counts. A horizontal one — iPhone Duo's inner
  /// display in portrait, half open — divides top from bottom, and the panes
  /// side by side have nothing to align to it.
  ///
  /// iPhone Duo reports its fold 40 across, a line with 20 of margin either
  /// side (455.5…495.5 on the inner display in landscape, `reservedRegions`,
  /// simulator, iOS 27.1), so the panes meet on 475.5 and each keeps its
  /// content 20 clear of it.
  static PaneFold? fromRects({
    required List<Rect> folds,
    required double origin,
    required double paneArea,
  }) {
    for (final Rect b in folds) {
      if (b.height < b.width) {
        continue; // horizontal: not our axis
      }
      final PaneFold? fold = fromBounds(
        bounds: b,
        origin: origin,
        paneArea: paneArea,
      );
      if (fold != null) {
        return fold;
      }
    }
    return null;
  }

  /// A [FoldLocator] that puts the crease down the middle of the window.
  ///
  /// It is a line, not a region, and it is there whatever the posture.
  @Deprecated(
    'It cannot see the posture: it puts the boundary down the middle on a '
    'flat device too, where there is no crease to avoid. On iPhone Duo, '
    'adaptive_nav_ios reports the real fold, active only while half open, '
    'through SystemGeometryScope.',
  )
  static Rect? windowCentre(Size window, EdgeInsets padding) =>
      Rect.fromLTRB(window.width / 2, 0, window.width / 2, window.height);
}
