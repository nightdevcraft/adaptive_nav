import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets the logical window size for a test (dpr = 1, so logical == physical).
void setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

const Size kCompact = Size(500, 900);
const Size kWide = Size(1200, 900);
