import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:adaptive_nav_ios/adaptive_nav_ios.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One posture's `duo_probe` line, as the probe printed it on the iPhone Duo
/// simulator (Xcode 27.1, iOS 27.1), parsed the way the plugin's map is.
DuoGeometry pose(String name) {
  final String line = File('test/fixtures/$name.txt').readAsLinesSync().first;
  final Map<String, Object?> probe =
      jsonDecode(line.substring('duo_probe '.length)) as Map<String, Object?>;
  return DuoGeometry.fromMap(probe['uikit']! as Map<String, Object?>)!;
}

void main() {
  // What the shell is told in each measured posture.
  final Map<String, SystemGeometry> expected = <String, SystemGeometry>{
    // Trailing, LTR. The camera at 399.7…436.7 stands clear of the right
    // edge; the status area is the one against it.
    '01-outer-portrait': const SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(382, 0, 466, 170),
    ),
    '02-outer-landscape-left': const SystemGeometry(
      verticalBar: ChromePlacement.left,
      statusArea: Rect.fromLTRB(0, 0, 84, 82),
    ),
    // Turned the other way: the status area at the bottom of the column.
    '03-outer-landscape-right': const SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(594, 384, 678, 466),
    ),
    // Horizontal bars: the status area against the top edge. The inactive
    // under-display camera and the inactive fold are left out.
    '04-inner-portrait-flat': const SystemGeometry(
      statusArea: Rect.fromLTRB(535, 0, 669, 82),
    ),
    '05-inner-landscape-flat': const SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(867, 0, 951, 120),
    ),
    // Half open: the fold is active, its frame the same as flat.
    '06-inner-landscape-book': const SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(867, 0, 951, 120),
      folds: <Rect>[Rect.fromLTRB(455.5, 0, 495.5, 669)],
    ),
    // Horizontal, but active: the shell decides what to do with its axis.
    '07-inner-portrait-tent': const SystemGeometry(
      statusArea: Rect.fromLTRB(535, 0, 669, 82),
      folds: <Rect>[Rect.fromLTRB(0, 455.5, 669, 495.5)],
    ),
    // The outer edge of the display, though the status bar is in the other
    // window: a side, and no status area.
    '08-split-left-half': const SystemGeometry(
      verticalBar: ChromePlacement.left,
    ),
    '09-split-right-half': const SystemGeometry(
      verticalBar: ChromePlacement.right,
      statusArea: Rect.fromLTRB(385, 0, 469, 120),
    ),
  };

  group('the measured postures', () {
    for (final MapEntry<String, SystemGeometry> e in expected.entries) {
      test(e.key, () {
        expect(systemGeometryOf(pose(e.key)), e.value);
      });
    }
  });

  group('what is not the status area', () {
    test('a camera clear of the edge, alone', () {
      final DuoGeometry g = pose('01-outer-portrait');
      final DuoGeometry cameraOnly = DuoGeometry(
        isSupported: true,
        size: g.size,
        safeArea: g.safeArea,
        layoutDirection: g.layoutDirection,
        verticalBarEdge: g.verticalBarEdge,
        regions: <ReservedRegion>[
          for (final ReservedRegion r in g.regions)
            if (r.frame.width < 40) r,
        ],
      );
      expect(cameraOnly.activeOcclusions, hasLength(1));
      expect(systemGeometryOf(cameraOnly)!.statusArea, isNull);
    });

    test('an area against the other edge', () {
      final DuoGeometry g = DuoGeometry(
        isSupported: true,
        size: const Size(466, 678),
        safeArea: EdgeInsets.zero,
        layoutDirection: TextDirection.ltr,
        verticalBarEdge: VerticalBarEdge.leading,
        regions: const <ReservedRegion>[
          ReservedRegion(
            kind: ReservedRegionKind.occlusion,
            frame: Rect.fromLTRB(382, 0, 466, 170),
            margins: EdgeInsets.zero,
            isActive: true,
          ),
        ],
      );
      expect(systemGeometryOf(g)!.statusArea, isNull);
    });
  });

  // Not measured: the side follows the layout direction, and the status area
  // follows the side.
  test('right-to-left: a trailing bar and its area on the left', () {
    final DuoGeometry g = DuoGeometry(
      isSupported: true,
      size: const Size(466, 678),
      safeArea: const EdgeInsets.only(left: 84, bottom: 34),
      layoutDirection: TextDirection.rtl,
      verticalBarEdge: VerticalBarEdge.trailing,
      regions: const <ReservedRegion>[
        ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          frame: Rect.fromLTRB(0, 0, 84, 170),
          margins: EdgeInsets.zero,
          isActive: true,
        ),
      ],
    );
    expect(
      systemGeometryOf(g),
      const SystemGeometry(
        verticalBar: ChromePlacement.left,
        statusArea: Rect.fromLTRB(0, 0, 84, 170),
      ),
    );
  });

  test('nothing to say: no window, or below iOS 27.1', () {
    expect(systemGeometryOf(null), isNull);
    expect(
      systemGeometryOf(
        const DuoGeometry(
          isSupported: false,
          size: Size(466, 678),
          safeArea: EdgeInsets.only(right: 84),
          layoutDirection: TextDirection.ltr,
        ),
      ),
      isNull,
    );
  });

  testWidgets('the provider hands the shell its geometry', (
    WidgetTester tester,
  ) async {
    final StreamController<DuoGeometry?> source =
        StreamController<DuoGeometry?>(sync: true);
    SystemGeometry? seen;
    DuoGeometry? raw;
    await tester.pumpWidget(
      DuoGeometryProvider(
        source: source.stream,
        child: Builder(
          builder: (BuildContext context) {
            seen = SystemGeometryScope.maybeOf(context);
            raw = DuoGeometryScope.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen, isNull);

    source.add(pose('06-inner-landscape-book'));
    await tester.pump();
    expect(raw, pose('06-inner-landscape-book'));
    expect(seen, expected['06-inner-landscape-book']);

    source.add(null);
    await tester.pump();
    expect(seen, isNull);
    unawaited(source.close());
  });
}
