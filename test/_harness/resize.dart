import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets the logical window size for a test (dpr = 1, so logical == physical).
void setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

const Size kCompact = Size(500, 900);
const Size kWide = Size(1200, 900);

/// Sets the window size together with the safe-area insets, which on a
/// foldable are neither zero nor symmetric.
void setPose(
  WidgetTester tester,
  Size size, {
  EdgeInsets padding = EdgeInsets.zero,
}) {
  setWindow(tester, size);
  final FakeViewPadding inset = FakeViewPadding(
    left: padding.left,
    top: padding.top,
    right: padding.right,
    bottom: padding.bottom,
  );
  tester.view.padding = inset;
  tester.view.viewPadding = inset;
}

/// iPhone Duo, measured on the simulator (Xcode 27.1 / iOS 27.1) rather than
/// taken from a spec sheet: the inner display is 2007x2853 physical pixels at
/// dpr 3, the outer one 1398x2034.
///
/// The status bar is a vertical strip on one side, which is where the 84 comes
/// from — and which side it is on changes with the posture.
const Size kDuoOuterPortrait = Size(466, 678);
const EdgeInsets kDuoOuterPortraitPadding = EdgeInsets.only(
  right: 84,
  bottom: 34,
);

const Size kDuoOuterLandscape = Size(678, 466);
const EdgeInsets kDuoOuterLandscapePadding = EdgeInsets.only(
  left: 84,
  bottom: 34,
);

/// Turned the other way: the column is on the right and the camera at its
/// bottom.
const EdgeInsets kDuoOuterLandscapeRightPadding = EdgeInsets.only(
  right: 84,
  bottom: 34,
);

const Size kDuoInnerPortrait = Size(669, 951);
const EdgeInsets kDuoInnerPortraitPadding = EdgeInsets.only(
  top: 82,
  bottom: 34,
);

const Size kDuoInnerLandscape = Size(951, 669);
const EdgeInsets kDuoInnerLandscapePadding = EdgeInsets.only(
  right: 84,
  bottom: 34,
);
