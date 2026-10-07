import 'package:flutter/foundation.dart';

@immutable
class Person {
  const Person({required this.id, required this.name, required this.role});

  final int id;
  final String name;
  final String role;
}

/// A tiny in-memory store, so the example needs no plugins or backend.
class PeopleStore extends ChangeNotifier {
  final List<Person> _people = <Person>[
    const Person(id: 1, name: 'Ada Lovelace', role: 'Analyst'),
    const Person(id: 2, name: 'Grace Hopper', role: 'Rear Admiral'),
    const Person(id: 3, name: 'Alan Turing', role: 'Cryptanalyst'),
    const Person(id: 4, name: 'Katherine Johnson', role: 'Mathematician'),
    const Person(id: 5, name: 'Barbara Liskov', role: 'Researcher'),
  ];

  List<Person> get people => List<Person>.unmodifiable(_people);

  Person byId(int id) => _people.firstWhere((Person p) => p.id == id);

  void rename(int id, String name, String role) {
    final int i = _people.indexWhere((Person p) => p.id == id);
    if (i < 0) {
      return;
    }
    _people[i] = Person(id: id, name: name, role: role);
    notifyListeners();
  }
}

@immutable
class Team {
  const Team({required this.id, required this.name, required this.members});

  final int id;
  final String name;
  final List<String> members;
}

const List<Team> teams = <Team>[
  Team(
    id: 1,
    name: 'Compilers',
    members: <String>['Grace Hopper', 'Fran Allen'],
  ),
  Team(
    id: 2,
    name: 'Codebreakers',
    members: <String>['Alan Turing', 'Joan Clarke'],
  ),
  Team(
    id: 3,
    name: 'Flight Dynamics',
    members: <String>['Katherine Johnson', 'Dorothy Vaughan', 'Mary Jackson'],
  ),
  Team(
    id: 4,
    name: 'Languages',
    members: <String>['Barbara Liskov', 'Niklaus Wirth'],
  ),
];

Team teamById(int id) => teams.firstWhere((Team t) => t.id == id);

enum StarredKind { person, team, note }

@immutable
class StarredItem {
  const StarredItem(this.title, this.kind);

  final String title;
  final StarredKind kind;
}

const List<StarredItem> starred = <StarredItem>[
  StarredItem('Ada Lovelace', StarredKind.person),
  StarredItem('Flight Dynamics', StarredKind.team),
  StarredItem('Release checklist', StarredKind.note),
  StarredItem('Grace Hopper', StarredKind.person),
  StarredItem('Compilers', StarredKind.team),
  StarredItem('Interview questions', StarredKind.note),
];

@immutable
class Note {
  const Note({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;
}

const List<Note> notes = <Note>[
  Note(id: 1, title: 'Release checklist', body: 'Bump version, tag, publish.'),
  Note(
    id: 2,
    title: 'Interview questions',
    body: 'Ask about the last bug they fixed.',
  ),
  Note(id: 3, title: 'Offsite ideas', body: 'Somewhere with a whiteboard.'),
  Note(id: 4, title: 'Reading list', body: 'The Mythical Man-Month.'),
];

Note noteById(int id) => notes.firstWhere((Note n) => n.id == id);

const List<String> archived = <String>[
  'Q1 planning',
  'Old onboarding guide',
  'Hackathon 2024',
  'Vendor contracts',
];

const List<String> trashed = <String>[
  'Draft: team rename',
  'Duplicate of Reading list',
  'Untitled note',
];
