import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nav_config.dart';

/// One screen in a branch stack.
@immutable
class NavEntry<R> {
  NavEntry({
    required this.route,
    required this.transition,
    this.onExit,
    this.completer,
    LocalKey? pageKey,
  }) : pageKey = pageKey ?? UniqueKey();

  final R route;
  final AppTransition transition;

  /// Asked before leaving this screen. `null` means no guard.
  final NavExitGuard? onExit;

  /// Completed by `popWithResult`, or with `null` on a plain pop.
  final Completer<Object?>? completer;

  /// Identity of the `Page` inside its `Navigator`. Not what preserves screen
  /// state on a rotation — that is the navigator's own key.
  final LocalKey pageKey;

  // Route and transition only, so that decode(encode(top)) == top holds.
  @override
  bool operator ==(Object other) =>
      other is NavEntry<R> &&
      other.route == route &&
      other.transition == transition;

  @override
  int get hashCode => Object.hash(route, transition);
}

/// One branch's stack, root first.
@immutable
class BranchStack<R> {
  const BranchStack(this.entries);

  final List<NavEntry<R>> entries;

  NavEntry<R> get root => entries.first;
  NavEntry<R> get top => entries.last;

  /// Whether anything sits above the root; in a wide layout, whether the
  /// detail pane has content.
  bool get hasDetail => entries.length > 1;

  BranchStack<R> push(NavEntry<R> entry) =>
      BranchStack<R>(<NavEntry<R>>[...entries, entry]);

  BranchStack<R> pop() => entries.length <= 1
      ? this
      : BranchStack<R>(entries.sublist(0, entries.length - 1));

  BranchStack<R> replaceTop(NavEntry<R> entry) => BranchStack<R>(<NavEntry<R>>[
    ...entries.sublist(0, entries.length - 1),
    entry,
  ]);

  BranchStack<R> resetToRoot() => BranchStack<R>(<NavEntry<R>>[entries.first]);

  @override
  bool operator ==(Object other) =>
      other is BranchStack<R> && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// The whole navigation state: the active branch plus every branch's stack.
@immutable
class NavState<R> {
  const NavState({required this.activeBranch, required this.branches});

  final int activeBranch;
  final List<BranchStack<R>> branches;

  BranchStack<R> get active => branches[activeBranch];

  NavState<R> copyWith({int? activeBranch, List<BranchStack<R>>? branches}) =>
      NavState<R>(
        activeBranch: activeBranch ?? this.activeBranch,
        branches: branches ?? this.branches,
      );

  NavState<R> withBranch(int index, BranchStack<R> stack) {
    final List<BranchStack<R>> next = List<BranchStack<R>>.of(branches);
    next[index] = stack;
    return copyWith(branches: next);
  }

  NavState<R> withActiveStack(BranchStack<R> stack) =>
      withBranch(activeBranch, stack);

  @override
  bool operator ==(Object other) =>
      other is NavState<R> &&
      other.activeBranch == activeBranch &&
      listEquals(other.branches, branches);

  @override
  int get hashCode => Object.hash(activeBranch, Object.hashAll(branches));
}
