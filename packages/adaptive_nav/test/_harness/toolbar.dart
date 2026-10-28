import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'demo_app.dart';

/// A screen with a [PaneToolbar]: Close or Back on its own, the given
/// [pinned] items and [groups], and its header from the layout it is handed.
class ToolbarScreen extends StatelessWidget {
  const ToolbarScreen({
    required this.title,
    this.pinned = const <PaneToolbarItem>[],
    this.groups = const <List<PaneToolbarItem>>[],
    this.compression,
    this.onBuild,
    super.key,
  });

  final String title;
  final List<PaneToolbarItem> pinned;
  final List<List<PaneToolbarItem>> groups;
  final VerticalBarCompression? compression;

  /// Called every time the screen itself is built, not its toolbar.
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild?.call();
    return PaneToolbar(
      pinned: pinned,
      groups: groups,
      compression: compression,
      builder: (BuildContext context, PaneToolbarLayout toolbar) => Scaffold(
        appBar: AppBar(
          leading: toolbar.leading,
          automaticallyImplyLeading: toolbar.automaticallyImplyLeading,
          title: Text(title),
          actions: toolbar.actions,
        ),
        body: Center(child: Text('$title body')),
      ),
    );
  }
}

/// An item with an icon of its own, so a test can find it by the icon.
PaneToolbarItem toolbarItem(
  IconData icon, {
  int priority = 0,
  bool horizontalOnly = false,
  VoidCallback? onPressed,
}) => PaneToolbarItem(
  icon: icon,
  label: 'item ${icon.codePoint}',
  visibilityPriority: priority,
  horizontalOnly: horizontalOnly,
  onPressed: onPressed ?? () {},
);

/// [DemoHarness.wrapPage] that gives the detail the Edit action of the
/// example's person screen, and every other screen a bare toolbar.
Widget Function(DemoRoute, Widget) toolbarScreens({
  List<PaneToolbarItem>? detailPinned,
  List<List<PaneToolbarItem>> detailGroups = const <List<PaneToolbarItem>>[],
  VerticalBarCompression? compression,
  VoidCallback? onDetailBuild,
}) =>
    (DemoRoute route, Widget screen) => switch (route) {
      DemoDetail(:final int id) => ToolbarScreen(
        title: 'Detail $id',
        pinned:
            detailPinned ??
            <PaneToolbarItem>[
              PaneToolbarItem(
                icon: Icons.edit,
                label: 'Edit',
                onPressed: () {},
              ),
            ],
        groups: detailGroups,
        compression: compression,
        onBuild: onDetailBuild,
      ),
      DemoList() => const ToolbarScreen(title: 'List'),
      DemoHome() => const ToolbarScreen(title: 'Home'),
      _ => screen,
    };
