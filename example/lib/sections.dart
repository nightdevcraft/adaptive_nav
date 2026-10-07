import 'package:flutter/material.dart';

import 'data.dart';
import 'routes.dart';
import 'screens.dart';

class TeamsListScreen extends StatelessWidget {
  const TeamsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      body: ListView(
        children: <Widget>[
          for (final Team t in teams)
            ListTile(
              title: Text(t.name),
              subtitle: Text('${t.members.length} members'),
              onTap: () => scope.delegate.push(TeamDetail(t.id)),
            ),
        ],
      ),
    );
  }
}

class TeamDetailScreen extends StatelessWidget {
  const TeamDetailScreen({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context) {
    final Team team = teamById(id);
    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: ListView(
        children: <Widget>[
          for (final String name in team.members)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(name),
            ),
        ],
      ),
    );
  }
}

/// A drawer inside a screen is not reported to the system, so the screen
/// blocks pop while it is open and closes it instead.
class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});

  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;
  final Set<StarredKind> _kinds = StarredKind.values.toSet();

  static IconData _icon(StarredKind kind) => switch (kind) {
    StarredKind.person => Icons.person_outline,
    StarredKind.team => Icons.groups_outlined,
    StarredKind.note => Icons.notes,
  };

  static String _label(StarredKind kind) => switch (kind) {
    StarredKind.person => 'People',
    StarredKind.team => 'Teams',
    StarredKind.note => 'Notes',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_drawerOpen,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          _scaffold.currentState?.closeDrawer();
        }
      },
      child: Scaffold(
        key: _scaffold,
        appBar: AppBar(
          title: const Text('Starred'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filters',
              onPressed: () => _scaffold.currentState?.openDrawer(),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: <Widget>[
                const ListTile(title: Text('Show')),
                for (final StarredKind kind in StarredKind.values)
                  CheckboxListTile(
                    secondary: Icon(_icon(kind)),
                    title: Text(_label(kind)),
                    value: _kinds.contains(kind),
                    onChanged: (bool? on) => setState(
                      () => on! ? _kinds.add(kind) : _kinds.remove(kind),
                    ),
                  ),
              ],
            ),
          ),
        ),
        onDrawerChanged: (bool open) => setState(() => _drawerOpen = open),
        body: ListView(
          children: <Widget>[
            for (final StarredItem item in starred)
              if (_kinds.contains(item.kind))
                ListTile(
                  leading: Icon(_icon(item.kind)),
                  title: Text(item.title),
                  trailing: const Icon(Icons.star),
                ),
          ],
        ),
      ),
    );
  }
}

class NotesListScreen extends StatelessWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recent')),
      body: ListView(
        children: <Widget>[
          for (final Note n in notes)
            ListTile(
              title: Text(n.title),
              subtitle: Text(n.body, maxLines: 1),
              onTap: () => scope.delegate.push(NoteDetail(n.id)),
            ),
        ],
      ),
    );
  }
}

/// Holds the user on the screen while the text differs from what was saved.
class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({required this.id, super.key});

  final int id;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late String _saved = noteById(widget.id).body;
  late final TextEditingController _text = TextEditingController(text: _saved)
    ..addListener(() => setState(() {}));

  bool get _dirty => _text.text != _saved;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Unsaved')));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(noteById(widget.id).title),
          actions: <Widget>[
            TextButton(
              onPressed: _dirty
                  ? () => setState(() => _saved = _text.text)
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _text,
            maxLines: null,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ),
    );
  }
}

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final List<String> _items = List<String>.of(archived);

  Future<void> _restore(String item) async {
    final bool? restore = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Restore?'),
        content: Text(item),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (restore ?? false) {
      setState(() => _items.remove(item));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: ListView(
        children: <Widget>[
          for (final String item in _items)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(item),
              onTap: () => _restore(item),
            ),
        ],
      ),
    );
  }
}

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final List<String> _items = List<String>.of(trashed);

  Future<void> _empty() async {
    final bool? empty = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text('${_items.length} items will be deleted.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (empty ?? false) {
      setState(_items.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: <Widget>[
          TextButton(
            onPressed: _items.isEmpty ? null : _empty,
            child: const Text('Empty'),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          for (final String item in _items)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(item),
            ),
        ],
      ),
    );
  }
}
