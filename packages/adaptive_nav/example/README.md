# adaptive_nav example

A small contacts app. Resize the window and watch what does *not* happen:
nothing remounts.

## What it shows

- **People** is a master-detail branch. Below 540 logical pixels of pane area
  it is a plain stack; above it the list and the person sit side by side, the
  boundary starts at 40 % in portrait (`portraitPaneRatio`) and on the window
  centre in landscape (`alignToWindowCenter`), and can be dragged
  (`PaneSplitController`, with `onCommit` firing on release). The
  minimums behind that number are picked so the inner display of an iPhone Duo
  in portrait still splits; the package's own defaults are wider.
- **Settings** is a plain tab with a switch. Leave the tab and come back — the
  switch is where you left it, because the branch navigator stays mounted.
- **Teams** is a list with a pushed team screen. **Starred** has a filter
  drawer of its own, closed by system back through the README's `PopScope`
  workaround. **Recent** holds notes whose editor blocks back while the text
  is unsaved. **Archive** and **Trash** ask in a dialog. **Calendar**, **Files**
  and **Tags** are plain lists, there for the number of tabs.
- **How many tabs** is `--dart-define=TABS=<n>`, from 2 to 10, 7 by default:
  People and Settings, then the sections in the order above. With more tabs
  than the iPhone Duo column holds, the last place of the tabs becomes More,
  with the rest behind it; turned, the outer display holds six, so seven make
  five and More. There a screen with a button — Starred's filter, Trash's
  Empty — leaves no room beside six places, and the tabs fold to two buttons,
  the current tab above More, until you are back on a screen without one. With two or three tabs nothing
  folds and no More appears.
- The person, the person's editor, a team, Starred, a note and Trash
  describe their toolbars with `PaneToolbar`. On iPhone Duo, beside the
  system's bar, the shell stands them at the top of the column, apart from
  the tabs at its bottom, with a menu of their own for what does not fit:
  Close and Edit for a person, Back and Save for the editor, a team's Back,
  the filter, the note's Back (its Save is a word and stays in the header),
  and Empty, which has an icon so that it can. A screen without one would get
  its Back there too (`automaticBackInColumn`). On the inner display in portrait the headers sit
  beside the clock (`liftHeadersIntoStatusRow`, experimental; see `PaneAppBar`
  in `lib/screens.dart`).
- An open person covers the bar, or the rail beside one pane, as Material
  does (`detailChrome`). Run with `--dart-define=DETAIL_CHROME=kept` to keep
  them beside it on iOS, as a tab bar stays there; on iPhone Duo the column
  then reads status bar, Close, Edit, tabs.
- The tabs in the iPhone Duo column are icons, as Apple draws a vertical tab
  bar. Run with `--dart-define=RAIL_LABELS=all` to name them all, or
  `selected` to name the current one; either way no tab moves as you switch.
  Labels take room: on the outer display turned four tabs have a place
  instead of six.
- System back at the root of any tab but People returns to People
  (`backToBranch: 0`).
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
- Routes encode as `/people`, `/people/3`, `/people/3/edit`, `/settings`,
  `/teams`, `/teams/1`, `/starred`, `/recent`, `/recent/1`, `/archive`,
  `/trash`, `/calendar`, `/files` and `/tags`, so deep links and the browser
  address bar work. A link to a section the app was started without opens
  People.

## What it leaves out

Deliberately — one readable app cannot also be a feature matrix. Not shown
here: custom `barBuilder` / `railBuilder` chrome, the shell drawer, chromeless mode
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
and fold buttons and a choice of 2, 3, 5, 7 or 10 tabs. The [online playground](https://nightdevcraft.github.io/adaptive_nav/)
is this file:

```sh
cd example
flutter create --platforms=web .
flutter run -d chrome -t lib/playground.dart
```

The page holds a single instance of the app. Switching devices, rotating and
folding only change its `MediaQuery` and the theme's platform (iOS on the
phone, tablet and iPhone Duo, Android on the Galaxy), so open screens and their
state stay. Another number of tabs is another navigation, since the shell's
branches are fixed for the life of one: every tab that stays opens on the
screen it showed, a person or a team still open, but what a screen holds in
its own state — a switch, a filter, an unsaved edit — starts over.

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
