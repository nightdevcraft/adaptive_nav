## 0.1.0

- `DuoGeometryProvider` reads the iPhone Duo geometry from UIKit and puts it
  in the tree: the edge of the system's vertical bar
  (`UITraitCollection.verticalBarEdge`), the reserved regions — the fold, the
  cameras and the status area — with their active flag, the hinge status and angle, the safe
  area with and without corner adaptation, the size classes and where the
  window sits on the screen.
- `DuoGeometryProbe` draws all of it over the app and logs every change, for
  measuring a posture in Device Hub.
- `DuoGeometryProvider` also puts a `SystemGeometryScope` in the tree, which
  adaptive_nav's shell reads: the side of the system's vertical bar, the
  status area — the active occlusion against the window's edge on that side,
  or the top edge where the bars are horizontal, never a camera clear of it —
  and the active folds. `systemGeometryOf` is that mapping, as a function.
  With the provider above the app the shell puts the rail on the left edge of
  the left Split View window and meets the panes on the hinge while the
  device is half open.
- Depends on adaptive_nav 0.15.0.
