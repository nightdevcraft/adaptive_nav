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
| `≥ 600`, `fits` false | rail | one pane, detail overlaying the rail |
| `≥ 600`, `fits` true | rail | two panes |

With the defaults (rail 80 + 1, minimums 320 + 360, no margins, gap or
insets) `fits` turns true from 761 across.

Two states would be simpler and wrong: a wide window with a narrow content area
has room for a rail but not for two unsqueezed panes. The chrome threshold is a
breakpoint; the pane count is `MasterDetailConfig.fits`.

Below the breakpoint, though, a branch is one pane whatever `fits` says. The
two decisions were independent there too, and that made the pane count jump:
with minimums that fit beside a bar but not beside a rail, a narrowing window
went to one pane as it crossed 600 and back to two the moment the bar replaced
the rail and handed its width to the panes. Tying both to the same 600 keeps
the layout moving one way as the window narrows.

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

## A detail over one pane covers the chrome — on Apple, it may not

Over one pane the detail is a screen of its own, and something has to give:
either the chrome stays beside it or the detail takes the window.
`AdaptiveShellConfig.detailChrome` is that choice.

**Covered by default, on every platform.** Material's detail screen is full
screen, over the navigation; back is how you leave it. Until 0.15 the bar did
that and the rail did not — a rail beside one pane kept showing next to an open
detail, so a phone and the Duo's outer display behaved differently for the
same branch. Now both are covered. The mechanism is the bar's: the detail
layer lies over the whole window, chrome included, and is there whether the
detail is open or not, transparent and ignoring taps while it is empty. So
nothing about the chrome animates on the shell's side: the detail's own
transition slides or fades over the rail and off it again, at its own
duration, and the screens are built once per state change, as
`pane_rebuild_test.dart` checks.

On iPhone Duo the column is the system's, not just the rail's. Covered, the
rail's destinations and their menu go; the status area is the system's to
keep, and the detail's toolbar is the screen's, so it stays — drawn over the
detail as a column of its own, the way a column without the rail always was,
from the status area down, with all of the column's length. The column's
background stays as well, and the detail stands beside it, in the area the
single pane had: the rail's column, `railColumnWidth` (the larger of the
rail and the inset), is left out on that side, the detail's padding there is
removed as a pane's is, and it is clipped there, so a swipe back takes it
under the column's edge rather than across it. It used to lie under the
column with the window's inset as its padding, and a screen that does not
read the padding — a `Scaffold`'s body does not — ran under the column. The
layer is still the same widgets either way, so a turn of the device that
brings the column or takes it away does not move the detail's navigator; in
immersive mode the column's width goes with the rail's, by the same tween.
The left Split View window has no inset: the rail was its column, so a
covering detail takes the whole window and has its toolbar in the header.

**Kept, on Apple platforms only.** iOS keeps a tab bar beside a pushed screen
unless that screen asks to hide it (`hidesBottomBarWhenPushed`), and on the
Duo the HIG column is status bar, Back, actions, tab bar — the order the shell
already draws with the rail in the column. `DetailChrome.kept` is that: over a
bar, the detail goes into the `Scaffold`'s body above the bar, which has
already taken the bar's inset off it; beside a rail, the detail stays in the
pane. It is honoured only where `Theme.of(context).platform` is iOS or macOS:
on Android a bar beside a detail is not a pattern, and a value ignored there
lets one config serve both. The theme rather than `defaultTargetPlatform`, so
the playground's iPhone in a browser behaves as the iPhone. No assertion: an
app sets it once for its iOS build and the same code runs everywhere.

Two panes are untouched by either: the detail has its own pane.

### A back swipe from the column

Beside the column, the detail's edge is a column's width in from the
window's. The iOS swipe the route listens for starts at the route's own edge
— `max(inset, 20)` from it, and the detail has no inset on that side — so
with the column at the leading edge (outer display, turned left; in a
right-to-left app, the column on the right) a finger starting at the glass,
as a back swipe does, landed in the column and nothing moved. Before 0.15 it
worked only because the detail lay under the column.

The shell puts the strip back where the finger starts: `ColumnBackGesture`,
above everything in the window at the leading edge, from the glass to the
edge of the pane the route is in — at least the width Cupertino's detector
would have there (`max(inset, 20)`), and on past the rail's divider and the
gap beside it, so no finger between the column and the screen is lost (in
pose 2 the inset is 84 and the screen starts at 89) — translucent, so what
is under it still gets the pointer. The pane's edge is read from its
navigator as the finger lands, not computed from the rail's layout. A finger becomes a swipe only past the horizontal
slop, through a `HorizontalDragGestureRecognizer` in the same arena as the
buttons under it: a tap on Back, Save, the menu, a tab or More stays theirs, and a finger
that starts on one and goes sideways is a swipe — the same as on a button at
the screen's own edge. It is there only where it is needed: iOS, a
single pane beside the system's column — a covering detail beside the bare
column, or any screen beside the rail in it, a kept detail, a screen over
one, a screen pushed in a plain tab — the column at the leading edge, and
something in that pane to go back to: at a tab's root there is no strip,
the column is only buttons there. Two panes are left as they were. The route
it drives is the top route of the pane against the column, the one whose
toolbar the column shows — the active branch's detail navigator over a
master-detail branch with a detail open, its master navigator otherwise —
read when the finger lands and taken only if
its `popGestureEnabled` says so then — an exit guard, a `PopScope` that
blocks, a route still arriving, another gesture under way all say no, as
they do for the route's own swipe, and an inactive branch is never asked.
A navigator does not name its top route, so the column's observers, which
already see every route come and go, keep the stack (`ColumnTransitions
.topOf`).

**Driven through the route's predictive back interface.** Every
`TransitionRoute` is a `PredictiveBackRoute`, public:
`handleStartBackGesture` and `handleUpdateBackGestureProgress` move the
route's own animation and start the navigator's user gesture,
`handleCancelBackGesture` runs it back and ends the gesture when it is
there. So the screen moves with whatever transition the theme gives it —
Cupertino's on iOS, linear while the gesture lasts — and the column follows
`didStartUserGesture` exactly as for the route's own swipe. The decision on
release is Cupertino's: at a speed of a screen width a second or more the
direction decides, otherwise the half way; the width is the route's, so the
finger and the screen move together. The commit is not
`handleCommitBackGesture`: that one pops and then restarts the reverse
animation from the top, which Android's predictive back transition expects
for its own commit, and a Cupertino page jumped back open before it slid
out. The swipe pops the route itself, as Cupertino's controller does, and
ends the user gesture when the pop's animation stops, so the transition
stays straight to the end. What is left from Cupertino is the timing of the
release: its controller animates the rest over 350 ms with its own curve,
this one at the route's own durations.

**Rejected.** Copying `_CupertinoBackGestureDetector` and its controller:
private, and a copy would drift from the framework. Forwarding the pointer
into the detail at its edge, so the route's own detector takes it: the hit
test would reach whatever is under that point of the detail as well — a list
tile at its edge would be pressed by a tap on Back. Laying the detail under
the column again: that is what the detail was moved out of, above, for the
screens that ran under it. Widening the detail's own drag area: the strip is built by
the route's transition, out of the shell's reach.

## The chrome follows the system's own bars

`AdaptiveShellConfig.chromeLayout` returns where the chrome goes — bottom, left
or right — instead of the "rail or bar" boolean it used to be.

The third answer exists because of iPhone Duo. The device puts the status bar
and the Dynamic Island in a vertical strip along one edge and asks apps to put
their bars on the same edge, so that controls stay where the hand is as the
device folds and turns. The strip moves: right on the outer display in
portrait, left when that display turns, right on the inner display in
landscape — "bar position stays consistent with the outer display". On the
inner display in portrait it goes back to the top, and Apple asks for ordinary
horizontal bars there.

The system's own answer is `UITraitCollection.verticalBarEdge`, and it is the
first thing the layout asks. The package knows nothing about UIKit: a
`SystemGeometry` arrives through a `SystemGeometryScope`, and adaptive_nav_ios
is what fills it in on iPhone Duo. The core takes it as input and nothing more,
so the same rule runs in tests, in the browser playground and on Android, where
nobody provides one.

The trait turned out to mean something other than "where the status bar is".
Under Split View both windows get the outer edge of the display — the left
window `leading`, the right one `trailing` — though the status bar is only in
the right one; Safari in the left window puts its own bar on the left. It is
the edge the window's own bar belongs on, which is exactly the question the
layout asks, and it is the one posture `MediaQuery` cannot answer: the left
window has no side inset at all.

Everywhere else the padding says the same thing, and without a provider the
layout reads it there. The discriminator is **asymmetry**:

| | left | top | right |
| --- | --- | --- | --- |
| iPhone 18 Pro, portrait | 0 | 62 | 0 |
| iPhone 18 Pro, landscape | 62 | 0 | 62 |
| iPad | 0 | 24 | 0 |
| Duo outer, portrait | 0 | 0 | **84** |
| Duo outer, landscape | **84** | 0 | 0 |
| Duo inner, portrait | 0 | 82 | 0 |
| Duo inner, landscape | 0 | 0 | **84** |
| Duo Split View, left | 0 | 0 | 0 |
| Duo Split View, right | 0 | 0 | **84** |

A notched iPhone in landscape reserves both sides, and a display cutout
reserves one but is half as wide; a bar standing on its end is the only thing
that is wide *and* one-sided, and where it is, the chrome joins it at any
width. The inner display in portrait is then separated from a tablet of the
same proportions by the depth of its top inset — 82 against 24 — which is the
system saying "this is a phone". The left half of Split View falls through to
the width and gets a bottom bar: the fallback's one wrong answer, pinned by a
test and named in the README.

The reported side wins at any width, with one exception the measurements do not
cover: a right-to-left layout. adaptive_nav_ios turns `leading` and `trailing`
into a side through the window's layout direction, and if that is ever wrong,
the rail would land across the window from the system's column. So where the
padding shows a bar inset on the other side, the inset wins. It is the cheaper
mistake to make: the column is certainly where the inset is.

Both thresholds are empirical, and both are named constants with the
measurements in their doc comments. `chrome_layout_test.dart` asserts that
every non-Duo pose still decides exactly as the old width breakpoint did, with
no geometry and with one that has no opinion; that test is the contract.

### The rail joins the system's column; it does not take a second one

On the outer display the camera sits at the end of the vertical strip and the
status bar runs along it, and Apple's point is that the controls line up with
the camera. So the rail goes *into* that column: `PaneMetrics.railColumnWidth`
is the wider of the rail's own region and the system's inset, never their sum,
and a reserve keeps the status end of it free so the destinations start below
the clock rather than under it.

The reserve is the status area: the active occlusion `UIView.reservedRegions`
reports against the window's edge on the bar's side. It reaches 170 points down
on the outer display upright, 82 in landscape — at the bottom of the column
when the phone is turned with the column on the right — and 120 on the inner
display, in either landscape orientation and in the right half of Split View.
The camera is an occlusion too, but it stands clear of the edge, and the inner
display's under-display camera is reported inactive; neither is the status
area. With a provider the reserve is taken from the area as reported; without
one `SystemBarMetrics` holds the same numbers and picks between them by the
**display**, not the window, since a Split View window is narrower than the
outer display. Where the reported area is at the bottom, the reserve goes there
too, so `SystemBarMetrics.end` is only the fallback's guess.

The other number is the line the rail is centred on, and no API reports it. It
is not the middle of the column: the camera is centred 48 points in from the
window edge, in an 84-point column, so a rail simply centred in the column
would still miss it by six points, and a rail flush against the edge misses it
by eight. `SystemBarMetrics.axisFromEdge` holds it.

In the column the destinations gather at the bottom, unless the app set
`railAlignment`. Apple stacks a column the way it stacks a screen — status bar,
then toolbar, then tab bar — and the bottom is where the thumb of the hand
holding the phone is. That is why `railAlignment` is nullable: "not set" has to
be told apart from "set to the top", which an app may want everywhere.

Sharing rather than stacking also keeps the pane area honest. The column costs
89 points — the system's 84, widened by the rail being held off the edge onto
the camera's axis — and leaves 377 on the outer display in portrait, 589 in
landscape and 862 on the inner display. Minimums that split the inner
display's 669 in portrait can still clear 589, so it is not the minimums that
keep the outer display a single pane, as Apple asks: without its side bar it is
under 600 across, and below that a window is always one screen
(`kCompactWidthBreakpoint`).

The inner display in landscape used to be the exception: wide enough for the
rail to lead as it does everywhere else, with the detail bleeding under the
system bar on the far edge. Apple's guidance says otherwise, and keeping the
bar on one side as the device unfolds is what makes the unfold calm. So the
rail joins the column there too, the master starts at the left edge and the
detail ends against the column. A rail that does *not* share a column is now
the left half of Split View, which the system puts against the display's outer
edge with nothing at the top of the window; that one keeps `cornerClearance`
free rather than start in the rounded corner.

### The status row on the inner display

Experimental, off by default and iOS only, since the geometry was measured on
the iOS simulator (Xcode 27.1).

In portrait the 82-point top inset spans the width, but the glyphs are a row
in the top right corner: the status area is 535…669 across, 134 points, and
the glyphs are centred 48 down. `liftHeadersIntoStatusRow` hands each pane a
top inset of 20, which centres a 56-point toolbar on that line, and tells the
pane under the glyphs their width — the reported area's, or
`SystemBarMetrics.statusRowTrailing` without a provider. It cannot keep an
`AppBar`'s actions clear of them itself, which is why the screen gets
`StatusRowScope` rather than a finished layout. Android puts its clock at the
left end of the row, so the option does nothing there.

The line is measured, not derived. On a screenshot of the flat inner display
the clock's digits and the Wi-Fi glyph are both centred 48.0 points down, and a
header lifted onto 48 has its icons at 48.0–48.2 and its capitals at 48.2–48.3.
The middle of the 82-point status area would be 41: the area is what the system
keeps for itself, glyphs and the room around them, and the glyphs sit below its
middle.

## The system's column: two zones, toolbar and tabs

Apple's vertical column has an order, top to bottom: the status area, the
navigation button, the prominent action, the other groups after a gap — and,
apart from all of them, the tab bar at the bottom. They are two zones, not one
stack: the toolbar's at the top and the tabs' at the bottom, each with its own
overflow ("Vertical controls", Tech Talk 111462). The first version here
stacked them as one — Material's rail under the toolbar, one "…" menu for both
— and on the outer display in landscape that column jumped as you used it:
the selected tab's label made it taller, which changed how many tabs fit, so
the "…" came and went and the whole column moved by a slot; the menu was
shared with the toolbar, so changing screens (a filter on one tab, Empty on
another) moved it too; and selecting a tab near the end pushed that very tab
into the menu.

**The tabs' places depend on the column alone.** The tabs' zone is anchored
to the column's bottom and its number of places is worked out from the
column's height and `railLabelsInColumn`, nothing else — not the selection,
not the screen (`columnTabPlaces`). A screen change touches only the toolbar's
zone and changes it with the screen's transition; the tabs do not move by a
pixel, which `system_column_test.dart` checks frame by frame through every tab
and a detail opened and closed, for 2, 3, 5, 7 and 10 tabs, in every posture
with a column and with every label type. Only a new window size changes the
places, laid out from the zone's bottom edge, and at once: no route
transition carries it.

**The tabs do not give way to a toolbar that is not there; short of room,
they fold, as Apple's do.** The zone used to keep a fixed minimum for the
toolbar, two buttons (the navigation button and its menu) and the gap, so
that the count need not know whether the current screen had a toolbar at all.
On the outer display turned that was 120 of a 336-point column: a root with
no buttons showed two tabs and More under an empty top. Apple's tab bar
(`prefersTabBar`, the default) does not do that, so the zone now takes every
place the column holds, less only the 12 between the zones. The toolbar of
the current screen gets what is left; its items go into "•••", bottom up by
`visibilityPriority`. When what is left does not hold even the navigation
button and "•••" — or "•••" alone, with no navigation button — the tabs fold,
Apple's `prefersToolbarItems` (Tech Talk 111462), and the toolbar gets the
rest of the column. Apple names that mode,
not when the system switches to it on its own; that the system's tab bar
folds in this short column is a third-party measurement on the iOS 27.1
simulator (https://github.com/sdegenaar/liquid_glass_widgets/issues/348).
When a screen that fits comes back, they unfold to the same places. That one
change goes with the transition of the screen that brings it, and no screen
is built for it; it is the only time the tabs change between screens.

**Folded, the tabs are two buttons, not one.** The first fold was one button
with the current tab's icon and a menu of every tab. It hid that the button
was a tab: tapping it again opened a menu instead of doing what the selected
tab does, and the More that people had learnt at the bottom place turned
into something else. Now the bottom place stays More, with its icon and in
its place, its menu holding every tab, and above it stands the selected tab,
an ordinary tab of the zone, filled and doing on a tap what it does unfolded.
The two take two places, so the toolbar gets the column less those and the
gap (`column_capacity_test.dart`); for one button that is always enough. Only
where two places leave too little for the least of the toolbar — the
navigation button and "•••", or "•••" alone — More stays alone and filled, as
it is when the selected tab is behind it. Two places where the full zone has
only two would give the toolbar nothing, so there `tabsFirst` folds straight
to More alone. The animation keeps More still: the other tabs fade where they
stand, the selected one moves down to its place above More, and unfolding is
the same backwards. Every place is one widget for both forms, so nothing is
laid out twice and no place that stays in view jumps.

**More, not an ellipsis.** More tabs than places give the last place to More,
which is what `UITabBarController` does on an iPhone; Apple does not describe
the case for a vertical tab bar at all. The selected tab never leaves its
place, and selecting a hidden one does not reshuffle the visible ones — it
lights More up. The ellipsis is the toolbar's menu, so More has a grid.

**Labels reserve their room.** With `NavigationRailLabelType.selected` only
the current tab shows its label, but every tab keeps the room for one; with
`none`, the default and Apple's, there is no label to reserve. A tab whose
height changed with the selection is exactly what moved the column before.

**The sizes are measured.** Safari and Settings on the simulator (iPhone Duo,
iOS 27.1, outer display upright, @3x): buttons are circles of 48, centred on
the glyphs' axis 48 in from the edge; Back and Reader, separate circles, are
60 apart, centre to centre — 12 between; New Tab and Tabs share a capsule 102
tall, glyphs 54 apart — 6 between two of one group. Back starts 24 below the
170-point status area, and the Settings search button ends 24 above the
window's bottom edge, inside the 34-point home indicator inset. Those are
`kPaneToolbarItemExtent`, `kPaneToolbarGroupGap`, `kPaneToolbarItemGap` and
`SystemBarMetrics.columnInset`. A tab is a 48 circle like a button, and the
tabs are one group, 6 apart, as Apple draws the tab bar in one capsule: there
is no system app with a tab bar on this simulator to measure, and Safari's
capsule is the nearest thing.

**Which pane.** The column belongs to the pane against it, and the shell
decides which that is before it builds the screens, from the same arithmetic
the layouts use: the single pane — outer display, either Split View window, a
plain tab across the inner display — or the detail of two while the column is
on the detail's side and the detail is open. A master keeps its header even
when it spans the window with the detail collapsed: it is the list of a
master-detail pair, and Apple keeps that header horizontal. Inside that pane,
only the screen on top of its navigator (`ModalRoute.isCurrent`) is drawn;
the screens below it are covered anyway. Each pane's navigator gets a
`PaneBarScope`, so a screen knows whether its header is empty, and a
`PaneToolbarHost`, where its `PaneToolbar` registers.

**Who draws it.** The shell, not the screen. On the outer display the column is
not part of the pane — the rail's region has it — so a toolbar drawn in the
screen's body, as the old `StatusColumnActions` did, cannot get there. Screens
register their items in a registry the delegate owns; the column listens to it
and rebuilds on its own. Registration happens while the screens build, when
nothing may be notified, so the news goes out after the frame — one frame late
for a screen that has just appeared, which the first half of its transition
covers. A screen is not built again for any of it: the header changes once,
when the side does, and the fade runs in the column and in the header's
buttons.

**A screen without a toolbar still gets Back.** `UINavigationController`
puts Back in the vertical bar itself; a screen should not need a
`PaneToolbar` for the column to have its navigation button. Every page the
shell builds wraps its screen in an `AutomaticPaneBack`, which registers the
button a `PaneToolbar` would pick under the pane, in a second map of the
registry: a `PaneToolbar` of the same screen wins the slot, and the column
cannot tell the two apart otherwise — the same transitions, the same swipe
back (`ofRoute`), the same pop through the pop scopes and so through the
guards.

The `AppBar`'s own arrow is the other half. `AppBar` asks the route, through
`ModalRoute.of`, whether it `impliesAppBarDismissal`; the getter is the
framework's switch for exactly this and can be overridden. So the pages are
subclasses of `MaterialPage` building subclasses of `MaterialPageRoute`, and
those of `fade` and `none` subclasses of `PageRouteBuilder`, with one mixin
on top: while the `PaneBarScope` above its navigator is vertical and the
option is on, the route says no. Subclasses rather than routes of our own, so
nothing else changes for the app: `ModalRoute.of(context) is
MaterialPageRoute` holds where it did, the theme's `pageTransitionsTheme`
builds the transition, `fullscreenDialog` and heroes work as with the
framework's. The framework's `MaterialPage` cannot be used as it is: the route
it creates is private and takes no mixin, so the subclass overrides
`createRoute` and its route takes its content from the page, as the private
one does. Nothing has to tell the header that
the bar changed sides: the shell rebuilds the pane's navigator with the new
`PaneBarScope`, the navigator has every route rebuild its scope
(`changedExternalState`), the scope reads the getter again and the `AppBar`
depending on it rebuilds — in the same frame, before the column has even
heard. `PaneToolbar` and `AutomaticPaneBack` read the framework's answer
before the override (`routeImpliesDismissal`), or a screen with a toolbar
would lose its Back to its own route.

**An app's own decision wins.** An `AppBar` with a `leading` ignores the
route's answer altogether, so the header is untouched; a Back in the column
next to it would be a second one, so the column gets nothing. Nor does it for
`automaticallyImplyLeading: false`: the app has said there is no button. Which
of the two a screen is cannot be known before it is built, and an element tree
cannot be walked while it builds, so `AutomaticPaneBack` registers after the
frame, having looked breadth first for the screen's first `AppBar`,
`SliverAppBar` or `PaneToolbar` — not into a nested navigator. That is the
frame the column hears of a `PaneToolbar` in anyway. It looks again whenever
the screen comes to the top; a `leading` that appears later is not noticed.
Routes pushed on a pane's navigator past the router are not the package's and
keep their arrow.

**The column goes with the route's transition.** `UINavigationBar` ties its
items to the push: the old buttons go as the new screen comes in, and a
swipe back holds them where the finger is. The column first changed on a
clock of its own, `kDefaultImmersiveDuration` from the frame the state
changed: on the outer display turned, Close and Edit stood at full strength
over the tabs for the first 150 ms of a detail sliding in, and on the way
back vanished in one frame, the tabs reappearing in the next while the
screen was still leaving; a swipe back did not move the column at all. Now
every change of the column takes the progress of the route transition behind
it (`ColumnTransitions`): each branch navigator reports its pushes, pops and
gestures through an observer of its own, and a change of the column — the
tabs going under a covering detail and coming back, the toolbar's zone from
one screen to the next, the tabs folding and unfolding — follows that
route's `animation`, forward for a push, backwards for a pop.

It is a cross-fade in two halves, never one over the other: what goes is gone
by the transition's middle, what comes starts there. The opacities are linear
in the route's progress — the controller's value, before the transition's
own curve — so the middle of the column is the middle of the transition, and
during a gesture it is where the finger is. A place that moves while the
tabs fold eases (`Curves.easeInOut`) over the whole of it, as it did on its
own clock, and lands on a place the other tabs have already left. The
platform's curve would put the halves elsewhere on every platform —
Cupertino's push is fast at the start, Android's predictive back has none —
while the route's progress is the one thing they all share.

A back gesture, iOS's swipe or Android's predictive back, starts with the
route still on top and the state unchanged, so the shell works out what the
column will show once that screen is gone — the detail closed, or the screen
below on top — and leads the column there by the finger
(`NavigatorObserver.didStartUserGesture`); the toolbar of the screen below is
kept in the registry under its route for this. Let go short of the point of
no return, the column is back where it started, frame for frame with the
screen; past it, the route pops and the column carries on from where the
finger left it — predictive back runs the pop's animation again from the top,
which the column does not follow back. Every route whose predictive back is
enabled takes the gesture, an open detail in a tab out of view as well, so
the observers keep one gesture per navigator and the column follows the one
on the active pane's top screen. What `WidgetsApp` tells the system about
back is still the delegate's one answer; the column only listens.

Some of a change is known before the navigators build — the state — and some
only after: the route and its animation, and the toolbars, which register as
the screens build. The column cannot wait for the navigators with a
`LayoutBuilder` (see above), so a change takes a drive that settles on its
transition when the column is painted, by which time every navigator has
reported: this frame's transition, or one still running, which a toolbar
registered a frame late joins from where that transition started. With
neither — `AppTransition.none`, a link without animation, a new window size
or a turn of the device — the column changes at once. A tab switch has no
route transition and keeps its own: the toolbar's zone cross-fades and the
tabs fold over `PaneToolbar.duration`, as before, alongside the branch fade.
The opacities and positions are worked out in paint (`DrivenBox`), so nothing
is built frame by frame: not the screens, and not the column either.

**Why a count.** The toolbar's items and the tabs are declared heights, so
how many places the tabs get and what the toolbar keeps is arithmetic over the
column the rail card already works out. A `LayoutBuilder` around the column
would be one around tooltips, which is the combination this file warns about.

`toolbarFirst` (Apple's `prefersTabBar`) lets toolbar items go, lowest
priority first and from the bottom up among equals, into the toolbar's own
menu; the tabs give way to it only when not even the navigation button and the
menu fit, and then by folding, not by losing places. `tabsFirst`
(`prefersToolbarItems`) folds the tabs to the selected one and More as soon
as the toolbar does not fit beside them whole. The navigation
button never goes: Apple does not fold Back away.

**Without the rail in the column.** Where a custom `chromeLayout` keeps the
rail across the window, the column is still the system's inset, the panes bleed
under it, and the toolbar is drawn over them, 72 wide on the column's axis,
from the status area down. It lies above the shell's `Scaffold`, so a drawer
from the other edge would pass under it; on the Duo a drawer is narrower than
the window by far more than the column. With the default layout this does not
occur: the rail is in the column in every posture that has one, including the
left Split View window, where the screenshots of the previous round showed
Safari's toolbar at the outer edge, Back at the top — which is where ours goes
too. Where the status area is at the bottom of the column (outer display,
turned right), the toolbar still starts at the top and the rail stays at the
bottom, by the camera: the thumb's end belongs to the destinations.

**Nothing of the system's at the top.** There the column used to start at
the glass's edge, Close in the rounded corner, then `cornerClearance` (16)
down. It now keeps `columnInset` (24) at both ends whatever is there, the
number Safari keeps under the status area; with the status area at the bottom
(outer display, turned right) the toolbar starts 24 from the top and the tabs
end 24 above the status area.

**The prominent action is tinted.** It was a filled tonal circle, the same as
the rail's selected destination a few points below it, and Edit read as a
section of the app. Apple tints a prominent item rather than filling it; the
pinned items take the scheme's primary colour and no fill, in the column and
in the header alike.

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

`AdaptiveNav.immersive` (or `AdaptiveShellConfig.immersive` with a hand-built
`Router`) slides the rail out and gives the strip to the panes. It changes
geometry and nothing else:

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
boundary on the hinge, and the crease's width is an inset either side of it.

This is the one case where the split's position is not a preference. A ratio,
or a width the user dragged, is a choice about how to divide a flat plane;
half open there is no flat plane, and a pane laid across the crease is bent
over two of them. So the fold wins while it is reported active, the divider
stops being draggable — the hinge decided, and a handle would be a lie — and
the app's width comes back when the device goes flat. The boundary moves once
and once back rather than settling somewhere new, which is what the guidance
to keep folding calm asks for.

The panes meet on the line of the hinge — the middle of the crease's bounds,
or the line itself when the crease has no width — and the crease is not a gap
between them. It used to be: the master ended at 455.5 on iPhone Duo, the detail
started at 495.5, and the 40 between showed the master's colour, so the visible
seam stood 20 points past the hinge, on a plane the master was not on. A crease
is to a pane what the system bar is ([A pane bleeds under an
inset](#a-pane-bleeds-under-an-inset-it-does-not-own-the-width)): the background
goes to the edge, the content stays out. So each pane reaches the hinge and
gets half the crease, 20 on Duo, as padding on that side, by the same
`_paneInsets` path as an underlap; its screens see it in `MediaQuery.padding`
and keep their content off the bend, and the seam is where the device folds.

`PaneDecoration.gap` does not move the boundary either, nor widen what the
content keeps clear: with cards, the gap is split evenly around the hinge, and
whatever is left of the crease past it is each pane's inset — so the content
still stops where the crease starts, and the space between the cards is
symmetric about the hinge. Only a gap wider than the crease leaves no inset at
all.

It wins only where both panes still clear their minimums around it, and the
minimums are checked against what the user sees — each pane's width less its
half of the crease, as with an underlap. A crease near one edge would squeeze
one pane below the width it declared, and the package would rather ignore the
hinge than break its own promise.

A fold counts only if it is **active**, **vertical** and **inside the pane
area**. A flat posture reports the fold too, and a crease on a continuous
display occludes nothing; a horizontal fold — the inner display in portrait,
half open — says nothing about a vertical boundary; and a fold behind the rail
is not a boundary either pane could sit against.

There are three places to find one, asked in order. `MediaQuery.displayFeatures`
comes first: the framework fills it on Android, and when it maps Apple's
`reservedRegions` onto it too (flutter/flutter#193025), it will be first on iOS
as well with nothing to change here. Then `SystemGeometry.folds`, which
adaptive_nav_ios fills on iPhone Duo in the meantime. UIKit reports the fold as
a division 40 points across — a line with 20 of margin either side — in every
posture, flat or not, and only the active flag changes, so the provider passes
on the active ones: the panes meet on its middle and keep 20 clear on each
side. On Android a hinge has the width of the gap between the screens and a
fold on a continuous display is a line; the same rule gives the first an inset
and the second none. Last comes the app's
own `foldLocator`, for a device nothing reports.

`FoldMetrics.windowCentre` was the recipe for iPhone Duo before there was a
provider, and it is deprecated: it puts the boundary down the middle whatever
the posture, so a flat device got a split it did not need. Device Hub in
Xcode 27.1 has a half-open posture, at a fixed angle of about 128°, so the real
fold can be tried on the simulator; `fold_split_test.dart` and
`duo_poses_test.dart` inject it directly.

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

Which destinations give way is `BranchConfig.visibilityPriority`'s. The count
takes them out lowest first, the last of equals first, until the rest fit; the
rest keep their order. With no priorities that is the longest run from the top
that fits, which is what the count used to be.

None of this applies in iPhone Duo's system column, whose tabs have places
of their own (above); the count there is simpler, a place every 48 points and
12 between, and does not depend on which tab is selected.

With `RailAlignment.bottom` the button is the rail's `leading` instead of its
`trailing` — `trailing` sits inside the group `groupAlignment` moves, so it
would go to the bottom with the destinations. `NavigationRail` puts a spacer
after a `leading` as well as before it, so the count takes 8 more for the
button there; `rail_alignment_test.dart` sweeps the same heights with the
destinations at the bottom to keep that term honest.

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

## The active tab tapped again goes to its root

Until 0.15.0 a tap on the selected destination did nothing, which is what the
code had to say about a tab already open, not what users expect from one.
iOS has gone back to the root on a second tap since `UITabBarController`, and
Material's navigation bar guidance says the same; people from both reach for
it to get out of a deep stack. So it is the default, and `BranchReselect.none`
is the way back for an app that has a reason.

It is the existing `popToRoot`, not a new kind of exit: the gate is the one
every way out goes through, and what the root is in master-detail — the
master, so the detail goes — does not change because of how the pop was
asked for. It lives where a destination is chosen, the shell's one
`onSelectBranch`, rather than in each widget, so a `barBuilder` or a
`railBuilder` gets it for free, and `goBranch(active)` from code stays a
no-op: code that selects the tab it is on did not ask for its stack to go.
`onReselect` is called whether or not anything was popped, because the second
step on iOS, scrolling to the top at the root, belongs to the screen.

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
`backToBranch`. It is recounted after every state change too, because a
detail opened or closed changes which navigator is on top before that one has
said anything.

That answers *whether* the app takes back, not *who* does. A back button is a
call to `popRoute`, and the delegate picks the navigator. A back gesture is
not: Android's predictive back goes through `WidgetsBinding` to every observer
that wants it, and each `PageRoute` built with the predictive transition has
one, `_PredictiveBackGestureDetector`, which wants it when its route
`isCurrent` and `popGestureEnabled`. Both are per navigator. Inactive branches
stay mounted under an `IndexedStack`, so their current routes said yes too, and
one gesture closed the top screen of every branch that had one, a detail out of
view among them.

The framework's switch for that is the route's pop disposition:
`popGestureEnabled` is false while any `PopEntry` of the route cannot pop — a
screen's `PopScope(canPop: false)` turns its gesture off this way, and the
iOS edge swipe reads the same getter. Every screen of the shell already sits in
the entry's own `PopScope` (the guard's), so that scope also says `canPop:
false` while the branch is inactive, read from a `BranchActiveScope` the shell
puts above each branch navigator. Nothing intercepts the gesture: the inactive
routes simply decline it, and only the active branch's routes are asked. The
alternatives were worse. Swallowing the binding's back callbacks before the
routes see them means reimplementing the dispatch; unmounting inactive
branches loses their state; a route subclass of our own does not cover the
`MaterialPage`s of the other transitions.

The block shows up in the reports: a navigator of an inactive branch says it
handles back (a route that cannot pop "handles" it — the same report a
blocking `PopScope` gives). The delegate reads only the root and the active
branch's top navigator, so that value is never used; the tab switch that makes
the branch active lifts the block, and the navigator reports again at the end
of that frame, after the delegate's own recount, so the last report wins and is
right. A screen's own blocking `PopScope` still reports the same way, and is
still read, because its branch is active.

A gesture belongs to the routes that took it at the start. A tab switch in the
middle does not move it: the hidden branch's screen still follows the finger
and is popped or restored when the finger lets go, while the branch now in view
takes no part. The next gesture goes to the new active branch. One more effect
of the block: `Navigator.maybePop` from a screen of an inactive branch is now
refused (`pop` is not); the shell never does that, and system back never
reaches an inactive branch.

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

**A symmetric side inset is not subtracted from the content area.** A
landscape iPhone reports the Dynamic Island on both sides at once, so the rail
sits against the edge and covers that inset rather than growing by it: the
content gets exactly `window − rail − divider`, the inset is removed for the
panes' subtree, and the pane on the far side bleeds under its own copy
(`PaneUnderlap`). A one-sided inset on the rail's edge that is not the system's
vertical bar — Android's navigation buttons, a camera cutout in landscape — is
different: `PaneMetrics.railCutoutInset` returns it, and the rail column grows
by it, with the rail's background painted underneath and the destinations
clear of it.

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
