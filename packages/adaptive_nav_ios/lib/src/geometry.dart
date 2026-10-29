import 'dart:ui' show Rect, Size, TextDirection;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

/// `UITraitCollection.verticalBarEdge`: whether the system lays this window's
/// bars out vertically, and along which edge.
///
/// Leading and trailing are UIKit's words. Which physical side that is
/// depends on [DuoGeometry.layoutDirection]; [DuoGeometry.verticalBarSide]
/// does the conversion.
enum VerticalBarEdge {
  /// Bars are horizontal: no vertical bar in this window.
  none,

  /// Along the leading edge: the left one left to right.
  leading,

  /// Along the trailing edge: the right one left to right.
  trailing,

  /// A raw value this version does not know. [DuoGeometry.verticalBarEdgeRaw]
  /// has it.
  unknown,
}

/// A physical side of the window.
enum VerticalBarSide {
  /// The left edge.
  left,

  /// The right edge.
  right,
}

/// `UIHingeInteraction`'s status.
enum HingeStatus {
  /// Folded shut.
  closed,

  /// Half open: the fold is active.
  partiallyOpen,

  /// Flat.
  fullyOpen,

  /// A raw value this version does not know. [DuoGeometry.hingeStatusRaw]
  /// has it.
  unknown,
}

/// `UIView.ReservedRegion.Kind`.
enum ReservedRegionKind {
  /// Divides the area in two: the fold.
  division,

  /// Covers part of the area: a front camera, or the system's status area.
  occlusion,
}

/// One `UIView.ReservedRegion`, in Flutter logical pixels relative to the
/// Flutter view — the coordinates `MediaQuery` and a global `Offset` use.
@immutable
class ReservedRegion {
  /// A region as UIKit reports it; [DuoGeometry.fromMap] builds these.
  const ReservedRegion({
    required this.kind,
    required this.frame,
    required this.margins,
    required this.isActive,
  });

  /// A fold or an occlusion.
  final ReservedRegionKind kind;

  /// Where the region is, in Flutter logical pixels relative to the view.
  final Rect frame;

  /// Space UIKit asks to keep clear around [frame].
  final EdgeInsets margins;

  /// A fold is active only while the device is partly open. Flat it is
  /// still reported, inactive and with the same frame: 40 points across,
  /// which is a line down the middle and [margins] of 20 on either side.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is ReservedRegion &&
      other.kind == kind &&
      other.frame == frame &&
      other.margins == margins &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(kind, frame, margins, isActive);

  @override
  String toString() =>
      'ReservedRegion(${kind.name}, $frame, active: $isActive)';
}

/// What UIKit says about the Flutter view's window.
@immutable
class DuoGeometry {
  /// Geometry with the given values. The plugin's comes from [fromMap]; this
  /// is for tests and for previewing a posture through
  /// `DuoGeometryProvider.source`.
  const DuoGeometry({
    required this.isSupported,
    required this.size,
    required this.safeArea,
    required this.layoutDirection,
    this.cornerSafeArea,
    this.verticalBarEdge = VerticalBarEdge.none,
    this.verticalBarEdgeRaw,
    this.regions = const <ReservedRegion>[],
    this.hingeStatus,
    this.hingeStatusRaw,
    this.hingeAngle,
    this.screenSize,
    this.frameInScreen,
    this.horizontalSizeClass,
    this.verticalSizeClass,
    this.raw = const <String, Object?>{},
  });

  /// Parses the map the plugin sends. `null` for a view that is not in a
  /// window yet.
  static DuoGeometry? fromMap(Map<Object?, Object?> map) {
    if (map['attached'] != true) {
      return null;
    }
    final int? edgeRaw = _int(map['verticalBarEdge']);
    final int? hingeRaw = _int(map['hingeStatus']);
    return DuoGeometry(
      isSupported: map['supported'] == true,
      size: _size(map['size']) ?? Size.zero,
      safeArea: _insets(map['safeArea']) ?? EdgeInsets.zero,
      cornerSafeArea: _insets(map['cornerSafeArea']),
      layoutDirection: map['layoutDirection'] == 'rtl'
          ? TextDirection.rtl
          : TextDirection.ltr,
      verticalBarEdge: _edge(edgeRaw),
      verticalBarEdgeRaw: edgeRaw,
      regions: <ReservedRegion>[
        for (final Object? r in (map['regions'] as List<Object?>?) ?? const [])
          if (_region(r) case final ReservedRegion region) region,
      ],
      hingeStatus: hingeRaw == null ? null : _hinge(hingeRaw),
      hingeStatusRaw: hingeRaw,
      hingeAngle: (map['hingeAngle'] as num?)?.toDouble(),
      screenSize: _size(map['screenSize']),
      frameInScreen: _rect(map['frameInScreen']),
      horizontalSizeClass: map['horizontalSizeClass'] as String?,
      verticalSizeClass: map['verticalSizeClass'] as String?,
      raw: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry<Object?, Object?> e in map.entries)
          '${e.key}': e.value,
      }),
    );
  }

  /// The view is on iOS 27.1 or later, where the fields below the safe area
  /// mean something. `false` below that: no vertical bar, no regions.
  final bool isSupported;

  /// The Flutter view's size, in logical pixels.
  final Size size;

  /// `UIView.safeAreaInsets`.
  final EdgeInsets safeArea;

  /// The safe area with the corners adapted horizontally (iOS 26): the side
  /// insets widen where the display's corners curve.
  final EdgeInsets? cornerSafeArea;

  /// The window's layout direction, which [verticalBarEdge] is relative to.
  final TextDirection layoutDirection;

  /// `UITraitCollection.verticalBarEdge`: [VerticalBarEdge.none] where the
  /// bars are horizontal. [verticalBarSide] has it as a physical side.
  final VerticalBarEdge verticalBarEdge;

  /// The trait's raw value, kept so a mapping this version gets wrong shows.
  final int? verticalBarEdgeRaw;

  /// Every reserved region, active or not.
  final List<ReservedRegion> regions;

  /// `null` until the hinge interaction has reported, and where there is no
  /// hinge.
  final HingeStatus? hingeStatus;

  /// The status's raw value, kept so a mapping this version gets wrong
  /// shows.
  final int? hingeStatusRaw;

  /// The hinge angle as UIKit reports it.
  final double? hingeAngle;

  /// The size of the screen the window is on.
  final Size? screenSize;

  /// Where the view sits on the screen. Under Split View the window is part
  /// of the screen, and this says which part.
  final Rect? frameInScreen;

  /// `UITraitCollection.horizontalSizeClass`: `compact`, `regular` or
  /// `unspecified`.
  final String? horizontalSizeClass;

  /// `UITraitCollection.verticalSizeClass`: `compact`, `regular` or
  /// `unspecified`.
  final String? verticalSizeClass;

  /// The map as the plugin sent it, for logging.
  final Map<String, Object?> raw;

  /// [verticalBarEdge] as a physical side, or `null` with no vertical bar.
  VerticalBarSide? get verticalBarSide {
    final bool rtl = layoutDirection == TextDirection.rtl;
    return switch (verticalBarEdge) {
      VerticalBarEdge.leading =>
        rtl ? VerticalBarSide.right : VerticalBarSide.left,
      VerticalBarEdge.trailing =>
        rtl ? VerticalBarSide.left : VerticalBarSide.right,
      VerticalBarEdge.none || VerticalBarEdge.unknown => null,
    };
  }

  /// The active folds.
  Iterable<ReservedRegion> get activeDivisions => regions.where(
    (ReservedRegion r) => r.isActive && r.kind == ReservedRegionKind.division,
  );

  /// The active cameras.
  Iterable<ReservedRegion> get activeOcclusions => regions.where(
    (ReservedRegion r) => r.isActive && r.kind == ReservedRegionKind.occlusion,
  );

  @override
  bool operator ==(Object other) =>
      other is DuoGeometry &&
      other.isSupported == isSupported &&
      other.size == size &&
      other.safeArea == safeArea &&
      other.cornerSafeArea == cornerSafeArea &&
      other.layoutDirection == layoutDirection &&
      other.verticalBarEdge == verticalBarEdge &&
      other.verticalBarEdgeRaw == verticalBarEdgeRaw &&
      listEquals(other.regions, regions) &&
      other.hingeStatus == hingeStatus &&
      other.hingeAngle == hingeAngle &&
      other.screenSize == screenSize &&
      other.frameInScreen == frameInScreen &&
      other.horizontalSizeClass == horizontalSizeClass &&
      other.verticalSizeClass == verticalSizeClass;

  @override
  int get hashCode => Object.hash(
    isSupported,
    size,
    safeArea,
    cornerSafeArea,
    layoutDirection,
    verticalBarEdge,
    Object.hashAll(regions),
    hingeStatus,
    hingeAngle,
    screenSize,
    frameInScreen,
    horizontalSizeClass,
    verticalSizeClass,
  );

  @override
  String toString() =>
      'DuoGeometry(size: $size, safeArea: $safeArea, bar: '
      '${verticalBarEdge.name} ($verticalBarEdgeRaw), regions: $regions, '
      'hinge: ${hingeStatus?.name} $hingeAngle)';
}

// The raw values below are what UIKit's enums were seen to carry on the iOS
// 27.1 simulator. They are the one guess in this file; the probe prints the
// raw value next to the name so a wrong one shows up.

VerticalBarEdge _edge(int? raw) => switch (raw) {
  null || 0 => VerticalBarEdge.none,
  1 => VerticalBarEdge.leading,
  2 => VerticalBarEdge.trailing,
  _ => VerticalBarEdge.unknown,
};

HingeStatus _hinge(int raw) => switch (raw) {
  1 => HingeStatus.closed,
  2 => HingeStatus.partiallyOpen,
  3 => HingeStatus.fullyOpen,
  _ => HingeStatus.unknown,
};

int? _int(Object? value) => (value as num?)?.toInt();

double _d(Map<Object?, Object?> m, String key) =>
    (m[key] as num?)?.toDouble() ?? 0;

Size? _size(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  return Size(_d(value, 'width'), _d(value, 'height'));
}

Rect? _rect(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  return Rect.fromLTRB(
    _d(value, 'left'),
    _d(value, 'top'),
    _d(value, 'right'),
    _d(value, 'bottom'),
  );
}

EdgeInsets? _insets(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  return EdgeInsets.fromLTRB(
    _d(value, 'left'),
    _d(value, 'top'),
    _d(value, 'right'),
    _d(value, 'bottom'),
  );
}

ReservedRegion? _region(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  final Rect? frame = _rect(value['frame']);
  if (frame == null) {
    return null;
  }
  return ReservedRegion(
    kind: value['kind'] == 'division'
        ? ReservedRegionKind.division
        : ReservedRegionKind.occlusion,
    frame: frame,
    margins: _insets(value['margins']) ?? EdgeInsets.zero,
    isActive: value['active'] == true,
  );
}
