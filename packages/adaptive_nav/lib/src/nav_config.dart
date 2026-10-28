// material, not widgets: the config refers to `ScaffoldState`.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fold.dart';
import 'nav_state.dart';
import 'pane_split.dart';
import 'pane_toolbar.dart';
import 'status_row.dart';
import 'system_geometry.dart';

/// Transition template for a screen.
///
/// [adaptive] is for the detail of a master-detail branch: it fades in a pane
/// and slides when it takes the whole screen, and it decides that while the
/// animation runs rather than at push time. Baking the choice into the entry
/// would make the dismissal play the wrong transition after a resize; swapping
/// it on resize changes the `Page` type and remounts the screen.
enum AppTransition { platform, fade, modal, none, adaptive }

/// Asked before leaving a screen. `false` blocks the exit.
typedef NavExitGuard = Future<bool> Function();

/// Where the shell puts its navigation chrome.
///
/// [bottom] is a horizontal `NavigationBar`; [left] and [right] are a vertical
/// `NavigationRail` against that edge of the window.
///
/// The sides are physical, not leading and trailing. iPhone Duo aligns its
/// vertical bar with the hardware — the camera is at one end of it — so it
/// stays on the same side in right-to-left languages, and a shell that mapped
/// the side through `Directionality` would disagree with the system bar it is
/// supposed to sit next to.
enum ChromePlacement {
  bottom,
  left,
  right;

  bool get isRail => this != ChromePlacement.bottom;
}

/// Given the window, its safe-area padding and what the platform reported
/// about its own chrome, decides where the chrome goes. Pane count is decided
/// separately, by [MasterDetailConfig.fits].
///
/// [system] is the nearest [SystemGeometryScope]'s, `null` without one.
typedef ChromeLayout =
    ChromePlacement Function(
      Size window,
      EdgeInsets padding,
      SystemGeometry? system,
    );

/// A one-sided horizontal inset at least this wide is a system bar standing on
/// its end, not a cutout.
///
/// Measured: iPhone Duo reserves 84 for its vertical status bar
/// (`safeAreaInsets`, simulator, iOS 27.1, on both displays and under Split
/// View). A notched iPhone in landscape reserves 62 — but on *both* sides,
/// which [defaultChromeLayout] does not count; this threshold only keeps a
/// one-sided display cutout, some 30 to 50 logical pixels on Android, from
/// reading as a bar.
const double kVerticalBarInset = 60;

/// A top inset at least this deep belongs to a phone-shaped display.
///
/// Measured: iPhone 18 Pro reports 62 in portrait and iPhone Duo's inner
/// display 82, against 24 on an iPad and 0 on a desktop. It is the one signal
/// that separates the Duo's inner display in portrait — 669 points wide, which
/// the width rule alone would hand a rail — from a tablet of the same
/// proportions.
const double kPhoneStatusBarInset = 50;

/// The compact/medium boundary of the Material 3 window size classes, measured
/// without the side insets.
///
/// Wider gets a rail ([defaultChromeLayout]); narrower is always one pane,
/// whatever [MasterDetailConfig.fits] says.
const double kCompactWidthBreakpoint = 600;

/// Rail from [kCompactWidthBreakpoint], with iPhone Duo's postures taken
/// first.
///
/// The system's own answer comes first: a [SystemGeometry.verticalBar] is
/// where the chrome goes, at any width. That is the only source that gets
/// iPhone Duo's Split View right — the window on the left has no inset on
/// either side, yet the system wants its bar against the left edge, the outer
/// edge of the display.
///
/// One exception, for right-to-left layouts, which have not been measured:
/// where the padding shows a one-sided inset of [kVerticalBarInset] on the
/// *other* side, the inset wins. The system's bar stands in that column, and
/// a reported side that disagrees with it is more likely a leading/trailing
/// edge mapped the wrong way than a request to put the rail across the
/// window from it.
///
/// Without a [SystemGeometry], three rules, in order:
///
/// 1. A substantial inset on exactly one side is the system's own vertical
///    bar, and the chrome joins it at any width. On the outer display the bar
///    and the camera share one column and the rail belongs in it; on the inner
///    display in landscape Apple asks for the bar to stay where it is on the
///    outer one — "inner display, landscape — bar position stays consistent
///    with the outer display" (Tech Talk 111462) — and the system's column is
///    on that side.
/// 2. A phone-shaped status bar means horizontal bars, which is what the Duo's
///    inner display in portrait asks for.
/// 3. Otherwise the width breakpoint, as before.
///
/// Rule 1 is fenced off to a display that really does carry a side bar: it
/// wants a one-sided inset of [kVerticalBarInset]. iOS reports the landscape
/// insets symmetrically and a display cutout is narrower than the threshold,
/// so nothing else reaches it.
///
/// Rule 2 is not fenced that way. It reads the top inset alone, so any window
/// at least [kPhoneStatusBarInset] deep at the top gets horizontal bars,
/// however wide it is and whatever device it belongs to. Nothing measured
/// reports that on a window wide enough for a rail — an iPad sends 24, a
/// desktop 0 — but a device that did would follow the Duo's inner display
/// rather than the width breakpoint.
///
/// `chrome_layout_test.dart` pins all of it: the devices that must not
/// change, what a deep top inset does when it turns up, and what the
/// fallback cannot see.
ChromePlacement defaultChromeLayout(
  Size window,
  EdgeInsets padding, [
  SystemGeometry? system,
]) {
  final bool wide =
      (window.width - padding.horizontal) >= kCompactWidthBreakpoint;
  final bool barLeft =
      padding.left >= kVerticalBarInset && padding.right < kVerticalBarInset;
  final bool barRight =
      padding.right >= kVerticalBarInset && padding.left < kVerticalBarInset;
  switch (system?.verticalBar) {
    case ChromePlacement.left:
      return barRight ? ChromePlacement.right : ChromePlacement.left;
    case ChromePlacement.right:
      return barLeft ? ChromePlacement.left : ChromePlacement.right;
    case ChromePlacement.bottom || null:
      break;
  }
  if (barLeft) {
    return ChromePlacement.left;
  }
  if (barRight) {
    return ChromePlacement.right;
  }
  if (padding.top >= kPhoneStatusBarInset) {
    return ChromePlacement.bottom;
  }
  return wide ? ChromePlacement.left : ChromePlacement.bottom;
}

/// Auth guard: may substitute a state before it is applied. Runs on incoming
/// URLs and on `AdaptiveRouterDelegate.reevaluate`, not on every stack
/// mutation.
typedef RedirectHook<R> = NavState<R> Function(NavState<R> next);

/// Builds custom chrome in place of the Material default.
///
/// [activeBranch] and [onSelectBranch] are in BRANCH indices, not destination
/// positions — the app owns the destinations, so nothing is mapped twice.
/// Returning `null` means no chrome this frame.
typedef ShellChromeBuilder =
    Widget? Function(
      BuildContext context,
      int activeBranch,
      ValueChanged<int> onSelectBranch,
    );

/// Builds the button at the end of the default rail that carries the
/// destinations its column could not hold.
///
/// [hidden] and [onSelectBranch] are in BRANCH indices, like
/// [ShellChromeBuilder]'s. [active] says the current branch is one of the
/// hidden ones: the rail shows nothing selected then, so the button is what
/// carries the selection.
///
/// The widget is centred in a slot [kRailOverflowExtent] tall and laid out
/// into it. That height is one of the terms in the shell's count of how many
/// destinations fit, so it is not the builder's to change — a rail whose
/// overflow button needs more room than that is a [ShellChromeBuilder] rail.
///
/// In iPhone Duo's system column the same builder makes the More button,
/// the last of the tabs' places: [hidden] are the tabs without a place of
/// their own, and the widget is centred in the top [kPaneToolbarItemExtent]
/// of that place, where the other tabs have their circles.
typedef ShellRailOverflowBuilder =
    Widget Function(
      BuildContext context,
      List<int> hidden,
      ValueChanged<int> onSelectBranch,
      bool active,
    );

/// Builds the shell drawer. [rail] tells which layout is up; `null` also
/// disables the edge swipe.
typedef ShellDrawerBuilder = Widget? Function(BuildContext context, bool rail);

/// Whether to show chrome for a given state. A predicate over the state rather
/// than a flag on the branch, so it covers both a tabless branch and a single
/// full-screen screen inside a normal one.
typedef ChromeVisibility<R> = bool Function(NavState<R> state);

/// `NavigationRail.minWidth`.
const double kDefaultRailWidth = 80;

const double kDefaultRailDividerWidth = 1;

/// Everything a `NavigationRail` destination is, apart from its label: icon,
/// indicator and the padding around them.
///
/// The label is the part that varies — "Home" is one line in an 80-point rail
/// and "People" is two — so the shell lays the text out with a `TextPainter`
/// and adds it to this. Measured: a one-line destination is 64 and a two-line
/// one is 80, against a 16-point line.
///
/// Computed rather than measured *from the tree*, for the same reason
/// [kDefaultRailWidth] is declared: the shell decides how many destinations
/// fit at build time, and a `LayoutBuilder` around the rail is exactly where
/// `OverlayPortal` tooltips once brought the framework down — see
/// `doc/design.md`. `rail_overflow_test.dart` pins both numbers.
const double kRailDestinationBase = 48;

/// Width the label gets inside the rail: [kDefaultRailWidth] less its padding.
const double kRailLabelInset = 16;

/// A `NavigationRail` destination without its label: what each one takes
/// where the rail shows no labels, or only the selected one's
/// ([AdaptiveShellConfig.railLabelsInColumn]). Measured like
/// [kRailDestinationBase]: icons 44 apart, where a one-line label makes it 64.
const double kRailDestinationIconExtent = 44;

/// Height the overflow button takes at the end of the rail.
const double kRailOverflowExtent = 56;

/// `NavigationRail`'s own spacer above its destinations, and again after its
/// `leading` widget when there is one.
const double kRailLeadingSpacer = 8;

/// Which end of the rail's column the default rail gathers its destinations
/// at — [AdaptiveShellConfig.railAlignment].
enum RailAlignment {
  /// Against the top, as Material lays a rail out. The overflow button follows
  /// the last destination.
  ///
  /// Leaves `NavigationRail.groupAlignment` unset, so a
  /// `NavigationRailThemeData.groupAlignment` still applies.
  top,

  /// Centred in the column, the overflow button following the last
  /// destination.
  center,

  /// Against the bottom, where the thumb of the hand holding the phone
  /// reaches — a folded iPhone Duo is held in one. The overflow button moves
  /// to the top: the end within reach is kept for the destinations, and the
  /// menu of the ones that did not fit goes where reaching costs more.
  ///
  /// "Bottom" is the physical bottom of the window, whichever end the system
  /// bar is at: on a Duo turned with its column on the right the camera is at
  /// the bottom too, and the destinations sit just above it.
  bottom,
}

/// Which end of its column the system's vertical bar keeps the camera and the
/// status glyphs at.
enum SystemBarEnd { top, bottom }

/// What a detail does to the shell's chrome where it opens over a single
/// pane — [AdaptiveShellConfig.detailChrome].
///
/// Where the detail has a pane of its own, beside the master, the chrome
/// stays whichever this is.
enum DetailChrome {
  /// The detail takes the whole window, the bar or the rail included, as
  /// Material puts a detail screen over the navigation. The chrome goes and
  /// comes back with the detail's own transition. In iPhone Duo's column the
  /// rail's destinations go and the detail's toolbar stays: it is the
  /// screen's, not the chrome.
  covered,

  /// The bar or the rail stays in view and in use beside the detail, as
  /// UIKit keeps a tab bar for a pushed screen that does not ask to hide it
  /// (`hidesBottomBarWhenPushed`). Apple platforms only — see
  /// [AdaptiveShellConfig.detailChrome].
  kept,
}

/// What tapping the active destination again does —
/// [AdaptiveShellConfig.reselect].
enum BranchReselect {
  /// Back to the branch root, as `UITabBarController` does and Material
  /// advises: `AdaptiveRouterDelegate.popToRoot`, gated by every `onExit`
  /// above the root. The root is the branch's first screen, so in a
  /// master-detail branch the detail goes too and the master is left with
  /// its placeholder, or alone where [MasterDetailConfig.collapseWhenDetailEmpty]
  /// is on.
  popToRoot,

  /// Nothing, as before 0.15.0. [AdaptiveShellConfig.onReselect] is still
  /// called.
  none,
}

/// Called after the active destination is tapped again, with the branch and
/// whether anything was taken off its stack. See
/// [AdaptiveShellConfig.onReselect].
typedef BranchReselectCallback = void Function(int branch, bool popped);

/// Picks the [SystemBarEnd] for a window, given the side the bar is on and
/// the size of the display the window is on, in logical pixels.
///
/// Only consulted without a [SystemGeometry.statusArea], which says which end
/// outright.
typedef SystemBarEndResolver =
    SystemBarEnd Function(Size window, ChromePlacement side, Size display);

/// A display whose shorter side is under this is iPhone Duo's outer one.
///
/// Measured: the outer display is 466 × 678 and the inner one 669 × 951
/// (`simctl io enumerate`, simulator, iOS 27.1). It is the display, not the
/// window, that tells them apart: a Split View window on the inner display
/// is 469 across, narrower than the outer display.
const double kCompactDisplayShortSide = 600;

/// iPhone Duo's outer display: the camera is in one corner of the glass, and
/// the system turns its column so the column is always on a long side.
///
/// Upright, that corner is the top right. Turned one way it ends up top left;
/// turned the other, bottom right — so the only landscape column with the
/// camera at its bottom is the one on the right (the status area at
/// 594…678 × 384…466 in `reservedRegions`, simulator, iOS 27.1).
///
/// The inner display keeps its status area at the top in either landscape
/// orientation, 867…951 × 0…120 both ways, so there the end is always the
/// top.
SystemBarEnd defaultSystemBarEnd(
  Size window,
  ChromePlacement side,
  Size display,
) {
  final bool outer = display.shortestSide < kCompactDisplayShortSide;
  final bool landscape = window.width > window.height;
  return outer && landscape && side == ChromePlacement.right
      ? SystemBarEnd.bottom
      : SystemBarEnd.top;
}

/// Where the system's own vertical bar sits inside the column it reserves.
///
/// On iPhone Duo that column holds the status glyphs and, on the outer
/// display, the camera at one end, and the rail joins the same column rather
/// than taking one of its own — the controls are meant to line up with the
/// camera. To sit *with* them the rail needs two things: how far its end of
/// the column the system's own elements reach, and which vertical line they
/// are centred on.
///
/// A [SystemGeometry.statusArea] answers the first outright, and where there
/// is one it replaces [reserve], [landscapeReserve], [innerReserve], [end],
/// and [statusRowTrailing]. The numbers here are the
/// fallback, for an app without a platform provider: the same areas as
/// measured on the simulator. They are used only where the window has a
/// vertical system bar on one side, which today means iPhone Duo and nothing
/// else; everywhere else the rail is flush against the window and starts at
/// the top.
@immutable
class SystemBarMetrics {
  const SystemBarMetrics({
    this.reserve = 170,
    this.landscapeReserve = 82,
    this.innerReserve = 120,
    this.axisFromEdge = 48,
    this.end = defaultSystemBarEnd,
    this.cornerClearance = 16,
    this.statusRowAxis = 48,
    this.statusRowTrailing = 134,
    this.statusColumnWidth = 72,
    this.columnInset = 24,
    this.followsSystemGeometry = true,
  });

  /// iPhone Duo as measured on the simulator, iOS 27.1. The status areas are
  /// the active occlusions in `UIView.reservedRegions` that touch the
  /// window's edge:
  ///
  /// - outer display, portrait: 382…466 × 0…170 — the column's top 170;
  /// - outer display, landscape: 0…84 × 0…82, or 594…678 × 384…466 at the
  ///   bottom when turned the other way — 82 either way, the clock hidden;
  /// - inner display, landscape: 867…951 × 0…120, both orientations, and
  ///   385…469 × 0…120 in the right-hand Split View window — 120;
  /// - inner display, portrait: 535…669 × 0…82, a row in the top right
  ///   corner, 134 across.
  ///
  /// The camera is centred 48 in from the edge (399.7…436.7 across a 466
  /// window), not on the middle of the 84-point column, which would be 42;
  /// the glyphs share that line.
  static const SystemBarMetrics measured = SystemBarMetrics();

  /// Treat the column as ordinary space: flush against the edge, no reserve,
  /// whatever the platform reports.
  static const SystemBarMetrics none = SystemBarMetrics(
    reserve: 0,
    landscapeReserve: 0,
    innerReserve: 0,
    axisFromEdge: kDefaultRailWidth / 2,
    cornerClearance: 0,
    followsSystemGeometry: false,
  );

  /// Kept free at the status end of the column on the outer display, measured
  /// from the window edge. At the bottom the home indicator's inset is part
  /// of it, not added to it.
  final double reserve;

  /// [reserve] for a landscape window on the outer display, where the system
  /// shows no clock.
  final double landscapeReserve;

  /// [reserve] on the inner display: landscape, and the Split View window
  /// that has the system's column. The column is narrower in content than on
  /// the outer display — the glyphs, no camera — and ends sooner.
  ///
  /// The outer and inner displays are told apart by the display's size, not
  /// the window's; see [kCompactDisplayShortSide].
  final double innerReserve;

  /// The reserve for a [window] on a display whose shorter side is under
  /// [kCompactDisplayShortSide] ([outerDisplay]) or not.
  double reserveFor(Size window, {required bool outerDisplay}) {
    if (!outerDisplay) {
      return innerReserve;
    }
    return window.width > window.height ? landscapeReserve : reserve;
  }

  /// Kept free at the top of a rail that does *not* share the system's column
  /// when nothing else is at the top, so the first destination stays out of
  /// the rounded corner.
  ///
  /// That rail is the one in the left-hand Split View window on iPhone Duo's
  /// inner display, which the system puts against the display's outer edge
  /// with no inset at the top and no column to share; or one a custom
  /// [ChromeLayout] put across the window from the system's bar. Measured:
  /// the inner display's `cornerSafeArea` is 16 in from the sides where the
  /// safe area is 0 (simulator, iOS 27.1).
  final double cornerClearance;

  /// Which end [reserve] is kept at, without a [SystemGeometry.statusArea].
  final SystemBarEndResolver end;

  /// How far down the glyphs are centred where they are a row in a corner;
  /// a lifted header is centred on it
  /// ([AdaptiveShellConfig.liftHeadersIntoStatusRow]).
  ///
  /// Measured on a screenshot of the inner display in portrait, flat
  /// (simulator, iOS 27.1, @3x): the clock's digits and the Wi-Fi glyph are
  /// both centred 48.0 down, and a header lifted onto 48 has its icons at
  /// 48.0–48.2 and its capitals at 48.2–48.3.
  ///
  /// It is not the middle of the status area, which is 82 deep there and
  /// would put the line at 41: the area is what the system keeps for itself,
  /// glyphs and the room around them, while this is the line the glyphs are
  /// drawn on, lower in the area than its middle.
  final double statusRowAxis;

  /// How much of the window's width, from its right edge, that row takes,
  /// without a [SystemGeometry.statusArea]. Measured: 535…669 across the
  /// inner display in portrait.
  ///
  /// The glyphs themselves start at 549.7, so a header's last action, which
  /// ends at 535, keeps some 15 points clear of the clock.
  final double statusRowTrailing;

  /// The top inset that centres a header [height] tall on [statusRowAxis],
  /// kept out of the rounded corner by [cornerClearance].
  double statusRowTop(double height) =>
      math.max(cornerClearance, statusRowAxis - height / 2);

  /// The width of the system's column where a vertical [PaneToolbar] has it
  /// to itself — no rail there — centred on [axisFromEdge]: 36 either side
  /// of a line 48 into the 84-point column. Below the status area, like the
  /// rail's destinations.
  final double statusColumnWidth;

  /// The line the system centres its glyphs on, measured in from the window
  /// edge. The rail is centred on the same line, and so are the buttons and
  /// tabs of the system's column.
  final double axisFromEdge;

  /// What the system's column keeps free at either end, round its toolbar
  /// and its tabs: from the status area to the first button, or from the
  /// window's edge where the status area is not at that end, and from the
  /// last tab to the window's bottom edge, or to the status area where it is
  /// at the bottom.
  ///
  /// Measured on the simulator (iPhone Duo, iOS 27.1, outer display upright):
  /// Safari's Back button starts 24 below the 170-point status area, and the
  /// Settings search button ends 24 above the window's bottom edge — inside
  /// the 34-point home indicator inset, which the column does not keep.
  final double columnInset;

  /// Whether a reported [SystemGeometry.statusArea] replaces the numbers
  /// above. [none] turns it off, so that "no reserve" means none.
  final bool followsSystemGeometry;

  /// How far the rail is held off the window edge to land on that line.
  double edgeGap(double railWidth) =>
      math.max(0.0, axisFromEdge - railWidth / 2);
}

/// Matches the detail pane reveal, so the shell's movements read as one.
const Duration kDefaultImmersiveDuration = Duration(milliseconds: 240);

/// Comfortable for a finger and for a mouse, and wider than the visible marker.
const double kDefaultPaneSplitHandleWidth = 24;

const double kPaneSplitDotSize = 3;

/// Equal to the dot diameter, so three dots read as one marker.
const double kPaneSplitDotGap = 3;

/// Colour of the canvas the panes float on.
///
/// A function of the context rather than a `Color`, because a shell config is
/// usually built once and kept, while the colour has to follow the theme. Same
/// for [ShellCardShadow] and [ShellCardBorder].
typedef PaneCanvasColor = Color Function(BuildContext context);

typedef ShellCardShadow = List<BoxShadow> Function(BuildContext context);

typedef ShellCardBorder = BoxBorder Function(BuildContext context);

/// Rail decoration: the rail can be a floating card too.
///
/// Margin and divider are part of the width arithmetic, so this is data rather
/// than styling. The default is a solid edge-to-edge strip plus a divider.
@immutable
class RailDecoration {
  const RailDecoration({
    this.margin = EdgeInsets.zero,
    this.radius = BorderRadius.zero,
    this.dividerWidth = kDefaultRailDividerWidth,
    this.shadow,
    this.border,
    this.backgroundColor,
  });

  /// A full-height strip with a divider after it.
  static const RailDecoration none = RailDecoration();

  /// True when the rail has no margin and no corner radius, so it fills its
  /// column instead of floating on the canvas.
  bool get isFlush => margin == EdgeInsets.zero && radius == BorderRadius.zero;

  /// Outer margin of the rail card. Its horizontal part reduces the space left
  /// for the panes.
  final EdgeInsets margin;

  final BorderRadius radius;

  /// `0` — no divider; a floating card is bounded by the gap around it.
  final double dividerWidth;

  /// Without one, a floating capsule barely reads as floating: its contrast
  /// against the background is low and a column of icons never touches its
  /// edges to outline the shape. Painted around the same area, so it changes no
  /// geometry.
  final ShellCardShadow? shadow;

  /// What actually holds the capsule's shape in a dark theme, where a shadow is
  /// dark on dark. Painted inside the card's bounds and adds no size.
  final ShellCardBorder? border;

  /// Fills the whole rail column, including the part
  /// [SystemBarMetrics.reserve] keeps free at the top.
  ///
  /// `NavigationRail` paints only as far as it is laid out, so without this the
  /// reserve would show the canvas through and the column would read as two
  /// pieces rather than one. `null` resolves the way `NavigationRail` resolves
  /// its own background — the theme first, then `ColorScheme.surface` — which
  /// is seamless for the default rail; a [AdaptiveShellConfig.railBuilder] that
  /// paints something else should say so here.
  final PaneCanvasColor? backgroundColor;

  /// Total horizontal space a decorated rail occupies.
  double regionWidth(double railWidth) =>
      railWidth + margin.horizontal + dividerWidth;
}

/// Pane decoration: rounded cards floating on a canvas, inset from the rail and
/// the window edges.
///
/// The margins and the gap reduce the width left to the panes, so they count
/// towards the "one pane or two" threshold — which is why they are config data
/// the package needs at build time, not a theme. The default puts the panes
/// flush, and the gap replaces the divider that used to sit between them.
@immutable
class PaneDecoration {
  const PaneDecoration({
    this.margin = EdgeInsets.zero,
    this.gap = 0,
    this.radius = BorderRadius.zero,
    this.canvasColor,
    this.border,
    this.splitHandleWidth = kDefaultPaneSplitHandleWidth,
    this.splitHandleColor,
  });

  /// Panes flush against each other, filling the content area.
  static const PaneDecoration none = PaneDecoration();

  /// From the rail divider on the left, from the window edges elsewhere.
  final EdgeInsets margin;

  final double gap;

  final BorderRadius radius;

  /// Visible in the margin and the gap. `null` — the `Scaffold` background.
  final PaneCanvasColor? canvasColor;

  /// The same line that outlines the rail capsule; otherwise the rail and the
  /// panes read as elements of a different nature.
  final ShellCardBorder? border;

  /// Hit area around the divider, centred on the gap.
  ///
  /// Wider than the gap, because 8 logical pixels cannot be hit by finger or
  /// mouse. Where it overlaps the panes it is `translucent`: taps and vertical
  /// scrolling reach the pane, only horizontal drags are claimed.
  final double splitHandleWidth;

  /// Colour of the three-dot marker in the gap. `null` leaves the hit area
  /// invisible — which on a tablet means nothing advertises that the boundary
  /// can be dragged at all, since there is no cursor to change.
  final PaneCanvasColor? splitHandleColor;

  /// Width actually left to the panes out of the content area.
  double paneAreaWidth(double contentWidth) => contentWidth - margin.horizontal;
}

/// How a branch splits: master is the branch root, detail is everything above.
@immutable
class MasterDetailConfig {
  const MasterDetailConfig({
    this.paneRatio = 0.38,
    this.masterMinWidth = 320,
    this.detailMinWidth = 360,
    this.collapseWhenDetailEmpty = true,
    this.alignToFold = true,
    this.alignToWindowCenter = false,
    this.portraitPaneRatio,
  }) : assert(
         portraitPaneRatio == null ||
             (portraitPaneRatio > 0 && portraitPaneRatio < 1),
         'portraitPaneRatio must be between 0 and 1',
       );

  /// Share of the available width given to the master pane.
  ///
  /// Overridden by [portraitPaneRatio] in a portrait window, by
  /// [alignToWindowCenter], by an active fold ([alignToFold]) and by the
  /// user's drag.
  final double paneRatio;

  final double masterMinWidth;

  final double detailMinWidth;

  /// While the detail is empty, the split collapses and the master takes the
  /// whole content area. `false` keeps two panes and shows
  /// [BranchConfig.detailPlaceholder] in the empty one.
  ///
  /// Only widths change either way — both navigators stay mounted, so screen
  /// state survives the collapse and the expansion.
  final bool collapseWhenDetailEmpty;

  /// While the device is half open, put the boundary on the fold instead of
  /// where [paneRatio] or the user's drag would have it.
  ///
  /// A pane straddling a crease is bent across two planes at an angle, which
  /// is the one posture where the split's position is not a preference. The
  /// fold only wins while it is reported active *and* both panes still clear
  /// their minimums around it; flat, or too far to one side, and the ordinary
  /// width applies again — so the boundary moves once, on the fold, and back.
  ///
  /// The fold comes from `MediaQuery.displayFeatures`, which the framework
  /// fills on Android and not yet on iOS, then from [SystemGeometry.folds],
  /// which adaptive_nav_ios fills on iPhone Duo; see `FoldMetrics`.
  final bool alignToFold;

  /// Put the boundary on the window's horizontal centre instead of at
  /// [paneRatio], with the gap split evenly around it.
  ///
  /// A rail on the left comes out of the master's half. The user's drag and an
  /// active fold still win, and the pane minimums still apply.
  final bool alignToWindowCenter;

  /// [paneRatio] for a portrait window; `null` keeps [paneRatio] there too.
  ///
  /// Wins over [alignToWindowCenter] and [paneRatio]. The user's drag and an
  /// active fold still win, and the pane minimums still apply.
  final double? portraitPaneRatio;

  /// Whether [available] — the pane width, decoration margins already removed —
  /// fits two unsqueezed panes plus the [gap]. If not, the branch renders as a
  /// compact stack: a detail narrower than its list is worse than no split.
  bool fits(double available, {required double gap}) =>
      available >= masterMinWidth + detailMinWidth + gap;

  /// Master width for [available]. Only call it when [fits].
  ///
  /// [fraction] is the user's dragged share; without one,
  /// [portraitPaneRatio] in a [portrait] window, then [centre] (the window
  /// centre in pane-area coordinates, for [alignToWindowCenter]) or
  /// [paneRatio] decides. All go through [clampMasterWidth] — a hand-picked
  /// width obeys the same minimums as a computed one.
  double masterWidthFor(
    double available, {
    required double gap,
    double? fraction,
    double? centre,
    bool portrait = false,
  }) => clampMasterWidth(
    fraction != null
        ? available * fraction
        : portrait && portraitPaneRatio != null
        ? available * portraitPaneRatio!
        : centre != null
        ? centre - gap / 2
        : available * paneRatio,
    available,
    gap: gap,
  );

  /// Neither pane may go below its minimum. This is also the drag limit; there
  /// is no separate minimum for dragging.
  double clampMasterWidth(
    double width,
    double available, {
    required double gap,
  }) {
    final double maxMaster = available - detailMinWidth - gap;
    if (maxMaster <= masterMinWidth) {
      return masterMinWidth;
    }
    return width.clamp(masterMinWidth, maxMaster).toDouble();
  }

  /// Whether [fold] leaves both panes their minimums, so the boundary can go
  /// on it rather than where the width would put it.
  ///
  /// The panes meet on [PaneFold.centre], and what each one keeps clear of it
  /// — half the crease, or half the [gap] where that is wider — is not width
  /// it can use, the same as an inset it reaches under. So the minimums are
  /// checked against what is left, the content the user actually sees.
  bool fitsAround(PaneFold fold, double available, {double gap = 0}) {
    final double clear = math.max(gap, fold.width) / 2;
    return fold.centre - clear >= masterMinWidth &&
        available - fold.centre - clear >= detailMinWidth;
  }

  /// Whether there is room to move the divider. At exactly the threshold width
  /// both panes are already at their minimums, and a handle would be a lie.
  bool isResizable(double available, {required double gap}) =>
      available - detailMinWidth - gap > masterMinWidth;
}

/// One navigation branch (a tab).
@immutable
class BranchConfig<R> {
  const BranchConfig({
    required this.id,
    required this.icon,
    required this.label,
    required this.pageBuilder,
    this.masterDetail,
    this.transition = AppTransition.platform,
    this.detailPlaceholder,
    this.showsInChrome = true,
    this.visibilityPriority = 0,
    this.verticalCompression = VerticalBarCompression.toolbarFirst,
  });

  /// Stable identifier, used for comparison and debugging.
  final Object id;

  final IconData icon;

  final String label;

  /// The package knows nothing about screens; this is where the app comes in.
  final Widget Function(R route) pageBuilder;

  /// `null` — a plain tab, one stack in any layout.
  final MasterDetailConfig? masterDetail;

  final AppTransition transition;

  /// Shown in an empty detail pane, when the split is not collapsed.
  ///
  /// `null` leaves the pane blank. The package does not put a caption there:
  /// it knows nothing about the app's screens and could not localise one
  /// anyway, so "Select a person" and the like belong here.
  final WidgetBuilder? detailPlaceholder;

  /// `false` keeps the branch alive — stack, state, mounted navigator — but
  /// gives it no destination: it is entered programmatically only. While such a
  /// branch is active, no chrome destination is highlighted.
  final bool showsInChrome;

  /// Which destinations the default rail puts behind its menu first when its
  /// column cannot hold them all: the lowest, and among equals the last.
  ///
  /// The rail keeps its order either way, the hidden ones simply missing
  /// from it; an active branch among them lights the menu button up.
  final int visibilityPriority;

  /// Who gives up room in the system's column while this branch is active,
  /// when a vertical [PaneToolbar] and the rail do not both fit. A screen's
  /// [PaneToolbar.compression] overrides it.
  final VerticalBarCompression verticalCompression;
}

/// `R ↔ URL`, injected by the app. The package only drives deep links and cold
/// start through it.
abstract class RouteCodec<R> {
  const RouteCodec();

  Uri encode(R route);

  /// What to do with something unrecognised is the app's call; usually a
  /// fallback to the home screen.
  R decode(Uri uri);

  /// Which branch a route lands on when opened from a URL or a push.
  int branchOf(R route);
}

/// Shell configuration: branches, layout thresholds, chrome and decoration.
@immutable
class AdaptiveShellConfig<R> {
  const AdaptiveShellConfig({
    required this.branches,
    this.chromeLayout = defaultChromeLayout,
    this.foldLocator,
    this.railWidth = kDefaultRailWidth,
    this.railDestinationExtent,
    this.railOverflow = true,
    this.railOverflowBuilder,
    this.railAlignment,
    this.systemBar = SystemBarMetrics.measured,
    this.rail = RailDecoration.none,
    this.panes = PaneDecoration.none,
    this.paneSplit,
    this.redirect,
    this.showsChrome,
    this.barBuilder,
    this.railBuilder,
    this.drawerBuilder,
    this.scaffoldKey,
    this.extendBodyBehindBar = false,
    this.branchFadeDuration = Duration.zero,
    this.immersive,
    this.immersiveDuration = kDefaultImmersiveDuration,
    this.backToBranch,
    this.liftHeadersIntoStatusRow = false,
    this.detailChrome = DetailChrome.covered,
    this.railLabelsInColumn = NavigationRailLabelType.none,
    this.automaticBackInColumn = true,
    this.reselect = BranchReselect.popToRoot,
    this.onReselect,
  }) : assert(
         backToBranch == null || backToBranch >= 0,
         'backToBranch must be a branch index',
       );

  /// At least one; at least two with [BranchConfig.showsInChrome] for the
  /// Material bar and rail, unless [barBuilder] and [railBuilder] are given.
  final List<BranchConfig<R>> branches;

  /// Where the bar or the rail goes. See [defaultChromeLayout]; replace it to
  /// take the decision over entirely. It is handed the nearest
  /// [SystemGeometryScope]'s geometry along with the window.
  final ChromeLayout chromeLayout;

  /// Where the crease is, for a device whose platform does not say.
  ///
  /// `MediaQuery.displayFeatures` is consulted first, then
  /// [SystemGeometry.folds], and this only fills the silence after both. On
  /// iPhone Duo adaptive_nav_ios reports the real fold through
  /// [SystemGeometryScope], posture included, so this is for a device nothing
  /// reports. `null` — no fold unless the platform reports one.
  ///
  /// Only consulted where [MasterDetailConfig.alignToFold] is on.
  final FoldLocator? foldLocator;

  /// How much the wide layout gives up on the left before the panes get their
  /// share. Declared rather than measured, because the layout is decided at
  /// build time.
  ///
  /// **Invariant:** it must match the actual width of the widget from
  /// [railBuilder]. If they disagree, the detail pane width is off by the
  /// difference.
  final double railWidth;

  /// Height of a destination in the default rail, used to decide how many of
  /// them fit. It applies to every destination alike; `null` lays each label
  /// out and works each one out on its own — see [kRailDestinationBase].
  final double? railDestinationExtent;

  /// When the default rail has more destinations than its column can hold, put
  /// the ones that do not fit behind a menu button at its end.
  ///
  /// `false` lets them overflow instead, which is what Material does on its
  /// own. Nothing here applies to a [railBuilder] rail: that one is the app's
  /// to fit.
  ///
  /// It matters on a folded iPhone Duo, where the column is short and shares
  /// its top with the system bar: seven one-line destinations fit upright,
  /// five turned, against a desktop's dozen.
  final bool railOverflow;

  /// Builds that menu button in place of the Material one — `null` is an
  /// `IconButton` opening a `MenuAnchor`, filled tonal while the active branch
  /// is one of the hidden ones.
  ///
  /// The button and its menu only. Where it sits, how tall it is and which
  /// destinations it carries stay with the shell, because [railOverflow]'s
  /// count depends on all three. Nothing here applies to a [railBuilder] rail
  /// either, for the same reason [railOverflow] does not: that one is the
  /// app's to fit, overflow included.
  final ShellRailOverflowBuilder? railOverflowBuilder;

  /// Which end of its column the default rail keeps its destinations at.
  ///
  /// [RailAlignment.bottom] brings them within reach of the thumb and moves
  /// the overflow button to the top of the rail; which destinations go behind
  /// it does not change — the last ones, in order, as with the button at the
  /// end.
  ///
  /// `null` decides by the column. Where the rail shares it with the system's
  /// vertical bar — iPhone Duo — that is [RailAlignment.bottom]: Apple orders
  /// the column top to bottom as status bar, toolbar, tab bar, so the
  /// destinations go to the end away from the clock. Everywhere else it is
  /// [RailAlignment.top], as Material lays a rail out. A value set here
  /// applies everywhere, [RailAlignment.top] included — except iPhone Duo's
  /// system column, whose tabs have a zone of their own at its bottom
  /// ([railLabelsInColumn]).
  ///
  /// Nothing here applies to a [railBuilder] rail.
  final RailAlignment? railAlignment;

  /// How the rail lines itself up with a system vertical bar it shares a
  /// column with — iPhone Duo, and nowhere else. See [SystemBarMetrics];
  /// [SystemBarMetrics.none] ignores the bar entirely.
  final SystemBarMetrics systemBar;

  /// [railWidth] is the width of the rail itself, without the margin: the app
  /// lays its destinations into that, and the package adds the card margin
  /// around them.
  final RailDecoration rail;

  /// **Invariant:** an app that computes the layout with a formula of its own
  /// has to subtract the same margins and gap, or the shell and the screens
  /// will disagree at the boundary.
  final PaneDecoration panes;

  /// `null` — the divider is fixed and widths follow
  /// [MasterDetailConfig.paneRatio] (or the window centre, with
  /// [MasterDetailConfig.alignToWindowCenter]). Otherwise the boundary can be
  /// dragged and the master share comes from the controller.
  ///
  /// A mutable object inside an immutable config, like [scaffoldKey]: the
  /// config holds a reference to something the app owns and never mutates it.
  final PaneSplitController? paneSplit;

  final RedirectHook<R>? redirect;

  /// `null` — chrome is always shown. `false` from the predicate renders the
  /// active branch full screen.
  final ChromeVisibility<R>? showsChrome;

  /// A custom bar for the compact layout. Called exactly where the default
  /// would be drawn, so it is skipped while a branch with
  /// `showsInChrome: false` is active — `NavigationBar.selectedIndex` is not
  /// nullable, and a wrapper around it inherits that.
  final ShellChromeBuilder? barBuilder;

  /// A custom rail. The divider after it stays with the package, since it is
  /// part of the [MasterDetailConfig.fits] arithmetic; the builder must not add
  /// one.
  final ShellChromeBuilder? railBuilder;

  /// Not attached while chrome is hidden, or an edge swipe would open the
  /// signed-in area's drawer on the auth screen.
  final ShellDrawerBuilder? drawerBuilder;

  /// Lets the app open the drawer from any screen. Set on the `Scaffold` of
  /// both layouts; they never exist at the same time.
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// Extends the body behind the navigation bar, compact only.
  ///
  /// Off by default by design, not caution: under the opaque default
  /// `NavigationBar` the content would disappear. Scrolling under the bar is a
  /// property of a floating bar, and a floating bar comes from [barBuilder], so
  /// the decision belongs to the app.
  final bool extendBodyBehindBar;

  /// Fades tab switches instead of swapping instantly. The value is the fade
  /// in; the fade out is half as long, as in the Material motion spec.
  ///
  /// Purely visual: every branch's navigator stays mounted throughout, so tab
  /// state is untouched. Transitions between screens inside a branch come from
  /// [BranchConfig.transition] instead.
  final Duration branchFadeDuration;

  /// Slides the rail out of the wide layout and hands the strip to the panes.
  /// `null` — no immersive mode at all, and no listener or extra layer.
  ///
  /// A `ValueListenable` because the config is usually built once while the
  /// flag changes at runtime; the listener rebuilds only the layout row. The
  /// package does not know why the app wants the full width, and the mode is
  /// deliberately narrow in what it does — see `doc/design.md`.
  final ValueListenable<bool>? immersive;

  /// The curve stays internal; only the duration is exposed.
  final Duration immersiveDuration;

  /// The branch system back leads to from the root of any other branch — the
  /// start tab, as in most Android apps. `null` — back at a branch root goes to
  /// the system.
  ///
  /// Dialogs, the drawer, pushed screens and a detail are popped first. The
  /// root's `onExit` is asked as on a tab tap. Must be an index into
  /// [branches].
  final int? backToBranch;

  /// Experimental, iOS only: lifts the panes' headers into the status row
  /// where the glyphs take only its corner — iPhone Duo's inner display in
  /// portrait.
  ///
  /// Each pane hands its screen a top inset that centres a [kToolbarHeight]
  /// toolbar on the glyphs ([SystemBarMetrics.statusRowTop]). The pane under
  /// the glyphs reports how much of its trailing end they cover through
  /// [StatusRowScope.trailingReserveOf]; the screen keeps its actions clear
  /// with a trailing box that wide, since an `AppBar` lays out its own.
  ///
  /// Recognised from `MediaQuery`: a bottom bar, a top inset of at least
  /// [kPhoneStatusBarInset], no side bar and a portrait window at least
  /// [kCompactWidthBreakpoint] wide. Elsewhere this changes nothing. How much
  /// of the row the glyphs take comes from [SystemGeometry.statusArea] where
  /// there is one, [SystemBarMetrics.statusRowTrailing] otherwise.
  ///
  /// Off by default: a header that is not a [kToolbarHeight] toolbar, or has
  /// no trailing box, ends up under the clock.
  final bool liftHeadersIntoStatusRow;

  /// Whether an open detail covers the chrome where it opens over a single
  /// pane: the bar on a phone, or a rail beside one pane.
  ///
  /// [DetailChrome.covered], the default, is Material's: a detail is a
  /// screen of its own, over the navigation. [DetailChrome.kept] is what an
  /// iOS app does with a tab bar: it stays, the detail ends at its top edge,
  /// and a tab tapped from the detail switches branches as anywhere else,
  /// the detail kept in its branch. On iPhone Duo the column then reads, top
  /// to bottom, status bar, Back, actions, tab bar.
  ///
  /// [DetailChrome.kept] applies only where `Theme.of(context).platform` is
  /// [TargetPlatform.iOS] or [TargetPlatform.macOS], and is ignored —
  /// [DetailChrome.covered] — everywhere else, without an assertion: a
  /// navigation bar left beside a detail is not a Material pattern, and the
  /// same config should serve both. Read from the theme rather than the
  /// host, so an app that overrides the platform, a playground showing an
  /// iPhone in a browser, behaves as that device.
  ///
  /// Two panes are not affected: the detail is in a pane of its own there.
  final DetailChrome detailChrome;

  /// The tabs' labels in iPhone Duo's system column; a rail anywhere else
  /// shows them all. The app's call, not the user's.
  ///
  /// - [NavigationRailLabelType.none], the default: icons only, as Apple
  ///   draws a vertical tab bar. The label is the tab's tooltip and its
  ///   semantic label.
  /// - [NavigationRailLabelType.all]: a label under every icon.
  /// - [NavigationRailLabelType.selected]: a label under the current tab's
  ///   icon only — but every tab keeps the room for one. A label that came
  ///   and went with the selection would make the tab taller and shift every
  ///   tab below it on each switch, and with the column's height the number
  ///   of tabs that fit, so the More button would come and go as well.
  ///
  /// The number of tabs that fit depends only on the column's height and on
  /// this, never on the screen or the selection; see
  /// [SystemBarMetrics.columnInset].
  final NavigationRailLabelType railLabelsInColumn;

  /// Whether a screen without a `PaneToolbar` gets its navigation button in
  /// iPhone Duo's system column, as `UINavigationController` puts Back in
  /// the vertical bar whatever the screen's own bar holds.
  ///
  /// On by default. Wherever a pane's toolbar is vertical
  /// (`PaneBarScope`), the shell stands Back — or Close, by the rules of a
  /// `PaneToolbar` without a `navigation` — in the column's toolbar zone for
  /// the screen on top of that pane, and the screen's `AppBar` draws no arrow
  /// of its own meanwhile: the route withholds `impliesAppBarDismissal` from
  /// it. Where the toolbar is a header, the `AppBar` has its arrow as usual.
  ///
  /// A screen that has decided about the button is left alone: an `AppBar`
  /// with a `leading`, or with `automaticallyImplyLeading: false`, keeps its
  /// header, and the column gets nothing. `false` brings the arrow back to
  /// every header and leaves the column to `PaneToolbar`s.
  ///
  /// Only the pages the shell builds take part: a route pushed on a pane's
  /// navigator past the router keeps the `AppBar`'s arrow.
  final bool automaticBackInColumn;

  /// What tapping the active destination again does: back to the branch
  /// root by default — see [BranchReselect].
  ///
  /// Every destination the shell draws counts: the bar, the rail, the tabs in
  /// iPhone Duo's system column, folded or not, and the active tab's item in
  /// a More or overflow menu. So does a [barBuilder] or [railBuilder] that
  /// calls its `onSelectBranch` with the active branch, and a
  /// [railOverflowBuilder]'s. `AdaptiveRouterDelegate.goBranch` with the
  /// active branch is not a tap and stays a no-op.
  final BranchReselect reselect;

  /// Called after every tap on the active destination, whatever [reselect]
  /// is, once the gate has answered. `popped` says whether anything was taken
  /// off the stack: `false` at the root, after a refusing `onExit`, or with
  /// [BranchReselect.none]. A list already at its root can scroll to the top
  /// then, as iOS does on a second tap.
  final BranchReselectCallback? onReselect;
}
