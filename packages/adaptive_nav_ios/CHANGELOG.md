## 0.1.0

- `DuoGeometryProvider` and `DuoGeometryScope`: iPhone Duo's geometry from UIKit
  as `DuoGeometry`: bar edge, reserved regions, hinge, safe areas, size classes.
- `ReservedRegion`, `ReservedRegionKind`, `HingeStatus`, `VerticalBarEdge` and
  `VerticalBarSide`.
- The provider also puts adaptive_nav's `SystemGeometryScope` in the tree;
  `systemGeometryOf` is that mapping. README has what the shell does with it.
- `DuoGeometryProbe`: draws the geometry over the app and logs every change.
- Depends on adaptive_nav 0.15.0.
