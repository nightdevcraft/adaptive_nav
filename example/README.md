# adaptive_nav example

A small contacts app. Resize the window and watch what does *not* happen:
nothing remounts.

## What it shows

- **People** is a master-detail branch. Below ~638 logical pixels of pane area
  it is a plain stack; above it the list and the person sit side by side, and
  the boundary between them can be dragged (`PaneSplitController`, with
  `onCommit` firing on release). The minimums behind that number are picked so
  the inner display of an iPhone Duo in portrait still splits; the package's
  own defaults are wider.
- **Settings** is a plain tab with a switch. Leave the tab and come back — the
  switch is where you left it, because the branch navigator stays mounted.
- **Teams**, **Starred**, **Recent calls**, **Archive** and
  **Trash** are stubs, there to give the chrome more sections than a short rail
  can hold. Fold an iPhone Duo and the ones that do not fit move behind the
  menu button at the end of the rail; widen the window and they all come back.
  Each keeps a tap count, so a trip through the menu and back shows that
  switching sections does not rebuild them.
  "Recent calls" is the label that takes two lines in an 80-point rail, and
  every destination is counted at that height.
- Picking another person uses `resetDetailTo`, not `push`: a lateral move that
  replaces a detail of any depth without flashing an empty pane.
- The editor declares an `onExit` guard. Back, a tab switch or picking another
  person all ask before discarding.
- `AppTransition.adaptive`: the detail fades when it swaps the contents of a
  pane and slides when it takes the whole screen.
- The detail's app bar reads `DetailEntryScope.isDetailRoot` to choose a close
  button over a back arrow, and `DetailPaneScope.isFullScreen` to take its own
  bottom edge when it covers the navigation bar.
- Saving raises a snack bar from the screen's own context, so it appears in the
  detail pane rather than across the window.
- Routes encode as `/people`, `/people/3`, `/people/3/edit` and `/settings`, so
  deep links and the browser address bar work.

## What it leaves out

Deliberately — one readable app cannot also be a feature matrix. Not shown
here: custom `barBuilder` / `railBuilder` chrome, the drawer, chromeless mode
and hidden branches, the `redirect` auth hook and `reevaluate`, immersive mode,
rail decoration, and `detailPlaceholder` (which never appears while an empty
detail collapses, as it does by default).

Every one of those has tests in [`../test`](../test), and the tests are the
exhaustive reference for behaviour.

## Running it

The example ships as Dart sources only. Generate the platform folders once,
then run it:

```sh
cd example
flutter create .
flutter run
```

### In the browser

`lib/playground.dart` runs the same app inside device frames: a resizable
desktop window, a phone, a tablet, iPhone Duo and Galaxy Z Fold8, with rotate
and fold buttons. The [online playground](https://nightdevcraft.github.io/adaptive_nav/)
is this file:

```sh
cd example
flutter create --platforms=web .
flutter run -d chrome -t lib/playground.dart
```

The page holds a single instance of the app. Switching devices, rotating and
folding only change its `MediaQuery`, so open screens and their state stay.

### iOS 27.1 and iPhone Duo

`flutter create` still writes `IPHONEOS_DEPLOYMENT_TARGET = 13.0`, and an iOS
27.1 runtime refuses to build below 15.0:

```
The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to
13.0, but the range of supported deployment target versions is 15.0 to 27.1.x.
```

Raise it after generating the project:

```sh
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' \
  ios/Runner.xcodeproj/project.pbxproj
```

Build with the iOS 27.1 SDK (Xcode 27.1) to see the real thing on an iPhone
Duo. Under an older SDK both displays hand the app a 375 × 667 compatibility
box, and none of the postures in the main README apply. The simulator's fold
and rotate controls live in `DeviceHub.app`, which replaced `Simulator.app`.
