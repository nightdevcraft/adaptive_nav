import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav_example/main.dart';
import 'package:adaptive_nav_example/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The platform comes from a theme above the app, as in the playground.
  Future<void> pumpDuo(
    WidgetTester tester,
    Size size,
    FakeViewPadding Function(double dpr) padding, {
    int tabs = kTabs,
    SystemGeometry? system,
  }) async {
    addTearDown(tester.view.reset);
    final double dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = size * dpr;
    tester.view.padding = padding(dpr);
    await tester.pumpWidget(
      SystemGeometryScope(
        geometry: system,
        child: Theme(
          data: ThemeData(platform: TargetPlatform.iOS),
          child: ExampleApp(tabs: tabs),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the example starts on the people list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
  });

  testWidgets('system back from a team returns to Teams', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);

    await tester.tap(find.text('Compilers'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Compilers'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Teams'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Compilers'), findsNothing);
  });

  testWidgets(
    'iPhone Duo in portrait: a lifted title is centred where it fits',
    (WidgetTester tester) async {
      await pumpDuo(
        tester,
        const Size(669, 951),
        (double dpr) => FakeViewPadding(top: 82 * dpr, bottom: 34 * dpr),
      );

      final Finder people = find.widgetWithText(AppBar, 'People');
      final Finder ada = find.widgetWithText(AppBar, 'Ada Lovelace');
      double reserve(Finder bar) =>
          StatusRowScope.trailingReserveOf(tester.element(bar));
      bool? centred(Finder bar) => tester.widget<AppBar>(bar).centerTitle;

      // The master alone spans the display: 669 - 2 × 134 leaves room.
      expect(tester.getSize(people).width, 669);
      expect(reserve(people), 134);
      expect(centred(people), isTrue);

      await tester.tap(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();

      // Under the glyphs and too narrow to centre beside them.
      expect(tester.getSize(ada).width, 399);
      expect(reserve(ada), 134);
      expect(centred(ada), isFalse);

      // The master is clear of the glyphs, so the platform centres it.
      expect(tester.getSize(people).width, 270);
      expect(reserve(people), 0);
      expect(centred(people), isNull);
      final Rect bar = tester.getRect(people);
      expect(
        tester
            .getCenter(
              find.descendant(of: people, matching: find.text('People')),
            )
            .dx,
        moreOrLessEquals(bar.center.dx, epsilon: 1),
      );
    },
  );

  // The toolbars on the Duo's inner display in landscape: at the top of the
  // system's column, beside the detail or a tab's single pane, and the tabs
  // at its bottom, apart; the master keeps its header.
  group('iPhone Duo in landscape: the toolbar in the system\'s column', () {
    Finder inHeader(Finder matching) =>
        find.descendant(of: find.byType(AppBar), matching: matching);

    Future<void> pumpLandscape(WidgetTester tester, {int tabs = kTabs}) =>
        pumpDuo(
          tester,
          const Size(951, 669),
          (double dpr) => FakeViewPadding(right: 84 * dpr, bottom: 34 * dpr),
          tabs: tabs,
        );

    testWidgets('a person: Close and Edit above the tabs', (
      WidgetTester tester,
    ) async {
      await pumpLandscape(tester);
      await tester.tap(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();

      final Rect people = tester.getRect(
        find.byTooltip('People').hitTestable(),
      );
      expect(people.center.dx, 951 - 48);
      final Rect close = tester.getRect(find.byTooltip('Close'));
      final Rect edit = tester.getRect(find.byTooltip('Edit'));
      expect(close.center.dx, 951 - 48);
      expect(edit.top, greaterThanOrEqualTo(close.bottom));
      expect(people.top, greaterThanOrEqualTo(edit.bottom));
      expect(inHeader(find.byTooltip('Edit')), findsNothing);
      expect(inHeader(find.byIcon(Icons.close)), findsNothing);
    });

    testWidgets('Starred: the filter', (WidgetTester tester) async {
      await pumpLandscape(tester);
      await tester.tap(find.byTooltip('Starred'));
      await tester.pumpAndSettle();

      expect(tester.getCenter(find.byTooltip('Filters')).dx, 951 - 48);
      expect(inHeader(find.byTooltip('Filters')), findsNothing);
    });

    testWidgets('Trash: Empty has an icon, so it moves too', (
      WidgetTester tester,
    ) async {
      await pumpLandscape(tester);
      // All seven tabs have a place beside the detail.
      expect(find.byIcon(Icons.apps), findsNothing);
      await tester.tap(find.byTooltip('Trash'));
      await tester.pumpAndSettle();

      expect(tester.getCenter(find.byTooltip('Empty')).dx, 951 - 48);
      expect(inHeader(find.byTooltip('Empty')), findsNothing);
    });

    testWidgets('ten tabs: Files and Tags behind More', (
      WidgetTester tester,
    ) async {
      await pumpLandscape(tester, tabs: 10);
      // Nine places: eight tabs and More.
      expect(find.byTooltip('Calendar'), findsOneWidget);
      expect(find.byTooltip('Files'), findsNothing);
      await tester.tap(find.byIcon(Icons.apps));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Tags'), findsOneWidget);
    });
  });

  // The outer display turned left, as in the screenshot that started it: a
  // short column, where seven tabs leave a screen with a button no room. The
  // status area as adaptive_nav_ios reports it on the simulator.
  group('iPhone Duo, outer display in landscape', () {
    Future<void> pumpOuter(WidgetTester tester, {int tabs = kTabs}) => pumpDuo(
      tester,
      const Size(678, 466),
      (double dpr) => FakeViewPadding(left: 84 * dpr, bottom: 34 * dpr),
      tabs: tabs,
      system: const SystemGeometry(
        verticalBar: ChromePlacement.left,
        statusArea: Rect.fromLTRB(0, 0, 84, 82),
      ),
    );

    testWidgets('People keeps no room for a toolbar it does not have', (
      WidgetTester tester,
    ) async {
      await pumpOuter(tester);
      // 336 between the column's ends: five tabs and More, 6 apart.
      for (final String tab in <String>[
        'People',
        'Settings',
        'Teams',
        'Starred',
        'Recent',
      ]) {
        expect(find.byTooltip(tab).hitTestable(), findsOneWidget);
      }
      expect(find.byIcon(Icons.apps), findsOneWidget);
    });

    testWidgets('Starred folds the tabs to itself and More for Filters, and '
        'People unfolds them', (WidgetTester tester) async {
      await pumpOuter(tester);
      final Rect people = tester.getRect(
        find.byTooltip('People').hitTestable(),
      );
      final Rect more = tester.getRect(find.byIcon(Icons.apps).hitTestable());
      await tester.tap(find.byTooltip('Starred'));
      await tester.pumpAndSettle();

      expect(tester.getCenter(find.byTooltip('Filters')).dx, 48);
      expect(find.byTooltip('People').hitTestable(), findsNothing);
      // Two buttons at the bottom: Starred, above More, which has not moved
      // and has a menu of every tab.
      expect(tester.getRect(find.byIcon(Icons.apps).hitTestable()), more);
      expect(
        tester.getCenter(find.byTooltip('Starred').hitTestable()).dy,
        tester.getCenter(find.byIcon(Icons.apps)).dy - 48 - 6,
      );
      await tester.tap(find.byIcon(Icons.apps));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(kTabs));
      await tester.tap(find.widgetWithText(MenuItemButton, 'People'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Filters'), findsNothing);
      expect(tester.getRect(find.byTooltip('People').hitTestable()), people);
    });

    testWidgets('three tabs leave Starred room: nothing folds', (
      WidgetTester tester,
    ) async {
      await pumpOuter(tester, tabs: 3);
      final Rect people = tester.getRect(
        find.byTooltip('People').hitTestable(),
      );
      await tester.tap(find.byTooltip('Teams'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.apps), findsNothing);
      expect(tester.getRect(find.byTooltip('People').hitTestable()), people);
    });
  });

  group('another number of tabs', () {
    testWidgets('keeps every tab that stays where it was', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      final GlobalKey app = GlobalKey();
      await tester.pumpWidget(ExampleApp(key: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compilers'));
      await tester.pumpAndSettle();

      // Three: People, Settings, Teams — Teams still on Compilers.
      await tester.pumpWidget(ExampleApp(key: app, tabs: 3));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Compilers'), findsOneWidget);
      expect(find.text('Starred'), findsNothing);
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Ada Lovelace'), findsOneWidget);

      // Ten: the new ones at their roots, the old ones as they were.
      await tester.tap(find.text('Teams'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(ExampleApp(key: app, tabs: 10));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Compilers'), findsOneWidget);
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Tags'), findsOneWidget);

      // Two: Tags goes, and People takes over.
      await tester.pumpWidget(ExampleApp(key: app, tabs: 2));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Ada Lovelace'), findsOneWidget);
      expect(find.text('Teams'), findsNothing);
    });

    test('a link to a section the app does not have opens People', () {
      const AppRouteCodec codec = AppRouteCodec(sections: <String>['teams']);
      expect(codec.decode(Uri.parse('/trash')), const PeopleList());
      expect(codec.decode(Uri.parse('/teams/1')), const TeamDetail(1));
      expect(codec.branchOf(const TeamDetail(1)), 2);
    });
  });
}
