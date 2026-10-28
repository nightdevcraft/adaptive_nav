import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/back_log.dart';
import '_harness/demo_app.dart';
import '_harness/resize.dart';

/// A screen's own `PopScope` decides about system back; the package's one is
/// invoked too and must not remove an unguarded entry.
void main() {
  for (final (String name, Size window) in <(String, Size)>[
    ('compact', kCompact),
    ('wide', kWide),
  ]) {
    group(name, () {
      testWidgets('a screen PopScope holds back', (WidgetTester tester) async {
        int invoked = 0;
        final DemoHarness h = DemoHarness(
          wrapPage: (DemoRoute route, Widget screen) => route is DemoDetail
              ? PopScope<Object?>(
                  canPop: false,
                  onPopInvokedWithResult: (bool didPop, Object? _) {
                    if (!didPop) {
                      invoked++;
                    }
                  },
                  child: screen,
                )
              : screen,
        );
        await pumpBackLog(tester, h, window);

        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        expect(find.text('Detail 1'), findsOneWidget);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Detail 1'), findsOneWidget);
        expect(h.delegate.state.active.entries, hasLength(2));
        expect(invoked, 1);
      });

      testWidgets('README drawer workaround on a pushed screen', (
        WidgetTester tester,
      ) async {
        final GlobalKey<ScaffoldState> drawerScaffold =
            GlobalKey<ScaffoldState>();
        final DemoHarness h = DemoHarness(
          wrapPage: (DemoRoute route, Widget screen) => route is DemoDetail
              ? _DrawerScreen(scaffoldKey: drawerScaffold, title: 'Inbox')
              : screen,
        );
        await pumpBackLog(tester, h, window);

        h.delegate.push(const DemoDetail(1));
        await tester.pumpAndSettle();
        drawerScaffold.currentState!.openDrawer();
        await tester.pumpAndSettle();
        expect(find.text('Filters'), findsOneWidget);

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Filters'), findsNothing);
        expect(find.text('Inbox'), findsOneWidget);
        expect(h.delegate.state.active.entries, hasLength(2));

        expect(await h.delegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Inbox'), findsNothing);
        expect(h.delegate.state.active.entries, hasLength(1));
      });
    });
  }

  testWidgets('README drawer workaround at a branch root', (
    WidgetTester tester,
  ) async {
    final GlobalKey<ScaffoldState> drawerScaffold = GlobalKey<ScaffoldState>();
    final DemoHarness h = DemoHarness(
      wrapPage: (DemoRoute route, Widget screen) => route is DemoHome
          ? _DrawerScreen(scaffoldKey: drawerScaffold, title: 'Inbox')
          : screen,
    );
    final List<bool> log = await pumpBackLog(tester, h, kCompact);
    await h.delegate.goBranch(1);
    await tester.pumpAndSettle();
    expect(log.last, isFalse);

    drawerScaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsOneWidget);
    expect(log.last, isTrue);

    expect(await h.delegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsNothing);
    expect(find.text('Inbox'), findsOneWidget);
    expect(log.last, isFalse);
  });

  for (final bool allow in <bool>[true, false]) {
    testWidgets('guarded entry, onExit -> $allow, on system back', (
      WidgetTester tester,
    ) async {
      int asked = 0;
      final DemoHarness h = DemoHarness();
      await pumpBackLog(tester, h, kCompact);

      h.delegate.push(
        const DemoDetail(1),
        onExit: () async {
          asked++;
          return allow;
        },
      );
      await tester.pumpAndSettle();

      expect(await h.delegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.text('Detail 1'), allow ? findsNothing : findsOneWidget);
    });
  }
}

/// The README's "System back" example.
class _DrawerScreen extends StatefulWidget {
  const _DrawerScreen({required this.scaffoldKey, required this.title});

  final GlobalKey<ScaffoldState> scaffoldKey;
  final String title;

  @override
  State<_DrawerScreen> createState() => _DrawerScreenState();
}

class _DrawerScreenState extends State<_DrawerScreen> {
  bool _drawerOpen = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_drawerOpen,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          widget.scaffoldKey.currentState?.closeDrawer();
        }
      },
      child: Scaffold(
        key: widget.scaffoldKey,
        drawer: const Drawer(child: Text('Filters')),
        onDrawerChanged: (bool open) => setState(() => _drawerOpen = open),
        body: Center(child: Text(widget.title)),
      ),
    );
  }
}
