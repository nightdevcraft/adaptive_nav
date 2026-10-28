import 'dart:async';

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';

/// A mutation that waits on a gate applies to the stack as it is when the gate
/// answers, not to the copy it took before asking.
void main() {
  /// Each call to the guard is one dialog the test answers later.
  final List<Completer<bool>> dialogs = <Completer<bool>>[];
  Future<bool> dialog() {
    final Completer<bool> c = Completer<bool>();
    dialogs.add(c);
    return c.future;
  }

  setUp(dialogs.clear);

  List<DemoRoute> routes(BranchStack<DemoRoute> stack) => <DemoRoute>[
    for (final NavEntry<DemoRoute> e in stack.entries) e.route,
  ];

  /// What each gated operation leaves of `[List, Detail 1]` with `Detail 9`
  /// pushed after it was called.
  final Map<String, (Future<void> Function(DemoHarness h), List<DemoRoute>)>
  operations = <String, (Future<void> Function(DemoHarness), List<DemoRoute>)>{
    'pop': (
      (DemoHarness h) => h.delegate.pop(),
      <DemoRoute>[const DemoList(), const DemoDetail(9)],
    ),
    'replace': (
      (DemoHarness h) => h.delegate.replace(const DemoEdit(1)),
      <DemoRoute>[const DemoList(), const DemoEdit(1), const DemoDetail(9)],
    ),
    'resetTo': (
      (DemoHarness h) => h.delegate.resetTo(const DemoEdit(1)),
      <DemoRoute>[const DemoEdit(1), const DemoDetail(9)],
    ),
    'popToRoot': (
      (DemoHarness h) => h.delegate.popToRoot(),
      <DemoRoute>[const DemoList(), const DemoDetail(9)],
    ),
    'resetDetailTo': (
      (DemoHarness h) => h.delegate.resetDetailTo(const DemoDetail(2)),
      <DemoRoute>[const DemoList(), const DemoDetail(2), const DemoDetail(9)],
    ),
  };

  for (final MapEntry<
        String,
        (Future<void> Function(DemoHarness), List<DemoRoute>)
      >
      op
      in operations.entries) {
    final String name = op.key;
    final (Future<void> Function(DemoHarness) run, List<DemoRoute> expected) =
        op.value;

    group(name, () {
      test('without a guard it applies at once; a push after it stays', () {
        final DemoHarness h = DemoHarness();
        h.delegate.push(const DemoDetail(1));

        unawaited(run(h));
        bool done = false;
        h.delegate.push(const DemoDetail(9)).then((_) => done = true);

        expect(routes(h.delegate.state.active), expected);
        return Future<void>.delayed(Duration.zero, () {
          expect(routes(h.delegate.state.active), expected);
          expect(done, isFalse); // still on screen, so still pending
        });
      });

      test('a push while the guard is asked survives the answer', () async {
        final DemoHarness h = DemoHarness();
        h.delegate.push(const DemoDetail(1), onExit: dialog);

        final Future<void> pending = run(h);
        bool done = false;
        h.delegate.push(const DemoDetail(9)).then((_) => done = true);
        dialogs.single.complete(true);
        await pending;
        await Future<void>.delayed(Duration.zero);

        expect(routes(h.delegate.state.active), expected);
        expect(done, isFalse);
      });

      for (final String switcher in <String>['goBranch', 'setNewRoutePath']) {
        test('a $switcher while the guard is asked leaves the other '
            'branch alone', () async {
          final DemoHarness h = DemoHarness();
          await h.delegate.goBranch(1);
          h.delegate.push(const DemoHome());
          await h.delegate.goBranch(0);
          h.delegate.push(const DemoDetail(1), onExit: dialog);

          final Future<void> pending = run(h);
          if (switcher == 'goBranch') {
            // Leaving the tab asks the same screen again.
            final Future<void> switching = h.delegate.goBranch(1);
            dialogs.last.complete(true);
            await switching;
          } else {
            await h.delegate.setNewRoutePath(
              await h.parser.parseRouteInformation(
                RouteInformation(uri: Uri.parse('/home')),
              ),
            );
          }
          expect(h.delegate.state.activeBranch, 1);
          // As the switch left it; the answer below must not touch it.
          final BranchStack<DemoRoute> home = h.delegate.state.branches[1];
          dialogs.first.complete(true);
          await pending;

          expect(h.delegate.state.branches[1], same(home));
        });
      }
    });
  }

  test(
    'a pop whose entry went while the guard was asked does nothing',
    () async {
      final DemoHarness h = DemoHarness();
      h.delegate.push(const DemoDetail(1), onExit: dialog);

      final Future<bool> pending = h.delegate.pop();
      h.delegate.popWithResult<Object?>(null);
      h.delegate.push(const DemoDetail(2));
      dialogs.single.complete(true);

      expect(await pending, isFalse);
      expect(routes(h.delegate.state.active), <DemoRoute>[
        const DemoList(),
        const DemoDetail(2),
      ]);
    },
  );

  test('a guard that throws counts as a refusal', () async {
    final List<FlutterErrorDetails> reported = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    final DemoHarness h = DemoHarness();
    h.delegate.push(
      const DemoDetail(1),
      onExit: () async => throw StateError('broken guard'),
    );

    expect(await h.delegate.pop(), isFalse);
    expect(h.delegate.state.active.top.route, const DemoDetail(1));
    expect(reported.single.exception, isA<StateError>());
  });

  test('an answer that arrives after dispose is dropped', () async {
    final DemoHarness h = DemoHarness();
    h.delegate.push(const DemoDetail(1), onExit: dialog);

    final Future<bool> pending = h.delegate.pop();
    h.delegate.dispose();
    dialogs.single.complete(true);

    expect(await pending, isFalse);
  });

  test('dispose completes pending pushes with null', () async {
    final DemoHarness h = DemoHarness();
    final Future<Object?> detail = h.delegate.push(const DemoDetail(1));
    await h.delegate.goBranch(1);
    final Future<Object?> home = h.delegate.push(const DemoHome());

    h.delegate.dispose();

    expect(await detail.timeout(const Duration(seconds: 1)), isNull);
    expect(await home.timeout(const Duration(seconds: 1)), isNull);
  });

  test('a push after dispose asserts', () {
    final DemoHarness h = DemoHarness();
    h.delegate.dispose();
    expect(() => h.delegate.push(const DemoDetail(1)), throwsAssertionError);
  });

  test('goBranch out of range throws', () {
    final DemoHarness h = DemoHarness();
    expect(() => h.delegate.goBranch(2), throwsArgumentError);
    expect(() => h.delegate.goBranch(-1), throwsArgumentError);
    expect(h.delegate.state.activeBranch, 0);
  });

  test('mountedBranches cannot be changed from outside', () {
    final DemoHarness h = DemoHarness();
    expect(() => h.delegate.mountedBranches.add(1), throwsUnsupportedError);
  });
}
