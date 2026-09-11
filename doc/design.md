# Design notes

Why the package is put together the way it is. Most of this was learned the
hard way, on devices, and is written down here so it does not have to be
re-learned. The API reference lives in the doc comments; this file is the
reasoning behind them.

## One state, two renderings

Navigation is a value: `NavState` holds the active branch and every branch's
stack, all with `==` by value. It lives in a delegate that is created once and
never rebuilt.

A resize changes only how that value is rendered. Nothing about the state
changes, so nothing needs to be rebuilt from it — and the branch `Navigator`s,
which hold the actual screens, are addressed by stable `GlobalKey`s. They move
between `Stack` and `Row` as whole subtrees. That is the entire trick behind
state surviving a rotation; there is no serialisation, no restoration and no
`PageStorageKey` anywhere.

An entry's `pageKey` is a separate thing and does much less work than it looks
like: it gives a `Page` identity inside its own `Navigator`. Entries never
migrate between navigators.

## The layout is decided at build time

`AdaptiveShell.build` reads `MediaQuery` and computes widths arithmetically.
There is no `LayoutBuilder` between the shell and the branch screens, and there
is a test that keeps it that way (`layout_decision_test.dart`).

It used to be a `LayoutBuilder`. Crossing a threshold then moved the branch
navigators by `GlobalKey` from inside the layout callback, and the first time a
deferred overlay child reactivated during that move — a rail tooltip, a menu,
anything built on `OverlayPortal` — Flutter asserted:

```
_RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout
```

It never reproduced in `flutter test` until the harness screens were given a
live `OverlayPortal` of their own. Forty-six tests had passed over the hole.

The consequence is that every width has to be known without measuring:

- `railWidth` is declared, not measured, and the package clamps the actual rail
  widget to it. A rail that grew with the length of its labels used to eat into
  the panes silently and push the detail off the edge of the screen.
- `PaneDecoration` margins and gap are data for the same reason. They reduce
  the width left to the panes, so they belong to the threshold arithmetic, not
  to a theme.

An app that computes "is this the wide layout" with its own formula has to
subtract the same values, or the shell and the screens will disagree at the
boundary. The shell computes it in `paneAreaWidthFor`, which is currently
internal — an app has to mirror the same subtraction.

## Three layouts, not two

Chrome and pane count are decided separately:

| Width | Chrome | Panes |
| --- | --- | --- |
| `< 600` | bar | master in the body, detail overlaying the bar |
| `600–840` | rail | one pane |
| `> 840` | rail | two panes |

Two states would be simpler and wrong: a wide window with a narrow content area
has room for a rail but not for two unsqueezed panes. The chrome threshold is a
breakpoint; the pane count is `MasterDetailConfig.fits`.

## Transitions follow the layout, not the push

`AppTransition.adaptive` picks its transition while the animation runs.

Baking the choice in at push time does not work, because a transition belongs
to the page and therefore also plays the dismissal: an editor opened on a
tablet would still fade out after the window shrank to phone width. Swapping
the entry's `transition` on resize is worse — that changes the `Page` type,
`Navigator.canUpdate` returns `false`, and the screen is remounted with its
state gone.

So there is one page type at every width, and `transitionsBuilder` decides per
frame. It reads `DetailPaneScope`, which the shell puts above the detail
navigators, rather than recomputing the layout from `MediaQuery` — a second
source of truth would disagree with the shell exactly at the boundary.

In a pane, `secondaryAnimation` is ignored on purpose. Going deeper, from a card
to its editor, should not push the card away: the arriving screen fades in over
it.

## The keyboard belongs to the focused pane

Both shell `Scaffold`s run with `resizeToAvoidBottomInset: false`.

With the default `true`, the keyboard height was subtracted twice. The shell
squeezed the whole body — rail and both panes — and then the screen inside a
pane subtracted it again, because the panes' subtree receives the window's
`MediaQuery` afresh, with `viewInsets` untouched. On an iPad in landscape the
keyboard is about half the screen; twice that left the panes as empty
rectangles.

Squeezing the whole shell was never right anyway. The rail and the neighbouring
pane have nothing to do with a text field in the other pane.

The cost is a requirement on the consumer: a screen inside a pane needs its own
`Scaffold`, or its own handling of `viewInsets.bottom`.

## Snack bars are scoped to a pane

Each pane gets its own `ScaffoldMessenger`.

A `ScaffoldMessengerState` shows a snack bar in every root `Scaffold` of its
set, where "root" means one without a registered `Scaffold` ancestor. This
layout produces two of those on compact — the shell and the detail layer, which
is a sibling of the shell `Scaffold` rather than its descendant — so one message
was drawn twice. The wide layout had no duplicate, but the shell drew it and
the bar stretched under both panes, for an action that happened in one.

The messenger keys live in the delegate, next to the navigator keys, for the
same reason: a pane moves between layouts and a visible snack bar has to
survive the move.

## What animates, and what does not

Two places animate a *progress* between 0 and 1 and recompute the widths from
the live window width every frame: the detail reveal and the immersive rail.

Animating the width directly was the first attempt. During a window resize the
tween's target moved every frame, so each frame started a new quarter-second
journey and the pane boundary trailed the window edge by about that much. With
a progress, the target does not depend on the width and a resize lands in the
same frame. `pane_resize_lag_test.dart` measures widths after a single `pump()`.

The same arrangement removes the need for a special case while the divider is
being dragged: the drag moves the final width while the progress stays put.

### Immersive mode is deliberately narrow

`AdaptiveShellConfig.immersive` slides the rail out and gives the strip to the
panes. It changes geometry and nothing else:

- **The layout class stays frozen.** The freed strip is enough to carry a branch
  across the `fits` threshold, which would move the branch navigators by
  `GlobalKey` in the middle of an animation, and would put the app's own layout
  formula out of step with the package's. The layout class is a property of the
  window, not of whether the chrome is visible.
- **The detail is untouched.** Closing it is a `NavState` mutation, which is
  navigation, and navigation is the app's call.
- **Nothing happens on compact.** Hiding a bottom bar is a different mechanism,
  and a floating bar comes from `barBuilder` anyway.
- **The flag is read-only for the package.** A shell that silently cleared the
  app's flag would leave the app out of sync with the picture.

## Guards run on every way out

An entry's `onExit` gates back, gestures, the app bar, `replace`, `resetTo`,
`popToRoot`, `resetDetailTo` — and switching tabs.

The tab switch was the contested one. The first version parked the screen
instead of gating it: nothing is destroyed, so why ask? Because the app being
replaced asked, and users expected it to. A parked editor with unsaved text is
unsaved text.

Ordering differs between the two paths, and both are deliberate:

- `goBranch(index)` gates the **current** branch's top screen **before**
  switching. The question is about the screen the user is looking at, so the tab
  must not change before the answer, or the dialog hangs over somebody else's
  tab.
- `goBranch(index, resetToRoot: true)` enters the branch **first** and gates the
  **target** branch's stack after, because that is the stack being destroyed and
  the dialog should appear over the screen it is asking about.

Screens without a guard prompt for nothing, and such a switch stays synchronous,
completing in the same frame. Anything else would leave a window for re-entry on
an ordinary tap.

Two details that are easy to get wrong:

- The branch is captured before the gate. While a dialog is up, another branch
  can become active, and the answer applies to the branch that was asked about.
- After the gate, the stack is compared by identity against what was gated. A
  push or a deep link may have arrived meanwhile, and it never passed the gate.

## `resetDetailTo` is a primitive, not a composition

Picking another item in a master-detail list is a lateral move: the old detail,
at whatever depth, goes, and one new screen takes its place.

`popToRoot()` followed by `push()` looks equivalent and is not. `popToRoot` does
not report the gate's verdict, so the push happens even after a cancel. And two
mutations produce a frame with an empty detail, which
`collapseWhenDetailEmpty` turns into a reverse reveal — the pane flinches on
every selection.

## Small things with sharp edges

**Card layers.** A floating card is three wrappers in a fixed order: the shadow
outermost and behind, the border outside the clip but in the foreground, the
clip innermost. Inside the `ClipRRect` the shadow is cut off with the corners;
in the background the border is covered by the opaque fill of the screen inside
the card.

**The border, not the shadow, holds the shape.** In a dark theme a shadow is
dark on dark, and the card fill differs from the background by a few percent.

**Detail navigators are always mounted**, empty ones included — an empty one
holds a single transparent page. A `Navigator` cannot exist without pages, and
an unmounted one would lose its `GlobalKey`.

That base page does one more job: without it a detail would be the first page of
its navigator, and `AppBar` only draws a back arrow when another route sits
below it (`impliesAppBarDismissal`).

**`DragStartBehavior.down` on the split handle.** With the default, the
recogniser eats the touch slop — 20 logical pixels — to confirm the gesture and
reports deltas from the point of acceptance, so the divider trails the cursor by
those 20 px forever.

**The drag reads the controller, not the last frame.** A frame does not
necessarily carry one move, and a delta computed from what was drawn loses every
move but the last.

**Branch fade is two-phase, not a cross-fade.** `IndexedStack` draws exactly one
branch; two rendered at once would overlap two `Scaffold`s and two `AppBar`s.
The index in the state changes immediately, so the chrome highlights the new
destination without delay, and only the display is held back.

**Branches mount lazily** and then live for good. Mounting them all at start-up
would build every tab's screens with their `initState`s, subscriptions and
animations, for tabs the user never opened.

**The left inset is not subtracted from the content area.** The rail sits
against the edge and covers a landscape notch rather than growing by it, so the
content gets exactly `window − rail − divider`, and the inset is removed for the
panes' subtree.

It is removed for the rail's subtree too, which is less obvious. Material's
`NavigationRail` carries a `SafeArea` of its own, and on a notched phone in
landscape that inset is 59 of the rail's 80 logical pixels: the region keeps its
declared width while the destinations are squeezed into the 21 that are left,
one letter of the label per line. A custom rail from `railBuilder` gets the same
treatment, so the declared `railWidth` stays the width the rail can actually
lay out into.

**The top inset is handled once, by the shell.** On compact the screen's
`AppBar` reserves it. On wide the screen lives inside a pane whose top edge is
the window edge, so without a reserve a floating card slides under the status
bar.
