import 'package:adaptive_nav_ios/adaptive_nav_ios.dart';
import 'package:flutter/widgets.dart';

import 'main.dart';

/// The example with the geometry probe over it: `flutter run -t
/// lib/duo_probe.dart`.
///
/// Every posture change prints one `duo_probe` line to the console with
/// UIKit's values next to Flutter's `MediaQuery`, and the panel behind the
/// "probe" button copies the same JSON.
void main() => runApp(
  const DuoGeometryProvider(child: DuoGeometryProbe(child: ExampleApp())),
);
