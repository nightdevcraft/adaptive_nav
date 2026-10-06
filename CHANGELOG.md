## 0.11.0

### Breaking

- In the rail layout the rail and the panes now extend under the status bar,
  as the panes above a bottom bar already did. Before, the whole layout started
  below it and the status bar showed one colour (the canvas or the `Scaffold`
  background) across all three. Now it shows the rail's colour over the rail
  and each pane's colour over that pane. The rail reserves the inset itself;
  a pane passes `padding.top − margin.top` to its screen. A screen with an
  `AppBar` needs no change. A screen without one has to handle
  `MediaQuery.padding.top` itself, as it does on a phone.

### Fixes

- On iPhone Duo's outer display a flush rail left an unpainted gap between
  itself and the window edge. The gap is now painted in the rail's colour.
  New `RailDecoration.isFlush` reports whether the rail has no margin and no
  corner radius.

### Example

- Panes are flush, in three shades, with the drag marker on the boundary.
- `lib/playground.dart`: the example in a desktop window, a phone, a tablet,
  iPhone Duo and Galaxy Z Fold8, with rotate and fold buttons. Built for the
  web and published from `.github/workflows/pages.yml`.

## 0.10.0

**iPhone Duo.** The navigation follows the system's own bars on both displays
and in every orientation, the pane arithmetic counts the safe area, and the
screens keep their state through every fold. Measured on the iPhone Duo
simulator under Xcode 27.1; build against the iOS 27.1 SDK.

### Breaking

- `AdaptiveShellConfig.showsRail` is now `chromeLayout`, and returns a
  `ChromePlacement` — `bottom`, `left` or `right` — instead of a bool.
  `ChromePredicate` and `defaultShowsRail` are gone; the replacements are
  `ChromeLayout` and `defaultChromeLayout`.
- An empty detail pane with no `BranchConfig.detailPlaceholder` is now blank,
  where it used to read "Select an item". The package has no screens of its
  own and could not localise that string; a caption belongs to the app.

### iPhone Duo

- **The rail can sit on the right**, and on the outer display it joins the
  system's vertical bar instead of taking a second column: it is centred on
  the same axis as the clock and the camera, and moves to the other edge as
  the phone turns.
- `AdaptiveShellConfig.systemBar`, a `SystemBarMetrics`, keeps the camera's
  end of that column free — 150 points upright, 80 in landscape, where the
  system hides the clock. The camera is in a corner of the glass, so turned
  one way it ends up at the bottom of the column; `SystemBarMetrics.end`
  follows it there.
- `defaultChromeLayout` reads the posture off `MediaQuery.padding` alone: a
  vertical inset of 60 points or more on exactly one side is the system bar.
  The rail follows it only on a display compact enough to need it — the outer
  one. On the inner display in landscape the rail leads, the far pane bleeds
  under the bar, and `SystemBarMetrics.cornerClearance` keeps the first
  destination out of the rounded corner.
- **A bottom bar with two panes above it**, for the inner display in portrait:
  669 points across, with horizontal bars. The pane cards run up under the
  status bar and the top inset is reserved once for the whole layout, so its
  82 points cost the panes nothing but the margin.
- **The rail no longer overflows a short column.** Destinations it cannot hold
  go behind a menu button at its end; on a folded Duo six fit, against a
  desktop's dozen. `AdaptiveShellConfig.railOverflow` turns it off,
  `railOverflowBuilder` draws the button in place of the Material one, and
  `railDestinationExtent` overrides the height the count is based on. That
  height is otherwise worked out per destination from its label, with the
  rail theme's styles, so one long label does not cost the others a line.
- `RailDecoration.backgroundColor`. The rail column is painted as one piece,
  including the strip under the system bar, where the canvas used to show
  through.

### Foldables in general

- `MasterDetailConfig.alignToFold` (default `true`), `FoldMetrics` and
  `PaneFold`. While a device is half open the pane boundary goes on the
  crease, the panes part by its width, and the divider stops being draggable
  until the device is flat again. Read from `MediaQuery.displayFeatures`,
  which the framework fills on Android and not yet on iOS.
- `AdaptiveShellConfig.foldLocator` and `FoldMetrics.windowCentre`. An app can
  say where the crease is on a device whose platform does not — iPhone Duo
  today — and a fold the platform *does* report still wins.

### Pane arithmetic

- **Fixed:** the horizontal safe-area insets are now part of it. They were
  ignored, so `fits`, `paneRatio` and `detailMinWidth` all counted width that
  lay under a system inset. On an iPhone Duo's inner display in landscape a
  detail dragged to its stop was 276 points wide while `detailMinWidth` said
  360. The panes still reach the window edge; only the width they may count
  on changed.
- `PaneMetrics` and `PaneUnderlap` are exported, with `systemBarInset` and
  `railColumnWidth`, so an app can arrive at the same numbers the shell does.
- A pane's `MediaQuery` now carries the part of the inset it actually reaches
  under, rather than all of it or none: with a `PaneDecoration.margin` the card
  is already held off the edge, and the screen inside it was insetting for the
  margin a second time.

### Example and docs

- `example/` uses master-detail minimums of 300 and 330, which fit the inner
  display in portrait and keep the outer display a single stack. The package
  defaults are unchanged.
- The README documents the five iPhone Duo postures and the iOS 27.1 SDK
  requirement.

### Changes to expect on devices that are not foldables

- A notched phone **in landscape** loses the trailing inset from its pane
  area: the detail bleeds under it, so it was never width the screen could
  use. `MasterDetailConfig.fits` therefore sees ~60 points less than before,
  which can turn two panes into one at the boundary.
- A **bottom bar no longer implies a single pane**. The width still decides,
  and a phone is far under the package's default minimums — but an app that
  lowered them now gets the split it asked for where it used to get a stack.
- An **Android foldable** aligns its split to a reported fold while half open.
  `MasterDetailConfig.alignToFold: false` keeps the old behaviour.

`other_devices_test.dart` pins the first two.

## 0.9.0

First public release. The API is still settling — pre-1.0, so breaking changes
come in minor versions.

- `NavState` / `BranchStack` / `NavEntry`: immutable navigation state with
  value equality.
- `AdaptiveRouterDelegate`: `push`, `pop`, `popWithResult`, `replace`,
  `resetTo`, `resetDetailTo`, `popToRoot`, `goBranch`, system back handling and
  a single exit-guard gate across every way out of a screen.
- Three layouts from one state: compact (navigation bar, detail over the bar),
  medium (rail, one pane) and expanded (rail, master-detail panes), with the
  screens' element tree preserved across every transition.
- `AdaptiveRouteInformationParser` plus an app-supplied `RouteCodec` for deep
  links and cold start.
- Configurable chrome: custom bar and rail builders, a drawer, hidden branches,
  a chromeless mode and a redirect hook.
- Pane decoration (margins, gap, radius, canvas, borders), a draggable pane
  divider through `PaneSplitController`, and an immersive mode that slides the
  rail away.
