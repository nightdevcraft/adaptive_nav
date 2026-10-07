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
boundary. That arithmetic is `PaneMetrics`, and it is exported for exactly this
reason.

## A pane bleeds under an inset; it does not own the width

`PaneMetrics.paneAreaWidth` subtracts the horizontal safe-area insets that
nothing else covers, and the panes are then laid out *wider* than their share
by the same amount.

This reads like a contradiction and is not. Apple's own rule is that background
reaches past the safe area while foreground stays inside it, so a pane card has
to touch the window edge — stopping short would leave a strip of canvas beside
an opaque screen. But the width under the status bar is not width the screen
can use, so it must not count towards `fits`, towards `paneRatio`, or towards
`detailMinWidth`. The two requirements are met by laying the pane out over the
inset and handing the inset down in its `MediaQuery`, where the screen's own
`SafeArea` takes it away again. `PaneUnderlap` is the amount involved.

On a notched phone this was worth a couple of pixels, which is why the first
version of the arithmetic simply ignored insets. iPhone Duo made it visible:
its status bar is a vertical strip 84 points wide, on the left or on the right
depending on the posture. Dragging the divider fully right on the inner display
in landscape left the detail 276 points wide while `detailMinWidth` said 360.
`duo_poses_test.dart` pins that number down.

Two details that follow from the same reasoning:

- **The inset on the rail's own edge belongs to the rail.** It is covered or
  shared there (see below), so the pane against it does not also pay. An inset
  on any other edge is the panes' to bleed under — including a system bar the
  rail did not go to.
- **`PaneDecoration.margin` is subtracted first, and only what is left of the
  inset counts.** A card held 12 points off the edge underlaps 84 − 12 of the
  status bar, and the 12 are already gone as decoration. Counting the whole
  inset again would take it twice.

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

The separation turned out to be load-bearing. iPhone Duo's inner display in
portrait wants a bottom bar *and* two panes, which the table above never
produces — every wide layout in it has a rail. Because the two decisions were
already independent, the fourth combination cost one branch in `_buildBar`
rather than a fifth layout.

That branch splits the top inset instead of reserving it whole. The question is
who is at the window's top edge: with one pane the screen is, and its `AppBar`
reserves the inset itself; with two panes a *card* is, and neither end of the
inset belongs entirely to the shell or entirely to the screen. Reserving it in
the shell (as the rail layout did before 0.11) leaves the card starting below the inset
*and* below its own margin, which on the display this branch exists for is 94
points of bare canvas under the clock. Leaving it to the screens has each
`AppBar` reserve it inside the card, below the margin, and sit that much too
low.

So the card bleeds up under the status bar the way the panes bleed under a
horizontal inset: the margin is held back from the window's top edge, and
`padding.top − margin.top` is handed to the screens, where the `AppBar`
reserves it. The title lands on the same line either way; what changes is that
the strip under the clock is the card's own background and the card is 70
points taller.

In 0.11 the rail layout switched to the same scheme. With the inset reserved
once for the whole layout, an Android tablet or a phone in landscape showed a
single colour under the clock across the rail and both panes, which looked
wrong when those three had different colours. Now the rail and the panes extend
under the status bar. The rail reserves the inset inside its own surface and
removes it from `NavigationRail`'s `SafeArea`; the panes pass
`padding.top − margin.top` to their screens. The status bar icons have one
style for the whole bar, so the three colours need to be all light or all dark.

## The chrome follows the system's own bars

`AdaptiveShellConfig.chromeLayout` returns where the chrome goes — bottom, left
or right — instead of the "rail or bar" boolean it used to be.

The third answer exists because of iPhone Duo. The device puts the status bar
and the Dynamic Island in a vertical strip along one edge and asks apps to put
their bars on the same edge, so that controls stay where the hand is as the
device folds and turns. The strip moves: right on the outer display in
portrait, left when that display turns. On the inner display in portrait it
goes back to the top, and Apple asks for ordinary horizontal bars there.

None of that needs a plugin, a platform channel or `displayFeatures`. The
system announces its choice in `MediaQuery.padding`, and the discriminator is
**asymmetry**:

| | left | top | right |
| --- | --- | --- | --- |
| iPhone 18 Pro, portrait | 0 | 62 | 0 |
| iPhone 18 Pro, landscape | 62 | 0 | 62 |
| iPad | 0 | 24 | 0 |
| Duo outer, portrait | 0 | 0 | **84** |
| Duo outer, landscape | **84** | 0 | 0 |
| Duo inner, portrait | 0 | 82 | 0 |
| Duo inner, landscape | 0 | 0 | **84** |

A notched iPhone in landscape reserves both sides, and a display cutout
reserves one but is half as wide; a bar standing on its end is the only thing
that is wide *and* one-sided. The inner display in portrait is then separated
from a tablet of the same proportions by the depth of its top inset — 82
against 24 — which is the system saying "this is a phone".

Both thresholds are empirical, and both are named constants with the
measurements in their doc comments. `chrome_layout_test.dart` asserts that
every non-Duo pose still decides exactly as the old width breakpoint did; that
test is the contract.

### The rail joins the system's column; it does not take a second one

On the outer display the camera sits at the end of the vertical strip and the
status bar runs below it, and Apple's point is that the controls line up with
the camera. So the rail goes *into* that column: `PaneMetrics.railColumnWidth`
is the wider of the rail's own region and the system's inset, never their sum,
and `AdaptiveShellConfig.systemBarReserve` keeps the top of it free so the
destinations start below the clock rather than under it.

Two numbers there are measured, not derived, because nothing reports them: how
far down the system's glyphs end, and the line they are centred on. The second
one is not the middle of the column — the symmetric wifi glyph sits 36 points
into an 84-point column, which is 48 in from the window edge — so a rail simply
centred in the column would still miss the clock by six points, and a rail
flush against the edge misses it by eight. `SystemBarMetrics` holds both, with
the measurements in its doc comment, and is configurable for exactly the reason
that they are a screenshot's word rather than an API's.

Sharing rather than stacking also settles the pane count without a rule about
displays. The outer display gives up 84 points to the column and keeps 382 in
portrait and 594 in landscape, both below any minimum wide enough to split the
inner display's 669 — so the outer display collapses to a single pane on its
own, which is what Apple asks for.

The inner display in landscape is the other case, and it does not follow the
bar. There is room for the rail and both panes in the arrangement they have on
every other device, and moving the rail to the trailing edge for one posture
would make the layout jump as the device unfolds. So the rail leads, and the
detail pane bleeds under the system bar on the far edge like any other inset —
which is what the underlap arithmetic above is for.

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

## The hinge outranks the ratio

While the device is half open, `MasterDetailConfig.alignToFold` puts the pane
boundary on the crease and parts the panes by its width.

This is the one case where the split's position is not a preference. A ratio,
or a width the user dragged, is a choice about how to divide a flat plane;
half open there is no flat plane, and a pane laid across the crease is bent
over two of them. So the fold wins while it is reported active, the divider
stops being draggable — the hinge decided, and a handle would be a lie — and
the app's width comes back when the device goes flat. The boundary moves once
and once back rather than settling somewhere new, which is what the guidance
to keep folding calm asks for.

It wins only where both panes still clear their minimums around it. A crease
near one edge would squeeze one pane below the width it declared, and the
package would rather ignore the hinge than break its own promise.

`FoldMetrics` reads `MediaQuery.displayFeatures` and takes a feature only if it
is a fold, **active**, **vertical** and **inside the pane area**. A flat
posture reports the fold too, and a crease on a continuous display occludes
nothing; a horizontal fold says nothing about a vertical boundary; and a fold
behind the rail is not a boundary either pane could sit against.

The framework fills `displayFeatures` on Android and not yet on iOS, so this
runs on a book-style foldable today and is inert on iPhone Duo until the
framework catches up — and there is nothing to change here when it does. It is
also not reachable by hand: Xcode 27.1's simulator has open, closed and rotate
and no posture between them, so `fold_split_test.dart` injects the feature.

## Counting the rail's destinations instead of measuring them

The default rail hides what its column cannot hold behind a menu at its end.
Deciding how many that is means knowing the column's height and a
destination's — and the second one is not a constant, because a label too wide
for an 80-point rail takes a second line and that destination grows with it.
"Home" is 64 points; "People" is 80.

The obvious answer is a `LayoutBuilder`, and it is the one this file already
has a section against: the rail carries `OverlayPortal` tooltips, which is
exactly the combination that used to assert. So instead the shell lays the
label out with a `TextPainter` — arithmetic over the *declared* `railWidth`,
not a measurement of the tree — and adds it to `kRailDestinationBase`. Every
other term is already declared or known: the window, the inset reserved once,
the rail card's margin, what the system bar keeps, the button's own height.

The heights are added up one destination at a time, not multiplied out from
the tallest. Material lays each destination out on its own — a rail of "Home"s
beside one "People" is a column of 64s with a single 80 in it — so counting
them all at 80 lost a whole destination to a single long label and left the
column visibly short of the menu it had just filled.

That is also why the button's own height is fixed rather than measured: a
`railOverflowBuilder` supplies the widget and the shell supplies the
56-point slot, so the term the count spends on the button stays a term the
count knows. An app that wants more than a slot has `railBuilder`, where the
whole rail — overflow included — is its own.

`rail_overflow_test.dart` pins the two measured numbers and then sweeps
heights against destination counts, with wrapping labels and short ones,
asserting that nothing ever overflows. One spacer forgotten and that sweep
fails by exactly that spacer, which is the point of it.

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

## One answer for system back

With predictive back Android hands back to Flutter only while the app has said
it can handle it, and `WidgetsApp` passes on whatever the last
`NavigationNotification` said. One navigator per app makes that right; the
shell mounts several — every visited branch, a master and a detail — and the
last to report is often the wrong one: an empty detail says "no" after a push
into another tab, and back closes the app.

So each navigator's report stops at the shell, and the delegate sends one of
its own, recounted from the same rule `popRoute` follows: the root navigator
(dialogs, the drawer), the active branch's top screen, a detail, then
`backToBranch`. It is recounted after every state change too, because a tab
switch changes which navigator is on top without any of them reporting.

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

**The top inset.** On compact the screen's `AppBar` reserves it. In the wide
layouts the rail and the panes extend under the status bar, inset only by their
margins. The rail reserves the rest inside its surface; each pane passes it to
the screen, where the `AppBar` reserves it (see the bar-with-two-panes branch
above). A screen without an `AppBar` has to handle `MediaQuery.padding.top`
itself, as it would on a phone.
