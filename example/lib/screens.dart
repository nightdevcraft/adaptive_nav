import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';

/// Hands the delegate and the store down to the screens. A real app would use
/// whatever state management it already has.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.delegate,
    required this.store,
    required super.child,
    super.key,
  });

  final AdaptiveRouterDelegate<AppRoute> delegate;
  final PeopleStore store;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.delegate != delegate || oldWidget.store != store;
}

/// The master: the branch root, so in the wide layout it lives in the left
/// pane and in the compact one it is the whole screen.
class PeopleListScreen extends StatelessWidget {
  const PeopleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
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
                onTap: () => scope.delegate.resetDetailTo(PersonDetail(p.id)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The first detail. In the wide layout it fills the right pane, and
/// [DetailEntryScope.isDetailRoot] is what tells it to offer a close button
/// instead of a back arrow.
class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final bool isRoot = DetailEntryScope.isDetailRoot(context);
    // On a phone the detail covers the shell's navigation bar, so its bottom
    // edge becomes its own business. In a pane the shell has already dealt
    // with it.
    final bool fullScreen = DetailPaneScope.isFullScreen(context);
    return ListenableBuilder(
      listenable: scope.store,
      builder: (BuildContext context, Widget? _) {
        final Person person = scope.store.byId(id);
        return Scaffold(
          appBar: AppBar(
            title: Text(person.name),
            leading: IconButton(
              icon: Icon(isRoot ? Icons.close : Icons.arrow_back),
              onPressed: scope.delegate.pop,
            ),
          ),
          body: SafeArea(
            top: false,
            bottom: fullScreen,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    person.role,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    // The guard runs on every way out of the editor: system
                    // back, replace, a tab switch, or picking another person.
                    onPressed: () => scope.delegate.push(
                      PersonEdit(id),
                      onExit: () => confirmDiscard(context),
                    ),
                    child: const Text('Edit'),
                  ),
                ],
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
    scope.delegate.popWithResult(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
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
      appBar: AppBar(title: const Text('Settings')),
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
