import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'nav_config.dart';
import 'nav_state.dart';

/// `URL ↔ NavState` for deep links and cold start.
///
/// The `R ↔ path` codec comes from the app; [baseState] is the default state
/// the decoded route is placed on top of. The round trip is defined on the
/// visible location, the top of the active branch: one URL encodes the current
/// screen, and a deep link opens it rather than synthesising a back stack for
/// it.
class AdaptiveRouteInformationParser<R>
    extends RouteInformationParser<NavState<R>> {
  AdaptiveRouteInformationParser({
    required this.codec,
    required this.baseState,
  });

  final RouteCodec<R> codec;
  final NavState<R> baseState;

  @override
  Future<NavState<R>> parseRouteInformation(RouteInformation routeInformation) {
    return SynchronousFuture<NavState<R>>(
      _locate(codec.decode(routeInformation.uri)),
    );
  }

  @override
  RouteInformation? restoreRouteInformation(NavState<R> configuration) {
    return RouteInformation(uri: codec.encode(configuration.active.top.route));
  }

  NavState<R> _locate(R route) {
    final int branch = codec
        .branchOf(route)
        .clamp(0, baseState.branches.length - 1)
        .toInt();
    final BranchStack<R> base = baseState.branches[branch];
    if (route == base.root.route) {
      return baseState
          .copyWith(activeBranch: branch)
          .withBranch(branch, base.resetToRoot());
    }
    final NavEntry<R> entry = NavEntry<R>(
      route: route,
      transition: AppTransition.platform,
    );
    return baseState
        .copyWith(activeBranch: branch)
        .withBranch(branch, BranchStack<R>(<NavEntry<R>>[base.root, entry]));
  }
}
