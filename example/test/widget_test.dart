import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav_example/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The platform comes from a theme above the app, as in the playground.
  Future<void> pumpDuo(
    WidgetTester tester,
    Size size,
    FakeViewPadding Function(double dpr) padding,
  ) async {
    addTearDown(tester.view.reset);
    final double dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = size * dpr;
    tester.view.padding = padding(dpr);
    await tester.pumpWidget(
      Theme(
        data: ThemeData(platform: TargetPlatform.iOS),
        child: const ExampleApp(),
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

      // The master alone spans the display: 669 - 2 × 120 leaves room.
      expect(tester.getSize(people).width, 669);
      expect(reserve(people), 120);
      expect(centred(people), isTrue);

      await tester.tap(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();

      // Under the glyphs and too narrow to centre beside them.
      expect(tester.getSize(ada).width, 399);
      expect(reserve(ada), 120);
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

  testWidgets(
    'iPhone Duo in landscape: a drawer covers the status column filter',
    (WidgetTester tester) async {
      await pumpDuo(
        tester,
        const Size(951, 669),
        (double dpr) => FakeViewPadding(right: 84 * dpr, bottom: 34 * dpr),
      );

      await tester.tap(find.text('Starred'));
      await tester.pumpAndSettle();
      final Finder filter = find.byTooltip('Filters');
      // In the column below the glyphs, not in the header.
      expect(
        find.descendant(of: find.byType(AppBar), matching: filter),
        findsNothing,
      );
      final Offset centre = tester.getCenter(filter);
      expect(centre.dy, greaterThan(106));

      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      final HitTestResult result = tester.hitTestOnBinding(centre);
      bool hits(Finder finder) => result.path.any(
        (HitTestEntry entry) => entry.target == tester.renderObject(finder),
      );
      expect(hits(find.byType(DrawerController)), isTrue);
      expect(hits(filter), isFalse);
    },
  );
}
