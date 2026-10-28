import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// System back belongs to the active branch. The inactive ones stay mounted,
/// and Android's predictive back used to close their top screens too: every
/// current route with the gesture enabled took it.
///
/// The scene: a detail in People (branch 0) with its counter at 1, Profile
/// pushed in Home (branch 1).
void main() {
  Future<DemoHarness> scene(
    WidgetTester tester,
    Size window, {
    required int active,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    addTearDown(tester.view.reset);
    setPose(tester, window);
    final DemoHarness h = DemoHarness(platform: platform);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.delegate.push(const DemoDetail(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inc')));
    await tester.pump();
    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    h.delegate.push(const DemoProfile());
    await tester.pumpAndSettle();
    if (active != 1) {
      await h.delegate.goBranch(active);
      await tester.pumpAndSettle();
    }
    return h;
  }

  ModalRoute<Object?> routeOf(WidgetTester tester, String text) =>
      ModalRoute.of(tester.element(find.text(text, skipOffstage: false)))!;

  ModalRoute<Object?> detailRoute(WidgetTester tester) =>
      routeOf(tester, 'Counter: 1');

  ModalRoute<Object?> profileRoute(WidgetTester tester) =>
      routeOf(tester, 'Profile');

  Future<void> send(
    WidgetTester tester,
    String method, [
    Map<String, Object?>? args,
  ]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (ByteData? _) {},
  );

  /// A swipe from the left edge; [button] — the back button, which Android
  /// sends with no touch.
  Map<String, Object?> event(double progress, {bool button = false}) =>
      <String, Object?>{
        'touchOffset': button ? null : <double>[5, 300],
        'progress': progress,
        'swipeEdge': 0,
      };

  /// No navigator left mid-gesture, and every route at rest.
  void settled(WidgetTester tester) {
    for (final Element e
        in find.byType(Navigator, skipOffstage: false).evaluate()) {
      final NavigatorState nav = (e as StatefulElement).state as NavigatorState;
      expect(nav.userGestureInProgress, isFalse);
    }
  }

  /// The other branch's screen is there, still the same one, and unmoved.
  void untouched(ModalRoute<Object?> route) {
    expect(route.isActive, isTrue);
    expect(route.isCurrent, isTrue);
    expect(route.animation!.value, 1);
    expect(route.navigator!.userGestureInProgress, isFalse);
  }

  /// Switches to People and finds the detail as it was left.
  Future<void> detailStillThere(WidgetTester tester, DemoHarness h) async {
    await h.delegate.goBranch(0);
    await tester.pumpAndSettle();
    expect(h.delegate.state.branches[0].entries, hasLength(2));
    expect(find.text('Counter: 1'), findsOneWidget);
  }

  for (final (String name, Size window) in <(String, Size)>[
    ('one pane', kCompact),
    ('two panes', kWide),
  ]) {
    group(name, () {
      group('Android', () {
        testWidgets('predictive back closes Profile, the detail stays', (
          WidgetTester tester,
        ) async {
          final DemoHarness h = await scene(tester, window, active: 1);
          final ModalRoute<Object?> detail = detailRoute(tester);
          final ModalRoute<Object?> profile = profileRoute(tester);

          await send(tester, 'startBackGesture', event(0));
          await tester.pump();
          await send(tester, 'updateBackGestureProgress', event(0.5));
          await tester.pump();
          expect(profile.navigator!.userGestureInProgress, isTrue);
          expect(profile.animation!.value, lessThan(1));
          untouched(detail);

          await send(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(h.delegate.state.branches[1].entries, hasLength(1));
          expect(h.delegate.state.branches[0].entries, hasLength(2));
          untouched(detail);
          settled(tester);
          await detailStillThere(tester, h);
        });

        testWidgets('a cancelled gesture leaves both', (
          WidgetTester tester,
        ) async {
          final DemoHarness h = await scene(tester, window, active: 1);
          final ModalRoute<Object?> detail = detailRoute(tester);
          final ModalRoute<Object?> profile = profileRoute(tester);

          await send(tester, 'startBackGesture', event(0));
          await tester.pump();
          await send(tester, 'updateBackGestureProgress', event(0.6));
          await tester.pump();
          untouched(detail);
          await send(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(h.delegate.state.branches[1].entries, hasLength(2));
          untouched(profile);
          untouched(detail);
          settled(tester);
          await detailStillThere(tester, h);
        });

        testWidgets('the back button closes Profile, the detail stays', (
          WidgetTester tester,
        ) async {
          final DemoHarness h = await scene(tester, window, active: 1);
          final ModalRoute<Object?> detail = detailRoute(tester);

          // Predictive back's button press: no route takes it, and the
          // framework hands it to the router as a plain back.
          await send(tester, 'startBackGesture', event(0, button: true));
          await send(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(h.delegate.state.branches[1].entries, hasLength(1));
          untouched(detail);

          // The plain one, from an Android without predictive back.
          h.delegate.push(const DemoProfile());
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(h.delegate.state.branches[1].entries, hasLength(1));
          untouched(detail);
          settled(tester);
          await detailStillThere(tester, h);
        });

        testWidgets('with People active the gesture closes the detail only', (
          WidgetTester tester,
        ) async {
          final DemoHarness h = await scene(tester, window, active: 0);
          final ModalRoute<Object?> profile = profileRoute(tester);

          await send(tester, 'startBackGesture', event(0));
          await tester.pump();
          await send(tester, 'updateBackGestureProgress', event(0.5));
          await tester.pump();
          untouched(profile);
          await send(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(h.delegate.state.branches[0].entries, hasLength(1));
          expect(h.delegate.state.branches[1].entries, hasLength(2));
          untouched(profile);
          settled(tester);
        });

        for (final (String end, String method) in <(String, String)>[
          ('committed', 'commitBackGesture'),
          ('cancelled', 'cancelBackGesture'),
        ]) {
          testWidgets('a tab switch mid-gesture, then $end: it ends where it '
              'began', (WidgetTester tester) async {
            final DemoHarness h = await scene(tester, window, active: 1);
            final ModalRoute<Object?> detail = detailRoute(tester);

            await send(tester, 'startBackGesture', event(0));
            await tester.pump();
            await send(tester, 'updateBackGestureProgress', event(0.4));
            await tester.pump();
            await h.delegate.goBranch(0);
            await tester.pump();
            // The detail was not in the gesture; switching to it does not
            // put it there.
            await send(tester, 'updateBackGestureProgress', event(0.7));
            await tester.pump();
            untouched(detail);
            await send(tester, method);
            await tester.pumpAndSettle();

            expect(h.delegate.state.activeBranch, 0);
            expect(h.delegate.state.branches[0].entries, hasLength(2));
            expect(
              h.delegate.state.branches[1].entries,
              hasLength(method == 'commitBackGesture' ? 1 : 2),
            );
            expect(find.text('Counter: 1'), findsOneWidget);
            settled(tester);

            // The next gesture goes to People.
            await send(tester, 'startBackGesture', event(0));
            await tester.pump();
            await send(tester, 'commitBackGesture');
            await tester.pumpAndSettle();
            expect(h.delegate.state.branches[0].entries, hasLength(1));
            settled(tester);
          });
        }

        testWidgets('a tab switch right after the gesture', (
          WidgetTester tester,
        ) async {
          final DemoHarness h = await scene(tester, window, active: 1);
          final ModalRoute<Object?> detail = detailRoute(tester);

          await send(tester, 'startBackGesture', event(0));
          await tester.pump();
          await send(tester, 'updateBackGestureProgress', event(0.5));
          await tester.pump();
          await send(tester, 'commitBackGesture');
          await tester.pump();
          await h.delegate.goBranch(0);
          await tester.pumpAndSettle();
          expect(h.delegate.state.branches[1].entries, hasLength(1));
          expect(h.delegate.state.branches[0].entries, hasLength(2));
          expect(find.text('Counter: 1'), findsOneWidget);
          untouched(detail);
          settled(tester);

          // And back to Home: Profile is gone, the root is at rest.
          await h.delegate.goBranch(1);
          await tester.pumpAndSettle();
          expect(find.text('Profile'), findsNothing);
          expect(find.text('Home: 0'), findsOneWidget);
          settled(tester);
        });
      });

      testWidgets('iOS: the edge swipe closes Profile, the detail stays', (
        WidgetTester tester,
      ) async {
        final DemoHarness h = await scene(
          tester,
          window,
          active: 1,
          platform: TargetPlatform.iOS,
        );
        final ModalRoute<Object?> detail = detailRoute(tester);
        final Rect screen = tester.getRect(
          find
              .ancestor(
                of: find.text('Profile'),
                matching: find.byType(Scaffold),
              )
              .first, // the screen's, not the shell's
        );

        final TestGesture swipe = await tester.startGesture(
          screen.centerLeft + const Offset(5, 0),
        );
        await swipe.moveBy(const Offset(20, 0));
        await swipe.moveBy(Offset(screen.width * 0.3, 0));
        await tester.pump();
        expect(profileRoute(tester).navigator!.userGestureInProgress, isTrue);
        untouched(detail);
        await swipe.moveBy(Offset(screen.width * 0.4, 0));
        await swipe.up();
        await tester.pumpAndSettle();
        expect(h.delegate.state.branches[1].entries, hasLength(1));
        untouched(detail);
        settled(tester);
        await detailStillThere(tester, h);
      });
    });
  }
}
