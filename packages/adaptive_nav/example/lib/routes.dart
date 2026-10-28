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

class CalendarRoute extends AppRoute {
  const CalendarRoute();

  @override
  bool operator ==(Object other) => other is CalendarRoute;

  @override
  int get hashCode => (CalendarRoute).hashCode;
}

class FilesRoute extends AppRoute {
  const FilesRoute();

  @override
  bool operator ==(Object other) => other is FilesRoute;

  @override
  int get hashCode => (FilesRoute).hashCode;
}

class TagsRoute extends AppRoute {
  const TagsRoute();

  @override
  bool operator ==(Object other) => other is TagsRoute;

  @override
  int get hashCode => (TagsRoute).hashCode;
}

/// The section a route belongs to, by the id of its branch; `null` for
/// People and Settings, which are always there.
String? sectionOf(AppRoute route) => switch (route) {
  PeopleList() || PersonDetail() || PersonEdit() || SettingsRoute() => null,
  TeamsList() || TeamDetail() => 'teams',
  StarredRoute() => 'starred',
  NotesList() || NoteDetail() => 'recent',
  ArchiveRoute() => 'archive',
  TrashRoute() => 'trash',
  CalendarRoute() => 'calendar',
  FilesRoute() => 'files',
  TagsRoute() => 'tags',
};

/// Deep links and the address bar on the web go through this codec.
///
/// [sections] are the ids of the branches after People and Settings, in
/// order: a link to a section the app was not started with opens People.
class AppRouteCodec extends RouteCodec<AppRoute> {
  const AppRouteCodec({required this.sections});

  final List<String> sections;

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
    CalendarRoute() => Uri.parse('/calendar'),
    FilesRoute() => Uri.parse('/files'),
    TagsRoute() => Uri.parse('/tags'),
  };

  @override
  AppRoute decode(Uri uri) {
    final AppRoute route = _decode(uri);
    final String? section = sectionOf(route);
    return section == null || sections.contains(section)
        ? route
        : const PeopleList();
  }

  AppRoute _decode(Uri uri) {
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
      case 'calendar':
        return const CalendarRoute();
      case 'files':
        return const FilesRoute();
      case 'tags':
        return const TagsRoute();
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
    _ => 2 + sections.indexOf(sectionOf(route)!),
  };
}
