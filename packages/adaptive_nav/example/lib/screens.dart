import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';

/// Hands the router and the store down to the screens. A real app would use
/// whatever state management it already has.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.nav,
    required this.store,
    required super.child,
    super.key,
  });

  final AdaptiveNav<AppRoute> nav;
  final PeopleStore store;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.nav != nav || oldWidget.store != store;
}

/// An `AppBar` that keeps its trailing end clear of the clock where the shell
/// lifts it into the status row (`liftHeadersIntoStatusRow`).
///
/// There the title stays centred only if [minCentredTitleWidth] is left
/// between the reserves at both ends; otherwise it would drift towards the
/// clock, so it goes to the start.
class PaneAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PaneAppBar({
    required this.title,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.actions = const <Widget>[],
    super.key,
  });

  /// Builds one from a [PaneToolbar]'s layout: its navigation button and
  /// actions, or none of them while the shell has them in the system's
  /// column.
  PaneAppBar.of(
    PaneToolbarLayout toolbar, {
    required Widget title,
    Color? backgroundColor,
    Key? key,
  }) : this(
         title: title,
         leading: toolbar.leading,
         automaticallyImplyLeading: toolbar.automaticallyImplyLeading,
         backgroundColor: backgroundColor,
         actions: toolbar.actions,
         key: key,
       );

  final Widget title;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final List<Widget> actions;

  static const double minCentredTitleWidth = 240;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final double reserve = StatusRowScope.trailingReserveOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints pane) => AppBar(
        backgroundColor: backgroundColor,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        title: title,
        centerTitle: reserve == 0
            ? null
            : pane.maxWidth - 2 * reserve >= minCentredTitleWidth,
        actions: <Widget>[
          ...actions,
          SizedBox(width: reserve),
        ],
      ),
    );
  }
}

/// The master: the branch root, so in the wide layout it lives in the left
/// pane and in the compact one it is the whole screen.
class PeopleListScreen extends StatelessWidget {
  const PeopleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return Scaffold(
      appBar: const PaneAppBar(title: Text('People')),
      body: ListenableBuilder(
        listenable: scope.store,
        builder: (BuildContext context, Widget? _) => ListView(
          children: <Widget>[
            for (final Person p in scope.store.people)
              ListTile(
                title: Text(p.name),
                subtitle: Text(p.role),
                // resetDetailTo, not push: picking another person is a lateral
                // move, so a detail of any depth is replaced in one mutation.
                onTap: () => scope.nav.resetDetailTo(PersonDetail(p.id)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Background of the detail screens. One step darker than the master, so two
/// flush panes are told apart without a divider. Used on a phone as well.
Color detailShade(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLow;

/// The first detail. In the wide layout it fills the right pane. Its toolbar
/// is a [PaneToolbar]: a close button — the toolbar picks it, as the first
/// screen of the detail — and Edit, in the header or, on iPhone Duo, in the
/// system's column above the rail.
class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    // On a phone the detail covers the shell's navigation bar, so its bottom
    // edge becomes its own business. In a pane the shell has already dealt
    // with it.
    final bool fullScreen = DetailPaneScope.isFullScreen(context);
    return ListenableBuilder(
      listenable: scope.store,
      builder: (BuildContext context, Widget? _) {
        final Person person = scope.store.byId(id);
        final Color shade = detailShade(context);
        return PaneToolbar(
          pinned: <PaneToolbarItem>[
            PaneToolbarItem(
              icon: Icons.edit_outlined,
              label: 'Edit',
              // The guard runs on every way out of the editor: system back,
              // replace, a tab switch, or picking another person.
              onPressed: () => scope.nav.push(
                PersonEdit(id),
                onExit: () => confirmDiscard(context),
              ),
            ),
          ],
          builder: (BuildContext context, PaneToolbarLayout toolbar) =>
              Scaffold(
                backgroundColor: shade,
                appBar: PaneAppBar.of(
                  toolbar,
                  backgroundColor: shade,
                  title: Text(person.name),
                ),
                body: SafeArea(
                  top: false,
                  bottom: fullScreen,
                  child: Center(
                    child: Text(
                      person.role,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
        );
      },
    );
  }
}

/// The second detail, pushed on top of the first. It carries an exit guard, so
/// every way out — back, a tab switch, picking another person — asks first.
class PersonEditScreen extends StatefulWidget {
  const PersonEditScreen({required this.id, super.key});

  final int id;

  @override
  State<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends State<PersonEditScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _role = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seeded once: the screen survives resizes and tab switches without being
    // remounted, and the fields must not be reset under the user.
    if (_seeded) {
      return;
    }
    _seeded = true;
    final Person person = AppScope.of(context).store.byId(widget.id);
    _name.text = person.name;
    _role.text = person.role;
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  void _save() {
    final AppScope scope = AppScope.of(context);
    scope.store.rename(widget.id, _name.text, _role.text);
    // This lands on the detail pane's own messenger, so the bar shows up in
    // that pane rather than across the whole window.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved')));
    // popWithResult, not pop: the screen has already decided, so the exit
    // guard is not asked again.
    scope.nav.popWithResult(null);
  }

  @override
  Widget build(BuildContext context) {
    final Color shade = detailShade(context);
    // Back is the toolbar's own pick, and Save stands next to it: in the
    // header, or with Back in the system's column on iPhone Duo.
    return PaneToolbar(
      pinned: <PaneToolbarItem>[
        PaneToolbarItem(icon: Icons.check, label: 'Save', onPressed: _save),
      ],
      builder: (BuildContext context, PaneToolbarLayout toolbar) => Scaffold(
        backgroundColor: shade,
        appBar: PaneAppBar.of(
          toolbar,
          backgroundColor: shade,
          title: Text(
            'Editing ${AppScope.of(context).store.byId(widget.id).name}',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _role,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PaneAppBar(title: Text('Settings')),
      // The switch is ephemeral state: leave the tab, come back, and it is
      // still where you left it — the branch navigator was never unmounted.
      body: SwitchListTile(
        title: const Text('Notifications'),
        value: _notifications,
        onChanged: (bool v) => setState(() => _notifications = v),
      ),
    );
  }
}

/// Asked before leaving the editor. Returning `false` keeps the screen where
/// it is, whichever way the user tried to leave.
Future<bool> confirmDiscard(BuildContext context) async {
  final bool? leave = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Discard changes?'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return leave ?? false;
}
