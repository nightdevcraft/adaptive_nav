/// iPhone Duo geometry read from UIKit, for adaptive_nav.
///
/// Put a [DuoGeometryProvider] above the app. The adaptive_nav shell takes
/// the side of the system's bar, its status area and the fold from it, and an
/// app can read the rest from [DuoGeometryScope.maybeOf]. Everywhere but iOS
/// it provides nothing, and the shell falls back to what `MediaQuery` says.
library;

export 'src/geometry.dart';
export 'src/geometry_probe.dart';
export 'src/geometry_provider.dart';
export 'src/system_geometry.dart';
