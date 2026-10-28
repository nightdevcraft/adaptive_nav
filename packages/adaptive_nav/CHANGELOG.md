## 0.15.0

### Breaking

- `ChromeLayout` takes a third argument, the `SystemGeometry?` from the
  nearest `SystemGeometryScope`, `null` without one. A custom layout adds the
  parameter; `defaultChromeLayout` takes it as an optional third, so a direct
  call with two still compiles.
- `defaultChromeLayout` puts the chrome on the side of a one-sided inset of
  `kVerticalBarInset` at any width, not only below the breakpoint. On iPhone
  Duo's inner display in landscape the rail moves from the left edge into the
  system's column on the right, where Apple keeps the bar as the device
  unfolds; the master starts at the left edge and the detail ends against the
  column. No other device measured reports such an inset, and
  `chrome_layout_test.dart` keeps them as they were.
- `SystemBarEndResolver` takes the display's size as a third argument.
  `defaultSystemBarEnd` puts the reserve at the bottom of a right-hand column
  only on the outer display; the inner display keeps its status area at the
  top in both landscape orientations.
- `SystemBarMetrics.measured` follows the status areas UIKit reports on the
  simulator rather than numbers read off screenshots: `reserve` 170 (was 150),
  `landscapeReserve` 82 (was 80) and `statusRowTrailing` 134 (was 120), with
  a new `innerReserve` of 120 for the inner display, landscape and Split
  View. Outer and inner are told apart by
  the display's size (`kCompactDisplayShortSide`), not the window's.
- `AdaptiveShellConfig.actionsInStatusColumn`, `StatusColumnScope` and
  `StatusColumnActions` are gone, and `SystemBarMetrics.statusColumnTop` with
  them; they were experimental. `PaneToolbar` replaces them: the screen
  describes its toolbar once, and the shell stands it in the system's column
  wherever Apple asks for a vertical one — the rail's column included, which
  the old option could not share — and hands the screen a header everywhere
  else. With a `chromeLayout` that keeps the rail away from the column, as the
  old option needed, the toolbar has the column to itself, as before.
- An open detail over a single pane now covers the rail beside it, as it
  already covered the bottom bar: the detail takes the whole window and the
  rail comes back with the detail's own transition. On iPhone Duo only the
  rail's destinations go: the system's column stays, its status area,
  background and the detail's toolbar, which has all of it, and the detail
  stands beside it, in the single pane's area and with its padding, as a pane
  does on the outer display. An iOS swipe back still starts at the window's
  edge (see Features). `AdaptiveShellConfig.detailChrome: DetailChrome.kept`
  keeps the rail, and the bar, on iOS and macOS.
- In the system's column on iPhone Duo the rail is no longer Material's
  `NavigationRail` under the toolbar but two zones, as Apple lays the column
  out: the screen's toolbar at the top, below the status area, and the tabs at
  the bottom, icons only by default (`railLabelsInColumn`). The tabs' places
  depend on the column's height alone, so they no longer move as tabs and
  screens change, and with more tabs than places the last one is More. No
  room is kept for a toolbar the screen does not have; a screen whose
  toolbar does not fit even its navigation button and menu beside the tabs
  folds them to the selected tab and More. A `railBuilder` rail still stands
  under the toolbar, as before.
- While a fold holds the pane boundary, the panes meet on the hinge — the
  middle of the crease, or the line a zero-width `foldLocator` gives — and the
  crease is an inset rather than a gap: each pane's background reaches the
  hinge and its screens get half the crease as `MediaQuery.padding` on that
  side, 20 on iPhone Duo, the way they get an underlapped safe-area inset.
  Before, the master ended where the crease started and the visible seam stood
  20 points past the hinge. With cards, `PaneDecoration.gap` is split evenly
  around the hinge and counts towards the inset. `MasterDetailConfig.fitsAround`
  checks the minimums against the width less the inset. A flat posture is
  unchanged.
- Tapping the active destination again goes back to the branch root, as
  `UITabBarController` does and Material advises; before, it did nothing.
  It is `popToRoot`, gated by the `onExit` of every screen above the root, so
  a refusal keeps the stack; in a master-detail branch the detail goes too.
  The bar, the rail, the tabs in iPhone Duo's column, folded or not, the
  ticked item in More and the rail's overflow menu all do it, and so does a
  `barBuilder` or `railBuilder` that calls `onSelectBranch` with the active
  branch. `goBranch` with the active branch stays a no-op.
  `AdaptiveShellConfig.reselect: BranchReselect.none` keeps the old
  behaviour.
- On iPhone Duo, beside the system's bar, a screen without a `PaneToolbar`
  loses the `AppBar`'s arrow to the column (see Features);
  `AdaptiveShellConfig.automaticBackInColumn: false` brings it back. The
  pages and routes the package builds stay subclasses of `MaterialPage` and
  `MaterialPageRoute` (`platform`, `modal`, and now `adaptive` too) and of
  `PageRouteBuilder` (`fade`, `none`); only `impliesAppBarDismissal` is added.
- `Navigator.maybePop` from a screen of an inactive branch now does nothing;
  `Navigator.pop` still pops it (see Fixes).

### Features

- `AdaptiveShellConfig.reselect` and `BranchReselect`, and
  `AdaptiveShellConfig.onReselect`, called after every tap on the active
  destination with the branch and whether anything was popped — `false` at
  the root, the moment to scroll a list to its top, as iOS does on a second
  tap.
- `AdaptiveShellConfig.detailChrome` and `DetailChrome`: whether an open
  detail over a single pane covers the bar or the rail (`covered`, the
  default, Material's full-screen detail) or leaves it in view and in use
  (`kept`, as iOS keeps a tab bar beside a pushed screen; over a bar the
  detail ends at its top edge). `kept` applies only where the theme's
  platform is iOS or macOS and is ignored elsewhere. Two panes are not
  affected.
- iPhone Duo's system column in two zones. The toolbar's zone is at the top,
  `SystemBarMetrics.columnInset` (24) below the status area or the window's
  edge, with a "•••" menu of its own as its last button. The tabs' zone is at
  the bottom, its last tab 24 above the window's edge, or above the status
  area where that is at the bottom; buttons and tabs are circles of 48, the
  tabs one group 6 apart, as Apple's tab bar is one capsule, and the zones 12
  apart. How many tabs have a place depends only on the column's height and
  the labels, never on the selection or the screen's toolbar, and keeps no
  room for a toolbar, as Apple's tab bar does not (`prefersTabBar`): seven
  tabs all have a place on the outer display upright and on the inner one in
  landscape, and six on the outer display turned, five and More. Switching
  tabs or screens changes the toolbar's zone and leaves every tab where it
  is; a new window size changes the places at once. With more
  tabs than places the last place is More, a grid icon with a menu of the
  rest, lit while the selected tab is one of them; `visibilityPriority` picks
  which tabs those are, and `railOverflowBuilder` can draw More. The README
  has a table of how many tabs each posture holds.
- The system's column goes with the route transition that changes it, as
  `UINavigationBar` goes with a push: the tabs under a covering detail, the
  toolbar's zone from one screen to the next and the tabs folding follow the
  route's `animation` — what goes is gone by its middle, what comes comes
  after, never one over the other — and a swipe back on iOS or predictive
  back on Android leads them by the finger, back to where they were if the
  gesture is cancelled. A tab switch keeps its own cross-fade; a transition
  without animation, a new window size or a turn of the device changes the
  column at once. Nothing is built frame by frame for it.
- An iOS swipe back from the window's edge, through iPhone Duo's system
  column. With the column at the leading edge, a single pane stands beside
  it, so the screen's own swipe starts a column's width in; the shell takes
  a swipe anywhere from the glass to the pane's edge, the rail's divider
  included, and leads the pane's top screen with it, as the screen's own
  swipe would, with the same transition, guards and column. It does so for
  any single pane beside the column that can go back — a covering detail, a
  kept detail, a screen over a detail, a screen pushed in a plain tab — and
  taps on the toolbar, the tabs and More stay taps. At a tab's root, over two
  panes and on Android there is no such swipe.
- `AdaptiveShellConfig.railLabelsInColumn`: the tabs' labels in that column —
  `NavigationRailLabelType.none` by default, icons as Apple draws a vertical
  tab bar, with the label as the tooltip; `all`; or `selected`, which names
  only the current tab but keeps the room for a label under every tab, so
  that none moves on a switch. Everywhere else the rail shows every label.
- `SystemGeometry` and `SystemGeometryScope`: what the platform says about the
  window's own chrome — the side it wants a vertical bar on, its status area
  and the active folds. The shell takes the side, the reserve, the status row
  and column and the fold from it, and reads `MediaQuery.padding` as before
  without one. adaptive_nav_ios provides it on iPhone Duo from UIKit, which
  gets the left half of Split View right — a rail on its left edge, where the
  padding alone gives a bottom bar — and the half-open fold.
- `AdaptiveShellConfig.railAlignment`: `RailAlignment.bottom` gathers the
  default rail's destinations at the bottom of the column, within reach of the
  thumb, and moves the overflow button to the top; `RailAlignment.center`
  centres them, and `RailAlignment.top` leaves `NavigationRail.groupAlignment`
  to the theme. Which destinations go behind the button does not change.
  Unset, a rail that shares the system's column goes to the bottom and every
  other rail to the top. iPhone Duo's system column has tabs of its own, at
  its bottom whatever this says.
- `FoldMetrics.fromRects` converts the folds a platform reported, with the
  rules `paneFold` applies: vertical and inside the pane area. The shell asks
  `MediaQuery.displayFeatures` first, then `SystemGeometry.folds`, then
  `foldLocator`.
- `PaneToolbar`: a screen's toolbar, laid out by the shell. A header with
  `leading` and `actions` for its `AppBar` — up to `maxHeaderActions`, the
  rest behind a menu — and on iPhone Duo, for the pane against the system's
  bar, a vertical toolbar at the top of the system's column: the navigation
  button (Close or Back, decided unless given), the `pinned` actions, then the
  `groups`. Circles of 48 points, 6 apart within a group and 12 between
  groups (`kPaneToolbarItemExtent`, `kPaneToolbarItemGap`,
  `kPaneToolbarGroupGap`), as measured on Safari's. Only the screen on top
  of its pane's navigator is drawn there, and changing sides or screens fades
  without building the screen again: a screen change with its route's
  transition, as below. `PaneToolbarItem` carries the icon, the
  label (tooltip and menu text), the callback, `visibilityPriority` and
  `horizontalOnly`; an item without an icon stays in the header.
- `AdaptiveShellConfig.automaticBackInColumn`, on by default: a screen
  without a `PaneToolbar` gets its navigation button in iPhone Duo's system
  column, as `UINavigationController` puts Back in the vertical bar. Wherever
  the pane's toolbar is vertical, the shell stands the button a `PaneToolbar`
  would pick — Close on a detail's first screen or a full-screen dialog, Back
  where there is something to go back to — in the column's toolbar zone, with
  the same transitions, swipe back and exit guards, and the screen's `AppBar`
  draws no arrow meanwhile; where the toolbar is a header, the arrow is the
  `AppBar`'s as before, and it moves there and back with the pose. An `AppBar`
  with a `leading` of its own, or `automaticallyImplyLeading: false`, is left
  as it is, and the column gets nothing.
- `PaneBar` and `PaneBarScope`: the edge a pane's toolbar stands against,
  vertically, or `null` for a header.
- `VerticalBarCompression` and `BranchConfig.verticalCompression`, overridden
  by `PaneToolbar.compression`: who gives way when the toolbar does not fit
  above the tabs. `toolbarFirst`, the default (Apple's `prefersTabBar`), keeps
  every tab in its place and puts toolbar items behind the toolbar's menu,
  the lowest `visibilityPriority` first, from the bottom up; when the tabs
  leave too little even for the navigation button and the menu, it folds them,
  as the system's tab bar does in a short column. `tabsFirst`
  (`prefersToolbarItems`) folds them as soon as the toolbar does not fit
  whole. Folded, the tabs keep two places: More, where the last place was,
  with a menu of every tab, and the selected tab above it, which does what
  it did unfolded; the toolbar gets the rest. Where two places leave too
  little for the navigation button and the menu, More stays alone, filled.
  Folding goes with the screen's transition without building a screen again:
  the other tabs fade, the selected one moves down to its place, More stays
  put; unfolding is the same backwards. The toolbar's menu and the tabs' More
  never mix.
- `BranchConfig.visibilityPriority`: which destinations the rail puts behind
  its menu first — the lowest, the last of equals first. The order in the
  rail does not change.
- `SystemBarMetrics.reserveFor` and `followsSystemGeometry`;
  `SystemBarMetrics.none` ignores a reported status area too.
- A rail with no column to share and nothing at the top of the window keeps
  `cornerClearance` free at its top, out of the rounded corner.
- The pinned items of a `PaneToolbar` are tinted with the scheme's primary
  colour, without a fill, in the column and in the header alike; a filled
  circle is the selected tab.

### Fixes

- Android's predictive back gesture closes the top screen of the active branch
  only. Every branch visited stays mounted, and its top screen took the
  gesture too: one swipe also closed a detail, or any pushed screen, in a tab
  out of view. Screens of an inactive branch now decline system back, the
  same way a `PopScope(canPop: false)` does.

### Deprecated

- `FoldMetrics.windowCentre`. It cannot see the posture and puts the boundary
  down the middle of a flat device too; adaptive_nav_ios reports the real
  fold, active only while half open.

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
