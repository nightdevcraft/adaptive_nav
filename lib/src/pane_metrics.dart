import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'nav_config.dart';

/// How far the panes reach under a safe-area inset that nothing else covers.
///
/// A pane card bleeds to the window edge on purpose — Apple's own guidance is
/// that background reaches past the safe area while foreground stays inside —
/// so the inset is not width the panes can *use*. It is subtracted from the
/// pane area, and the pane on that side is laid out wider by the same amount,
/// which is exactly what its screen then insets away.
///
/// This became load-bearing on iPhone Duo, where the status bar is a vertical
/// strip 84 logical pixels wide on one side. On a notched phone it was worth a
/// couple of pixels.
@immutable
class PaneUnderlap {
  const PaneUnderlap({required this.left, required this.right});

  static const PaneUnderlap zero = PaneUnderlap(left: 0, right: 0);

  /// How far the master reaches past the pane area's leading edge.
  final double left;

  /// How far the detail reaches past its trailing edge.
  final double right;

  double get horizontal => left + right;

  @override
  bool operator ==(Object other) =>
      other is PaneUnderlap && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'PaneUnderlap(left: $left, right: $right)';
}

/// The width arithmetic behind "one pane or two".
///
/// The layout is decided at build time, from `MediaQuery` and these functions,
/// never inside a `LayoutBuilder` — see `doc/design.md`. An app that decides
/// "is this the wide layout" with a formula of its own has to arrive at the
/// same number, which is why this is exported rather than kept inside the
/// shell.
abstract final class PaneMetrics {
  /// The system's own vertical bar on [placement]'s side, if there is one.
  ///
  /// This is the column iPhone Duo stands its status bar and Dynamic Island
  /// in, and on the outer display the camera sits at the end of it. The rail
  /// shares that column rather than taking one of its own — which is what the
  /// hardware asks for, the controls being aligned with the camera — so the
  /// two do not add up; see [railColumnWidth].
  ///
  /// It is the same one-sided inset [defaultChromeLayout] keys on, recognised
  /// the same way, which is why a notch — one-sided but narrower — and a
  /// landscape iPhone's symmetric pair both come back as zero. So does a bar
  /// on the side the rail is *not* on: there the panes bleed under it like any
  /// other inset.
  static double systemBarInset({
    required EdgeInsets padding,
    required ChromePlacement placement,
  }) {
    final (double own, double other) = switch (placement) {
      ChromePlacement.left => (padding.left, padding.right),
      ChromePlacement.right => (padding.right, padding.left),
      ChromePlacement.bottom => (0.0, 0.0),
    };
    return own >= kVerticalBarInset && other < kVerticalBarInset ? own : 0;
  }

  /// An inset on [placement]'s side wider than the opposite one that is not
  /// the system's vertical bar: Android's navigation buttons or a camera
  /// cutout in landscape. The rail grows by it ([railColumnWidth]).
  ///
  /// Symmetric insets count as zero: a landscape iPhone reports the Dynamic
  /// Island on both sides, so the rail would move over for nothing half the
  /// time.
  static double railCutoutInset({
    required EdgeInsets padding,
    required ChromePlacement placement,
  }) {
    if (systemBarInset(padding: padding, placement: placement) > 0) {
      return 0;
    }
    final (double own, double other) = switch (placement) {
      ChromePlacement.left => (padding.left, padding.right),
      ChromePlacement.right => (padding.right, padding.left),
      ChromePlacement.bottom => (0.0, 0.0),
    };
    return own > other + _symmetryTolerance ? own : 0;
  }

  /// How far apart the two side insets may be and still count as symmetric.
  static const double _symmetryTolerance = 2;

  /// Whether the window is wide enough for two panes at all: the rail's
  /// [kCompactWidthBreakpoint]. [MasterDetailConfig.fits] still has to agree.
  ///
  /// Otherwise, just under the breakpoint the bar hands the rail's width back
  /// to the panes and a second pane reappears as the window narrows.
  static bool allowsTwoPanes({
    required double window,
    required EdgeInsets padding,
  }) => window - padding.horizontal >= kCompactWidthBreakpoint;

  /// What the rail takes off the window: its own region, or the system's
  /// column where it joins one, plus a [cutout] on its edge.
  ///
  /// Joining one costs a little more than the region, because the rail is held
  /// off the edge to land on the line the system centres its glyphs on — see
  /// [SystemBarMetrics.edgeGap].
  static double railColumnWidth({
    required double railWidth,
    double systemBar = 0,
    double edgeGap = 0,
    double cutout = 0,
    RailDecoration rail = RailDecoration.none,
  }) => math.max(rail.regionWidth(railWidth) + edgeGap, systemBar) + cutout;

  /// What the rail's column leaves, before decoration and the insets the panes
  /// merely bleed under.
  static double contentWidth({
    required double window,
    required bool hasRail,
    required double railWidth,
    double systemBar = 0,
    double edgeGap = 0,
    double cutout = 0,
    RailDecoration rail = RailDecoration.none,
  }) =>
      window -
      (hasRail
          ? railColumnWidth(
              railWidth: railWidth,
              systemBar: systemBar,
              edgeGap: edgeGap,
              cutout: cutout,
              rail: rail,
            )
          : 0);

  /// The part of the horizontal insets the panes end up underneath.
  ///
  /// The rail absorbs the inset on *its own* side: it joins the system's own
  /// vertical bar there, which is exactly why [defaultChromeLayout] puts the
  /// rail there, or grows by a cutout ([railCutoutInset]). Either way the
  /// shell strips that inset from its subtree. On the other side nothing
  /// covers the inset, so the pane against it bleeds under.
  ///
  /// [PaneDecoration.margin] already holds the cards away from the edges, and
  /// that part of the width is accounted for as decoration; only what is left
  /// of the inset counts here, or it would be subtracted twice.
  static PaneUnderlap underlap({
    required EdgeInsets padding,
    required PaneDecoration panes,
    required ChromePlacement placement,
    bool hasChrome = true,
  }) {
    final bool rail = hasChrome && placement.isRail;
    // Where the rail is, the panes do not reach the edge at all. Everywhere
    // else the inset is theirs to bleed under — including a system vertical
    // bar on the side the rail did not go to, which is the arrangement on
    // iPhone Duo's inner display in landscape.
    final double left = rail && placement == ChromePlacement.left
        ? 0
        : math.max(0.0, padding.left - panes.margin.left);
    final double right = rail && placement == ChromePlacement.right
        ? 0
        : math.max(0.0, padding.right - panes.margin.right);
    return PaneUnderlap(left: left, right: right);
  }

  /// The width the panes are laid out into: the content area minus
  /// [PaneDecoration.margin] and minus whatever the panes only bleed under.
  ///
  /// This is the number that decides "one pane or two"
  /// ([MasterDetailConfig.fits]) and that the pane widths are computed from.
  ///
  /// [hasChrome] is `false` where the app hides the bar and the rail
  /// altogether; a hidden rail reserves no width and covers no inset.
  static double paneAreaWidth({
    required double window,
    required EdgeInsets padding,
    required ChromePlacement placement,
    required double railWidth,
    required PaneDecoration panes,
    RailDecoration rail = RailDecoration.none,
    SystemBarMetrics systemBarMetrics = SystemBarMetrics.measured,
    bool hasChrome = true,
  }) {
    final bool hasRail = hasChrome && placement.isRail;
    final double bar = hasRail
        ? systemBarInset(padding: padding, placement: placement)
        : 0;
    return math.max(
      0.0,
      panes.paneAreaWidth(
            contentWidth(
              window: window,
              hasRail: hasRail,
              railWidth: railWidth,
              systemBar: bar,
              edgeGap: bar > 0 ? systemBarMetrics.edgeGap(railWidth) : 0,
              cutout: hasRail
                  ? railCutoutInset(padding: padding, placement: placement)
                  : 0,
              rail: rail,
            ),
          ) -
          underlap(
            padding: padding,
            panes: panes,
            placement: placement,
            hasChrome: hasChrome,
          ).horizontal,
    );
  }
}
