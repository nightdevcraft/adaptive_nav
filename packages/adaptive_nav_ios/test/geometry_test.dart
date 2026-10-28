import 'dart:async';
import 'dart:convert';

import 'package:adaptive_nav_ios/adaptive_nav_ios.dart';
import 'package:flutter/foundation.dart' show DebugPrintCallback;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The outer display upright, as the plugin sends it.
Map<Object?, Object?> outerPortrait({String direction = 'ltr', int edge = 2}) =>
    <Object?, Object?>{
      'attached': true,
      'supported': true,
      'size': <Object?, Object?>{'width': 466.0, 'height': 678.0},
      'safeArea': <Object?, Object?>{
        'left': 0.0,
        'top': 0.0,
        'right': 84.0,
        'bottom': 20.0,
      },
      'layoutDirection': direction,
      'verticalBarEdge': edge,
      'hingeStatus': 1,
      'hingeAngle': 0.0,
      'regions': <Object?>[
        <Object?, Object?>{
          'kind': 'occlusion',
          'active': true,
          'frame': <Object?, Object?>{
            'left': 410.0,
            'top': 12.0,
            'right': 447.0,
            'bottom': 49.0,
          },
          'margins': <Object?, Object?>{
            'left': 0.0,
            'top': 0.0,
            'right': 0.0,
            'bottom': 0.0,
          },
        },
      ],
    };

void main() {
  test('a view outside a window parses to null', () {
    expect(DuoGeometry.fromMap(<Object?, Object?>{'attached': false}), isNull);
  });

  test('parses the outer display', () {
    final DuoGeometry g = DuoGeometry.fromMap(outerPortrait())!;
    expect(g.isSupported, isTrue);
    expect(g.size, const Size(466, 678));
    expect(g.safeArea, const EdgeInsets.only(right: 84, bottom: 20));
    expect(g.verticalBarEdge, VerticalBarEdge.trailing);
    expect(g.verticalBarSide, VerticalBarSide.right);
    expect(g.hingeStatus, HingeStatus.closed);
    expect(
      g.activeOcclusions.single.frame,
      const Rect.fromLTRB(410, 12, 447, 49),
    );
    expect(g.activeDivisions, isEmpty);
  });

  test('a trailing bar in a right-to-left window is on the left', () {
    final DuoGeometry g = DuoGeometry.fromMap(outerPortrait(direction: 'rtl'))!;
    expect(g.verticalBarSide, VerticalBarSide.left);
  });

  test('an unknown raw edge is kept, not guessed', () {
    final DuoGeometry g = DuoGeometry.fromMap(outerPortrait(edge: 7))!;
    expect(g.verticalBarEdge, VerticalBarEdge.unknown);
    expect(g.verticalBarEdgeRaw, 7);
    expect(g.verticalBarSide, isNull);
  });

  test('below iOS 27.1 there is no bar and no region', () {
    final DuoGeometry g = DuoGeometry.fromMap(<Object?, Object?>{
      'attached': true,
      'supported': false,
      'size': <Object?, Object?>{'width': 402.0, 'height': 874.0},
      'safeArea': <Object?, Object?>{
        'left': 0.0,
        'top': 62.0,
        'right': 0.0,
        'bottom': 34.0,
      },
      'layoutDirection': 'ltr',
    })!;
    expect(g.isSupported, isFalse);
    expect(g.verticalBarEdge, VerticalBarEdge.none);
    expect(g.regions, isEmpty);
    expect(g.hingeStatus, isNull);
  });

  testWidgets('the provider passes on what the source sends', (
    WidgetTester tester,
  ) async {
    // Synchronous, so an event is in the state before the pump that should
    // build it, not delivered in a microtask after that frame.
    final StreamController<DuoGeometry?> source =
        StreamController<DuoGeometry?>(sync: true);
    DuoGeometry? seen;
    await tester.pumpWidget(
      DuoGeometryProvider(
        source: source.stream,
        child: Builder(
          builder: (BuildContext context) {
            seen = DuoGeometryScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, isNull);

    source.add(DuoGeometry.fromMap(outerPortrait()));
    await tester.pump();
    expect(seen?.verticalBarSide, VerticalBarSide.right);

    source.addError(StateError('no plugin'));
    await tester.pump();
    expect(seen, isNull);
    // Not awaited: its future completes in a microtask the fake clock does
    // not run here.
    unawaited(source.close());
  });

  testWidgets('away from iOS the provider listens to nothing', (
    WidgetTester tester,
  ) async {
    DuoGeometry? seen;
    await tester.pumpWidget(
      DuoGeometryProvider(
        child: Builder(
          builder: (BuildContext context) {
            seen = DuoGeometryScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    expect(seen, isNull);
  });

  testWidgets('the probe draws over the app and snapshots both sides', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      DuoGeometryScope(
        geometry: DuoGeometry.fromMap(outerPortrait()),
        child: const DuoGeometryProbe(log: false, child: SizedBox()),
      ),
    );
    expect(find.text('probe'), findsOneWidget);
    await tester.tap(find.text('probe'));
    await tester.pump();
    expect(find.textContaining('bar trailing (raw 2) → right'), findsOneWidget);

    final Map<String, Object?> snap = duoProbeSnapshot(
      DuoGeometry.fromMap(outerPortrait()),
      const MediaQueryData(size: Size(466, 678)),
    );
    expect((snap['uikit']! as Map<String, Object?>)['verticalBarEdge'], 2);
    expect(snap['flutter'], isA<Map<String, Object?>>());
  });

  testWidgets('a long probe line is split so the iOS console keeps it all', (
    WidgetTester tester,
  ) async {
    final List<String> lines = <String>[];
    final DebugPrintCallback saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message!);
    try {
      await tester.pumpWidget(
        DuoGeometryScope(
          geometry: DuoGeometry.fromMap(outerPortrait()),
          child: const DuoGeometryProbe(child: SizedBox()),
        ),
      );
    } finally {
      debugPrint = saved;
    }
    expect(lines.first, startsWith('duo_probe {'));
    expect(lines.skip(1), everyElement(startsWith('duo_probe+ ')));
    expect(
      lines.every((String l) => l.length <= 'duo_probe+ '.length + 900),
      isTrue,
    );
    final String joined = lines
        .map((String l) => l.substring(l.indexOf(' ') + 1))
        .join();
    expect(jsonDecode(joined), isA<Map<String, Object?>>());
  });
}
