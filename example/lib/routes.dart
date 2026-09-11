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

/// Deep links and the address bar on the web go through this codec.
class AppRouteCodec extends RouteCodec<AppRoute> {
  const AppRouteCodec();

  @override
  Uri encode(AppRoute route) => switch (route) {
    PeopleList() => Uri.parse('/people'),
    PersonDetail(:final int id) => Uri.parse('/people/$id'),
    PersonEdit(:final int id) => Uri.parse('/people/$id/edit'),
    SettingsRoute() => Uri.parse('/settings'),
  };

  @override
  AppRoute decode(Uri uri) {
    final List<String> seg = uri.pathSegments;
    if (seg.isNotEmpty && seg.first == 'settings') {
      return const SettingsRoute();
    }
    if (seg.length >= 2 && seg.first == 'people') {
      final int? id = int.tryParse(seg[1]);
      if (id != null) {
        return seg.length >= 3 && seg[2] == 'edit'
            ? PersonEdit(id)
            : PersonDetail(id);
      }
    }
    return const PeopleList();
  }

  @override
  int branchOf(AppRoute route) => switch (route) {
    SettingsRoute() => 1,
    PeopleList() || PersonDetail() || PersonEdit() => 0,
  };
}
