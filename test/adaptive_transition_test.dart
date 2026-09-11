import 'dart:async';

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav/src/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// `AppTransition.adaptive` picks its transition while the animation runs:
/// a fade in a pane, the platform slide full screen, and the dismissal
/// follows whatever the layout is by then.
///
/// The platform is forced to iOS, where the platform transition is a
/// horizontal slide. On Android the zoom transition changes opacity too, and
/// there would be nothing to tell the two apart by.
void main() {
  /// Set through the test variant rather than by hand: the framework clears
  /// the override after the test body (otherwise the "debug variable not
  /// restored" assertion fires).
  final TargetPlatformVariant ios = TargetPlatformVariant.only(
    TargetPlatform.iOS,
  );

  /// The fade drawn by the detail PAGE itself (the wrapper between the stack
  /// of detail navigators and the screen). A screen's tooltips and overlays
  /// live in the root overlay and never reach here.
  Iterable<FadeTransition> paneFades(WidgetTester tester, Finder screen) =>
      tester.widgetList<FadeTransition>(
        find.ancestor(
          of: screen,
          matching: find.descendant(
            of: find.byKey(AdaptiveShell.detailsStackKey),
            matching: find.byType(FadeTransition),
          ),
        ),
      );

  /// A detail two deep (`[list, card, editor]`) at width [size]: the transition
  /// is visible when the TOP screen closes, and the detail does not empty out —
  /// the pane neither collapses nor spoils the geometry with its reveal.
  Future<DemoHarness> openEdit(WidgetTester tester, Size size) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, size);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    unawaited(
      harness.delegate.push(
        const DemoDetail(1),
        transition: AppTransition.adaptive,
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      harness.delegate.push(
        const DemoEdit(1),
        transition: AppTransition.adaptive,
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('opened wide, closed compact: platform slide', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = await openEdit(tester, kWide);

    setWindow(tester, kCompact);
    await tester.pumpAndSettle();
    final double rest = tester.getTopLeft(find.byType(DemoEditScreen)).dx;

    await harness.delegate.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // It moves sideways, so this is a slide rather than a fade in place.
    expect(
      tester.getTopLeft(find.byType(DemoEditScreen)).dx,
      greaterThan(rest + 50),
    );
    expect(paneFades(tester, find.byType(DemoEditScreen)), isEmpty);

    await tester.pumpAndSettle();
    expect(find.byType(DemoEditScreen), findsNothing);
    expect(find.byType(DemoDetailScreen), findsOneWidget);
  }, variant: ios);

  testWidgets('opened compact, closed wide: fade in the pane', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = await openEdit(tester, kCompact);

    setWindow(tester, kWide);
    await tester.pumpAndSettle();
    final Offset rest = tester.getTopLeft(find.byType(DemoEditScreen));

    await harness.delegate.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.getTopLeft(find.byType(DemoEditScreen)), rest);
    final Iterable<FadeTransition> fades = paneFades(
      tester,
      find.byType(DemoEditScreen),
    );
    expect(fades, hasLength(1));
    expect(fades.single.opacity.value, inExclusiveRange(0.0, 1.0));

    await tester.pumpAndSettle();
    expect(find.byType(DemoEditScreen), findsNothing);
  }, variant: ios);

  testWidgets('wide: going deeper does not push the screen below away', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    unawaited(
      harness.delegate.push(
        const DemoDetail(1),
        transition: AppTransition.adaptive,
      ),
    );
    await tester.pumpAndSettle();
    final Offset card = tester.getTopLeft(find.byType(DemoDetailScreen));

    unawaited(
      harness.delegate.push(
        const DemoEdit(1),
        transition: AppTransition.adaptive,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The card under the editor stays drawn and STILL — the arriving screen
    // fades in over it, with no flash of the background.
    expect(find.byType(DemoDetailScreen), findsOneWidget);
    expect(tester.getTopLeft(find.byType(DemoDetailScreen)), card);
    expect(tester.getTopLeft(find.byType(DemoEditScreen)).dx, card.dx);
  }, variant: ios);

  testWidgets('resize with an open detail does not remount the screen', (
    WidgetTester tester,
  ) async {
    final DemoHarness harness = DemoHarness();
    setWindow(tester, kWide);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    unawaited(
      harness.delegate.push(
        const DemoDetail(1),
        transition: AppTransition.adaptive,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.pump();
    expect(find.text('Counter: 2'), findsOneWidget);

    // The `Page` type does not depend on the layout, so `Navigator.canUpdate`
    // updates the route instead of recreating it: the detail state survives.
    setWindow(tester, kCompact);
    await tester.pumpAndSettle();
    expect(find.text('Counter: 2'), findsOneWidget);

    setWindow(tester, kWide);
    await tester.pumpAndSettle();
    expect(find.text('Counter: 2'), findsOneWidget);
  }, variant: ios);
}
