# adaptive_nav example

A small contacts app. Resize the window and watch what does *not* happen:
nothing remounts.

## What it shows

- **People** is a master-detail branch. Below ~680 logical pixels of pane area
  it is a plain stack; above it the list and the person sit side by side, and
  the boundary between them can be dragged (`PaneSplitController`, with
  `onCommit` firing on release).
- **Settings** is a plain tab with a switch. Leave the tab and come back — the
  switch is where you left it, because the branch navigator stays mounted.
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
