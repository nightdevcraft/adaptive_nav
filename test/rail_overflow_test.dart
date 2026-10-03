import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// More destinations than the rail's column can hold.
///
/// Material's `NavigationRail` lays its destinations into a plain `Column`: it
/// neither scrolls nor overflows into a menu, so past the column's height it
/// simply overflows. The shell counts them instead — arithmetically, because a
/// `LayoutBuilder` around the rail is the one place `doc/design.md` warns
/// about — and puts the rest behind a button at the end.
void main() {
  /// Collects framework errors raised while [body] runs, so a `RenderFlex`
  /// overflow is a value rather than a thrown test failure.
  Future<List<String>> errorsDuring(Future<void> Function() body) async {
    final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
    final List<String> errors = <String>[];
    FlutterError.onError = (FlutterErrorDetails d) =>
        errors.add(d.exception.toString().split('\n').first);
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  // The two numbers the shell's arithmetic is built on: a one-line
  // destination is 64 and a two-line one is 80. Material can change them;
  // this is where that would be noticed.
  testWidgets('a destination is 64 on one line and 80 on two', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setWindow(tester, const Size(400, 2000));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              SizedBox(
                width: kDefaultRailWidth,
                child: NavigationRail(
                  selectedIndex: 0,
                  labelType: NavigationRailLabelType.all,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.circle),
                      label: Text('A'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.circle),
                      label: Text('B'),
                    ),
                  ],
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double step() =>
        tester.getRect(find.byIcon(Icons.circle).at(1)).top -
        tester.getRect(find.byIcon(Icons.circle).at(0)).top;
    expect(step(), kRailDestinationBase + 16, reason: 'one line');

    // A label too wide for the rail takes a second, and every destination
    // grows with it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              SizedBox(
                width: kDefaultRailWidth,
                child: NavigationRail(
                  selectedIndex: 0,
                  labelType: NavigationRailLabelType.all,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.circle),
                      label: Text('A very long label'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.circle),
                      label: Text('B'),
                    ),
                  ],
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(step(), greaterThan(kRailDestinationBase + 16));
  });

  group('the column is counted, not measured', () {
    // A folded iPhone Duo: a short column whose top the system bar takes.
    testWidgets('a folded Duo holds seven, and hides the rest', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
      final DemoHarness h = DemoHarness(extraBranches: 10);
      final List<String> errors = await errorsDuring(() async {
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty, reason: 'the rail must never overflow');
      expect(find.byKey(AdaptiveShell.railOverflowKey), findsOneWidget);
      expect(find.byType(NavigationRailDestination), findsNothing);
      // 678 tall, less the bar's 150 of reserve, 34 of home indicator, the
      // rail's 8 spacer and the button's 56: 430 of column. The harness's
      // labels wrap, so a destination is 80 and five of them fit.
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
        hasLength(5),
      );
    });

    testWidgets('a desktop window holds them all, with no button', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, const Size(1200, 1200));
      final DemoHarness h = DemoHarness(extraBranches: 10);
      final List<String> errors = await errorsDuring(() async {
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty);
      expect(find.byKey(AdaptiveShell.railOverflowKey), findsNothing);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
        hasLength(12),
      );
    });

    // Material lays every destination out on its own, so one long label is one
    // tall destination and not twelve. Counting them all at the tallest sent
    // the last one to the menu with a destination's worth of column to spare.
    testWidgets('a short label is counted short, not as the tallest', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
      // The same 430 of column as above, and the same "People" wrapping to two
      // lines — but the extras are one-line now, so it is 80 + 5 × 64 = 400
      // that fits rather than five destinations of 80.
      final DemoHarness h = DemoHarness(
        extraBranches: 10,
        extraLabel: (int i) => 'E$i',
      );
      final List<String> errors = await errorsDuring(() async {
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty, reason: 'the rail must never overflow');
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
        hasLength(6),
      );
    });

    // The arithmetic has to hold at every height, not just the two above: one
    // spacer forgotten and the rail overflows by exactly that. Both label sets
    // run it, because a sum of per-destination heights is the thing that has
    // to be right now, not one height times a count.
    testWidgets('no height overflows, at any count', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      for (final double height in <double>[400, 500, 678, 700, 951, 1200]) {
        for (final int extra in <int>[0, 3, 10, 30]) {
          for (final bool short in <bool>[false, true]) {
            setWindow(tester, Size(900, height));
            final DemoHarness h = DemoHarness(
              extraBranches: extra,
              extraLabel: short ? (int i) => 'E$i' : null,
            );
            final List<String> errors = await errorsDuring(() async {
              await tester.pumpWidget(h.app());
              await tester.pumpAndSettle();
            });
            expect(
              errors,
              isEmpty,
              reason:
                  'height $height with ${extra + 2} destinations, '
                  '${short ? 'short' : 'wrapping'} labels',
            );
          }
        }
      }
    });
  });

  group('the button carries what the column cannot', () {
    testWidgets('it opens a menu of the hidden destinations', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
      final DemoHarness h = DemoHarness(extraBranches: 10);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      expect(find.text('Extra 9'), findsNothing);
      await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
      await tester.pumpAndSettle();
      expect(find.text('Extra 9'), findsOneWidget);
    });

    testWidgets('choosing one switches to it', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
      final DemoHarness h = DemoHarness(extraBranches: 10);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AdaptiveShell.railOverflowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extra 9'));
      await tester.pumpAndSettle();

      expect(h.delegate.state.activeBranch, 11);
    });

    // The order never changes as you navigate: a destination that jumps into
    // view is harder to track than one that stays where it was.
    testWidgets('an active hidden branch does not jump into the rail', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
      final DemoHarness h = DemoHarness(extraBranches: 10);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();

      List<String> labels() => tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .destinations
          .map((NavigationRailDestination d) => (d.label as Text).data!)
          .toList();
      final List<String> before = labels();

      h.delegate.goBranch(11);
      await tester.pumpAndSettle();

      expect(labels(), before);
      final NavigationRail rail = tester.widget<NavigationRail>(
        find.byType(NavigationRail),
      );
      // Nothing in the rail is selected; the button holds the selection.
      expect(rail.selectedIndex, isNull);
    });
  });

  // The button is the app's to draw; which destinations it carries and how
  // much room it gets are not, because the count depends on both.
  testWidgets('railOverflowBuilder draws the button instead', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
    bool? sawActive;
    final DemoHarness h = DemoHarness(
      extraBranches: 10,
      railOverflowBuilder:
          (
            BuildContext context,
            List<int> hidden,
            ValueChanged<int> onSelectBranch,
            bool active,
          ) {
            sawActive = active;
            return TextButton(
              key: const ValueKey<String>('mine'),
              onPressed: () => onSelectBranch(hidden.last),
              child: Text('+${hidden.length}'),
            );
          },
    );
    final List<String> errors = await errorsDuring(() async {
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
    });

    expect(errors, isEmpty, reason: 'the slot is the same height either way');
    expect(find.byKey(AdaptiveShell.railOverflowKey), findsNothing);
    // Five destinations of the twelve are in the rail; the rest are the
    // button's.
    expect(find.text('+7'), findsOneWidget);
    expect(sawActive, isFalse, reason: 'the active branch is in the rail');

    await tester.tap(find.byKey(const ValueKey<String>('mine')));
    await tester.pumpAndSettle();

    expect(h.delegate.state.activeBranch, 11);
    expect(sawActive, isTrue, reason: 'now it is one of the hidden ones');
  });

  testWidgets('railOverflow: false lets Material do what it does', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    setPose(tester, kDuoOuterPortrait, padding: kDuoOuterPortraitPadding);
    final DemoHarness h = DemoHarness(extraBranches: 10, railOverflow: false);
    final List<String> errors = await errorsDuring(() async {
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
    });

    expect(find.byKey(AdaptiveShell.railOverflowKey), findsNothing);
    expect(errors, isNotEmpty);
    expect(errors.first, contains('overflowed'));
  });
}
