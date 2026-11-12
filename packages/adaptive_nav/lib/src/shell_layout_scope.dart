/// @docImport 'entry_page.dart';
library;

import 'package:flutter/widgets.dart';

import 'nav_config.dart';

/// The pane a branch navigator fills.
enum ShellPane {
  /// The only pane: the compact layout, a branch without
  /// [BranchConfig.masterDetail], or one whose panes do not fit side by side.
  /// The branch's detail, if any, covers the master here.
  single,

  /// The master pane of two side by side.
  master,

  /// The detail pane of two side by side.
  detail,
}

/// The layout the shell built around a branch navigator: where the chrome is,
/// which pane the navigator fills, and whether the branch's detail has a pane
/// of its own.
///
/// The shell puts one above every branch navigator — master, detail, and
/// those of inactive branches, each with its own values — so a screen reads
/// the decision the shell made rather than recomputing it from `MediaQuery`
/// and disagreeing at the boundary. A resize, a rotation or a branch switch
/// rebuilds only the widgets that depend on it; the navigators and their
/// screens stay.
///
/// A screen deciding where to open its own detail — beside it in the second
/// pane, or in a bottom sheet over the single one:
///
/// ```dart
/// void openFilters(BuildContext context) {
///   if (ShellLayoutScope.of(context).detailInOwnPane) {
///     nav.push(const FiltersRoute()); // lands in the detail pane
///   } else {
///     showModalBottomSheet<void>(
///       context: context,
///       builder: (BuildContext context) => const FiltersSheet(),
///     );
///   }
/// }
/// ```
class ShellLayoutScope extends InheritedWidget {
  const ShellLayoutScope({
    required this.placement,
    required this.pane,
    required this.detailInOwnPane,
    required super.child,
    super.key,
  });

  /// Where the chrome is: the bottom bar, or a rail against the left or the
  /// right edge. It is the placement the layout is built for even where the
  /// chrome itself is hidden.
  final ChromePlacement placement;

  /// The pane this navigator fills.
  ///
  /// With one pane both navigators of the branch get [ShellPane.single]: the
  /// master's and the detail's that covers it. Whether a screen is the detail
  /// is [DetailPaneScope]'s to say.
  final ShellPane pane;

  /// Whether the detail of this navigator's branch is shown in a pane of its
  /// own, beside the master: the same [MasterDetailConfig.fits] the shell lays
  /// the panes out by. `false` for [ShellPane.single] and for a branch without
  /// [BranchConfig.masterDetail].
  final bool detailInOwnPane;

  /// The nearest scope. Asserts there is one: only screens in the shell's
  /// navigators have it.
  static ShellLayoutScope of(BuildContext context) {
    final ShellLayoutScope? scope = maybeOf(context);
    assert(
      scope != null,
      'No ShellLayoutScope above this context: it is not in a branch '
      'navigator of the adaptive shell.',
    );
    return scope!;
  }

  /// The nearest scope, or `null` outside the shell's navigators.
  static ShellLayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellLayoutScope>();

  @override
  bool updateShouldNotify(ShellLayoutScope oldWidget) =>
      oldWidget.placement != placement ||
      oldWidget.pane != pane ||
      oldWidget.detailInOwnPane != detailInOwnPane;
}
