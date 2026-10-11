import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav_example/main.dart';
import 'package:adaptive_nav_example/routes.dart';
import 'package:adaptive_nav_example/screens.dart';
import 'package:adaptive_nav_example/sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deep links as the platform delivers them: on `flutter/navigation`, as the
/// default route name at cold start, and `popRoute` for system back.
void main() {
  // A tap that lands on something else would otherwise pass in silence.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  /// Sends a location the way the engine does.
  Future<void> openLink(WidgetTester tester, String location) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', <String, dynamic>{
          'location': location,
          'state': null,
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester, Size window) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
  }

  AdaptiveNav<AppRoute> navOf(WidgetTester tester) =>
      tester.widget<AppScope>(find.byType(AppScope)).nav;

  /// A destination in the bar or the rail, whichever the window has.
  Future<void> tapBranch(WidgetTester tester, String label) async {
    final Finder chrome = find.byWidgetPredicate(
      (Widget w) => w is NavigationBar || w is NavigationRail,
    );
    await tester.tap(find.descendant(of: chrome, matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  Finder titled(String title) => find.widgetWithText(AppBar, title);

  /// Counts `SystemNavigator.pop`: the app handed back to the system.
  List<int> interceptSystemPop(WidgetTester tester) {
    final List<int> calls = <int>[0];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemNavigator.pop') {
          calls[0]++;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  /// Locations the router reported to the platform, oldest first.
  List<String> interceptReports(WidgetTester tester) {
    final List<String> reports = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (MethodCall call) async {
        if (call.method == 'routeInformationUpdated') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          reports.add((args['uri'] ?? args['location']).toString());
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
    return reports;
  }

  for (final (String name, Size window) in <(String, Size)>[
    ('phone', const Size(400, 800)),
    ('tablet', const Size(1200, 900)),
  ]) {
    final bool phone = window.width < 600;
    group(name, () {
      testWidgets('cold start on /people/3 opens person 3 in People', (
        WidgetTester tester,
      ) async {
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/people/3';
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );
        await pumpApp(tester, window);

        expect(navOf(tester).state.activeBranch, 0);
        expect(navOf(tester).state.active.top.route, const PersonDetail(3));
        expect(find.byType(PersonDetailScreen), findsOneWidget);
        expect(titled('Alan Turing'), findsOneWidget);
      });

      testWidgets('a warm link leaves the other branch stack alone', (
        WidgetTester tester,
      ) async {
        await pumpApp(tester, window);
        await tapBranch(tester, 'Teams');
        await tester.tap(find.text('Codebreakers'));
        await tester.pumpAndSettle();
        expect(titled('Codebreakers'), findsOneWidget);

        await openLink(tester, '/people/3');
        expect(navOf(tester).state.activeBranch, 0);
        expect(titled('Alan Turing'), findsOneWidget);
        expect(titled('Codebreakers'), findsNothing);

        if (phone) {
          // A full-screen detail covers the bar: the person is closed first.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(titled('People'), findsOneWidget);
        }
        await tapBranch(tester, 'Teams');
        expect(navOf(tester).state.active.top.route, const TeamDetail(2));
        expect(titled('Codebreakers'), findsOneWidget);
      });

      testWidgets('a repeated link to the open screen does not remount it', (
        WidgetTester tester,
      ) async {
        await pumpApp(tester, window);
        await openLink(tester, '/people/3');
        final Element first = tester.element(find.byType(PersonDetailScreen));
        final NavEntry<AppRoute> entry = navOf(tester).state.active.top;

        await openLink(tester, '/people/3');
        expect(find.byType(PersonDetailScreen), findsOneWidget);
        expect(tester.element(find.byType(PersonDetailScreen)), same(first));
        expect(navOf(tester).state.active.top, same(entry));
        expect(navOf(tester).state.active.entries, hasLength(2));
      });

      testWidgets(
        'a link to the branch root closes the detail, keeps the root',
        (WidgetTester tester) async {
          await pumpApp(tester, window);
          final Finder root = find.byType(
            PeopleListScreen,
            skipOffstage: false,
          );
          final Element before = tester.element(root);
          await openLink(tester, '/people/3');
          expect(find.byType(PersonDetailScreen), findsOneWidget);

          await openLink(tester, '/people');
          expect(navOf(tester).state.active.entries, hasLength(1));
          expect(find.byType(PersonDetailScreen), findsNothing);
          expect(tester.element(root), same(before));
        },
      );

      testWidgets('a link over the editor does not ask its guard', (
        WidgetTester tester,
      ) async {
        await pumpApp(tester, window);
        await tester.tap(find.text('Alan Turing'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit'));
        await tester.pumpAndSettle();
        expect(find.byType(PersonEditScreen), findsOneWidget);

        await openLink(tester, '/teams/2');
        // As the README describes: the editor is neither asked nor closed.
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(navOf(tester).state.activeBranch, 2);
        expect(navOf(tester).state.active.top.route, const TeamDetail(2));
        expect(titled('Codebreakers'), findsOneWidget);
        expect(navOf(tester).state.branches[0].top.route, const PersonEdit(3));
      });

      testWidgets('back after a link: team, Teams root, People, the system', (
        WidgetTester tester,
      ) async {
        final List<int> systemPops = interceptSystemPop(tester);
        await pumpApp(tester, window);
        await openLink(tester, '/teams/2');
        expect(titled('Codebreakers'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(navOf(tester).state.activeBranch, 2);
        expect(navOf(tester).state.active.entries, hasLength(1));
        expect(find.byType(TeamDetailScreen), findsNothing);
        expect(titled('Teams'), findsOneWidget);
        expect(systemPops.single, 0);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(navOf(tester).state.activeBranch, 0);
        expect(titled('People'), findsOneWidget);
        expect(systemPops.single, 0);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(systemPops.single, 1);
      });

      testWidgets('the reported URL follows a tap', (
        WidgetTester tester,
      ) async {
        final List<String> reports = interceptReports(tester);
        await pumpApp(tester, window);

        await tester.tap(find.text('Barbara Liskov'));
        await tester.pumpAndSettle();
        expect(titled('Barbara Liskov'), findsOneWidget);
        expect(reports, isNotEmpty);
        expect(reports.last, contains('/people/5'));
      });
    });
  }
}
