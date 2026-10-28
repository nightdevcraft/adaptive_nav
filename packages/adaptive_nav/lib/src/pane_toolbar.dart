import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'entry_page.dart';
import 'nav_config.dart';

/// Height of one toolbar item on the vertical axis, and of one tab of the
/// system's column: the circle Apple draws a vertical toolbar's button in.
///
/// Measured on the simulator (iPhone Duo, iOS 27.1, outer display upright,
/// @3x): Safari's Back and Reader buttons and the Settings search button are
/// circles 48 across, centred on the glyphs' axis 48 in from the edge — the
/// numbers Apple gives for vertical controls (Tech Talk 111462). It is also
/// over the 44 × 44 hit region of the Human Interface Guidelines.
const double kPaneToolbarItemExtent = 48;

/// Space between two buttons of a vertical toolbar that do not share a group:
/// the navigation button and the next one, two groups, the last group and the
/// menu — and between the toolbar's zone of the system's column and its tabs.
///
/// Measured with [kPaneToolbarItemExtent]: Safari's Back and Reader are 60
/// apart, centre to centre, so 12 between the circles.
const double kPaneToolbarGroupGap = 12;

/// Space between two buttons of one group, and between two tabs of the
/// system's column, which are one group, as Apple draws the tab bar in one
/// capsule.
///
/// Measured with [kPaneToolbarItemExtent]: Safari groups New Tab and Tabs in
/// one capsule 102 tall, the glyphs 54 apart — 6 between the two circles.
/// Material draws no capsule round a group, so the narrower gap is what
/// tells a group from its neighbours.
const double kPaneToolbarItemGap = 6;

/// Who gives up room in the system's column when a screen's vertical
/// toolbar does not fit above the tabs.
///
/// Apple's `UIToolbar` and `UITabBarController` on iPhone Duo: the default,
/// `prefersTabBar`, keeps every tab and folds actions away; with
/// `prefersToolbarItems` the tab bar folds to the selected tab and More and
/// the actions stay (Tech Talk 111462).
///
/// Folded, the tabs keep two places at the bottom of the column: More, in
/// the place of the last one, with a menu of every tab, and the selected
/// tab above it, which behaves as it did unfolded. Where even those two do
/// not leave room for the least of the toolbar — the navigation button and
/// the menu, or the menu alone — More stays alone, filled.
enum VerticalBarCompression {
  /// The tabs keep their places and the toolbar's items go behind its menu,
  /// the lowest [PaneToolbarItem.visibilityPriority] first. Apple's
  /// `prefersTabBar`.
  ///
  /// When the tabs leave too little even for the navigation button and the
  /// menu — or for the menu alone, with no navigation button — they fold, as
  /// with [tabsFirst], the way the system's tab bar does in a short column;
  /// they unfold when a screen that fits comes back.
  toolbarFirst,

  /// The tabs fold to the selected tab and More at the bottom of the column
  /// as soon as the toolbar does not fit beside them whole, and the toolbar
  /// gets the rest of the column. Apple's `prefersToolbarItems`.
  tabsFirst,
}

/// One action of a [PaneToolbar].
@immutable
class PaneToolbarItem {
  const PaneToolbarItem({
    required this.label,
    this.icon,
    this.onPressed,
    this.visibilityPriority = 0,
    this.horizontalOnly = false,
  });

  /// The tooltip, and the item's text in a menu. Without an [icon] it is
  /// also the button.
  final String label;

  /// `null` makes a text button, which stays in the header: a word does not
  /// fit an 80-point column.
  final IconData? icon;

  /// `null` disables the item.
  final VoidCallback? onPressed;

  /// The higher, the longer the item stays out of the menu when there is no
  /// room for all of them. Among equals the last one goes first.
  final int visibilityPriority;

  /// Keeps the item in the header even where the rest of the toolbar is
  /// vertical.
  final bool horizontalOnly;

  /// Whether the item can stand in a vertical toolbar.
  bool get canBeVertical => icon != null && !horizontalOnly;
}

/// How a pane's toolbar is laid out, from the shell.
@immutable
class PaneBar {
  const PaneBar({this.verticalEdge});

  /// The edge of the window the pane's toolbar stands against, vertically,
  /// in the system's column: [ChromePlacement.left] or
  /// [ChromePlacement.right]. `null` when the toolbar is a header.
  ///
  /// Only one pane gets it, and only beside the system's own vertical bar on
  /// iPhone Duo: the single pane on the outer display and in either Split
  /// View window, and the detail of a master-detail pair on the inner display
  /// in landscape. A master keeps its header; so does everything on the inner
  /// display in portrait, where the bars are horizontal.
  final ChromePlacement? verticalEdge;

  bool get isVertical => verticalEdge != null;

  @override
  bool operator ==(Object other) =>
      other is PaneBar && other.verticalEdge == verticalEdge;

  @override
  int get hashCode => verticalEdge.hashCode;

  @override
  String toString() => 'PaneBar(verticalEdge: ${verticalEdge?.name})';
}

/// Carries the [PaneBar] of the pane a screen is in. The shell puts one
/// above every pane's navigator.
class PaneBarScope extends InheritedWidget {
  const PaneBarScope({required this.bar, required super.child, super.key});

  final PaneBar bar;

  /// A horizontal [PaneBar] outside the shell.
  static PaneBar of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneBarScope>()?.bar ??
      const PaneBar();

  @override
  bool updateShouldNotify(PaneBarScope oldWidget) => bar != oldWidget.bar;
}

/// What a [PaneToolbar] hands its builder.
@immutable
class PaneToolbarLayout {
  const PaneToolbarLayout({
    required this.bar,
    required this.leading,
    required this.actions,
  });

  final PaneBar bar;

  /// For `AppBar.leading`: the navigation button, `null` while it is in the
  /// column or there is none.
  final Widget? leading;

  /// For `AppBar.actions`: the items, with what does not fit behind a menu.
  /// While the toolbar is vertical, only the [PaneToolbarItem.horizontalOnly]
  /// items and those without an icon.
  final List<Widget> actions;

  /// For `AppBar.automaticallyImplyLeading`. Always `false`: the toolbar has
  /// decided about the navigation button, and an `AppBar` left to imply one
  /// would put a back arrow in the header while the column has it too.
  bool get automaticallyImplyLeading => false;

  bool get isVertical => bar.isVertical;
}

/// A screen's toolbar, laid out by the shell: a header where the pane has
/// one, a column beside the system's bar where Apple asks for a vertical one
/// ([PaneBar.verticalEdge]).
///
/// ```dart
/// PaneToolbar(
///   pinned: <PaneToolbarItem>[
///     PaneToolbarItem(icon: Icons.edit, label: 'Edit', onPressed: edit),
///   ],
///   builder: (BuildContext context, PaneToolbarLayout toolbar) => Scaffold(
///     appBar: AppBar(
///       leading: toolbar.leading,
///       automaticallyImplyLeading: toolbar.automaticallyImplyLeading,
///       title: const Text('Ada Lovelace'),
///       actions: toolbar.actions,
///     ),
///     body: body,
///   ),
/// )
/// ```
///
/// Top to bottom on the vertical axis: [navigation], [pinned], then each of
/// [groups] after a gap. While the toolbar is vertical the shell draws the
/// items itself, in the system's column, which on the outer display is not
/// part of the pane at all; [builder] gets an empty header then. Only the
/// screen on top of its pane's navigator is drawn there.
///
/// Changing from one to the other fades over [duration], and only the
/// header's buttons and the column rebuild: the screen is not built again
/// for the animation.
class PaneToolbar extends StatefulWidget {
  const PaneToolbar({
    required this.builder,
    this.navigation,
    this.pinned = const <PaneToolbarItem>[],
    this.groups = const <List<PaneToolbarItem>>[],
    this.compression,
    this.maxHeaderActions = 3,
    this.duration = kDefaultImmersiveDuration,
    super.key,
  });

  /// Back or Close. `null` decides: Close on the first screen of a detail
  /// (`DetailEntryScope.isDetailRoot`) or a full-screen dialog, Back where the
  /// route has something below it to go back to, nothing on a root. Either
  /// pops the pane's navigator, as an `AppBar`'s own button does.
  final PaneToolbarItem? navigation;

  /// The screen's main actions, such as Done or Edit: right after [navigation]
  /// on the vertical axis, at the trailing end of the header.
  final List<PaneToolbarItem> pinned;

  /// The rest, one list per group.
  final List<List<PaneToolbarItem>> groups;

  /// Overrides `BranchConfig.verticalCompression` for this screen.
  final VerticalBarCompression? compression;

  /// How many items the header shows before the rest go behind its menu.
  final int maxHeaderActions;

  /// How long the toolbar fades when it changes sides, and in the system's
  /// column when a tab switch brings it. A screen coming or going changes
  /// the column with its route's transition instead.
  final Duration duration;

  final Widget Function(BuildContext context, PaneToolbarLayout toolbar)
  builder;

  @override
  State<PaneToolbar> createState() => _PaneToolbarState();
}

class _PaneToolbarState extends State<PaneToolbar> {
  PaneToolbarHost? _host;
  PaneToolbarEntry? _entry;
  PaneBar _bar = const PaneBar();

  /// Set once the toolbar has changed sides, so that only the buttons that
  /// arrive with a change fade in — not those of a screen just opened, which
  /// has a transition of its own.
  bool _switched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final PaneBar bar = PaneBarScope.of(context);
    if (_entry != null && bar.isVertical != _bar.isVertical) {
      _switched = true;
    }
    _bar = bar;
    _sync();
  }

  @override
  void didUpdateWidget(PaneToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Where the toolbar is remembered under its route, current or not.
  ({PaneToolbarRegistry registry, Route<Object?> route})? _remembered;

  /// Registers this screen with the shell while it is on top of its
  /// navigator, and withdraws it otherwise. Its route keeps it either way,
  /// for the column to show what a back gesture leads to.
  void _sync() {
    final PaneToolbarHost? host = PaneToolbarHost.maybeOf(context);
    final bool current = ModalRoute.isCurrentOf(context) ?? true;
    final Route<Object?>? route = ModalRoute.of(context);
    final PaneToolbarEntry entry = PaneToolbarEntry(
      owner: this,
      navigation: widget.navigation ?? automaticNavigation(context),
      pinned: widget.pinned,
      groups: widget.groups,
      compression: widget.compression,
      duration: widget.duration,
    );
    if (_host != null && (_host != host || !current)) {
      _host!.registry.release(_host!.slot, this);
    }
    _host = current ? host : null;
    _entry = entry;
    _host?.registry.claim(_host!.slot, entry);
    _forget();
    if (host != null && route != null) {
      _remembered = (registry: host.registry, route: route);
      host.registry.remember(route, entry);
    }
  }

  void _forget() {
    _remembered?.registry.forget(_remembered!.route, this);
    _remembered = null;
  }

  @override
  void dispose() {
    _host?.registry.release(_host!.slot, this);
    _forget();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PaneToolbarEntry entry = _entry!;
    final bool vertical = _bar.isVertical;
    Widget fade(Widget child) =>
        _switched ? _FadeIn(duration: widget.duration, child: child) : child;
    final PaneToolbarItem? navigation = entry.navigation;
    // In the column's order, which is the order they give way in.
    final List<PaneToolbarItem> items = <PaneToolbarItem>[
      ...widget.pinned,
      for (final List<PaneToolbarItem> group in widget.groups) ...group,
    ];
    return widget.builder(
      context,
      PaneToolbarLayout(
        bar: _bar,
        leading: vertical || navigation == null
            ? null
            : fade(paneToolbarButton(navigation)),
        actions: <Widget>[
          for (final Widget action in headerActions(
            context,
            <PaneToolbarItem>[
              for (final PaneToolbarItem item in items)
                if (!vertical || !item.canBeVertical) item,
            ],
            pinned: widget.pinned
                .where((PaneToolbarItem i) => !vertical || !i.canBeVertical)
                .length,
            limit: widget.maxHeaderActions,
          ))
            fade(action),
        ],
      ),
    );
  }
}

/// The navigation button a screen gets without asking: Close on the first
/// screen of a detail (`DetailEntryScope.isDetailRoot`) or a full-screen
/// dialog, Back where the route has something below it to go back to,
/// `null` on a root. Either pops the pane's navigator through its pop
/// scopes, so an exit guard has its say.
///
/// What a [PaneToolbar] without [PaneToolbar.navigation] shows, and what
/// the shell stands in the system's column for a screen without a toolbar.
PaneToolbarItem? automaticNavigation(BuildContext context) {
  final ModalRoute<Object?>? route = ModalRoute.of(context);
  final MaterialLocalizations l10n = MaterialLocalizations.of(context);
  void pop() => Navigator.maybePop(context);
  final bool dialog = route is PageRoute && route.fullscreenDialog;
  if (DetailEntryScope.isDetailRoot(context) || dialog) {
    return PaneToolbarItem(
      icon: Icons.close,
      label: l10n.closeButtonTooltip,
      onPressed: pop,
    );
  }
  if (route != null && routeImpliesDismissal(route)) {
    return PaneToolbarItem(
      icon: Icons.arrow_back,
      label: l10n.backButtonTooltip,
      onPressed: pop,
    );
  }
  return null;
}

/// A [PaneToolbarItem] as a button: an `IconButton` with its label for a
/// tooltip, or a `TextButton` without an icon. [prominent] is for the pinned
/// items, in a header and in a column alike.
///
/// A prominent action is set apart by colour alone — the icon in
/// `ColorScheme.primary`, no fill — as Apple tints a toolbar's prominent
/// item. A filled tonal circle is what marks the selected destination of the
/// rail beside it, and a pinned Edit drawn that way read as a section of the
/// app.
Widget paneToolbarButton(PaneToolbarItem item, {bool prominent = false}) {
  final IconData? icon = item.icon;
  if (icon == null) {
    return TextButton(onPressed: item.onPressed, child: Text(item.label));
  }
  if (!prominent) {
    return IconButton(
      icon: Icon(icon),
      tooltip: item.label,
      onPressed: item.onPressed,
    );
  }
  return Builder(
    builder: (BuildContext context) => IconButton(
      icon: Icon(icon),
      tooltip: item.label,
      color: Theme.of(context).colorScheme.primary,
      onPressed: item.onPressed,
    ),
  );
}

/// The order [items] go behind a menu in: the lowest
/// [PaneToolbarItem.visibilityPriority] first, the last of equals first.
List<int> hidingOrder(List<PaneToolbarItem> items) =>
    List<int>.generate(items.length, (int i) => i)..sort((int a, int b) {
      final int byPriority = items[a].visibilityPriority.compareTo(
        items[b].visibilityPriority,
      );
      return byPriority != 0 ? byPriority : b.compareTo(a);
    });

/// [items] for an `AppBar`: at most [limit] of them and a menu of the rest.
///
/// [items] come in the vertical toolbar's order, the first [pinned] of them
/// pinned, and give way in the same [hidingOrder]; the header shows the
/// groups first and the pinned items at its trailing end.
List<Widget> headerActions(
  BuildContext context,
  List<PaneToolbarItem> items, {
  required int pinned,
  required int limit,
}) {
  final Set<int> hidden = <int>{
    ...hidingOrder(items).take(items.length > limit ? items.length - limit : 0),
  };
  final List<int> shown = <int>[
    for (int i = pinned; i < items.length; i++) i,
    for (int i = 0; i < pinned; i++) i,
  ];
  return <Widget>[
    for (final int i in shown)
      if (!hidden.contains(i))
        paneToolbarButton(items[i], prominent: i < pinned),
    if (hidden.isNotEmpty)
      PopupMenuButton<PaneToolbarItem>(
        icon: const Icon(Icons.more_horiz),
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        onSelected: (PaneToolbarItem item) => item.onPressed?.call(),
        itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<PaneToolbarItem>>[
              for (int i = 0; i < items.length; i++)
                if (hidden.contains(i))
                  PopupMenuItem<PaneToolbarItem>(
                    value: items[i],
                    enabled: items[i].onPressed != null,
                    child: Text(items[i].label),
                  ),
            ],
      ),
  ];
}

/// One screen's toolbar as the shell sees it, with the navigation button
/// already decided.
@immutable
class PaneToolbarEntry {
  const PaneToolbarEntry({
    required this.owner,
    required this.navigation,
    required this.pinned,
    required this.groups,
    required this.compression,
    required this.duration,
  });

  /// The screen's toolbar: what tells one screen's entry from another's.
  final Object owner;
  final PaneToolbarItem? navigation;
  final List<PaneToolbarItem> pinned;
  final List<List<PaneToolbarItem>> groups;
  final VerticalBarCompression? compression;
  final Duration duration;

  /// Every item that can stand in the column, in order.
  List<PaneToolbarSlot> get vertical => <PaneToolbarSlot>[
    if (navigation case final PaneToolbarItem nav when nav.canBeVertical)
      (item: nav, group: -1, keep: true),
    for (final PaneToolbarItem item in pinned)
      if (item.canBeVertical) (item: item, group: 0, keep: false),
    for (int g = 0; g < groups.length; g++)
      for (final PaneToolbarItem item in groups[g])
        if (item.canBeVertical) (item: item, group: g + 1, keep: false),
  ];
}

/// One item of a vertical toolbar: its group — the navigation button stands
/// alone as -1, as Apple draws Back in a circle of its own, the pinned items
/// are 0 — and whether it may go behind the menu, which the navigation button
/// may not.
typedef PaneToolbarSlot = ({PaneToolbarItem item, int group, bool keep});

/// Which pane's navigator: the master (or a plain tab's only one) or the
/// detail, of [branch].
typedef PaneSlot = ({int branch, bool detail});

/// The toolbars of the screens on top of each pane's navigator, for the shell
/// to draw in the system's column.
///
/// Screens register while they build, when nothing may be notified, so the
/// news goes out after the frame.
class PaneToolbarRegistry extends ChangeNotifier {
  final Map<PaneSlot, PaneToolbarEntry> _entries =
      <PaneSlot, PaneToolbarEntry>{};
  bool _scheduled = false;
  bool _disposed = false;

  final Map<Route<Object?>, PaneToolbarEntry> _byRoute =
      <Route<Object?>, PaneToolbarEntry>{};

  /// The navigation buttons of screens without a toolbar
  /// ([AutomaticPaneBack]), each under a [PaneToolbar]'s if both are there.
  final Map<PaneSlot, PaneToolbarEntry> _automatic =
      <PaneSlot, PaneToolbarEntry>{};
  final Map<Route<Object?>, PaneToolbarEntry> _automaticByRoute =
      <Route<Object?>, PaneToolbarEntry>{};

  PaneToolbarEntry? operator [](PaneSlot slot) =>
      _entries[slot] ?? _automatic[slot];

  /// The toolbar of [route]'s screen, on top of its navigator or not.
  PaneToolbarEntry? ofRoute(Route<Object?>? route) =>
      route == null ? null : _byRoute[route] ?? _automaticByRoute[route];

  /// Nobody is told: only a back gesture reads it, and the gesture's start
  /// is news of its own.
  void remember(Route<Object?> route, PaneToolbarEntry entry) =>
      _byRoute[route] = entry;

  void forget(Route<Object?> route, Object owner) {
    if (_byRoute[route]?.owner == owner) {
      _byRoute.remove(route);
    }
  }

  void claim(PaneSlot slot, PaneToolbarEntry entry) {
    _entries[slot] = entry;
    _changed();
  }

  void release(PaneSlot slot, Object owner) {
    if (_entries[slot]?.owner == owner) {
      _entries.remove(slot);
      _changed();
    }
  }

  void claimAutomatic(
    PaneSlot slot,
    Route<Object?>? route,
    PaneToolbarEntry entry,
  ) {
    if (route != null) {
      _automaticByRoute[route] = entry;
    }
    _automatic[slot] = entry;
    _changed();
  }

  /// Remembers [entry] for [route] alone, while its screen is not on top.
  void claimAutomaticRoute(Route<Object?> route, PaneToolbarEntry entry) =>
      _automaticByRoute[route] = entry;

  void releaseAutomatic(PaneSlot slot, Route<Object?>? route, Object owner) {
    if (route != null && _automaticByRoute[route]?.owner == owner) {
      _automaticByRoute.remove(route);
    }
    if (_automatic[slot]?.owner == owner) {
      _automatic.remove(slot);
      _changed();
    }
  }

  void _changed() {
    if (_scheduled || _disposed) {
      return;
    }
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((Duration _) {
        _scheduled = false;
        if (!_disposed) {
          notifyListeners();
        }
      }, debugLabel: 'PaneToolbarRegistry.notify')
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Where a [PaneToolbar] registers: the shell's registry and the pane it is
/// in. Above every pane's navigator, next to its [PaneBarScope].
class PaneToolbarHost extends InheritedWidget {
  const PaneToolbarHost({
    required this.registry,
    required this.slot,
    required this.automaticBack,
    required super.child,
    super.key,
  });

  final PaneToolbarRegistry registry;
  final PaneSlot slot;

  /// `AdaptiveShellConfig.automaticBackInColumn`.
  final bool automaticBack;

  static PaneToolbarHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneToolbarHost>();

  @override
  bool updateShouldNotify(PaneToolbarHost oldWidget) =>
      registry != oldWidget.registry ||
      slot != oldWidget.slot ||
      automaticBack != oldWidget.automaticBack;
}

/// The extent of [groups] on the vertical axis: an item each,
/// [kPaneToolbarItemGap] between two of one group and [kPaneToolbarGroupGap]
/// wherever the group changes.
double verticalToolbarExtent(Iterable<int> groups) {
  double extent = 0;
  int? last;
  for (final int group in groups) {
    if (last != null) {
      extent += group == last ? kPaneToolbarItemGap : kPaneToolbarGroupGap;
    }
    extent += kPaneToolbarItemExtent;
    last = group;
  }
  return extent;
}

/// The places [tabs] tabs [extent] tall each have in the tabs' zone of the
/// system's column, the More button's included, where the column holds
/// [inner] between its ends.
///
/// Worked out from the column alone — never from the screen's toolbar or the
/// selection — so a tab stays where it is as screens and tabs change. The
/// zone keeps [kPaneToolbarGroupGap] from the toolbar's above it, and no
/// room for the toolbar itself: a screen without one leaves it to the tabs,
/// and one that needs more than the tabs leave folds them instead.
int columnTabPlaces({
  required double inner,
  required double extent,
  required int tabs,
}) {
  final int fit =
      ((inner - kPaneToolbarGroupGap + kPaneToolbarItemGap) /
              (extent + kPaneToolbarItemGap))
          .floor();
  return math.min(tabs, math.max(1, fit));
}

/// The extent of [places] tabs [extent] tall each, [kPaneToolbarItemGap]
/// apart.
double columnTabsExtent(int places, double extent) =>
    places * extent + (places - 1) * kPaneToolbarItemGap;

/// The group of a vertical toolbar's menu: after everything else.
const int kPaneToolbarMenuGroup = 1 << 30;

/// The items of a vertical toolbar that fit [room], and the rest.
///
/// Items go behind the menu in [hidingOrder]; the navigation button stays,
/// whatever is left for it — Apple never folds Back away — and the menu takes
/// a slot of its own, after a gap, once anything is in it.
({List<int> shown, List<int> hidden, bool menu}) fitVerticalToolbar(
  List<PaneToolbarSlot> items, {
  required double room,
}) {
  final Set<int> hidden = <int>{};
  double extent() => verticalToolbarExtent(<int>[
    for (int i = 0; i < items.length; i++)
      if (!hidden.contains(i)) items[i].group,
    if (hidden.isNotEmpty) kPaneToolbarMenuGroup,
  ]);
  final List<int> order = hidingOrder(<PaneToolbarItem>[
    for (final PaneToolbarSlot e in items) e.item,
  ]);
  for (final int i in order) {
    if (extent() <= room) {
      break;
    }
    if (!items[i].keep) {
      hidden.add(i);
    }
  }
  return (
    shown: <int>[
      for (int i = 0; i < items.length; i++)
        if (!hidden.contains(i)) i,
    ],
    hidden: <int>[
      for (int i = 0; i < items.length; i++)
        if (hidden.contains(i)) i,
    ],
    menu: hidden.isNotEmpty,
  );
}

/// The navigation button of a screen without a [PaneToolbar], for the
/// system's column: the shell wraps every page it builds in one.
///
/// `UINavigationController` puts Back in the vertical bar of iPhone Duo
/// whatever the screen's own bar holds; this does the same for a screen
/// that never described a toolbar. It registers [automaticNavigation] under
/// its pane, as a [PaneToolbar] registers its own, and a [PaneToolbar]
/// anywhere in the screen takes the slot over. The route keeps the
/// `AppBar` from drawing its arrow meanwhile (`impliesAppBarDismissal`, see
/// `entry_page.dart`).
///
/// A screen whose `AppBar` has a `leading` of its own, or
/// `automaticallyImplyLeading: false`, has decided about its navigation
/// button: it gets none in the column, and its header is left as it is.
/// The header is looked at after the frame the screen is built in, as the
/// column only hears of a toolbar then anyway, and again whenever the screen
/// becomes the top one; a `leading` that comes later is not noticed.
class AutomaticPaneBack extends StatefulWidget {
  const AutomaticPaneBack({required this.child, super.key});

  final Widget child;

  @override
  State<AutomaticPaneBack> createState() => _AutomaticPaneBackState();
}

class _AutomaticPaneBackState extends State<AutomaticPaneBack> {
  /// Where the entry is claimed: the pane and the route it is remembered
  /// under.
  ({PaneToolbarHost host, Route<Object?>? route})? _claimed;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final PaneToolbarHost? host = PaneToolbarHost.maybeOf(context);
    ModalRoute.isCurrentOf(context);
    DetailEntryScope.isDetailRoot(context);
    if (host == null || !host.automaticBack) {
      _release();
      return;
    }
    // After the frame: the screen is built by then, and only then can its
    // header be looked at.
    if (!_scheduled) {
      _scheduled = true;
      SchedulerBinding.instance
        ..addPostFrameCallback((Duration _) {
          _scheduled = false;
          if (mounted) {
            _sync();
          }
        }, debugLabel: 'AutomaticPaneBack.sync')
        ..ensureVisualUpdate();
    }
  }

  void _sync() {
    final PaneToolbarHost? host = PaneToolbarHost.maybeOf(context);
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    final bool current = ModalRoute.isCurrentOf(context) ?? true;
    final PaneToolbarItem? navigation =
        host == null || !host.automaticBack || _appDecides()
        ? null
        : automaticNavigation(context);
    if (host == null || navigation == null) {
      _release();
      return;
    }
    final PaneToolbarEntry entry = PaneToolbarEntry(
      owner: this,
      navigation: navigation,
      pinned: const <PaneToolbarItem>[],
      groups: const <List<PaneToolbarItem>>[],
      compression: null,
      duration: kDefaultImmersiveDuration,
    );
    if (_claimed
        case (
          host: final PaneToolbarHost old,
          route: final Route<Object?>? oldRoute,
        )
        when old.registry != host.registry ||
            old.slot != host.slot ||
            oldRoute != route) {
      _release();
    }
    if (current) {
      host.registry.claimAutomatic(host.slot, route, entry);
    } else {
      // Not on top: only a back gesture leading here reads it.
      host.registry.releaseAutomatic(host.slot, null, this);
      if (route != null) {
        host.registry.claimAutomaticRoute(route, entry);
      }
    }
    _claimed = (host: host, route: route);
  }

  void _release() {
    if (_claimed case (
      host: final PaneToolbarHost host,
      route: final Route<Object?>? route,
    )) {
      host.registry.releaseAutomatic(host.slot, route, this);
    }
    _claimed = null;
  }

  /// Whether the screen has a [PaneToolbar] or has decided about its
  /// `AppBar`'s navigation button. The first header met breadth first is the
  /// screen's own; a nested navigator's screens are their own business.
  bool _appDecides() {
    final List<Element> queue = <Element>[];
    context.visitChildElements(queue.add);
    for (int i = 0; i < queue.length; i++) {
      final Widget widget = queue[i].widget;
      switch (widget) {
        case PaneToolbar():
          return true;
        case AppBar(
          :final Widget? leading,
          :final bool automaticallyImplyLeading,
        ):
          return leading != null || !automaticallyImplyLeading;
        case SliverAppBar(
          :final Widget? leading,
          :final bool automaticallyImplyLeading,
        ):
          return leading != null || !automaticallyImplyLeading;
        case Navigator():
          continue;
      }
      queue[i].visitChildElements(queue.add);
    }
    return false;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Fades its child in once, when it is first built.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
