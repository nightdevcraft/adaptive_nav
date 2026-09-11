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
