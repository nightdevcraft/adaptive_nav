import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/foundation.dart';

/// The app's route type. `adaptive_nav` is generic over it and never looks
/// inside — it only asks the [AppRouteCodec] to turn it into a URL.
@immutable
sealed class AppRoute {
  const AppRoute();
}

class PeopleList extends AppRoute {
  const PeopleList();

  @override
  bool operator ==(Object other) => other is PeopleList;

  @override
  int get hashCode => (PeopleList).hashCode;
}

class PersonDetail extends AppRoute {
  const PersonDetail(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is PersonDetail && other.id == id;

  @override
  int get hashCode => Object.hash(PersonDetail, id);
}

class PersonEdit extends AppRoute {
  const PersonEdit(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is PersonEdit && other.id == id;

  @override
  int get hashCode => Object.hash(PersonEdit, id);
}

class SettingsRoute extends AppRoute {
  const SettingsRoute();

  @override
  bool operator ==(Object other) => other is SettingsRoute;

  @override
  int get hashCode => (SettingsRoute).hashCode;
}

class TeamsList extends AppRoute {
  const TeamsList();

  @override
  bool operator ==(Object other) => other is TeamsList;

  @override
  int get hashCode => (TeamsList).hashCode;
}

class TeamDetail extends AppRoute {
  const TeamDetail(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is TeamDetail && other.id == id;

  @override
  int get hashCode => Object.hash(TeamDetail, id);
}

class StarredRoute extends AppRoute {
  const StarredRoute();

  @override
  bool operator ==(Object other) => other is StarredRoute;

  @override
  int get hashCode => (StarredRoute).hashCode;
}

class NotesList extends AppRoute {
  const NotesList();

  @override
  bool operator ==(Object other) => other is NotesList;

  @override
  int get hashCode => (NotesList).hashCode;
}

class NoteDetail extends AppRoute {
  const NoteDetail(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is NoteDetail && other.id == id;

  @override
  int get hashCode => Object.hash(NoteDetail, id);
}

class ArchiveRoute extends AppRoute {
  const ArchiveRoute();

  @override
  bool operator ==(Object other) => other is ArchiveRoute;

  @override
  int get hashCode => (ArchiveRoute).hashCode;
}

class TrashRoute extends AppRoute {
  const TrashRoute();

  @override
  bool operator ==(Object other) => other is TrashRoute;

  @override
  int get hashCode => (TrashRoute).hashCode;
}

/// Deep links and the address bar on the web go through this codec.
class AppRouteCodec extends RouteCodec<AppRoute> {
  const AppRouteCodec();

  @override
  Uri encode(AppRoute route) => switch (route) {
    PeopleList() => Uri.parse('/people'),
    PersonDetail(:final int id) => Uri.parse('/people/$id'),
    PersonEdit(:final int id) => Uri.parse('/people/$id/edit'),
    SettingsRoute() => Uri.parse('/settings'),
    TeamsList() => Uri.parse('/teams'),
    TeamDetail(:final int id) => Uri.parse('/teams/$id'),
    StarredRoute() => Uri.parse('/starred'),
    NotesList() => Uri.parse('/recent'),
    NoteDetail(:final int id) => Uri.parse('/recent/$id'),
    ArchiveRoute() => Uri.parse('/archive'),
    TrashRoute() => Uri.parse('/trash'),
  };

  @override
  AppRoute decode(Uri uri) {
    final List<String> seg = uri.pathSegments;
    final int? id = seg.length >= 2 ? int.tryParse(seg[1]) : null;
    switch (seg.isEmpty ? '' : seg.first) {
      case 'settings':
        return const SettingsRoute();
      case 'teams':
        return id != null ? TeamDetail(id) : const TeamsList();
      case 'starred':
        return const StarredRoute();
      case 'recent':
        return id != null ? NoteDetail(id) : const NotesList();
      case 'archive':
        return const ArchiveRoute();
      case 'trash':
        return const TrashRoute();
      case 'people' when id != null:
        return seg.length >= 3 && seg[2] == 'edit'
            ? PersonEdit(id)
            : PersonDetail(id);
    }
    return const PeopleList();
  }

  @override
  int branchOf(AppRoute route) => switch (route) {
    PeopleList() || PersonDetail() || PersonEdit() => 0,
    SettingsRoute() => 1,
    TeamsList() || TeamDetail() => 2,
    StarredRoute() => 3,
    NotesList() || NoteDetail() => 4,
    ArchiveRoute() => 5,
    TrashRoute() => 6,
  };
}
