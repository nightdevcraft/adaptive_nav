# adaptive_nav_ios

What iPhone Duo's UIKit knows and `MediaQuery` does not, for
[adaptive_nav](https://pub.dev/packages/adaptive_nav):

- **the edge of the system's vertical bar** — `UITraitCollection.verticalBarEdge`,
  the system's own answer to "are this window's bars on the side, and which
  side", including under Split View, where the window's safe area does not
  say;
- **the reserved regions** — the fold (a *division*), the front cameras and
  the system's status area (*occlusions*), each with its active flag, from
  `UIView.reservedRegions`;
- **the hinge** — closed, partly open or fully open, and its angle, from
  `UIHingeInteraction`;
- the safe area with corner adaptation, the size classes, and where the
  window sits on the screen.

adaptive_nav works without this package: on iPhone Duo it reads the posture
off `MediaQuery.padding`. This package replaces that reading with UIKit's
where UIKit has one — which matters in two postures. The left window of Split
View has no side inset, so only UIKit says its bar belongs on the left edge;
and the framework leaves `MediaQuery.displayFeatures` empty on iOS, so only
UIKit says the device is half open and where it folds.

## Requirements

**Xcode 27.1 or later** (the iOS 27.1 SDK). The APIs it calls exist only from
that SDK on, so an app that depends on this package does not build with an
older Xcode. At run time they are checked: below iOS 27.1 the geometry says
`isSupported: false` and carries only the safe area.

The package is iOS only. Elsewhere it provides `null` and listens to nothing,
so it can stay in a cross-platform app's dependencies.

## Use

One line around the app:

```dart
void main() => runApp(const DuoGeometryProvider(child: MyApp()));
```

That is all adaptive_nav needs. Besides its own `DuoGeometryScope`, the
provider puts a `SystemGeometryScope` in the tree, and the shell takes three
things from it in place of what it would read off `MediaQuery`:

- **the side of the bar** — `verticalBarEdge` as a physical side. It is the
  edge the window's own bar belongs on, which under Split View is the outer
  edge of the display for either window, not the side the status bar is on;
- **the status area** — the active occlusion against the window's edge on
  that side, or against the top edge where the bars are horizontal. The shell
  keeps the rail's destinations clear of it and lines lifted headers up with
  it. A camera is an occlusion too, but stands clear of the edge, and is left
  out;
- **the folds** — the active divisions. UIKit reports the fold in every
  posture, 40 points across, and marks it active only while half open.

`systemGeometryOf` is that mapping, for an app that wants to see it. Without
the provider, or away from iOS, the shell reads the safe area as before.

Everything UIKit reports is in `DuoGeometryScope` as well:

```dart
final DuoGeometry? geometry = DuoGeometryScope.maybeOf(context);
final VerticalBarSide? side = geometry?.verticalBarSide;
final Iterable<ReservedRegion> folds = geometry?.activeDivisions ?? const [];
```

Regions are in Flutter logical pixels relative to the Flutter view — the
coordinates of `MediaQuery` and of a global `Offset`.

## Measuring a posture

`DuoGeometryProbe` draws the regions and the safe area over the app, shows the
numbers in a panel with a "Copy JSON" button, and prints one `duo_probe` line
per change with UIKit's values next to Flutter's `MediaQuery`:

```dart
void main() => runApp(
  const DuoGeometryProvider(child: DuoGeometryProbe(child: MyApp())),
);
```

The adaptive_nav example has this as a second entry point:
`flutter run -t lib/duo_probe.dart`.
