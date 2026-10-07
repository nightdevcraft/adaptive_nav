// material, not widgets: the config refers to `ScaffoldState`.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fold.dart';
import 'nav_state.dart';
import 'pane_split.dart';

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

/// Given the window and its safe-area padding, decides where the chrome goes.
/// Pane count is decided separately, by [MasterDetailConfig.fits].
typedef ChromeLayout =
    ChromePlacement Function(Size window, EdgeInsets padding);

/// A one-sided horizontal inset at least this wide is a system bar standing on
/// its end, not a cutout.
///
/// Measured: iPhone Duo reserves 84 for its vertical status bar. A notched
/// iPhone in landscape reserves 62 — but on *both* sides, which is what
/// [defaultChromeLayout] actually keys on; this threshold only keeps a
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

/// Rail from 600 logical pixels — the compact/medium boundary of the Material 3
/// window size classes — with iPhone Duo's postures taken first.
///
/// Three rules, in order:
///
/// 1. A substantial inset on exactly one side is the system's own vertical
///    bar. On a display narrow enough to be compact the chrome joins it: that
///    is iPhone Duo's outer display, where the bar and the camera share one
///    column and the rail belongs in it.
/// 2. A phone-shaped status bar means horizontal bars, which is what the Duo's
///    inner display in portrait asks for.
/// 3. Otherwise the width breakpoint, as before — and the rail goes to the
///    leading edge even where a system bar is on the other one. The Duo's
///    inner display in landscape is wide enough for the rail and the panes to
///    keep the arrangement they have everywhere else; the pane against the
///    bar bleeds under it instead.
///
/// Rule 1 is fenced off to a display that really does carry a side bar: it
/// wants a one-sided inset of [kVerticalBarInset] *and* a compact width. iOS
/// reports the landscape insets symmetrically and a display cutout is
/// narrower than the threshold, so nothing else reaches it.
///
/// Rule 2 is not fenced that way. It reads the top inset alone, so any window
/// at least [kPhoneStatusBarInset] deep at the top gets horizontal bars,
/// however wide it is and whatever device it belongs to. Nothing measured
/// reports that on a window wide enough for a rail — an iPad sends 24, a
/// desktop 0 — but a device that did would follow the Duo's inner display
/// rather than the width breakpoint.
///
/// `chrome_layout_test.dart` pins both: the devices that must not change, and
/// what a deep top inset does when it turns up.
ChromePlacement defaultChromeLayout(Size window, EdgeInsets padding) {
  final bool wide = (window.width - padding.horizontal) >= 600;
  final bool barLeft =
      padding.left >= kVerticalBarInset && padding.right < kVerticalBarInset;
  final bool barRight =
      padding.right >= kVerticalBarInset && padding.left < kVerticalBarInset;
  if (!wide && barLeft) {
    return ChromePlacement.left;
  }
  if (!wide && barRight) {
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

/// Height the overflow button takes at the end of the rail.
const double kRailOverflowExtent = 56;

/// `NavigationRail`'s own spacer above its destinations.
const double kRailLeadingSpacer = 8;

/// Which end of its column the system's vertical bar keeps the camera and the
/// status glyphs at.
enum SystemBarEnd { top, bottom }

/// Picks the [SystemBarEnd] for a window, given the side the bar is on.
typedef SystemBarEndResolver =
    SystemBarEnd Function(Size window, ChromePlacement side);

/// iPhone Duo's outer display: the camera is in one corner of the glass, and
/// the system turns its column so the column is always on a long side.
///
/// Upright, that corner is the top right. Turned one way it ends up top left;
/// turned the other, bottom right — so the only landscape column with the
/// camera at its bottom is the one on the right.
SystemBarEnd defaultSystemBarEnd(Size window, ChromePlacement side) {
  final bool landscape = window.width > window.height;
  return landscape && side == ChromePlacement.right
      ? SystemBarEnd.bottom
      : SystemBarEnd.top;
}

/// Where the system's own vertical bar sits inside the column it reserves.
///
/// On iPhone Duo's outer display that column holds the camera at one end and
/// the status bar below it, and the rail joins the same column rather than
/// taking one of its own — the controls are meant to line up with the camera.
/// To sit *with* them the rail needs two things the system does not report:
/// how far down its own elements end, and which vertical line they are centred
/// on.
///
/// The defaults were read off screenshots of the simulator, so they are
/// numbers to adjust rather than to trust. They are used only where the
/// window has a vertical system bar on one side, which today means iPhone Duo
/// and nothing else; everywhere else the rail is flush against the window and
/// starts at the top.
@immutable
class SystemBarMetrics {
  const SystemBarMetrics({
    this.reserve = 150,
    this.landscapeReserve = 80,
    this.axisFromEdge = 48,
    this.end = defaultSystemBarEnd,
    this.cornerClearance = 16,
  });

  /// What was measured: the status glyphs end about 150 points down, and the
  /// symmetric ones are centred 48 points in from the window edge — not on
  /// the middle of the 84-point column, which would be 42. In landscape the
  /// outer display hides the clock and only the camera is left, which ends
  /// about 65 points in.
  static const SystemBarMetrics measured = SystemBarMetrics();

  /// Treat the column as ordinary space: flush against the edge, no reserve.
  static const SystemBarMetrics none = SystemBarMetrics(
    reserve: 0,
    landscapeReserve: 0,
    axisFromEdge: kDefaultRailWidth / 2,
    cornerClearance: 0,
  );

  /// Kept free at the camera's end of the column, measured from the window
  /// edge. At the bottom the home indicator's inset is part of it, not added
  /// to it.
  final double reserve;

  /// [reserve] for a landscape window, where the system shows no clock.
  final double landscapeReserve;

  /// Kept free at the top of a rail that does *not* share the system's column
  /// — the bar is on the far edge — when nothing else is at the top. That is
  /// iPhone Duo's inner display in landscape: no inset at the top, so without
  /// it the first destination sits in the rounded corner.
  final double cornerClearance;

  /// Which end [reserve] is kept at.
  final SystemBarEndResolver end;

  /// The line the system centres its glyphs on, measured in from the window
  /// edge. The rail is centred on the same line.
  final double axisFromEdge;

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
  /// [AdaptiveShellConfig.systemBarReserve] keeps free at the top.
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
  });

  /// Share of the available width given to the master pane.
  ///
  /// Overridden by [alignToWindowCenter], by an active fold ([alignToFold])
  /// and by the user's drag.
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
  /// Requires `MediaQuery.displayFeatures`, which the framework fills on
  /// Android and not yet on iOS; see `FoldMetrics`.
  final bool alignToFold;

  /// Put the boundary on the window's horizontal centre instead of at
  /// [paneRatio], with the gap split evenly around it.
  ///
  /// A rail on the left comes out of the master's half. The user's drag and an
  /// active fold still win, and the pane minimums still apply.
  final bool alignToWindowCenter;

  /// Whether [available] — the pane width, decoration margins already removed —
  /// fits two unsqueezed panes plus the [gap]. If not, the branch renders as a
  /// compact stack: a detail narrower than its list is worse than no split.
  bool fits(double available, {required double gap}) =>
      available >= masterMinWidth + detailMinWidth + gap;

  /// Master width for [available]. Only call it when [fits].
  ///
  /// [fraction] is the user's dragged share; without one, [centre] (the
  /// window centre in pane-area coordinates, for [alignToWindowCenter]) or
  /// [paneRatio] decides. All go through [clampMasterWidth] — a hand-picked
  /// width obeys the same minimums as a computed one.
  double masterWidthFor(
    double available, {
    required double gap,
    double? fraction,
    double? centre,
  }) => clampMasterWidth(
    fraction != null
        ? available * fraction
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
  bool fitsAround(PaneFold fold, double available) =>
      fold.start >= masterMinWidth && available - fold.end >= detailMinWidth;

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
  }) : assert(
         backToBranch == null || backToBranch >= 0,
         'backToBranch must be a branch index',
       );

  final List<BranchConfig<R>> branches;

  /// Where the bar or the rail goes. See [defaultChromeLayout]; replace it to
  /// take the decision over entirely.
  final ChromeLayout chromeLayout;

  /// Where the crease is, for a device whose platform does not say.
  ///
  /// `MediaQuery.displayFeatures` is consulted first and this only fills the
  /// silence, so an app can pass [FoldMetrics.windowCentre] on iOS today and
  /// take nothing away from an Android foldable that reports a real fold.
  /// `null` — no fold unless the platform reports one.
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
  /// its top with the system bar: about seven destinations fit there against a
  /// desktop's dozen.
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

  /// How the rail lines itself up with a system vertical bar it shares a
  /// column with — iPhone Duo's outer display, and nowhere else. See
  /// [SystemBarMetrics]; [SystemBarMetrics.none] ignores the bar entirely.
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
}
