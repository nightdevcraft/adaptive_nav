import 'dart:ui' show Rect;

import 'package:adaptive_nav/adaptive_nav.dart'
    show ChromePlacement, SystemGeometry;

import 'geometry.dart';

/// How close to the window's edge an occlusion has to be to count as lying
/// against it. The status areas measured touch it exactly.
const double _edgeTolerance = 1;

/// What adaptive_nav's shell needs out of a [DuoGeometry], or `null` where
/// UIKit has nothing to say: no window yet, or below iOS 27.1.
///
/// - **The bar's side** is [DuoGeometry.verticalBarSide]: the edge of the
///   window the system wants a vertical bar on, which under Split View is
///   the outer edge of the display for either window, not the side the
///   status bar is on (iPhone Duo simulator, iOS 27.1).
/// - **The status area** is the active occlusion lying against the window's
///   edge on the bar's side — or against the top edge where the bars are
///   horizontal, the inner display in portrait. A camera is an occlusion
///   too, but stands clear of the edge (37 × 37 at 399.7…436.7 across a
///   466-point window), and an inactive one is the inner display's
///   under-display camera; neither is the status area.
/// - **The folds** are the active divisions. Flat, the fold is reported
///   inactive with the same 40-point frame, and is left out.
///
/// A window without the system's column — the left half of Split View — has
/// a side and no status area.
SystemGeometry? systemGeometryOf(DuoGeometry? geometry) {
  if (geometry == null || !geometry.isSupported) {
    return null;
  }
  final VerticalBarSide? side = geometry.verticalBarSide;
  final double width = geometry.size.width;
  bool against(Rect r) => switch (side) {
    VerticalBarSide.left => r.left <= _edgeTolerance,
    VerticalBarSide.right => r.right >= width - _edgeTolerance,
    null => r.top <= _edgeTolerance,
  };
  Rect? statusArea;
  for (final ReservedRegion r in geometry.activeOcclusions) {
    if (against(r.frame)) {
      statusArea = r.frame;
      break;
    }
  }
  return SystemGeometry(
    verticalBar: switch (side) {
      VerticalBarSide.left => ChromePlacement.left,
      VerticalBarSide.right => ChromePlacement.right,
      null => null,
    },
    statusArea: statusArea,
    folds: <Rect>[
      for (final ReservedRegion r in geometry.activeDivisions) r.frame,
    ],
  );
}
