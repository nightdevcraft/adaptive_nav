## 0.15.1

- Shorter changelog for 0.15.0.

## 0.15.0

### Breaking

- `ChromeLayout` takes a third argument, `SystemGeometry?`: add it to a custom
  layout. `defaultChromeLayout` takes it as optional.
- `defaultChromeLayout` follows a one-sided `kVerticalBarInset` at any width:
  on iPhone Duo's inner display in landscape the rail moves into the column.
- In iPhone Duo's system column the rail is the screen's toolbar at the top and
  icon-only tabs at the bottom, More for the rest. A `railBuilder` is unchanged.
- An open detail over a single pane covers the rail, as it covers the bar. To
  keep it on iOS and macOS: `detailChrome: DetailChrome.kept`.
- Tapping the active destination pops to the branch root, through `onExit`.
  To keep the old no-op: `reselect: BranchReselect.none`.
- Removed `actionsInStatusColumn`, `StatusColumnScope`, `StatusColumnActions`
  and `SystemBarMetrics.statusColumnTop`: use `PaneToolbar`.
- `Navigator.maybePop` from a screen of an inactive branch does nothing;
  `Navigator.pop` still pops it (see Fixes).
- On iPhone Duo a screen without a `PaneToolbar` gets Back in the column, not
  the `AppBar`'s arrow. To opt out: `automaticBackInColumn: false`.
- With a fold, panes meet on the hinge and get half the crease as
  `MediaQuery.padding`; `PaneDecoration.gap` is split around it.
- `SystemBarEndResolver` takes the display's size as a third argument: add it
  to a custom resolver.
- `SystemBarMetrics.measured`: `reserve` 170, `landscapeReserve` 82,
  `statusRowTrailing` 134, new `innerReserve` 120 (`kCompactDisplayShortSide`).

### Features

- `SystemGeometry` and `SystemGeometryScope`: the platform's bar side, status
  area and folds, read by the shell. adaptive_nav_ios provides them.
- `SystemBarMetrics.reserveFor`, `followsSystemGeometry` and `columnInset`;
  `SystemBarMetrics.none` ignores a reported status area too.
- `PaneToolbar`, `PaneToolbarItem` and `PaneToolbarLayout`: a screen's toolbar,
  as a header or in iPhone Duo's column. README: "iPhone Duo".
- `PaneBar`, `PaneBarScope`, `maxHeaderActions`, `kPaneToolbarItemExtent`,
  `kPaneToolbarItemGap`, `kPaneToolbarGroupGap`. Pinned items get the primary.
- `VerticalBarCompression`, `BranchConfig.verticalCompression` and
  `PaneToolbar.compression`: whether the toolbar or the tabs give way first.
- `AdaptiveShellConfig.railLabelsInColumn` (`kRailDestinationIconExtent`),
  `railAlignment` (`RailAlignment`) and `BranchConfig.visibilityPriority`.
- The column follows route transitions and back gestures; the iOS swipe back
  starts at the window's edge, across the column.
- `AdaptiveShellConfig.detailChrome` and `DetailChrome`. README: "A detail and
  the chrome".
- `AdaptiveShellConfig.reselect`, `BranchReselect` and `onReselect`
  (`BranchReselectCallback`). README: "Tapping the active tab again".
- `AdaptiveShellConfig.automaticBackInColumn`; built pages and routes add
  `impliesAppBarDismissal`.
- `FoldMetrics.fromRects`. Folds come from `MediaQuery.displayFeatures`, then
  `SystemGeometry.folds`, then `foldLocator`.
- A rail with nothing above it keeps `cornerClearance` free at its top.

### Fixes

- Android's predictive back no longer closes screens in inactive tabs.

### Deprecated

- `FoldMetrics.windowCentre`: adaptive_nav_ios reports the real fold.

## 0.14.0

### Features

- `AdaptiveNav`: the router as one object, a `RouterConfig` for
  `MaterialApp.router(routerConfig: nav)` that carries the navigation API. It
  is not a `Listenable`, so it fits a Riverpod provider under `riverpod_lint`.
- `AdaptiveNav` owns everything that notifies, the immersive flag and pane
  split included (`immersive`, `resizablePanes`, `paneFractions`,
  `onPaneCommit`). The config fields stay for a hand-built `Router`.

### Changed

- A deep link replaces only the target branch: its root and any screen already
  in the stack are kept, and the other tabs keep their stacks. A deep-linked
  screen gets its branch's `transition`.
- `redirect` sees the start exactly once, with or without a codec. `state`
  before the first frame is the initial state as given.
- `goBranch` with an index outside the branches throws an `ArgumentError`.
  `mountedBranches` is read-only and `@visibleForTesting`.
- The router asserts that the config has branches, and the stock
  `NavigationBar` that it has at least two in the chrome.
- Gated mutations with no guard involved notify listeners in the same call,
  as `push` does. Calling one from `build` now fails an assert.
- Disposing the delegate completes every pending `push` with `null`; `push`
  after dispose asserts.

### Fixes

- System back at a guarded root with nowhere to switch to leaves the app once
  the guard agrees. The app's own `maybePop` there still does nothing.
- Two panes over a bottom bar no longer get the bottom inset twice.
- Exit guards no longer race: `pop`, `replace`, `resetTo`, `popToRoot` and
  `resetDetailTo` remove only what they asked about and keep anything pushed
  meanwhile, in any branch.
- A screen removed by any route completes its `push` future with `null`.
- An `onExit` guard that throws counts as a refusal and is reported; one that
  answers after dispose changes nothing.
- Right-to-left locales no longer mirror the wide layout.
- A rail column too short for two destinations puts all of them behind the
  overflow menu.
- With `immersive` configured, the rail sits where it does without it.
- Dragging the pane boundary, the detail reveal and the immersive slide no
  longer rebuild every mounted screen each frame.
- `MasterDetailConfig.fitsAround` takes the pane gap into account.
- `PaneSplitController`: a drag that ends where it began commits nothing, a
  drag writes only to its own branch, and `restore` leaves it alone. A handle
  that leaves mid-drag ends the drag.
- The empty detail's `detailPlaceholder` is no longer rebuilt every frame of a
  drag or the detail reveal.

## 0.13.0

### Breaking

- Below 600 across, without the side insets, a window is always a single
  screen, whatever `MasterDetailConfig.fits` says (`kCompactWidthBreakpoint`,
  `PaneMetrics.allowsTwoPanes`). A phone no longer splits over its bar, and a
  window narrowed through 600 no longer goes back to two panes when the rail
  gives way to the bar. iPhone Duo's inner display in portrait, 669 across,
  keeps its two panes.

### Features

- `AdaptiveShellConfig.liftHeadersIntoStatusRow` (experimental, iOS): on
  iPhone Duo's inner display in portrait the panes' headers move up beside the
  clock, which takes only the top right corner. The pane under the glyphs
  reports their width through `StatusRowScope.trailingReserveOf(context)` for
  the end of its `AppBar` actions. Off by default.
- `MasterDetailConfig.portraitPaneRatio`: the master's share in a portrait
  window, ahead of `alignToWindowCenter` and `paneRatio`. The user's drag, a
  fold and the pane minimums still win.
- `AdaptiveShellConfig.actionsInStatusColumn` (experimental, iOS): on iPhone
  Duo's inner display in landscape the empty part of the status column, below
  the clock, goes to the pane against it (`StatusColumnScope.of(context)`).
  `StatusColumnActions` moves a screen's header actions there and back with a
  short fade. Off by default.

### Fixes

- On Android the rail no longer sits under the navigation buttons or a camera
  cutout on its edge in landscape: its background reaches the edge, its
  destinations start after the inset (`PaneMetrics.railCutoutInset`).

## 0.12.0

### Features

- `AdaptiveShellConfig.backToBranch`: system back at the root of any other
  branch switches to that branch instead of closing the app, the way most
  Android apps return to their start tab. Dialogs, the drawer, pushed screens
  and a detail are popped first, and the root's `onExit` is asked as on a tab
  tap. `null`, the default, keeps the old behaviour.
- `MasterDetailConfig.alignToWindowCenter` puts the boundary between the panes
  on the window's horizontal centre instead of at `paneRatio`. The user's drag
  and an active fold still win, and the pane minimums still apply.

### Fixes

- On Android with predictive back, system back could close the app instead of
  going back — after a push into a branch without master-detail, or after
  switching to a tab with screens above its root. Every navigator of the shell
  reported to the system and the last one won. The shell now sends one answer
  for all of them. Apps that worked around this with their own
  `onNavigationNotification` in `MaterialApp.router` can remove it.
- System back closes a dialog on the root navigator (the default for
  `showDialog`) instead of the screen under it or the app.
- System back closes an open shell drawer, with predictive back too. A drawer
  or `showBottomSheet` inside a screen still is not reported to the system;
  see "System back" in the README.
- A screen's own `PopScope(canPop: false)` now holds system back for an entry
  pushed without `onExit`; the screen used to be removed anyway.

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
