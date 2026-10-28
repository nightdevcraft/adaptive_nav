import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

import 'resize.dart';

/// One iPhone Duo posture with a system column, as measured on the simulator
/// (iOS 27.1); the numbers are those of
/// `duo_poses_test.dart`.
typedef DuoPose = ({
  int number,
  Size window,
  EdgeInsets padding,
  Size display,
  SystemGeometry system,
});

const List<DuoPose> kDuoColumnPoses = <DuoPose>[
  (
    number: 1,
    window: kDuoOuterPortrait,
    padding: kDuoOuterPortraitPadding,
    display: kDuoOuterPortrait,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(382, 0, 466, 170),
    ),
  ),
  (
    number: 2,
    window: kDuoOuterLandscape,
    padding: kDuoOuterLandscapePadding,
    display: kDuoOuterLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.left,
      statusArea: Rect.fromLTRB(0, 0, 84, 82),
    ),
  ),
  (
    number: 3,
    window: kDuoOuterLandscape,
    padding: kDuoOuterLandscapeRightPadding,
    display: kDuoOuterLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(594, 384, 678, 466),
    ),
  ),
  (
    number: 5,
    window: kDuoInnerLandscape,
    padding: kDuoInnerLandscapePadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(867, 0, 951, 120),
    ),
  ),
  (
    number: 6,
    window: kDuoInnerLandscape,
    padding: kDuoInnerLandscapePadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(867, 0, 951, 120),
      folds: <Rect>[Rect.fromLTRB(455.5, 0, 495.5, 669)],
    ),
  ),
  (
    number: 9,
    window: kDuoSplit,
    padding: kDuoSplitRightPadding,
    display: kDuoInnerLandscape,
    system: SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(385, 0, 469, 120),
    ),
  ),
];

/// The posture numbered [number] in the README's iPhone Duo table.
DuoPose duoPose(int number) =>
    kDuoColumnPoses.firstWhere((DuoPose p) => p.number == number);

/// Where the system column's first button starts and its last place ends,
/// [SystemBarMetrics.columnInset] from the status area or the window's edge.
({double top, double end}) duoColumn(DuoPose pose) {
  final Rect area = pose.system.statusArea!;
  final bool top = area.top == 0;
  return (
    top: (top ? area.bottom : 0) + 24,
    end: (top ? pose.window.height : area.top) - 24,
  );
}
