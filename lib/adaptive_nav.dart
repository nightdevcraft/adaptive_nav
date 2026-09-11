/// A Navigator 2.0 router that keeps screen state across window resizes.
///
/// One navigation state ([NavState]) lives in a long-lived
/// [AdaptiveRouterDelegate] and is rendered two ways: `compact` is a single
/// `Navigator` stack, `wide` is master-detail panes. A resize changes the
/// layout and nothing else — the screens move under stable navigator keys, so
/// scroll offsets, text fields and controllers survive a rotation.
///
/// The package is generic over the route type `R` and knows nothing about the
/// app's screens. Branches ([BranchConfig]), the `R ↔ URL` codec
/// ([RouteCodec]) and exit guards all come from the app.
///
/// See `doc/design.md` for why it is built this way.
library;

export 'src/adaptive_route_information_parser.dart';
export 'src/adaptive_router_delegate.dart';
// App screens read these too, not just pages this package builds.
export 'src/entry_page.dart' show DetailEntryScope, DetailPaneScope;
export 'src/nav_config.dart';
export 'src/nav_state.dart';
export 'src/pane_split.dart';
