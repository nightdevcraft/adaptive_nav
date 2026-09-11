// material, not widgets: the config refers to `ScaffoldState`.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// Given the router area's width and safe-area padding, decides between the
/// rail (`true`) and the bar (`false`). Pane count is decided separately, by
/// [MasterDetailConfig.fits].
typedef ChromePredicate = bool Function(double width, EdgeInsets padding);

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

/// Builds the shell drawer. [rail] tells which layout is up; `null` also
/// disables the edge swipe.
typedef ShellDrawerBuilder = Widget? Function(BuildContext context, bool rail);

/// Whether to show chrome for a given state. A predicate over the state rather
/// than a flag on the branch, so it covers both a tabless branch and a single
/// full-screen screen inside a normal one.
typedef ChromeVisibility<R> = bool Function(NavState<R> state);

/// Rail from 600 logical pixels — the compact/medium boundary of the Material 3
/// window size classes.
bool defaultShowsRail(double width, EdgeInsets padding) =>
    (width - padding.horizontal) >= 600;

/// `NavigationRail.minWidth`.
const double kDefaultRailWidth = 80;

const double kDefaultRailDividerWidth = 1;

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
  });

  /// A full-height strip with a divider after it.
  static const RailDecoration none = RailDecoration();

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
  });

  /// Share of the available width given to the master pane.
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

  /// Whether [available] — the pane width, decoration margins already removed —
  /// fits two unsqueezed panes plus the [gap]. If not, the branch renders as a
  /// compact stack: a detail narrower than its list is worse than no split.
  bool fits(double available, {required double gap}) =>
      available >= masterMinWidth + detailMinWidth + gap;

  /// Master width for [available]. Only call it when [fits].
  ///
  /// [fraction] is the user's dragged share; `null` falls back to [paneRatio].
  /// Both go through [clampMasterWidth] — a hand-picked width obeys the same
  /// minimums as a computed one.
  double masterWidthFor(
    double available, {
    required double gap,
    double? fraction,
  }) => clampMasterWidth(
    available * (fraction ?? paneRatio),
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
    this.showsRail = defaultShowsRail,
    this.railWidth = kDefaultRailWidth,
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
  });

  final List<BranchConfig<R>> branches;
  final ChromePredicate showsRail;

  /// How much the wide layout gives up on the left before the panes get their
  /// share. Declared rather than measured, because the layout is decided at
  /// build time.
  ///
  /// **Invariant:** it must match the actual width of the widget from
  /// [railBuilder]. If they disagree, the detail pane width is off by the
  /// difference.
  final double railWidth;

  /// [railWidth] is the width of the rail itself, without the margin: the app
  /// lays its destinations into that, and the package adds the card margin
  /// around them.
  final RailDecoration rail;

  /// **Invariant:** an app that computes the layout with a formula of its own
  /// has to subtract the same margins and gap, or the shell and the screens
  /// will disagree at the boundary.
  final PaneDecoration panes;

  /// `null` — the divider is fixed and widths follow
  /// [MasterDetailConfig.paneRatio]. Otherwise the boundary can be dragged and
  /// the master share comes from the controller.
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
}
